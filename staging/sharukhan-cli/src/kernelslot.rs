//! The stage's kernel slot, shared by prebuilt and equivalent builds.
//!
//! Every build of one release shares `stage/RPMS`, and the kernel RPMs in it
//! decide what an ISO boots. A prebuilt build and a canister-equivalent build
//! want different kernels there, so each pushed the other's out: runPh5's
//! shadowing purge removed the equivalent kernels (a higher Release), and the
//! phase-B purge removed every kernel at its NEVR, its own earlier phase-B
//! output included. Gate 55 spent ~5.5 h on full/2.8/equivalent and another
//! 3-4 h on minimal/2.8/equivalent, nearly all of it rebuilding linux and
//! linux-esx from inputs that had not changed.
//!
//! Two things live here.
//!
//! - **The keyed store** of canister-equivalent kernel RPMs (phase B's
//!   kernels, phase A's canister). An entry is keyed by the sha256 of every
//!   input the kernel build reads: the patched kernel spec directory (hashed
//!   as the same-NEVR ledger hashes it), the embedded patches the build
//!   applies, the canister version, the phase and its macros, the arch, and
//!   the toolchain - every stage RPM a kernel spec BuildRequires, by file name
//!   and content. A build reuses an entry only when the key is identical, and
//!   every restored RPM is hashed after the copy: one that is not byte-identical
//!   to the stored one is refused, the whole entry is discarded and the kernel
//!   is rebuilt. A miss names the inputs that moved since the newest stored
//!   entry, so the log says why a kernel is being rebuilt.
//!
//! - **The mode ledger** (`stage/.sharukhan-kernel-mode.tsv`), which records
//!   which build class put each kernel RPM into the stage. Entering a build
//!   takes every kernel of another class out of the stage: an equivalent one
//!   is removed (the keyed store holds it), any other is parked and returned
//!   when a build of its class runs. So a prebuilt build never sees an
//!   equivalent kernel, and an equivalent build never sees a prebuilt one.
//!
//! The store is `<base>/.sharukhan-kernel-store/<release>/`, beside the
//! release and common trees and inside neither: build.py and the ISO step read
//! `<base>/<release>/stage` and `<base>/<common>`, and a full ISO copies every
//! RPM under `stage/RPMS`, so nothing kept aside may live there.

use crate::sha256;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

/// The stage file recording which build class put each kernel RPM there.
pub const MODE_LEDGER: &str = ".sharukhan-kernel-mode.tsv";
/// The directory, beside the release trees, that holds kept-aside kernels.
pub const STORE_DIR: &str = ".sharukhan-kernel-store";
/// Bumped whenever the meaning of an input line changes, so entries written
/// under an older reading can never match.
const SCHEMA: &str = "1";
/// Keyed entries kept per phase; the oldest beyond this are pruned.
pub const KEEP_ENTRIES: usize = 3;
/// Class name of every canister-equivalent phase.
pub const EQUIVALENT: &str = "equivalent";
/// What an unrecorded kernel outside the equivalent NEVRs is assumed to be.
pub const ASSUMED_CLASS: &str = "prebuilt";

pub fn store_root(base_dir: &Path, release: &str) -> PathBuf {
    base_dir.join(STORE_DIR).join(release)
}

/// The class a canister mode's kernels belong to: both equivalent phases are
/// one class, every other mode its own.
pub fn class_of(mode: &str) -> &str {
    if mode.starts_with("equivalent") {
        EQUIVALENT
    } else {
        mode
    }
}

// ---------------------------------------------------------------------------
// what is a kernel RPM
// ---------------------------------------------------------------------------

/// Every binary package the kernel specs (`linux.spec`, `linux-esx.spec`)
/// declare, read from the specs as the subrelease sees them. The canister is
/// left out: it is not a kernel, and which canister the stage may hold is
/// decided by the canister pin (`vault_mismatched_canisters`).
pub fn kernel_families(specs_linux: &Path, subrelease: Option<u32>) -> BTreeSet<String> {
    let read = crate::specresolve::dir_reader(specs_linux);
    let mut out = BTreeSet::new();
    for flavour in ["linux", "linux-esx"] {
        let Some(text) = crate::specresolve::resolve(&read, &format!("{flavour}.spec"), subrelease)
        else {
            continue;
        };
        if let Some(f) = crate::buildexec::spec_families_text(&text) {
            out.extend(f.families);
        }
    }
    out.retain(|n| !n.starts_with("linux-fips-canister"));
    out
}

/// Every RPM under `stage/RPMS`, as (path relative to `stage/RPMS`, path).
pub fn stage_rpms(stage: &Path) -> Vec<(String, PathBuf)> {
    let root = stage.join("RPMS");
    let mut v: Vec<(String, PathBuf)> = crate::build::find_files_rec(&root, "", ".rpm")
        .into_iter()
        .filter_map(|p| {
            let rel = p.strip_prefix(&root).ok()?.to_string_lossy().into_owned();
            Some((rel, p))
        })
        .collect();
    v.sort();
    v
}

fn file_name(rel: &str) -> &str {
    rel.rsplit('/').next().unwrap_or(rel)
}

/// The canister is not a kernel: which one the stage may hold is decided by
/// the canister pin (`vault_mismatched_canisters`), never by this slot.
fn is_canister(fname: &str) -> bool {
    fname.starts_with("linux-fips-canister-")
}

fn rpm_name(rel: &str) -> Option<String> {
    crate::buildexec::parse_rpm_name(file_name(rel)).map(|(n, _, _)| n)
}

