//! `sharukhan iso-content`: what every ISO in a directory carries, as
//! Markdown beside it.
//!
//! Everything is read back, nothing is taken from a name alone:
//!
//! - the RPMs from the ISO itself (`/RPMS`, listed by xorriso);
//! - the base commit named in the file name, resolved in the gate repository
//!   or any build clone, with its subject, date and parents, and whether
//!   vmware/photon's and the fork's release branch contain it;
//! - what that commit's specs produce at the release's subrelease, so every
//!   RPM whose Version-Release differs from the base is found;
//! - for each such RPM, the PR heads of the fork (current, and every head a
//!   sync recorded) and the fork's `experimental/*` branches whose spec
//!   declares exactly that Version-Release. An RPM no candidate declares is
//!   listed as unattributed, never guessed;
//! - the cache record (`inputs.txt`, `photon.iso.sha256`) of a cache entry
//!   that links to the ISO, and the build log that stored it.

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};

use crate::config::Config;

/// Packages named in the summary table of every ISO, when it carries them.
const KEY_PACKAGES: &[&str] = &[
    "linux", "linux-esx", "linux-rt", "linux-fips-canister", "systemd", "glibc", "openssl", "rpm", "tdnf",
    "photon-os-installer", "stig-hardening", "cloud-init", "docker",
];

/// One RPM on an ISO.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct IsoRpm {
    pub arch: String,
    pub file: String,
    pub name: String,
    pub version: String,
    /// The release without the dist tag (`3` of `3.ph5`).
    pub release: String,
}

/// An ISO file name as sharukhan stores it:
/// `<type>-poi<variant>-<canister>[-hyperv...]__[<stamp>-]photon[-minimal]-5.0-<commit>.<arch>[-<n>].iso`.
#[derive(Debug, Default, PartialEq)]
pub struct IsoName {
    pub build: String,
    pub release: String,
    pub commit: String,
    pub arch: String,
}

pub fn parse_name(file: &str) -> IsoName {
    let mut n = IsoName::default();
    if let Some((b, _)) = file.split_once("__") {
        n.build = b.to_string();
    }
    let stem = file.rsplit("__").next().unwrap_or(file);
    let toks: Vec<&str> = stem.split('-').collect();
    for (i, t) in toks.iter().enumerate() {
        if t.chars().next().is_some_and(|c| c.is_ascii_digit()) && t.contains('.') && t.split('.').all(|p| p.chars().all(|c| c.is_ascii_digit())) && i + 1 < toks.len() {
            n.release = t.to_string();
            let rest = toks[i + 1];
            let (c, a) = rest.split_once('.').unwrap_or((rest, ""));
            if c.len() >= 7 && c.chars().all(|x| x.is_ascii_hexdigit()) {
                n.commit = c.to_string();
                n.arch = a.split(['.', '-']).next().unwrap_or("").to_string();
            }
            break;
        }
    }
    n
}

/// Every RPM under /RPMS of `iso`.
pub fn iso_rpms(iso: &Path) -> Result<Vec<IsoRpm>, String> {
    let o = Command::new("xorriso")
        .arg("-indev")
        .arg(iso)
        .args(["-find", "/RPMS", "-type", "f", "-name", "*.rpm"])
        .output()
        .map_err(|e| format!("running xorriso: {e}"))?;
    if !o.status.success() {
        return Err(format!("xorriso could not list {}: {}", iso.display(), String::from_utf8_lossy(&o.stderr).trim()));
    }
    let mut v = Vec::new();
    for l in String::from_utf8_lossy(&o.stdout).lines() {
        let p = l.trim().trim_matches('\'');
        let mut parts = p.rsplit('/');
        let (Some(file), Some(arch)) = (parts.next(), parts.next()) else { continue };
        let Some((name, version, rel)) = crate::buildexec::parse_rpm_name(file) else { continue };
        let release = rel.split(".ph").next().unwrap_or(&rel).to_string();
        v.push(IsoRpm { arch: arch.to_string(), file: file.to_string(), name, version, release });
    }
    v.sort();
    Ok(v)
}

/// `git cat-file --batch` on one repository: one process for every read.
struct Batch {
    child: Child,
    input: ChildStdin,
    output: BufReader<ChildStdout>,
}

