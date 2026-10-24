//! `sharukhan canister-equivalent [--check]`: regenerate the embedded
//! canister-equivalent patch against the current tree (it replaced the
//! Python tools/regen-canister-equivalent.py, with identical output).
//!
//! The embedded patch layers on top of the installer variant patch, so its
//! context lines carry whatever kernel Release the variant patch produces.
//! Every time the kernel moves the patch stops applying, and hand-editing a
//! diff is how you get context that applies but means something else - so it
//! is regenerated from the real tree, never edited.
//!
//! What the patch expresses: `fips_canister_version` and
//! `fips_certified_kernel_version` become overridable (canister_equivalent=1
//! plus fips_canister_override=<NEVR>, canister_stamp_real=1 plus
//! fips_certified_override=<NEVR>), each as a 0/1 flag plus a value macro in
//! an %if, because Photon's SpecParser only sees definitions that start a line
//! and eval()s %if text; a Release bump and one changelog entry per flavour.
//!
//! Everything it writes is read from the tree: the kernel directory, the
//! subrelease, Version and Release, the published canister and certified
//! versions the overrides default to, the author. Each block it rewrites must
//! occur exactly once; a spec of another shape stops it.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

fn cmp(op: &str, a: u32, b: u32) -> bool {
    match op {
        "==" => a == b,
        "!=" => a != b,
        ">=" => a >= b,
        "<=" => a <= b,
        ">" => a > b,
        "<" => a < b,
        _ => false,
    }
}

/// `%if 0%{?photon_subrelease} >= 92` and its spellings: (op, number).
fn subrel_if(line: &str) -> Option<(String, u32)> {
    let rest = line.trim().strip_prefix("%if")?.trim();
    let rest = rest.strip_prefix('0').unwrap_or(rest);
    let rest = rest.strip_prefix("%{?photon_subrelease}").or_else(|| rest.strip_prefix("%{photon_subrelease}"))?.trim();
    let op = ["==", "!=", ">=", "<=", ">", "<"].into_iter().find(|o| rest.starts_with(o))?;
    let n = rest[op.len()..].trim().parse().ok()?;
    Some((op.to_string(), n))
}

/// Line indices that subrelease `sub` keeps: plain photon_subrelease
/// conditionals are decided, every other conditional line is kept (the rule
/// check_spec applies).
fn kept(lines: &[&str], sub: u32) -> Vec<usize> {
    // Some(taken) for a decided %if, None for any other
    let mut stack: Vec<Option<bool>> = Vec::new();
    let open = |s: &[Option<bool>]| s.iter().all(|f| f.unwrap_or(true));
    let mut out = Vec::new();
    for (i, line) in lines.iter().enumerate() {
        let s = line.trim();
        if let Some((op, n)) = subrel_if(s) {
            stack.push(Some(cmp(&op, sub, n)));
            continue;
        }
        if s.starts_with("%if") {
            if open(&stack) {
                out.push(i);
            }
            stack.push(None);
            continue;
        }
        if s.starts_with("%else") && !stack.is_empty() {
            match stack.last_mut() {
                Some(Some(t)) => *t = !*t,
                _ => {
                    if open(&stack) {
                        out.push(i);
                    }
                }
            }
            continue;
        }
        if s.starts_with("%endif") && !stack.is_empty() {
            if stack.pop().flatten().is_none() && open(&stack) {
                out.push(i);
            }
            continue;
        }
        if open(&stack) {
            out.push(i);
        }
    }
    out
}

pub fn resolved_lines(text: &str, sub: u32) -> Vec<String> {
    let lines: Vec<&str> = text.split('\n').collect();
    kept(&lines, sub).into_iter().map(|i| lines[i].to_string()).collect()
}

pub fn version_of(text: &str, sub: u32) -> Result<String, String> {
    resolved_lines(text, sub)
        .iter()
        .find_map(|l| l.strip_prefix("Version:").map(|v| v.trim().to_string()))
        .filter(|v| !v.is_empty())
        .ok_or_else(|| "no Version:".into())
}

