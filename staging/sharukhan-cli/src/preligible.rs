//! `sharukhan pr-eligibility`: is each PR still needed on the current base?
//!
//! A PR fixes defects. Whether it is still needed is a question about those
//! defects, never about a guest that happens to pass without the PR: a
//! package that installs and boots without its fix proves nothing about the
//! fix (a dangling udev rule only logs, a file owned twice only shows on
//! removal). So each PR's defects are data (config/pr-defects.json), each
//! with probes that look for the defect itself, and every probe runs against
//! every copy of the PR's package in the base tree (Photon 5.0 keeps one spec
//! directory per subrelease range, e.g. SPECS/91/systemd beside SPECS/systemd).
//!
//! Probes, all read-only against the base:
//! - `file`: lines of a file of the copy's spec directory (a spec, a patch).
//! - `upstream`: are the upstream fix commits in the commit the copy's source
//!   archive is made from (config.yaml `commit_id`), as ancestors or as
//!   cherry-picks, or carried by a patch the copy lists (its header names the
//!   commit)?
//! - `upstream-file`: does that source carry the fixed code? Positive-only: a
//!   miss leaves the defect to the other probes (the copy may patch it in).
//! - `series`: does the copy's %prep exist and apply at fuzz 0 against its
//!   sha512-verified source archive, for a set of defines (a build variant)?
//! - `rpm-overlap`: do two packages of the base's own build (the gate's
//!   baseline, no PR) own the same files?
//!
//! A guest check attributed to the PR (config/check-prs.tsv) is reported as
//! the symptom record beside the verdicts. The verdict never closes a PR:
//! "no defect present in any copy" says the PR's own symptom is gone on this
//! base, and the decision is the user's.

use serde::Deserialize;
use std::collections::BTreeMap;
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const BUILTIN_PR_DEFECTS: &str = include_str!("../config/pr-defects.json");

// --- data -------------------------------------------------------------------

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Data {
    pub prs: Vec<PrDef>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PrDef {
    pub pr: u64,
    pub package: String,
    #[serde(default)]
    pub title: String,
    /// The subreleases the PR is about; a copy outside them is listed, not
    /// probed (another PR may own that copy).
    #[serde(default)]
    pub subreleases: Option<Scope>,
    pub defects: Vec<Defect>,
}

#[derive(Debug, Clone, Copy, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Scope {
    #[serde(default)]
    pub from: Option<u32>,
    #[serde(default)]
    pub to: Option<u32>,
}

