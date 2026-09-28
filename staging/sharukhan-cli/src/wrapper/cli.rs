//! `sharukhan wrapper ...`: derive, check, resolve and verify kernel wrappers.

use std::path::{Path, PathBuf};

use super::branch;
use super::derive::{self, Derived};
use super::error::{io, Result, WrapperError};
use super::escape;
use super::identity::KernelRelease;
use super::kernelorg::{self, Trust};
use super::profile::{release_mentions, Profile};

pub const USAGE: &str = "\
sharukhan wrapper - build wrappers for any kernel.org Linux release

USAGE:
    sharukhan wrapper <COMMAND> [OPTIONS]

COMMANDS
    derive          derive the wrapper for one profile from the version-neutral,
                    slot-marked base wrapper, and write it atomically
                    (--check compares with the committed one instead)
    check           derive every profile and compare with the committed wrappers
    kernel <sel>    resolve a selector against kernel.org's releases.json and
                    print the derived identity: mainline | stable | longterm |
                    longterm-X.Y | X.Y-rcN | X.Y | X.Y.Z
    verify <rel>    download (or take --tarball) and verify a release tarball:
                    .tar.sign for cdn.kernel.org releases, signed tag plus
                    byte-identical `git archive` for git.kernel.org snapshots
    profile-new     start a profile for another release from an existing one;
                    the source is verified first, and every text naming a
                    release is listed for review

OPTIONS
    --profile <p>       profile file, or a release naming <profiles>/<rel>.json
    --profiles <dir>    profile directory; default $SHARUKHAN_WRAPPER_PROFILES,
                        else ./profiles/kernel
    --wrappers <dir>    directory holding the base and derived wrappers; default
                        $SHARUKHAN_WRAPPERS, else <profiles>/../../..
    --out <file>        derive: output path; default <wrappers>/<tag>.sh
    --check             derive: compare instead of writing
    --repo <dir>        photon clone whose origin/experimental/linux-<rel> is
                        checked against the profile; default $SHARUKHAN_PHOTON_REPO
    --no-branch         skip the branch check (reported as NOT verified)
    --trust <file>      reviewed signer list; default <profiles>/kernel-org-signers.json
    --tarball <file>    verify/profile-new: a local copy, still fully verified
    --cache <dir>       download cache; default $SHARUKHAN_KERNEL_CACHE, else
                        $XDG_CACHE_HOME/sharukhan/kernel, else ~/.cache/sharukhan/kernel
    --kernel <rel>      profile-new: the new release
    --from <p>          profile-new: the profile to start from
    --force             profile-new: overwrite an existing profile
    --offline           kernel: print the identity without asking kernel.org
";

#[derive(Debug, Default)]
struct Opts {
    positional: Vec<String>,
    profile: Option<String>,
    profiles: Option<PathBuf>,
    wrappers: Option<PathBuf>,
    out: Option<PathBuf>,
    check: bool,
    repo: Option<PathBuf>,
    no_branch: bool,
    trust: Option<PathBuf>,
    tarball: Option<PathBuf>,
    cache: Option<PathBuf>,
    kernel: Option<String>,
    from: Option<String>,
    force: bool,
    offline: bool,
}

fn parse(args: &[String]) -> std::result::Result<Opts, String> {
    let mut o = Opts::default();
    let mut it = args.iter();
    while let Some(a) = it.next() {
        let mut val = |name: &str| -> std::result::Result<String, String> {
            it.next()
                .cloned()
                .filter(|v| !v.starts_with("--"))
                .ok_or_else(|| format!("{name} needs a value"))
        };
        match a.as_str() {
            "--profile" => o.profile = Some(val(a)?),
            "--profiles" => o.profiles = Some(val(a)?.into()),
            "--wrappers" => o.wrappers = Some(val(a)?.into()),
            "--out" => o.out = Some(val(a)?.into()),
            "--repo" => o.repo = Some(val(a)?.into()),
            "--trust" => o.trust = Some(val(a)?.into()),
            "--tarball" => o.tarball = Some(val(a)?.into()),
            "--cache" => o.cache = Some(val(a)?.into()),
            "--kernel" => o.kernel = Some(val(a)?),
            "--from" => o.from = Some(val(a)?),
            "--check" => o.check = true,
            "--no-branch" => o.no_branch = true,
            "--force" => o.force = true,
            "--offline" => o.offline = true,
            s if s.starts_with('-') => return Err(format!("unknown option: {s}")),
            s => o.positional.push(s.to_string()),
        }
    }
    if o.repo.is_some() && o.no_branch {
        return Err("--repo and --no-branch contradict each other".into());
    }
    Ok(o)
}