impl Batch {
    fn open(repo: &Path) -> Result<Batch, String> {
        let mut child = Command::new("git")
            .arg("-C")
            .arg(repo)
            .args(["cat-file", "--batch"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| format!("git cat-file in {}: {e}", repo.display()))?;
        let input = child.stdin.take().ok_or("no stdin")?;
        let output = BufReader::new(child.stdout.take().ok_or("no stdout")?);
        Ok(Batch { child, input, output })
    }

    fn read(&mut self, spec: &str) -> Option<String> {
        writeln!(self.input, "{spec}").ok()?;
        self.input.flush().ok()?;
        let mut head = String::new();
        self.output.read_line(&mut head).ok()?;
        let f: Vec<&str> = head.split_whitespace().collect();
        if f.len() < 3 || f[1] != "blob" {
            return None;
        }
        let size: usize = f[2].parse().ok()?;
        let mut buf = vec![0u8; size + 1];
        self.output.read_exact(&mut buf).ok()?;
        buf.pop();
        Some(String::from_utf8_lossy(&buf).into_owned())
    }
}

impl Drop for Batch {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn git(repo: &Path, args: &[&str]) -> Option<String> {
    let o = Command::new("git").arg("-C").arg(repo).args(args).output().ok()?;
    o.status.success().then(|| String::from_utf8_lossy(&o.stdout).into_owned())
}

/// What a commit's specs produce: package -> (version, release, spec dir,
/// whether the Release carries a macro tail after its number, e.g. the kernel
/// version a driver package appends: `2%{?kernelsubrelease}` builds `2.0612115001`).
pub type Produced = BTreeMap<String, (String, String, String, bool)>;

/// The lines that name packages (`Name:`, `Version:`, `Release:`, `%package`)
/// with the spec's literal `%define`/`%global` macros expanded, `%ifarch` and
/// `%ifnarch` evaluated for `arch`. Any other conditional keeps both branches:
/// a package it guards is a candidate, never silently lost. A macro whose
/// value is not literal stays as written.
pub fn expand_names(text: &str, arch: &str) -> String {
    let mut macros: BTreeMap<String, String> = BTreeMap::new();
    let mut active: Vec<(bool, bool)> = Vec::new();
    let on = |a: &Vec<(bool, bool)>| a.iter().all(|(v, _)| *v);
    let subst = |line: &str, m: &BTreeMap<String, String>| -> String {
        let mut l = line.to_string();
        for _ in 0..4 {
            let before = l.clone();
            for (k, v) in m.iter() {
                l = l.replace(&format!("%{{{k}}}"), v).replace(&format!("%{{?{k}}}"), v);
            }
            if l == before {
                break;
            }
        }
        l
    };
    let mut out = String::new();
    for line in text.lines() {
        let t = line.trim();
        let word = t.split_whitespace().next().unwrap_or("");
        match word {
            "%ifarch" | "%ifnarch" => {
                let hit = t.split_whitespace().skip(1).any(|a| a == arch);
                active.push((if word == "%ifarch" { hit } else { !hit }, true));
                continue;
            }
            "%if" => {
                active.push((true, false));
                continue;
            }
            "%else" => {
                if let Some(top) = active.last_mut() {
                    if top.1 {
                        top.0 = !top.0;
                    }
                }
                continue;
            }
            "%endif" => {
                active.pop();
                continue;
            }
            _ => {}
        }
        if !on(&active) {
            continue;
        }
        if word == "%define" || word == "%global" {
            let mut f = t.splitn(3, char::is_whitespace);
            let (_, k, v) = (f.next(), f.next().unwrap_or(""), f.next().unwrap_or("").trim());
            let v = subst(v, &macros);
            if !k.is_empty() && !k.contains(['(', '{', '%', '?', '!']) && !v.is_empty() && !v.contains('%') {
                macros.insert(k.to_string(), v);
            }
            continue;
        }
        if t.starts_with("Name:") || t.starts_with("Version:") || t.starts_with("Release:") || word == "%package" {
            out.push_str(&subst(line, &macros));
        } else {
            out.push_str(line);
        }
        out.push('\n');
    }
    out
}

/// The number a Release starts with, and whether a macro other than the dist
/// tag follows it.
pub fn release_of(text: &str) -> Option<(String, bool)> {
    let raw = text.lines().find(|l| l.starts_with("Release:"))?.split_whitespace().nth(1)?.to_string();
    let num: String = raw.chars().take_while(|c| c.is_ascii_digit() || *c == '.').collect();
    let num = num.trim_end_matches('.').to_string();
    if num.is_empty() {
        return None;
    }
    let tail = raw[num.len()..].replace("%{?dist}", "");
    Some((num, !tail.is_empty()))
}

/// Does an ISO release (`2.0612115001`) match a spec's (`2`, macro tail)?
pub fn release_matches(iso: &str, spec: &str, tail: bool) -> bool {
    iso == spec || (tail && iso.strip_prefix(spec).is_some_and(|r| r.starts_with('.')))
}

/// The specs of `dirs` (all of SPECS when None) at `rev`, read through one
/// batch process; a package two specs claim is dropped.
fn produced_at(repo: &Path, rev: &str, sub: Option<u32>, arch: &str, dirs: Option<&BTreeSet<String>>) -> Produced {
    let mut out = Produced::new();
    let Some(list) = git(repo, &["ls-tree", "-r", "--name-only", rev, "--", "SPECS"]) else { return out };
    let Ok(batch) = Batch::open(repo) else { return out };
    let batch = std::cell::RefCell::new(batch);
    let mut doubled = BTreeSet::new();
    for path in list.lines().filter(|p| p.ends_with(".spec")) {
        let Some((dir, file)) = path.rsplit_once('/') else { continue };
        if dirs.is_some_and(|d| !d.contains(dir)) {
            continue;
        }
        let read = |name: &str| batch.borrow_mut().read(&format!("{rev}:{dir}/{name}"));
        let Some(text) = crate::specresolve::resolve(&read, file, sub) else { continue };
        if !crate::buildexec::builds_at(&text, sub) {
            continue;
        }
        let text = expand_names(&text, arch);
        let Some(fams) = crate::buildexec::spec_families_text(&text) else { continue };
        let Some((rel, tail)) = release_of(&text) else { continue };
        for p in fams.families {
            if out.insert(p.clone(), (fams.version.clone(), rel.clone(), dir.to_string(), tail)).is_some() {
                doubled.insert(p);
            }
        }
    }
    for d in doubled {
        out.remove(&d);
    }
    out
}

/// A candidate source of an RPM that differs from the base.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct Source {
    /// `#95` or `experimental/systemd-262.2`.
    pub label: String,
    pub title: String,
    pub branch: String,
}

/// Every git repository the builds use: the gate repository and each clone
/// below the build root and the work directory (three levels).
fn repos(cfg: &Config) -> Vec<PathBuf> {
    let mut v = vec![cfg.gate_repo.clone()];
    let mut walk = |root: &Path| {
        let mut stack = vec![(root.to_path_buf(), 0)];
        while let Some((d, depth)) = stack.pop() {
            if d.join(".git").exists() {
                v.push(d.clone());
                continue;
            }
            if depth >= 3 {
                continue;
            }
            if let Ok(rd) = fs::read_dir(&d) {
                for e in rd.flatten() {
                    if e.file_type().is_ok_and(|t| t.is_dir()) {
                        stack.push((e.path(), depth + 1));
                    }
                }
            }
        }
    };
    walk(&cfg.build_root);
    walk(&cfg.work.join("sbuild"));
    walk(&cfg.work.join("kbuild"));
    walk(&cfg.work.join("baseline-root"));
    // the gate repository first: a commit it has is named as upstream's or
    // the fork's, not as a build clone's
    let gate = v.remove(0);
    v.sort();
    v.dedup();
    v.retain(|r| r != &gate);
    v.insert(0, gate);
    v
}

/// The repository that has `commit`, and its full id.
fn resolve_commit(repos: &[PathBuf], commit: &str) -> Option<(PathBuf, String)> {
    for r in repos {
        if let Some(full) = git(r, &["rev-parse", "--verify", "-q", &format!("{commit}^{{commit}}")]) {
            return Some((r.clone(), full.trim().to_string()));
        }
    }
    None
}

/// Index: "name-version-release" -> the candidates whose spec declares it.
fn candidate_index(cfg: &Config, base_ref: &str, arch: &str, log: &mut dyn FnMut(&str)) -> BTreeMap<String, BTreeSet<Source>> {
    let repo = &cfg.gate_repo;
    let mut heads: BTreeMap<String, BTreeSet<Source>> = BTreeMap::new();
    let mut add = |commit: &str, s: Source| {
        if !commit.is_empty() {
            heads.entry(commit.to_string()).or_default().insert(s);
        }
    };
    // the fork's PRs, open and closed, as GitHub names them now
    let mut titles: BTreeMap<u64, (String, String)> = BTreeMap::new();
    match Command::new("gh")
        .args(["pr", "list", "-R", &cfg.fork, "--state", "all", "--limit", "500", "--json", "number,title,headRefName,headRefOid"])
        .output()
    {
        Ok(o) if o.status.success() => {
            if let Ok(serde_json::Value::Array(a)) = serde_json::from_slice::<serde_json::Value>(&o.stdout) {
                for p in a {
                    let n = p["number"].as_u64().unwrap_or(0);
                    let t = p["title"].as_str().unwrap_or("").to_string();
                    let b = p["headRefName"].as_str().unwrap_or("").to_string();
                    titles.insert(n, (t.clone(), b.clone()));
                    add(p["headRefOid"].as_str().unwrap_or(""), Source { label: format!("#{n}"), title: t, branch: b });
                }
            }
        }
        _ => log(&format!("  [warn] gh pr list -R {} failed: PRs are matched from the sync records only", cfg.fork)),
    }
    // every head a sync recorded (a PR before and after each rebase)
    if let Ok(db) = rusqlite::Connection::open_with_flags(&cfg.memory_db, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY) {
        if let Ok(mut st) = db.prepare("select distinct number, branch, gh_head, coalesce(new_head,'') from sync_pr") {
            let rows: Vec<(u64, String, String, String)> = st
                .query_map([], |r| Ok((r.get::<_, i64>(0)? as u64, r.get(1)?, r.get(2)?, r.get(3)?)))
                .map(|it| it.flatten().collect())
                .unwrap_or_default();
            for (n, b, h, nh) in rows {
                let t = titles.get(&n).map(|x| x.0.clone()).unwrap_or_default();
                for c in [h, nh] {
                    let full = git(repo, &["rev-parse", "--verify", "-q", &format!("{c}^{{commit}}")]).map(|s| s.trim().to_string());
                    if let Some(f) = full {
                        add(&f, Source { label: format!("#{n}"), title: t.clone(), branch: b.clone() });
                    }
                }
            }
        }
    }
    // the gate repository's own port branches, pushed or not
    if let Some(ls) = git(repo, &["for-each-ref", "--format=%(objectname)\t%(refname)", "refs/heads/experimental/"]) {
        for l in ls.lines() {
            if let Some((c, r)) = l.split_once('\t') {
                let b = r.trim_start_matches("refs/heads/").to_string();
                add(c, Source { label: b.clone(), title: format!("port branch {b}"), branch: b });
            }
        }
    }
    // the fork's experimental branches (kernel and systemd ports)
    if let Some(ls) = git(repo, &["ls-remote", &format!("https://github.com/{}.git", cfg.fork), "refs/heads/experimental/*"]) {
        for l in ls.lines() {
            if let Some((c, r)) = l.split_once('\t') {
                let b = r.trim_start_matches("refs/heads/").to_string();
                if git(repo, &["cat-file", "-e", &format!("{c}^{{commit}}")]).is_some() {
                    add(c, Source { label: b.clone(), title: format!("port branch {b}"), branch: b });
                }
            }
        }
    }
    log(&format!("  {} candidate head(s) to read", heads.len()));
    let mut index: BTreeMap<String, BTreeSet<Source>> = BTreeMap::new();
    for (commit, sources) in heads {
        let Some(mb) = git(repo, &["merge-base", &commit, base_ref]) else { continue };
        let Some(names) = git(repo, &["diff", "--name-only", mb.trim(), &commit, "--", "SPECS"]) else { continue };
        let dirs: BTreeSet<String> = names.lines().filter_map(|p| p.rsplit_once('/').map(|(d, _)| d.to_string())).filter(|d| d != "SPECS").collect();
        if dirs.is_empty() {
            continue;
        }
        let sub = git(repo, &["show", &format!("{commit}:build-config.json")]).and_then(|t| crate::specresolve::subrelease_in(&t));
        for (pkg, (v, r, _, tail)) in produced_at(repo, &commit, sub, arch, Some(&dirs)) {
            let key = if tail { format!("{pkg}-{v}-{r}.*") } else { format!("{pkg}-{v}-{r}") };
            index.entry(key).or_default().extend(sources.iter().cloned());
        }
    }
    index
}

/// The cache entry that links to `iso`, if any: its directory.
fn cache_entry(cfg: &Config, iso: &Path) -> Option<PathBuf> {
    let target = fs::canonicalize(iso).ok()?;
    let mut stack = vec![(cfg.iso_cache.clone(), 0)];
    let mut found: Option<(PathBuf, bool)> = None;
    while let Some((d, depth)) = stack.pop() {
        let Ok(rd) = fs::read_dir(&d) else { continue };
        for e in rd.flatten() {
            let p = e.path();
            let Ok(ft) = e.file_type() else { continue };
            if ft.is_dir() && depth < 3 {
                stack.push((p, depth + 1));
            } else if ft.is_symlink() && fs::canonicalize(&p).ok().as_ref() == Some(&target) {
                let current = p.file_name().is_some_and(|n| n == "photon.iso");
                if found.as_ref().is_none_or(|(_, c)| !c && current) {
                    found = Some((d.clone(), current));
                }
            }
        }
    }
    found.map(|(d, _)| d)
}

/// The build log of `iso`: the log of the build that a driver log (a build
/// log itself, a sync stage's log, or a run log) names last before the line
/// that stored `iso`; that driver log when it names no build log.
fn build_log(cfg: &Config, iso: &Path) -> Option<PathBuf> {
    let name = iso.file_name()?.to_string_lossy().into_owned();
    let mut logs: Vec<PathBuf> = Vec::new();
    let mut add_dir = |d: &Path| {
        if let Ok(rd) = fs::read_dir(d) {
            logs.extend(rd.flatten().map(|e| e.path()).filter(|p| p.extension().is_some_and(|x| x == "log")));
        }
    };
    add_dir(&cfg.build_log_dir);
    add_dir(&cfg.run_log_dir);
    if let Ok(rd) = fs::read_dir(cfg.results_dir.join("sync")) {
        for e in rd.flatten() {
            add_dir(&e.path());
        }
    }
    logs.sort_by_key(|p| fs::metadata(p).and_then(|m| m.modified()).ok());
    for l in logs.into_iter().rev() {
        let Ok(t) = fs::read_to_string(&l) else { continue };
        let lines: Vec<&str> = t.lines().collect();
        let Some(at) = lines.iter().position(|x| x.contains("stored in") && x.contains(&name)) else { continue };
        let named = lines[..at].iter().rev().find_map(|x| {
            let (_, rest) = x.split_once(" -> ")?;
            let p = rest.split_whitespace().next()?;
            (p.ends_with(".log") && p.starts_with(&*cfg.build_log_dir.to_string_lossy())).then(|| PathBuf::from(p))
        });
        return Some(named.filter(|p| p.is_file()).unwrap_or(l));
    }
    produced_by(cfg, iso, &name)
}

/// A `run`-driven build logs no "stored in" line: the build log of the same
/// build whose "produced" line, or the image builder's "Generating Iso:"
/// line, names this ISO's delivered name (the stored name without the build
/// prefix and store stamp), written at most ten minutes after the ISO; the
/// latest such log.
fn produced_by(cfg: &Config, iso: &Path, name: &str) -> Option<PathBuf> {
    let (build, rest) = name.split_once("__")?;
    let delivered = match rest.split_once('-') {
        Some((stamp, r)) if stamp.len() == 16 && stamp.ends_with('Z') && stamp.contains('T') => r,
        _ => rest,
    };
    let iso_t = fs::metadata(iso).and_then(|m| m.modified()).ok()?;
    let limit = iso_t + std::time::Duration::from_secs(600);
    let mut best: Option<(std::time::SystemTime, PathBuf)> = None;
    for e in fs::read_dir(&cfg.build_log_dir).ok()?.flatten() {
        let p = e.path();
        if p.extension().is_none_or(|x| x != "log") || !p.file_name().is_some_and(|n| n.to_string_lossy().starts_with(build)) {
            continue;
        }
        let Ok(t) = fs::metadata(&p).and_then(|m| m.modified()) else { continue };
        if t > limit || best.as_ref().is_some_and(|(b, _)| *b >= t) {
            continue;
        }
        let Ok(text) = fs::read_to_string(&p) else { continue };
        let hit = text.lines().any(|l| {
            (l.contains("produced ") && l.contains(&format!("/{build}/{delivered}"))) || l.contains(&format!("Generating Iso: /workdir/{delivered}"))
        });
        if hit {
            best = Some((t, p));
        }
    }
    best.map(|(_, p)| p)
}

/// `YYYY-MM-DDTHH:MM:SSZ` of a Unix time.
fn utc(secs: u64) -> String {
    let (y, m, d) = crate::wrapper::escape::civil_from_days((secs / 86400) as i64);
    let t = secs % 86400;
    format!("{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}Z", t / 3600, t % 3600 / 60, t % 60)
}

/// A kernel-spec RPM (`dir` is the base's kernel directory) that sharukhan
/// built differently from the base: an Azure remaster (`.azure` Release), a
/// kernel profile (the `<kernel>_` prefix of the build name, e.g. `7.3_`), or
/// a `canister=equivalent` rebuild (same Version, Release bumped).
pub fn kernel_source(build: &str, dir: &str, base_version: &str, version: &str, release: &str, port_branches: &[String]) -> Option<Source> {
    if dir.rsplit('/').next() != Some("linux") {
        return None;
    }
    if release.ends_with(".azure") {
        return Some(Source { label: "remaster: Azure".into(), title: "kernel rebuilt by sharukhan remaster with the Hyper-V fragment (.azure Release)".into(), branch: "-".into() });
    }
    if version != base_version {
        // the profile is the build-name prefix (`7.3_`), else the port branch
        // of the kernel's major.minor
        let mm: String = version.split('.').take(2).collect::<Vec<_>>().join(".");
        let k = build.split_once('_').map(|(k, _)| k.to_string()).filter(|k| !k.is_empty() && version.starts_with(k.as_str()))
            .or_else(|| port_branches.iter().any(|b| *b == format!("experimental/linux-{mm}")).then_some(mm));
        if let Some(k) = k {
            let b = format!("experimental/linux-{k}");
            return Some(Source { label: format!("kernel profile {k}"), title: format!("sharukhan --kernel {k}: kernel version pinned on {b}"), branch: b });
        }
    }
    if build.contains("-equivalent") && version == base_version {
        return Some(Source { label: "canister=equivalent".into(), title: "kernel rebuilt by sharukhan against a locally built FIPS canister (Release bumped)".into(), branch: "-".into() });
    }
    None
}

/// The tag a kernel module's Release carries for kernel `version`-`release`:
/// 6.12.115-2 is `0612115002`.
pub fn kernel_tag(version: &str, release: &str) -> Option<String> {
    let v: Vec<u32> = version.split('.').map(|x| x.parse().ok()).collect::<Option<Vec<u32>>>()?;
    let r: u32 = release.split('.').next()?.parse().ok()?;
    (v.len() == 3).then(|| format!("{:02}{:02}{:03}{:03}", v[0], v[1], v[2], r))
}

fn md_escape(s: &str) -> String {
    s.replace('|', "\\|")
}

/// Everything known about one ISO, ready to be written.
pub struct Report {
    pub file: String,
    pub size: u64,
    pub modified: String,
    pub name: IsoName,
    pub base: Option<(String, String, String)>,
    pub base_note: Vec<String>,
    pub rpms: Vec<IsoRpm>,
    pub from_sources: BTreeMap<Source, Vec<String>>,
    pub unattributed: Vec<String>,
    /// Out-of-tree modules built with a kernel: their Release ends in that
    /// kernel's Version-Release (`.0612115002` is linux 6.12.115-2).
    pub kernel_bound: BTreeMap<String, Vec<String>>,
    pub base_unknown: bool,
    pub inputs: Option<String>,
    pub sha256: Option<String>,
    pub log: Option<String>,
}

impl Report {
    pub fn markdown(&self) -> String {
        let mut m = format!("# {}\n\n", self.file);
        m.push_str("| | |\n|---|---|\n");
        m.push_str(&format!("| Build | `{}` |\n", if self.name.build.is_empty() { "-" } else { &self.name.build }));
        m.push_str(&format!("| Release | {} |\n", if self.name.release.is_empty() { "-" } else { &self.name.release }));
        m.push_str(&format!("| Architecture | {} |\n", if self.name.arch.is_empty() { "-" } else { &self.name.arch }));
        m.push_str(&format!("| Size | {:.2} GB |\n", self.size as f64 / 1e9));
        m.push_str(&format!("| Written | {} |\n", self.modified));
        m.push_str(&format!("| sha256 | {} |\n", self.sha256.as_deref().map(|s| format!("`{s}`")).unwrap_or_else(|| "not recorded (no cache entry links to this file)".into())));
        m.push_str(&format!("| Build log | {} |\n", self.log.as_deref().map(|s| format!("`{s}`")).unwrap_or_else(|| "not found".into())));
        m.push_str(&format!("| RPMs | {} |\n\n", self.rpms.len()));

        m.push_str("## Base commit\n\n");
        match &self.base {
            Some((full, date, subject)) => {
                m.push_str(&format!("`{full}` ({date}): {}\n\n", md_escape(subject)));
            }
            None => m.push_str(&format!("`{}` is in none of the repositories this host builds from.\n\n", self.name.commit)),
        }
        for n in &self.base_note {
            m.push_str(&format!("- {n}\n"));
        }
        if !self.base_note.is_empty() {
            m.push('\n');
        }

        m.push_str("## Key packages\n\n| Package | Version-Release |\n|---|---|\n");
        for k in KEY_PACKAGES {
            let hits: Vec<String> = self.rpms.iter().filter(|r| r.name == *k).map(|r| format!("{}-{}", r.version, r.release)).collect::<BTreeSet<_>>().into_iter().collect();
            if !hits.is_empty() {
                m.push_str(&format!("| {k} | {} |\n", hits.join(", ")));
            }
        }
        m.push('\n');

        m.push_str("## Changes against the base\n\n");
        if self.base_unknown {
            m.push_str("The base commit is not resolvable here, so no RPM can be compared with it.\n\n");
        } else if self.from_sources.is_empty() && self.unattributed.is_empty() {
            m.push_str("None: every RPM is the Version-Release its base commit's spec declares.\n\n");
        } else {
            m.push_str("RPMs whose Version-Release differs from what the base commit's specs declare, by the PR or branch whose spec declares exactly that Version-Release. Stacked PRs carry their parent's specs, so an RPM can be listed under each PR of a stack.\n\n");
            if !self.from_sources.is_empty() {
                m.push_str("| PR / branch | Title | Branch | RPMs |\n|---|---|---|---|\n");
                for (s, rpms) in &self.from_sources {
                    let label = if s.branch == "-" {
                        s.label.clone()
                    } else if s.label.starts_with('#') {
                        format!("[{}](https://github.com/dcasota/photon/pull/{})", s.label, &s.label[1..])
                    } else {
                        format!("[{}](https://github.com/dcasota/photon/tree/{})", s.label, s.branch)
                    };
                    m.push_str(&format!("| {label} | {} | `{}` | {} |\n", md_escape(&s.title), s.branch, rpms.join("<br>")));
                }
                m.push('\n');
            }
            for (k, pkgs) in &self.kernel_bound {
                m.push_str(&format!("Built against {k}, their Release carries the kernel's ({}): {}\n\n", pkgs.len(), pkgs.join(", ")));
            }
            if !self.unattributed.is_empty() {
                m.push_str(&format!(
                    "Differs from the base, declared by no PR head or port branch known here ({}): {}\n\n",
                    self.unattributed.len(),
                    self.unattributed.join(", ")
                ));
            }
        }

        if let Some(i) = &self.inputs {
            m.push_str("## Build inputs (cache record)\n\n```\n");
            m.push_str(i.trim_end());
            m.push_str("\n```\n\n");
        }

        m.push_str(&format!("<details><summary>All {} RPMs</summary>\n\n", self.rpms.len()));
        for r in &self.rpms {
            m.push_str(&format!("- {}/{}\n", r.arch, r.file));
        }
        m.push_str("\n</details>\n");
        m
    }
}

/// The report of one ISO.
fn report(
    cfg: &Config,
    iso: &Path,
    repos: &[PathBuf],
    produced: &mut BTreeMap<String, Produced>,
    index: &BTreeMap<String, BTreeSet<Source>>,
    upstream_head: &str,
    fork_head: &str,
) -> Result<Report, String> {
    let file = iso.file_name().unwrap_or_default().to_string_lossy().into_owned();
    let meta = fs::metadata(iso).map_err(|e| format!("{}: {e}", iso.display()))?;
    let modified = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| utc(d.as_secs()))
        .unwrap_or_default();
    let name = parse_name(&file);
    let rpms = iso_rpms(iso)?;
    let mut base_note = Vec::new();
    let resolved = if name.commit.is_empty() { None } else { resolve_commit(repos, &name.commit) };
    let base = resolved.as_ref().and_then(|(r, full)| {
        let l = git(r, &["log", "-1", "--format=%cs%x09%s%x09%P", full])?;
        let mut f = l.trim().splitn(3, '\t');
        let (d, s, p) = (f.next()?.to_string(), f.next()?.to_string(), f.next().unwrap_or("").to_string());
        let parents: Vec<&str> = p.split_whitespace().collect();
        if parents.len() > 1 {
            for par in &parents {
                let ps = git(r, &["log", "-1", "--format=%h %cs %s", par]).unwrap_or_default();
                base_note.push(format!("merge parent `{}`", md_escape(ps.trim())));
            }
        }
        for (label, head) in [("vmware/photon 5.0", upstream_head), ("dcasota/photon 5.0", fork_head)] {
            if head.is_empty() {
                continue;
            }
            let has = git(&cfg.gate_repo, &["merge-base", "--is-ancestor", full, head]).is_some();
            let is_head = full == head;
            base_note.push(format!("{label}: {}", if is_head { "is this commit (its head)".to_string() } else if has { "contains this commit".to_string() } else { "does not contain this commit".to_string() }));
        }
        if r != &cfg.gate_repo {
            base_note.push(format!("found in the build clone `{}`", r.display()));
        }
        // a base outside the release branch: where it leaves it, and the
        // port branch it belongs to (contains it, or has its tree at the head)
        if !upstream_head.is_empty() && git(&cfg.gate_repo, &["merge-base", "--is-ancestor", full, upstream_head]).is_none() {
            let first = if parents.len() > 1 { parents.iter().find(|p| git(&cfg.gate_repo, &["cat-file", "-e", &format!("{p}^{{commit}}")]).is_some()).map(|p| p.to_string()) } else { Some(full.clone()) };
            if let Some(mb) = first.and_then(|c| git(&cfg.gate_repo, &["merge-base", &c, upstream_head])) {
                let ms = git(&cfg.gate_repo, &["log", "-1", "--format=%h %cs %s", mb.trim()]).unwrap_or_default();
                base_note.push(format!("branches off vmware/photon 5.0 at `{}`", md_escape(ms.trim())));
            }
            let tree = git(r, &["rev-parse", &format!("{full}^{{tree}}")]).map(|t| t.trim().to_string()).unwrap_or_default();
            for b in git(&cfg.gate_repo, &["for-each-ref", "--format=%(refname:short) %(objectname:short) %(tree)", "refs/heads/experimental/"]).unwrap_or_default().lines() {
                let mut f = b.split_whitespace();
                let (Some(name), Some(head), Some(t)) = (f.next(), f.next(), f.next()) else { continue };
                if git(&cfg.gate_repo, &["merge-base", "--is-ancestor", full, name]).is_some() {
                    base_note.push(format!("port branch `{name}` contains this commit"));
                } else if !tree.is_empty() && t == tree {
                    base_note.push(format!("port branch `{name}`: its head `{head}` has exactly this tree"));
                }
            }
        }
        Some((full.clone(), d, s))
    });
    let mut from_sources: BTreeMap<Source, Vec<String>> = BTreeMap::new();
    let port_branches: Vec<String> = git(&cfg.gate_repo, &["for-each-ref", "--format=%(refname:short)", "refs/heads/experimental/"])
        .map(|t| t.lines().map(str::to_string).collect())
        .unwrap_or_default();
    let mut unattributed = Vec::new();
    let mut kernel_bound: BTreeMap<String, Vec<String>> = BTreeMap::new();
    let base_unknown = resolved.is_none();
    if let Some((repo, full)) = &resolved {
        if !produced.contains_key(full) {
            let sub = git(repo, &["show", &format!("{full}:build-config.json")]).and_then(|t| crate::specresolve::subrelease_in(&t));
            let arch = if name.arch.is_empty() { std::env::consts::ARCH } else { name.arch.as_str() };
            produced.insert(full.clone(), produced_at(repo, full, sub, arch, None));
        }
        let made = &produced[full];
        let tags: Vec<(String, String)> = rpms
            .iter()
            .filter(|r| r.name == "linux" || r.name == "linux-esx")
            .filter_map(|r| kernel_tag(&r.version, &r.release).map(|t| (t, format!("{}-{}-{}", r.name, r.version, r.release))))
            .collect();
        let mut seen = BTreeSet::new();
        for r in &rpms {
            if r.name.ends_with("-debuginfo") || !seen.insert((r.name.clone(), r.version.clone(), r.release.clone())) {
                continue;
            }
            let base_has = made.get(&r.name);
            if base_has.is_some_and(|(v, rel, _, tail)| *v == r.version && release_matches(&r.release, rel, *tail)) {
                continue;
            }
            let key = format!("{}-{}-{}", r.name, r.version, r.release);
            // the kernel specs: how sharukhan built them, from what the ISO says
            if let Some(src) = base_has.and_then(|(v, _, dir, _)| kernel_source(&name.build, dir, v, &r.version, &r.release, &port_branches)) {
                from_sources.entry(src).or_default().push(key);
                continue;
            }
            if let Some((_, k)) = tags.iter().find(|(t, _)| r.release.ends_with(&format!(".{t}"))) {
                kernel_bound.entry(k.clone()).or_default().push(key);
                continue;
            }
            let pre = r.release.split('.').next().unwrap_or("");
            let found = index.get(&key).or_else(|| index.get(&format!("{}-{}-{pre}.*", r.name, r.version)));
            match found {
                Some(srcs) => {
                    for s in srcs {
                        from_sources.entry(s.clone()).or_default().push(key.clone());
                    }
                }
                None => unattributed.push(key),
            }
        }
    }
    let entry = cache_entry(cfg, iso);
    let inputs = entry.as_ref().and_then(|d| fs::read_to_string(d.join(crate::build::INPUTS_FILE)).ok());
    let sha256 = entry.as_ref().and_then(|d| {
        let cur = fs::canonicalize(d.join("photon.iso")).ok()?;
        (cur == fs::canonicalize(iso).ok()?).then(|| fs::read_to_string(d.join("photon.iso.sha256")).ok()).flatten()
    }).and_then(|t| t.split_whitespace().next().map(str::to_string));
    let log = build_log(cfg, iso).map(|p| p.display().to_string());
    Ok(Report { file, size: meta.len(), modified, name, base, base_note, rpms, from_sources, unattributed, kernel_bound, base_unknown, inputs, sha256, log })
}

