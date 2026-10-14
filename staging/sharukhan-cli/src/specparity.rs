//! Spec parity: does a reworked SPECS tree build exactly what a reference tree builds?
//!
//! Written for the kernel fold (one linux/linux-esx spec for every 5.0 subrelease,
//! replacing SPECS/90/linux and SPECS/91/linux), and kept generic: any package, any
//! set of subreleases, architectures and build modes.
//!
//! For every cell (subrelease x spec x arch x mode) each tree's spec is chosen the
//! way Photon chooses it - among `SPECS/<dir>/<spec>` and `SPECS/<NN>/<dir>/<spec>`,
//! the one whose `build_if` holds - and read with rpmspec. Compared:
//!
//! - refusal: a cell one side refuses to parse must be refused by the other;
//! - every subpackage's NEVRA with its Requires/Provides/Conflicts/Obsoletes;
//! - BuildRequires and the %changelog;
//! - every numbered Source/Patch, resolved to file content the way the package
//!   builder stages it (any file of that basename under the spec's directory;
//!   two different files with one basename is an error, the builder would copy
//!   both into one SOURCES dir), archives by their config.yaml sha512. Included
//!   `.inc` sources are spec text, not inputs: their effect is in the other facts.
//!
//! The expanded build scripts (%prep .. %posttrans) are compared too, but a
//! difference there is a warning: a restructured spec may copy a file under a
//! suffixed name and rename it in %prep. `--prep` settles it: rpmbuild -bp at
//! patch fuzz 0 on both sides, and the two build trees must be identical.

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const DEFAULT_ARCHES: &[&str] = &["x86_64", "aarch64"];
pub const DEFAULT_MODES: &[&str] = &["default", "canister_build", "acvp_build", "kat_build"];
const SCRIPT_SECTIONS: &[&str] = &[
    "%prep", "%build", "%install", "%check", "%pre", "%post", "%preun", "%postun", "%posttrans",
    "%triggerin", "%triggerun",
];
const OTHER_SECTIONS: &[&str] = &["%files", "%description", "%package", "%changelog"];

/// What the comparison runs over.
pub struct Plan {
    pub base_root: PathBuf,
    pub new_root: PathBuf,
    pub pkg_dir: String,
    pub specs: Vec<String>,
    pub subreleases: Vec<u32>,
    pub arches: Vec<String>,
    pub modes: Vec<String>,
    /// Name suffixes a restructured tree adds on purpose (e.g. "6.1"); stripped
    /// from script lines before they are compared.
    pub suffixes: Vec<String>,
    pub work: PathBuf,
}

/// Evaluate a Photon `%global build_if %{photon_subrelease} <op> <n>` line.
/// No build_if means the spec builds for every subrelease.
pub fn build_if_holds(spec_text: &str, sr: u32) -> Result<bool, String> {
    for l in spec_text.lines() {
        let t: Vec<&str> = l.split_whitespace().collect();
        if t.len() >= 3 && (t[0] == "%global" || t[0] == "%define") && t[1] == "build_if" {
            let expr = t[2..].join(" ");
            let e = expr.replace("%{photon_subrelease}", &sr.to_string()).replace("0%{?photon_subrelease}", &sr.to_string());
            let p: Vec<&str> = e.split_whitespace().collect();
            if p.len() != 3 {
                return Err(format!("unsupported build_if: {expr}"));
            }
            let (a, op, b) = (p[0].parse::<i64>(), p[1], p[2].parse::<i64>());
            let (a, b) = match (a, b) {
                (Ok(a), Ok(b)) => (a, b),
                _ => return Err(format!("unsupported build_if: {expr}")),
            };
            return match op {
                "==" => Ok(a == b),
                "!=" => Ok(a != b),
                ">=" => Ok(a >= b),
                "<=" => Ok(a <= b),
                ">" => Ok(a > b),
                "<" => Ok(a < b),
                _ => Err(format!("unsupported build_if operator in: {expr}")),
            };
        }
    }
    Ok(true)
}