fn profiles_dir(o: &Opts) -> PathBuf {
    o.profiles
        .clone()
        .or_else(|| std::env::var_os("SHARUKHAN_WRAPPER_PROFILES").map(PathBuf::from))
        .unwrap_or_else(|| PathBuf::from("profiles/kernel"))
}

/// A profile argument: an existing file, or a release in the profile dir.
fn profile_path(o: &Opts, arg: &str) -> Result<PathBuf> {
    let p = PathBuf::from(arg);
    if p.is_file() {
        return Ok(p);
    }
    let k = KernelRelease::parse(arg)?;
    let p = profiles_dir(o).join(format!("{}.json", k.ksrc()));
    if !p.is_file() {
        return Err(io(p.display().to_string(), "no such profile"));
    }
    Ok(p)
}

fn wrappers_dir(o: &Opts, profile: &Path) -> Result<PathBuf> {
    if let Some(w) = o
        .wrappers
        .clone()
        .or_else(|| std::env::var_os("SHARUKHAN_WRAPPERS").map(PathBuf::from))
    {
        return Ok(w);
    }
    let dir = profile.parent().unwrap_or_else(|| Path::new("."));
    // profiles/kernel/<p>.json inside sharukhan-cli, beside the wrappers.
    let w = dir.join("../../..");
    w.canonicalize().map_err(|e| io(w.display().to_string(), e))
}

fn trust_path(o: &Opts, profile_dir: &Path) -> PathBuf {
    o.trust
        .clone()
        .unwrap_or_else(|| profile_dir.join("kernel-org-signers.json"))
}

fn load_profile(path: &Path) -> Result<Profile> {
    let p = Profile::load(path)?;
    let want = format!("{}.json", p.release()?.ksrc());
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    if name != want {
        return Err(io(
            path.display().to_string(),
            format!("a profile for {} must be named {want}", p.kernel),
        ));
    }
    Ok(p)
}

fn same_file(a: &Path, b: &Path) -> bool {
    match (a.canonicalize(), b.canonicalize()) {
        (Ok(x), Ok(y)) => x == y,
        _ => false,
    }
}

#[derive(Debug)]
struct Outcome {
    derived: Derived,
    out: PathBuf,
    branch: Option<branch::BranchReport>,
}

fn derive_one(o: &Opts, path: &Path) -> Result<Outcome> {
    let profile = load_profile(path)?;
    let pdir = path.parent().unwrap_or_else(|| Path::new("."));
    let trust = Trust::load(&trust_path(o, pdir))?;
    let v = &profile.source.verified;
    if trust.signer(&v.signer).is_none() {
        return Err(WrapperError::Verify {
            what: "profile source.verified.signer".into(),
            expected: "a reviewed kernel.org signer".into(),
            found: v.signer.clone(),
        });
    }
    let wdir = wrappers_dir(o, path)?;
    let base_path = wdir.join(&profile.base.script);
    let base_text =
        std::fs::read_to_string(&base_path).map_err(|e| io(base_path.display().to_string(), e))?;
    let target = profile.release()?;
    let out = o
        .out
        .clone()
        .unwrap_or_else(|| derive::default_out(&base_path, &target));
    if same_file(&out, &base_path)
        || out.file_name() == base_path.file_name() && out.parent() == base_path.parent()
    {
        return Err(io(
            out.display().to_string(),
            "is the base wrapper; refusing to overwrite it",
        ));
    }
    let branch = if o.no_branch {
        None
    } else {
        let repo = o
            .repo
            .clone()
            .or_else(|| std::env::var_os("SHARUKHAN_PHOTON_REPO").map(PathBuf::from))
            .ok_or_else(|| {
                io(
                    "branch check",
                    "no photon clone given: pass --repo <dir> (or set SHARUKHAN_PHOTON_REPO), or --no-branch to skip it",
                )
            })?;
        Some(branch::verify(&repo, &profile)?)
    };
    let derived = derive::derive_text(&base_text, &profile)?;
    Ok(Outcome {
        derived,
        out,
        branch,
    })
}

