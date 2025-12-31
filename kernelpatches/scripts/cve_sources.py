"""
CVE source fetching from NVD, GHSA, Atom feeds, and upstream commits.
"""

import asyncio
import gzip
import json
import re
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple
from urllib.parse import urljoin

import aiohttp
import requests

from scripts.common import (
    extract_commit_sha,
    extract_cve_ids,
    get_github_token,
    logger,
    version_less_than,
)
from scripts.config import DEFAULT_CONFIG, KernelConfig
from scripts.models import CVE, CVEReference, CVESource, KernelVersion, Severity


class CVEFetcher:
    """Base class for CVE fetching from various sources."""
    
    def __init__(self, config: Optional[KernelConfig] = None):
        self.config = config or DEFAULT_CONFIG
        self.session: Optional[aiohttp.ClientSession] = None
    
    async def __aenter__(self):
        self.session = aiohttp.ClientSession()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()
    
    def fetch(
        self,
        kernel_version: str,
        output_dir: Path,
        current_version: Optional[str] = None,
    ) -> List[CVE]:
        """Synchronous wrapper for fetch_async."""
        return asyncio.run(self.fetch_async(kernel_version, output_dir, current_version))
    
    async def fetch_async(
        self,
        kernel_version: str,
        output_dir: Path,
        current_version: Optional[str] = None,
    ) -> List[CVE]:
        """Fetch CVEs - to be implemented by subclasses."""
        raise NotImplementedError