/// Package names a spec text requires to build: every `BuildRequires:` line
/// and every `ExtraBuildRequires*` macro, on BOTH sides of every conditional.
///
/// Deliberately a superset: a name that is not needed in this configuration
/// can only make the key stricter (rebuild more often), never let a changed
/// toolchain package through unseen.
pub fn build_requires(text: &str) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    for line in text.lines() {
        let l = line.trim();
        let deps = if let Some(r) = l.strip_prefix("BuildRequires:") {
            r
        } else if let Some(r) = l
            .strip_prefix("%define")
            .or_else(|| l.strip_prefix("%global"))
        {
            let r = r.trim_start();
            match r.split_once(char::is_whitespace) {
                Some((name, value)) if name.starts_with("ExtraBuildRequires") => value,
                _ => continue,
            }
        } else {
            continue;
        };
        for item in deps.split(',') {
            let Some(name) = item
                .split_whitespace()
                .next()
                .map(|n| n.trim_matches(|c| c == '(' || c == ')'))
            else {
                continue;
            };
            if !name.is_empty() && !matches!(name, "or" | "and" | "if" | "else" | "with") {
                out.insert(name.to_string());
            }
        }
    }
    out
}

// ---------------------------------------------------------------------------
// the key
// ---------------------------------------------------------------------------

/// Everything a canister-equivalent kernel build reads, as stable text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Inputs {
    pub mode: String,
    pub text: String,
    pub key: String,
}

/// The inputs of one equivalent phase. `patches` are the embedded patches the
/// build applies (name, text); `macros` the pkg-build-options for the phase.
/// None when the kernel spec directory cannot be read: no key, no reuse.
#[allow(clippy::too_many_arguments)]
pub fn inputs(
    specs_linux: &Path,
    subrelease: Option<u32>,
    patches: &[(&str, &str)],
    canister: Option<&str>,
    mode: &str,
    macros: &[String],
    arch: &str,
    stage: &Path,
) -> Option<Inputs> {
    let spec_hash = crate::buildexec::spec_dir_hash(specs_linux)?;
    let read = crate::specresolve::dir_reader(specs_linux);
    let mut brs = BTreeSet::new();
    let mut read_any = false;
    for flavour in ["linux", "linux-esx"] {
        if let Some(t) = crate::specresolve::resolve(&read, &format!("{flavour}.spec"), subrelease)
        {
            read_any = true;
            brs.extend(build_requires(&t));
        }
    }
    if !read_any {
        return None;
    }
    let mut lines: Vec<String> = vec![
        format!("schema\t{SCHEMA}"),
        format!("mode\t{mode}"),
        format!("arch\t{arch}"),
        format!("canister\t{}", canister.unwrap_or("-")),
        format!("macros\t{}", macros.join("; ")),
        format!(
            "subrelease\t{}",
            subrelease
                .map(|n| n.to_string())
                .unwrap_or_else(|| "-".into())
        ),
        format!("spec\t{spec_hash}"),
    ];
    for (name, text) in patches {
        lines.push(format!("patch:{name}\t{}", sha256::bytes(text.as_bytes())));
    }
    // The toolchain: each required name, resolved to the stage RPMs that
    // carry it, by file name and content. Absent is a value too - the day it
    // appears in the stage, the build that installs it is a different build.
    let mut by_name: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for (rel, p) in stage_rpms(stage) {
        let Some(n) = rpm_name(&rel) else { continue };
        if !brs.contains(&n) {
            continue;
        }
        let h = sha256::file(&p).ok()?;
        by_name
            .entry(n)
            .or_default()
            .push(format!("{}={h}", file_name(&rel)));
    }
    for n in &brs {
        let v = by_name
            .get(n)
            .map(|v| v.join(" "))
            .unwrap_or_else(|| "-".into());
        lines.push(format!("br:{n}\t{v}"));
    }
    let text: String = lines.iter().map(|l| format!("{l}\n")).collect();
    let key = sha256::bytes(text.as_bytes());
    Some(Inputs {
        mode: mode.to_string(),
        text,
        key,
    })
}

fn input_map(text: &str) -> BTreeMap<String, String> {
    text.lines()
        .filter_map(|l| l.split_once('\t'))
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect()
}

/// Which inputs differ between a stored entry and now, for the log.
pub fn explain(stored: &str, now: &str) -> Vec<String> {
    let (a, b) = (input_map(stored), input_map(now));
    let label = |k: &str| -> String {
        match k {
            "spec" => "the kernel spec directory content".into(),
            "canister" => "the canister version".into(),
            "macros" => "the phase's build macros".into(),
            k if k.starts_with("patch:") => format!("the embedded patch {}", &k[6..]),
            k if k.starts_with("br:") => format!("the toolchain package {}", &k[3..]),
            k => k.to_string(),
        }
    };
    let mut out = Vec::new();
    for k in a.keys().chain(b.keys()).collect::<BTreeSet<_>>() {
        match (a.get(k), b.get(k)) {
            (Some(x), Some(y)) if x == y => {}
            (Some(_), None) => out.push(format!("{} is no longer an input", label(k))),
            (None, Some(_)) => out.push(format!("{} is a new input", label(k))),
            _ => out.push(format!("{} changed", label(k))),
        }
    }
    out
}

// ---------------------------------------------------------------------------
// manifests and the mode ledger
// ---------------------------------------------------------------------------

/// `rel \t sha256` per line.
fn parse_manifest(text: &str) -> Vec<(String, String)> {
    text.lines()
        .filter_map(|l| l.split_once('\t'))
        .map(|(a, b)| (a.trim().to_string(), b.trim().to_string()))
        .filter(|(a, b)| !a.is_empty() && b.len() == 64 && !a.contains(".."))
        .collect()
}

fn write_manifest(path: &Path, m: &[(String, String)]) -> std::io::Result<()> {
    let text: String = m.iter().map(|(a, b)| format!("{a}\t{b}\n")).collect();
    let tmp = path.with_extension("tmp");
    fs::write(&tmp, text)?;
    fs::rename(&tmp, path)
}

/// file name -> (class, detail). `detail` is the store key for an equivalent
/// kernel, `-` otherwise.
pub fn parse_ledger(text: &str) -> BTreeMap<String, (String, String)> {
    text.lines()
        .filter_map(|l| {
            let mut it = l.split('\t');
            let (f, c) = (it.next()?.trim(), it.next()?.trim());
            let d = it.next().unwrap_or("-").trim();
            (!f.is_empty() && !c.is_empty())
                .then(|| (f.to_string(), (c.to_string(), d.to_string())))
        })
        .collect()
}