/// The spec Photon builds for `sr` in `root`: exactly one candidate's build_if must hold.
pub fn pick_spec(root: &Path, pkg_dir: &str, spec: &str, sr: u32) -> Result<PathBuf, String> {
    let mut cands = vec![root.join("SPECS").join(pkg_dir).join(spec)];
    if let Ok(rd) = fs::read_dir(root.join("SPECS")) {
        for e in rd.flatten() {
            let n = e.file_name().to_string_lossy().to_string();
            if n.chars().all(|c| c.is_ascii_digit()) {
                cands.push(e.path().join(pkg_dir).join(spec));
            }
        }
    }
    let mut hits = vec![];
    for c in cands {
        if let Ok(t) = fs::read_to_string(&c) {
            if build_if_holds(&t, sr)? {
                hits.push(c);
            }
        }
    }
    match hits.len() {
        1 => Ok(hits.remove(0)),
        0 => Err(format!("{}: no {pkg_dir}/{spec} builds for subrelease {sr}", root.display())),
        _ => Err(format!(
            "{}: {} specs claim subrelease {sr}: {}",
            root.display(),
            hits.len(),
            hits.iter().map(|p| p.display().to_string()).collect::<Vec<_>>().join(", ")
        )),
    }
}

/// Archive name -> sha512 from a config.yaml (the builder fetches these by checksum).
pub fn archives(config_yaml: &str) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    let mut cur: Option<String> = None;
    for l in config_yaml.lines() {
        let t = l.trim();
        if let Some(n) = t.strip_prefix("- archive:") {
            let n = n.trim().to_string();
            out.insert(n.clone(), String::new());
            cur = Some(n);
        } else if let Some(h) = t.strip_prefix("archive_sha512sum:") {
            if let Some(c) = &cur {
                out.insert(c.clone(), h.trim().trim_matches('\'').trim_matches('"').to_string());
            }
        } else if !l.starts_with(' ') && !l.starts_with('-') && !t.is_empty() {
            cur = None;
        }
    }
    out
}

/// `SourceN:`/`PatchN:` lines of `rpmspec -P` output, as (key, basename).
pub fn numbered_sources(parsed: &str) -> Vec<(String, String)> {
    let mut out = vec![];
    for l in parsed.lines() {
        let Some((head, val)) = l.split_once(':') else { continue };
        let kind = if head.starts_with("Source") {
            "Source"
        } else if head.starts_with("Patch") {
            "Patch"
        } else {
            continue;
        };
        let num = &head[kind.len()..];
        if !num.chars().all(|c| c.is_ascii_digit()) || head.contains(' ') {
            continue;
        }
        let v = val.trim();
        if v.is_empty() || v.contains(char::is_whitespace) {
            continue;
        }
        let name = v.rsplit('/').next().unwrap_or(v).to_string();
        out.push((format!("{kind}{}", if num.is_empty() { "0" } else { num }), name));
    }
    out
}

/// The expanded build and scriptlet sections, comments and blank lines dropped.
pub fn scripts(parsed: &str) -> Vec<String> {
    let mut out = vec![];
    let mut keep = false;
    for l in parsed.lines() {
        let head = l.split_whitespace().next().unwrap_or("");
        if head.starts_with('%') && (SCRIPT_SECTIONS.contains(&head) || OTHER_SECTIONS.contains(&head)) {
            keep = SCRIPT_SECTIONS.contains(&head);
            if keep {
                out.push(l.trim().to_string());
            }
            continue;
        }
        if keep && !l.trim().is_empty() && !l.trim_start().starts_with('#') {
            out.push(l.trim_end().to_string());
        }
    }
    out
}

/// Remove `-<suffix>` where it ends a file name: before an extension or at a name end.
pub fn strip_suffixes(line: &str, suffixes: &[String]) -> String {
    let mut s = line.to_string();
    for suf in suffixes {
        let pat = format!("-{suf}");
        let mut out = String::with_capacity(s.len());
        let mut rest = s.as_str();
        while let Some(i) = rest.find(&pat) {
            let after = &rest[i + pat.len()..];
            let next = after.chars().next();
            let ends_name = match next {
                None => true,
                Some('.') => after[1..].chars().next().is_some_and(|c| c.is_ascii_alphabetic()),
                Some(c) => !(c.is_ascii_alphanumeric() || c == '-' || c == '_'),
            };
            out.push_str(&rest[..i]);
            if !ends_name {
                out.push_str(&pat);
            }
            rest = after;
        }
        out.push_str(rest);
        s = out;
    }
    s
}