/// The numeric Release subrelease `sub` builds, without conditionals or dist.
pub fn release_of(text: &str, sub: u32) -> Result<u32, String> {
    resolved_lines(text, sub)
        .iter()
        .find_map(|l| l.strip_prefix("Release:"))
        .and_then(|r| r.trim().chars().take_while(char::is_ascii_digit).collect::<String>().parse().ok())
        .ok_or_else(|| format!("no numeric Release: for subrelease {sub}"))
}

/// Bump the one Release: line subrelease `sub` builds, found by position, so
/// another subrelease's Release: is never touched even at the same number.
pub fn set_release(text: &str, sub: u32, old: u32, new: u32) -> Result<String, String> {
    let mut lines: Vec<String> = text.split('\n').map(str::to_string).collect();
    let refs: Vec<&str> = text.split('\n').collect();
    let i = kept(&refs, sub)
        .into_iter()
        .find(|&i| refs[i].starts_with("Release:"))
        .ok_or_else(|| format!("no Release: for subrelease {sub}"))?;
    let rest = &refs[i]["Release:".len()..];
    let ws: String = rest.chars().take_while(|c| c.is_whitespace()).collect();
    let num: String = rest[ws.len()..].chars().take_while(char::is_ascii_digit).collect();
    if num.parse::<u32>().ok() != Some(old) {
        return Err(format!("Release for subrelease {sub} is {num}, expected {old}"));
    }
    lines[i] = format!("Release:{ws}{new}{}", &rest[ws.len() + num.len()..]);
    Ok(lines.join("\n"))
}

/// Exactly one line `%define <name> <value>` starting a line: (line index, value).
fn one_define(text: &str, name: &str) -> Result<(usize, String), String> {
    let hits: Vec<(usize, String)> = text
        .split('\n')
        .enumerate()
        .filter_map(|(i, l)| {
            let v = l.strip_prefix("%define ")?.trim_start().strip_prefix(name)?;
            v.starts_with(char::is_whitespace).then(|| (i, v.trim().to_string()))
        })
        .collect();
    match hits.len() {
        1 => Ok(hits.into_iter().next().unwrap_or_default()),
        n => Err(format!("{n} '%define {name}' lines where exactly one was expected: the spec changed shape upstream and this must be updated, not worked around")),
    }
}

const CANISTER_BLOCK: &str = "# Which canister this build links.
#
# Default: the published, certified one. A build that has just created an
# equivalent canister from the kernel under test overrides it with
# canister_equivalent=1 plus fips_canister_override=<NEVR>.
#
# Two macros rather than one, and an %%if rather than a bang-question guard,
# because Photon's own SpecParser is stricter than rpm:
#   - _isDefinition() matches only a line STARTING with %%define/%%global, so
#     a guard of the bang-question form never reaches self.defs and
#     ExtraBuildRequiresSansSnapshot keeps the macro literal;
#   - _isConditionTrue() eval()s the expanded text after lstrip(\"0\"), which is
#     fine for a 0/1 flag and a NameError for a version string.
# So the flag is what %%if tests, and the version rides in a second macro.
%if 0%{?canister_equivalent}
%define fips_canister_version %{fips_canister_override}
%else
%define fips_canister_version @PUBLISHED@
%endif";

const CERT_OLD: [&str; 2] = ["# This is the last certified canister version", "# Remove below line when building a new canister"];

const CERT_BLOCK: &str = "# This is the last certified canister version, stamped into fips_integrity.c.
# A build that creates a NEW canister must stamp the kernel it was really built
# from rather than inherit a certification it does not carry, so
# canister_stamp_real=1 plus fips_certified_override=<NEVR> replaces it. Same
# two-macro shape as fips_canister_version below, for the same parser reasons.
%if 0%{?canister_stamp_real}
%define fips_certified_kernel_version %{fips_certified_override}
%else
%define fips_certified_kernel_version @CERTIFIED@
%endif";