fn read_ledger(stage: &Path) -> BTreeMap<String, (String, String)> {
    parse_ledger(&fs::read_to_string(stage.join(MODE_LEDGER)).unwrap_or_default())
}

fn write_ledger(stage: &Path, l: &BTreeMap<String, (String, String)>, say: &mut dyn FnMut(&str)) {
    let text: String = l
        .iter()
        .map(|(f, (c, d))| format!("{f}\t{c}\t{d}\n"))
        .collect();
    if let Err(e) = fs::write(stage.join(MODE_LEDGER), text) {
        say(&format!(
            "  could not write {}: {e}",
            stage.join(MODE_LEDGER).display()
        ));
    }
}

/// Record kernel RPMs (paths relative to `stage/RPMS`) as put there by `class`.
pub fn record(stage: &Path, rels: &[String], class: &str, detail: &str, say: &mut dyn FnMut(&str)) {
    let mut l = read_ledger(stage);
    for r in rels.iter().filter(|r| !is_canister(file_name(r))) {
        l.insert(r.clone(), (class.to_string(), detail.to_string()));
    }
    // Entries whose file is gone are history, not state.
    l.retain(|r, _| stage.join("RPMS").join(r).is_file());
    write_ledger(stage, &l, say);
}

/// After a build of `class` succeeded: every kernel RPM in the stage that is
/// not recorded yet is this build's, or a predecessor's that it kept.
pub fn record_unrecorded(
    stage: &Path,
    families: &BTreeSet<String>,
    class: &str,
    say: &mut dyn FnMut(&str),
) {
    let l = read_ledger(stage);
    let new: Vec<String> = stage_rpms(stage)
        .into_iter()
        .map(|(r, _)| r)
        .filter(|r| !l.contains_key(r) && rpm_name(r).is_some_and(|n| families.contains(&n)))
        .collect();
    if !new.is_empty() {
        say(&format!(
            "  recorded {} kernel RPM(s) in the stage as {class}",
            new.len()
        ));
    }
    record(stage, &new, class, "-", say);
}

// ---------------------------------------------------------------------------
// moving files without trusting them
// ---------------------------------------------------------------------------

/// Copy `src` to `dst` through a temporary name, and hand back the hash of
/// what landed. The temporary never ends in `.rpm`, so a half-written copy is
/// never an RPM in anybody's repo.
fn copy_hashed(src: &Path, dst: &Path) -> Result<String, String> {
    if let Some(d) = dst.parent() {
        fs::create_dir_all(d).map_err(|e| format!("{}: {e}", d.display()))?;
    }
    let tmp = dst.with_extension("sharukhan-partial");
    fs::copy(src, &tmp)
        .map_err(|e| format!("copying {} -> {}: {e}", src.display(), tmp.display()))?;
    let h = match sha256::file(&tmp) {
        Ok(h) => h,
        Err(e) => {
            let _ = fs::remove_file(&tmp);
            return Err(e);
        }
    };
    fs::rename(&tmp, dst).map_err(|e| {
        let _ = fs::remove_file(&tmp);
        format!("{}: {e}", dst.display())
    })?;
    Ok(h)
}

fn move_file(src: &Path, dst: &Path) -> Result<(), String> {
    if let Some(d) = dst.parent() {
        fs::create_dir_all(d).map_err(|e| format!("{}: {e}", d.display()))?;
    }
    if fs::rename(src, dst).is_ok() {
        return Ok(());
    }
    copy_hashed(src, dst)?;
    fs::remove_file(src).map_err(|e| format!("{}: {e}", src.display()))
}

/// Remove a store entry: its files, then its directories. Only ever called on
/// a directory below the store root.
fn discard_entry(dir: &Path) {
    for f in crate::build::find_files_rec(dir, "", "") {
        let _ = fs::remove_file(f);
    }
    let mut dirs: Vec<PathBuf> = Vec::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(d) = stack.pop() {
        if let Ok(rd) = fs::read_dir(&d) {
            for e in rd.flatten() {
                if e.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                    stack.push(e.path());
                }
            }
        }
        dirs.push(d);
    }
    dirs.sort_by_key(|d| std::cmp::Reverse(d.components().count()));
    for d in dirs {
        let _ = fs::remove_dir(d);
    }
}

// ---------------------------------------------------------------------------
// entering a build: the slot holds this class's kernels and nothing else
// ---------------------------------------------------------------------------

fn parked_dir(root: &Path, class: &str) -> PathBuf {
    root.join("parked").join(class)
}