fn report(o: &Outcome, verb: &str) {
    let d = &o.derived;
    println!("{verb} {} ({} lines)", o.out.display(), d.measured.lines);
    println!(
        "  kernel {}  tag {}  sh -n {}  python heredocs parsed {}",
        d.target.ksrc(),
        d.target.tag(),
        d.measured.sh_n,
        d.measured.python_heredocs
    );
    for r in &d.renames {
        println!("  renamed {} -> {} x{}", r.from, r.to, r.count);
    }
    match &o.branch {
        Some(b) => {
            println!(
                "  branch {} at {} ({})",
                b.git_ref,
                &b.commit[..12.min(b.commit.len())],
                b.manifest
            );
            for c in &b.checked {
                println!("    ok  {c}");
            }
        }
        None => println!("  branch NOT verified (--no-branch)"),
    }
}

fn cmd_derive(o: &Opts) -> Result<()> {
    let arg = o
        .profile
        .clone()
        .or_else(|| o.positional.first().cloned())
        .ok_or_else(|| io("derive", "needs --profile <file|release>"))?;
    let path = profile_path(o, &arg)?;
    let outcome = derive_one(o, &path)?;
    if o.check {
        derive::check_against(&outcome.derived.script, &outcome.out)?;
        report(&outcome, "up to date:");
    } else {
        derive::write_atomic(&outcome.out, &outcome.derived.script)?;
        report(&outcome, "wrote");
    }
    Ok(())
}

fn cmd_check(o: &Opts) -> Result<()> {
    let dir = profiles_dir(o);
    let mut paths: Vec<PathBuf> = std::fs::read_dir(&dir)
        .map_err(|e| io(dir.display().to_string(), e))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| {
            p.extension().is_some_and(|x| x == "json")
                && p.file_name()
                    .is_some_and(|n| n != "kernel-org-signers.json")
        })
        .collect();
    paths.sort();
    if paths.is_empty() {
        return Err(io(dir.display().to_string(), "holds no profiles"));
    }
    let mut failed = Vec::new();
    for p in &paths {
        let r = derive_one(o, p)
            .and_then(|out| derive::check_against(&out.derived.script, &out.out).map(|_| out));
        match r {
            Ok(out) => report(&out, "up to date:"),
            Err(e) => {
                println!("FAILED {}: {e}", p.display());
                failed.push(p.display().to_string());
            }
        }
    }
    if failed.is_empty() {
        Ok(())
    } else {
        Err(io(
            "wrapper check",
            format!(
                "{} of {} profiles failed: {}",
                failed.len(),
                paths.len(),
                failed.join(", ")
            ),
        ))
    }
}

fn print_identity(k: &KernelRelease, listed: Option<&kernelorg::Listed>) {
    println!("{}", k.ksrc());
    let rows = [
        ("kind", k.kind_long().to_string()),
        ("rpm Version", k.rpm_version()),
        ("rpm Release", format!("{} (iteration 1)", k.rpm_release(1))),
        ("wrapper", k.script_file()),
        ("branch", k.branch()),
        ("git tag", k.git_tag()),
        ("tarball", k.source_url()),
        (
            "signature",
            k.signature_url()
                .unwrap_or_else(|| "none (verified via the signed tag)".into()),
        ),
        (
            "kernel.org",
            match listed {
                Some(l) => format!(
                    "listed as {}{}",
                    l.moniker,
                    if l.iseol { ", EOL" } else { "" }
                ),
                None => "not listed in releases.json".into(),
            },
        ),
    ];
    for (k, v) in rows {
        println!("  {k:<12} {v}");
    }
}