/// A flat SOURCES dir as the package builder stages it, symlinks by basename.
pub fn stage(spec_dir: &Path, into: &Path) -> Result<(), String> {
    if into.exists() {
        for e in fs::read_dir(into).map_err(|e| format!("{}: {e}", into.display()))?.flatten() {
            fs::remove_file(e.path()).map_err(|e| format!("{}: {e}", e))?;
        }
    } else {
        fs::create_dir_all(into).map_err(|e| format!("{}: {e}", into.display()))?;
    }
    let mut seen: BTreeMap<String, PathBuf> = BTreeMap::new();
    let mut stack = vec![spec_dir.to_path_buf()];
    while let Some(d) = stack.pop() {
        for e in fs::read_dir(&d).map_err(|e| format!("{}: {e}", d.display()))?.flatten() {
            let p = e.path();
            if p.is_dir() {
                stack.push(p);
                continue;
            }
            let n = e.file_name().to_string_lossy().to_string();
            let real = fs::canonicalize(&p).map_err(|e| format!("{}: {e}", p.display()))?;
            if let Some(prev) = seen.get(&n) {
                if fs::read(prev).ok() != fs::read(&real).ok() {
                    return Err(format!(
                        "{} stages two different files named {n}: {} and {}",
                        spec_dir.display(),
                        prev.display(),
                        real.display()
                    ));
                }
                continue;
            }
            seen.insert(n, real);
        }
    }
    for (n, p) in &seen {
        std::os::unix::fs::symlink(p, into.join(n)).map_err(|e| format!("{n}: {e}"))?;
    }
    Ok(())
}

fn rpmspec(staged: &Path, spec: &Path, sr: u32, arch: &str, mode: &str, extra: &[&str]) -> (bool, String, String) {
    let mut a: Vec<String> = vec![
        "--target".into(), arch.into(),
        "--define".into(), format!("_sourcedir {}", staged.display()),
        "--define".into(), format!("photon_subrelease {sr}"),
        "--define".into(), "dist .ph5".into(),
    ];
    if mode != "default" {
        a.push("--define".into());
        a.push(format!("{mode} 1"));
    }
    a.extend(extra.iter().map(|s| s.to_string()));
    a.push(spec.display().to_string());
    match Command::new("rpmspec").args(&a).output() {
        Ok(o) => (
            o.status.success(),
            String::from_utf8_lossy(&o.stdout).to_string(),
            String::from_utf8_lossy(&o.stderr).to_string(),
        ),
        Err(e) => (false, String::new(), format!("running rpmspec: {e}")),
    }
}

/// Everything compared for one side of one cell.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Facts {
    pub refused: Option<String>,
    pub packages: BTreeMap<String, BTreeSet<String>>,
    pub buildrequires: Vec<String>,
    pub changelog: String,
    pub sources: BTreeMap<String, (String, String)>,
    pub scripts: Vec<String>,
}

fn content_of(spec_dir: &Path, name: &str, archives: &BTreeMap<String, String>, index: &BTreeMap<String, PathBuf>) -> String {
    if let Some(p) = index.get(name) {
        return crate::sha256::file(p).unwrap_or_else(|e| format!("UNREADABLE:{e}"));
    }
    match archives.get(name) {
        Some(h) if !h.is_empty() => format!("archive:{h}"),
        Some(_) => "archive:no-sha512".into(),
        None => format!("MISSING under {}", spec_dir.display()),
    }
}