/// Make the stage's kernel slot fit a build of `class`.
///
/// - an equivalent kernel is removed when any build enters (the keyed store
///   holds it; an equivalent build restores its own entry after the purge);
/// - a kernel of another non-equivalent class is parked under its class;
/// - an unrecorded kernel is left to the existing purges when it sits at the
///   NEVR this build produces (`at_build_nevr`), and is otherwise left alone by
///   a non-equivalent build and parked as `prebuilt` by an equivalent one;
/// - this class's parked kernels come back, each verified against the hash it
///   was parked with.
pub fn enter(
    stage: &Path,
    root: &Path,
    class: &str,
    families: &BTreeSet<String>,
    at_build_nevr: &dyn Fn(&str) -> bool,
    dry: bool,
    say: &mut dyn FnMut(&str),
) {
    let mut ledger = read_ledger(stage);
    let rpms = stage.join("RPMS");
    for (rel, p) in stage_rpms(stage) {
        let fname = file_name(&rel).to_string();
        if is_canister(&fname) {
            continue;
        }
        let recorded = ledger.get(&rel).cloned();
        let is_kernel = recorded.is_some() || rpm_name(&rel).is_some_and(|n| families.contains(&n));
        if !is_kernel {
            continue;
        }
        let other = match &recorded {
            // Out on every entry, an equivalent build's own included: it
            // gets back exactly the entry its inputs key, after the purge.
            Some((c, d)) if c == EQUIVALENT => (c.clone(), d.clone()),
            Some((c, _)) if c == class => continue,
            Some((c, d)) => (c.clone(), d.clone()),
            None if at_build_nevr(&fname) => continue,
            None if class == EQUIVALENT => (ASSUMED_CLASS.to_string(), "-".to_string()),
            None => continue,
        };
        let (oc, detail) = other;
        if oc == EQUIVALENT {
            let kept = if detail != "-" && find_entry(root, &detail).is_some() {
                format!("stored under key {}", short(&detail))
            } else {
                "not in the store; rebuilt when needed".into()
            };
            if dry {
                say(&format!(
                    "  would remove equivalent kernel {fname} from the stage ({kept})"
                ));
                continue;
            }
            if fs::remove_file(&p).is_ok() {
                let why = if class == EQUIVALENT {
                    "an equivalent build gets back only the entry its inputs key"
                } else {
                    "a non-equivalent build must not see it"
                };
                say(&format!(
                    "  removed equivalent kernel {fname} from the stage: {why} ({kept})"
                ));
                ledger.remove(&rel);
            }
            continue;
        }
        let why = if recorded.is_none() {
            format!("no record of its build; taken as {oc}")
        } else {
            format!("built by a {oc} build")
        };
        if dry {
            say(&format!("  would park {fname} ({why}) outside the stage"));
            continue;
        }
        match park(root, &oc, &rel, &p) {
            Ok(()) => {
                say(&format!(
                    "  parked {fname} ({why}) in {}: a {class} build must not see it",
                    parked_dir(root, &oc).display()
                ));
                ledger.remove(&rel);
            }
            Err(e) => say(&format!("  could not park {fname}: {e}")),
        }
    }
    if !dry {
        write_ledger(stage, &ledger, say);
    }
    if class == EQUIVALENT {
        return;
    }
    // This class's own kernels, parked by a build of another class.
    let dir = parked_dir(root, class);
    let man_path = dir.join("manifest.tsv");
    let man = parse_manifest(&fs::read_to_string(&man_path).unwrap_or_default());
    if man.is_empty() {
        return;
    }
    if dry {
        say(&format!(
            "  would return {} parked {class} kernel RPM(s) to the stage",
            man.len()
        ));
        return;
    }
    let mut back = Vec::new();
    for (rel, want) in &man {
        let src = dir.join("rpms").join(rel);
        let dst = rpms.join(rel);
        if dst.exists() {
            say(&format!(
                "  dropped parked {}: the stage holds a newer file of that name",
                file_name(rel)
            ));
            let _ = fs::remove_file(&src);
            continue;
        }
        match move_file(&src, &dst).and_then(|_| sha256::file(&dst)) {
            Ok(h) if &h == want => {
                say(&format!(
                    "  returned parked {class} kernel {}",
                    file_name(rel)
                ));
                back.push(rel.clone());
            }
            Ok(_) => {
                let _ = fs::remove_file(&dst);
                say(&format!(
                    "  refused parked {}: not byte-identical to what was parked; it will be rebuilt",
                    file_name(rel)
                ));
            }
            Err(e) => say(&format!(
                "  could not return parked {}: {e}",
                file_name(rel)
            )),
        }
    }
    discard_entry(&dir);
    record(stage, &back, class, "-", say);
}

fn park(root: &Path, class: &str, rel: &str, p: &Path) -> Result<(), String> {
    let dir = parked_dir(root, class);
    let h = sha256::file(p)?;
    move_file(p, &dir.join("rpms").join(rel))?;
    let man_path = dir.join("manifest.tsv");
    let mut man = parse_manifest(&fs::read_to_string(&man_path).unwrap_or_default());
    man.retain(|(r, _)| r != rel);
    man.push((rel.to_string(), h));
    write_manifest(&man_path, &man).map_err(|e| format!("{}: {e}", man_path.display()))
}

// ---------------------------------------------------------------------------
// the keyed store of equivalent kernels
// ---------------------------------------------------------------------------

fn short(key: &str) -> &str {
    &key[..key.len().min(12)]
}

fn mode_dir(root: &Path, mode: &str) -> PathBuf {
    root.join(EQUIVALENT).join(mode)
}

fn find_entry(root: &Path, key: &str) -> Option<PathBuf> {
    let base = root.join(EQUIVALENT);
    fs::read_dir(&base)
        .ok()?
        .flatten()
        .map(|e| e.path().join(key))
        .find(|d| d.join("manifest.tsv").is_file())
}

/// Entries of one phase, newest first.
fn entries(root: &Path, mode: &str) -> Vec<PathBuf> {
    let mut v: Vec<(std::time::SystemTime, PathBuf)> = fs::read_dir(mode_dir(root, mode))
        .map(|rd| {
            rd.flatten()
                .map(|e| e.path())
                .filter(|d| d.join("manifest.tsv").is_file())
                .filter_map(|d| {
                    let t = d.join("manifest.tsv").metadata().ok()?.modified().ok()?;
                    Some((t, d))
                })
                .collect()
        })
        .unwrap_or_default();
    v.sort_by(|a, b| b.0.cmp(&a.0));
    v.into_iter().map(|(_, d)| d).collect()
}

/// The outcome of a restore.
#[derive(Debug, PartialEq, Eq)]
pub enum Restore {
    /// Every RPM of the entry is in the stage, byte-identical to the stored one.
    Reused(Vec<String>),
    /// Nothing stored under this key; the reasons name what moved.
    Miss(Vec<String>),
    /// An entry existed but a restored file did not match its hash; the entry
    /// is discarded and nothing of it is left in the stage.
    Refused(String),
}

