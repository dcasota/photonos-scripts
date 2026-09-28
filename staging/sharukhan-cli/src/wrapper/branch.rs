//! The experimental release branch must carry what the profile says it does.
//!
//! A derived wrapper pins a tarball and applies patch files at build time from
//! `experimental/linux-<release>`. The branch documents its kernel in
//! `SPECS/linux/EXPERIMENTAL-<release>.md`; that manifest, the profile and the
//! computed identity must agree on the tarball URL, its sha512, the tagged
//! commit and the RPM Version/Release, and every patch file the profile names
//! must exist on the branch exactly once. Read with `git show`/`git ls-tree`
//! on the remote-tracking ref only; nothing is fetched or checked out.

use std::collections::BTreeMap;
use std::path::Path;
use std::process::{Command, Stdio};

use super::error::{io, Result, WrapperError};
use super::identity::KernelRelease;
use super::profile::Profile;

fn verify_err(
    what: impl Into<String>,
    expected: impl Into<String>,
    found: impl Into<String>,
) -> WrapperError {
    WrapperError::Verify {
        what: what.into(),
        expected: expected.into(),
        found: found.into(),
    }
}

fn git(repo: &Path, args: &[&str]) -> Result<String> {
    let out = Command::new("git")
        .arg("-C")
        .arg(repo)
        .args(args)
        .env("LC_ALL", "C")
        .stdin(Stdio::null())
        .output()
        .map_err(|e| io("running git", e))?;
    if !out.status.success() {
        return Err(io(
            format!("git {}", args.join(" ")),
            String::from_utf8_lossy(&out.stderr).trim().to_string(),
        ));
    }
    String::from_utf8(out.stdout).map_err(|e| io(format!("git {}", args.join(" ")), e))
}

/// The `| Field | Value |` rows of a manifest, values without backticks.
pub fn manifest_fields(md: &str) -> Result<BTreeMap<String, String>> {
    let mut m = BTreeMap::new();
    for l in md.lines() {
        let Some(inner) = l.strip_prefix('|').and_then(|r| r.strip_suffix('|')) else {
            continue;
        };
        let Some((k, v)) = inner.split_once('|') else {
            continue;
        };
        let (k, v) = (k.trim(), v.trim());
        if k.is_empty() || k == "Field" || k.starts_with("---") {
            continue;
        }
        if m.insert(k.to_string(), v.replace('`', "")).is_some() {
            return Err(verify_err(
                "branch manifest",
                format!("the row '{k}' once"),
                "twice",
            ));
        }
    }
    Ok(m)
}

#[derive(Debug, Clone, PartialEq)]
pub struct BranchReport {
    pub git_ref: String,
    pub commit: String,
    pub manifest: String,
    pub checked: Vec<String>,
}