pub fn facts(spec: &Path, staged: &Path, sr: u32, arch: &str, mode: &str, suffixes: &[String]) -> Facts {
    let mut f = Facts::default();
    let (ok, parsed, err) = rpmspec(staged, spec, sr, arch, mode, &["-P"]);
    if !ok {
        let why = err.lines().filter(|l| l.to_lowercase().contains("error")).last().unwrap_or(err.trim()).to_string();
        f.refused = Some(why);
        return f;
    }
    let qf = "@%{name}-%{epoch}:%{version}-%{release}.%{arch}\n[R %{REQUIRENEVRS}\n][P %{PROVIDENEVRS}\n][C %{CONFLICTNEVRS}\n][O %{OBSOLETENEVRS}\n]";
    let (_, out, _) = rpmspec(staged, spec, sr, arch, mode, &["-q", "--qf", qf]);
    let mut cur: Option<String> = None;
    for l in out.lines() {
        if let Some(n) = l.strip_prefix('@') {
            cur = Some(n.to_string());
            f.packages.entry(n.to_string()).or_default();
        } else if let Some(c) = &cur {
            f.packages.get_mut(c).map(|s| s.insert(l.to_string()));
        }
    }
    let (_, br, _) = rpmspec(staged, spec, sr, arch, mode, &["-q", "--buildrequires"]);
    f.buildrequires = br.lines().map(String::from).collect();
    f.buildrequires.sort();
    let (_, cl, _) = rpmspec(staged, spec, sr, arch, mode, &["-q", "--srpm", "--changelog"]);
    f.changelog = cl;
    let spec_dir = spec.parent().unwrap_or(Path::new("."));
    let arch_map = fs::read_to_string(spec_dir.join("config.yaml")).map(|t| archives(&t)).unwrap_or_default();
    let mut index = BTreeMap::new();
    if let Ok(rd) = fs::read_dir(staged) {
        for e in rd.flatten() {
            if let Ok(t) = fs::canonicalize(e.path()) {
                index.insert(e.file_name().to_string_lossy().to_string(), t);
            }
        }
    }
    for (k, name) in numbered_sources(&parsed) {
        if name.ends_with(".inc") {
            continue;
        }
        let c = content_of(spec_dir, &name, &arch_map, &index);
        f.sources.insert(k, (name, c));
    }
    let sd = staged.display().to_string();
    f.scripts = scripts(&parsed)
        .into_iter()
        .map(|l| strip_suffixes(&l.replace(&sd, "<SRCDIR>"), suffixes))
        .collect();
    f
}

/// Hard differences, and script lines that differ (warnings).
pub fn compare(a: &Facts, b: &Facts) -> (Vec<String>, Vec<String>) {
    let mut hard = vec![];
    match (&a.refused, &b.refused) {
        (Some(_), Some(_)) => return (hard, vec![]),
        (Some(x), None) => return (vec![format!("only the reference refuses: {x}")], vec![]),
        (None, Some(y)) => return (vec![format!("only the new tree refuses: {y}")], vec![]),
        _ => {}
    }
    let names: BTreeSet<&String> = a.packages.keys().chain(b.packages.keys()).collect();
    for p in names {
        let (x, y) = (a.packages.get(p), b.packages.get(p));
        if x != y {
            let empty = BTreeSet::new();
            let (x, y) = (x.unwrap_or(&empty), y.unwrap_or(&empty));
            let only_a: Vec<&String> = x.difference(y).take(6).collect();
            let only_b: Vec<&String> = y.difference(x).take(6).collect();
            hard.push(format!("package {p}: only in reference {only_a:?}, only in new {only_b:?}"));
        }
    }
    if a.buildrequires != b.buildrequires {
        hard.push("BuildRequires differ".into());
    }
    if a.changelog != b.changelog {
        hard.push("%changelog differs".into());
    }
    let keys: BTreeSet<&String> = a.sources.keys().chain(b.sources.keys()).collect();
    for k in keys {
        match (a.sources.get(k), b.sources.get(k)) {
            (Some(x), Some(y)) if x.1 == y.1 && !y.1.starts_with("MISSING") => {}
            (x, y) => hard.push(format!(
                "{k}: reference {} / new {}",
                x.map(|v| format!("{}:{}", v.0, short(&v.1))).unwrap_or_else(|| "-".into()),
                y.map(|v| format!("{}:{}", v.0, short(&v.1))).unwrap_or_else(|| "-".into())
            )),
        }
    }
    let mut warn = vec![];
    if a.scripts != b.scripts {
        let sa: BTreeSet<&String> = a.scripts.iter().collect();
        let sb: BTreeSet<&String> = b.scripts.iter().collect();
        warn.extend(sa.difference(&sb).map(|l| format!("- {l}")));
        warn.extend(sb.difference(&sa).map(|l| format!("+ {l}")));
        if warn.is_empty() {
            warn.push("the same script lines in another order".into());
        }
    }
    (hard, warn)
}

