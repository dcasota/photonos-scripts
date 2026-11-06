//! `--systemd <release>`: an ISO whose systemd is a systemd release other than
//! the one the Photon OS 5.0 tree packages (FRD-004).
//!
//! The pattern is the kernel profile's: a release string is parsed into every
//! name it implies; a reviewed profile pins the source (the GitHub tarball's
//! sha512, the tagged commit and who signed the tag); the port of
//! `SPECS/systemd` lives on a branch `experimental/systemd-<release>` of the
//! gate repository; a build is refused until that branch carries exactly what
//! the profile pins and its spec parses, passes the spec checker and applies
//! every patch to the verified tarball. Nothing about a release is written
//! here: it is computed from the release string or read from the profile.

use std::path::{Path, PathBuf};
use std::process::Command;

use serde::Deserialize;

use crate::sha512::Sha512;
use crate::wrapper::kernelorg::{self, Keyring, TarWalk, Trust};

/// Where systemd's sources and the keys of its signers may be fetched from.
pub const HOSTS: [&str; 3] = ["github.com", "codeload.github.com", "keys.openpgp.org"];
pub const REPO: &str = "https://github.com/systemd/systemd.git";
pub const SIGNERS_FILE: &str = "systemd-signers.json";

// ------------------------------------------------------------- identity ---

/// A systemd release as tagged in systemd/systemd: `<major>` or
/// `<major>.<point>`. Release candidates are refused: Photon's RPM version
/// comparison has no `~` to sort them below the final.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SystemdRelease {
    pub major: u32,
    pub point: Option<u32>,
}

impl SystemdRelease {
    /// `262.2`, `262`, or the tag spelling `v262.2`. No leading zeros, no
    /// sign, no whitespace, bounded components.
    pub fn parse(input: &str) -> Result<SystemdRelease, String> {
        let bad = |why: &str| format!("systemd release {input:?}: {why}");
        let s = input.strip_prefix('v').unwrap_or(input);
        if s.contains("-rc") {
            return Err(bad("release candidates are not packaged (RPM versions here have no '~' to sort them below the final)"));
        }
        let num = |p: &str, max: u32| -> Result<u32, String> {
            if p.is_empty() || !p.bytes().all(|b| b.is_ascii_digit()) {
                return Err(bad("expected <major> or <major>.<point>, digits only"));
            }
            if p.len() > 1 && p.starts_with('0') {
                return Err(bad("leading zero"));
            }
            let v: u32 = p.parse().map_err(|_| bad("number out of range"))?;
            if v == 0 || v > max {
                return Err(bad(&format!("component must be 1..={max}")));
            }
            Ok(v)
        };
        let mut parts = s.split('.');
        let major = num(parts.next().unwrap_or(""), 9999)?;
        let point = parts.next().map(|p| num(p, 999)).transpose()?;
        if parts.next().is_some() {
            return Err(bad("expected <major> or <major>.<point>"));
        }
        Ok(SystemdRelease { major, point })
    }

    /// The RPM Version and the tarball's version: `262.2`.
    pub fn version(&self) -> String {
        match self.point {
            Some(p) => format!("{}.{p}", self.major),
            None => self.major.to_string(),
        }
    }
    pub fn tag(&self) -> String {
        format!("v{}", self.version())
    }
    /// The top directory of the GitHub tarball and of `git archive`.
    pub fn top_dir(&self) -> String {
        format!("systemd-{}", self.version())
    }
    pub fn tarball(&self) -> String {
        format!("{}.tar.gz", self.top_dir())
    }
    pub fn url(&self) -> String {
        format!("https://github.com/systemd/systemd/archive/refs/tags/{}.tar.gz", self.tag())
    }
    pub fn branch(&self) -> String {
        format!("experimental/systemd-{}", self.version())
    }
    pub fn profile_file(&self) -> String {
        format!("{}.json", self.version())
    }
    /// The axis name used for build roots and caches: `s262.2`.
    pub fn key(&self) -> String {
        format!("s{}", self.version())
    }
}

// -------------------------------------------------------------- profile ---

#[derive(Debug, Clone, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Verified {
    pub method: String,
    pub signer: String,
    pub on: String,
}

#[derive(Debug, Clone, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Source {
    pub url: String,
    pub sha512: String,
    pub commit: String,
    pub verified: Verified,
}

/// `profiles/systemd/<release>.json`.
#[derive(Debug, Clone, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Profile {
    pub schema: u32,
    pub systemd: String,
    pub branch: String,
    /// The RPM Release number of the port (`262.2-<n>`).
    pub rpm_release: u32,
    pub source: Source,
}

pub const METHOD: &str = "signed-tag+git-archive";

fn is_date(s: &str) -> bool {
    let b = s.as_bytes();
    b.len() == 10 && b[4] == b'-' && b[7] == b'-' && b.iter().enumerate().all(|(i, c)| i == 4 || i == 7 || c.is_ascii_digit())
}