/// `fips_canister_version` overridable, defaulting to the version the spec pins.
pub fn overridable_canister(text: &str) -> Result<String, String> {
    let (i, published) = one_define(text, "fips_canister_version")?;
    let mut lines: Vec<String> = text.split('\n').map(str::to_string).collect();
    lines[i] = CANISTER_BLOCK.replace("@PUBLISHED@", &published);
    Ok(lines.join("\n"))
}

/// `fips_certified_kernel_version` overridable, with the two comment lines
/// upstream writes above it replaced.
pub fn overridable_certified(text: &str) -> Result<String, String> {
    let (i, certified) = one_define(text, "fips_certified_kernel_version")?;
    let lines: Vec<&str> = text.split('\n').collect();
    if i < 2 || lines[i - 2] != CERT_OLD[0] || lines[i - 1] != CERT_OLD[1] {
        return Err("the fips_certified_kernel_version block is not where it is expected (its two comment lines are missing)".into());
    }
    let mut out: Vec<String> = lines[..i - 2].iter().map(|l| l.to_string()).collect();
    out.push(CERT_BLOCK.replace("@CERTIFIED@", &certified));
    out.extend(lines[i + 1..].iter().map(|l| l.to_string()));
    Ok(out.join("\n"))
}

pub fn linux_entry(date: &str, author: &str, vr: &str) -> String {
    format!(
        "* {date} {author} {vr}
- Let a build link a canister other than the published one, so a kernel with no
  official canister at its own level can be covered by an equivalent one built
  locally. canister_equivalent=1 plus fips_canister_override=<NEVR> selects it;
  with neither set the published pin is used and nothing changes.
- Same for fips_certified_kernel_version via canister_stamp_real=1 plus
  fips_certified_override=<NEVR>, so a newly created canister stamps the kernel
  it was really built from instead of inheriting a certification it does not
  carry.
- Both wrap a plain definition in a conditional on a 0/1 flag, rather than
  using the bang-question guard form. rpm expands that guard correctly, but
  Photon's SpecParser._isDefinition() matches only a line STARTING with a
  definition directive, so the guard never reaches self.defs and
  ExtraBuildRequiresSansSnapshot keeps the macro unexpanded - the build then
  asks tdnf for a package whose name still contains the macro reference. The
  version cannot be tested by the conditional either: _isConditionTrue() runs
  eval() on the expanded text after lstrip(\"0\"), which is a NameError for a
  version string. Hence a 0/1 flag plus a separate value macro.
"
    )
}

pub fn esx_entry(date: &str, author: &str, vr: &str) -> String {
    format!(
        "* {date} {author} {vr}
- Accept the same canister_equivalent / fips_canister_override pair as
  linux.spec, so this flavour - the one the ISO actually boots - can link a
  locally built canister too. It never builds one; it only links.
"
    )
}

pub fn insert_changelog(text: &str, entry: &str) -> Result<String, String> {
    if !text.contains("%changelog\n") {
        return Err("no %changelog".into());
    }
    Ok(text.replacen("%changelog\n", &format!("%changelog\n{entry}"), 1))
}

/// (spec, preamble, changelog) of one flavour, relative to the tree: the
/// single-source spec keeps Release, the pins and the changelog of each kernel
/// in included files it picks by subrelease; otherwise all three are the spec.
pub fn kernel_files(tree: &Path, kdir: &str, flavour: &str, sub: u32) -> Result<(String, String, String), String> {
    let spec = format!("{kdir}/{flavour}.spec");
    let text = fs::read_to_string(tree.join(&spec)).map_err(|e| format!("{spec}: {e}"))?;
    let mut sources = std::collections::BTreeMap::new();
    let (mut pre, mut clog) = (spec.clone(), spec.clone());
    for l in resolved_lines(&text, sub) {
        if let Some(rest) = l.strip_prefix("Source") {
            let (n, v) = rest.split_once(':').unwrap_or(("", ""));
            if !n.is_empty() && n.chars().all(|c| c.is_ascii_digit()) {
                sources.insert(n.to_string(), v.trim().to_string());
            }
            continue;
        }
        let Some(n) = l.trim().strip_prefix("%include %{SOURCE").and_then(|r| r.strip_suffix('}')) else { continue };
        let Some(name) = sources.get(n) else { continue };
        let mid = name.strip_prefix(&format!("{flavour}-")).unwrap_or("");
        let numeric = |s: &str| !s.is_empty() && s.chars().all(|c| c.is_ascii_digit() || c == '.');
        if name == &format!("{flavour}-changelog.inc") || mid.strip_suffix("-changelog.inc").is_some_and(numeric) {
            clog = format!("{kdir}/{name}");
        } else if mid.strip_suffix(".inc").is_some_and(numeric) {
            pre = format!("{kdir}/{name}");
        }
    }
    Ok((spec, pre, clog))
}

fn git(dir: &Path, args: &[&str]) -> Result<String, String> {
    let o = Command::new("git").arg("-C").arg(dir).args(args).output().map_err(|e| format!("git: {e}"))?;
    if !o.status.success() {
        return Err(format!("git {} failed: {}", args.join(" "), String::from_utf8_lossy(&o.stderr).trim()));
    }
    Ok(String::from_utf8_lossy(&o.stdout).to_string())
}

pub struct Request<'a> {
    pub repo: &'a Path,
    pub base: &'a str,
    pub variant: &'a Path,
    pub common: &'a Path,
    pub date: &'a str,
    pub author: &'a crate::author::Author,
}