fn short(s: &str) -> String {
    if s.len() > 24 && !s.starts_with("MISSING") { s[..24].to_string() } else { s.to_string() }
}

/// rpmbuild -bp at fuzz 0; the manifest is "<sha256|->target> <relative path>" for every file under BUILD.
pub fn prep_manifest(spec: &Path, staged: &Path, top: &Path, sr: u32, arch: &str, mode: &str) -> Result<Vec<String>, String> {
    fs::create_dir_all(top).map_err(|e| format!("{}: {e}", top.display()))?;
    let mut a: Vec<String> = vec![
        "-bp".into(), "--nodeps".into(), "--target".into(), arch.into(),
        "--define".into(), format!("_topdir {}", top.display()),
        "--define".into(), format!("_sourcedir {}", staged.display()),
        "--define".into(), format!("photon_subrelease {sr}"),
        "--define".into(), "dist .ph5".into(),
        "--define".into(), "_default_patch_fuzz 0".into(),
    ];
    if mode != "default" {
        a.push("--define".into());
        a.push(format!("{mode} 1"));
    }
    a.push(spec.display().to_string());
    let o = Command::new("rpmbuild").args(&a).output().map_err(|e| format!("running rpmbuild: {e}"))?;
    if !o.status.success() {
        let err = String::from_utf8_lossy(&o.stderr);
        let out = String::from_utf8_lossy(&o.stdout);
        let tail: Vec<&str> = out.lines().chain(err.lines()).rev().take(6).collect();
        return Err(format!("%prep failed: {}", tail.into_iter().rev().collect::<Vec<_>>().join(" | ")));
    }
    let build = top.join("BUILD");
    let mut out = vec![];
    let mut stack = vec![build.clone()];
    while let Some(d) = stack.pop() {
        for e in fs::read_dir(&d).map_err(|e| format!("{}: {e}", d.display()))?.flatten() {
            let p = e.path();
            let rel = p.strip_prefix(&build).unwrap_or(&p).display().to_string();
            let md = fs::symlink_metadata(&p).map_err(|e| format!("{}: {e}", p.display()))?;
            if md.file_type().is_symlink() {
                out.push(format!("->{} {rel}", fs::read_link(&p).map(|t| t.display().to_string()).unwrap_or_default()));
            } else if md.is_dir() {
                stack.push(p);
            } else {
                out.push(format!("{} {rel}", crate::sha256::file(&p)?));
            }
        }
    }
    out.sort();
    Ok(out)
}