fn is_sha512(s: &str) -> bool {
    s.len() == 128 && s.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

impl Profile {
    /// Parse and check a profile against the release it must describe and the
    /// reviewed signers.
    pub fn parse(text: &str, source: &str, trust: &Trust) -> Result<(Profile, SystemdRelease), String> {
        let p: Profile = serde_json::from_str(text).map_err(|e| format!("{source}: not a valid systemd profile: {e}"))?;
        let bad = |field: &str, why: String| format!("{source}: {field}: {why}");
        if p.schema != 1 {
            return Err(bad("schema", format!("{} is not 1", p.schema)));
        }
        let r = SystemdRelease::parse(&p.systemd).map_err(|e| bad("systemd", e))?;
        if p.systemd != r.version() {
            return Err(bad("systemd", format!("write it as {}", r.version())));
        }
        let want_file = r.profile_file();
        if let Some(name) = Path::new(source).file_name().and_then(|n| n.to_str()) {
            if name.ends_with(".json") && name != want_file {
                return Err(bad("file name", format!("the profile of {} is named {want_file}", r.version())));
            }
        }
        if p.branch != r.branch() {
            return Err(bad("branch", format!("{} is not {}", p.branch, r.branch())));
        }
        if p.rpm_release == 0 {
            return Err(bad("rpm_release", "must be 1 or more".into()));
        }
        if p.source.url != r.url() {
            return Err(bad("source.url", format!("{} is not {}", p.source.url, r.url())));
        }
        if !is_sha512(&p.source.sha512) {
            return Err(bad("source.sha512", "128 lowercase hex digits".into()));
        }
        if !crate::wrapper::profile::is_commit(&p.source.commit) {
            return Err(bad("source.commit", "40 lowercase hex digits".into()));
        }
        let v = &p.source.verified;
        if v.method != METHOD {
            return Err(bad("source.verified.method", format!("{} is not {METHOD}", v.method)));
        }
        if trust.signer(&v.signer).is_none() {
            return Err(bad("source.verified.signer", format!("{} is not a reviewed systemd signer", v.signer)));
        }
        if !is_date(&v.on) {
            return Err(bad("source.verified.on", "YYYY-MM-DD".into()));
        }
        Ok((p, r))
    }

    /// The NEVR the port's packages carry with the tree's dist tag.
    pub fn nevr(&self, dist: &str) -> String {
        format!("{}-{}{dist}", self.systemd, self.rpm_release)
    }

    /// The profile as JSON (keys sorted), as the files under
    /// `profiles/systemd/` are written.
    pub fn to_json(&self) -> String {
        let v = serde_json::json!({
            "schema": self.schema,
            "systemd": self.systemd,
            "branch": self.branch,
            "rpm_release": self.rpm_release,
            "source": {
                "url": self.source.url,
                "sha512": self.source.sha512,
                "commit": self.source.commit,
                "verified": {"method": self.source.verified.method, "signer": self.source.verified.signer, "on": self.source.verified.on},
            },
        });
        format!("{}\n", serde_json::to_string_pretty(&v).unwrap_or_default())
    }
}

/// The reviewed systemd signers: `SHARUKHAN_SYSTEMD_PROFILES/systemd-signers.json`
/// when that directory is set, else the copy built in.
pub fn trust() -> Result<Trust, String> {
    let (source, text) = data_file(SIGNERS_FILE)?;
    Trust::parse(&text, &source, &HOSTS, "systemd").map_err(|e| e.to_string())
}

/// A file of `profiles/systemd/`: from `SHARUKHAN_SYSTEMD_PROFILES` when set
/// (a profile under review), else built in. Returns where it came from.
fn data_file(name: &str) -> Result<(String, String), String> {
    match std::env::var_os("SHARUKHAN_SYSTEMD_PROFILES") {
        Some(d) if !d.is_empty() => {
            let p = PathBuf::from(d).join(name);
            let t = std::fs::read_to_string(&p).map_err(|e| format!("{}: {e}", p.display()))?;
            Ok((p.display().to_string(), t))
        }
        _ => crate::wrapper::embedded::systemd_file(name)
            .map(|t| (format!("built-in profiles/systemd/{name}"), t.to_string()))
            .ok_or_else(|| format!("no systemd profile {name} is built in (set SHARUKHAN_SYSTEMD_PROFILES for one on disk)")),
    }
}

/// The profile of `release`, checked.
pub fn load(release: &str) -> Result<(Profile, SystemdRelease, String), String> {
    let r = SystemdRelease::parse(release)?;
    let trust = trust()?;
    let (source, text) = data_file(&r.profile_file())?;
    let (p, r) = Profile::parse(&text, &source, &trust)?;
    Ok((p, r, source))
}

// --------------------------------------------------------- verification ---

/// What verifying a release established.
#[derive(Debug, Clone, PartialEq)]
pub struct Verification {
    pub tarball: PathBuf,
    /// sha512 of the tarball as downloaded: the pin.
    pub sha512: String,
    pub commit: String,
    pub signer: String,
    pub entries: u64,
}

/// `$SHARUKHAN_SYSTEMD_CACHE`, else `$XDG_CACHE_HOME/sharukhan/systemd`, else
/// `$HOME/.cache/sharukhan/systemd`.
pub fn default_cache() -> Result<PathBuf, String> {
    if let Some(p) = std::env::var_os("SHARUKHAN_SYSTEMD_CACHE").filter(|p| !p.is_empty()) {
        return Ok(PathBuf::from(p));
    }
    if let Some(x) = std::env::var_os("XDG_CACHE_HOME").filter(|p| !p.is_empty()) {
        return Ok(PathBuf::from(x).join("sharukhan/systemd"));
    }
    let home = std::env::var_os("HOME").ok_or("no HOME for the default systemd cache; set SHARUKHAN_SYSTEMD_CACHE")?;
    Ok(PathBuf::from(home).join(".cache/sharukhan/systemd"))
}

fn ve(e: crate::wrapper::error::WrapperError) -> String {
    e.to_string()
}

/// Verify a release from scratch: the tarball (downloaded unless `tarball`
/// names a local copy), the tag fetched from systemd/systemd, its signature by
/// a reviewed signer in a keyring private to this verification, and the
/// tarball's content byte-identical to `git archive` of the tagged commit.
pub fn verify(r: &SystemdRelease, tarball: Option<&Path>, cache: &Path, trust: &Trust) -> Result<Verification, String> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::create_dir_all(cache).map_err(|e| format!("{}: {e}", cache.display()))?;
    let _ = std::fs::set_permissions(cache, std::fs::Permissions::from_mode(0o700));
    let path = match tarball {
        Some(p) => {
            if p.file_name().and_then(|n| n.to_str()) != Some(r.tarball().as_str()) {
                return Err(format!("--tarball {}: the file of {} is named {}", p.display(), r.tag(), r.tarball()));
            }
            p.to_path_buf()
        }
        None => {
            let p = cache.join(r.tarball());
            if !p.exists() {
                kernelorg::fetch_in(&r.url(), &p, &HOSTS).map_err(ve)?;
            }
            p
        }
    };
    let work = cache.join(format!("work.{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&work);
    std::fs::create_dir_all(&work).map_err(|e| format!("{}: {e}", work.display()))?;
    let res = (|| {
        let ring = Keyring::build(&work, trust).map_err(ve)?;
        let (signer, commit, walk) = verify_tag_and_archive(r, &path, &cache.join("systemd.git"), &ring, trust)?;
        walk.check(&format!("{} contents", r.tarball())).map_err(ve)?;
        let sha512 = crate::sha512::file(&path)?;
        Ok(Verification { tarball: path.clone(), sha512, commit, signer, entries: walk.entries })
    })();
    let _ = std::fs::remove_dir_all(&work);
    res
}

fn verify_tag_and_archive(
    r: &SystemdRelease,
    tarball: &Path,
    repo: &Path,
    ring: &Keyring,
    trust: &Trust,
) -> Result<(String, String, TarWalk), String> {
    let git = |args: &[&str]| {
        let mut c = kernelorg::tool("git");
        c.arg("-C").arg(repo).env("GNUPGHOME", &ring.home).args(args);
        c
    };
    if !repo.join("HEAD").exists() {
        std::fs::create_dir_all(repo).map_err(|e| format!("{}: {e}", repo.display()))?;
        let mut c = kernelorg::tool("git");
        c.args(["init", "--quiet", "--bare", "--"]).arg(repo);
        kernelorg::run(c, "git init --bare").map_err(ve)?;
    }
    kernelorg::check_url_in(REPO, &HOSTS).map_err(ve)?;
    let tag = r.tag();
    let tag_ref = format!("refs/tags/{tag}");
    let refspec = format!("+{tag_ref}:{tag_ref}");
    kernelorg::run(
        git(&["-c", "protocol.allow=never", "-c", "protocol.https.allow=always", "fetch", "--quiet", "--depth=1", "--no-tags", "--", REPO, &refspec]),
        &format!("git fetch {tag}"),
    )
    .map_err(ve)?;
    let raw = String::from_utf8_lossy(&kernelorg::run(git(&["cat-file", "tag", &tag_ref]), "git cat-file tag").map_err(ve)?).into_owned();
    let header = |k: &str| {
        raw.lines()
            .take_while(|l| !l.is_empty())
            .find_map(|l| l.strip_prefix(&format!("{k} ")).map(str::to_string))
    };
    let commit = header("object").unwrap_or_default();
    if !crate::wrapper::profile::is_commit(&commit) || header("type").as_deref() != Some("commit") || header("tag").as_deref() != Some(tag.as_str()) {
        return Err(format!("tag object {tag}: expected object <commit>, type commit, tag {tag}; found {}", raw.lines().take(3).collect::<Vec<_>>().join(" | ")));
    }
    let mut vt = git(&["verify-tag", "--raw", &tag_ref]);
    vt.stdin(std::process::Stdio::null());
    let out = vt.output().map_err(|e| format!("git verify-tag: {e}"))?;
    let signer = kernelorg::judge_status(&String::from_utf8_lossy(&out.stderr), trust).map_err(ve)?;
    if !out.status.success() {
        return Err(format!("git verify-tag {tag}: exit {}", out.status.code().unwrap_or(-1)));
    }
    let mut walk = TarWalk::new(&r.top_dir());
    let mut snap = Sha512::default();
    let mut gz = kernelorg::tool("gzip");
    gz.args(["-dc", "--"]).arg(tarball);
    kernelorg::stream(gz, "decompressing the tarball", |c| {
        walk.update(c);
        snap.update(c);
        Ok(())
    })
    .map_err(ve)?;
    let mut arch = Sha512::default();
    let prefix = format!("--prefix={}/", r.top_dir());
    kernelorg::stream(git(&["archive", "--format=tar", &prefix, &commit]), "git archive", |c| {
        arch.update(c);
        Ok(())
    })
    .map_err(ve)?;
    let (snap, arch) = (snap.hex(), arch.hex());
    if snap != arch {
        return Err(format!("{} content differs from git archive of {commit} ({tag})", r.tarball()));
    }
    if walk.comment.as_deref() != Some(commit.as_str()) {
        return Err(format!("{}: its pax comment {:?} is not the tagged commit {commit}", r.tarball(), walk.comment));
    }
    Ok((signer, commit, walk))
}

// ------------------------------------------------------ the spec edits ---

/// The value of the first `<key>:` line of a spec text.
pub fn spec_field(text: &str, key: &str) -> Option<String> {
    text.lines()
        .find(|l| l.starts_with(&format!("{key}:")))
        .and_then(|l| l.split_whitespace().nth(1))
        .map(str::to_string)
}

/// The version bump that starts a port: the first `Version:` and `Release:`
/// lines set, and one `%changelog` entry on top. Every other line is the
/// release tree's, for the port to adapt.
pub fn bump_spec(text: &str, version: &str, rpm_release: u32, date: &str, author: &str) -> Result<String, String> {
    let mut out = String::with_capacity(text.len() + 128);
    let (mut ver, mut rel, mut log) = (false, false, false);
    for l in text.split_inclusive('\n') {
        let key = |k: &str| l.starts_with(&format!("{k}:"));
        let pad = |k: &str| {
            let rest = &l[k.len() + 1..];
            let ws: String = rest.chars().take_while(|c| *c == ' ' || *c == '\t').collect();
            format!("{k}:{ws}")
        };
        if !ver && key("Version") {
            out.push_str(&format!("{}{version}\n", pad("Version")));
            ver = true;
        } else if !rel && key("Release") {
            out.push_str(&format!("{}{rpm_release}%{{?dist}}\n", pad("Release")));
            rel = true;
        } else if !log && l.trim_end() == "%changelog" {
            out.push_str(l);
            out.push_str(&format!("* {date} {author} {version}-{rpm_release}\n- Update to systemd {version}\n"));
            log = true;
        } else {
            out.push_str(l);
        }
    }
    for (done, what) in [(ver, "Version:"), (rel, "Release:"), (log, "%changelog")] {
        if !done {
            return Err(format!("the spec has no {what} line"));
        }
    }
    Ok(out)
}

/// Point the `config.yaml` source entry of the systemd tarball at the
/// verified release: archive, sha512, name, version, url and commit_id.
pub fn set_source(yaml: &str, r: &SystemdRelease, sha512: &str, commit: &str) -> Result<String, String> {
    let mut out = String::with_capacity(yaml.len());
    let mut inside = false;
    let mut entries = 0;
    let mut set = std::collections::BTreeSet::new();
    for l in yaml.split_inclusive('\n') {
        if let Some(name) = l.strip_prefix("- archive: ") {
            inside = name.trim().starts_with("systemd-") && name.trim().ends_with(".tar.gz");
            if inside {
                entries += 1;
                out.push_str(&format!("- archive: {}\n", r.tarball()));
                set.insert("archive");
                continue;
            }
        } else if !l.starts_with(' ') && !l.starts_with('-') {
            inside = false;
        }
        if inside {
            let indent: String = l.chars().take_while(|c| *c == ' ').collect();
            let field = l.trim_start().split_once(':').map(|(k, _)| k).unwrap_or("");
            let value = match field {
                "archive_sha512sum" => Some(sha512.to_string()),
                "name" => Some(r.top_dir()),
                "version" => Some(r.version()),
                "url" => Some(r.url()),
                "commit_id" => Some(commit.to_string()),
                _ => None,
            };
            if let Some(v) = value {
                out.push_str(&format!("{indent}{field}: {v}\n"));
                set.insert(field);
                continue;
            }
        }
        out.push_str(l);
    }
    if entries != 1 {
        return Err(format!("config.yaml has {entries} systemd-*.tar.gz source entries, not one"));
    }
    for f in ["archive", "archive_sha512sum", "name", "version", "url", "commit_id"] {
        if !set.contains(f) {
            return Err(format!("config.yaml's systemd source entry has no {f}"));
        }
    }
    Ok(out)
}

// ----------------------------------------------------- the patch replay ---

/// The patches `%autosetup -p1` applies, in the order it applies them: by
/// number, an unnumbered `Patch:` taking the next one, read from an expanded
/// spec (conditionals decided).
pub fn patches_in_order(expanded: &str) -> Vec<String> {
    let mut next = 0u32;
    let mut v: Vec<(u32, String)> = Vec::new();
    for l in expanded.lines() {
        let Some(rest) = l.strip_prefix("Patch") else { continue };
        let Some((num, file)) = rest.split_once(':') else { continue };
        let n = if num.is_empty() {
            next
        } else if let Ok(n) = num.parse::<u32>() {
            n
        } else {
            continue;
        };
        next = n + 1;
        if let Some(f) = file.split_whitespace().next() {
            v.push((n, f.to_string()));
        }
    }
    v.sort_by_key(|(n, _)| *n);
    v.into_iter().map(|(_, f)| f).collect()
}

#[derive(Debug, Clone, PartialEq)]
pub enum Applies {
    Yes,
    AlreadyUpstream,
    No(String),
}

/// Apply each patch in turn to `src` at fuzz 0; one that does not apply is
/// tried in reverse (the release already carries it) and otherwise reported
/// with patch's own words. The replay goes on after a failure, so the report
/// lists every patch.
pub fn replay(src: &Path, spec_dir: &Path, patches: &[String]) -> Vec<(String, Applies)> {
    let run = |file: &Path, extra: &[&str]| -> Result<(), String> {
        let f = std::fs::File::open(file).map_err(|e| format!("{}: {e}", file.display()))?;
        let o = Command::new("patch")
            .args(["-p1", "--fuzz=0", "--batch", "--silent", "--no-backup-if-mismatch", "-r", "-"])
            .args(extra)
            .current_dir(src)
            .stdin(f)
            .output()
            .map_err(|e| format!("patch: {e}"))?;
        if o.status.success() {
            Ok(())
        } else {
            let all = format!("{}{}", String::from_utf8_lossy(&o.stdout), String::from_utf8_lossy(&o.stderr));
            Err(all.lines().take(3).collect::<Vec<_>>().join(" / "))
        }
    };
    patches
        .iter()
        .map(|p| {
            let file = spec_dir.join(p);
            let outcome = match run(&file, &["--forward", "--dry-run"]) {
                Ok(()) => match run(&file, &["--forward"]) {
                    Ok(()) => Applies::Yes,
                    Err(e) => Applies::No(e),
                },
                Err(e) => match run(&file, &["--reverse", "--dry-run"]) {
                    Ok(()) => Applies::AlreadyUpstream,
                    Err(_) => Applies::No(e),
                },
            };
            (p.clone(), outcome)
        })
        .collect()
}

/// meson's own options, which a project's option file does not declare.
const MESON_BUILTIN: [&str; 27] = [
    "prefix", "bindir", "datadir", "includedir", "infodir", "libdir", "libexecdir", "localedir", "localstatedir", "mandir",
    "sbindir", "sharedstatedir", "sysconfdir", "auto_features", "backend", "buildtype", "debug", "default_library",
    "errorlogs", "install_umask", "layout", "optimization", "strip", "unity", "warning_level", "werror", "wrap_mode",
];

/// The `-D<option>` names an expanded spec passes to meson that the release's
/// option file (`meson_options.txt` or `meson.options`) does not declare.
pub fn unknown_meson_options(src: &Path, expanded: &str) -> Result<Vec<String>, String> {
    let mut defined = std::collections::BTreeSet::new();
    let mut found = false;
    for f in ["meson_options.txt", "meson.options"] {
        if let Ok(t) = std::fs::read_to_string(src.join(f)) {
            found = true;
            for part in t.split("option(").skip(1) {
                let name: String = part.trim_start().trim_start_matches(['\'', '"']).chars().take_while(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_').collect();
                if !name.is_empty() {
                    defined.insert(name);
                }
            }
        }
    }
    if !found {
        return Err(format!("{}: neither meson_options.txt nor meson.options", src.display()));
    }
    let mut unknown = std::collections::BTreeSet::new();
    for tok in expanded.split(|c: char| c.is_whitespace() || c == '"' || c == '\'') {
        let Some(rest) = tok.strip_prefix("-D") else { continue };
        let Some((name, _)) = rest.split_once('=') else { continue };
        if name.is_empty() || !name.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_') {
            continue;
        }
        if name.starts_with("b_") || name.ends_with("_args") || name.ends_with("_link_args") || MESON_BUILTIN.contains(&name) || defined.contains(name) {
            continue;
        }
        unknown.insert(name.to_string());
    }
    Ok(unknown.into_iter().collect())
}

// --------------------------------------------- the port: start and check ---

fn git_in(dir: &Path, args: &[&str]) -> Result<String, String> {
    let o = Command::new("git").arg("-C").arg(dir).args(args).output().map_err(|e| format!("git {}: {e}", args.join(" ")))?;
    if !o.status.success() {
        return Err(format!("git {}: {}", args.join(" "), String::from_utf8_lossy(&o.stderr).trim()));
    }
    Ok(String::from_utf8_lossy(&o.stdout).into_owned())
}

fn today(fmt: &str) -> Result<String, String> {
    let o = Command::new("date").args(["-u", fmt]).output().map_err(|e| format!("date: {e}"))?;
    let s = String::from_utf8_lossy(&o.stdout).trim().to_string();
    if s.is_empty() {
        return Err("date printed nothing".into());
    }
    Ok(s)
}

/// A work directory under the builder's shared root, removed again by its
/// caller: the spec tools may run in the builder container, which sees only
/// that root.
fn scratch(cfg: &crate::config::Config, what: &str) -> Result<PathBuf, String> {
    let d = cfg.work.join(format!("systemd-{what}.{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).map_err(|e| format!("{}: {e}", d.display()))?;
    Ok(d)
}

/// `photon-subrelease`, `photon-mainline` and `photon-dist-tag` of a
/// build-config.json text.
fn build_params(text: &str) -> Result<(String, String, String), String> {
    let v: serde_json::Value = serde_json::from_str(text).map_err(|e| format!("build-config.json: {e}"))?;
    let p = &v["photon-build-param"];
    let s = |k: &str| p[k].as_str().map(str::to_string).ok_or_else(|| format!("build-config.json has no photon-build-param.{k}"));
    Ok((s("photon-subrelease")?, s("photon-mainline")?, s("photon-dist-tag")?))
}

/// The expanded spec at the mainline for `arch`, by `rpmspec -P` in `dir`.
fn expand(dir: &Path, spec: &str, sub: &str, dist: &str, arch: &str, log: &mut dyn FnMut(&str)) -> Result<String, String> {
    let args: Vec<std::ffi::OsString> = vec![
        "-P".into(),
        "--target".into(),
        arch.into(),
        "-D".into(),
        format!("_sourcedir {}", dir.display()).into(),
        "-D".into(),
        format!("photon_subrelease {sub}").into(),
        "-D".into(),
        format!("dist {dist}").into(),
        "-D".into(),
        "with_check 0".into(),
        spec.into(),
    ];
    let o = crate::builder::tool_command("rpmspec", dir, &args, log)?.output().map_err(|e| format!("rpmspec: {e}"))?;
    if !o.status.success() {
        let err = String::from_utf8_lossy(&o.stderr);
        return Err(format!("rpmspec -P {arch} at subrelease {sub}: {}", err.lines().find(|l| l.contains("error")).unwrap_or(err.trim())));
    }
    Ok(String::from_utf8_lossy(&o.stdout).into_owned())
}

/// The tarball of a release as the profile pins it: the cached copy when its
/// sha512 is the pin, else verified again (and so downloaded) from scratch.
fn pinned_tarball(r: &SystemdRelease, p: &Profile, log: &mut dyn FnMut(&str)) -> Result<PathBuf, String> {
    let cache = default_cache()?;
    let cached = cache.join(r.tarball());
    if cached.exists() && crate::sha512::file(&cached)? == p.source.sha512 {
        return Ok(cached);
    }
    log(&format!("verifying {} from scratch", r.tag()));
    let v = verify(r, None, &cache, &trust()?)?;
    if v.sha512 != p.source.sha512 || v.commit != p.source.commit {
        return Err(format!(
            "{} now verifies as sha512 {} commit {}, the profile pins {} {}",
            r.tag(),
            &v.sha512[..16],
            &v.commit[..12],
            &p.source.sha512[..16],
            &p.source.commit[..12]
        ));
    }
    Ok(v.tarball)
}

/// What the port branch is now, against the release's own tarball: every
/// patch the expanded spec applies, and every meson option it passes that
/// the release does not declare. Lines for the operator; the outcomes for
/// the caller.
fn port_report(
    cfg: &crate::config::Config,
    r: &SystemdRelease,
    tarball: &Path,
    branch: &str,
    log: &mut dyn FnMut(&str),
) -> Result<(Vec<(String, Applies)>, Vec<String>, String), String> {
    let d = scratch(cfg, &format!("port-{}", r.version()))?;
    let res = (|| {
        let tree = d.join("tree");
        std::fs::create_dir_all(&tree).map_err(|e| format!("{e}"))?;
        let arch = Command::new("sh")
            .arg("-c")
            .arg("git -C \"$1\" archive \"$2\" SPECS/systemd build-config.json | tar -x -C \"$3\"")
            .arg("sh")
            .arg(&cfg.gate_repo)
            .arg(format!("refs/heads/{branch}"))
            .arg(&tree)
            .status()
            .map_err(|e| format!("git archive: {e}"))?;
        if !arch.success() {
            return Err(format!("{branch} has no SPECS/systemd or build-config.json"));
        }
        let (_, mainline, dist) = build_params(&std::fs::read_to_string(tree.join("build-config.json")).map_err(|e| format!("{e}"))?)?;
        let spec_dir = tree.join("SPECS/systemd");
        let expanded = expand(&spec_dir, "systemd.spec", &mainline, &dist, "x86_64", log)?;
        let src = d.join("src");
        std::fs::create_dir_all(&src).map_err(|e| format!("{e}"))?;
        let ok = Command::new("tar").arg("-xzf").arg(tarball).arg("-C").arg(&src).status().map_err(|e| format!("tar: {e}"))?;
        if !ok.success() {
            return Err(format!("extracting {}", tarball.display()));
        }
        let top = src.join(r.top_dir());
        let replayed = replay(&top, &spec_dir, &patches_in_order(&expanded));
        let unknown = unknown_meson_options(&top, &expanded)?;
        Ok((replayed, unknown, expanded))
    })();
    let _ = std::fs::remove_dir_all(&d);
    res
}

/// `sharukhan systemd profile-new <release>`: verify the release, write its
/// profile, start `experimental/systemd-<release>` in the gate repository
/// from the release branch with the version bump, and report what the port
/// still has to do.
pub fn profile_new(
    cfg: &crate::config::Config,
    release: &str,
    out_dir: &Path,
    force: bool,
    tarball: Option<&Path>,
    log: &mut dyn FnMut(&str),
) -> Result<bool, String> {
    let r = SystemdRelease::parse(release)?;
    let trust = trust()?;
    let out = out_dir.join(r.profile_file());
    if out.exists() && !force {
        return Err(format!("{} exists; pass --force to replace it", out.display()));
    }
    let v = verify(&r, tarball, &default_cache()?, &trust)?;
    log(&format!(
        "{}: tarball sha512 {}..., tag signed by {} ({}), content is git archive of {}",
        r.tag(),
        &v.sha512[..16],
        trust.signer(&v.signer).map(|s| s.name.as_str()).unwrap_or("?"),
        v.signer,
        v.commit
    ));
    let p = Profile {
        schema: 1,
        systemd: r.version(),
        branch: r.branch(),
        rpm_release: 1,
        source: Source {
            url: r.url(),
            sha512: v.sha512.clone(),
            commit: v.commit.clone(),
            verified: Verified { method: METHOD.into(), signer: v.signer.clone(), on: today("+%Y-%m-%d")? },
        },
    };
    Profile::parse(&p.to_json(), &out.display().to_string(), &trust)?;
    std::fs::create_dir_all(out_dir).map_err(|e| format!("{}: {e}", out_dir.display()))?;
    std::fs::write(&out, p.to_json()).map_err(|e| format!("{}: {e}", out.display()))?;
    log(&format!("wrote {}", out.display()));

    let gate = &cfg.gate_repo;
    let bref = format!("refs/heads/{}", r.branch());
    if git_in(gate, &["rev-parse", "--verify", "--quiet", &bref]).is_ok() {
        log(&format!("{} exists in {}: left as it is", r.branch(), gate.display()));
    } else {
        let base = git_in(gate, &["rev-parse", &format!("refs/heads/{}", cfg.release)])?.trim().to_string();
        let wt = scratch(cfg, &format!("start-{}", r.version()))?;
        let _ = std::fs::remove_dir(&wt);
        git_in(gate, &["worktree", "add", "--quiet", "--detach", &wt.to_string_lossy(), &base])?;
        let res = (|| {
            let spec = wt.join("SPECS/systemd/systemd.spec");
            let yaml = wt.join("SPECS/systemd/config.yaml");
            let author = crate::author::resolve(Some(gate))?;
            let text = std::fs::read_to_string(&spec).map_err(|e| format!("{}: {e}", spec.display()))?;
            let was = spec_field(&text, "Version").unwrap_or_default();
            std::fs::write(&spec, bump_spec(&text, &r.version(), 1, &today("+%a %b %d %Y")?, &author.line())?).map_err(|e| format!("{e}"))?;
            let y = std::fs::read_to_string(&yaml).map_err(|e| format!("{}: {e}", yaml.display()))?;
            std::fs::write(&yaml, set_source(&y, &r, &v.sha512, &v.commit)?).map_err(|e| format!("{e}"))?;
            git_in(&wt, &["add", "SPECS/systemd/systemd.spec", "SPECS/systemd/config.yaml"])?;
            git_in(
                &wt,
                &[
                    "-c",
                    &format!("user.name={}", author.name),
                    "-c",
                    &format!("user.email={}", author.email),
                    "commit",
                    "--quiet",
                    "-m",
                    &format!("systemd: start the port from {was} to {}", r.version()),
                ],
            )?;
            let head = git_in(&wt, &["rev-parse", "HEAD"])?.trim().to_string();
            git_in(gate, &["update-ref", &bref, &head])?;
            log(&format!("started {} at {} on {} {}", r.branch(), &head[..12], cfg.release, &base[..12]));
            Ok::<(), String>(())
        })();
        let _ = git_in(gate, &["worktree", "remove", "--force", &wt.to_string_lossy()]);
        res?;
    }
    let (replayed, unknown, _) = port_report(cfg, &r, &v.tarball, &r.branch(), log)?;
    let mut todo = 0;
    for (patch, a) in &replayed {
        match a {
            Applies::Yes => log(&format!("  applies:          {patch}")),
            Applies::AlreadyUpstream => {
                todo += 1;
                log(&format!("  already upstream: {patch} - drop it from the spec"))
            }
            Applies::No(why) => {
                todo += 1;
                log(&format!("  does not apply:   {patch} - port it ({why})"))
            }
        }
    }
    for o in &unknown {
        todo += 1;
        log(&format!("  meson option -D{o}: {} does not declare it - drop or rename it", r.tag()));
    }
    log(&format!(
        "{todo} item(s) for the port on {}; the files lists and new units are proven by the build. Then: sharukhan systemd check {}",
        r.branch(),
        r.version()
    ));
    Ok(todo == 0)
}

/// `sharukhan systemd check <release>`, and the gate before every
/// `--systemd` build: the branch carries exactly what the profile pins, is a
/// mainline tree, its spec parses on both architectures and passes the spec
/// checker, every patch applies to the verified tarball and every meson
/// option is one the release declares. Returns the lines that prove it;
/// any failure refuses, with every failure named.
pub fn check(cfg: &crate::config::Config, release: &str, log: &mut dyn FnMut(&str)) -> Result<Vec<String>, String> {
    let (p, r, source) = load(release)?;
    let mut ok = vec![format!("profile {source}")];
    let mut bad = Vec::new();
    let gate = &cfg.gate_repo;
    // under a --systemd configuration the release is the port branch itself
    let base = cfg.systemd.as_ref().map(|s| s.base_release.clone()).unwrap_or_else(|| cfg.release.clone());
    let bref = format!("refs/heads/{}", p.branch);
    let head = git_in(gate, &["rev-parse", "--verify", &bref]).map_err(|_| format!("{} is not in {}: start it with `sharukhan systemd profile-new {}`", p.branch, gate.display(), r.version()))?;
    ok.push(format!("{} at {}", p.branch, &head.trim()[..12]));
    match git_in(gate, &["merge-base", "--is-ancestor", &format!("refs/heads/{base}"), &bref]) {
        Ok(_) => ok.push(format!("contains the head of {base}")),
        Err(_) => {
            let behind = git_in(gate, &["rev-list", "--count", &format!("{bref}..refs/heads/{base}")]).unwrap_or_default();
            log(&format!("warning: {} is {} commit(s) behind {base}: rebase the port to test today's tree", p.branch, behind.trim()));
        }
    }
    let show = |path: &str| git_in(gate, &["show", &format!("{bref}:{path}")]);
    let (sub, mainline, dist) = build_params(&show("build-config.json")?)?;
    if sub == mainline {
        ok.push(format!("mainline tree (subrelease {sub})"));
    } else {
        bad.push(format!("build-config.json pins subrelease {sub}, the mainline is {mainline}: --systemd builds the mainline only"));
    }
    let yaml = show("SPECS/systemd/config.yaml")?;
    let want = [
        format!("- archive: {}", r.tarball()),
        format!("archive_sha512sum: {}", p.source.sha512),
        format!("url: {}", p.source.url),
        format!("commit_id: {}", p.source.commit),
    ];
    let missing: Vec<&String> = want.iter().filter(|w| !yaml.lines().any(|l| l.trim() == w.trim())).collect();
    if missing.is_empty() {
        ok.push("config.yaml pins the profile's tarball, sha512, url and commit".into());
    } else {
        bad.push(format!("config.yaml lacks: {}", missing.iter().map(|s| s.as_str()).collect::<Vec<_>>().join("; ")));
    }
    let tarball = pinned_tarball(&r, &p, log)?;
    ok.push(format!("tarball {} has the pinned sha512", tarball.display()));
    match port_report(cfg, &r, &tarball, &p.branch, log) {
        Err(e) => bad.push(e),
        Ok((replayed, unknown, expanded)) => {
            let v = spec_field(&expanded, "Version").unwrap_or_default();
            let rel = spec_field(&expanded, "Release").unwrap_or_default();
            let want_rel = format!("{}{dist}", p.rpm_release);
            if v == r.version() && rel == want_rel {
                ok.push(format!("spec is systemd {v}-{rel}"));
            } else {
                bad.push(format!("spec is {v}-{rel}, the profile says {}-{want_rel}", r.version()));
            }
            for (patch, a) in &replayed {
                match a {
                    Applies::Yes => {}
                    Applies::AlreadyUpstream => bad.push(format!("{patch} is already in {}: drop it", r.tag())),
                    Applies::No(why) => bad.push(format!("{patch} does not apply at fuzz 0: {why}")),
                }
            }
            if replayed.iter().all(|(_, a)| *a == Applies::Yes) {
                ok.push(format!("all {} patch(es) apply in order at fuzz 0", replayed.len()));
            }
            if unknown.is_empty() {
                ok.push(format!("every meson option is declared by {}", r.tag()));
            } else {
                bad.push(format!("meson options {} declares nowhere: {}", r.tag(), unknown.join(", ")));
            }
        }
    }
    // the other architecture parses too, and the spec checker passes
    let d = scratch(cfg, &format!("check-{}", r.version()))?;
    let res = (|| {
        let st = Command::new("sh")
            .arg("-c")
            .arg("git -C \"$1\" archive \"$2\" SPECS/systemd | tar -x -C \"$3\"")
            .arg("sh")
            .arg(gate)
            .arg(&bref)
            .arg(&d)
            .status()
            .map_err(|e| format!("git archive: {e}"))?;
        if !st.success() {
            return Err("archiving SPECS/systemd".to_string());
        }
        let spec_dir = d.join("SPECS/systemd");
        match expand(&spec_dir, "systemd.spec", &mainline, &dist, "aarch64", log) {
            Ok(_) => ok.push("spec parses on aarch64 too".into()),
            Err(e) => bad.push(e),
        }
        let common = cfg.build_root.join(&cfg.build_common);
        let checker = common.join("support/spec-checker/check_spec.py");
        let mut args = crate::specdata::checker_argv(&checker);
        args.extend(["--mainline".into(), mainline.clone().into(), "--subrelease".into(), mainline.clone().into(), spec_dir.join("systemd.spec").into()]);
        let o = crate::builder::python_command(&common, &args, log)?.output().map_err(|e| format!("check_spec: {e}"))?;
        if o.status.success() {
            ok.push(format!("check_spec.py --mainline {mainline} passes"));
        } else {
            let all = format!("{}{}", String::from_utf8_lossy(&o.stdout), String::from_utf8_lossy(&o.stderr));
            bad.push(format!("check_spec.py: {}", all.lines().filter(|l| l.contains("ERROR") || l.contains("Error")).take(3).collect::<Vec<_>>().join(" | ")));
        }
        Ok(())
    })();
    let _ = std::fs::remove_dir_all(&d);
    res?;
    if bad.is_empty() {
        Ok(ok)
    } else {
        Err(format!("the port of systemd {} is not ready ({} problem(s)): {}", r.version(), bad.len(), bad.join("; ")))
    }
}

// ------------------------------------------------------ the build axis ---

/// The configuration a `--systemd` build runs under: its own build root,
/// whose release tree is the port branch, its own ISO cache and variant
/// patches. Nothing else changes.
pub fn effective_cfg(cfg: &crate::config::Config, p: &Profile, r: &SystemdRelease, profile_text: &str) -> Result<crate::config::Config, String> {
    if cfg.systemd.as_ref().is_some_and(|s| s.name == r.version()) {
        return Ok(cfg.clone());
    }
    let dist = crate::specresolve::dist_tag_of(&cfg.photon_tree).ok_or_else(|| format!("{}: no photon-dist-tag in build-config.json", cfg.photon_tree.display()))?;
    let mut s = cfg.clone();
    s.systemd = Some(crate::config::SystemdAxis {
        name: r.version(),
        nevr: p.nevr(&dist),
        profile_sha256: crate::sha256::bytes(profile_text.as_bytes()),
        base_release: cfg.release.clone(),
        gate_stage: cfg.photon_tree.join("stage"),
    });
    let root = cfg.work.join("sbuild").join(r.version());
    s.build_root = root.clone();
    s.release = p.branch.clone();
    s.photon_tree = root.join(&p.branch);
    s.variant_patches = cfg.variant_patches.join(r.key());
    s.iso_cache = cfg.iso_cache.join(r.key());
    Ok(s)
}

/// `--systemd <release>` on a test command (plan, run, install, verify ...):
/// the rows run against that profile's media, and the guest is verified to
/// run that systemd.
pub fn apply(cfg: &crate::config::Config, release: &str) -> Result<crate::config::Config, String> {
    let (p, r, _) = load(release)?;
    let (_, text) = data_file(&r.profile_file())?;
    effective_cfg(cfg, &p, &r, &text)
}

/// The profile of a `--systemd` request with the configuration it builds
/// under; refused together with `--kernel` (each builds its own release
/// tree) and for a tree that pins a subrelease (the port is the mainline's).
pub fn context(cfg: &crate::config::Config, release: &str, kernel: Option<&str>) -> Result<(crate::config::Config, Profile, String), String> {
    if let Some(k) = kernel {
        return Err(format!("--systemd {release} with --kernel {k}: each builds in a release tree of its own; build them separately"));
    }
    let (p, r, source) = load(release)?;
    let (_, text) = data_file(&r.profile_file())?;
    let sc = effective_cfg(cfg, &p, &r, &text)?;
    Ok((sc, p, source))
}

const USAGE: &str = "usage:
  sharukhan systemd verify <release> [--tarball <file>]
      verify a systemd release: the GitHub tarball, the tag's signature by a
      reviewed signer, and the tarball identical to git archive of the tag
  sharukhan systemd profile-new <release> [--out <dir>] [--force] [--tarball <file>]
      verify it, write profiles/systemd/<release>.json, start the port branch
      experimental/systemd-<release> in the gate repository and report what
      the port still has to do
  sharukhan systemd check <release>
      the gate before every --systemd build: the branch against the profile,
      the spec on both architectures, the spec checker, every patch at fuzz 0
      and every meson option

<release> is a systemd/systemd release tag: 262.2 or v262.2.";

pub fn cli(args: &[String]) -> u8 {
    let cfg = crate::config::Config::load();
    let mut log = |l: &str| println!("{l}");
    let (mut out, mut force, mut tarball, mut pos) = (None, false, None, Vec::new());
    let mut it = args.iter().skip(1);
    while let Some(a) = it.next() {
        match a.as_str() {
            "--out" => out = it.next().map(PathBuf::from),
            "--tarball" => tarball = it.next().map(PathBuf::from),
            "--force" => force = true,
            "-h" | "--help" => {
                println!("{USAGE}");
                return 0;
            }
            s if s.starts_with('-') => {
                eprintln!("sharukhan systemd: unknown option {s}\n{USAGE}");
                return 64;
            }
            s => pos.push(s.to_string()),
        }
    }
    let Some(release) = pos.first() else {
        eprintln!("{USAGE}");
        return 64;
    };
    let res: Result<u8, String> = match args.first().map(String::as_str) {
        Some("verify") => SystemdRelease::parse(release).and_then(|r| {
            let v = verify(&r, tarball.as_deref(), &default_cache()?, &trust()?)?;
            println!("{} verified: {} ({} entries)\n  sha512 {}\n  commit {}\n  signer {}", r.tag(), v.tarball.display(), v.entries, v.sha512, v.commit, v.signer);
            Ok(0)
        }),
        Some("profile-new") => {
            let dir = out
                .or_else(|| std::env::var_os("SHARUKHAN_SYSTEMD_PROFILES").filter(|d| !d.is_empty()).map(PathBuf::from))
                .unwrap_or_else(|| PathBuf::from("profiles/systemd"));
            profile_new(&cfg, release, &dir, force, tarball.as_deref(), &mut log).map(|ready| if ready { 0 } else { 10 })
        }
        Some("check") => check(&cfg, release, &mut log).map(|lines| {
            for l in lines {
                println!("  ok  {l}");
            }
            0
        }),
        _ => {
            eprintln!("{USAGE}");
            return 64;
        }
    };
    match res {
        Ok(rc) => rc,
        Err(e) => {
            eprintln!("sharukhan systemd: {e}");
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_version_bump_sets_version_release_and_one_changelog_entry() {
        let spec = "Name:           systemd\nVersion:        257.13\nRelease:        6%{?dist}\nSummary: x\n%description\nx\n%changelog\n* Sat Oct 31 2026 A <a@b.c> 257.13-6\n- y\n";
        let out = bump_spec(spec, "262.2", 1, "Thu Nov 05 2026", "D <d@e.f>").unwrap();
        assert!(out.contains("\nVersion:        262.2\n"), "{out}");
        assert!(out.contains("\nRelease:        1%{?dist}\n"), "{out}");
        assert!(out.contains("%changelog\n* Thu Nov 05 2026 D <d@e.f> 262.2-1\n- Update to systemd 262.2\n* Sat Oct 31 2026"), "{out}");
        assert_eq!(spec_field(&out, "Version").as_deref(), Some("262.2"));
        assert!(bump_spec("Name: x\nRelease: 1\n%changelog\n", "262.2", 1, "d", "a").unwrap_err().contains("Version:"));
    }

    #[test]
    fn the_source_entry_follows_the_verified_release() {
        let yaml = "sources:\n- archive: systemd-257.13.tar.gz\n  archive_type: upstream\n  archive_sha512sum: f627\n  name: systemd-257.13\n  version: 257.13\n  url: https://github.com/systemd/systemd/archive/refs/tags/v257.13.tar.gz\n  repo_url: https://github.com/systemd/systemd\n  commit_id: 70b5d110\n  skip_list: []\nspdx:\n  package:\n    name: systemd\n    version: 257.13\n";
        let r = SystemdRelease::parse("262.2").unwrap();
        let out = set_source(yaml, &r, &"b".repeat(128), "63511d7283d7d0e2a2fc28075481afaf1a7be8f5").unwrap();
        for want in [
            "- archive: systemd-262.2.tar.gz\n",
            &format!("  archive_sha512sum: {}\n", "b".repeat(128)),
            "  name: systemd-262.2\n",
            "  version: 262.2\n",
            "  url: https://github.com/systemd/systemd/archive/refs/tags/v262.2.tar.gz\n",
            "  commit_id: 63511d7283d7d0e2a2fc28075481afaf1a7be8f5\n",
            "  repo_url: https://github.com/systemd/systemd\n",
        ] {
            assert!(out.contains(want), "{want}\n{out}");
        }
        assert!(out.contains("spdx:\n  package:\n    name: systemd\n    version: 257.13\n"), "only the source entry is edited: {out}");
        assert!(set_source("sources:\n- archive: other-1.tar.gz\n", &r, "x", "y").unwrap_err().contains("0 systemd"));
        assert!(set_source(&yaml.replace("  commit_id: 70b5d110\n", ""), &r, "x", "y").unwrap_err().contains("commit_id"));
    }

    #[test]
    fn patches_are_applied_in_number_order_and_unnumbered_ones_take_the_next() {
        let spec = "Patch2: c.patch\nPatch0: a.patch\nPatch1: b.patch\nPatch:  d.patch\nPatchX: no\nSource0: s\n";
        assert_eq!(patches_in_order(spec), vec!["a.patch", "b.patch", "c.patch", "d.patch"]);
    }

    #[test]
    fn the_replay_tells_applied_already_upstream_and_rejected_apart() {
        let d = std::env::temp_dir().join(format!("shk-sdreplay-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        let (src, pd) = (d.join("src"), d.join("spec"));
        std::fs::create_dir_all(&src).unwrap();
        std::fs::create_dir_all(&pd).unwrap();
        std::fs::write(src.join("f"), "one\ntwo\nthree\n").unwrap();
        std::fs::write(pd.join("ok.patch"), "--- a/f\n+++ b/f\n@@ -1,3 +1,3 @@\n one\n-two\n+TWO\n three\n").unwrap();
        // the release already says THREE
        std::fs::write(src.join("g"), "x\nTHREE\ny\n").unwrap();
        std::fs::write(pd.join("up.patch"), "--- a/g\n+++ b/g\n@@ -1,3 +1,3 @@\n x\n-three\n+THREE\n y\n").unwrap();
        std::fs::write(pd.join("bad.patch"), "--- a/f\n+++ b/f\n@@ -1,3 +1,3 @@\n one\n-zwei\n+ZWEI\n three\n").unwrap();
        let r = replay(&src, &pd, &["ok.patch".into(), "up.patch".into(), "bad.patch".into()]);
        assert_eq!(r[0], ("ok.patch".into(), Applies::Yes));
        assert_eq!(r[1], ("up.patch".into(), Applies::AlreadyUpstream));
        assert!(matches!(&r[2].1, Applies::No(_)), "{r:?}");
        assert_eq!(std::fs::read_to_string(src.join("f")).unwrap(), "one\nTWO\nthree\n", "the applied patch stays applied");
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn meson_options_the_release_does_not_declare_are_named() {
        let d = std::env::temp_dir().join(format!("shk-sdmeson-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        std::fs::write(d.join("meson_options.txt"), "option('homed', type : 'feature')\noption(\"oomd\", type : 'boolean')\noption('kernel-install', type : 'boolean')\n").unwrap();
        let spec = "CONFIGURE_OPTS=(\n -Dhomed=disabled\n -Doomd=false\n -Dkernel-install=false\n -Dsplit-usr=false\n -Db_lto=true\n -Dc_args=-O2\n --prefix=/usr\n -Dlibdir=/usr/lib\n)\n";
        assert_eq!(unknown_meson_options(&d, spec).unwrap(), vec!["split-usr"]);
        std::fs::remove_file(d.join("meson_options.txt")).unwrap();
        assert!(unknown_meson_options(&d, spec).is_err(), "no option file is an error, not an empty answer");
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn a_systemd_build_runs_in_a_root_cache_and_variant_patches_of_its_own() {
        let d = std::env::temp_dir().join(format!("shk-sdcfg-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        std::fs::write(d.join("build-config.json"), r#"{"photon-build-param": {"photon-dist-tag": ".ph5"}}"#).unwrap();
        let mut cfg = crate::config::Config::for_test(&d);
        cfg.work = d.join("work");
        cfg.release = "5.0".into();
        let (p, r) = Profile::parse(&profile_text(), "262.2.json", &trust()).unwrap();
        let s = effective_cfg(&cfg, &p, &r, &profile_text()).unwrap();
        assert_eq!(s.build_root, d.join("work/sbuild/262.2"));
        assert_eq!(s.release, "experimental/systemd-262.2");
        assert_eq!(s.photon_tree, d.join("work/sbuild/262.2/experimental/systemd-262.2"));
        assert_eq!(s.iso_cache, cfg.iso_cache.join("s262.2"));
        assert_eq!(s.variant_patches, cfg.variant_patches.join("s262.2"));
        let axis = s.systemd.clone().unwrap();
        assert_eq!((axis.name.as_str(), axis.nevr.as_str(), axis.base_release.as_str()), ("262.2", "262.2-1.ph5", "5.0"));
        assert_eq!(axis.profile_sha256, crate::sha256::bytes(profile_text().as_bytes()));
        // the port's stage is seeded from the gate's, never from its own
        assert_eq!(axis.gate_stage, cfg.photon_tree.join("stage"));
        assert_ne!(axis.gate_stage, s.photon_tree.join("stage"));
        // applied twice, the paths are derived once, never nested
        assert_eq!(effective_cfg(&s, &p, &r, &profile_text()).unwrap().build_root, s.build_root);
        match context(&cfg, "262.2", Some("7.3")) {
            Err(e) => assert!(e.contains("--kernel 7.3"), "{e}"),
            Ok(_) => panic!("--systemd with --kernel must be refused"),
        }
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn a_release_string_yields_every_name() {
        let r = SystemdRelease::parse("v262.2").unwrap();
        assert_eq!(r, SystemdRelease::parse("262.2").unwrap());
        assert_eq!(r.version(), "262.2");
        assert_eq!(r.tag(), "v262.2");
        assert_eq!(r.top_dir(), "systemd-262.2");
        assert_eq!(r.tarball(), "systemd-262.2.tar.gz");
        assert_eq!(r.url(), "https://github.com/systemd/systemd/archive/refs/tags/v262.2.tar.gz");
        assert_eq!(r.branch(), "experimental/systemd-262.2");
        assert_eq!(r.key(), "s262.2");
        assert_eq!(SystemdRelease::parse("262").unwrap().version(), "262");
    }

    #[test]
    fn anything_outside_the_grammar_is_refused_with_the_reason() {
        for (bad, why) in [
            ("262-rc3", "release candidates"),
            ("v262-rc1", "release candidates"),
            ("262.02", "leading zero"),
            ("0262", "leading zero"),
            ("262.0", "1..="),
            ("262.2.1", "<major>"),
            (" 262", "digits only"),
            ("262.", "digits only"),
            ("vv262", "digits only"),
            ("", "digits only"),
            ("99999", "1..="),
        ] {
            let e = SystemdRelease::parse(bad).unwrap_err();
            assert!(e.contains(why), "{bad}: {e}");
        }
    }

    fn trust() -> Trust {
        Trust::parse(crate::wrapper::embedded::systemd_file(SIGNERS_FILE).unwrap(), "signers", &HOSTS, "systemd").unwrap()
    }

    fn profile_text() -> String {
        Profile {
            schema: 1,
            systemd: "262.2".into(),
            branch: "experimental/systemd-262.2".into(),
            rpm_release: 1,
            source: Source {
                url: "https://github.com/systemd/systemd/archive/refs/tags/v262.2.tar.gz".into(),
                sha512: "a".repeat(128),
                commit: "63511d7283d7d0e2a2fc28075481afaf1a7be8f5".into(),
                verified: Verified { method: METHOD.into(), signer: "A9EA9081724FFAE0484C35A1A81CEA22BC8C7E2E".into(), on: "2026-11-05".into() },
            },
        }
        .to_json()
    }

    #[test]
    fn a_profile_round_trips_and_each_wrong_field_is_named() {
        let t = trust();
        let (p, r) = Profile::parse(&profile_text(), "262.2.json", &t).unwrap();
        assert_eq!(r.version(), "262.2");
        assert_eq!(p.nevr(".ph5"), "262.2-1.ph5");
        assert_eq!(Profile::parse(&p.to_json(), "262.2.json", &t).unwrap().0, p);
        for (from, to, field) in [
            ("\"systemd\": \"262.2\"", "\"systemd\": \"v262.2\"", "systemd"),
            ("experimental/systemd-262.2", "experimental/systemd-262.1", "branch"),
            ("\"rpm_release\": 1", "\"rpm_release\": 0", "rpm_release"),
            ("refs/tags/v262.2", "refs/tags/v262.1", "source.url"),
            ("aaaa", "AAAA", "source.sha512"),
            ("63511d7283", "63511D7283", "source.commit"),
            (METHOD, "tarball-only", "source.verified.method"),
            ("A9EA9081724FFAE0484C35A1A81CEA22BC8C7E2E", "0000000000000000000000000000000000000000", "source.verified.signer"),
            ("2026-11-05", "05.11.2026", "source.verified.on"),
            ("\"schema\": 1", "\"schema\": 2", "schema"),
        ] {
            let text = profile_text().replacen(from, to, 1);
            assert_ne!(text, profile_text(), "{from}");
            let e = Profile::parse(&text, "262.2.json", &t).unwrap_err();
            assert!(e.contains(field), "{field}: {e}");
        }
        assert!(Profile::parse(&profile_text(), "262.1.json", &t).unwrap_err().contains("file name"));
        assert!(Profile::parse(&profile_text().replace("\"schema\": 1,", "\"schema\": 1, \"extra\": 1,"), "262.2.json", &t).is_err());
    }

    #[test]
    fn the_built_in_signers_are_valid_and_fetch_from_the_allowed_hosts_only() {
        let t = trust();
        assert!(t.signer("A9EA9081724FFAE0484C35A1A81CEA22BC8C7E2E").is_some());
        assert!(kernelorg::check_url_in("https://cdn.kernel.org/x", &HOSTS).is_err());
        assert!(kernelorg::check_url_in(&SystemdRelease::parse("262.2").unwrap().url(), &HOSTS).is_ok());
    }
}