class NVDFetcher(CVEFetcher):
    """Fetch CVEs from NIST National Vulnerability Database."""
    
    def __init__(self, config: Optional[KernelConfig] = None):
        super().__init__(config)
        self.yearly_marker_file = self.config.cache_dir / ".nvd_yearly_last_run"
    
    def _should_run_yearly_feeds(self) -> bool:
        """Check if yearly feeds should be processed (once per 24h)."""
        if not self.yearly_marker_file.exists():
            return True
        
        try:
            last_run = float(self.yearly_marker_file.read_text().strip())
            age = time.time() - last_run
            if age >= 86400:  # 24 hours
                return True
            hours_since = int(age / 3600)
            logger.debug(f"Yearly feeds last run {hours_since}h ago")
            return False
        except Exception:
            return True
    
    def _update_yearly_marker(self) -> None:
        """Update the yearly feed timestamp marker."""
        self.yearly_marker_file.parent.mkdir(parents=True, exist_ok=True)
        self.yearly_marker_file.write_text(str(time.time()))
    
    def _parse_nvd_json(self, nvd_data: Dict[str, Any]) -> List[CVE]:
        """Parse NVD JSON response into CVE objects."""
        cves = []
        kernel_cna = self.config.kernel_org_cna
        
        vulnerabilities = nvd_data.get("vulnerabilities", [])
        
        for vuln in vulnerabilities:
            cve_data = vuln.get("cve", {})
            
            # Filter by kernel.org CNA
            source_id = cve_data.get("sourceIdentifier", "")
            if source_id != kernel_cna:
                continue
            
            cve_id = cve_data.get("id", "")
            if not cve_id.startswith("CVE-"):
                continue
            
            # Extract CVSS score
            cvss_score = 0.0
            severity = Severity.UNKNOWN
            
            metrics = cve_data.get("metrics", {})
            for metric_key in ["cvssMetricV31", "cvssMetricV30", "cvssMetricV2"]:
                metric_list = metrics.get(metric_key, [])
                if metric_list:
                    cvss_data = metric_list[0].get("cvssData", {})
                    cvss_score = cvss_data.get("baseScore", 0.0)
                    sev_str = cvss_data.get("baseSeverity", "UNKNOWN")
                    try:
                        severity = Severity(sev_str.upper())
                    except ValueError:
                        severity = Severity.from_cvss(cvss_score)
                    break
            
            # Extract description
            descriptions = cve_data.get("descriptions", [])
            description = ""
            for desc in descriptions:
                if desc.get("lang") == "en":
                    description = desc.get("value", "")
                    break
            
            # Extract references and commits
            references = []
            fix_commits = []
            
            for ref in cve_data.get("references", []):
                url = ref.get("url", "")
                ref_obj = CVEReference(
                    url=url,
                    source=ref.get("source"),
                    tags=ref.get("tags", []),
                )
                references.append(ref_obj)
                
                # Extract commit SHA from URL
                commit = extract_commit_sha(url)
                if commit:
                    fix_commits.append(commit)
            
            # Extract dates
            published = cve_data.get("published")
            modified = cve_data.get("lastModified")
            
            cve = CVE(
                cve_id=cve_id,
                cvss_score=cvss_score,
                severity=severity,
                description=description,
                published_date=datetime.fromisoformat(published.replace("Z", "+00:00")) if published else None,
                modified_date=datetime.fromisoformat(modified.replace("Z", "+00:00")) if modified else None,
                source=CVESource.NVD,
                references=references,
                fix_commits=list(set(fix_commits)),
            )
            cves.append(cve)
        
        return cves
    
    async def _fetch_feed(
        self,
        session: aiohttp.ClientSession,
        feed_url: str,
        output_dir: Path,
        feed_name: str,
    ) -> List[CVE]:
        """Fetch and parse a single NVD feed."""
        logger.debug(f"Fetching {feed_name} feed from {feed_url}")
        
        try:
            async with session.get(feed_url, timeout=aiohttp.ClientTimeout(total=180)) as response:
                if response.status != 200:
                    logger.warning(f"Failed to fetch {feed_name} feed: HTTP {response.status}")
                    return []
                
                gz_data = await response.read()
        except Exception as e:
            logger.warning(f"Failed to fetch {feed_name} feed: {e}")
            return []
        
        # Decompress
        try:
            json_data = gzip.decompress(gz_data)
            nvd_data = json.loads(json_data)
        except Exception as e:
            logger.warning(f"Failed to decompress {feed_name} feed: {e}")
            return []
        
        return self._parse_nvd_json(nvd_data)
    
    async def fetch_async(
        self,
        kernel_version: str,
        output_dir: Path,
        current_version: Optional[str] = None,
    ) -> List[CVE]:
        """Fetch CVEs from NVD feeds."""
        logger.info("Source: NIST National Vulnerability Database (NVD)")
        logger.info(f"Filter: kernel.org CNA ({self.config.kernel_org_cna})")
        logger.info(f"Target kernel: {kernel_version}")
        
        all_cves: Dict[str, CVE] = {}
        output_dir.mkdir(parents=True, exist_ok=True)
        
        async with aiohttp.ClientSession() as session:
            # Always fetch recent feed
            recent_url = f"{self.config.nvd_feed_base}/nvdcve-2.0-recent.json.gz"
            recent_cves = await self._fetch_feed(session, recent_url, output_dir, "recent")
            for cve in recent_cves:
                all_cves[cve.cve_id] = cve
            
            # Fetch yearly feeds once per 24 hours
            if self._should_run_yearly_feeds():
                current_year = datetime.now().year
                start_year = 2023
                
                logger.info(f"Processing yearly feeds from {start_year} to {current_year}")
                
                for year in range(start_year, current_year + 1):
                    yearly_url = f"{self.config.nvd_feed_base}/nvdcve-2.0-{year}.json.gz"
                    yearly_cves = await self._fetch_feed(session, yearly_url, output_dir, str(year))
                    for cve in yearly_cves:
                        all_cves[cve.cve_id] = cve
                
                self._update_yearly_marker()
                logger.info("Yearly feeds processing complete")
        
        cves = list(all_cves.values())
        logger.info(f"Found {len(cves)} kernel.org CVE entries from NVD")
        
        return cves