/// The regenerated patch, checked with check_spec in the builder.
pub fn regenerate(r: &Request, log: &mut dyn FnMut(&str)) -> Result<String, String> {
    if !r.variant.is_file() {
        return Err(format!("{}: not found - run `sharukhan variant-patches` first", r.variant.display()));
    }
    let checker = r.common.join("support/spec-checker/check_spec.py");
    if !checker.is_file() {
        return Err(format!("{}: the spec checker is required", checker.display()));
    }
    static SEQ: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let n = SEQ.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    // under the builder's shared root, so the checker container sees it
    let tree: PathBuf = crate::builder::shared_root().join(format!("work/caneq-{}-{n}", std::process::id()));
    let _ = git(r.repo, &["worktree", "remove", "--force", &tree.to_string_lossy()]);
    git(r.repo, &["worktree", "add", "-f", "-q", "--detach", &tree.to_string_lossy(), r.base])?;
    let result = (|| {
        git(&tree, &["apply", &r.variant.to_string_lossy()])?;
        // the variant state as a commit, so the diff below is the embedded delta alone
        git(&tree, &["add", "-A"])?;
        git(&tree, &["-c", &format!("user.name={}", r.author.name), "-c", &format!("user.email={}", r.author.email), "commit", "-q", "-m", "variant baseline"])?;
        let sub = crate::specresolve::tree_subrelease(&tree).ok_or("the tree has no photon-subrelease")?;
        let kdir = crate::specresolve::kernel_dir(&tree, Some(sub))?;
        let read = |p: &str| fs::read_to_string(tree.join(p)).map_err(|e| format!("{p}: {e}"));
        let mut edited = Vec::new();
        for flavour in ["linux", "linux-esx"] {
            let (spec, pre, clog) = kernel_files(&tree, &kdir, flavour, sub)?;
            let ver = version_of(&read(&spec)?, sub).map_err(|e| format!("{spec}: {e}"))?;
            let mut p = read(&pre)?;
            let old = release_of(&p, sub).map_err(|e| format!("{pre}: {e}"))?;
            log(&format!("  subrelease {sub}: the variant patch leaves {flavour} at {ver}-{old}"));
            if flavour == "linux" {
                p = overridable_certified(&p).map_err(|e| format!("{pre}: {e}"))?;
            }
            p = overridable_canister(&p).map_err(|e| format!("{pre}: {e}"))?;
            p = set_release(&p, sub, old, old + 1).map_err(|e| format!("{pre}: {e}"))?;
            let vr = format!("{ver}-{}", old + 1);
            let entry = if flavour == "linux" { linux_entry(r.date, &r.author.line(), &vr) } else { esx_entry(r.date, &r.author.line(), &vr) };
            if clog == pre {
                p = insert_changelog(&p, &entry).map_err(|e| format!("{pre}: {e}"))?;
                fs::write(tree.join(&pre), &p).map_err(|e| format!("{pre}: {e}"))?;
            } else {
                fs::write(tree.join(&pre), &p).map_err(|e| format!("{pre}: {e}"))?;
                let c = insert_changelog(&read(&clog)?, &entry).map_err(|e| format!("{clog}: {e}"))?;
                fs::write(tree.join(&clog), c).map_err(|e| format!("{clog}: {e}"))?;
            }
            log(&format!("  the embedded patch takes {flavour} to {vr}"));
            edited.push(tree.join(&spec));
        }
        // the specs as build.py checks them
        let mut args: Vec<std::ffi::OsString> = vec![checker.clone().into(), "--subrelease".into(), sub.to_string().into()];
        args.extend(edited.iter().map(|p| p.clone().into_os_string()));
        let o = crate::builder::python_command(r.common, &args, log)?.output().map_err(|e| format!("check_spec: {e}"))?;
        if !o.status.success() {
            return Err(format!(
                "the regenerated specs do not pass check_spec:\n{}{}",
                String::from_utf8_lossy(&o.stdout),
                String::from_utf8_lossy(&o.stderr)
            ));
        }
        log("  check_spec: exit 0");
        // index lines carry blob hashes that churn on every base move
        let diff = git(&tree, &["diff", "--", &format!("{kdir}/")])?;
        Ok(diff.lines().filter(|l| !l.starts_with("index ") && !l.starts_with("diff --git")).map(|l| format!("{l}\n")).collect())
    })();
    let _ = git(r.repo, &["worktree", "remove", "--force", &tree.to_string_lossy()]);
    result
}