fn index_markdown(rows: &[Report], dir: &Path) -> String {
    let mut m = format!(
        "# ISOs in {}\n\nOne file `<iso>.md` beside each ISO says what it carries: the base commit, the key packages, every RPM that differs from the base and the PR or branch it comes from, and the build inputs. Generated by `sharukhan iso-content`, read back from the ISOs themselves.\n\n",
        dir.display()
    );
    m.push_str("| ISO | Written | Base | Kernel | systemd | Installer | PRs / branches |\n|---|---|---|---|---|---|---|\n");
    for r in rows {
        let pick = |n: &str| r.rpms.iter().find(|x| x.name == n).map(|x| format!("{}-{}", x.version, x.release)).unwrap_or_else(|| "-".into());
        let base = r.base.as_ref().map(|(f, d, _)| format!("`{}` {d}", &f[..10])).unwrap_or_else(|| format!("`{}` (unresolved)", r.name.commit));
        let labels: Vec<String> = r.from_sources.keys().map(|s| s.label.clone()).collect::<BTreeSet<_>>().into_iter().collect();
        m.push_str(&format!(
            "| [{}]({}.md) | {} | {base} | {} | {} | {} | {} |\n",
            r.file,
            r.file.replace(' ', "%20"),
            r.modified.get(..10).unwrap_or(""),
            pick("linux"),
            pick("systemd"),
            pick("photon-os-installer"),
            if labels.is_empty() { "none".to_string() } else { format!("{}", labels.len()) }
        ));
    }
    m
}