class GHSAFetcher(CVEFetcher):
    """Fetch CVEs from GitHub Advisory Database."""
    
    GRAPHQL_QUERY = """
    query($cursor: String) {
        securityAdvisories(first: 100, orderBy: {field: PUBLISHED_AT, direction: DESC}, after: $cursor) {
            pageInfo {
                hasNextPage
                endCursor
            }
            nodes {
                ghsaId
                summary
                severity
                publishedAt
                updatedAt
                identifiers {
                    type
                    value
                }
                references {
                    url
                }
                cwes(first: 5) {
                    nodes {
                        cweId
                        name
                    }
                }
            }
        }
    }
    """
    
    SEVERITY_MAP = {
        "CRITICAL": Severity.CRITICAL,
        "HIGH": Severity.HIGH,
        "MODERATE": Severity.MEDIUM,
        "MEDIUM": Severity.MEDIUM,
        "LOW": Severity.LOW,
    }
    
    def _is_kernel_related(self, advisory: Dict[str, Any]) -> bool:
        """Check if advisory is related to Linux kernel."""
        summary = advisory.get("summary", "").lower()
        
        kernel_keywords = [
            "linux kernel", "kernel", "smb", "cifs",
            "net/", "fs/", "drivers/", "mm/", "arch/",
        ]
        
        if any(kw in summary for kw in kernel_keywords):
            return True
        
        # Check references
        for ref in advisory.get("references", []):
            url = ref.get("url", "")
            if "git.kernel.org" in url or "torvalds/linux" in url:
                return True
        
        return False
    
    def _parse_advisory(self, advisory: Dict[str, Any]) -> Optional[CVE]:
        """Parse a GHSA advisory into a CVE object."""
        # Get CVE ID
        cve_id = None
        ghsa_id = advisory.get("ghsaId")
        
        for identifier in advisory.get("identifiers", []):
            if identifier.get("type") == "CVE":
                cve_id = identifier.get("value")
                break
        
        if not cve_id:
            return None
        
        # Get severity
        severity_str = advisory.get("severity", "UNKNOWN")
        severity = self.SEVERITY_MAP.get(severity_str.upper(), Severity.UNKNOWN)
        
        # Estimate CVSS from severity
        cvss_map = {
            Severity.CRITICAL: 9.5,
            Severity.HIGH: 7.5,
            Severity.MEDIUM: 5.5,
            Severity.LOW: 2.5,
            Severity.UNKNOWN: 0.0,
        }
        cvss_score = cvss_map.get(severity, 0.0)
        
        # Extract references and commits
        references = []
        fix_commits = []
        
        for ref in advisory.get("references", []):
            url = ref.get("url", "")
            ref_obj = CVEReference(url=url, source="GHSA")
            references.append(ref_obj)
            
            commit = extract_commit_sha(url)
            if commit:
                fix_commits.append(commit)
        
        # Extract CWEs
        cwes = []
        for cwe_node in advisory.get("cwes", {}).get("nodes", []):
            cwe_id = cwe_node.get("cweId")
            if cwe_id:
                cwes.append(cwe_id)
        
        # Parse dates
        published = advisory.get("publishedAt")
        modified = advisory.get("updatedAt")
        
        return CVE(
            cve_id=cve_id,
            cvss_score=cvss_score,
            severity=severity,
            description=advisory.get("summary", ""),
            published_date=datetime.fromisoformat(published.replace("Z", "+00:00")) if published else None,
            modified_date=datetime.fromisoformat(modified.replace("Z", "+00:00")) if modified else None,
            source=CVESource.GHSA,
            references=references,
            fix_commits=list(set(fix_commits)),
            ghsa_id=ghsa_id,
            cwes=cwes,
        )
    
    async def fetch_async(
        self,
        kernel_version: str,
        output_dir: Path,
        current_version: Optional[str] = None,
    ) -> List[CVE]:
        """Fetch CVEs from GitHub Advisory Database."""
        logger.info("Source: GitHub Advisory Database (GHSA)")
        logger.info(f"Target kernel: {kernel_version}")
        
        token = get_github_token()
        if not token:
            logger.error("GitHub authentication required. Set GITHUB_TOKEN or run 'gh auth login'")
            return []
        
        headers = {
            "Authorization": f"bearer {token}",
            "Content-Type": "application/json",
        }
        
        all_cves: Dict[str, CVE] = {}
        cursor = None
        page = 0
        max_pages = 5
        
        async with aiohttp.ClientSession(headers=headers) as session:
            while page < max_pages:
                page += 1
                logger.debug(f"Fetching GHSA page {page}")
                
                variables = {"cursor": cursor} if cursor else {}
                payload = {
                    "query": self.GRAPHQL_QUERY,
                    "variables": variables,
                }
                
                try:
                    async with session.post(
                        self.config.github_graphql_url,
                        json=payload,
                        timeout=aiohttp.ClientTimeout(total=60),
                    ) as response:
                        if response.status != 200:
                            logger.warning(f"GHSA API error: HTTP {response.status}")
                            break
                        
                        data = await response.json()
                except Exception as e:
                    logger.warning(f"GHSA API request failed: {e}")
                    break
                
                # Check for errors
                if "errors" in data:
                    logger.warning(f"GHSA API error: {data['errors']}")
                    break
                
                advisories = data.get("data", {}).get("securityAdvisories", {})
                nodes = advisories.get("nodes", [])
                
                for advisory in nodes:
                    if not self._is_kernel_related(advisory):
                        continue
                    
                    cve = self._parse_advisory(advisory)
                    if cve and cve.fix_commits:
                        all_cves[cve.cve_id] = cve
                
                # Check pagination
                page_info = advisories.get("pageInfo", {})
                if not page_info.get("hasNextPage"):
                    break
                cursor = page_info.get("endCursor")
                
                await asyncio.sleep(1)  # Rate limiting
        
        cves = list(all_cves.values())
        logger.info(f"Found {len(cves)} kernel CVEs from GHSA")
        
        return cves