/// Run the plan; prints one line per cell and returns the number of cells with hard differences.
pub fn run(plan: &Plan, prep: bool, neutralize: &[String]) -> Result<usize, String> {
    let mut bad = 0;
    let mut warned = 0;
    let mut staged_dirs: BTreeMap<PathBuf, PathBuf> = BTreeMap::new();
    let mut stage_for = |spec: &Path, side: &str| -> Result<PathBuf, String> {
        let d = spec.parent().unwrap_or(Path::new(".")).to_path_buf();
        if let Some(s) = staged_dirs.get(&d) {
            return Ok(s.clone());
        }
        let into = plan.work.join(format!("stage-{side}-{}", staged_dirs.len()));
        stage(&d, &into)?;
        staged_dirs.insert(d, into.clone());
        Ok(into)
    };
    for &sr in &plan.subreleases {
        for spec in &plan.specs {
            let a_spec = pick_spec(&plan.base_root, &plan.pkg_dir, spec, sr)?;
            let b_spec = pick_spec(&plan.new_root, &plan.pkg_dir, spec, sr)?;
            let sa = stage_for(&a_spec, "base")?;
            let sb = stage_for(&b_spec, "new")?;
            for arch in &plan.arches {
                for mode in &plan.modes {
                    let fa = facts(&a_spec, &sa, sr, arch, mode, &plan.suffixes);
                    let fb = facts(&b_spec, &sb, sr, arch, mode, &plan.suffixes);
                    let (hard, warn) = compare(&fa, &fb);
                    let cell = format!("sr{sr} {spec} {arch} {mode}");
                    let state = if fa.refused.is_some() && fb.refused.is_some() {
                        "refused"
                    } else if !hard.is_empty() {
                        "DIFF"
                    } else if !warn.is_empty() {
                        "scripts"
                    } else {
                        "ok"
                    };
                    println!("  [{state:7}] {cell}");
                    for h in hard.iter().take(30) {
                        println!("            {h}");
                    }
                    for w in warn.iter().take(12) {
                        println!("            script {w}");
                    }
                    bad += usize::from(!hard.is_empty());
                    warned += usize::from(hard.is_empty() && !warn.is_empty());
                    if prep && fa.refused.is_none() && fb.refused.is_none() {
                        let (pa, pb) = (plan.work.join("prep-stage-base"), plan.work.join("prep-stage-new"));
                        stage(a_spec.parent().unwrap_or(Path::new(".")), &pa)?;
                        stage(b_spec.parent().unwrap_or(Path::new(".")), &pb)?;
                        neutralize_includes(&pa, neutralize)?;
                        neutralize_includes(&pb, neutralize)?;
                        let ma = prep_manifest(&a_spec, &pa, &plan.work.join("top-base"), sr, arch, mode);
                        let mb = prep_manifest(&b_spec, &pb, &plan.work.join("top-new"), sr, arch, mode);
                        match (ma, mb) {
                            (Ok(x), Ok(y)) if x == y => println!("            %prep: identical trees ({} files)", x.len()),
                            (Ok(x), Ok(y)) => {
                                bad += usize::from(hard.is_empty());
                                let sx: BTreeSet<&String> = x.iter().collect();
                                let sy: BTreeSet<&String> = y.iter().collect();
                                println!("            %prep: TREES DIFFER ({} only in reference, {} only in new)", sx.difference(&sy).count(), sy.difference(&sx).count());
                            }
                            (Err(e), Err(f)) => println!("            %prep: both sides fail here (reference: {e}; new: {f})"),
                            (Err(e), Ok(_)) => println!("            %prep: only the reference fails: {e}"),
                            (Ok(_), Err(f)) => {
                                bad += usize::from(hard.is_empty());
                                println!("            %prep: only the new tree fails: {f}");
                            }
                        }
                    }
                }
            }
        }
    }
    println!("spec-parity: {bad} cell(s) differ, {warned} with script-only differences");
    Ok(bad)
}