/// Restore the entry for `inp` into the stage, or say why it cannot be.
///
/// Records `inp` as the pending key either way, so [`store`] files this
/// build's output under the inputs it was built from - not under a key
/// recomputed after the build has added RPMs to the stage.
pub fn restore(root: &Path, inp: &Inputs, stage: &Path, say: &mut dyn FnMut(&str)) -> Restore {
    let md = mode_dir(root, &inp.mode);
    let _ = fs::create_dir_all(&md);
    let _ = fs::write(
        md.join("pending.tsv"),
        format!("key\t{}\n{}", inp.key, inp.text),
    );
    let dir = md.join(&inp.key);
    let man_path = dir.join("manifest.tsv");
    let Ok(man_text) = fs::read_to_string(&man_path) else {
        let reasons = match entries(root, &inp.mode).first() {
            Some(prev) => {
                let stored = fs::read_to_string(prev.join("inputs.tsv")).unwrap_or_default();
                let r = explain(&stored, &inp.text);
                if r.is_empty() {
                    vec!["the newest stored entry has unreadable inputs".into()]
                } else {
                    r
                }
            }
            None => vec![format!("nothing stored for {} yet", inp.mode)],
        };
        return Restore::Miss(reasons);
    };
    let man = parse_manifest(&man_text);
    if man.is_empty() {
        discard_entry(&dir);
        return Restore::Refused("the entry's manifest is empty or unreadable".into());
    }
    let rpms = stage.join("RPMS");
    let mut placed: Vec<PathBuf> = Vec::new();
    let mut fail: Option<String> = None;
    for (rel, want) in &man {
        let dst = rpms.join(rel);
        match copy_hashed(&dir.join("rpms").join(rel), &dst) {
            Ok(h) if &h == want => placed.push(dst),
            Ok(h) => {
                let _ = fs::remove_file(&dst);
                fail = Some(format!(
                    "{} restored as sha256 {} but was stored as {}",
                    file_name(rel),
                    short(&h),
                    short(want)
                ));
                break;
            }
            Err(e) => {
                fail = Some(e);
                break;
            }
        }
    }
    if let Some(why) = fail {
        for p in placed {
            let _ = fs::remove_file(p);
        }
        discard_entry(&dir);
        return Restore::Refused(why);
    }
    let rels: Vec<String> = man.iter().map(|(r, _)| r.clone()).collect();
    record(stage, &rels, EQUIVALENT, &inp.key, say);
    // A reused entry counts as the newest one when old entries are pruned.
    let _ = write_manifest(&man_path, &man);
    Restore::Reused(rels)
}

/// File this phase's output (`files`, inside `stage/RPMS`) under the pending
/// key [`restore`] recorded, and record it in the mode ledger. Returns the key.
pub fn store(
    root: &Path,
    mode: &str,
    stage: &Path,
    files: &[PathBuf],
    say: &mut dyn FnMut(&str),
) -> Result<String, String> {
    let md = mode_dir(root, mode);
    let pending = fs::read_to_string(md.join("pending.tsv")).map_err(|_| {
        format!("no pending {mode} key: the purge did not compute this build's inputs")
    })?;
    let (first, text) = pending.split_once('\n').unwrap_or((&pending, ""));
    let key = first
        .strip_prefix("key\t")
        .filter(|k| k.len() == 64)
        .ok_or("the pending key is malformed")?
        .to_string();
    if sha256::bytes(text.as_bytes()) != key {
        return Err("the pending inputs do not hash to the pending key".into());
    }
    let rpms = stage.join("RPMS");
    let mut man = Vec::new();
    for f in files {
        let rel = f
            .strip_prefix(&rpms)
            .map_err(|_| format!("{} is not under {}", f.display(), rpms.display()))?
            .to_string_lossy()
            .into_owned();
        man.push((rel, sha256::file(f)?));
    }
    man.sort();
    if man.is_empty() {
        return Err(format!("{mode} left no kernel RPM to store"));
    }
    let dir = md.join(&key);
    let man_path = dir.join("manifest.tsv");
    let rels: Vec<String> = man.iter().map(|(r, _)| r.clone()).collect();
    if parse_manifest(&fs::read_to_string(&man_path).unwrap_or_default()) == man {
        say(&format!(
            "  {mode} kernels already stored under key {} - nothing to copy",
            short(&key)
        ));
    } else {
        if dir.exists() {
            discard_entry(&dir);
        }
        for (rel, want) in &man {
            let h = copy_hashed(&rpms.join(rel), &dir.join("rpms").join(rel))?;
            if &h != want {
                discard_entry(&dir);
                return Err(format!("{rel} changed while it was being stored"));
            }
        }
        fs::write(dir.join("inputs.tsv"), text).map_err(|e| format!("{}: {e}", dir.display()))?;
        // The manifest last: an entry without one is not an entry.
        write_manifest(&man_path, &man).map_err(|e| format!("{}: {e}", man_path.display()))?;
        say(&format!(
            "  stored {} {mode} RPM(s) under key {} in {}",
            man.len(),
            short(&key),
            dir.display()
        ));
    }
    let _ = fs::remove_file(md.join("pending.tsv"));
    record(stage, &rels, EQUIVALENT, &key, say);
    for old in entries(root, mode).into_iter().skip(KEEP_ENTRIES) {
        say(&format!(
            "  pruned stored {mode} entry {} (keeping the newest {KEEP_ENTRIES})",
            old.file_name()
                .and_then(|n| n.to_str())
                .map(short)
                .unwrap_or("?")
        ));
        discard_entry(&old);
    }
    Ok(key)
}

#[cfg(test)]
mod tests {
    use super::*;