class AtomFetcher(CVEFetcher):
    """Fetch CVEs from linux-cve-announce Atom feed."""
    
    async def fetch_async(
        self,
        kernel_version: str,
        output_dir: Path,
        current_version: Optional[str] = None,
    ) -> List[CVE]:
        """Fetch CVEs from Atom feed."""
        logger.info("Source: linux-cve-announce mailing list (kernel.org)")
        logger.info(f"Target kernel: {kernel_version}")
        
        if current_version:
            logger.info(f"Current Photon version: {current_version} (will skip fixes already in tarball)")
        
        try:
            response = requests.get(
                self.config.cve_announce_feed,
                timeout=60,
            )
            response.raise_for_status()
            feed_content = response.text
        except Exception as e:
            logger.error(f"Failed to fetch Atom feed: {e}")
            return []
        
        # Parse fixes for target kernel
        pattern = rf"Fixed in ({kernel_version}\.\d+) with commit ([a-f0-9]{{40}})"
        matches = re.findall(pattern, feed_content)
        
        cves: Dict[str, CVE] = {}
        skipped = 0
        
        for fix_version, commit in matches:
            # Skip if already in current version
            if current_version and not version_less_than(current_version, fix_version):
                skipped += 1
                continue
            
            # Create a minimal CVE object (Atom feed doesn't provide full details)
            # We use commit as identifier since CVE ID isn't directly available
            cve_id = f"CVE-ATOM-{commit[:8]}"  # Placeholder
            
            cve = CVE(
                cve_id=cve_id,
                source=CVESource.ATOM,
                fix_commits=[commit],
                affected_versions=[fix_version],
            )
            cves[commit] = cve
        
        logger.info(f"Found {len(cves)} CVE fixes for kernel {kernel_version} (skipped {skipped})")
        
        return list(cves.values())