pub fn cli(args: &[String]) -> u8 {
    let cfg = Config::load();
    let mut dir: Option<PathBuf> = cfg.iso_store.clone();
    let mut out: Option<PathBuf> = None;
    let mut it = args.iter();
    while let Some(a) = it.next() {
        match a.as_str() {
            "--dir" => dir = it.next().map(PathBuf::from),
            "--out" => out = it.next().map(PathBuf::from),
            "-h" | "--help" => {
                println!("usage: sharukhan iso-content [--dir <dir with ISOs>] [--out <dir>]\n\nWrites <iso>.md beside every *.iso of --dir (default: the ISO store) and README.md as an index:\nbase commit, key packages, every RPM that differs from the base with the PR or branch whose\nspec declares it, and the cache record and build log of the ISO.");
                return 0;
            }
            other => {
                eprintln!("sharukhan iso-content: unknown option {other}");
                return 2;
            }
        }
    }
    let Some(dir) = dir else {
        eprintln!("sharukhan iso-content: no --dir and no ISO store configured");
        return 2;
    };
    let out = out.unwrap_or_else(|| dir.clone());
    let mut log = |l: &str| eprintln!("{l}");
    let mut isos: Vec<PathBuf> = match fs::read_dir(&dir) {
        Ok(rd) => rd.flatten().map(|e| e.path()).filter(|p| p.extension().is_some_and(|x| x == "iso") && p.is_file()).collect(),
        Err(e) => {
            eprintln!("sharukhan iso-content: {}: {e}", dir.display());
            return 1;
        }
    };
    isos.sort();
    let repos = repos(&cfg);
    log(&format!("{} ISO(s), {} repositor(ies)", isos.len(), repos.len()));
    let fetch = |url: &str, rf: &str| -> String {
        git(&cfg.gate_repo, &["fetch", "-q", url, &format!("+refs/heads/{0}:refs/sharukhan/iso-content/{1}", cfg.release, rf)]);
        git(&cfg.gate_repo, &["rev-parse", "--verify", "-q", &format!("refs/sharukhan/iso-content/{rf}")]).map(|s| s.trim().to_string()).unwrap_or_default()
    };
    let upstream = fetch(&format!("https://github.com/{}.git", cfg.upstream), "upstream");
    let fork = fetch(&format!("https://github.com/{}.git", cfg.fork), "fork");
    let base_ref = if upstream.is_empty() { cfg.release.clone() } else { upstream.clone() };
    let index = candidate_index(&cfg, &base_ref, std::env::consts::ARCH, &mut log);
    let mut produced = BTreeMap::new();
    let mut rows = Vec::new();
    let mut rc = 0;
    for iso in &isos {
        match report(&cfg, iso, &repos, &mut produced, &index, &upstream, &fork) {
            Ok(r) => {
                let p = out.join(format!("{}.md", r.file));
                if let Err(e) = fs::write(&p, r.markdown()) {
                    eprintln!("  {}: {e}", p.display());
                    rc = 1;
                }
                log(&format!("  {}: {} RPM(s), {} source(s), {} unattributed", r.file, r.rpms.len(), r.from_sources.len(), r.unattributed.len()));
                rows.push(r);
            }
            Err(e) => {
                eprintln!("  {}: {e}", iso.display());
                rc = 1;
            }
        }
    }
    let p = out.join("README.md");
    if let Err(e) = fs::write(&p, index_markdown(&rows, &dir)) {
        eprintln!("  {}: {e}", p.display());
        rc = 1;
    }
    log(&format!("wrote {} report(s) and {}", rows.len(), p.display()));
    rc
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_from_literal_macros_and_the_isos_arch() {
        let spec = "%global realname sd_notify\nName: erlang-%{realname}\nVersion: 1.1\nRelease: 10%{?dist}\n%ifarch x86_64\n%global targetArch aarch64\n%else\n%global targetArch x86_64\n%endif\n%package user-static-%{targetArch}\nSummary: s\n";
        let x = expand_names(spec, "x86_64");
        assert!(x.contains("Name: erlang-sd_notify"), "{x}");
        assert!(x.contains("%package user-static-aarch64"), "{x}");
        assert!(expand_names(spec, "aarch64").contains("%package user-static-x86_64"));
        let f = crate::buildexec::spec_families_text(&x).unwrap();
        assert!(f.families.contains(&"erlang-sd_notify".to_string()));
    }

    #[test]
    fn kernels_are_attributed_to_how_sharukhan_built_them() {
        let d = "SPECS/92/linux";
        assert_eq!(kernel_source("full-poilatest-equivalent-hyperv-console", d, "6.12.109", "6.12.109", "4.azure", &[]).unwrap().label, "remaster: Azure");
        assert_eq!(kernel_source("7.3_full-poilatest-equivalent", d, "6.12.113", "7.3.0", "1", &[]).unwrap().label, "kernel profile 7.3");
        assert_eq!(kernel_source("minimal-poi2.8-equivalent", d, "6.12.115", "6.12.115", "3", &[]).unwrap().label, "canister=equivalent");
        assert!(kernel_source("minimal-poi2.8-prebuilt", d, "6.12.115", "6.12.115", "3", &[]).is_none(), "a prebuilt build bumps nothing");
        assert!(kernel_source("7.3_full", "SPECS/systemd", "1", "7.3", "1", &[]).is_none());
        let branches = vec!["experimental/linux-7.3".to_string()];
        assert_eq!(kernel_source("full-poilatest-equivalent-hyperv-console", d, "6.12.113", "7.3.0", "1", &branches).unwrap().label, "kernel profile 7.3");
        assert!(kernel_source("full-poilatest-prebuilt", d, "6.12.113", "6.12.115", "1", &branches).is_none(), "no branch for 6.12: not a profile");
    }

    #[test]
    fn a_module_release_names_its_kernel() {
        assert_eq!(kernel_tag("6.12.115", "2").as_deref(), Some("0612115002"));
        assert_eq!(kernel_tag("7.3.0", "1").as_deref(), Some("0703000001"));
        assert_eq!(kernel_tag("6.12", "1"), None);
    }

    #[test]
    fn a_release_with_a_macro_tail_matches_its_expansion_only() {
        assert_eq!(release_of("Release: 2%{?kernelsubrelease}%{?dist}\n"), Some(("2".into(), true)));
        assert_eq!(release_of("Release: 10%{?dist}\n"), Some(("10".into(), false)));
        assert!(release_matches("2.0612115001", "2", true));
        assert!(!release_matches("2.0612115001", "2", false));
        assert!(!release_matches("21", "2", true));
        assert!(release_matches("10", "10", false));
    }

    #[test]
    fn names_as_sharukhan_stores_them() {
        let n = parse_name("minimal-poi2.8-prebuilt__20261107T102122Z-photon-minimal-5.0-543809d2a7.x86_64.iso");
        assert_eq!((n.build.as_str(), n.release.as_str(), n.commit.as_str(), n.arch.as_str()), ("minimal-poi2.8-prebuilt", "5.0", "543809d2a7", "x86_64"));
        let n = parse_name("full-poi2.8-equivalent__photon-5.0-682001eb08.x86_64-6d3ac79d9800.iso");
        assert_eq!((n.commit.as_str(), n.arch.as_str()), ("682001eb08", "x86_64"));
        let n = parse_name("photon-5.0-dde71ec57.x86_64-secureboot.iso");
        assert_eq!((n.build.as_str(), n.commit.as_str(), n.arch.as_str()), ("", "dde71ec57", "x86_64"));
        let n = parse_name("photon-5.0-c6db6a0d6.aarch64.azure.iso");
        assert_eq!((n.commit.as_str(), n.arch.as_str()), ("c6db6a0d6", "aarch64"));
    }

    #[test]
    fn the_report_names_its_sources_and_what_it_cannot_attribute() {
        let r = Report {
            file: "x.iso".into(),
            size: 1,
            modified: "2026-11-07T00:00:00Z".into(),
            name: parse_name("minimal-poi2.8-prebuilt__photon-minimal-5.0-4ebada30b6.x86_64.iso"),
            base: Some(("4ebada30b696e710c0b3f3b2b0077ef5b32c5afa".into(), "2026-11-06".into(), "90: strongswan | fix".into())),
            base_note: vec!["vmware/photon 5.0: is this commit (its head)".into()],
            rpms: vec![IsoRpm { arch: "x86_64".into(), file: "systemd-262.2-1.ph5.x86_64.rpm".into(), name: "systemd".into(), version: "262.2".into(), release: "1".into() }],
            from_sources: BTreeMap::from([(Source { label: "#95".into(), title: "libfastjson 1.2609.0".into(), branch: "fix/libfastjson-1.2609.0".into() }, vec!["libfastjson-1.2609.0-1".into()])]),
            unattributed: vec!["foo-1-2".into()],
            kernel_bound: BTreeMap::new(),
            base_unknown: false,
            inputs: Some("release-base abc\n".into()),
            sha256: None,
            log: None,
        };
        let m = r.markdown();
        assert!(m.contains("| systemd | 262.2-1 |"));
        assert!(m.contains("[#95](https://github.com/dcasota/photon/pull/95)"));
        assert!(m.contains("90: strongswan \\| fix"), "a pipe in a subject must not break the table");
        assert!(m.contains("declared by no PR head or port branch known here (1): foo-1-2"));
        assert!(m.contains("release-base abc"));
    }
}