impl Scope {
    /// Does a copy building for `build_if` serve any subrelease of the scope?
    pub fn covers(&self, build_if: &str) -> bool {
        let (lo, hi) = range(build_if);
        let a = lo.unwrap_or(0).max(self.from.unwrap_or(0));
        let b = hi.unwrap_or(u32::MAX).min(self.to.unwrap_or(u32::MAX));
        a <= b
    }
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Defect {
    pub id: String,
    pub summary: String,
    #[serde(default)]
    pub symptom_check: Option<String>,
    pub probes: Vec<Probe>,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case", deny_unknown_fields)]
pub enum Probe {
    File {
        file: String,
        #[serde(default)]
        applies_if: Vec<Pat>,
        #[serde(default)]
        present_if_all: Vec<Pat>,
        #[serde(default)]
        present_if_none: Vec<Pat>,
    },
    Upstream {
        commits: Vec<String>,
    },
    UpstreamFile {
        path: String,
        fixed_if: Pat,
    },
    Series {
        #[serde(default)]
        defines: BTreeMap<String, String>,
        #[serde(default)]
        applies_if: Vec<Pat>,
        #[serde(default)]
        expect_patch: Option<String>,
    },
    RpmOverlap {
        packages: Vec<String>,
    },
}

/// One line pattern: exactly one of an exact line, a line prefix, or a
/// substring of a line (trailing whitespace of the file's lines ignored).
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Pat {
    #[serde(default)]
    pub line: Option<String>,
    #[serde(default)]
    pub prefix: Option<String>,
    #[serde(default)]
    pub contains: Option<String>,
}

impl Pat {
    fn matches(&self, text: &str) -> bool {
        text.lines().map(str::trim_end).any(|l| match (&self.line, &self.prefix, &self.contains) {
            (Some(x), None, None) => l == x,
            (None, Some(x), None) => l.starts_with(x.as_str()),
            (None, None, Some(x)) => l.contains(x.as_str()),
            _ => false,
        })
    }
    fn show(&self) -> String {
        match (&self.line, &self.prefix, &self.contains) {
            (Some(x), _, _) => format!("`{}`", x.trim()),
            (_, Some(x), _) => format!("`{}…`", x.trim()),
            (_, _, Some(x)) => format!("`…{}…`", x.trim()),
            _ => "?".into(),
        }
    }
    fn valid(&self) -> bool {
        let n = [&self.line, &self.prefix, &self.contains].iter().filter(|x| x.is_some()).count();
        n == 1 && [&self.line, &self.prefix, &self.contains].iter().all(|x| x.as_ref().map_or(true, |s| !s.trim().is_empty()))
    }
}

fn is_full_sha(s: &str) -> bool {
    s.len() == 40 && s.bytes().all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
}

fn safe_rel(p: &str) -> bool {
    !p.is_empty() && !p.starts_with('/') && p.split('/').all(|c| !c.is_empty() && c != "." && c != "..")
}

fn safe_macro(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_')
}

/// The data, checked: every rule here is one a typo would otherwise turn into
/// a silent "absent".
pub fn parse(text: &str) -> Result<Data, String> {
    let d: Data = serde_json::from_str(text).map_err(|e| format!("pr-defects: {e}"))?;
    let mut seen = std::collections::BTreeSet::new();
    for p in &d.prs {
        if !seen.insert(p.pr) {
            return Err(format!("pr-defects: #{} is listed twice", p.pr));
        }
        if !safe_rel(&p.package) || p.package.contains('/') {
            return Err(format!("pr-defects: #{}: package {:?} is not a spec directory name", p.pr, p.package));
        }
        if p.defects.is_empty() {
            return Err(format!("pr-defects: #{} has no defect", p.pr));
        }
        if let Some(Scope { from: Some(a), to: Some(b) }) = p.subreleases {
            if a > b {
                return Err(format!("pr-defects: #{}: subreleases from {a} to {b} is empty", p.pr));
            }
        }
        let mut ids = std::collections::BTreeSet::new();
        for df in &p.defects {
            let at = format!("pr-defects: #{} {}", p.pr, df.id);
            if df.id.trim().is_empty() || !ids.insert(df.id.clone()) {
                return Err(format!("{at}: empty or repeated defect id"));
            }
            if df.summary.trim().is_empty() {
                return Err(format!("{at}: no summary"));
            }
            if df.probes.is_empty() {
                return Err(format!("{at}: no probe"));
            }
            for pr in &df.probes {
                match pr {
                    Probe::File { file, applies_if, present_if_all, present_if_none } => {
                        if !safe_rel(file) {
                            return Err(format!("{at}: file {file:?} must be a relative path inside the spec directory"));
                        }
                        if present_if_all.is_empty() && present_if_none.is_empty() {
                            return Err(format!("{at}: a file probe needs present_if_all or present_if_none"));
                        }
                        if !applies_if.iter().chain(present_if_all).chain(present_if_none).all(Pat::valid) {
                            return Err(format!("{at}: each pattern takes exactly one of line, prefix, contains"));
                        }
                    }
                    Probe::Upstream { commits } => {
                        if commits.is_empty() || !commits.iter().all(|c| is_full_sha(c)) {
                            return Err(format!("{at}: upstream commits must be full 40-hex lower-case SHAs"));
                        }
                    }
                    Probe::UpstreamFile { path, fixed_if } => {
                        if !safe_rel(path) || !fixed_if.valid() {
                            return Err(format!("{at}: upstream-file needs a relative path and one pattern"));
                        }
                    }
                    Probe::Series { defines, applies_if, expect_patch } => {
                        if !defines.iter().all(|(k, v)| safe_macro(k) && !v.contains('\n')) || !applies_if.iter().all(Pat::valid) {
                            return Err(format!("{at}: series defines must be macro names with one-line values"));
                        }
                        if expect_patch.as_deref().is_some_and(|x| !safe_rel(x) || x.contains('/')) {
                            return Err(format!("{at}: expect_patch must be a file name"));
                        }
                    }
                    Probe::RpmOverlap { packages } => {
                        if packages.len() != 2 || !packages.iter().all(|x| safe_rel(x) && !x.contains('/')) {
                            return Err(format!("{at}: rpm-overlap takes two package names"));
                        }
                    }
                }
            }
        }
    }
    Ok(d)
}

// --- the copies of a package ------------------------------------------------

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Copy {
    pub dir: String,
    pub build_if: String,
    pub version: String,
    pub release: String,
    pub archive: Option<String>,
    pub sha512: Option<String>,
    pub url: Option<String>,
    pub repo_url: Option<String>,
    pub commit_id: Option<String>,
    pub archives: Vec<Archive>,
}

impl Copy {
    pub fn label(&self) -> String {
        let r = self.release.split('%').next().unwrap_or("").trim();
        let range = range_text(&self.build_if);
        format!("`{}` {}-{}{}", self.dir, self.version, r, if range.is_empty() { String::new() } else { format!(", {range}") })
    }
}

/// `%{photon_subrelease} >= 91 && %{photon_subrelease} <= 92` -> (91, 92).
pub fn range(build_if: &str) -> (Option<u32>, Option<u32>) {
    let (mut lo, mut hi) = (None, None);
    let t = build_if.replace("%{photon_subrelease}", "S").replace("%{?photon_subrelease}", "S");
    for part in t.split("&&") {
        let p: String = part.chars().filter(|c| !c.is_whitespace()).collect();
        let num = |s: &str| s.parse::<u32>().ok();
        if let Some(n) = p.strip_prefix("S>=").and_then(num) {
            lo = Some(n);
        } else if let Some(n) = p.strip_prefix("S>").and_then(num) {
            lo = Some(n + 1);
        } else if let Some(n) = p.strip_prefix("S<=").and_then(num) {
            hi = Some(n);
        } else if let Some(n) = p.strip_prefix("S<").and_then(num) {
            hi = n.checked_sub(1);
        } else if let Some(n) = p.strip_prefix("S==").and_then(num) {
            lo = Some(n);
            hi = Some(n);
        }
    }
    (lo, hi)
}

fn range_text(build_if: &str) -> String {
    match range(build_if) {
        (Some(a), Some(b)) if a == b => format!("subrelease {a}"),
        (Some(a), Some(b)) => format!("subreleases {a}-{b}"),
        (Some(a), None) => format!("subrelease {a}+"),
        (None, Some(b)) => format!("subrelease <= {b}"),
        (None, None) => String::new(),
    }
}

/// A subrelease the copy builds for, for expanding its spec as Photon would.
pub fn representative(build_if: &str) -> Option<u32> {
    let (lo, hi) = range(build_if);
    lo.or(hi)
}

/// One source entry of config.yaml.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Archive {
    pub name: String,
    pub sha512: Option<String>,
    pub url: Option<String>,
    pub repo_url: Option<String>,
    pub commit_id: Option<String>,
}

/// Every `- archive:` entry of config.yaml. A key whose value is on the next,
/// deeper-indented line (`archive_sha512sum:` then the digest) is read too.
pub fn archives_of(yaml: &str) -> Vec<Archive> {
    let ls: Vec<&str> = yaml.lines().collect();
    let mut v: Vec<Archive> = Vec::new();
    let mut i = 0;
    while i < ls.len() {
        let l = ls[i];
        let indent = l.len() - l.trim_start().len();
        let t = l.trim_start().trim_start_matches("- ").trim();
        let Some((k, val)) = t.split_once(':') else {
            i += 1;
            continue;
        };
        let unq = |s: &str| s.trim().trim_matches('"').trim_matches('\'').to_string();
        let mut val = unq(val);
        if val.is_empty() {
            if let Some(n) = ls.get(i + 1) {
                let ni = n.len() - n.trim_start().len();
                let nt = n.trim();
                if ni > indent && !nt.is_empty() && !nt.contains(':') && !nt.starts_with('-') {
                    val = unq(nt);
                    i += 1;
                }
            }
        }
        let field = if val.is_empty() { None } else { Some(val.clone()) };
        match k.trim() {
            "archive" if l.trim_start().starts_with("- ") => v.push(Archive { name: val, ..Archive::default() }),
            "archive_sha512sum" => {
                if let Some(a) = v.last_mut() {
                    a.sha512 = a.sha512.take().or(field);
                }
            }
            "url" => {
                if let Some(a) = v.last_mut() {
                    a.url = a.url.take().or(field);
                }
            }
            "repo_url" => {
                if let Some(a) = v.last_mut() {
                    a.repo_url = a.repo_url.take().or(field);
                }
            }
            "commit_id" => {
                if let Some(a) = v.last_mut() {
                    a.commit_id = a.commit_id.take().or(field);
                }
            }
            _ => {}
        }
        i += 1;
    }
    v.retain(|a| !a.name.is_empty());
    v
}

/// The copy's source facts from config.yaml: the first archive's, and every
/// archive for a %prep that unpacks more than one.
pub fn source_of(yaml: &str, c: &mut Copy) {
    let all = archives_of(yaml);
    if let Some(a) = all.first() {
        c.archive = Some(a.name.clone());
        c.sha512 = a.sha512.clone();
        c.url = a.url.clone();
        c.repo_url = a.repo_url.clone();
        c.commit_id = a.commit_id.clone();
    }
    c.archives = all;
}

fn git(dir: &Path, args: &[&str]) -> Result<String, String> {
    let out = Command::new("git").arg("-C").arg(dir).args(args).output().map_err(|e| format!("running git {}: {e}", args.join(" ")))?;
    if !out.status.success() {
        return Err(format!("git {} failed: {}", args.join(" "), String::from_utf8_lossy(&out.stderr).trim()));
    }
    Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

/// Every spec directory of `package` at `rev`: SPECS/<package> and
/// SPECS/<NN>/<package>, each with its build condition and source.
pub fn copies(repo: &Path, rev: &str, package: &str) -> Result<Vec<Copy>, String> {
    let names = git(repo, &["ls-tree", "-r", "--name-only", rev, "SPECS"])?;
    let spec = format!("{package}/{package}.spec");
    let mut v = Vec::new();
    for n in names.lines() {
        let Some(dir) = n.strip_suffix(&format!("/{package}.spec")) else { continue };
        let parts: Vec<&str> = dir.split('/').collect();
        let ok = match parts.as_slice() {
            ["SPECS", p] => *p == package,
            ["SPECS", sub, p] => *p == package && sub.bytes().all(|b| b.is_ascii_digit()),
            _ => false,
        };
        if !ok || !n.ends_with(&spec) {
            continue;
        }
        let read = crate::specresolve::git_reader(repo, rev, dir, None);
        let text = read(&format!("{package}.spec")).ok_or_else(|| format!("{n}: unreadable at {rev}"))?;
        let mut c = Copy {
            dir: dir.to_string(),
            build_if: text.lines().find_map(|l| l.trim().strip_prefix("%global build_if").map(|x| x.trim().to_string())).unwrap_or_default(),
            version: crate::specresolve::field(&text, "Version:").unwrap_or_default(),
            release: crate::specresolve::field(&text, "Release:").unwrap_or_default(),
            ..Copy::default()
        };
        if let Some(y) = read("config.yaml") {
            source_of(&y, &mut c);
        }
        v.push(c);
    }
    // the copy for the oldest subreleases first, as Photon's table reads
    v.sort_by_key(|c| (range(&c.build_if).0.unwrap_or(0), c.dir.clone()));
    if v.is_empty() {
        return Err(format!("no spec directory of {package} at {rev}"));
    }
    Ok(v)
}

// --- verdicts -----------------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
pub enum Verdict {
    Present(String),
    Absent(String),
    Fixed(String),
    NotApplicable(String),
    Unknown(String),
}

impl Verdict {
    fn word(&self) -> &'static str {
        match self {
            Verdict::Present(_) => "**present**",
            Verdict::Absent(_) => "absent",
            Verdict::Fixed(_) => "fixed upstream",
            Verdict::NotApplicable(_) => "not applicable",
            Verdict::Unknown(_) => "unknown",
        }
    }
    fn why(&self) -> &str {
        match self {
            Verdict::Present(s) | Verdict::Absent(s) | Verdict::Fixed(s) | Verdict::NotApplicable(s) | Verdict::Unknown(s) => s,
        }
    }
}

/// The probes of one defect on one copy, combined: a probe that finds the
/// defect's subject missing makes it not applicable; a probe that finds it
/// and one that finds the fix upstream contradict each other, and the
/// contradiction is reported, never resolved by order.
pub fn combine(v: &[Verdict]) -> Verdict {
    if let Some(n) = v.iter().find(|x| matches!(x, Verdict::NotApplicable(_))) {
        return n.clone();
    }
    let present: Vec<&str> = v.iter().filter_map(|x| if let Verdict::Present(s) = x { Some(s.as_str()) } else { None }).collect();
    let fixed: Vec<&str> = v.iter().filter_map(|x| if let Verdict::Fixed(s) = x { Some(s.as_str()) } else { None }).collect();
    let absent: Vec<&str> = v.iter().filter_map(|x| if let Verdict::Absent(s) = x { Some(s.as_str()) } else { None }).collect();
    if !present.is_empty() && !fixed.is_empty() {
        return Verdict::Unknown(format!("contradicting probes: {} / {}", present.join("; "), fixed.join("; ")));
    }
    if !present.is_empty() {
        return Verdict::Present(present.join("; "));
    }
    if !fixed.is_empty() {
        return Verdict::Fixed(fixed.join("; "));
    }
    if !absent.is_empty() {
        return Verdict::Absent(absent.join("; "));
    }
    let unknown: Vec<&str> = v.iter().map(Verdict::why).collect();
    Verdict::Unknown(unknown.join("; "))
}

/// A `file` probe on the file's text (None: the copy has no such file).
pub fn file_verdict(file: &str, text: Option<&str>, applies_if: &[Pat], all: &[Pat], none: &[Pat]) -> Verdict {
    let Some(t) = text else {
        return Verdict::NotApplicable(format!("no `{file}`"));
    };
    if let Some(p) = applies_if.iter().find(|p| !p.matches(t)) {
        return Verdict::NotApplicable(format!("`{file}` has no {}", p.show()));
    }
    let missing: Vec<String> = all.iter().filter(|p| !p.matches(t)).map(Pat::show).collect();
    let found: Vec<String> = none.iter().filter(|p| p.matches(t)).map(Pat::show).collect();
    if missing.is_empty() && found.is_empty() {
        let mut why = Vec::new();
        if !all.is_empty() {
            why.push(format!("has {}", all.iter().map(Pat::show).collect::<Vec<_>>().join(", ")));
        }
        if !none.is_empty() {
            why.push(format!("no {}", none.iter().map(Pat::show).collect::<Vec<_>>().join(", ")));
        }
        Verdict::Present(format!("`{file}` {}", why.join("; ")))
    } else {
        let mut why = Vec::new();
        if !missing.is_empty() {
            why.push(format!("no {}", missing.join(", ")));
        }
        if !found.is_empty() {
            why.push(format!("has {}", found.join(", ")));
        }
        Verdict::Absent(format!("`{file}` {}", why.join("; ")))
    }
}

/// Of `n` fix commits, `contained` are in the source and `carried` more are
/// patches of the copy itself -> the verdict.
pub fn upstream_verdict(contained: usize, carried: usize, n: usize, at: &str) -> Verdict {
    if n > 0 && contained == n {
        Verdict::Fixed(format!("all {n} fix commit(s) are in {at}"))
    } else if n > 0 && contained + carried == n {
        if contained == 0 {
            Verdict::Absent(format!("all {n} fix commit(s) carried by the copy's own patches ({at} has none)"))
        } else {
            Verdict::Absent(format!("{carried} of {n} fix commit(s) carried by the copy's own patches, the other {contained} in {at}"))
        }
    } else if contained + carried == 0 {
        Verdict::Present(format!("none of {n} fix commit(s) is in {at} or a patch of the copy"))
    } else {
        Verdict::Present(format!("only {} of {n} fix commit(s) are in {at} or a patch of the copy", contained + carried))
    }
}

/// The patch files a spec lists (its Patch tags as written, any branch of a
/// conditional), each with its header: the text before the first diff.
pub fn listed_patch_headers(spec: &str, read: &dyn Fn(&str) -> Option<String>) -> Vec<(String, String)> {
    let mut v = Vec::new();
    for l in spec.lines() {
        let Some((tag, val)) = l.split_once(':') else { continue };
        let Some(num) = tag.trim().strip_prefix("Patch") else { continue };
        if !num.bytes().all(|b| b.is_ascii_digit()) {
            continue;
        }
        let name = val.trim();
        if name.is_empty() || name.contains('%') || !safe_rel(name) || name.contains('/') {
            continue;
        }
        if let Some(text) = read(name) {
            let head: String = text.lines().take_while(|l| !l.starts_with("diff --git ") && !l.starts_with("--- a/")).collect::<Vec<_>>().join("\n");
            v.push((name.to_string(), head));
        }
    }
    v
}

/// The listed patch whose header names the full commit `sha`, if any.
pub fn carried_by<'a>(headers: &'a [(String, String)], sha: &str) -> Option<&'a str> {
    headers.iter().find(|(_, h)| h.contains(sha)).map(|(n, _)| n.as_str())
}