class UpstreamFetcher(CVEFetcher):
    """Fetch CVEs from upstream torvalds/linux commits."""
    
    async def _scan_day(
        self,
        session: aiohttp.ClientSession,
        date_str: str,
    ) -> List[str]:
        """Scan commits for a single day."""
        since = f"{date_str}T00:00:00Z"
        until = f"{date_str}T23:59:59Z"
        
        url = f"{self.config.github_api_url}/repos/torvalds/linux/commits"
        params = {
            "since": since,
            "until": until,
            "per_page": 100,
        }
        
        try:
            async with session.get(url, params=params) as response:
                if response.status != 200:
                    return []
                commits = await response.json()
        except Exception:
            return []
        
        cve_commits = []
        for commit in commits:
            message = commit.get("commit", {}).get("message", "")
            if re.search(r"CVE", message, re.IGNORECASE):
                sha = commit.get("sha")
                if sha:
                    cve_commits.append(sha)
        
        return cve_commits
    
    async def fetch_async(
        self,
        kernel_version: str,
        output_dir: Path,
        current_version: Optional[str] = None,
        scan_month: Optional[str] = None,
    ) -> List[CVE]:
        """Fetch CVEs from upstream commits."""
        logger.info("Source: upstream torvalds/linux commits")
        logger.info("Searching for commits containing keyword: CVE")
        logger.warning("Note: Most CVE fixes don't mention CVE in commit messages")
        
        all_commits: Set[str] = set()
        
        # Determine date range
        now = datetime.now()
        if scan_month:
            year, month = map(int, scan_month.split("-"))
            months_to_scan = [(year, month)]
        else:
            # Scan from 2024-01 to now
            months_to_scan = []
            year, month = 2024, 1
            while (year, month) <= (now.year, now.month):
                months_to_scan.append((year, month))
                month += 1
                if month > 12:
                    month = 1
                    year += 1
        
        async with aiohttp.ClientSession() as session:
            for year, month in months_to_scan:
                logger.debug(f"Scanning {year}-{month:02d}")
                
                # Get days in month
                if month == 12:
                    next_year, next_month = year + 1, 1
                else:
                    next_year, next_month = year, month + 1
                
                from calendar import monthrange
                days_in_month = monthrange(year, month)[1]
                
                for day in range(1, days_in_month + 1):
                    date_str = f"{year}-{month:02d}-{day:02d}"
                    commits = await self._scan_day(session, date_str)
                    all_commits.update(commits)
                    
                    await asyncio.sleep(0.1)  # Rate limiting
        
        # Create CVE objects
        cves = []
        for commit in all_commits:
            cve = CVE(
                cve_id=f"CVE-UPSTREAM-{commit[:8]}",
                source=CVESource.UPSTREAM,
                fix_commits=[commit],
            )
            cves.append(cve)
        
        logger.info(f"Found {len(cves)} commits with CVE keyword")
        
        return cves


def get_fetcher(source: CVESource, config: Optional[KernelConfig] = None) -> CVEFetcher:
    """Get appropriate fetcher for a CVE source."""
    fetchers = {
        CVESource.NVD: NVDFetcher,
        CVESource.GHSA: GHSAFetcher,
        CVESource.ATOM: AtomFetcher,
        CVESource.UPSTREAM: UpstreamFetcher,
    }
    
    fetcher_class = fetchers.get(source, NVDFetcher)
    return fetcher_class(config)


async def fetch_cves(
    source: CVESource,
    kernel_version: str,
    output_dir: Path,
    current_version: Optional[str] = None,
    config: Optional[KernelConfig] = None,
) -> List[CVE]:
    """
    Fetch CVEs from specified source.
    
    Args:
        source: CVE source (NVD, GHSA, ATOM, UPSTREAM)
        kernel_version: Target kernel version
        output_dir: Output directory for intermediate files
        current_version: Current Photon kernel version (for filtering)
        config: Optional configuration
    
    Returns:
        List of CVE objects
    """
    fetcher = get_fetcher(source, config)
    return await fetcher.fetch_async(kernel_version, output_dir, current_version)


def fetch_cves_sync(
    source: CVESource,
    kernel_version: str,
    output_dir: Path,
    current_version: Optional[str] = None,
    config: Optional[KernelConfig] = None,
) -> List[CVE]:
    """Synchronous wrapper for fetch_cves."""
    return asyncio.run(fetch_cves(source, kernel_version, output_dir, current_version, config))
