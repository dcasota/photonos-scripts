//! Read a spec the way one Photon subrelease sees it.
//!
//! A spec can serve several subreleases. SPECS/linux/linux.spec builds kernel
//! 6.1 up to photon_subrelease 90 and 6.12 from 91, with each kernel's preamble
//! and changelog in included files. A reader that takes the first `Version:`
//! line of the raw file answers for the wrong kernel, and one that ignores
//! `%include` finds no `Release:` at all.
//!
//! This applies the two steps check_spec applies: plain
//! `%if 0%{?photon_subrelease} <op> <n>` blocks are decided for one
//! subrelease, and `%include`d files are inlined. Every other conditional is
//! left in place, because deciding those needs rpm. A spec with neither comes
//! back unchanged.

use std::path::Path;
use std::process::Command;

/// Includes nest a level or two in practice; the bound only stops a file that
/// includes itself.
const MAX_INCLUDE_DEPTH: usize = 8;

/// The spec `spec` as subrelease `subrelease` sees it, or None when it cannot
/// be read. `read` maps a file name inside the spec directory to its content.
///
/// With `subrelease` None the subrelease conditionals stay, and includes on
/// both sides of them are inlined.
pub fn resolve(
    read: &dyn Fn(&str) -> Option<String>,
    spec: &str,
    subrelease: Option<u32>,
) -> Option<String> {
    let text = read(spec)?;
    let mut st = State { stack: Vec::new(), sources: Vec::new(), out: String::new() };
    process(read, &text, subrelease, &mut st, 0);
    Some(st.out)
}

struct State {
    /// One frame per open conditional: None when it is left to rpm,
    /// Some(taken) for a subrelease comparison decided here. Frames span
    /// include boundaries, as they do in rpm.
    stack: Vec<Option<bool>>,
    /// Source tags seen so far, for `%include %{SOURCEn}`.
    sources: Vec<(String, String)>,
    out: String,
}

fn active(stack: &[Option<bool>]) -> bool {
    stack.iter().all(|f| f.unwrap_or(true))
}

fn process(
    read: &dyn Fn(&str) -> Option<String>,
    text: &str,
    subrelease: Option<u32>,
    st: &mut State,
    depth: usize,
) {
    for line in text.lines() {
        let t = line.trim();
        if let (Some(n), Some((op, rhs))) = (subrelease, subrelease_cond(t)) {
            st.stack.push(Some(compare(op, n, rhs)));
            continue;
        }
        if t.starts_with("%if") {
            if active(&st.stack) {
                push(&mut st.out, line);
            }
            st.stack.push(None);
            continue;
        }
        if t.starts_with("%else") && !st.stack.is_empty() {
            let keep = active(&st.stack[..st.stack.len() - 1]);
            match st.stack.last_mut() {
                Some(Some(taken)) => *taken = !*taken,
                _ => {
                    if keep {
                        push(&mut st.out, line);
                    }
                }
            }
            continue;
        }
        if t.starts_with("%endif") && !st.stack.is_empty() {
            if st.stack.pop().flatten().is_none() && active(&st.stack) {
                push(&mut st.out, line);
            }
            continue;
        }
        if !active(&st.stack) {
            continue;
        }
        if let Some(target) = t.strip_prefix("%include") {
            if depth < MAX_INCLUDE_DEPTH {
                if let Some(inner) = include_target(target.trim(), &st.sources).and_then(|n| read(&n)) {
                    process(read, &inner, subrelease, st, depth + 1);
                    continue;
                }
            }
        }
        if let Some(tag) = source_tag(t) {
            st.sources.push(tag);
        }
        push(&mut st.out, line);
    }
}

fn push(out: &mut String, line: &str) {
    out.push_str(line);
    out.push('\n');
}

/// `%if 0%{?photon_subrelease} >= 91` (also without the `0` or the `?`) as an
/// operator and a number. Anything more complex is rpm's to decide.
fn subrelease_cond(line: &str) -> Option<(&str, u32)> {
    let rest = line.strip_prefix("%if")?;
    if !rest.starts_with(char::is_whitespace) {
        return None;
    }
    let mut words = rest.split_whitespace();
    let (lhs, op, rhs) = (words.next()?, words.next()?, words.next()?);
    if words.next().is_some() {
        return None;
    }
    let lhs = lhs.strip_prefix('0').unwrap_or(lhs);
    if lhs != "%{?photon_subrelease}" && lhs != "%{photon_subrelease}" {
        return None;
    }
    if !["==", "!=", ">=", "<=", ">", "<"].contains(&op) {
        return None;
    }
    Some((op, rhs.parse().ok()?))
}

fn compare(op: &str, a: u32, b: u32) -> bool {
    match op {
        "==" => a == b,
        "!=" => a != b,
        ">=" => a >= b,
        "<=" => a <= b,
        ">" => a > b,
        _ => a < b,
    }
}