// --- probing a copy -----------------------------------------------------------

pub struct Ctx<'a> {
    pub repo: &'a Path,
    pub rev: &'a str,
    pub cache: PathBuf,
    pub scratch: PathBuf,
    pub sources: Vec<PathBuf>,
    pub rpms: PathBuf,
    pub log: &'a mut dyn FnMut(&str),
}

fn spec_text(ctx: &Ctx, c: &Copy, package: &str) -> Option<String> {
    crate::specresolve::git_reader(ctx.repo, ctx.rev, &c.dir, None)(&format!("{package}.spec"))
}

/// The bare upstream clone for `url` under the cache, with `sha` present.
fn upstream_repo(ctx: &mut Ctx, url: &str, sha: &str) -> Result<PathBuf, String> {
    if !url.starts_with("https://") || url.contains(char::is_whitespace) {
        return Err(format!("{url}: only https upstream URLs are fetched"));
    }
    let name: String = url.trim_start_matches("https://").trim_end_matches(".git").chars().map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '.' { c } else { '_' }).collect();
    let dir = ctx.cache.join(format!("{name}.git"));
    if !dir.join("HEAD").is_file() {
        fs::create_dir_all(&dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        git(&dir, &["init", "-q", "--bare"])?;
    }
    if git(&dir, &["cat-file", "-e", &format!("{sha}^{{commit}}")]).is_err() {
        (ctx.log)(&format!("  fetching {} from {url}", &sha[..12.min(sha.len())]));
        git(&dir, &["fetch", "-q", "--no-tags", url, sha])?;
        git(&dir, &["cat-file", "-e", &format!("{sha}^{{commit}}")])?;
    }
    Ok(dir)
}

/// Is the fix `fix` in the source `id`: an ancestor, or cherry-picked into its
/// history (git cherry-pick -x writes the trailer; the stable branches use it)?
/// `have` is false when the source's repository does not know the commit at
/// all; only a cherry-pick can bring it in then.
fn contains(dir: &Path, fix: &str, id: &str, have: bool) -> Result<Option<String>, String> {
    if have && git(dir, &["merge-base", "--is-ancestor", fix, id]).is_ok() {
        return Ok(Some("ancestor".into()));
    }
    let hit = git(dir, &["log", "--format=%H", "-F", &format!("--grep=cherry picked from commit {fix}"), "-n", "1", id])?;
    Ok(hit.lines().next().map(|h| format!("cherry-picked as {}", &h[..10.min(h.len())])))
}

fn source_commit(c: &Copy) -> Result<(String, String), String> {
    let url = c.repo_url.clone().ok_or("no repo_url in config.yaml")?;
    let id = c.commit_id.clone().filter(|x| is_full_sha(x)).ok_or("no full commit_id in config.yaml")?;
    Ok((url, id))
}