fn cmd_kernel(o: &Opts) -> Result<()> {
    let sel = o
        .positional
        .first()
        .ok_or_else(|| io("kernel", "needs a selector"))?;
    if o.offline {
        let k = KernelRelease::parse(sel)?;
        print_identity(&k, None);
        println!("  (offline: kernel.org not consulted)");
        return Ok(());
    }
    let cache = o
        .cache
        .clone()
        .map(Ok)
        .unwrap_or_else(kernelorg::default_cache)?;
    std::fs::create_dir_all(&cache).map_err(|e| io(cache.display().to_string(), e))?;
    let json_path = cache.join("releases.json");
    kernelorg::fetch(kernelorg::RELEASES_URL, &json_path)?;
    let json =
        std::fs::read_to_string(&json_path).map_err(|e| io(json_path.display().to_string(), e))?;
    let (latest, listed, other) = kernelorg::parse_releases(&json)?;
    for (k, l) in kernelorg::select(sel, &latest, &listed)? {
        print_identity(&k, l.as_ref());
    }
    if !other.is_empty() {
        println!(
            "(not kernel.org releases in this sense: {})",
            other.join(", ")
        );
    }
    Ok(())
}

fn today() -> Result<(i64, u32, u32, String)> {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|e| io("clock", e))?
        .as_secs() as i64;
    let (y, m, d) = escape::civil_from_days(secs.div_euclid(86400));
    Ok((y, m, d, format!("{y:04}-{m:02}-{d:02}")))
}

fn run_verify(o: &Opts, k: &KernelRelease, trust_file: &Path) -> Result<kernelorg::Verification> {
    let trust = Trust::load(trust_file)?;
    let cache = o
        .cache
        .clone()
        .map(Ok)
        .unwrap_or_else(kernelorg::default_cache)?;
    let v = kernelorg::verify(k, o.tarball.as_deref(), &cache, &trust)?;
    let who = trust
        .signer(&v.signer)
        .map(|s| s.name.as_str())
        .unwrap_or("?");
    println!("verified {} ({})", v.tarball.display(), v.method);
    println!("  sha512   {}", v.sha512);
    println!("  signer   {} ({who})", v.signer);
    if let Some(c) = &v.commit {
        println!("  commit   {c} ({}; snapshot == git archive)", k.git_tag());
    }
    println!("  entries  {} under linux-{}/", v.entries, k.ksrc());
    Ok(v)
}

fn cmd_verify(o: &Opts) -> Result<()> {
    let rel = o
        .positional
        .first()
        .ok_or_else(|| io("verify", "needs a release"))?;
    let k = KernelRelease::parse(rel)?;
    let pdir = profiles_dir(o);
    let v = run_verify(o, &k, &trust_path(o, &pdir))?;
    if let Some(p) = &o.profile {
        let path = profile_path(o, p)?;
        let prof = load_profile(&path)?;
        if prof.release()? != k {
            return Err(io(
                path.display().to_string(),
                format!("is the profile for {}, not {}", prof.kernel, k.ksrc()),
            ));
        }
        let pv = &prof.source.verified;
        let checks = [
            (
                "source.sha512",
                prof.source.sha512.clone(),
                v.sha512.clone(),
            ),
            (
                "source.verified.method",
                pv.method.clone(),
                v.method.to_string(),
            ),
            (
                "source.verified.signer",
                pv.signer.clone(),
                v.signer.clone(),
            ),
            (
                "source.verified.commit",
                pv.commit.clone().unwrap_or_default(),
                v.commit.clone().unwrap_or_default(),
            ),
        ];
        for (field, have, measured) in checks {
            if have != measured {
                return Err(WrapperError::Verify {
                    what: format!("{} {field}", path.display()),
                    expected: measured,
                    found: have,
                });
            }
        }
        println!("  profile  {} agrees", path.display());
    }
    Ok(())
}