/// Check the manifest text and the branch file list against the profile.
pub fn check_manifest(
    profile: &Profile,
    target: &KernelRelease,
    md: &str,
    files: &[&str],
) -> Result<Vec<String>> {
    let f = manifest_fields(md)?;
    let row = |k: &str| {
        f.get(k)
            .cloned()
            .ok_or_else(|| verify_err("branch manifest", format!("a '{k}' row"), "none"))
    };
    let mut checked = Vec::new();
    let url = row("Tarball")?;
    if url != target.source_url() {
        return Err(verify_err("manifest Tarball", target.source_url(), url));
    }
    checked.push(format!("tarball {url}"));
    let sha = row("sha512")?;
    if sha != profile.source.sha512 {
        return Err(verify_err(
            "manifest sha512",
            profile.source.sha512.clone(),
            sha,
        ));
    }
    checked.push("sha512 equals the profile's".into());
    let tag_row = format!("git tag {} (peeled)", target.git_tag());
    match (&profile.source.verified.commit, f.get(&tag_row)) {
        (Some(c), Some(m)) if c == m => checked.push(format!("{} -> {c}", target.git_tag())),
        (Some(c), found) => {
            return Err(verify_err(
                format!("manifest '{tag_row}'"),
                c.clone(),
                found.cloned().unwrap_or_else(|| "no such row".into()),
            ))
        }
        (None, Some(m)) => {
            return Err(verify_err(
                format!("manifest '{tag_row}'"),
                "no tag row for a signature-verified release, or a signed-tag profile",
                m.clone(),
            ))
        }
        (None, None) => {}
    }
    let kernel = row("Kernel")?;
    let starts = kernel
        .strip_prefix(&target.ksrc())
        .is_some_and(|r| r.is_empty() || r.starts_with(' '));
    if !starts {
        return Err(verify_err(
            "manifest Kernel",
            format!("{} ...", target.ksrc()),
            kernel,
        ));
    }
    let rpm = row("RPM version")?;
    let kv = format!("Version: {}", target.rpm_version());
    let kr = format!(
        "Release: {}%{{?dist}}",
        target.rpm_release(profile.rpm_release_iteration)
    );
    if !rpm.contains(&kv) || !rpm.contains(&kr) {
        return Err(verify_err(
            "manifest RPM version",
            format!("{kv}, {kr}"),
            rpm,
        ));
    }
    checked.push(format!("{kv}, {kr}"));
    let once = |dir: &str, name: &str| -> Result<()> {
        let hits: Vec<&&str> = files
            .iter()
            .filter(|p| p.starts_with(dir) && p.rsplit('/').next() == Some(name))
            .collect();
        if hits.len() != 1 {
            return Err(verify_err(
                format!("patch file {name} under {dir}"),
                "exactly one",
                format!("{} {hits:?}", hits.len()),
            ));
        }
        Ok(())
    };
    for k in &profile.kernel_patches {
        once("SPECS/linux/", &k.file)?;
        if let Some(r) = &k.replaces {
            once("SPECS/linux/", r)?;
        }
        checked.push(format!("SPECS/linux: {}", k.file));
    }
    if let Some(ip) = &profile.installer_patches {
        for p in &ip.patches {
            once("SPECS/photon-os-installer/", &p.file)?;
            checked.push(format!("SPECS/photon-os-installer: {}", p.file));
        }
    }
    Ok(checked)
}