/// `Source55: license.txt` as ("55", "license.txt").
fn source_tag(line: &str) -> Option<(String, String)> {
    if line.len() < 7 || !line[..6].eq_ignore_ascii_case("source") {
        return None;
    }
    let rest = &line[6..];
    let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
    let value = rest[digits.len()..].trim_start().strip_prefix(':')?.trim();
    let value = value.split_whitespace().next()?;
    Some((digits, value.to_string()))
}

/// The file an `%include` names: `%{SOURCEn}` through the Source tags seen so
/// far, otherwise the literal name. rpm stages sources by bare name, so only
/// the last path component counts.
fn include_target(arg: &str, sources: &[(String, String)]) -> Option<String> {
    let name = match arg.strip_prefix("%{SOURCE").and_then(|r| r.strip_suffix('}')) {
        Some(n) => sources.iter().rev().find(|(num, _)| num == n)?.1.clone(),
        None => arg.to_string(),
    };
    if name.contains('%') {
        return None;
    }
    name.rsplit('/').next().map(str::to_string)
}

/// Files of a spec directory on disk.
pub fn dir_reader(dir: &Path) -> impl Fn(&str) -> Option<String> + '_ {
    move |name: &str| std::fs::read_to_string(dir.join(name)).ok()
}

/// Files of a spec directory as git has them: at `rev` (e.g. `origin/5.0`),
/// or in the index `index` when `rev` is empty.
pub fn git_reader<'a>(
    tree: &'a Path,
    rev: &'a str,
    dir: &'a str,
    index: Option<&'a Path>,
) -> impl Fn(&str) -> Option<String> + 'a {
    move |name: &str| {
        let mut cmd = Command::new("git");
        cmd.arg("-C").arg(tree);
        if let Some(i) = index {
            cmd.env("GIT_INDEX_FILE", i);
        }
        let out = cmd.args(["show", &format!("{rev}:{dir}/{name}")]).output().ok()?;
        if !out.status.success() {
            return None;
        }
        Some(String::from_utf8_lossy(&out.stdout).into_owned())
    }
}

/// The value of the first `key` line, e.g. `field(t, "Version:")`.
pub fn field(text: &str, key: &str) -> Option<String> {
    text.lines()
        .find(|l| l.starts_with(key))
        .map(|l| l[key.len()..].trim().to_string())
}

