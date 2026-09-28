//! Derivation: base wrapper + profile -> wrapper for the profile's kernel.
//!
//! Order matters and is fixed:
//!
//! 1. The base parses (declaration, every slot exactly once) and agrees with
//!    itself; the profile validates.
//! 2. Profile and base agree: same base kernel, and the base is still the
//!    wrapper version the profile was reviewed against.
//! 3. No target identity string already occurs in the carried base text - a
//!    rename could not be told apart from text that was already there.
//! 4. Every slot is rendered for the target; none may carry a base identity
//!    string.
//! 5. The carried text is renamed base -> target identity, each rename with a
//!    measured count, each required to occur.
//! 6. No base identity string survives anywhere (digests excepted, where a
//!    short token can occur by chance).
//! 7. The script is validated by `sh -n` and every Python heredoc parses.
//!
//! Only then is anything written, atomically - or, with `--check`, compared
//! byte for byte with what is committed.

use std::path::{Path, PathBuf};

use super::base::{Base, Segment};
use super::error::{io, Result, WrapperError};
use super::escape;
use super::identity::KernelRelease;
use super::profile::Profile;
use super::render::{self, Ctx, LIVE_AUTOPATCH};
use super::validate::{self, Measured};

/// One identity rename and how often it applied.
#[derive(Debug, Clone, PartialEq)]
pub struct Rename {
    pub from: String,
    pub to: String,
    pub count: usize,
}

#[derive(Debug, Clone)]
pub struct Derived {
    pub script: String,
    pub target: KernelRelease,
    pub renames: Vec<Rename>,
    pub measured: Measured,
}

/// Base identity -> target identity, most specific first.
fn identity_pairs(
    base: &KernelRelease,
    target: &KernelRelease,
) -> Vec<(String, String, &'static str)> {
    let mut v = vec![
        (base.tag(), target.tag(), "tag"),
        (base.marker(), target.marker(), "ISO marker"),
        (base.ksrc(), target.ksrc(), "kernel release"),
    ];
    if base.setup_macro() != target.setup_macro() {
        // %setup -n linux-%{MACRO}, literally and as an awk regex.
        v.push((
            format!("linux-%{{{}}}", base.setup_macro()),
            format!("linux-%{{{}}}", target.setup_macro()),
            "spec %setup directory",
        ));
        v.push((
            format!("linux-%\\{{{}\\}}", base.setup_macro()),
            format!("linux-%\\{{{}\\}}", target.setup_macro()),
            "spec %setup directory (regex)",
        ));
    }
    v
}

/// Occurrences of `token` that are not inside a run of 32 or more hex digits.
/// A digest can contain `727` by chance; a function name cannot hide in one.
fn token_hits(text: &str, token: &str) -> Vec<usize> {
    let b = text.as_bytes();
    let mut hits = Vec::new();
    let mut from = 0;
    while let Some(off) = text[from..].find(token) {
        let at = from + off;
        let mut s = at;
        while s > 0 && b[s - 1].is_ascii_hexdigit() {
            s -= 1;
        }
        let mut e = at + token.len();
        while e < b.len() && b[e].is_ascii_hexdigit() {
            e += 1;
        }
        if e - s < 32 {
            hits.push(at);
        }
        from = at + token.len().max(1);
    }
    hits
}

fn line_of(text: &str, at: usize) -> String {
    let s = text[..at].rfind('\n').map(|i| i + 1).unwrap_or(0);
    let e = text[at..].find('\n').map(|i| at + i).unwrap_or(text.len());
    let n = text[..at].matches('\n').count() + 1;
    format!("{n}: {}", &text[s..e])
}

/// Identity strings of `k` that must not appear where `k` is not meant.
fn forbidden(k: &KernelRelease) -> (Vec<String>, String) {
    // The bare token is matched separately: it may occur inside a digest.
    let token = k.token();
    let plain = k
        .identity_strings()
        .into_iter()
        .filter(|s| *s != token)
        .collect();
    (plain, token)
}