/// Check a FIPS series manifest (JSON, from the branch) against the branch
/// file list: the shape the wrapper's editor relies on, and every file it
/// names present exactly once under SPECS/linux/ (rpm sees the directory
/// flattened, so a basename must be unique there).
pub fn check_fips_manifest(json: &str, files: &[&str]) -> Result<Vec<String>> {
    let bad = |what: &str, why: String| verify_err(format!("FIPS manifest {what}"), "valid", why);
    let m: serde_json::Value =
        serde_json::from_str(json).map_err(|e| bad("JSON", e.to_string()))?;
    let obj = |v: &serde_json::Value, k: &str| -> Result<serde_json::Map<String, serde_json::Value>> {
        v.get(k)
            .and_then(|x| x.as_object())
            .cloned()
            .ok_or_else(|| bad(k, "missing or not an object".into()))
    };
    let num = |k: &str, what: &str| -> Result<u32> {
        k.parse::<u32>()
            .ok()
            .filter(|n| k == n.to_string())
            .ok_or_else(|| bad(what, format!("key '{k}' is not a number")))
    };
    let ranges_of = |v: Option<&serde_json::Value>, what: &str| -> Result<Vec<(u32, u32)>> {
        let Some(v) = v else { return Ok(vec![]) };
        let arr = v.as_array().ok_or_else(|| bad(what, "not a list".into()))?;
        arr.iter()
            .map(|r| {
                let a = r.as_array().filter(|a| a.len() == 2);
                let (lo, hi) = match a {
                    Some(a) => (a[0].as_u64(), a[1].as_u64()),
                    None => (None, None),
                };
                match (lo, hi) {
                    (Some(lo), Some(hi)) if lo <= hi && hi < u32::MAX as u64 => Ok((lo as u32, hi as u32)),
                    _ => Err(bad(what, format!("{r} is not [from, to]"))),
                }
            })
            .collect()
    };
    let mut named: Vec<String> = Vec::new();
    let mut take_files = |map: &serde_json::Map<String, serde_json::Value>, what: &str, installs: bool| -> Result<Vec<u32>> {
        let mut nums = Vec::new();
        for (k, v) in map {
            let n = num(k, what)?;
            match v.get("file") {
                Some(serde_json::Value::String(f)) => {
                    named.push(f.clone());
                    nums.push(n);
                }
                Some(serde_json::Value::Null) if !installs => {}
                _ => return Err(bad(what, format!("{k} has no file"))),
            }
            if installs {
                let i = v.get("installs").and_then(|x| x.as_str()).unwrap_or("");
                if i.is_empty() || i.contains('/') {
                    return Err(bad(what, format!("Source{k} has no plain 'installs' name")));
                }
            }
        }
        Ok(nums)
    };
    let patches = take_files(&obj(&m, "patches")?, "patches", false)?;
    take_files(&obj(&m, "sources")?, "sources", true)?;
    let mut ranges = ranges_of(m.get("autopatch"), "autopatch")?;
    if ranges.is_empty() {
        return Err(bad("autopatch", "no ranges".into()));
    }
    let dropped: Vec<u32> = obj(&m, "dropped")?
        .keys()
        .map(|k| num(k, "dropped"))
        .collect::<Result<_>>()?;
    let mut all_patches = patches.clone();
    if let Some(fl) = m.get("flavours") {
        let fl = fl.as_object().ok_or_else(|| bad("flavours", "not an object".into()))?;
        for (name, f) in fl {
            if name != "linux" && name != "linux-esx" {
                return Err(bad("flavours", format!("unknown flavour '{name}'")));
            }
            if let Some(p) = f.get("patches") {
                let p = p.as_object().ok_or_else(|| bad("flavours", format!("{name}.patches")))?;
                all_patches.extend(take_files(p, "flavours patches", false)?);
            }
            ranges.extend(ranges_of(f.get("autopatch"), "flavours autopatch")?);
        }
    }
    let in_range = |n: u32| ranges.iter().any(|(a, b)| *a <= n && n <= *b);
    if let Some(n) = all_patches.iter().find(|n| !in_range(**n)) {
        return Err(bad("patches", format!("Patch{n} is in no autopatch range")));
    }
    if let Some(n) = dropped.iter().find(|n| patches.contains(n) || !in_range(**n)) {
        return Err(bad("dropped", format!("Patch{n} is listed as a patch or is in no range")));
    }
    named.sort();
    named.dedup();
    let mut checked = Vec::new();
    for f in &named {
        let hits = files
            .iter()
            .filter(|p| p.starts_with("SPECS/linux/") && p.rsplit('/').next() == Some(f.as_str()))
            .count();
        if hits != 1 {
            return Err(verify_err(
                format!("FIPS file {f} under SPECS/linux/"),
                "exactly one",
                hits.to_string(),
            ));
        }
    }
    checked.push(format!(
        "FIPS manifest: {} files present once, {} patches in range, {} dropped",
        named.len(),
        all_patches.len(),
        dropped.len()
    ));
    Ok(checked)
}