/// Replace staged includes whose name starts with one of `prefixes` by a no-op on both
/// sides alike: for checks that depend on the host's toolchain, not on the spec.
fn neutralize_includes(staged: &Path, prefixes: &[String]) -> Result<(), String> {
    if prefixes.is_empty() {
        return Ok(());
    }
    for e in fs::read_dir(staged).map_err(|e| format!("{}: {e}", staged.display()))?.flatten() {
        let n = e.file_name().to_string_lossy().to_string();
        if n.ends_with(".inc") && prefixes.iter().any(|p| n.starts_with(p.as_str())) {
            let p = e.path();
            fs::remove_file(&p).map_err(|e| format!("{}: {e}", p.display()))?;
            fs::write(&p, format!("echo \"{n}: neutralized for the parity run on this host\"\n"))
                .map_err(|e| format!("{}: {e}", p.display()))?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_if_is_evaluated_like_photon_does() {
        let s = "%global build_if %{photon_subrelease} >= 92\nName: x\n";
        assert!(build_if_holds(s, 92).unwrap());
        assert!(!build_if_holds(s, 91).unwrap());
        assert!(build_if_holds("%global build_if %{photon_subrelease} == 91\n", 91).unwrap());
        assert!(!build_if_holds("%global build_if %{photon_subrelease} <= 90\n", 91).unwrap());
        assert!(build_if_holds("Name: x\n", 7).unwrap());
        assert!(build_if_holds("%global build_if %{photon_subrelease} ~ 9\n", 7).is_err());
    }

    #[test]
    fn exactly_one_spec_must_claim_a_subrelease() {
        let d = std::env::temp_dir().join(format!("shk-parity-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(d.join("SPECS/linux")).unwrap();
        fs::create_dir_all(d.join("SPECS/90/linux")).unwrap();
        fs::write(d.join("SPECS/linux/linux.spec"), "%global build_if %{photon_subrelease} >= 91\n").unwrap();
        fs::write(d.join("SPECS/90/linux/linux.spec"), "%global build_if %{photon_subrelease} <= 90\n").unwrap();
        assert!(pick_spec(&d, "linux", "linux.spec", 90).unwrap().ends_with("SPECS/90/linux/linux.spec"));
        assert!(pick_spec(&d, "linux", "linux.spec", 92).unwrap().ends_with("SPECS/linux/linux.spec"));
        fs::write(d.join("SPECS/90/linux/linux.spec"), "%global build_if %{photon_subrelease} <= 91\n").unwrap();
        assert!(pick_spec(&d, "linux", "linux.spec", 91).unwrap_err().contains("2 specs claim"));
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn archives_come_with_their_sha512() {
        let y = "sources:\n- archive: linux-6.1.189.tar.xz\n  archive_type: upstream\n  version: 6.1.189\n  archive_sha512sum: 'abc'\n- archive: x.tar.gz\n  archive_sha512sum: \n";
        let a = archives(y);
        assert_eq!(a["linux-6.1.189.tar.xz"], "abc");
        assert_eq!(a["x.tar.gz"], "");
    }

    #[test]
    fn numbered_sources_take_the_basename_and_default_number() {
        let p = "Name: linux\nSource: https://k.org/linux-6.1.tar.xz\nSource7:        check.inc\nPatch3085: a-6.1.patch\nPatchN: no\nSummary: Patch: no\n";
        assert_eq!(
            numbered_sources(p),
            vec![
                ("Source0".to_string(), "linux-6.1.tar.xz".to_string()),
                ("Source7".to_string(), "check.inc".to_string()),
                ("Patch3085".to_string(), "a-6.1.patch".to_string()),
            ]
        );
    }

    #[test]
    fn scripts_keep_build_sections_only() {
        let p = "Name: x\n%description\nhello\n%prep\n# note\ncp a b\n\n%files\n/usr/bin/x\n%post\ndepmod -a\n%changelog\n* x\n";
        assert_eq!(scripts(p), vec!["%prep", "cp a b", "%post", "depmod -a"]);
    }

    #[test]
    fn declared_suffixes_are_stripped_at_name_ends_only() {
        let s = vec!["6.1".to_string(), "6.12.111".to_string()];
        assert_eq!(strip_suffixes("cp S/config_x86_64-6.1 .config", &s), "cp S/config_x86_64 .config");
        assert_eq!(strip_suffixes("cp S/a-6.1.patch x", &s), "cp S/a.patch x");
        assert_eq!(strip_suffixes("tar xf linux-6.1.189.tar.xz", &s), "tar xf linux-6.1.189.tar.xz");
        assert_eq!(strip_suffixes("b-6.12.111.patch", &s), "b.patch");
    }

    #[test]
    fn refusal_must_match_and_sources_compare_by_content() {
        let mut a = Facts::default();
        let mut b = Facts::default();
        a.sources.insert("Patch1".into(), ("p.patch".into(), "h1".into()));
        b.sources.insert("Patch1".into(), ("p-6.1.patch".into(), "h1".into()));
        assert_eq!(compare(&a, &b), (vec![], vec![]));
        b.sources.insert("Patch1".into(), ("p-6.1.patch".into(), "h2".into()));
        assert_eq!(compare(&a, &b).0.len(), 1);
        b.refused = Some("error: x".into());
        assert!(compare(&a, &b).0[0].contains("only the new tree refuses"));
        a.refused = Some("error: y".into());
        assert_eq!(compare(&a, &b), (vec![], vec![]));
    }

    #[test]
    fn staging_refuses_two_different_files_with_one_name() {
        let d = std::env::temp_dir().join(format!("shk-stage-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(d.join("t/a")).unwrap();
        fs::create_dir_all(d.join("t/b")).unwrap();
        fs::write(d.join("t/a/x.patch"), "1").unwrap();
        fs::write(d.join("t/b/x.patch"), "1").unwrap();
        stage(&d.join("t"), &d.join("s")).unwrap();
        assert!(d.join("s/x.patch").exists());
        fs::write(d.join("t/b/x.patch"), "2").unwrap();
        assert!(stage(&d.join("t"), &d.join("s2")).unwrap_err().contains("two different files named x.patch"));
        let _ = fs::remove_dir_all(&d);
    }
}