pub fn cli(cfg: &crate::config::Config, args: &[String]) -> Result<(), String> {
    let flag = |n: &str| args.iter().position(|a| a == n).and_then(|i| args.get(i + 1)).cloned();
    let check = args.iter().any(|a| a == "--check");
    let repo = flag("--repo").map(PathBuf::from).unwrap_or_else(|| cfg.photon_tree.clone());
    let base = match flag("--base") {
        Some(b) => b,
        None => format!("origin/{}", crate::specresolve::branch_of(&repo)?),
    };
    let dflt = crate::variants::load(&cfg.variants_file)?.default_variant().name.clone();
    let variant = flag("--variant").map(PathBuf::from).unwrap_or_else(|| cfg.variant_patches.join(format!("poi-{dflt}.patch")));
    let common = flag("--common").map(PathBuf::from).unwrap_or_else(|| crate::builder::shared_root().join("work/common-check"));
    let date = match flag("--date") {
        Some(d) => d,
        None => {
            let o = Command::new("date").args(["-u", "+%a %b %d %Y"]).output().map_err(|e| format!("date: {e}"))?;
            String::from_utf8_lossy(&o.stdout).trim().to_string()
        }
    };
    let author = crate::author::resolve(Some(&repo))?;
    let req = Request { repo: &repo, base: &base, variant: &variant, common: &common, date: &date, author: &author };
    let patch = regenerate(&req, &mut |l| println!("{l}"))?;
    if check {
        // the embedded copy of this binary; context and numbers, not the date
        let same = |a: &str| a.lines().filter(|l| !l.starts_with("+* ")).collect::<Vec<_>>().join("\n");
        if same(&patch) == same(crate::buildmode::Embedded::CanisterEquivalent.patch()) {
            println!("  up to date");
            return Ok(());
        }
        return Err("STALE: the embedded patch does not match a regeneration".into());
    }
    let out = flag("--out").ok_or("--out <file> (the source tree's src/embedded/canister-equivalent.patch), or --check")?;
    fs::write(&out, &patch).map_err(|e| format!("{out}: {e}"))?;
    println!("  wrote {out} ({} lines)", patch.lines().count());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const PRE: &str = "%if 0%{?photon_subrelease} == 91\nRelease:        4%{?dist}\n%else\nRelease:        6%{?dist}\n%endif\n\
%global fips 1\n# This is the last certified canister version\n# Remove below line when building a new canister\n\
%define fips_certified_kernel_version 6.12.60-18.ph5\n%if 0%{?canister_usage}\n%define fips_canister_version 6.12.60-18.2.ph5\n%endif\n";

    #[test]
    fn the_release_of_the_subrelease_is_read_and_bumped_in_place() {
        assert_eq!(release_of(PRE, 92).unwrap(), 6);
        assert_eq!(release_of(PRE, 91).unwrap(), 4);
        let s = set_release(PRE, 92, 6, 7).unwrap();
        assert!(s.contains("Release:        4%{?dist}\n%else\nRelease:        7%{?dist}"), "{s}");
        assert!(set_release(PRE, 92, 5, 6).unwrap_err().contains("expected 5"));
    }

    #[test]
    fn the_overrides_keep_the_versions_the_spec_pins() {
        let s = overridable_canister(&overridable_certified(PRE).unwrap()).unwrap();
        assert!(s.contains("%define fips_certified_kernel_version 6.12.60-18.ph5\n%endif"), "{s}");
        assert!(s.contains("%define fips_canister_version 6.12.60-18.2.ph5\n%endif"), "{s}");
        assert!(s.contains("%if 0%{?canister_equivalent}") && s.contains("%if 0%{?canister_stamp_real}"));
        assert!(!s.contains("# Remove below line when building a new canister"));
    }

    #[test]
    fn a_spec_of_another_shape_stops_it() {
        let two = format!("{PRE}%define fips_canister_version 1\n");
        assert!(overridable_canister(&two).unwrap_err().contains("2 '%define fips_canister_version'"));
        let bare = PRE.replace("# Remove below line when building a new canister\n", "");
        assert!(overridable_certified(&bare).unwrap_err().contains("comment lines"));
    }

    #[test]
    fn the_entry_names_the_configured_author() {
        let e = linux_entry("Sat Oct 24 2026", "Ada Lovelace <ada@example.org>", "6.12.113-7");
        assert!(e.starts_with("* Sat Oct 24 2026 Ada Lovelace <ada@example.org> 6.12.113-7\n- Let a build"));
        let c = insert_changelog("x\n%changelog\n* old\n", &esx_entry("D", "A <a@b>", "1-2")).unwrap();
        assert!(c.starts_with("x\n%changelog\n* D A <a@b> 1-2\n"));
    }

    #[test]
    fn included_preamble_and_changelog_are_found_by_subrelease() {
        let d = std::env::temp_dir().join(format!("shk-caneq-{}", std::process::id()));
        fs::create_dir_all(d.join("SPECS/92/linux")).unwrap();
        fs::write(
            d.join("SPECS/92/linux/linux.spec"),
            "Source990: linux-6.1.inc\nSource991: linux-6.12.inc\nSource993: linux-6.12-changelog.inc\n\
%if 0%{?photon_subrelease} <= 90\n%include %{SOURCE990}\n%else\n%include %{SOURCE991}\n%endif\n%changelog\n%include %{SOURCE993}\n",
        )
        .unwrap();
        let (s, p, c) = kernel_files(&d, "SPECS/92/linux", "linux", 92).unwrap();
        assert_eq!((s.as_str(), p.as_str(), c.as_str()), ("SPECS/92/linux/linux.spec", "SPECS/92/linux/linux-6.12.inc", "SPECS/92/linux/linux-6.12-changelog.inc"));
        let (_, p90, _) = kernel_files(&d, "SPECS/92/linux", "linux", 90).unwrap();
        assert_eq!(p90, "SPECS/92/linux/linux-6.1.inc");
        let _ = fs::remove_dir_all(&d);
    }
}