fn find_identity(text: &str, k: &KernelRelease) -> Vec<(String, Vec<String>)> {
    let (plain, token) = forbidden(k);
    let mut out = Vec::new();
    for s in plain {
        let hits: Vec<String> = text
            .match_indices(s.as_str())
            .map(|(i, _)| line_of(text, i))
            .take(10)
            .collect();
        if !hits.is_empty() {
            out.push((s, hits));
        }
    }
    let hits: Vec<String> = token_hits(text, &token)
        .into_iter()
        .map(|i| line_of(text, i))
        .take(10)
        .collect();
    if !hits.is_empty() {
        out.push((token, hits));
    }
    out
}

fn apply_renames(
    text: &str,
    pairs: &[(String, String, &'static str)],
    counts: &mut [usize],
) -> String {
    let mut t = text.to_string();
    for (i, (from, to, _)) in pairs.iter().enumerate() {
        counts[i] += t.matches(from.as_str()).count();
        t = t.replace(from.as_str(), to);
    }
    t
}

/// Join Python string pieces: drop every `'<whitespace>'` boundary.
fn join_py_pieces(region: &str) -> std::result::Result<String, String> {
    let mut joined = String::new();
    let mut chars = region.chars().peekable();
    while let Some(ch) = chars.next() {
        if ch == '\'' {
            while chars.peek().is_some_and(|x| x.is_whitespace()) {
                chars.next();
            }
            if chars.peek() == Some(&'\'') {
                chars.next();
                continue;
            }
            return Err("a quote inside the pkgs list does not join two pieces".into());
        }
        joined.push(ch);
    }
    Ok(joined)
}

/// The packages of the one `pkgs="..."` list in a (derived) wrapper, pieces
/// joined and every name validated. Empty when there is no list.
pub fn pkgs_list(text: &str) -> std::result::Result<Vec<String>, String> {
    let starts: Vec<usize> = text.match_indices("pkgs=\"").map(|(i, _)| i).collect();
    let start = match starts.as_slice() {
        [] => return Ok(vec![]),
        [s] => *s,
        _ => return Err("more than one pkgs=\"...\" list".into()),
    };
    let from = start + "pkgs=\"".len();
    let close = text[from..]
        .find('"')
        .map(|i| from + i)
        .ok_or("the pkgs list is never closed")?;
    let joined = join_py_pieces(&text[from..close])?;
    joined
        .split(',')
        .map(|p| {
            escape::package_name("pkgs list", p)
                .map(|_| p.to_string())
                .map_err(|e| e.to_string())
        })
        .collect()
}

/// The pre-build slot extends the base's own package list; it never restates
/// it. The list is found structurally (`pkgs="..."`, possibly split over
/// several Python string pieces), the target's extras are appended, and the
/// slot's comment literal is re-rendered for the target.
fn prebuild(c: &Ctx, renamed: &str) -> Result<String> {
    let slot_err = |why: String| WrapperError::Slot {
        name: "prebuild".into(),
        expected: 1,
        found: renamed.matches("pkgs=\"").count(),
        why,
    };
    let starts: Vec<usize> = renamed.match_indices("pkgs=\"").map(|(i, _)| i).collect();
    let [start] = starts.as_slice() else {
        return Err(slot_err(
            "the slot must hold exactly one pkgs=\"...\" list".into(),
        ));
    };
    let list_from = start + "pkgs=\"".len();
    let close = renamed[list_from..]
        .find('"')
        .map(|i| list_from + i)
        .ok_or_else(|| slot_err("the pkgs list is never closed".into()))?;
    let joined = join_py_pieces(&renamed[list_from..close]).map_err(slot_err)?;
    let have: Vec<&str> = joined.split(',').collect();
    for p in &have {
        escape::package_name("base prebuild list", p).map_err(|e| slot_err(e.to_string()))?;
    }
    for p in &c.profile.prebuild_extra {
        if have.contains(&p.as_str()) {
            return Err(slot_err(format!(
                "prebuild_extra '{p}' is already in the base's list; remove it from the profile"
            )));
        }
    }
    let mut out = String::with_capacity(renamed.len() + 64);
    out.push_str(&renamed[..close]);
    for p in &c.profile.prebuild_extra {
        out.push(',');
        out.push_str(p);
    }
    out.push_str(&renamed[close..]);
    // The comment literal: exactly one `'# ...\n'` piece.
    let comments: Vec<usize> = out.match_indices("'# ").map(|(i, _)| i).collect();
    let [cstart] = comments.as_slice() else {
        return Err(slot_err(format!(
            "expected exactly one comment literal '# ...', found {}",
            comments.len()
        )));
    };
    let body_from = cstart + 1;
    let body_end = out[body_from..]
        .find("\\n'")
        .map(|i| body_from + i)
        .ok_or_else(|| slot_err("the comment literal does not end in \\n'".into()))?;
    let and = if c.profile.prebuild_extra.is_empty() {
        ""
    } else {
        " and branch-updated packages"
    };
    let comment = format!(
        "# {}: build the ISO KS_STIG_PACKAGES set{and} before make image",
        c.target.ksrc()
    );
    Ok(format!(
        "{}{comment}{}",
        &out[..body_from],
        &out[body_end..]
    ))
}

/// Derive the wrapper text. Pure apart from the validation commands.
pub fn derive_text(base_text: &str, profile: &Profile) -> Result<Derived> {
    let base = Base::parse(base_text)?;
    let target = profile.release()?;
    let from = profile.base_release()?;
    if base.kernel != from {
        return Err(WrapperError::Base {
            why: format!(
                "declares kernel={}, but the profile derives from base.kernel={}",
                base.kernel.ksrc(),
                from.ksrc()
            ),
        });
    }
    let base_v = base.wrapper_version()?;
    if base_v != profile.base.wrapper_version {
        return Err(WrapperError::Base {
            why: format!(
                "{} is wrapper v{base_v}, but profile {} was reviewed against v{}. \
                 Review what changed in the base since v{}, update the profile if the \
                 derived wrapper needs it, then set base.wrapper_version = {base_v} and \
                 raise wrapper_version",
                profile.base.script,
                target.ksrc(),
                profile.base.wrapper_version,
                profile.base.wrapper_version
            ),
        });
    }
    let carried = base.carried_text();
    if !carried.contains(LIVE_AUTOPATCH) && !profile.kernel_patches.is_empty() {
        return Err(WrapperError::Base {
            why: format!(
                "no longer re-enables '{LIVE_AUTOPATCH}', which every kernel patch enabler anchors after"
            ),
        });
    }
    // 3. collision pre-check
    if let Some((token, lines)) = find_identity(&carried, &target).into_iter().next() {
        return Err(WrapperError::Collision { token, lines });
    }
    // 4. render
    let ctx = Ctx {
        target: &target,
        base: &base,
        profile,
    };
    let pairs = identity_pairs(&base.kernel, &target);
    let mut counts = vec![0usize; pairs.len()];
    let mut out = String::with_capacity(base_text.len() + 16 * 1024);
    // The renamed carried text alone: the rendered pin legitimately names
    // the old %setup form it rewrites, the carried text must not.
    let mut carried_out = String::with_capacity(base_text.len());
    for seg in &base.segments {
        match seg {
            Segment::Text(t) => {
                let r = apply_renames(t, &pairs, &mut counts);
                carried_out.push_str(&r);
                out.push_str(&r);
            }
            Segment::Slot { name, content } => {
                let rendered = match name.as_str() {
                    "header" => render::header(&ctx),
                    "banner" => render::banner(&ctx),
                    "kernel-pin" => render::kernel_pin(&ctx),
                    "kernel-sandbox-names" => render::kernel_sandbox_names(&ctx),
                    "kernel-pin-calls" => render::kernel_pin_calls(&ctx),
                    "kernel-patches" => render::kernel_patches(&ctx),
                    "kernel-fips" => render::kernel_fips(&ctx),
                    "kernel-source" => render::kernel_source(&ctx),
                    "version-assert" => render::version_assert(&ctx),
                    "prebuild" => {
                        let mut scratch_counts = vec![0usize; pairs.len()];
                        prebuild(&ctx, &apply_renames(content, &pairs, &mut scratch_counts))?
                    }
                    other => {
                        return Err(WrapperError::Slot {
                            name: other.into(),
                            expected: 1,
                            found: 0,
                            why: "has no renderer".into(),
                        })
                    }
                };
                if let Some((token, _)) = find_identity(&rendered, &base.kernel).into_iter().next()
                {
                    return Err(WrapperError::RenderLeak {
                        slot: name.clone(),
                        token,
                    });
                }
                out.push_str(&rendered);
            }
        }
    }
    // 5. every rename must have applied
    let mut renames = Vec::new();
    for ((from, to, what), n) in pairs.iter().zip(&counts) {
        if *n == 0 {
            return Err(WrapperError::Base {
                why: format!(
                    "the {what} '{from}' never occurs outside the slots; the base no longer \
                     carries what the rename to '{to}' exists for"
                ),
            });
        }
        renames.push(Rename {
            from: from.clone(),
            to: to.clone(),
            count: *n,
        });
    }
    // 6. leftovers, anywhere
    let left = find_identity(&out, &base.kernel);
    let mut left_pairs: Vec<(String, Vec<String>)> = left;
    for (from, _, what) in &pairs {
        if what.starts_with("spec %setup") && carried_out.contains(from.as_str()) {
            left_pairs.push((
                from.clone(),
                carried_out
                    .match_indices(from.as_str())
                    .map(|(i, _)| line_of(&carried_out, i))
                    .take(10)
                    .collect(),
            ));
        }
    }
    if !left_pairs.is_empty() {
        return Err(WrapperError::Leftover {
            tokens: left_pairs.iter().map(|(t, _)| t.clone()).collect(),
            lines: {
                let mut seen = std::collections::BTreeSet::new();
                left_pairs
                    .into_iter()
                    .flat_map(|(_, l)| l)
                    .filter(|l| seen.insert(l.clone()))
                    .take(10)
                    .collect()
            },
        });
    }
    // 7. validate
    let measured = validate::validate(&out)?;
    Ok(Derived {
        script: out,
        target,
        renames,
        measured,
    })
}

/// Where the derived script goes by default: beside the base, under its tag.
pub fn default_out(base_path: &Path, target: &KernelRelease) -> PathBuf {
    base_path
        .parent()
        .unwrap_or_else(|| Path::new("."))
        .join(target.script_file())
}

/// Compare with a committed copy, reporting the first differing line.
pub fn check_against(derived: &str, path: &Path) -> Result<()> {
    let committed = std::fs::read_to_string(path).map_err(|e| io(path.display().to_string(), e))?;
    if committed == derived {
        return Ok(());
    }
    let (mut dl, mut cl) = (derived.lines(), committed.lines());
    let mut n = 0;
    loop {
        n += 1;
        match (dl.next(), cl.next()) {
            (Some(a), Some(b)) if a == b => continue,
            (a, b) => {
                return Err(WrapperError::Drift {
                    path: path.display().to_string(),
                    line: n,
                    expected: a.unwrap_or("<end of file>").to_string(),
                    found: b.unwrap_or("<end of file>").to_string(),
                })
            }
        }
    }
}

/// Write atomically: a temporary file in the destination directory, synced,
/// made executable, then renamed over the destination.
pub fn write_atomic(path: &Path, text: &str) -> Result<()> {
    use std::io::Write;
    use std::os::unix::fs::PermissionsExt;
    let dir = path.parent().unwrap_or_else(|| Path::new("."));
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .ok_or_else(|| io(path.display().to_string(), "has no file name"))?;
    let tmp = dir.join(format!(".{name}.tmp.{}", std::process::id()));
    let result = (|| -> std::io::Result<()> {
        let mut f = std::fs::File::create(&tmp)?;
        f.write_all(text.as_bytes())?;
        f.sync_all()?;
        std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o755))?;
        std::fs::rename(&tmp, path)
    })();
    if let Err(e) = result {
        let _ = std::fs::remove_file(&tmp);
        return Err(io(format!("writing {}", path.display()), e));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_token_inside_a_digest_is_not_a_hit_but_one_in_a_name_is() {
        let digest = "9a7ee3e35e1e4eea44fd2fadce7b51deb9c727b1e19ed4d8dc1e59d2e310ffa6";
        assert!(token_hits(digest, "727").is_empty());
        assert_eq!(token_hits("pin_727 K727_SHA runph727", "727").len(), 3);
    }

    #[test]
    fn check_against_reports_the_first_differing_line() {
        let p = std::env::temp_dir().join(format!("sharukhan-drift-{}", std::process::id()));
        std::fs::write(&p, "a\nb\nc\n").unwrap();
        assert!(check_against("a\nb\nc\n", &p).is_ok());
        let e = check_against("a\nB\nc\n", &p).unwrap_err().to_string();
        assert!(e.contains("line 2") && e.contains("derived:   B"), "{e}");
        let e = check_against("a\nb\nc\nd\n", &p).unwrap_err().to_string();
        assert!(e.contains("line 4") && e.contains("<end of file>"), "{e}");
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn an_atomic_write_leaves_an_executable_file_and_no_temporary() {
        use std::os::unix::fs::PermissionsExt;
        let d = std::env::temp_dir().join(format!("sharukhan-atomic-{}", std::process::id()));
        std::fs::create_dir_all(&d).unwrap();
        let p = d.join("x.sh");
        write_atomic(&p, "echo hi\n").unwrap();
        assert_eq!(std::fs::read_to_string(&p).unwrap(), "echo hi\n");
        assert_eq!(
            std::fs::metadata(&p).unwrap().permissions().mode() & 0o777,
            0o755
        );
        assert_eq!(std::fs::read_dir(&d).unwrap().count(), 1);
        assert!(write_atomic(&d.join("missing").join("y.sh"), "x").is_err());
        let _ = std::fs::remove_dir_all(&d);
    }
}

#[cfg(test)]
mod controls {
    //! Negative controls on the committed base and profile: each mutation
    //! must fail with the typed error that names it, and nothing is written.
    use super::*;

    fn root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
    }

    fn base() -> String {
        std::fs::read_to_string(root().join("../runPh7-2-7.sh")).unwrap()
    }

    fn profile() -> Profile {
        Profile::load(&root().join("profiles/kernel/7.3-rc4.json")).unwrap()
    }

    fn fails(base: &str, p: &Profile) -> String {
        derive_text(base, p).unwrap_err().to_string()
    }

    #[test]
    fn the_committed_pair_derives_and_renders_the_target_tag_directly() {
        let d = derive_text(&base(), &profile()).unwrap();
        assert!(!d.script.contains("runPh7-2-7") && !d.script.contains("7.2.7"));
        // every enabler's log line carries the target tag, rendered, not renamed
        for f in [
            "enable_rap_73rc4",
            "enable_rdrand_73rc4",
            "enable_vmwgfx_73rc4",
            "pin_installer_73rc4",
            "pin_73rc4",
        ] {
            assert!(d.script.contains(&format!("{f}() {{")), "{f}");
        }
        assert!(d
            .script
            .contains("print(f\"[runPh7-3-RC4] {p}: vmwgfx blend mode (Patch7300) enabled\")"));
    }

    #[test]
    fn a_missing_slot_end_is_expected_1_found_0() {
        let b = base().replacen("# @sharukhan-slot kernel-source end\n", "", 1);
        let e = fails(&b, &profile());
        assert!(e.contains("kernel-source"), "{e}");
        let b = base()
            .replacen("# @sharukhan-slot version-assert begin\n", "", 1)
            .replacen("  # @sharukhan-slot version-assert end\n", "", 1);
        let e = fails(&b, &profile());
        assert!(
            e.contains("slot 'version-assert': expected 1, found 0"),
            "{e}"
        );
    }

    #[test]
    fn a_duplicated_slot_is_found_2() {
        let slot = "# @sharukhan-slot kernel-patches begin\n# @sharukhan-slot kernel-patches end\n";
        assert!(base().contains(slot));
        let b = base().replacen(slot, &format!("{slot}{slot}"), 1);
        let e = fails(&b, &profile());
        assert!(e.contains("expected 1, found 2"), "{e}");
    }

    #[test]
    fn an_unrenamed_identity_string_is_a_leftover_with_its_line() {
        let b = base().replacen(
            "wipe_kernel_sandboxes\n\n",
            "wipe_kernel_sandboxes\n\n: \"$K727_SHA\"\n",
            1,
        );
        let e = fails(&b, &profile());
        assert!(
            e.contains("survived derivation")
                && e.contains("K727_SHA")
                && e.contains(": \"$K727_SHA\""),
            "{e}"
        );
        assert_eq!(
            e.matches(": \"$K727_SHA\"").count(),
            1,
            "each line once: {e}"
        );
    }

    #[test]
    fn a_target_identity_already_in_the_base_is_a_collision() {
        let b = base().replacen(
            "wipe_kernel_sandboxes\n\n",
            "wipe_kernel_sandboxes\n\n# see runPh7-3-RC4.sh\n",
            1,
        );
        let e = fails(&b, &profile());
        assert!(e.contains("'runPh7-3-RC4' already occurs"), "{e}");
    }

    #[test]
    fn a_base_bumped_since_review_names_the_review_to_do() {
        let b = base().replace("wrapper v14", "wrapper v15");
        let e = fails(&b, &profile());
        assert!(
            e.contains("is wrapper v15")
                && e.contains("reviewed against v14")
                && e.contains("base.wrapper_version = 15"),
            "{e}"
        );
        let mut p = profile();
        p.base.kernel = "7.2.8".into();
        assert!(fails(&base(), &p).contains("base.kernel=7.2.8"));
    }

    #[test]
    fn a_rename_with_nothing_to_rename_is_refused() {
        let b = base().replace("linux-%\\{version\\}", "linux-%\\{Version\\}");
        let e = fails(&b, &profile());
        assert!(e.contains("never occurs outside the slots"), "{e}");
    }

    #[test]
    fn a_profile_text_carrying_the_base_tag_leaks_and_is_refused() {
        let mut p = profile();
        p.kernel_patches[2].applied = "done by runPh7-2-7".into();
        let e = fails(&base(), &p);
        assert!(
            e.contains("rendered slot 'kernel-patches'") && e.contains("runPh7-2-7"),
            "{e}"
        );
    }

    #[test]
    fn prebuild_extras_already_in_the_base_list_are_refused() {
        let mut p = profile();
        p.prebuild_extra.push("aide".into());
        let e = fails(&base(), &p);
        assert!(e.contains("'aide' is already in the base's list"), "{e}");
        let mut p = profile();
        p.prebuild_extra.clear();
        let d = derive_text(&base(), &p).unwrap();
        assert!(d
            .script
            .contains("# 7.3-rc4: build the ISO KS_STIG_PACKAGES set before make image"));
        assert!(d.script.contains("aide,libgcrypt\" THREADS=8"));
    }

    #[test]
    fn output_that_is_not_valid_shell_or_python_is_refused() {
        let b = format!("{}if true; then\n", base());
        assert!(fails(&b, &profile()).contains("'sh -n' failed"));
        let b = base().replacen("import re, sys\nfrom pathlib import Path\np = Path(sys.argv[1])\nt = p.read_text()\nnt = t\n",
                                "import re, sys\nfrom pathlib import Path\np = Path(sys.argv[1]\nt = p.read_text()\nnt = t\n", 1);
        assert_ne!(b, base());
        assert!(fails(&b, &profile()).contains("python heredoc"));
    }
}