/// Replace `from` with `to` in every string of a JSON value, counting.
fn rename_strings(v: &mut serde_json::Value, from: &str, to: &str, n: &mut usize) {
    match v {
        serde_json::Value::String(s) if s.contains(from) => {
            *n += s.matches(from).count();
            *s = s.replace(from, to);
        }
        serde_json::Value::Array(a) => a.iter_mut().for_each(|x| rename_strings(x, from, to, n)),
        serde_json::Value::Object(m) => m.values_mut().for_each(|x| rename_strings(x, from, to, n)),
        _ => {}
    }
}

/// Every string field (by JSON path) that still names a release or series.
fn review_list(v: &serde_json::Value, path: &str, out: &mut Vec<String>) {
    match v {
        serde_json::Value::String(s) => {
            let series = s
                .split(|c: char| !(c.is_ascii_digit() || c == '.'))
                .any(|w| {
                    let p: Vec<&str> = w.split('.').collect();
                    p.len() == 2 && p.iter().all(|x| !x.is_empty())
                });
            if !release_mentions(s).is_empty() || series {
                out.push(format!("{path}: {s}"));
            }
        }
        serde_json::Value::Array(a) => a
            .iter()
            .enumerate()
            .for_each(|(i, x)| review_list(x, &format!("{path}[{i}]"), out)),
        serde_json::Value::Object(m) => m.iter().for_each(|(k, x)| {
            review_list(
                x,
                &if path.is_empty() {
                    k.clone()
                } else {
                    format!("{path}.{k}")
                },
                out,
            )
        }),
        _ => {}
    }
}

fn cmd_profile_new(o: &Opts) -> Result<()> {
    let new = KernelRelease::parse(
        o.kernel
            .as_deref()
            .ok_or_else(|| io("profile-new", "needs --kernel <release>"))?,
    )?;
    let from_path = profile_path(
        o,
        o.from
            .as_deref()
            .ok_or_else(|| io("profile-new", "needs --from <profile>"))?,
    )?;
    let from = load_profile(&from_path)?;
    let old = from.release()?;
    if old == new {
        return Err(io(
            "profile-new",
            "--kernel is the --from profile's own release",
        ));
    }
    let pdir = from_path
        .parent()
        .unwrap_or_else(|| Path::new("."))
        .to_path_buf();
    let out = o
        .out
        .clone()
        .unwrap_or_else(|| pdir.join(format!("{}.json", new.ksrc())));
    if out.exists() && !o.force {
        return Err(io(
            out.display().to_string(),
            "exists; pass --force to replace it",
        ));
    }
    // The base as it is now: the new profile is reviewed against it.
    let wdir = wrappers_dir(o, &from_path)?;
    let base_path = wdir.join(&from.base.script);
    let base_text =
        std::fs::read_to_string(&base_path).map_err(|e| io(base_path.display().to_string(), e))?;
    let base = super::base::Base::parse(&base_text)?;
    let v = run_verify(o, &new, &trust_path(o, &pdir))?;
    let (y, m, d, iso) = today()?;
    let text =
        std::fs::read_to_string(&from_path).map_err(|e| io(from_path.display().to_string(), e))?;
    let mut j: serde_json::Value =
        serde_json::from_str(&text).map_err(|e| io(from_path.display().to_string(), e))?;
    let mut renamed = 0;
    rename_strings(&mut j, &old.ksrc(), &new.ksrc(), &mut renamed);
    j["kernel"] = new.ksrc().into();
    j["base"]["wrapper_version"] = base.wrapper_version()?.into();
    j["wrapper_version"] = 1.into();
    j["rpm_release_iteration"] = 1.into();
    j["source"]["sha512"] = v.sha512.clone().into();
    let mut verified = serde_json::json!({"method": v.method, "signer": v.signer, "on": iso});
    if let Some(c) = &v.commit {
        verified["commit"] = c.clone().into();
    }
    j["source"]["verified"] = verified;
    j["changelog"]["date"] = escape::changelog_date_of(y, m, d).into();
    let pretty =
        serde_json::to_string_pretty(&j).map_err(|e| io("serialising the profile", e))? + "\n";
    let prof: Profile = serde_json::from_str(&pretty).map_err(|e| io("new profile", e))?;
    prof.validate()?;
    derive::derive_text(&base_text, &prof)?;
    derive::write_atomic(&out, &pretty)?;
    use std::os::unix::fs::PermissionsExt;
    let _ = std::fs::set_permissions(&out, std::fs::Permissions::from_mode(0o644));
    println!(
        "wrote {} ({} release mentions renamed {} -> {}); it derives cleanly.",
        out.display(),
        renamed,
        old.ksrc(),
        new.ksrc()
    );
    let mut review = Vec::new();
    review_list(&j, "", &mut review);
    review.retain(|l| {
        !l.starts_with("kernel:") && !l.starts_with("base.") && !l.starts_with("source.")
    });
    println!("Review before use - these name a release or series, and the patch files must exist,");
    println!("rebased for {}, on {}:", new.ksrc(), new.branch());
    for r in review {
        println!("  {r}");
    }
    for k in &prof.kernel_patches {
        println!("  kernel_patches.{}: {}", k.name, k.file);
    }
    Ok(())
}