    struct T(PathBuf);
    impl Drop for T {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }
    fn tmp(tag: &str) -> T {
        let d = std::env::temp_dir().join(format!("shk-kslot-{tag}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        T(d)
    }

    const LINUX: &str = "Name: linux\nVersion: 6.12.111\nRelease: 4%{?dist}\n\
BuildRequires: gcc >= 12.2.0-6\nBuildRequires: bc, kmod-devel\n\
%define ExtraBuildRequiresSansSnapshot linux-fips-canister = %{fips_canister_version}\n\
%package devel\nSummary: x\n%package -n bpftool\nSummary: y\n%package fips-canister\n";
    const ESX: &str = "Name: linux-esx\nVersion: 6.12.111\nRelease: 5%{?dist}\n\
BuildRequires: gcc\nBuildRequires: openssl-devel\n%package devel\n";

    /// A release tree with kernel specs and a stage holding the toolchain.
    fn tree(t: &Path) -> (PathBuf, PathBuf) {
        let specs = t.join("5.0/SPECS/linux");
        let stage = t.join("5.0/stage");
        fs::create_dir_all(&specs).unwrap();
        fs::create_dir_all(stage.join("RPMS/x86_64")).unwrap();
        fs::write(specs.join("linux.spec"), LINUX).unwrap();
        fs::write(specs.join("linux-esx.spec"), ESX).unwrap();
        fs::write(specs.join("0001-fix.patch"), "a\n").unwrap();
        for (n, c) in [
            ("gcc-12.2.0-6.ph5.x86_64.rpm", "gcc"),
            ("bc-1.07-1.ph5.x86_64.rpm", "bc"),
            ("linux-fips-canister-6.12.111-4.ph5.x86_64.rpm", "canister"),
            ("zlib-1.3-1.ph5.x86_64.rpm", "zlib"),
        ] {
            fs::write(stage.join("RPMS/x86_64").join(n), c).unwrap();
        }
        (specs, stage)
    }

    fn inp(specs: &Path, stage: &Path, patch: &str, canister: &str, mode: &str) -> Inputs {
        let macros = vec![format!("fips_canister_override {canister}")];
        inputs(
            specs,
            None,
            &[("canister-equivalent", patch)],
            Some(canister),
            mode,
            &macros,
            "x86_64",
            stage,
        )
        .unwrap()
    }

    #[test]
    fn build_requires_reads_every_form_and_both_branches() {
        let b = build_requires(LINUX);
        for n in ["gcc", "bc", "kmod-devel", "linux-fips-canister"] {
            assert!(b.contains(n), "{n} missing from {b:?}");
        }
        assert!(!b.contains(">="), "{b:?}");
        let fams = {
            let t = tmp("fam");
            let (specs, _) = tree(&t.0);
            kernel_families(&specs, None)
        };
        assert!(
            fams.contains("linux-esx-devel") && fams.contains("bpftool"),
            "{fams:?}"
        );
        assert!(
            !fams.iter().any(|f| f.starts_with("linux-fips-canister")),
            "{fams:?}"
        );
    }

    /// Negative controls: each input, changed alone, moves the key - so the
    /// stored kernels are not reused and the kernel is rebuilt.
    #[test]
    fn a_changed_spec_patch_canister_or_toolchain_package_forces_a_rebuild() {
        let t = tmp("key");
        let (specs, stage) = tree(&t.0);
        let base = inp(&specs, &stage, "P1", "6.12.111-4.ph5", "equivalent-b");
        assert_eq!(
            base,
            inp(&specs, &stage, "P1", "6.12.111-4.ph5", "equivalent-b"),
            "stable"
        );

        // an unrelated stage package is not an input
        fs::write(stage.join("RPMS/x86_64/zlib-1.3-1.ph5.x86_64.rpm"), "zlib2").unwrap();
        assert_eq!(
            base.key,
            inp(&specs, &stage, "P1", "6.12.111-4.ph5", "equivalent-b").key
        );

        // spec content
        fs::write(specs.join("0001-fix.patch"), "b\n").unwrap();
        let k = inp(&specs, &stage, "P1", "6.12.111-4.ph5", "equivalent-b");
        assert_ne!(base.key, k.key, "a spec directory change must rebuild");
        assert!(explain(&base.text, &k.text)
            .iter()
            .any(|r| r.contains("spec directory")));
        fs::write(specs.join("0001-fix.patch"), "a\n").unwrap();
        assert_eq!(
            base.key,
            inp(&specs, &stage, "P1", "6.12.111-4.ph5", "equivalent-b").key
        );

        // the embedded patch
        let k = inp(&specs, &stage, "P2", "6.12.111-4.ph5", "equivalent-b");
        assert_ne!(base.key, k.key, "an embedded patch change must rebuild");
        assert!(explain(&base.text, &k.text)
            .iter()
            .any(|r| r.contains("embedded patch")));

        // the canister version
        let k = inp(&specs, &stage, "P1", "6.12.111-5.ph5", "equivalent-b");
        assert_ne!(base.key, k.key, "a canister version change must rebuild");
        assert!(explain(&base.text, &k.text)
            .iter()
            .any(|r| r.contains("canister version")));

        // a toolchain package: same file name, other content
        fs::write(
            stage.join("RPMS/x86_64/gcc-12.2.0-6.ph5.x86_64.rpm"),
            "gcc rebuilt",
        )
        .unwrap();
        let k = inp(&specs, &stage, "P1", "6.12.111-4.ph5", "equivalent-b");
        assert_ne!(base.key, k.key, "a toolchain package change must rebuild");
        assert_eq!(
            explain(&base.text, &k.text),
            vec!["the toolchain package gcc changed".to_string()]
        );
        fs::write(stage.join("RPMS/x86_64/gcc-12.2.0-6.ph5.x86_64.rpm"), "gcc").unwrap();

        // the canister itself is a toolchain package of phase B
        fs::write(
            stage.join("RPMS/x86_64/linux-fips-canister-6.12.111-4.ph5.x86_64.rpm"),
            "other canister",
        )
        .unwrap();
        assert_ne!(
            base.key,
            inp(&specs, &stage, "P1", "6.12.111-4.ph5", "equivalent-b").key
        );
        fs::write(
            stage.join("RPMS/x86_64/linux-fips-canister-6.12.111-4.ph5.x86_64.rpm"),
            "canister",
        )
        .unwrap();

        // a toolchain package appearing in the stage
        fs::write(
            stage.join("RPMS/x86_64/openssl-devel-3.0-1.ph5.x86_64.rpm"),
            "o",
        )
        .unwrap();
        assert_ne!(
            base.key,
            inp(&specs, &stage, "P1", "6.12.111-4.ph5", "equivalent-b").key
        );
        fs::remove_file(stage.join("RPMS/x86_64/openssl-devel-3.0-1.ph5.x86_64.rpm")).unwrap();

        // the phase
        assert_ne!(
            base.key,
            inp(&specs, &stage, "P1", "6.12.111-4.ph5", "equivalent-a").key
        );
        assert_eq!(
            base.key,
            inp(&specs, &stage, "P1", "6.12.111-4.ph5", "equivalent-b").key
        );
    }

    fn put(stage: &Path, name: &str, content: &str) -> PathBuf {
        let p = stage.join("RPMS/x86_64").join(name);
        fs::write(&p, content).unwrap();
        p
    }

    #[test]
    fn stored_kernels_come_back_byte_identical_and_only_under_their_key() {
        let t = tmp("store");
        let (specs, stage) = tree(&t.0);
        let root = t.0.join(STORE_DIR).join("5.0");
        let mut log = Vec::new();
        let mut say = |l: &str| log.push(l.to_string());
        let i = inp(&specs, &stage, "P1", "6.12.111-4.ph5", "equivalent-b");

        assert!(matches!(
            restore(&root, &i, &stage, &mut say),
            Restore::Miss(_)
        ));
        let k = put(&stage, "linux-6.12.111-4.ph5.x86_64.rpm", "KERNEL");
        let e = put(&stage, "linux-esx-6.12.111-5.ph5.x86_64.rpm", "ESX");
        assert_eq!(
            store(
                &root,
                "equivalent-b",
                &stage,
                &[k.clone(), e.clone()],
                &mut say
            )
            .unwrap(),
            i.key
        );
        assert!(
            !root.starts_with(&stage),
            "the store must be outside the stage"
        );

        // the next build of another class removes them; an identical key restores them
        fs::remove_file(&k).unwrap();
        fs::remove_file(&e).unwrap();
        assert_eq!(
            restore(&root, &i, &stage, &mut say),
            Restore::Reused(vec![
                "x86_64/linux-6.12.111-4.ph5.x86_64.rpm".into(),
                "x86_64/linux-esx-6.12.111-5.ph5.x86_64.rpm".into()
            ])
        );
        assert_eq!(fs::read_to_string(&k).unwrap(), "KERNEL");
        assert_eq!(fs::read_to_string(&e).unwrap(), "ESX");
        assert_eq!(
            read_ledger(&stage)
                .get("x86_64/linux-6.12.111-4.ph5.x86_64.rpm")
                .unwrap()
                .0,
            EQUIVALENT
        );

        // another key gets nothing, and is told why
        fs::remove_file(&k).unwrap();
        fs::remove_file(&e).unwrap();
        let other = inp(&specs, &stage, "P1", "6.12.111-5.ph5", "equivalent-b");
        match restore(&root, &other, &stage, &mut say) {
            Restore::Miss(r) => assert!(r.iter().any(|x| x.contains("canister version")), "{r:?}"),
            x => panic!("{x:?}"),
        }
        assert!(!k.exists() && !e.exists());
    }

    /// A stored RPM that is no longer the bytes it was stored as is refused:
    /// nothing of the entry is left in the stage, the entry is discarded, and
    /// the kernel is rebuilt.
    #[test]
    fn a_stored_rpm_that_changed_is_refused_and_rebuilt() {
        let t = tmp("tamper");
        let (specs, stage) = tree(&t.0);
        let root = t.0.join(STORE_DIR).join("5.0");
        let mut say = |_: &str| {};
        let i = inp(&specs, &stage, "P1", "6.12.111-4.ph5", "equivalent-b");
        let _ = restore(&root, &i, &stage, &mut say);
        let k = put(&stage, "linux-6.12.111-4.ph5.x86_64.rpm", "KERNEL");
        let e = put(&stage, "linux-esx-6.12.111-5.ph5.x86_64.rpm", "ESX");
        store(
            &root,
            "equivalent-b",
            &stage,
            &[k.clone(), e.clone()],
            &mut say,
        )
        .unwrap();
        fs::remove_file(&k).unwrap();
        fs::remove_file(&e).unwrap();
        let entry = root.join(EQUIVALENT).join("equivalent-b").join(&i.key);
        fs::write(
            entry.join("rpms/x86_64/linux-esx-6.12.111-5.ph5.x86_64.rpm"),
            "ESX!",
        )
        .unwrap();

        match restore(&root, &i, &stage, &mut say) {
            Restore::Refused(why) => assert!(why.contains("linux-esx"), "{why}"),
            x => panic!("{x:?}"),
        }
        assert!(
            !k.exists() && !e.exists(),
            "nothing of a refused entry may stay in the stage"
        );
        assert!(
            !entry.join("manifest.tsv").exists(),
            "the entry is discarded"
        );
        assert!(matches!(
            restore(&root, &i, &stage, &mut say),
            Restore::Miss(_)
        ));
    }

    #[test]
    fn store_files_under_the_key_of_the_purge_not_of_the_stage_after_the_build() {
        let t = tmp("pending");
        let (specs, stage) = tree(&t.0);
        let root = t.0.join(STORE_DIR).join("5.0");
        let mut say = |_: &str| {};
        assert!(
            store(&root, "equivalent-b", &stage, &[], &mut say).is_err(),
            "no pending key"
        );
        let i = inp(&specs, &stage, "P1", "6.12.111-4.ph5", "equivalent-b");
        let _ = restore(&root, &i, &stage, &mut say);
        // the build adds a toolchain package to the stage
        put(&stage, "openssl-devel-3.0-1.ph5.x86_64.rpm", "o");
        let k = put(&stage, "linux-6.12.111-4.ph5.x86_64.rpm", "KERNEL");
        assert_eq!(
            store(&root, "equivalent-b", &stage, &[k], &mut say).unwrap(),
            i.key
        );
    }

    /// Leak prevention, both ways: a prebuilt build never sees an equivalent
    /// kernel, an equivalent build never sees a prebuilt one, and nothing of
    /// either is lost.
    #[test]
    fn a_prebuilt_build_never_receives_an_equivalent_kernel_and_vice_versa() {
        let t = tmp("leak");
        let (specs, stage) = tree(&t.0);
        let root = t.0.join(STORE_DIR).join("5.0");
        let fams = kernel_families(&specs, None);
        let mut log = Vec::new();
        let mut say = |l: &str| log.push(l.to_string());
        let kernels = |stage: &Path| -> Vec<String> {
            stage_rpms(stage)
                .into_iter()
                .map(|(r, _)| file_name(&r).to_string())
                .filter(|n| n.starts_with("linux-") && !n.starts_with("linux-fips"))
                .collect()
        };
        let eq_nevr = |n: &str| n.contains("-6.12.111-4.") || n.contains("-6.12.111-5.");
        let never = |_: &str| false;

        // a prebuilt build left its kernels
        put(&stage, "linux-6.12.111-3.ph5.x86_64.rpm", "PRE");
        put(&stage, "linux-esx-6.12.111-3.ph5.x86_64.rpm", "PRE-ESX");
        record_unrecorded(&stage, &fams, "prebuilt", &mut say);

        // an equivalent build enters: the prebuilt kernels leave the stage
        enter(&stage, &root, EQUIVALENT, &fams, &eq_nevr, false, &mut say);
        assert!(kernels(&stage).is_empty(), "{:?}", kernels(&stage));
        // it builds and stores its own
        let i = inp(&specs, &stage, "P1", "6.12.111-4.ph5", "equivalent-b");
        let _ = restore(&root, &i, &stage, &mut say);
        let k = put(&stage, "linux-6.12.111-4.ph5.x86_64.rpm", "EQ");
        let e = put(&stage, "linux-esx-6.12.111-5.ph5.x86_64.rpm", "EQ-ESX");
        store(&root, "equivalent-b", &stage, &[k, e], &mut say).unwrap();

        // a prebuilt build enters: only prebuilt kernels, byte-identical
        enter(&stage, &root, "prebuilt", &fams, &never, false, &mut say);
        let mut got = kernels(&stage);
        got.sort();
        assert_eq!(
            got,
            vec![
                "linux-6.12.111-3.ph5.x86_64.rpm",
                "linux-esx-6.12.111-3.ph5.x86_64.rpm"
            ]
        );
        assert_eq!(
            fs::read_to_string(stage.join("RPMS/x86_64/linux-6.12.111-3.ph5.x86_64.rpm")).unwrap(),
            "PRE"
        );

        // an equivalent build enters again: no prebuilt kernel, its own come back
        enter(&stage, &root, EQUIVALENT, &fams, &eq_nevr, false, &mut say);
        assert!(kernels(&stage).is_empty());
        assert!(matches!(
            restore(&root, &i, &stage, &mut say),
            Restore::Reused(_)
        ));
        let mut got = kernels(&stage);
        got.sort();
        assert_eq!(
            got,
            vec![
                "linux-6.12.111-4.ph5.x86_64.rpm",
                "linux-esx-6.12.111-5.ph5.x86_64.rpm"
            ]
        );

        // the store and the parking lot are outside the stage
        assert!(!root.starts_with(&stage));
        assert!(
            log.iter().any(|l| l.contains("removed equivalent kernel")),
            "{log:?}"
        );
        assert!(
            log.iter().any(|l| l.contains("parked linux-6.12.111-3")),
            "{log:?}"
        );
    }

    /// An unrecorded kernel at the NEVR an equivalent build produces is left to
    /// the phase purge, never parked as prebuilt - parking it would hand an
    /// equivalent kernel to the next prebuilt build.
    #[test]
    fn an_unrecorded_kernel_at_the_equivalent_nevr_is_never_parked_as_prebuilt() {
        let t = tmp("unrec");
        let (specs, stage) = tree(&t.0);
        let root = t.0.join(STORE_DIR).join("5.0");
        let fams = kernel_families(&specs, None);
        let mut say = |_: &str| {};
        let k = put(&stage, "linux-6.12.111-4.ph5.x86_64.rpm", "EQ?");
        let p = put(&stage, "linux-6.12.111-3.ph5.x86_64.rpm", "PRE?");
        let eq_nevr = |n: &str| n.contains("-6.12.111-4.");
        enter(&stage, &root, EQUIVALENT, &fams, &eq_nevr, false, &mut say);
        assert!(k.exists(), "left to the phase purge");
        assert!(!p.exists(), "the other one is parked");
        assert!(!parked_dir(&root, ASSUMED_CLASS)
            .join("rpms/x86_64/linux-6.12.111-4.ph5.x86_64.rpm")
            .exists());
        // a prebuilt build leaves unrecorded kernels to runPh5's shadowing purge
        let never = |_: &str| false;
        enter(&stage, &root, "prebuilt", &fams, &never, false, &mut say);
        assert!(k.exists() && p.exists());
    }

    #[test]
    fn a_dry_run_moves_nothing() {
        let t = tmp("dry");
        let (specs, stage) = tree(&t.0);
        let root = t.0.join(STORE_DIR).join("5.0");
        let fams = kernel_families(&specs, None);
        let mut log = Vec::new();
        let mut say = |l: &str| log.push(l.to_string());
        let p = put(&stage, "linux-6.12.111-3.ph5.x86_64.rpm", "PRE");
        enter(
            &stage,
            &root,
            EQUIVALENT,
            &fams,
            &|_: &str| false,
            true,
            &mut say,
        );
        assert!(p.exists() && !root.exists());
        assert!(log.iter().any(|l| l.contains("would park")), "{log:?}");
    }

    #[test]
    fn old_entries_are_pruned_beyond_the_newest_few() {
        let t = tmp("prune");
        let (specs, stage) = tree(&t.0);
        let root = t.0.join(STORE_DIR).join("5.0");
        let mut say = |_: &str| {};
        for n in 0..(KEEP_ENTRIES + 2) {
            let i = inp(
                &specs,
                &stage,
                &format!("P{n}"),
                "6.12.111-4.ph5",
                "equivalent-b",
            );
            let _ = restore(&root, &i, &stage, &mut say);
            let k = put(&stage, "linux-6.12.111-4.ph5.x86_64.rpm", &format!("K{n}"));
            store(&root, "equivalent-b", &stage, &[k], &mut say).unwrap();
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
        assert_eq!(entries(&root, "equivalent-b").len(), KEEP_ENTRIES);
    }
}