/// A source archive, sha512-verified: from a SOURCES directory, or downloaded
/// into the cache. A file whose digest differs is never used.
fn archive(ctx: &mut Ctx, a: &Archive) -> Result<PathBuf, String> {
    let name = Some(a.name.clone()).filter(|n| safe_rel(n) && !n.contains('/')).ok_or("no archive name in config.yaml")?;
    let want = a.sha512.clone().filter(|s| crate::sha512::is_hex_digest(s)).ok_or_else(|| format!("{name}: no archive_sha512sum in config.yaml"))?;
    for d in ctx.sources.clone().iter().chain(std::iter::once(&ctx.cache.join("sources"))) {
        let p = d.join(&name);
        if p.is_file() && crate::sha512::file(&p)? == want {
            return Ok(p);
        }
    }
    let url = a.url.clone().filter(|u| u.starts_with("https://")).ok_or_else(|| format!("{name}: no https url in config.yaml"))?;
    let dir = ctx.cache.join("sources");
    fs::create_dir_all(&dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    let part = dir.join(format!("{name}.part.{}", std::process::id()));
    (ctx.log)(&format!("  downloading {url}"));
    let st = Command::new("curl").args(["-fsSL", "--proto", "=https", "--retry", "3", "-o"]).arg(&part).arg(&url).status().map_err(|e| format!("curl: {e}"))?;
    if !st.success() {
        let _ = fs::remove_file(&part);
        return Err(format!("downloading {url} failed"));
    }
    if crate::sha512::file(&part)? != want {
        let _ = fs::remove_file(&part);
        return Err(format!("{url}: sha512 differs from config.yaml"));
    }
    let p = dir.join(&name);
    fs::rename(&part, &p).map_err(|e| format!("{}: {e}", p.display()))?;
    Ok(p)
}

/// A fresh directory under the scratch root, removed by the caller.
fn fresh(ctx: &Ctx, tag: &str) -> Result<PathBuf, String> {
    static N: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let d = ctx.scratch.join(format!("preligible-{}-{}-{tag}", std::process::id(), N.fetch_add(1, std::sync::atomic::Ordering::Relaxed)));
    fs::create_dir_all(&d).map_err(|e| format!("{}: {e}", d.display()))?;
    Ok(d)
}

/// The spec's patches in the order rpmspec -P expands them.
pub fn patch_list(expanded: &str) -> Vec<String> {
    expanded
        .lines()
        .filter_map(|l| {
            let (tag, val) = l.split_once(':')?;
            // "Patch:" stays unnumbered in the expanded spec; rpm numbers it
            let num = tag.strip_prefix("Patch")?;
            if !num.bytes().all(|b| b.is_ascii_digit()) {
                return None;
            }
            let v = val.trim();
            (!v.is_empty()).then(|| v.rsplit('/').next().unwrap_or(v).to_string())
        })
        .collect()
}

/// Photon stages a spec directory's files by name: a file in a subdirectory
/// (SPECS/92/linux/CVE/x.patch) is a source as `x.patch`. The same here: each
/// one is linked to the top of `dir`. Two different files of one name are
/// refused, as Photon's staging would pick one silently.
pub fn flatten_sources(dir: &Path) -> Result<usize, String> {
    let mut found: Vec<PathBuf> = Vec::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(d) = stack.pop() {
        for e in fs::read_dir(&d).map_err(|e| format!("{}: {e}", d.display()))? {
            let e = e.map_err(|e| format!("{e}"))?;
            let ft = e.file_type().map_err(|e| format!("{e}"))?;
            if ft.is_dir() {
                stack.push(e.path());
            } else if ft.is_file() && d != dir {
                found.push(e.path());
            }
        }
    }
    found.sort();
    let mut n = 0;
    for f in found {
        let Some(name) = f.file_name() else { continue };
        let top = dir.join(name);
        if top.exists() {
            if fs::read(&top).map_err(|e| format!("{e}"))? != fs::read(&f).map_err(|e| format!("{e}"))? {
                return Err(format!("two different files are named {}: {} and {}", name.to_string_lossy(), top.display(), f.display()));
            }
            continue;
        }
        fs::hard_link(&f, &top).or_else(|_| fs::copy(&f, &top).map(|_| ())).map_err(|e| format!("{}: {e}", top.display()))?;
        n += 1;
    }
    Ok(n)
}

/// The Source file names an expanded spec lists.
pub fn source_list(expanded: &str) -> Vec<String> {
    expanded
        .lines()
        .filter_map(|l| {
            let (tag, val) = l.split_once(':')?;
            let num = tag.strip_prefix("Source")?;
            if !num.bytes().all(|b| b.is_ascii_digit()) {
                return None;
            }
            let v = val.trim();
            (!v.is_empty()).then(|| v.rsplit('/').next().unwrap_or(v).to_string())
        })
        .collect()
}

/// The patch %prep was applying when it failed: the last patch file the
/// trace names, from `Patch #N (name):` (%patch) or the file %autosetup feeds
/// to patch (`+ /usr/lib/rpm/rpmuncompress .../name.patch`, `cat`, `<`).
pub fn failing_patch(out: &str) -> Option<String> {
    let mut last = None;
    for l in out.lines().map(str::trim) {
        if let Some(r) = l.strip_prefix("Patch #") {
            if let Some((_, x)) = r.split_once('(') {
                if let Some((n, _)) = x.split_once(')') {
                    last = Some(n.to_string());
                }
            }
            continue;
        }
        if !l.starts_with('+') {
            continue;
        }
        for w in l.split(|c: char| c.is_whitespace() || c == '<' || c == '\'' || c == '"') {
            if w.ends_with(".patch") || w.ends_with(".diff") {
                last = Some(w.rsplit('/').next().unwrap_or(w).to_string());
            }
        }
    }
    last
}

/// A command %prep ran that the builder lacks (`line 61: dotnet: command not
/// found`): the environment's gap, not the spec's defect.
/// A header is the same gap: `--nodeps` installs no build dependency, so a
/// %prep that compiles a probe (`fatal error: libelf.h: No such file or
/// directory`) says the builder lacks it, not that the spec is broken.
pub fn missing_command(out: &str) -> Option<String> {
    out.lines().find_map(|l| {
        let l = l.trim();
        if let Some(head) = l.strip_suffix(": command not found") {
            let cmd = head.rsplit(": ").next()?.trim();
            return (!cmd.is_empty() && !cmd.contains(' ')).then(|| cmd.to_string());
        }
        let (_, rest) = l.split_once("fatal error: ")?;
        let hdr = rest.strip_suffix(": No such file or directory")?.trim();
        (hdr.ends_with(".h") && !hdr.contains(' ')).then(|| format!("<{hdr}>"))
    })
}

/// Did patch itself refuse a hunk or a file?
pub fn patch_failed(out: &str) -> bool {
    out.lines().map(str::trim).any(|l| (l.contains("hunk") && l.contains("FAILED")) || l.starts_with("can't find file to patch") || l.contains("Reversed (or previously applied) patch detected") || l.contains("malformed patch"))
}

/// What patch or the shell said when %prep failed: the first line that
/// carries a reason, not rpm's own summary.
pub fn prep_reason(out: &str) -> Option<String> {
    const KEYS: [&str; 6] = ["FAILED", "can't find file", "No such file", "Reversed (or previously applied)", "malformed patch", "not found"];
    out.lines().map(str::trim).find(|l| KEYS.iter().any(|k| l.contains(k)) && !l.starts_with("error: Bad exit status")).map(|l| l.chars().take(160).collect())
}

/// The copy's real %prep for `defines`: rpmbuild -bp --nodeps in the builder,
/// with the spec directory and every config.yaml archive (sha512-verified) as
/// its sources, in a scratch tree. A switch fixed by a plain %define is set in
/// the scratch copy of the spec, since -D cannot reach it.
fn series(ctx: &mut Ctx, c: &Copy, package: &str, defines: &BTreeMap<String, String>, expect: Option<&str>) -> Result<Verdict, String> {
    let work = fresh(ctx, "series")?;
    let r = (|| -> Result<Verdict, String> {
        let specdir = work.join("spec");
        fs::create_dir_all(&specdir).map_err(|e| format!("{e}"))?;
        let tar = Command::new("git")
            .arg("-C")
            .arg(ctx.repo)
            .args(["archive", "--format=tar", ctx.rev, &c.dir])
            .output()
            .map_err(|e| format!("git archive: {e}"))?;
        if !tar.status.success() {
            return Err(format!("git archive {}:{} failed", ctx.rev, c.dir));
        }
        let mut x = Command::new("tar")
            .args(["-x", "--strip-components", &c.dir.split('/').count().to_string(), "-C"])
            .arg(&specdir)
            .stdin(std::process::Stdio::piped())
            .spawn()
            .map_err(|e| format!("tar: {e}"))?;
        use std::io::Write;
        x.stdin.take().ok_or("tar stdin")?.write_all(&tar.stdout).map_err(|e| format!("tar: {e}"))?;
        if !x.wait().map_err(|e| format!("tar: {e}"))?.success() {
            return Err("unpacking the spec directory failed".into());
        }
        flatten_sources(&specdir)?;
        let spec = specdir.join(format!("{package}.spec"));
        let mut fixed = Vec::new();
        let raw = fs::read_to_string(&spec).map_err(|e| format!("{}: {e}", spec.display()))?;
        let mut text = raw.clone();
        for s in crate::specswitch::switches(&raw) {
            if let (crate::specswitch::Kind::Fixed(_), Some(v)) = (&s.kind, defines.get(&s.name)) {
                text = crate::specswitch::set(&text, &s, v)?;
                fixed.push(s.name.clone());
            }
        }
        if !fixed.is_empty() {
            fs::write(&spec, &text).map_err(|e| format!("{}: {e}", spec.display()))?;
        }
        let with = if defines.is_empty() {
            String::new()
        } else {
            let set = |k: &str| if fixed.iter().any(|f| f == k) { " (a plain %define, set in a scratch copy of the spec)" } else { "" };
            format!(" with {}", defines.iter().map(|(k, v)| format!("{k}={v}{}", set(k))).collect::<Vec<_>>().join(" "))
        };
        let mut common: Vec<OsString> = vec!["-D".into(), format!("_sourcedir {}", specdir.display()).into(), "-D".into(), "dist .ph5".into(), "-D".into(), "with_check 0".into()];
        if let Some(s) = representative(&c.build_if) {
            common.extend(["-D".into(), format!("photon_subrelease {s}").into()]);
        }
        for (k, v) in defines {
            common.extend(["-D".into(), format!("{k} {v}").into()]);
        }
        let mut args: Vec<OsString> = vec!["-P".into()];
        args.extend(common.iter().cloned());
        args.push(spec.clone().into_os_string());
        let out = crate::builder::tool_command("rpmspec", &specdir, &args, ctx.log)?.output().map_err(|e| format!("rpmspec: {e}"))?;
        if !out.status.success() {
            let err = String::from_utf8_lossy(&out.stderr);
            let line = err.lines().find(|l| l.contains("error")).unwrap_or("rpmspec failed").trim().to_string();
            return Ok(Verdict::Present(format!("the spec does not expand{with}: {line}")));
        }
        let expanded = String::from_utf8_lossy(&out.stdout).into_owned();
        let patches = patch_list(&expanded);
        if let Some(e) = expect {
            if !patches.iter().any(|p| p == e) {
                return Ok(Verdict::Present(format!("`{e}` is not in %prep{with}: the variant is unreachable")));
            }
        }
        // the sources %prep may need: every config.yaml archive, verified
        let mut unavailable = Vec::new();
        for s in source_list(&expanded) {
            if specdir.join(&s).exists() {
                continue;
            }
            match c.archives.iter().find(|a| a.name == s) {
                Some(a) => {
                    let p = archive(ctx, a)?;
                    let dst = specdir.join(&s);
                    if fs::hard_link(&p, &dst).is_err() {
                        fs::copy(&p, &dst).map_err(|e| format!("{}: {e}", dst.display()))?;
                    }
                }
                None => unavailable.push(s),
            }
        }
        let (top, tmp) = (work.join("top"), work.join("tmp"));
        for d in [&top, &tmp] {
            fs::create_dir_all(d).map_err(|e| format!("{}: {e}", d.display()))?;
        }
        let mut bp: Vec<OsString> = vec!["-bp".into(), "--nodeps".into(), "-D".into(), format!("_topdir {}", top.display()).into(), "-D".into(), format!("_builddir {}", top.join("BUILD").display()).into(), "-D".into(), format!("_tmppath {}", tmp.display()).into()];
        bp.extend(common);
        bp.push(spec.into_os_string());
        let o = crate::builder::tool_command_with("rpmbuild", &specdir, &bp, &[work.clone()], ctx.log)?.output().map_err(|e| format!("rpmbuild: {e}"))?;
        let all = format!("{}\n{}", String::from_utf8_lossy(&o.stdout), String::from_utf8_lossy(&o.stderr));
        if o.status.success() {
            return Ok(Verdict::Absent(format!("%prep runs (rpmbuild -bp) with {} patch(es){with}", patches.len())));
        }
        if let Some(s) = unavailable.iter().find(|s| all.contains(s.as_str())) {
            return Ok(Verdict::Unknown(format!("%prep{with} needs `{s}`, which is neither in the spec directory nor a verified archive of config.yaml")));
        }
        // the trace is kept: a verdict a reader cannot check is not one
        let logs = ctx.cache.join("logs");
        fs::create_dir_all(&logs).map_err(|e| format!("{}: {e}", logs.display()))?;
        let tag: String = format!("{}{}", c.dir, if defines.is_empty() { String::new() } else { format!("-{}", defines.iter().map(|(k, v)| format!("{k}={v}")).collect::<Vec<_>>().join("-")) })
            .chars()
            .map(|ch| if ch.is_ascii_alphanumeric() || ch == '-' || ch == '=' || ch == '.' { ch } else { '_' })
            .collect();
        let log = logs.join(format!("{tag}.prep.log"));
        fs::write(&log, &all).map_err(|e| format!("{}: {e}", log.display()))?;
        // a patch that does not apply is decisive; a missing tool or header is
        // only the answer when no patch failed (the log may carry both)
        if !patch_failed(&all) {
            if let Some(cmd) = missing_command(&all) {
                return Ok(Verdict::Unknown(format!("%prep{with} needs `{cmd}`, which the builder does not have (--nodeps installs no build dependency; log {})", log.display())));
            }
        }
        let why = prep_reason(&all).map(|r| format!(" (`{r}`)")).unwrap_or_default();
        let why = format!("{why}; log {}", log.display());
        Ok(match failing_patch(&all) {
            Some(p) => Verdict::Present(format!("%prep fails at `{p}`{with}{why}")),
            None => {
                let line = all.lines().rev().find(|l| l.contains("error") && !l.contains("RPM build errors") && !l.contains("Bad exit status")).unwrap_or("rpmbuild -bp failed").trim().to_string();
                Verdict::Present(format!("%prep fails{with}: {line}{why}"))
            }
        })
    })();
    let _ = fs::remove_dir_all(&work);
    r
}

fn rpm_files(rpm: &Path) -> Result<std::collections::BTreeSet<String>, String> {
    let out = Command::new("rpm").arg("-qlp").arg(rpm).output().map_err(|e| format!("rpm: {e}"))?;
    if !out.status.success() {
        return Err(format!("rpm -qlp {} failed", rpm.display()));
    }
    Ok(String::from_utf8_lossy(&out.stdout).lines().filter(|l| l.starts_with('/') && !l.starts_with("/usr/share/licenses/")).map(str::to_string).collect())
}

/// `<name>-<version>-<release><dist>.<arch>.rpm` of exactly this name,
/// version and release: a build of other code is no evidence about this one.
/// `release` is the spec's Release without its `%{?dist}` tail.
pub fn find_rpm(names: &[String], name: &str, version: &str, release: &str) -> Option<String> {
    let pre = format!("{name}-{version}-{release}.ph");
    names
        .iter()
        .filter(|n| {
            let Some(rest) = n.strip_prefix(&pre) else { return false };
            let Some(body) = rest.strip_suffix(".rpm") else { return false };
            // the dist digits, then .<arch>, nothing else
            let Some((dist, arch)) = body.split_once('.') else { return false };
            !dist.is_empty() && dist.bytes().all(|b| b.is_ascii_digit()) && !arch.is_empty() && arch != "src" && !arch.contains('.')
        })
        .max()
        .cloned()
}

fn release_base(r: &str) -> String {
    r.split('%').next().unwrap_or("").trim().to_string()
}

fn overlap(ctx: &Ctx, c: &Copy, pkgs: &[String]) -> Result<Verdict, String> {
    let mut names = Vec::new();
    for arch in ["x86_64", "noarch"] {
        if let Ok(rd) = fs::read_dir(ctx.rpms.join(arch)) {
            names.extend(rd.filter_map(|e| e.ok()).map(|e| (arch, e.file_name().to_string_lossy().into_owned())).map(|(a, n)| format!("{a}/{n}")));
        }
    }
    let bare: Vec<String> = names.iter().map(|n| n.split_once('/').map(|x| x.1).unwrap_or(n).to_string()).collect();
    let mut sets = Vec::new();
    let rel = release_base(&c.release);
    for p in pkgs {
        let Some(f) = find_rpm(&bare, p, &c.version, &rel) else {
            return Ok(Verdict::Unknown(format!("no {p}-{}-{rel} RPM built from this code in {}", c.version, ctx.rpms.display())));
        };
        let full = names.iter().find(|n| n.ends_with(&format!("/{f}"))).cloned().unwrap_or(f.clone());
        sets.push((f, rpm_files(&ctx.rpms.join(full))?));
    }
    let both = sets[0].1.intersection(&sets[1].1).count();
    let what = format!("`{}` and `{}`", sets[0].0, sets[1].0);
    Ok(if both > 0 { Verdict::Present(format!("{both} file(s) owned by both {what}")) } else { Verdict::Absent(format!("no file owned by both {what}")) })
}

pub fn probe(ctx: &mut Ctx, c: &Copy, package: &str, p: &Probe) -> Verdict {
    let r: Result<Verdict, String> = (|| match p {
        Probe::File { file, applies_if, present_if_all, present_if_none } => {
            let text = crate::specresolve::git_reader(ctx.repo, ctx.rev, &c.dir, None)(file);
            Ok(file_verdict(file, text.as_deref(), applies_if, present_if_all, present_if_none))
        }
        Probe::Upstream { commits } => {
            let (url, id) = source_commit(c)?;
            let dir = upstream_repo(ctx, &url, &id)?;
            let read = crate::specresolve::git_reader(ctx.repo, ctx.rev, &c.dir, None);
            let headers = listed_patch_headers(&spec_text(ctx, c, package).ok_or("the spec is unreadable")?, &read);
            let (mut n, mut picked, mut carried) = (0, 0, 0);
            for s in commits {
                // a fix the source's repository refuses ("not our ref") is not
                // an ancestor; any other fetch failure leaves it undecided
                let have = match upstream_repo(ctx, &url, s) {
                    Ok(_) => true,
                    Err(e) if e.contains("not our ref") => false,
                    Err(e) => return Err(e),
                };
                if let Some(how) = contains(&dir, s, &id, have)? {
                    n += 1;
                    picked += usize::from(how.starts_with("cherry"));
                } else if carried_by(&headers, s).is_some() {
                    carried += 1;
                }
            }
            let at = format!("the {} source ({})", c.version, &id[..10]);
            let v = upstream_verdict(n, carried, commits.len(), &at);
            Ok(match v {
                Verdict::Fixed(s) if picked > 0 => Verdict::Fixed(format!("{s}, {picked} as cherry-picks")),
                other => other,
            })
        }
        Probe::UpstreamFile { path, fixed_if } => {
            // the source as released: the copy's own patches are the upstream
            // probe's to see; this one asks whether the release has the code
            let (url, id) = source_commit(c)?;
            let dir = upstream_repo(ctx, &url, &id)?;
            let text = git(&dir, &["show", &format!("{id}:{path}")]).map_err(|_| format!("no {path} in the {} source", c.version))?;
            // positive-only: finding the fixed code says the release has it;
            // not finding it says nothing about the copy's own patches
            Ok(if fixed_if.matches(&text) {
                Verdict::Fixed(format!("the {} source's `{path}` has {}", c.version, fixed_if.show()))
            } else {
                Verdict::Unknown(format!("the {} source's `{path}` has no {}", c.version, fixed_if.show()))
            })
        }
        Probe::Series { defines, applies_if, expect_patch } => {
            let spec = spec_text(ctx, c, package).ok_or("the spec is unreadable")?;
            if let Some(p) = applies_if.iter().find(|p| !p.matches(&spec)) {
                return Ok(Verdict::NotApplicable(format!("the spec has no {}", p.show())));
            }
            series(ctx, c, package, defines, expect_patch.as_deref())
        }
        Probe::RpmOverlap { packages } => overlap(ctx, c, packages),
    })();
    r.unwrap_or_else(Verdict::Unknown)
}

// --- the symptom record ---------------------------------------------------------

/// pass/fail of one guest check over every stored run, and the last failure.
pub fn symptom(results: &Path, check: &str) -> String {
    let (mut pass, mut fail, mut info, mut last) = (0usize, 0usize, 0usize, String::new());
    let Ok(rows) = fs::read_dir(results) else { return "no results directory".into() };
    for row in rows.filter_map(|e| e.ok()) {
        let Ok(files) = fs::read_dir(row.path()) else { continue };
        for f in files.filter_map(|e| e.ok()) {
            let name = f.file_name().to_string_lossy().into_owned();
            let Some(stamp) = name.strip_prefix("checks-").and_then(|s| s.strip_suffix(".jsonl")) else { continue };
            let Ok(text) = fs::read_to_string(f.path()) else { continue };
            for l in text.lines() {
                let Ok(v) = serde_json::from_str::<serde_json::Value>(l) else { continue };
                if v.get("check").and_then(|x| x.as_str()) != Some(check) {
                    continue;
                }
                match v.get("status").and_then(|x| x.as_str()) {
                    Some("pass") => pass += 1,
                    Some("info") => info += 1,
                    Some("fail") => {
                        fail += 1;
                        if stamp > last.as_str() {
                            last = stamp.to_string();
                        }
                    }
                    _ => {}
                }
            }
        }
    }
    if pass + fail + info == 0 {
        return format!("`{check}`: no record");
    }
    if pass + fail == 0 {
        return format!("`{check}`: {info} informational record(s), no pass/fail");
    }
    let when = if last.len() >= 8 { format!(", last failure {}-{}-{}", &last[..4], &last[4..6], &last[6..8]) } else { String::new() };
    format!("`{check}`: {fail} fail / {pass} pass{when}")
}

// --- the report ----------------------------------------------------------------

pub struct PrReport {
    pub pr: u64,
    pub copies: Vec<Copy>,
    pub out_of_scope: Vec<Copy>,
    pub rows: Vec<(String, Vec<Verdict>, Option<String>)>,
}

impl PrReport {
    pub fn needed_in(&self) -> Vec<&Copy> {
        self.copies.iter().enumerate().filter(|(i, _)| self.rows.iter().any(|r| matches!(r.1[*i], Verdict::Present(_)))).map(|(_, c)| c).collect()
    }
    pub fn undecided(&self) -> bool {
        self.rows.iter().any(|r| r.1.iter().any(|v| matches!(v, Verdict::Unknown(_))))
    }
}

fn cell(s: &str) -> String {
    s.replace('|', "\\|").replace('\n', " ")
}

pub fn render(base: &str, title: &str, r: &PrReport) -> String {
    let mut o = format!("## #{} {}\n\nBase {base}. Copies: {}.", r.pr, title, r.copies.iter().map(Copy::label).collect::<Vec<_>>().join("; "));
    if !r.out_of_scope.is_empty() {
        o.push_str(&format!(" Outside the PR's subreleases, not probed: {}.", r.out_of_scope.iter().map(Copy::label).collect::<Vec<_>>().join("; ")));
    }
    o.push_str("\n\n");
    o.push_str("| Defect |");
    for c in &r.copies {
        o.push_str(&format!(" `{}` |", c.dir));
    }
    o.push_str(" Guest symptom record |\n|---|");
    for _ in &r.copies {
        o.push_str("---|");
    }
    o.push_str("---|\n");
    for (summary, v, sym) in &r.rows {
        o.push_str(&format!("| {} |", cell(summary)));
        for x in v {
            o.push_str(&format!(" {}: {} |", x.word(), cell(x.why())));
        }
        o.push_str(&format!(" {} |\n", cell(sym.as_deref().unwrap_or("-"))));
    }
    let need = r.needed_in();
    o.push('\n');
    if !need.is_empty() {
        o.push_str(&format!("**Still needed in:** {}.\n", need.iter().map(|c| format!("`{}`", c.dir)).collect::<Vec<_>>().join(", ")));
    } else if r.undecided() {
        o.push_str("**Undecided:** no defect is shown present, but a probe could not decide; see the cells marked unknown.\n");
    } else {
        o.push_str("**No defect present in any copy:** the PR's own symptom is gone on this base. Whether to close it is the user's decision.\n");
    }
    o
}

pub fn evaluate(ctx: &mut Ctx, def: &PrDef) -> Result<PrReport, String> {
    let all = copies(ctx.repo, ctx.rev, &def.package)?;
    let (copies, out_of_scope): (Vec<Copy>, Vec<Copy>) = all.into_iter().partition(|c| def.subreleases.map_or(true, |s| s.covers(&c.build_if)));
    if copies.is_empty() {
        return Err(format!("#{}: no copy of {} serves the PR's subreleases", def.pr, def.package));
    }
    let mut rows = Vec::new();
    for d in &def.defects {
        let mut v = Vec::new();
        for c in &copies {
            let per: Vec<Verdict> = d.probes.iter().map(|p| probe(ctx, c, &def.package, p)).collect();
            v.push(combine(&per));
        }
        rows.push((d.summary.clone(), v, None));
    }
    Ok(PrReport { pr: def.pr, copies, out_of_scope, rows })
}

pub fn cli(cfg: &crate::config::Config, args: &[String]) -> Result<(), String> {
    let mut want: Vec<u64> = Vec::new();
    let (mut rev, mut out, mut file) = (None, None, None);
    let mut i = 0;
    while i < args.len() {
        let next = |i: usize| args.get(i + 1).cloned().ok_or_else(|| format!("{} needs a value", args[i]));
        match args[i].as_str() {
            "--rev" => rev = Some(next(i)?),
            "--out" => out = Some(next(i)?),
            "--defects" => file = Some(next(i)?),
            "--pr" => want.push(next(i)?.trim_start_matches('#').parse().map_err(|_| "--pr takes a PR number")?),
            "-h" | "--help" => {
                println!("usage: sharukhan pr-eligibility [--pr <n>]... [--rev <base>] [--defects <pr-defects.json>] [--out <file.md>]");
                return Ok(());
            }
            a => return Err(format!("unknown argument {a}")),
        }
        i += 2;
    }
    let text = match &file {
        Some(f) => fs::read_to_string(f).map_err(|e| format!("{f}: {e}"))?,
        None => cfg.pr_defects.text()?.into_owned(),
    };
    let data = parse(&text)?;
    let rev = rev.unwrap_or_else(|| cfg.release.clone());
    let sha = git(&cfg.gate_repo, &["rev-parse", "--verify", &format!("{rev}^{{commit}}")])?.trim().to_string();
    let prs: Vec<&PrDef> = if want.is_empty() {
        data.prs.iter().collect()
    } else {
        want.iter().map(|n| data.prs.iter().find(|p| p.pr == *n).ok_or_else(|| format!("#{n} has no entry in the pr-defects data"))).collect::<Result<_, _>>()?
    };
    let check_prs = crate::evidence::load_attribution_file(&cfg.check_prs)?;
    let mut log = |l: &str| eprintln!("{l}");
    let mut ctx = Ctx {
        repo: &cfg.gate_repo,
        rev: &sha,
        cache: cfg.work.join("pr-eligibility"),
        scratch: crate::builder::shared_root().join("work"),
        sources: vec![cfg.build_root.join(&cfg.release).join("stage/SOURCES")],
        rpms: cfg.work.join("baseline-root").join(&cfg.release).join("stage/RPMS"),
        log: &mut log,
    };
    let mut doc = format!("# PR eligibility on {rev} ({})\n\n", &sha[..10]);
    doc.push_str("Each defect a PR fixes, probed in every copy of its package. \"present\": the defect is in the base; \"fixed upstream\": the source already has the fix; \"not applicable\": the copy has nothing the defect is about. A guest that passes without a PR is not evidence here.\n\n");
    for def in prs {
        (ctx.log)(&format!("#{}: {}", def.pr, def.package));
        let mut r = evaluate(&mut ctx, def)?;
        for (row, d) in r.rows.iter_mut().zip(&def.defects) {
            row.2 = d.symptom_check.as_ref().map(|c| {
                let attributed = check_prs.get(c.as_str()).map(|p| p.as_str());
                let rec = symptom(&cfg.results_dir, c);
                match attributed {
                    Some(p) if p != format!("PR#{}", def.pr) => format!("{rec} (attributed to {p})"),
                    _ => rec,
                }
            });
        }
        doc.push_str(&render(&format!("{rev} ({})", &sha[..10]), &def.title, &r));
        doc.push('\n');
    }
    match out {
        Some(p) => {
            let tmp = format!("{p}.tmp.{}", std::process::id());
            fs::write(&tmp, &doc).map_err(|e| format!("{tmp}: {e}"))?;
            fs::rename(&tmp, &p).map_err(|e| format!("{p}: {e}"))?;
            println!("wrote {p}");
        }
        None => print!("{doc}"),
    }
    Ok(())
}

// --- switch-check: every build variant's %prep -----------------------------------

/// Does a conditional block that tests `name` hold a Patch line? Only then can
/// turning the switch on change what %prep applies.
pub fn patches_behind(spec: &str, name: &str) -> bool {
    let forms = [format!("%{{?{name}}}"), format!("%{{{name}}}"), format!("%{{?{name}:")];
    let mut stack: Vec<bool> = Vec::new();
    for l in spec.lines().map(str::trim_start) {
        if l.starts_with("%if") {
            stack.push(forms.iter().any(|f| l.contains(f.as_str())));
        } else if l.starts_with("%elif") {
            if let Some(top) = stack.last_mut() {
                *top = *top || forms.iter().any(|f| l.contains(f.as_str()));
            }
        } else if l.starts_with("%endif") {
            stack.pop();
        } else if stack.iter().any(|b| *b) {
            if let Some((tag, _)) = l.split_once(':') {
                if tag.strip_prefix("Patch").is_some_and(|n| n.bytes().all(|b| b.is_ascii_digit())) {
                    return true;
                }
            }
        }
    }
    false
}

/// The packages at `rev` with a switch that guards a patch, from one pass of
/// git grep over the specs and a read of each candidate.
fn packages_with_switches(repo: &Path, rev: &str) -> Result<Vec<String>, String> {
    let out = Command::new("git")
        .arg("-C")
        .arg(repo)
        .args(["grep", "-l", "-E", r"^[[:space:]]*(%\{!\?[A-Za-z_][A-Za-z0-9_]*:|%(define|global)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+0[[:space:]]*$)", rev, "--", "SPECS/*.spec", "SPECS/*/*.spec", "SPECS/*/*/*.spec"])
        .output()
        .map_err(|e| format!("git grep: {e}"))?;
    if !out.status.success() && !out.stdout.is_empty() {
        return Err(format!("git grep failed: {}", String::from_utf8_lossy(&out.stderr).trim()));
    }
    let mut v = std::collections::BTreeSet::new();
    for l in String::from_utf8_lossy(&out.stdout).lines() {
        let path = l.split_once(':').map(|x| x.1).unwrap_or(l);
        let Some((dir, file)) = path.rsplit_once('/') else { continue };
        let pkg = dir.rsplit('/').next().unwrap_or("");
        if file != format!("{pkg}.spec") {
            continue;
        }
        let Ok(text) = git(repo, &["show", &format!("{rev}:{path}")]) else { continue };
        if crate::specswitch::switches(&text).iter().any(|s| patches_behind(&text, &s.name)) {
            v.insert(pkg.to_string());
        }
    }
    Ok(v.into_iter().collect())
}

/// One row of the switch check.
pub struct SwitchRow {
    pub copy: String,
    pub switch: String,
    pub kind: &'static str,
    pub result: Verdict,
}

pub fn switch_rows(ctx: &mut Ctx, package: &str) -> Result<Vec<SwitchRow>, String> {
    let mut rows = Vec::new();
    for c in copies(ctx.repo, ctx.rev, package)? {
        let spec = spec_text(ctx, &c, package).ok_or_else(|| format!("{}: unreadable", c.dir))?;
        for s in crate::specswitch::switches(&spec) {
            if !patches_behind(&spec, &s.name) {
                continue;
            }
            let mut d = BTreeMap::new();
            d.insert(s.name.clone(), "1".to_string());
            let result = series(ctx, &c, package, &d, None).unwrap_or_else(Verdict::Unknown);
            rows.push(SwitchRow { copy: c.label(), switch: s.name.clone(), kind: s.describe(), result });
        }
    }
    Ok(rows)
}

pub fn switch_cli(cfg: &crate::config::Config, args: &[String]) -> Result<(), String> {
    let (mut pkgs, mut all, mut rev, mut out) = (Vec::new(), false, None, None);
    let mut i = 0;
    while i < args.len() {
        let next = |i: usize| args.get(i + 1).cloned().ok_or_else(|| format!("{} needs a value", args[i]));
        match args[i].as_str() {
            "--package" => {
                let p = next(i)?;
                if !safe_rel(&p) || p.contains('/') {
                    return Err(format!("--package {p:?} is not a spec directory name"));
                }
                pkgs.push(p);
                i += 2;
            }
            "--all" => {
                all = true;
                i += 1;
            }
            "--rev" => {
                rev = Some(next(i)?);
                i += 2;
            }
            "--out" => {
                out = Some(next(i)?);
                i += 2;
            }
            "-h" | "--help" => {
                println!("usage: sharukhan switch-check (--package <name>... | --all) [--rev <base>] [--out <file.md>]");
                return Ok(());
            }
            a => return Err(format!("unknown argument {a}")),
        }
    }
    if pkgs.is_empty() == !all {
        return Err("name packages with --package, or --all; not both, not neither".into());
    }
    let rev = rev.unwrap_or_else(|| cfg.release.clone());
    let sha = git(&cfg.gate_repo, &["rev-parse", "--verify", &format!("{rev}^{{commit}}")])?.trim().to_string();
    if all {
        pkgs = packages_with_switches(&cfg.gate_repo, &sha)?;
    }
    let mut log = |l: &str| eprintln!("{l}");
    let mut ctx = Ctx {
        repo: &cfg.gate_repo,
        rev: &sha,
        cache: cfg.work.join("pr-eligibility"),
        scratch: crate::builder::shared_root().join("work"),
        sources: vec![cfg.build_root.join(&cfg.release).join("stage/SOURCES")],
        rpms: cfg.work.join("baseline-root").join(&cfg.release).join("stage/RPMS"),
        log: &mut log,
    };
    let mut doc = format!("# Build switches on {rev} ({})\n\nEvery switch that guards a patch, turned on, and the variant's %prep applied at fuzz 0 to the sha512-checked source. A switch fixed by a plain %define is set in a scratch copy of the spec: no build reaches it with -D, which is how such a variant goes stale.\n\n| Copy | Switch | Kind | %prep with the switch on |\n|---|---|---|---|\n", &sha[..10]);
    let mut broken = 0;
    for p in &pkgs {
        (ctx.log)(&format!("{p}"));
        for r in switch_rows(&mut ctx, p)? {
            broken += usize::from(matches!(r.result, Verdict::Present(_) | Verdict::Unknown(_)));
            let word = match &r.result {
                Verdict::Absent(_) => "builds",
                Verdict::Present(_) => "**broken**",
                _ => "undecided",
            };
            doc.push_str(&format!("| {} | `{}` | {} | {word}: {} |\n", cell(&r.copy), r.switch, r.kind, cell(r.result.why())));
        }
    }
    if pkgs.is_empty() {
        doc.push_str("| - | - | - | no spec has a switch that guards a patch |\n");
    }
    match out {
        Some(p) => {
            let tmp = format!("{p}.tmp.{}", std::process::id());
            fs::write(&tmp, &doc).map_err(|e| format!("{tmp}: {e}"))?;
            fs::rename(&tmp, &p).map_err(|e| format!("{p}: {e}"))?;
            println!("wrote {p}");
        }
        None => print!("{doc}"),
    }
    if broken > 0 {
        return Err(format!("{broken} switched variant(s) do not build their %prep or could not be decided"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_a_switch_guarding_a_patch_can_change_prep() {
        let spec = "%define STIG_HARDEN 0\n%define with_check 0\n%if 0%{?STIG_HARDEN}\nSource2: stig.conf\n%if 1\nPatch5: tmp.patch\n%endif\n%endif\n%if 0%{?with_check}\nBuildRequires: x\n%endif\n";
        assert!(patches_behind(spec, "STIG_HARDEN"));
        assert!(!patches_behind(spec, "with_check"));
        assert!(patches_behind("%if 0\n%elif %{a}\nPatch: p\n%endif\n", "a"));
        assert!(!patches_behind("%if 0%{?a}\n%endif\nPatch0: p\n", "a"));
    }

    fn pat_line(s: &str) -> Pat {
        Pat { line: Some(s.into()), prefix: None, contains: None }
    }
    fn pat_contains(s: &str) -> Pat {
        Pat { line: None, prefix: None, contains: Some(s.into()) }
    }

    #[test]
    fn the_builtin_data_parses() {
        let d = parse(BUILTIN_PR_DEFECTS).unwrap();
        assert!(!d.prs.is_empty());
    }

    #[test]
    fn data_mistakes_are_refused() {
        let base = |probes: &str| format!(r#"{{"prs":[{{"pr":1,"package":"p","defects":[{{"id":"a","summary":"s","probes":[{probes}]}}]}}]}}"#);
        assert!(parse(&base(r#"{"kind":"upstream","commits":["abc"]}"#)).unwrap_err().contains("40-hex"));
        assert!(parse(&base(r#"{"kind":"file","file":"../x","present_if_all":[{"line":"a"}]}"#)).unwrap_err().contains("relative"));
        assert!(parse(&base(r#"{"kind":"file","file":"x"}"#)).unwrap_err().contains("present_if"));
        assert!(parse(&base(r#"{"kind":"file","file":"x","present_if_all":[{"line":"a","prefix":"b"}]}"#)).unwrap_err().contains("exactly one"));
        assert!(parse(&base(r#"{"kind":"series","defines":{"a b":"1"}}"#)).unwrap_err().contains("macro"));
        assert!(parse(&base(r#"{"kind":"rpm-overlap","packages":["a"]}"#)).unwrap_err().contains("two"));
        assert!(parse(&base(r#"{"kind":"nonsense"}"#)).is_err());
        assert!(parse(r#"{"prs":[{"pr":1,"package":"p","defects":[]}]}"#).unwrap_err().contains("no defect"));
        let two = r#"{"prs":[{"pr":1,"package":"p","defects":[{"id":"a","summary":"s","probes":[{"kind":"file","file":"x","present_if_all":[{"line":"a"}]}]}]},{"pr":1,"package":"p","defects":[{"id":"a","summary":"s","probes":[{"kind":"file","file":"x","present_if_all":[{"line":"a"}]}]}]}]}"#;
        assert!(parse(two).unwrap_err().contains("twice"));
    }

    #[test]
    fn subrelease_ranges_read_as_photon_writes_them() {
        assert_eq!(range("%{photon_subrelease} >= 91 && %{photon_subrelease} <= 92"), (Some(91), Some(92)));
        assert_eq!(range("%{photon_subrelease} >= 93"), (Some(93), None));
        assert_eq!(range("%{photon_subrelease} <= 90"), (None, Some(90)));
        assert_eq!(range("%{photon_subrelease} < 91"), (None, Some(90)));
        assert_eq!(range("%{photon_subrelease} > 90"), (Some(91), None));
        assert_eq!(range(""), (None, None));
        assert_eq!(representative("%{photon_subrelease} <= 90"), Some(90));
        assert_eq!(range_text("%{photon_subrelease} >= 91 && %{photon_subrelease} <= 92"), "subreleases 91-92");
    }

    #[test]
    fn the_first_source_of_config_yaml_is_read() {
        let y = "sources:\n- archive: a-1.tar.gz\n  archive_sha512sum: ff\n  url: https://x/a.tar.gz\n  repo_url: https://github.com/o/a\n  commit_id: 0123456789012345678901234567890123456789\n- archive: b.tar.gz\n  url: https://other\n";
        let mut c = Copy::default();
        source_of(y, &mut c);
        assert_eq!(c.archive.as_deref(), Some("a-1.tar.gz"));
        assert_eq!(c.url.as_deref(), Some("https://x/a.tar.gz"));
        assert_eq!(c.repo_url.as_deref(), Some("https://github.com/o/a"));
        assert_eq!(c.commit_id.as_deref(), Some("0123456789012345678901234567890123456789"));
    }

    #[test]
    fn every_archive_is_read_and_a_folded_digest_too() {
        let y = "sources:\n- archive: linux-6.12.115.tar.xz\n  archive_type: upstream\n  url: https://cdn.kernel.org/x.tar.xz\n  commit_id: 03bae623ec326c2738198739625832aab0eb120a\n  skip_list: []\n  archive_sha512sum: \n    ea97aa\n  skip_validation: false\n- archive: second.tar.gz\n  archive_sha512sum: ff00\n";
        let a = archives_of(y);
        assert_eq!(a.len(), 2);
        assert_eq!(a[0].name, "linux-6.12.115.tar.xz");
        assert_eq!(a[0].sha512.as_deref(), Some("ea97aa"));
        assert_eq!(a[1].sha512.as_deref(), Some("ff00"));
        assert_eq!(a[1].url, None);
        let mut c = Copy::default();
        source_of(y, &mut c);
        assert_eq!(c.sha512.as_deref(), Some("ea97aa"));
        assert_eq!(c.archives.len(), 2);
        // a key with an empty value and a following key is not folded into it
        assert_eq!(archives_of("- archive: 'q.tar.xz'\n  archive_sha512sum: 'ce27'\n")[0].sha512.as_deref(), Some("ce27"));
        let z = archives_of("- archive: a\n  archive_sha512sum:\n  url: https://u\n");
        assert_eq!((z[0].sha512.as_deref(), z[0].url.as_deref()), (None, Some("https://u")));
    }

    #[test]
    fn sources_in_subdirectories_are_staged_by_name_as_photon_does() {
        let d = crate::safepath::test_base().join(format!("sharukhan-pe-{}-flat", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(d.join("CVE/deeper")).unwrap();
        fs::write(d.join("x.spec"), "s").unwrap();
        fs::write(d.join("CVE/a.patch"), "a").unwrap();
        fs::write(d.join("CVE/deeper/b.patch"), "b").unwrap();
        fs::write(d.join("CVE/x.spec"), "s").unwrap();
        assert_eq!(flatten_sources(&d).unwrap(), 2);
        assert_eq!(fs::read_to_string(d.join("a.patch")).unwrap(), "a");
        assert_eq!(fs::read_to_string(d.join("b.patch")).unwrap(), "b");
        fs::write(d.join("CVE/deeper/a.patch"), "other").unwrap();
        assert!(flatten_sources(&d).unwrap_err().contains("two different files"));
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn a_prep_failure_names_the_patch_it_was_applying() {
        let out = "Patch #0 (0001-a.patch):\n+ /usr/bin/patch -p1\nPatch #5 (harden-tmpfs-mount-options.patch):\n1 out of 1 hunk FAILED\nerror: Bad exit status\n";
        assert_eq!(failing_patch(out).as_deref(), Some("harden-tmpfs-mount-options.patch"));
        assert_eq!(failing_patch("error: x\n"), None);
        let auto = "+ /usr/lib/rpm/rpmuncompress /w/spec/0001-a.patch\n+ /usr/bin/patch -p1 -s --fuzz=0 --no-backup-if-mismatch -f\n+ /usr/lib/rpm/rpmuncompress /w/spec/harden-tmpfs-mount-options.patch\n+ /usr/bin/patch -p1 -s --fuzz=0 --no-backup-if-mismatch -f\n1 out of 1 hunk FAILED -- saving rejects to file units/tmp.mount.rej\nerror: Bad exit status from /w/tmp/rpm-tmp.x (%prep)\n";
        assert_eq!(failing_patch(auto).as_deref(), Some("harden-tmpfs-mount-options.patch"));
        assert_eq!(prep_reason(auto).as_deref(), Some("1 out of 1 hunk FAILED -- saving rejects to file units/tmp.mount.rej"));
        assert_eq!(missing_command("/w/tmp/rpm-tmp.J: line 61: dotnet: command not found\n").as_deref(), Some("dotnet"));
        assert_eq!(missing_command("error: Bad exit status\n"), None);
        assert_eq!(missing_command("<stdin>:1:10: fatal error: libelf.h: No such file or directory\n").as_deref(), Some("<libelf.h>"));
        assert_eq!(missing_command("cat: x.patch: No such file or directory\n"), None);
        let both = "<stdin>:1:10: fatal error: libelf.h: No such file or directory\n+ /usr/lib/rpm/rpmuncompress /w/1000-FIPS-canister-creation.patch\n1 out of 9 hunks FAILED -- saving rejects to file crypto/Makefile.rej\n";
        assert!(patch_failed(both));
        assert!(!patch_failed("<stdin>:1:10: fatal error: libelf.h: No such file or directory\n"));
        // a path is not mistaken for a patch name
        assert_eq!(failing_patch("+ cd /x/patches-dir\n"), None);
        assert_eq!(source_list("Source0: https://x/a-1.tar.gz\nSource: b.conf\nSourceX: no\nPatch0: p\n"), vec!["a-1.tar.gz", "b.conf"]);
    }

    #[test]
    fn file_probes_tell_present_absent_and_not_applicable() {
        let t = " SUBSYSTEM==\"accel\", GROUP=\"render\"\n-g render  5 -\n";
        let all = [pat_line(" SUBSYSTEM==\"accel\", GROUP=\"render\""), Pat { line: None, prefix: Some("-g render ".into()), contains: None }];
        assert!(matches!(file_verdict("p", Some(t), &[], &all, &[]), Verdict::Present(_)));
        let fixed = "-SUBSYSTEM==\"accel\", GROUP=\"render\"\n-g render  5 -\n";
        assert!(matches!(file_verdict("p", Some(fixed), &[], &all, &[]), Verdict::Absent(_)));
        assert!(matches!(file_verdict("p", None, &[], &all, &[]), Verdict::NotApplicable(_)));
        // a pin missing is the defect; the pin there is its absence
        let none = [pat_contains("-Dsystemd-journal-gid=")];
        assert!(matches!(file_verdict("s", Some("x\n"), &[], &[], &none), Verdict::Present(_)));
        assert!(matches!(file_verdict("s", Some("  -Dsystemd-journal-gid=23\n"), &[], &[], &none), Verdict::Absent(_)));
        // a copy without the variant the defect is about
        let applies = [pat_contains("STIG_HARDEN")];
        assert!(matches!(file_verdict("s", Some("x\n"), &applies, &[pat_line("x")], &[]), Verdict::NotApplicable(_)));
        // trailing blanks of the file do not hide a line
        assert!(pat_line("a").matches("a   \n"));
    }

    #[test]
    fn combining_never_lets_order_decide_a_contradiction() {
        let p = Verdict::Present("p".into());
        let f = Verdict::Fixed("f".into());
        let a = Verdict::Absent("a".into());
        let n = Verdict::NotApplicable("n".into());
        let u = Verdict::Unknown("u".into());
        assert!(matches!(combine(&[p.clone(), f.clone()]), Verdict::Unknown(_)));
        assert!(matches!(combine(&[f.clone(), p.clone()]), Verdict::Unknown(_)));
        assert_eq!(combine(&[p.clone(), a.clone()]), Verdict::Present("p".into()));
        assert_eq!(combine(&[f.clone(), a.clone()]), Verdict::Fixed("f".into()));
        assert_eq!(combine(&[a.clone(), u.clone()]), Verdict::Absent("a".into()));
        assert_eq!(combine(&[p, n.clone()]), n);
        assert!(matches!(combine(&[u]), Verdict::Unknown(_)));
    }

    #[test]
    fn a_scope_keeps_the_copies_serving_its_subreleases() {
        let s = Scope { from: Some(91), to: None };
        assert!(!s.covers("%{photon_subrelease} <= 90"));
        assert!(s.covers("%{photon_subrelease} >= 91 && %{photon_subrelease} <= 92"));
        assert!(s.covers("%{photon_subrelease} >= 93"));
        assert!(s.covers(""));
        let only92 = Scope { from: Some(92), to: Some(92) };
        assert!(only92.covers("%{photon_subrelease} >= 91 && %{photon_subrelease} <= 92"));
        assert!(!only92.covers("%{photon_subrelease} >= 93"));
        let bad = r#"{"prs":[{"pr":1,"package":"p","subreleases":{"from":93,"to":91},"defects":[{"id":"a","summary":"s","probes":[{"kind":"file","file":"x","present_if_all":[{"line":"a"}]}]}]}]}"#;
        assert!(parse(bad).unwrap_err().contains("empty"));
    }

    #[test]
    fn a_cherry_pick_counts_as_contained() {
        let d = crate::safepath::test_base().join(format!("sharukhan-pe-{}-pick", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        let g = |a: &[&str]| {
            let o = Command::new("git").arg("-C").arg(&d).args(a).output().unwrap();
            assert!(o.status.success(), "{a:?}");
            String::from_utf8_lossy(&o.stdout).trim().to_string()
        };
        g(&["init", "-q", "-b", "main"]);
        let c = |m: &str| g(&["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", m]);
        c("base");
        g(&["branch", "stable"]);
        c("fix on main");
        let fix = g(&["rev-parse", "HEAD"]);
        g(&["checkout", "-q", "stable"]);
        c(&format!("fix\n\n(cherry picked from commit {fix})"));
        let stable = g(&["rev-parse", "HEAD"]);
        g(&["checkout", "-q", "main"]);
        let main = g(&["rev-parse", "HEAD"]);
        assert_eq!(contains(&d, &fix, &main, true).unwrap().as_deref(), Some("ancestor"));
        assert!(contains(&d, &fix, &stable, true).unwrap().unwrap().starts_with("cherry-picked as "));
        // a commit the repository never had: only the trailer can bring it in
        assert!(contains(&d, &fix, &stable, false).unwrap().unwrap().starts_with("cherry-picked"));
        let base = g(&["rev-parse", "stable~1"]);
        assert_eq!(contains(&d, &fix, &base, true).unwrap(), None);
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn upstream_containment_is_all_or_present() {
        assert!(matches!(upstream_verdict(3, 0, 3, "x"), Verdict::Fixed(_)));
        assert!(matches!(upstream_verdict(0, 0, 3, "x"), Verdict::Present(_)));
        assert!(matches!(upstream_verdict(1, 0, 3, "x"), Verdict::Present(ref s) if s.contains("only 1 of 3")));
        assert!(matches!(upstream_verdict(1, 2, 3, "x"), Verdict::Absent(ref s) if s.contains("2 of 3")));
        assert!(matches!(upstream_verdict(0, 3, 3, "x"), Verdict::Absent(ref s) if s.contains("all 3") && s.contains("has none")));
        assert!(matches!(upstream_verdict(0, 2, 3, "x"), Verdict::Present(ref s) if s.contains("only 2 of 3")));
    }

    #[test]
    fn a_fix_the_copy_already_carries_is_found_in_its_patch_headers() {
        let sha = "6eaa5ba32231290971823d0ddf73bc712c384bcc";
        let files = |n: &str| match n {
            "0007-x.patch" => Some(format!("From {sha} Mon Sep 17 00:00:00 2001\nSubject: x\n---\ndiff --git a/f b/f\n+{sha}\n")),
            "0008-y.patch" => Some(format!("Subject: y\n---\ndiff --git a/f b/f\n+ mentions {sha} only in code\n")),
            _ => None,
        };
        let spec = "Patch0: 0007-x.patch\nPatch: 0008-y.patch\nPatch9: %{name}-macro.patch\nPatch10: ../escape.patch\n";
        let h = listed_patch_headers(spec, &files);
        assert_eq!(h.len(), 2);
        assert_eq!(carried_by(&h, sha), Some("0007-x.patch"));
        // a SHA in the diff body is code, not provenance
        assert_eq!(carried_by(&h[1..], sha), None);
    }

    #[test]
    fn the_patch_list_is_read_from_the_expanded_spec() {
        let e = "Name: x\nPatch0: 0001-a.patch\nPatch: 0002-unnumbered.patch\nPatch12: /abs/0003-b.patch\nPatchX: no\nSource0: s.tar.gz\n";
        assert_eq!(patch_list(e), vec!["0001-a.patch".to_string(), "0002-unnumbered.patch".to_string(), "0003-b.patch".to_string()]);
    }

    #[test]
    fn rpms_match_by_exact_name_and_version() {
        let n: Vec<String> = ["systemd-257.13-6.ph5.x86_64.rpm", "systemd-libs-257.13-6.ph5.x86_64.rpm", "systemd-journal-remote-257.13-6.ph5.x86_64.rpm", "systemd-257.13-6.ph5.src.rpm", "systemd-257.13-6.1.ph5.x86_64.rpm"].iter().map(|s| s.to_string()).collect();
        assert_eq!(find_rpm(&n, "systemd", "257.13", "6").as_deref(), Some("systemd-257.13-6.ph5.x86_64.rpm"));
        assert_eq!(find_rpm(&n, "systemd-journal-remote", "257.13", "6").as_deref(), Some("systemd-journal-remote-257.13-6.ph5.x86_64.rpm"));
        // 6.1 is another release, never mistaken for 6 or the other way round
        assert_eq!(find_rpm(&n, "systemd", "257.13", "6.1").as_deref(), Some("systemd-257.13-6.1.ph5.x86_64.rpm"));
        assert_eq!(find_rpm(&n, "systemd", "257.13", "6.2"), None);
        assert_eq!(find_rpm(&n, "systemd", "262.1", "1"), None);
        assert_eq!(release_base("6.1%{?dist}"), "6.1");
    }

    fn repo(tag: &str) -> PathBuf {
        let d = crate::safepath::test_base().join(format!("sharukhan-pe-{}-{tag}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        let g = |a: &[&str]| assert!(Command::new("git").arg("-C").arg(&d).args(a).output().unwrap().status.success(), "{a:?}");
        g(&["init", "-q", "-b", "5.0"]);
        for (dir, ver, cond) in [("SPECS/91/pkg", "1.0", "%{photon_subrelease} >= 91 && %{photon_subrelease} <= 92"), ("SPECS/pkg", "2.0", "%{photon_subrelease} >= 93"), ("SPECS/other", "9", "")] {
            let p = d.join(dir);
            fs::create_dir_all(&p).unwrap();
            let name = dir.rsplit('/').next().unwrap();
            fs::write(p.join(format!("{name}.spec")), format!("%global build_if {cond}\nName: {name}\nVersion:        {ver}\nRelease:        1%{{?dist}}\n")).unwrap();
            fs::write(p.join("config.yaml"), format!("sources:\n- archive: {name}-{ver}.tar.gz\n  archive_sha512sum: ab\n")).unwrap();
        }
        fs::write(d.join("SPECS/91/pkg/fix.patch"), " keep me\n").unwrap();
        g(&["add", "-A"]);
        g(&["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base"]);
        d
    }

    #[test]
    fn every_copy_of_a_package_is_found_with_its_range() {
        let d = repo("copies");
        let c = copies(&d, "5.0", "pkg").unwrap();
        assert_eq!(c.iter().map(|c| c.dir.as_str()).collect::<Vec<_>>(), vec!["SPECS/91/pkg", "SPECS/pkg"]);
        assert_eq!(c[0].version, "1.0");
        assert_eq!(c[0].archive.as_deref(), Some("pkg-1.0.tar.gz"));
        assert_eq!(c[1].label(), "`SPECS/pkg` 2.0-1, subrelease 93+");
        assert!(copies(&d, "5.0", "absent").is_err());
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn a_report_names_the_copies_that_still_need_the_pr() {
        let d = repo("eval");
        let mut log = |_: &str| {};
        let mut ctx = Ctx { repo: &d, rev: "5.0", cache: d.join("cache"), scratch: d.join("scratch"), sources: vec![], rpms: d.join("rpms"), log: &mut log };
        let def = PrDef {
            pr: 7,
            package: "pkg".into(),
            title: "t".into(),
            subreleases: None,
            defects: vec![Defect { id: "a".into(), summary: "keep line".into(), symptom_check: None, probes: vec![Probe::File { file: "fix.patch".into(), applies_if: vec![], present_if_all: vec![pat_line(" keep me")], present_if_none: vec![] }] }],
        };
        let r = evaluate(&mut ctx, &def).unwrap();
        assert!(matches!(r.rows[0].1[0], Verdict::Present(_)));
        assert!(matches!(r.rows[0].1[1], Verdict::NotApplicable(_)));
        assert_eq!(r.needed_in().iter().map(|c| c.dir.as_str()).collect::<Vec<_>>(), vec!["SPECS/91/pkg"]);
        let md = render("5.0 (x)", "t", &r);
        assert!(md.contains("**Still needed in:** `SPECS/91/pkg`."));
        assert!(md.contains("| keep line | **present**:"));
        // the overlap probe without a build of the copy's version cannot decide
        let v = probe(&mut ctx, &r.copies[0], "pkg", &Probe::RpmOverlap { packages: vec!["pkg".into(), "pkg-sub".into()] });
        assert!(matches!(v, Verdict::Unknown(_)));
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn the_symptom_record_counts_one_check_over_all_runs() {
        let d = crate::safepath::test_base().join(format!("sharukhan-pe-{}-sym", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(d.join("k01")).unwrap();
        fs::write(d.join("k01/checks-20261106T110224Z.jsonl"), "{\"check\":\"g.x\",\"status\":\"fail\"}\n{\"check\":\"g.x\",\"status\":\"pass\"}\n{\"check\":\"g.y\",\"status\":\"fail\"}\nnot json\n").unwrap();
        fs::write(d.join("k01/checks-20261101T000000Z.jsonl"), "{\"check\":\"g.x\",\"status\":\"fail\"}\n").unwrap();
        assert_eq!(symptom(&d, "g.x"), "`g.x`: 2 fail / 1 pass, last failure 2026-11-06");
        assert_eq!(symptom(&d, "g.z"), "`g.z`: no record");
        fs::write(d.join("k01/checks-20261102T000000Z.jsonl"), "{\"check\":\"g.i\",\"status\":\"info\"}\n").unwrap();
        assert_eq!(symptom(&d, "g.i"), "`g.i`: 1 informational record(s), no pass/fail");
        let _ = fs::remove_dir_all(&d);
    }
}