/// Entry point for `sharukhan wrapper ...`; returns the process exit code.
pub fn main(args: &[String]) -> u8 {
    let Some((cmd, rest)) = args.split_first() else {
        print!("{USAGE}");
        return 64;
    };
    let o = match parse(rest) {
        Ok(o) => o,
        Err(e) => {
            eprintln!("sharukhan wrapper: {e}");
            return 64;
        }
    };
    let r = match cmd.as_str() {
        "derive" => cmd_derive(&o),
        "check" => cmd_check(&o),
        "kernel" => cmd_kernel(&o),
        "verify" => cmd_verify(&o),
        "profile-new" => cmd_profile_new(&o),
        "-h" | "--help" | "help" => {
            print!("{USAGE}");
            return 0;
        }
        other => {
            eprintln!("sharukhan wrapper: unknown command: {other}\n\n{USAGE}");
            return 64;
        }
    };
    match r {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("sharukhan wrapper: {e}");
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(v: &[&str]) -> Vec<String> {
        v.iter().map(|x| x.to_string()).collect()
    }

    #[test]
    fn options_parse_and_contradictions_are_refused() {
        let o = parse(&s(&["--profile", "7.3-rc4", "--check", "--no-branch"])).unwrap();
        assert!(o.check && o.no_branch);
        assert!(parse(&s(&["--repo", "/x", "--no-branch"])).is_err());
        assert!(parse(&s(&["--profile"])).is_err());
        assert!(parse(&s(&["--profile", "--check"])).is_err());
        assert!(parse(&s(&["--bogus"])).is_err());
    }

    #[test]
    fn unknown_commands_and_bad_options_exit_64() {
        assert_eq!(main(&s(&["frobnicate"])), 64);
        assert_eq!(main(&s(&["derive", "--nope"])), 64);
        assert_eq!(main(&s(&["help"])), 0);
        assert_eq!(main(&[]), 64);
    }

    #[test]
    fn json_renames_count_and_review_finds_series() {
        let mut j = serde_json::json!({"a": "7.3-rc4 and 7.3-rc4", "b": ["x 7.3-rc4"], "c": 1});
        let mut n = 0;
        rename_strings(&mut j, "7.3-rc4", "7.3-rc5", &mut n);
        assert_eq!(n, 3);
        assert_eq!(j["b"][0], "x 7.3-rc5");
        let mut r = Vec::new();
        review_list(
            &serde_json::json!({"s": "7.3's DRM", "t": "plain", "u": ["on 7.2.8"]}),
            "",
            &mut r,
        );
        assert_eq!(r, vec!["s: 7.3's DRM", "u[0]: on 7.2.8"]);
    }

    /// The committed 7.3-rc4 wrapper is exactly what the committed base and
    /// profile derive - the reference the Python generator was retired against.
    #[test]
    fn golden_the_committed_7_3_rc4_wrapper_is_derived_byte_for_byte() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let o = Opts {
            no_branch: true,
            ..Default::default()
        };
        let out = derive_one(&o, &root.join("profiles/kernel/7.3-rc4.json")).unwrap();
        let committed = std::fs::read_to_string(root.join("../runPh7-3-RC4.sh")).unwrap();
        derive::check_against(&out.derived.script, &out.out).unwrap();
        assert_eq!(out.derived.script, committed);
        assert!(out.derived.renames.iter().all(|r| r.count > 0));
    }

    /// A private copy of the base, the committed derived wrapper, the profile
    /// and the trust file, laid out as in the repository.
    struct Tree {
        dir: PathBuf,
    }

    impl Tree {
        fn new(tag: &str) -> Tree {
            let root = Path::new(env!("CARGO_MANIFEST_DIR"));
            let dir = std::env::temp_dir().join(format!("shk-cli-{tag}-{}", std::process::id()));
            let _ = std::fs::remove_dir_all(&dir);
            let prof = dir.join("sharukhan-cli/profiles/kernel");
            std::fs::create_dir_all(&prof).unwrap();
            for f in ["runPh7-2-7.sh", "runPh7-3-RC4.sh"] {
                std::fs::copy(root.join("..").join(f), dir.join(f)).unwrap();
            }
            for f in ["7.3-rc4.json", "kernel-org-signers.json"] {
                std::fs::copy(root.join("profiles/kernel").join(f), prof.join(f)).unwrap();
            }
            Tree { dir }
        }
        fn profiles(&self) -> PathBuf {
            self.dir.join("sharukhan-cli/profiles/kernel")
        }
        fn opts(&self) -> Opts {
            Opts {
                profiles: Some(self.profiles()),
                no_branch: true,
                ..Default::default()
            }
        }
    }

    impl Drop for Tree {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.dir);
        }
    }

    #[test]
    fn derive_writes_then_checks_and_check_reports_drift() {
        let t = Tree::new("derive");
        let mut o = t.opts();
        o.profile = Some("7.3-rc4".into());
        o.check = true;
        cmd_derive(&o).unwrap();
        cmd_check(&t.opts()).unwrap();
        // drift in the committed wrapper
        let out = t.dir.join("runPh7-3-RC4.sh");
        let text = std::fs::read_to_string(&out).unwrap();
        std::fs::write(&out, text.replacen("wrapper v10", "wrapper v11", 1)).unwrap();
        let e = cmd_derive(&o).unwrap_err().to_string();
        assert!(
            e.contains("differs from a fresh derivation at line 4"),
            "{e}"
        );
        assert!(cmd_check(&t.opts())
            .unwrap_err()
            .to_string()
            .contains("1 of 1 profiles failed"));
        // writing repairs it, atomically
        o.check = false;
        cmd_derive(&o).unwrap();
        assert_eq!(std::fs::read_to_string(&out).unwrap(), text);
        // to another path
        o.out = Some(t.dir.join("elsewhere.sh"));
        cmd_derive(&o).unwrap();
        assert_eq!(
            std::fs::read_to_string(t.dir.join("elsewhere.sh")).unwrap(),
            text
        );
    }

    #[test]
    fn derive_refuses_to_overwrite_the_base_and_to_skip_the_branch_silently() {
        let t = Tree::new("guard");
        let mut o = t.opts();
        o.profile = Some("7.3-rc4".into());
        o.out = Some(t.dir.join("runPh7-2-7.sh"));
        let e = cmd_derive(&o).unwrap_err().to_string();
        assert!(e.contains("refusing to overwrite"), "{e}");
        let mut o = t.opts();
        o.profile = Some("7.3-rc4".into());
        o.no_branch = false;
        if std::env::var_os("SHARUKHAN_PHOTON_REPO").is_none() {
            let e = cmd_derive(&o).unwrap_err().to_string();
            assert!(e.contains("--no-branch to skip it"), "{e}");
        }
        o.repo = Some(t.dir.join("no-such-clone"));
        assert!(cmd_derive(&o).is_err());
    }

    #[test]
    fn profiles_are_found_by_release_and_must_be_named_after_it() {
        let t = Tree::new("names");
        let o = t.opts();
        assert!(profile_path(&o, "7.3-rc4")
            .unwrap()
            .ends_with("7.3-rc4.json"));
        assert!(profile_path(&o, "7.3-rc5")
            .unwrap_err()
            .to_string()
            .contains("no such profile"));
        assert!(profile_path(&o, "not-a-release").is_err());
        let wrong = t.profiles().join("7.3-rc5.json");
        std::fs::copy(t.profiles().join("7.3-rc4.json"), &wrong).unwrap();
        let e = load_profile(&wrong).unwrap_err().to_string();
        assert!(e.contains("must be named 7.3-rc4.json"), "{e}");
        // check covers every profile, and a misnamed one fails it
        assert!(cmd_check(&o).is_err());
        let empty = t.dir.join("empty");
        std::fs::create_dir_all(&empty).unwrap();
        let mut e2 = t.opts();
        e2.profiles = Some(empty);
        assert!(cmd_check(&e2)
            .unwrap_err()
            .to_string()
            .contains("holds no profiles"));
    }

    #[test]
    fn a_profile_signed_by_an_unreviewed_key_does_not_derive() {
        let t = Tree::new("signer");
        let p = t.profiles().join("7.3-rc4.json");
        let text = std::fs::read_to_string(&p).unwrap();
        std::fs::write(
            &p,
            text.replace(
                "ABAF11C65A2970B130ABE3C479BE3E4300411886",
                "1111111111111111111111111111111111111111",
            ),
        )
        .unwrap();
        let e = derive_one(&t.opts(), &p).unwrap_err().to_string();
        assert!(e.contains("reviewed kernel.org signer"), "{e}");
    }

    #[test]
    fn commands_without_their_arguments_say_what_is_missing() {
        let o = Opts::default();
        for (r, needle) in [
            (cmd_derive(&o), "needs --profile"),
            (cmd_kernel(&o), "needs a selector"),
            (cmd_verify(&o), "needs a release"),
            (cmd_profile_new(&o), "needs --kernel"),
        ] {
            assert!(r.unwrap_err().to_string().contains(needle), "{needle}");
        }
        let o = Opts {
            kernel: Some("7.3-rc5".into()),
            ..Default::default()
        };
        assert!(cmd_profile_new(&o)
            .unwrap_err()
            .to_string()
            .contains("needs --from"));
        let mut o = Opts {
            positional: vec!["7.4".into()],
            offline: true,
            ..Default::default()
        };
        cmd_kernel(&o).unwrap();
        o.positional = vec!["7.4.0".into()];
        assert!(cmd_kernel(&o).is_err());
    }

    #[test]
    fn profile_new_refuses_its_own_release_and_an_existing_file() {
        let t = Tree::new("new");
        let mut o = t.opts();
        o.from = Some(t.profiles().join("7.3-rc4.json").display().to_string());
        o.kernel = Some("7.3-rc4".into());
        assert!(cmd_profile_new(&o)
            .unwrap_err()
            .to_string()
            .contains("own release"));
        o.kernel = Some("7.3-rc5".into());
        o.out = Some(t.profiles().join("7.3-rc4.json"));
        assert!(cmd_profile_new(&o)
            .unwrap_err()
            .to_string()
            .contains("--force"));
    }

    #[test]
    fn today_is_a_real_date() {
        let (y, m, d, iso) = today().unwrap();
        assert!(y >= 2026 && (1..=12).contains(&m) && (1..=31).contains(&d));
        assert_eq!(iso.len(), 10);
    }
}