/// `photon-subrelease` from a tree's build-config.json.
pub fn tree_subrelease(tree: &Path) -> Option<u32> {
    let text = std::fs::read_to_string(tree.join("build-config.json")).ok()?;
    text.lines()
        .find(|l| l.contains("\"photon-subrelease\""))?
        .split(':')
        .nth(1)?
        .trim()
        .trim_end_matches(',')
        .trim()
        .trim_matches('"')
        .parse()
        .ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;

    const SKELETON: &str = "\
Summary:        Kernel
Name:           linux
%if 0%{?photon_subrelease} <= 90
Version:        6.1.183
%else
Version:        6.12.109
%endif
Source990:      linux-6.1.inc
Source991:      linux-6.12.inc

%if 0%{?photon_subrelease} <= 90
%include %{SOURCE990}
%else
%include %{SOURCE991}
%endif

%ifarch x86_64
%if 0%{?photon_subrelease} >= 92
BuildRequires:  gcc >= 12.5
%endif
%endif
";

    fn fixture(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("shk-resolve-{tag}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        fs::write(d.join("linux.spec"), SKELETON).unwrap();
        fs::write(
            d.join("linux-6.1.inc"),
            "Release:        3%{?acvp_build:.acvp}%{?dist}\n%define fips_canister_version 5.0.0-6.1.75-2%{?dist}-secure\n",
        )
        .unwrap();
        fs::write(
            d.join("linux-6.12.inc"),
            "Release:        4%{?acvp_build:.acvp}%{?dist}\nSource55: license.txt\n%include %{SOURCE55}\n",
        )
        .unwrap();
        fs::write(d.join("license.txt"), "License:        GPLv2\n").unwrap();
        d
    }

    #[test]
    fn each_subrelease_reads_its_own_kernel() {
        let d = fixture("kernels");
        let read = dir_reader(&d);
        let old = resolve(&read, "linux.spec", Some(90)).unwrap();
        assert_eq!(field(&old, "Version:").unwrap(), "6.1.183");
        assert!(field(&old, "Release:").unwrap().starts_with("3%"));
        assert!(old.contains("5.0.0-6.1.75-2"), "{old}");
        assert!(!old.contains("6.12.109"), "{old}");

        let new = resolve(&read, "linux.spec", Some(92)).unwrap();
        assert_eq!(field(&new, "Version:").unwrap(), "6.12.109");
        assert!(field(&new, "Release:").unwrap().starts_with("4%"));
        // nested include, reached through a Source tag of the included file
        assert_eq!(field(&new, "License:").unwrap(), "GPLv2");
        let _ = fs::remove_dir_all(&d);
    }

    /// Only subrelease comparisons are decided; the arch conditional around
    /// one stays for rpm, and the decided one disappears inside it.
    #[test]
    fn other_conditionals_are_left_to_rpm() {
        let d = fixture("arch");
        let read = dir_reader(&d);
        let at91 = resolve(&read, "linux.spec", Some(91)).unwrap();
        assert!(at91.contains("%ifarch x86_64\n%endif\n"), "{at91}");
        assert!(!at91.contains("gcc >= 12.5"), "{at91}");
        let at92 = resolve(&read, "linux.spec", Some(92)).unwrap();
        assert!(at92.contains("%ifarch x86_64\nBuildRequires:  gcc >= 12.5\n%endif\n"), "{at92}");
        let _ = fs::remove_dir_all(&d);
    }

    /// A spec without subrelease conditionals or includes reads unchanged, so
    /// the resolver is safe for every spec, not only the kernel.
    #[test]
    fn a_plain_spec_is_unchanged() {
        let d = std::env::temp_dir().join(format!("shk-resolve-plain-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        let text = "Name:           aide\nVersion:        0.18\nRelease:        3%{?dist}\n%ifarch x86_64\nPatch0: a.patch\n%else\nPatch1: b.patch\n%endif\n";
        fs::write(d.join("aide.spec"), text).unwrap();
        assert_eq!(resolve(&dir_reader(&d), "aide.spec", Some(92)).unwrap(), text);
        let _ = fs::remove_dir_all(&d);
    }

    /// An include that cannot be read stays a line rather than vanishing, so
    /// a reader looking for a field finds nothing instead of a wrong value.
    #[test]
    fn an_unreadable_include_is_kept() {
        let d = std::env::temp_dir().join(format!("shk-resolve-missing-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        fs::write(d.join("x.spec"), "Source7: gone.inc\n%include %{SOURCE7}\n").unwrap();
        let got = resolve(&dir_reader(&d), "x.spec", Some(92)).unwrap();
        assert!(got.contains("%include %{SOURCE7}"), "{got}");
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn the_subrelease_comes_from_build_config() {
        let d = std::env::temp_dir().join(format!("shk-resolve-cfg-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        fs::write(
            d.join("build-config.json"),
            "{\n  \"photon-build-param\": {\n    \"photon-subrelease\": \"92\",\n    \"photon-mainline\": \"92\"\n  }\n}\n",
        )
        .unwrap();
        assert_eq!(tree_subrelease(&d), Some(92));
        assert_eq!(tree_subrelease(&d.join("nowhere")), None);
        let _ = fs::remove_dir_all(&d);
    }

    /// The index reader sees a patch applied with `git apply --cached`, which
    /// is how the kernel NEVR is read before a build without a checkout.
    #[test]
    fn the_index_reader_sees_a_cached_patch() {
        let d = std::env::temp_dir().join(format!("shk-resolve-git-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(d.join("SPECS/linux")).unwrap();
        let git = |args: &[&str]| {
            let ok = Command::new("git").arg("-C").arg(&d).args(args).output().unwrap();
            assert!(ok.status.success(), "git {args:?}: {}", String::from_utf8_lossy(&ok.stderr));
        };
        git(&["init", "-q"]);
        fs::write(d.join("SPECS/linux/linux.spec"), "Name: linux\nVersion: 6.12.109\nSource1: a.inc\n%include %{SOURCE1}\n").unwrap();
        fs::write(d.join("SPECS/linux/a.inc"), "Release: 3%{?dist}\n").unwrap();
        git(&["add", "-A"]);
        git(&["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "base"]);
        let patch = d.join("bump.patch");
        fs::write(
            &patch,
            "--- a/SPECS/linux/a.inc\n+++ b/SPECS/linux/a.inc\n@@ -1 +1 @@\n-Release: 3%{?dist}\n+Release: 4%{?dist}\n",
        )
        .unwrap();
        let index = d.join("tmp-index");
        let with_index = |args: &[&str]| {
            let ok = Command::new("git").arg("-C").arg(&d).env("GIT_INDEX_FILE", &index).args(args).output().unwrap();
            assert!(ok.status.success(), "git {args:?}: {}", String::from_utf8_lossy(&ok.stderr));
        };
        with_index(&["read-tree", "HEAD"]);
        with_index(&["apply", "--cached", &patch.to_string_lossy()]);
        let read = git_reader(&d, "", "SPECS/linux", Some(&index));
        let got = resolve(&read, "linux.spec", Some(92)).unwrap();
        assert_eq!(field(&got, "Release:").unwrap(), "4%{?dist}");
        let head = git_reader(&d, "HEAD", "SPECS/linux", None);
        assert_eq!(field(&resolve(&head, "linux.spec", Some(92)).unwrap(), "Release:").unwrap(), "3%{?dist}");
        let _ = fs::remove_dir_all(&d);
    }
}