/// Verify the branch in `repo` (a photon clone) at `origin/<branch>`.
pub fn verify(repo: &Path, profile: &Profile) -> Result<BranchReport> {
    let target = profile.release()?;
    let git_ref = format!("refs/remotes/origin/{}", target.branch());
    let commit = git(
        repo,
        &[
            "rev-parse",
            "--verify",
            "--quiet",
            &format!("{git_ref}^{{commit}}"),
        ],
    )
    .map_err(|_| {
        verify_err(
            format!("{} in {}", git_ref, repo.display()),
            "a remote-tracking branch",
            "none",
        )
    })?
    .trim()
    .to_string();
    let manifest = format!("SPECS/linux/EXPERIMENTAL-{}.md", target.ksrc());
    let md = git(repo, &["show", &format!("{commit}:{manifest}")])?;
    let listing = git(
        repo,
        &[
            "ls-tree",
            "-r",
            "--name-only",
            &commit,
            "--",
            "SPECS/linux",
            "SPECS/photon-os-installer",
        ],
    )?;
    let files: Vec<&str> = listing.lines().collect();
    let mut checked = check_manifest(profile, &target, &md, &files)?;
    if let Some(f) = &profile.fips {
        let json = git(repo, &["show", &format!("{commit}:{}", f.manifest)])?;
        checked.extend(check_fips_manifest(&json, &files)?);
    }
    Ok(BranchReport {
        git_ref,
        commit,
        manifest,
        checked,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const SHA: &str = "7a4b9599c2c593131e150ae22030f643813b0fb3de2b479281ebb9a413e7928903adc748eb522e03fd39e9ca4991c12e4d0331718fff59a53fc6676b390c7945";

    fn md() -> String {
        format!(
            "# x\n\n| Field | Value |\n|---|---|\n| Kernel | 7.3-rc4 (mainline release candidate, 2026-09-20) |\n\
             | Tarball | https://git.kernel.org/torvalds/t/linux-7.3-rc4.tar.gz |\n| sha512 | `{SHA}` |\n\
             | git tag v7.3-rc4 (peeled) | `93f51579e7df248780214094418f205253383cc5` |\n\
             | RPM version | `Version: 7.3.0`, `Release: 0.rc4.1%{{?dist}}` (sorts below) |\n"
        )
    }

    const FILES: [&str; 5] = [
        "SPECS/linux/secure/0001-gcc-rap-plugin-with-kcfi-7.3.patch",
        "SPECS/linux/secure/0001-gcc-rap-plugin-with-kcfi.patch",
        "SPECS/photon-os-installer/0008-x.patch",
        "SPECS/linux/linux.spec",
        "SPECS/photon-os-installer/photon-os-installer.spec",
    ];

    fn profile() -> Profile {
        let p: Profile = serde_json::from_str(&super::super::profile::tests::sample()).unwrap();
        p.validate().unwrap();
        p
    }

    #[test]
    fn a_matching_manifest_and_file_list_pass() {
        let p = profile();
        let c = check_manifest(&p, &p.release().unwrap(), &md(), &FILES).unwrap();
        assert!(c.iter().any(|l| l.contains("93f51579")), "{c:?}");
    }

    #[test]
    fn each_disagreement_is_named() {
        let p = profile();
        let t = p.release().unwrap();
        for (from, to, needle) in [
            ("torvalds/t/", "torvalds/snapshot/", "manifest Tarball"),
            ("`7a4b", "`8a4b", "manifest sha512"),
            ("`93f5", "`0000", "git tag v7.3-rc4"),
            (
                "| Kernel | 7.3-rc4",
                "| Kernel | 7.3-rc5",
                "manifest Kernel",
            ),
            ("0.rc4.1%", "0.rc4.2%", "manifest RPM version"),
            ("| sha512 |", "| sha256 |", "'sha512' row"),
        ] {
            let m = md().replacen(from, to, 1);
            assert_ne!(m, md());
            let e = check_manifest(&p, &t, &m, &FILES).unwrap_err().to_string();
            assert!(e.contains(needle), "{needle}: {e}");
        }
        let dup = format!("{}| sha512 | x |\n", md());
        assert!(check_manifest(&p, &t, &dup, &FILES)
            .unwrap_err()
            .to_string()
            .contains("twice"));
    }

    #[test]
    fn patch_files_must_exist_exactly_once() {
        let p = profile();
        let t = p.release().unwrap();
        let missing: Vec<&str> = FILES
            .iter()
            .copied()
            .filter(|f| !f.contains("-7.3.patch"))
            .collect();
        assert!(check_manifest(&p, &t, &md(), &missing)
            .unwrap_err()
            .to_string()
            .contains("kcfi-7.3.patch"));
        let mut twice = FILES.to_vec();
        twice.push("SPECS/linux/other/0001-gcc-rap-plugin-with-kcfi-7.3.patch");
        assert!(check_manifest(&p, &t, &md(), &twice)
            .unwrap_err()
            .to_string()
            .contains("exactly one"));
        let wrong_dir: Vec<&str> = FILES
            .iter()
            .copied()
            .filter(|f| !f.contains("0008"))
            .chain(["SPECS/linux/0008-x.patch"])
            .collect();
        assert!(check_manifest(&p, &t, &md(), &wrong_dir).is_err());
    }

    #[test]
    fn a_photon_clone_is_read_at_the_remote_tracking_ref_only() {
        let dir = std::env::temp_dir().join(format!("shk-branch-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let g = |args: &[&str]| {
            let st = Command::new("git")
                .arg("-C")
                .arg(&dir)
                .args(["-c", "user.name=T", "-c", "user.email=t@example.invalid"])
                .args(args)
                .env("GIT_CONFIG_GLOBAL", "/dev/null")
                .stdout(Stdio::null())
                .status()
                .unwrap();
            assert!(st.success(), "{args:?}");
        };
        g(&["init", "-q"]);
        for f in FILES {
            let path = dir.join(f);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(&path, "x\n").unwrap();
        }
        std::fs::write(dir.join("SPECS/linux/EXPERIMENTAL-7.3-rc4.md"), md()).unwrap();
        g(&["add", "-A"]);
        g(&["commit", "-q", "-m", "fixture"]);
        let p = profile();
        // no remote-tracking branch yet: a local branch of that name does not count
        g(&["branch", "experimental/linux-7.3-rc4"]);
        let e = verify(&dir, &p).unwrap_err().to_string();
        assert!(e.contains("remote-tracking"), "{e}");
        g(&[
            "update-ref",
            "refs/remotes/origin/experimental/linux-7.3-rc4",
            "HEAD",
        ]);
        let r = verify(&dir, &p).unwrap();
        assert_eq!(r.manifest, "SPECS/linux/EXPERIMENTAL-7.3-rc4.md");
        assert_eq!(r.commit.len(), 40);
        assert!(verify(&dir.join("missing"), &p).is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }
    const FIPS_JSON: &str = r#"{
      "patches": {"10001": {"file": "a-7.3.patch"}, "10119": {"file": "b-7.3.patch"}, "11018": {"file": null}},
      "sources": {"10101": {"file": "w-7.3.c", "installs": "w.c"}},
      "dropped": {"10003": "superseded"},
      "autopatch": [[10001, 10004], [10101, 10119], [11000, 11020]],
      "flavours": {"linux-esx": {"patches": {"10050": {"file": "j.patch"}}, "autopatch": [[10050, 10050]]}}
    }"#;
    const FIPS_FILES: [&str; 5] = [
        "SPECS/linux/fips-7.3/a-7.3.patch",
        "SPECS/linux/fips-7.3/b-7.3.patch",
        "SPECS/linux/fips-7.3/w-7.3.c",
        "SPECS/linux/jitterentropy_builder/j.patch",
        "SPECS/linux/linux.spec",
    ];

    #[test]
    fn a_fips_manifest_whose_files_are_on_the_branch_passes() {
        let c = check_fips_manifest(FIPS_JSON, &FIPS_FILES).unwrap();
        assert!(c[0].contains("4 files present once"), "{c:?}");
    }

    #[test]
    fn a_fips_manifest_is_refused_when_a_file_is_missing_or_ambiguous() {
        let missing: Vec<&str> = FIPS_FILES.iter().copied().filter(|f| !f.ends_with("w-7.3.c")).collect();
        let e = check_fips_manifest(FIPS_JSON, &missing).unwrap_err().to_string();
        assert!(e.contains("w-7.3.c"), "{e}");
        let mut dup = FIPS_FILES.to_vec();
        dup.push("SPECS/linux/other/a-7.3.patch");
        let e = check_fips_manifest(FIPS_JSON, &dup).unwrap_err().to_string();
        assert!(e.contains("a-7.3.patch") && e.contains('2'), "{e}");
    }

    #[test]
    fn a_fips_manifest_with_a_patch_outside_every_range_is_refused() {
        let j = FIPS_JSON.replace("\"10119\"", "\"10150\"");
        let e = check_fips_manifest(&j, &FIPS_FILES).unwrap_err().to_string();
        assert!(e.contains("Patch10150"), "{e}");
        let j = FIPS_JSON.replace("\"10003\": \"superseded\"", "\"10001\": \"superseded\"");
        let e = check_fips_manifest(&j, &FIPS_FILES).unwrap_err().to_string();
        assert!(e.contains("Patch10001"), "{e}");
    }
}
