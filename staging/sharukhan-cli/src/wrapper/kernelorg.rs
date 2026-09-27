//! kernel.org: which releases exist, and whether a tarball is what kernel.org
//! released.
//!
//! Nothing downloaded is trusted on arrival:
//!
//! * `releases.json` only names releases; each listed URL is compared with
//!   the one computed from the release's identity, so a layout change on
//!   kernel.org stops derivation instead of silently pointing elsewhere.
//! * Signer keys are fetched from kernel.org's pgpkeys repository, but a key
//!   is imported only when its primary fingerprint is one of the reviewed
//!   fingerprints in the trust file, into a keyring private to this run.
//! * cdn.kernel.org tarballs are verified with their `.tar.sign`, which signs
//!   the decompressed tar. git.kernel.org snapshots (release candidates) have
//!   no signature of their own: the tag they are cut from is fetched and its
//!   signature verified, and the decompressed snapshot must be byte-identical
//!   to `git archive` of the commit that tag names.
//! * Every tar entry must lie under `linux-<release>/`, so a correctly signed
//!   tarball of another release cannot stand in for this one.
//!
//! External programs (curl, gpg, xz, gzip, git) run with argument vectors,
//! never through a shell, and only https URLs on kernel.org hosts are fetched.

use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use serde::Deserialize;

use super::error::{io, Result, WrapperError};
use super::identity::{KernelRelease, Kind};
use super::profile::{is_commit, is_fingerprint};
use crate::sha512::Sha512;

pub const RELEASES_URL: &str = "https://www.kernel.org/releases.json";
pub const TORVALDS_GIT: &str = "https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git";
const HOSTS: [&str; 3] = ["www.kernel.org", "cdn.kernel.org", "git.kernel.org"];

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

/// Only `https://<kernel.org host>/<path>` with a plain path is fetched.
pub fn check_url(url: &str) -> Result<()> {
    let bad = |why: &str| {
        verify_err(
            format!("URL {url:?}"),
            "https://{www,cdn,git}.kernel.org/...",
            why,
        )
    };
    let rest = url
        .strip_prefix("https://")
        .ok_or_else(|| bad("not https"))?;
    let (host, path) = rest.split_once('/').ok_or_else(|| bad("no path"))?;
    if !HOSTS.contains(&host) {
        return Err(bad("host is not a kernel.org host"));
    }
    let ok = path
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || b"-._~/+".contains(&b));
    if path.is_empty() || !ok || path.contains("..") {
        return Err(bad("path has characters outside [A-Za-z0-9-._~/+] or '..'"));
    }
    Ok(())
}

fn tool(name: &str) -> Command {
    let mut c = Command::new(name);
    c.env("LC_ALL", "C");
    c
}

fn run(mut c: Command, what: &str) -> Result<Vec<u8>> {
    let out = c
        .stdin(Stdio::null())
        .output()
        .map_err(|e| io(format!("running {what}"), e))?;
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        return Err(io(
            what.to_string(),
            format!(
                "exit {}: {}",
                out.status.code().unwrap_or(-1),
                err.lines().rev().take(3).collect::<Vec<_>>().join(" / ")
            ),
        ));
    }
    Ok(out.stdout)
}

/// Download `url` to `dest` through a temporary file in the same directory.
pub fn fetch(url: &str, dest: &Path) -> Result<()> {
    check_url(url)?;
    let tmp = dest.with_extension(format!("part.{}", std::process::id()));
    let mut c = tool("curl");
    c.args([
        "--proto",
        "=https",
        "--proto-redir",
        "=https",
        "--tlsv1.2",
        "--fail",
        "--silent",
        "--show-error",
        "--location",
        "--max-redirs",
        "3",
        "--retry",
        "2",
        "--connect-timeout",
        "30",
        "--max-time",
        "3600",
        "--output",
    ])
    .arg(&tmp)
    .arg("--")
    .arg(url);
    if let Err(e) = run(c, &format!("curl {url}")) {
        let _ = std::fs::remove_file(&tmp);
        return Err(e);
    }
    std::fs::rename(&tmp, dest).map_err(|e| io(format!("moving {} into place", dest.display()), e))
}

// ---------------------------------------------------------------- trust ---

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Signer {
    pub name: String,
    pub fingerprint: String,
}

/// The reviewed kernel.org signers: fingerprints copied from
/// kernel.org/signature.html, and where their keys are fetched from.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Trust {
    pub schema: u32,
    pub source: String,
    pub reviewed: String,
    pub keys_from: String,
    pub signers: Vec<Signer>,
}

impl Trust {
    pub fn load(path: &Path) -> Result<Trust> {
        let text = std::fs::read_to_string(path).map_err(|e| io(path.display().to_string(), e))?;
        let t: Trust = serde_json::from_str(&text).map_err(|e| {
            io(
                path.display().to_string(),
                format!("not a valid trust file: {e}"),
            )
        })?;
        t.validate()
            .map_err(|why| io(path.display().to_string(), why))?;
        Ok(t)
    }

    fn validate(&self) -> std::result::Result<(), String> {
        if self.schema != 1 {
            return Err(format!("schema {} is not 1", self.schema));
        }
        check_url(&self.source).map_err(|e| e.to_string())?;
        check_url(&self.keys_from).map_err(|e| e.to_string())?;
        if !self.keys_from.ends_with('/') {
            return Err("keys_from must end with '/'".into());
        }
        let r = self.reviewed.as_bytes();
        if !(r.len() == 10
            && r[4] == b'-'
            && r[7] == b'-'
            && r.iter()
                .enumerate()
                .all(|(i, b)| i == 4 || i == 7 || b.is_ascii_digit()))
        {
            return Err("reviewed must be YYYY-MM-DD".into());
        }
        if self.signers.is_empty() {
            return Err("no signers".into());
        }
        let mut seen = std::collections::BTreeSet::new();
        for s in &self.signers {
            if !is_fingerprint(&s.fingerprint) {
                return Err(format!(
                    "{}: '{}' is not a 40-digit uppercase fingerprint",
                    s.name, s.fingerprint
                ));
            }
            if s.name.trim().is_empty() || s.name.chars().any(|c| c.is_control()) {
                return Err(format!("signer {} has no usable name", s.fingerprint));
            }
            if !seen.insert(s.fingerprint.clone()) {
                return Err(format!("{} is listed twice", s.fingerprint));
            }
        }
        Ok(())
    }

    pub fn signer(&self, fpr: &str) -> Option<&Signer> {
        self.signers.iter().find(|s| s.fingerprint == fpr)
    }

    fn key_url(&self, fpr: &str) -> String {
        format!("{}{}.asc", self.keys_from, &fpr[24..])
    }
}

/// Primary-key fingerprints in `gpg --with-colons` output: the `fpr` record
/// that directly follows each `pub` record (subkey fingerprints follow `sub`).
pub fn primary_fingerprints(colons: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut after_pub = false;
    for l in colons.lines() {
        let f: Vec<&str> = l.split(':').collect();
        match f.first().copied() {
            Some("pub") => after_pub = true,
            Some("fpr") if after_pub => {
                if let Some(x) = f.get(9) {
                    out.push(x.to_string());
                }
                after_pub = false;
            }
            _ => {}
        }
    }
    out
}

/// Judge `gpg --status-fd` output: exactly one good, valid signature whose
/// primary key is a trusted signer, and no bad, expired or revoked one.
pub fn judge_status(status: &str, trust: &Trust) -> Result<String> {
    const REFUSE: [&str; 7] = [
        "BADSIG",
        "ERRSIG",
        "EXPSIG",
        "EXPKEYSIG",
        "REVKEYSIG",
        "NO_PUBKEY",
        "FAILURE",
    ];
    let mut valid = Vec::new();
    let mut good = 0;
    for l in status.lines() {
        let Some(rest) = l.strip_prefix("[GNUPG:] ") else {
            continue;
        };
        let f: Vec<&str> = rest.split(' ').collect();
        if REFUSE.contains(&f[0]) {
            return Err(verify_err(
                "signature",
                "a good signature",
                rest.to_string(),
            ));
        }
        match f[0] {
            "GOODSIG" => good += 1,
            "VALIDSIG" => valid.push(f.get(10).copied().unwrap_or("").to_string()),
            _ => {}
        }
    }
    let [primary] = valid.as_slice() else {
        return Err(verify_err(
            "signature",
            "exactly one VALIDSIG",
            format!("{} VALIDSIG, {good} GOODSIG", valid.len()),
        ));
    };
    if good != 1 {
        return Err(verify_err(
            "signature",
            "exactly one GOODSIG",
            format!("{good}"),
        ));
    }
    if trust.signer(primary).is_none() {
        return Err(verify_err(
            "signer",
            "a reviewed kernel.org signer",
            primary.clone(),
        ));
    }
    Ok(primary.clone())
}

/// A keyring private to one verification, holding only reviewed keys.
pub struct Keyring {
    pub home: PathBuf,
}

impl Keyring {
    pub fn build(dir: &Path, trust: &Trust) -> Result<Keyring> {
        use std::os::unix::fs::PermissionsExt;
        let home = dir.join("gnupg");
        std::fs::create_dir_all(&home).map_err(|e| io(home.display().to_string(), e))?;
        std::fs::set_permissions(&home, std::fs::Permissions::from_mode(0o700))
            .map_err(|e| io(home.display().to_string(), e))?;
        let ring = Keyring { home };
        for s in &trust.signers {
            let file = dir.join(format!("{}.asc", s.fingerprint));
            fetch(&trust.key_url(&s.fingerprint), &file)?;
            let shown = ring.gpg(
                &["--with-colons", "--import-options", "show-only", "--import"],
                Some(&file),
            )?;
            let fprs = primary_fingerprints(&String::from_utf8_lossy(&shown));
            if fprs != [s.fingerprint.clone()] {
                return Err(verify_err(
                    format!("key file for {}", s.name),
                    format!("exactly the primary key {}", s.fingerprint),
                    format!("{fprs:?}"),
                ));
            }
            ring.gpg(&["--import"], Some(&file))?;
        }
        Ok(ring)
    }

    fn gpg(&self, args: &[&str], file: Option<&Path>) -> Result<Vec<u8>> {
        let mut c = tool("gpg");
        c.env("GNUPGHOME", &self.home)
            .args(["--batch", "--no-tty", "--no-auto-key-retrieve"]);
        c.args(args);
        if let Some(f) = file {
            c.arg("--").arg(f);
        }
        run(c, &format!("gpg {}", args.join(" ")))
    }
}

// ------------------------------------------------------------ tar walk ---

/// Streaming inspection of a tar: every entry's path, and the pax global
/// `comment` git writes (the commit id).
#[derive(Debug, Default)]
pub struct TarWalk {
    buf: Vec<u8>,
    skip: u64,
    pending: Option<(u8, u64, Vec<u8>)>,
    next_path: Option<String>,
    pub entries: u64,
    pub comment: Option<String>,
    pub outside: Vec<String>,
    pub zero_blocks: u32,
    prefix: String,
    pub error: Option<String>,
}

fn octal(field: &[u8]) -> Option<u64> {
    if field.first().is_some_and(|b| b & 0x80 != 0) {
        // base-256
        let mut v: u64 = (field[0] & 0x7f) as u64;
        for b in &field[1..] {
            v = v.checked_mul(256)?.checked_add(*b as u64)?;
        }
        return Some(v);
    }
    let s: String = field
        .iter()
        .take_while(|b| **b != 0)
        .map(|b| *b as char)
        .collect();
    let s = s.trim();
    if s.is_empty() {
        return Some(0);
    }
    u64::from_str_radix(s, 8).ok()
}

fn cstr(field: &[u8]) -> String {
    String::from_utf8_lossy(&field[..field.iter().position(|b| *b == 0).unwrap_or(field.len())])
        .into_owned()
}

/// pax records: "<len> <key>=<value>\n" repeated.
fn pax_records(data: &[u8]) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let mut rest = data;
    while !rest.is_empty() {
        let Some(sp) = rest.iter().position(|b| *b == b' ') else {
            break;
        };
        let Ok(len) = std::str::from_utf8(&rest[..sp])
            .unwrap_or("x")
            .parse::<usize>()
        else {
            break;
        };
        if len <= sp + 1 || len > rest.len() {
            break;
        }
        let rec = &rest[sp + 1..len];
        let rec = rec.strip_suffix(b"\n").unwrap_or(rec);
        if let Some(eq) = rec.iter().position(|b| *b == b'=') {
            out.push((
                String::from_utf8_lossy(&rec[..eq]).into_owned(),
                String::from_utf8_lossy(&rec[eq + 1..]).into_owned(),
            ));
        }
        rest = &rest[len..];
    }
    out
}

impl TarWalk {
    pub fn new(top_dir: &str) -> TarWalk {
        TarWalk {
            prefix: format!("{top_dir}/"),
            ..Default::default()
        }
    }

    pub fn update(&mut self, mut data: &[u8]) {
        while !data.is_empty() && self.error.is_none() {
            if self.skip > 0 {
                let n = (self.skip.min(data.len() as u64)) as usize;
                if let Some((_, _, body)) = &mut self.pending {
                    body.extend_from_slice(&data[..n]);
                }
                self.skip -= n as u64;
                data = &data[n..];
                if self.skip == 0 {
                    self.finish_pending();
                }
                continue;
            }
            let need = 512 - self.buf.len();
            let n = need.min(data.len());
            self.buf.extend_from_slice(&data[..n]);
            data = &data[n..];
            if self.buf.len() == 512 {
                let block = std::mem::take(&mut self.buf);
                self.header(&block);
            }
        }
    }

    fn finish_pending(&mut self) {
        if let Some((kind, size, mut body)) = self.pending.take() {
            body.truncate(size as usize);
            match kind {
                b'g' => {
                    for (k, v) in pax_records(&body) {
                        if k == "comment" {
                            self.comment = Some(v);
                        }
                    }
                }
                b'x' => {
                    for (k, v) in pax_records(&body) {
                        if k == "path" {
                            self.next_path = Some(v);
                        }
                    }
                }
                b'L' => self.next_path = Some(cstr(&body)),
                _ => {}
            }
        }
    }

    fn header(&mut self, h: &[u8]) {
        if h.iter().all(|b| *b == 0) {
            self.zero_blocks += 1;
            return;
        }
        if self.zero_blocks > 0 {
            self.error = Some("data after the end-of-archive blocks".into());
            return;
        }
        let Some(size) = octal(&h[124..136]) else {
            self.error = Some("unreadable size field".into());
            return;
        };
        let kind = h[156];
        let padded = size.div_ceil(512) * 512;
        match kind {
            b'g' | b'x' | b'L' => {
                if size > 1 << 20 {
                    self.error = Some(format!("{}-header of {size} bytes", kind as char));
                    return;
                }
                self.pending = Some((kind, size, Vec::with_capacity(size as usize)));
                self.skip = padded;
                if padded == 0 {
                    self.finish_pending();
                }
            }
            _ => {
                let path = self.next_path.take().unwrap_or_else(|| {
                    let name = cstr(&h[0..100]);
                    let prefix = if &h[257..262] == b"ustar" {
                        cstr(&h[345..500])
                    } else {
                        String::new()
                    };
                    if prefix.is_empty() {
                        name
                    } else {
                        format!("{prefix}/{name}")
                    }
                });
                self.entries += 1;
                let inside = path.starts_with(&self.prefix) && !path.split('/').any(|c| c == "..");
                if !inside && self.outside.len() < 5 {
                    self.outside.push(path);
                }
                self.skip = padded;
            }
        }
    }

    /// The archive ended properly and every entry lay under the top directory.
    pub fn check(&self, what: &str) -> Result<()> {
        if let Some(e) = &self.error {
            return Err(verify_err(what.to_string(), "a well-formed tar", e.clone()));
        }
        if self.zero_blocks < 2 || self.skip != 0 || !self.buf.is_empty() {
            return Err(verify_err(
                what.to_string(),
                "a complete tar",
                "a truncated one",
            ));
        }
        if self.entries == 0 {
            return Err(verify_err(what.to_string(), "entries", "an empty archive"));
        }
        if !self.outside.is_empty() {
            return Err(verify_err(
                what.to_string(),
                format!("every entry under {}", self.prefix),
                self.outside.join(", "),
            ));
        }
        Ok(())
    }
}

/// Run `producer`, hand every byte of its stdout to `sink`, require exit 0.
fn stream(
    mut producer: Command,
    what: &str,
    mut sink: impl FnMut(&[u8]) -> Result<()>,
) -> Result<()> {
    let mut child = producer
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| io(format!("running {what}"), e))?;
    let mut out = child
        .stdout
        .take()
        .ok_or_else(|| io(what.to_string(), "no stdout"))?;
    let mut buf = vec![0u8; 1 << 20];
    let mut sink_err = None;
    loop {
        let n = out
            .read(&mut buf)
            .map_err(|e| io(format!("reading {what}"), e))?;
        if n == 0 {
            break;
        }
        if let Err(e) = sink(&buf[..n]) {
            sink_err = Some(e);
            break;
        }
    }
    drop(out);
    let res = child
        .wait_with_output()
        .map_err(|e| io(format!("waiting for {what}"), e))?;
    if let Some(e) = sink_err {
        return Err(e);
    }
    if !res.status.success() {
        return Err(io(
            what.to_string(),
            format!(
                "exit {}: {}",
                res.status.code().unwrap_or(-1),
                String::from_utf8_lossy(&res.stderr).trim()
            ),
        ));
    }
    Ok(())
}

// --------------------------------------------------------- verification ---

#[derive(Debug, Clone, PartialEq)]
pub struct Verification {
    pub tarball: PathBuf,
    /// sha512 of the compressed tarball as downloaded: the pin.
    pub sha512: String,
    pub method: &'static str,
    pub signer: String,
    pub commit: Option<String>,
    pub entries: u64,
}

/// Decompressor for the release's tarball format.
fn decompress(target: &KernelRelease, tarball: &Path) -> Command {
    let mut c = match target.kind {
        Kind::MainlineRc { .. } => tool("gzip"),
        _ => tool("xz"),
    };
    c.args(["-dc", "--"]).arg(tarball);
    c
}

/// cdn.kernel.org: the `.tar.sign` signs the decompressed tar.
fn verify_pgp(
    target: &KernelRelease,
    tarball: &Path,
    work: &Path,
    ring: &Keyring,
    trust: &Trust,
) -> Result<(String, TarWalk)> {
    let sig_url = target
        .signature_url()
        .ok_or_else(|| verify_err("signature", "a .tar.sign URL", "none for this release"))?;
    let sig = work.join(format!("linux-{}.tar.sign", target.ksrc()));
    fetch(&sig_url, &sig)?;
    check_pgp(target, tarball, &sig, ring, trust)
}

/// Judge a detached signature over the decompressed tarball, walking the tar
/// in the same pass.
fn check_pgp(
    target: &KernelRelease,
    tarball: &Path,
    sig: &Path,
    ring: &Keyring,
    trust: &Trust,
) -> Result<(String, TarWalk)> {
    let mut gpg = tool("gpg");
    gpg.env("GNUPGHOME", &ring.home)
        .args([
            "--batch",
            "--no-tty",
            "--no-auto-key-retrieve",
            "--status-fd",
            "1",
            "--verify",
            "--",
        ])
        .arg(sig)
        .arg("-")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    let mut child = gpg.spawn().map_err(|e| io("running gpg --verify", e))?;
    let mut stdin = child.stdin.take().ok_or_else(|| io("gpg", "no stdin"))?;
    let mut walk = TarWalk::new(&format!("linux-{}", target.ksrc()));
    let fed = stream(
        decompress(target, tarball),
        "decompressing the tarball",
        |chunk| {
            walk.update(chunk);
            stdin.write_all(chunk).map_err(|e| io("feeding gpg", e))
        },
    );
    drop(stdin);
    let out = child
        .wait_with_output()
        .map_err(|e| io("waiting for gpg", e))?;
    fed?;
    let signer = judge_status(&String::from_utf8_lossy(&out.stdout), trust)?;
    if !out.status.success() {
        return Err(verify_err(
            "gpg --verify",
            "exit 0",
            format!("exit {}", out.status.code().unwrap_or(-1)),
        ));
    }
    Ok((signer, walk))
}

/// git.kernel.org snapshot: verify the signed tag, then require the snapshot
/// to be exactly `git archive` of the tagged commit.
fn verify_snapshot(
    target: &KernelRelease,
    tarball: &Path,
    git_cache: &Path,
    ring: &Keyring,
    trust: &Trust,
) -> Result<(String, String, TarWalk)> {
    let tag = target.git_tag();
    if !git_cache.join("HEAD").exists() {
        std::fs::create_dir_all(git_cache).map_err(|e| io(git_cache.display().to_string(), e))?;
        let mut c = tool("git");
        c.args(["init", "--quiet", "--bare", "--"]).arg(git_cache);
        run(c, "git init --bare")?;
    }
    let git = |args: &[&str]| {
        let mut c = tool("git");
        c.arg("-C")
            .arg(git_cache)
            .env("GNUPGHOME", &ring.home)
            .args(args);
        c
    };
    check_url(TORVALDS_GIT)?;
    let refspec = format!("+refs/tags/{tag}:refs/tags/{tag}");
    run(
        git(&[
            "-c",
            "protocol.allow=never",
            "-c",
            "protocol.https.allow=always",
            "fetch",
            "--quiet",
            "--depth=1",
            "--no-tags",
            "--",
            TORVALDS_GIT,
            &refspec,
        ]),
        &format!("git fetch {tag}"),
    )?;
    check_snapshot(target, tarball, git_cache, ring, trust)
}

/// The fetched tag must be the release's, signed by a reviewed signer, and
/// the snapshot must be `git archive` of the commit it names.
fn check_snapshot(
    target: &KernelRelease,
    tarball: &Path,
    repo: &Path,
    ring: &Keyring,
    trust: &Trust,
) -> Result<(String, String, TarWalk)> {
    let tag = target.git_tag();
    let git = |args: &[&str]| {
        let mut c = tool("git");
        c.arg("-C")
            .arg(repo)
            .env("GNUPGHOME", &ring.home)
            .args(args);
        c
    };
    let tag_ref = format!("refs/tags/{tag}");
    let raw = String::from_utf8_lossy(&run(
        git(&["cat-file", "tag", &tag_ref]),
        "git cat-file tag",
    )?)
    .into_owned();
    let header = |k: &str| {
        raw.lines()
            .take_while(|l| !l.is_empty())
            .find_map(|l| l.strip_prefix(&format!("{k} ")).map(str::to_string))
    };
    let commit = header("object").unwrap_or_default();
    if !is_commit(&commit)
        || header("type").as_deref() != Some("commit")
        || header("tag").as_deref() != Some(tag.as_str())
    {
        return Err(verify_err(
            format!("tag object {tag}"),
            format!("object <commit>, type commit, tag {tag}"),
            raw.lines().take(3).collect::<Vec<_>>().join(" | "),
        ));
    }
    let mut vt = git(&["verify-tag", "--raw", &tag_ref]);
    vt.stdin(Stdio::null());
    let out = vt.output().map_err(|e| io("git verify-tag", e))?;
    let signer = judge_status(&String::from_utf8_lossy(&out.stderr), trust)?;
    if !out.status.success() {
        return Err(verify_err(
            "git verify-tag",
            "exit 0",
            format!("exit {}", out.status.code().unwrap_or(-1)),
        ));
    }
    let mut walk = TarWalk::new(&format!("linux-{}", target.ksrc()));
    let mut snap = Sha512::default();
    stream(
        decompress(target, tarball),
        "decompressing the snapshot",
        |c| {
            walk.update(c);
            snap.update(c);
            Ok(())
        },
    )?;
    let mut arch = Sha512::default();
    let prefix = format!("--prefix=linux-{}/", target.ksrc());
    stream(
        git(&["archive", "--format=tar", &prefix, &commit]),
        "git archive",
        |c| {
            arch.update(c);
            Ok(())
        },
    )?;
    let (snap, arch) = (snap.hex(), arch.hex());
    if snap != arch {
        return Err(verify_err(
            format!("snapshot content against git archive of {commit}"),
            arch,
            snap,
        ));
    }
    if walk.comment.as_deref() != Some(commit.as_str()) {
        return Err(verify_err(
            "snapshot pax comment",
            commit,
            walk.comment.clone().unwrap_or_default(),
        ));
    }
    Ok((signer, commit, walk))
}

/// The default download cache: $SHARUKHAN_KERNEL_CACHE, else
/// $XDG_CACHE_HOME/sharukhan/kernel, else $HOME/.cache/sharukhan/kernel.
pub fn default_cache() -> Result<PathBuf> {
    if let Some(p) = std::env::var_os("SHARUKHAN_KERNEL_CACHE") {
        return Ok(PathBuf::from(p));
    }
    if let Some(p) = std::env::var_os("XDG_CACHE_HOME") {
        return Ok(PathBuf::from(p).join("sharukhan/kernel"));
    }
    std::env::var_os("HOME")
        .map(|h| PathBuf::from(h).join(".cache/sharukhan/kernel"))
        .ok_or_else(|| {
            io(
                "kernel cache",
                "neither SHARUKHAN_KERNEL_CACHE, XDG_CACHE_HOME nor HOME is set",
            )
        })
}

/// Verify the tarball for `target`, downloading it into `cache` unless a
/// local copy is given. A given copy must carry kernel.org's file name.
pub fn verify(
    target: &KernelRelease,
    tarball: Option<&Path>,
    cache: &Path,
    trust: &Trust,
) -> Result<Verification> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::create_dir_all(cache).map_err(|e| io(cache.display().to_string(), e))?;
    let _ = std::fs::set_permissions(cache, std::fs::Permissions::from_mode(0o700));
    let path = match tarball {
        Some(p) => {
            let name = p
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default();
            if name != target.tarball() {
                return Err(verify_err(
                    format!("--tarball {}", p.display()),
                    target.tarball(),
                    name,
                ));
            }
            p.to_path_buf()
        }
        None => {
            let p = cache.join(target.tarball());
            if !p.exists() {
                fetch(&target.source_url(), &p)?;
            }
            p
        }
    };
    let work = cache.join(format!("work.{}", std::process::id()));
    std::fs::create_dir_all(&work).map_err(|e| io(work.display().to_string(), e))?;
    let result = (|| {
        let ring = Keyring::build(&work, trust)?;
        let (method, signer, commit, walk) = match target.kind {
            Kind::MainlineRc { .. } => {
                let (s, c, w) =
                    verify_snapshot(target, &path, &cache.join("torvalds.git"), &ring, trust)?;
                ("signed-tag", s, Some(c), w)
            }
            _ => {
                let (s, w) = verify_pgp(target, &path, &work, &ring, trust)?;
                ("pgp-signature", s, None, w)
            }
        };
        walk.check(&format!("{} contents", target.tarball()))?;
        let sha512 = crate::sha512::file(&path).map_err(|e| io(path.display().to_string(), e))?;
        Ok(Verification {
            tarball: path.clone(),
            sha512,
            method,
            signer,
            commit,
            entries: walk.entries,
        })
    })();
    let _ = std::fs::remove_dir_all(&work);
    result
}

// ------------------------------------------------------ releases.json ---

#[derive(Debug, Clone, PartialEq)]
pub struct Listed {
    pub moniker: String,
    pub version: String,
    pub iseol: bool,
    pub source: Option<String>,
    pub pgp: Option<String>,
}

/// Parse releases.json; entries whose version is outside the release grammar
/// (linux-next) are returned separately, not dropped silently.
pub fn parse_releases(json: &str) -> Result<(String, Vec<Listed>, Vec<String>)> {
    let v: serde_json::Value = serde_json::from_str(json)
        .map_err(|e| verify_err("releases.json", "JSON", e.to_string()))?;
    let latest = v["latest_stable"]["version"]
        .as_str()
        .ok_or_else(|| verify_err("releases.json", "latest_stable.version", "missing"))?
        .to_string();
    let arr = v["releases"]
        .as_array()
        .ok_or_else(|| verify_err("releases.json", "a releases array", "missing"))?;
    let (mut listed, mut other) = (Vec::new(), Vec::new());
    for r in arr {
        let s = |k: &str| r[k].as_str().map(str::to_string);
        let version = s("version")
            .ok_or_else(|| verify_err("releases.json entry", "a version", r.to_string()))?;
        let moniker = s("moniker").unwrap_or_default();
        if KernelRelease::parse(&version).is_err() {
            other.push(format!("{moniker} {version}"));
            continue;
        }
        listed.push(Listed {
            moniker,
            version,
            iseol: r["iseol"].as_bool().unwrap_or(false),
            source: s("source"),
            pgp: s("pgp"),
        });
    }
    Ok((latest, listed, other))
}

/// kernel.org's listing must agree with the identity computed here.
pub fn cross_check(k: &KernelRelease, l: &Listed) -> Result<()> {
    if l.source.as_deref() != Some(k.source_url().as_str()) {
        return Err(verify_err(
            format!("releases.json source of {}", l.version),
            k.source_url(),
            l.source.clone().unwrap_or_default(),
        ));
    }
    if l.pgp != k.signature_url() {
        return Err(verify_err(
            format!("releases.json pgp of {}", l.version),
            k.signature_url().unwrap_or_else(|| "none".into()),
            l.pgp.clone().unwrap_or_else(|| "none".into()),
        ));
    }
    Ok(())
}

/// `mainline`, `stable`, `longterm`, `longterm-X.Y`, or a release.
pub fn select(
    sel: &str,
    latest: &str,
    listed: &[Listed],
) -> Result<Vec<(KernelRelease, Option<Listed>)>> {
    let pick = |pred: &dyn Fn(&Listed) -> bool| -> Vec<Listed> {
        listed.iter().filter(|l| pred(l)).cloned().collect()
    };
    let chosen: Vec<Listed> = match sel {
        "mainline" => pick(&|l| l.moniker == "mainline"),
        "stable" => pick(&|l| l.version == latest),
        "longterm" => pick(&|l| l.moniker == "longterm"),
        s if s.starts_with("longterm-") => {
            let series = &s["longterm-".len()..];
            pick(&|l| l.moniker == "longterm" && l.version.starts_with(&format!("{series}.")))
        }
        s => {
            let k = KernelRelease::parse(s)?;
            let l = listed.iter().find(|l| l.version == s).cloned();
            if let Some(l) = &l {
                cross_check(&k, l)?;
            }
            return Ok(vec![(k, l)]);
        }
    };
    if chosen.is_empty() {
        return Err(verify_err(
            format!("selector '{sel}'"),
            "at least one listed release",
            "none in releases.json",
        ));
    }
    chosen
        .into_iter()
        .map(|l| {
            let k = KernelRelease::parse(&l.version)?;
            cross_check(&k, &l)?;
            Ok((k, Some(l)))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn trust() -> Trust {
        Trust {
            schema: 1,
            source: "https://www.kernel.org/signature.html".into(),
            reviewed: "2026-09-27".into(),
            keys_from: "https://git.kernel.org/pub/scm/docs/kernel/pgpkeys.git/plain/keys/".into(),
            signers: vec![Signer {
                name: "Linus Torvalds".into(),
                fingerprint: "ABAF11C65A2970B130ABE3C479BE3E4300411886".into(),
            }],
        }
    }

    #[test]
    fn only_https_kernel_org_urls_with_plain_paths_are_fetched() {
        assert!(
            check_url("https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.8.tar.xz").is_ok()
        );
        for bad in [
            "http://cdn.kernel.org/x",
            "https://cdn.kernel.org.evil.com/x",
            "https://user@cdn.kernel.org/x",
            "https://cdn.kernel.org/../x",
            "https://cdn.kernel.org/x y",
            "https://cdn.kernel.org/x;rm",
            "https://cdn.kernel.org",
            "file:///etc/passwd",
        ] {
            assert!(check_url(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn the_trust_file_is_validated_and_the_key_url_uses_the_long_id() {
        let t = trust();
        assert!(t.validate().is_ok());
        assert_eq!(
            t.key_url(&t.signers[0].fingerprint),
            "https://git.kernel.org/pub/scm/docs/kernel/pgpkeys.git/plain/keys/79BE3E4300411886.asc"
        );
        let mut u = trust();
        u.signers[0].fingerprint = u.signers[0].fingerprint.to_lowercase();
        assert!(u.validate().is_err());
        let mut u = trust();
        u.signers.push(u.signers[0].clone());
        assert!(u.validate().unwrap_err().contains("twice"));
        let mut u = trust();
        u.keys_from = "https://keys.example.org/".into();
        assert!(u.validate().is_err());
        let shipped =
            Path::new(env!("CARGO_MANIFEST_DIR")).join("profiles/kernel/kernel-org-signers.json");
        assert!(Trust::load(&shipped)
            .unwrap()
            .signer("ABAF11C65A2970B130ABE3C479BE3E4300411886")
            .is_some());
    }

    #[test]
    fn primary_fingerprints_ignore_subkeys() {
        let c = "pub:-:4096:1:79BE3E4300411886:::::::\nfpr:::::::::ABAF11C65A2970B130ABE3C479BE3E4300411886:\n\
                 uid:::::::::Linus:\nsub:-:2048:1:X:::::\nfpr:::::::::1111111111111111111111111111111111111111:\n";
        assert_eq!(
            primary_fingerprints(c),
            vec!["ABAF11C65A2970B130ABE3C479BE3E4300411886"]
        );
    }

    #[test]
    fn a_signature_is_accepted_only_when_good_valid_single_and_trusted() {
        let good = "[GNUPG:] NEWSIG\n[GNUPG:] GOODSIG 79BE3E4300411886 Linus\n\
                    [GNUPG:] VALIDSIG ABAF11C65A2970B130ABE3C479BE3E4300411886 2026-09-20 1789937295 0 4 0 1 10 00 ABAF11C65A2970B130ABE3C479BE3E4300411886\n";
        assert_eq!(
            judge_status(good, &trust()).unwrap(),
            "ABAF11C65A2970B130ABE3C479BE3E4300411886"
        );
        let other = good.replace(
            " 00 ABAF11C65A2970B130ABE3C479BE3E4300411886",
            " 00 647F28654894E3BD457199BE38DBBDC86092693E",
        );
        assert!(judge_status(&other, &trust())
            .unwrap_err()
            .to_string()
            .contains("reviewed kernel.org signer"));
        assert!(judge_status(&format!("{good}[GNUPG:] BADSIG 1 x\n"), &trust()).is_err());
        assert!(judge_status(&format!("{good}[GNUPG:] REVKEYSIG 1 x\n"), &trust()).is_err());
        assert!(judge_status(&format!("{good}{good}"), &trust()).is_err());
        assert!(judge_status("[GNUPG:] GOODSIG 1 x\n", &trust()).is_err());
        assert!(judge_status("", &trust()).is_err());
    }

    fn tar_header(name: &str, kind: u8, size: usize) -> Vec<u8> {
        let mut h = vec![0u8; 512];
        h[..name.len()].copy_from_slice(name.as_bytes());
        let s = format!("{size:011o}");
        h[124..135].copy_from_slice(s.as_bytes());
        h[156] = kind;
        h[257..262].copy_from_slice(b"ustar");
        h
    }

    fn pax(records: &[(&str, &str)]) -> Vec<u8> {
        let mut out = Vec::new();
        for (k, v) in records {
            let body = format!(" {k}={v}\n");
            let mut len = body.len() + 1;
            while format!("{len}{body}").len() != len {
                len += 1;
            }
            out.extend_from_slice(format!("{len}{body}").as_bytes());
        }
        out
    }

    fn archive(entries: &[(u8, &str, Vec<u8>)]) -> Vec<u8> {
        let mut t = Vec::new();
        for (kind, name, data) in entries {
            t.extend(tar_header(name, *kind, data.len()));
            t.extend(data);
            t.resize(t.len().div_ceil(512) * 512, 0);
        }
        t.extend(vec![0u8; 1024]);
        t
    }

    #[test]
    fn the_tar_walk_reads_the_commit_and_every_path_in_uneven_chunks() {
        let c = "93f51579e7df248780214094418f205253383cc5";
        let t = archive(&[
            (b'g', "pax_global_header", pax(&[("comment", c)])),
            (b'5', "linux-7.3-rc4/", vec![]),
            (b'0', "linux-7.3-rc4/Makefile", vec![b'x'; 700]),
            (
                b'x',
                "PaxHeaders/long",
                pax(&[("path", "linux-7.3-rc4/a/very/long/path")]),
            ),
            (b'0', "ignored-short-name", vec![b'y'; 3]),
        ]);
        let mut w = TarWalk::new("linux-7.3-rc4");
        for chunk in t.chunks(333) {
            w.update(chunk);
        }
        w.check("t").unwrap();
        assert_eq!(w.entries, 3);
        assert_eq!(w.comment.as_deref(), Some(c));
    }

    #[test]
    fn the_tar_walk_refuses_foreign_paths_truncation_and_trailing_data() {
        let t = archive(&[(b'0', "linux-7.2.8/Makefile", vec![1; 10])]);
        let mut w = TarWalk::new("linux-7.3-rc4");
        w.update(&t);
        assert!(w
            .check("t")
            .unwrap_err()
            .to_string()
            .contains("linux-7.2.8/Makefile"));
        let t = archive(&[(b'0', "linux-7.3-rc4/../etc/x", vec![])]);
        let mut w = TarWalk::new("linux-7.3-rc4");
        w.update(&t);
        assert!(w.check("t").is_err());
        let t = archive(&[(b'0', "linux-7.3-rc4/Makefile", vec![1; 10])]);
        let mut w = TarWalk::new("linux-7.3-rc4");
        w.update(&t[..t.len() - 600]);
        assert!(w.check("t").unwrap_err().to_string().contains("truncated"));
        let mut w = TarWalk::new("linux-7.3-rc4");
        let mut more = t.clone();
        more.extend(tar_header("linux-7.3-rc4/late", b'0', 0));
        w.update(&more);
        assert!(w.check("t").is_err());
        let mut w = TarWalk::new("linux-7.3-rc4");
        w.update(&vec![0u8; 1024]);
        assert!(w.check("t").unwrap_err().to_string().contains("empty"));
    }

    #[test]
    fn base256_and_octal_sizes_parse() {
        assert_eq!(octal(b"00000001750\0"), Some(1000));
        let mut f = [0u8; 12];
        f[0] = 0x80;
        f[11] = 5;
        assert_eq!(octal(&f), Some(5));
        assert_eq!(octal(b"zz\0"), None);
    }

    const RELEASES: &str = r#"{"latest_stable": {"version": "7.2.8"}, "releases": [
      {"moniker": "mainline", "version": "7.3-rc4", "iseol": false,
       "source": "https://git.kernel.org/torvalds/t/linux-7.3-rc4.tar.gz", "pgp": null},
      {"moniker": "stable", "version": "7.2.8", "iseol": false,
       "source": "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.8.tar.xz",
       "pgp": "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.8.tar.sign"},
      {"moniker": "longterm", "version": "6.18.54", "iseol": false,
       "source": "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.18.54.tar.xz",
       "pgp": "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.18.54.tar.sign"},
      {"moniker": "longterm", "version": "6.12.111", "iseol": false,
       "source": "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.111.tar.xz",
       "pgp": "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.111.tar.sign"},
      {"moniker": "linux-next", "version": "next-20260925", "iseol": false, "source": null, "pgp": null}]}"#;

    #[test]
    fn selectors_resolve_against_the_listing_and_are_cross_checked() {
        let (latest, listed, other) = parse_releases(RELEASES).unwrap();
        assert_eq!(other, vec!["linux-next next-20260925"]);
        let v = |s: &str| {
            select(s, &latest, &listed)
                .unwrap()
                .into_iter()
                .map(|(k, _)| k.ksrc())
                .collect::<Vec<_>>()
        };
        assert_eq!(v("mainline"), ["7.3-rc4"]);
        assert_eq!(v("stable"), ["7.2.8"]);
        assert_eq!(v("longterm"), ["6.18.54", "6.12.111"]);
        assert_eq!(v("longterm-6.12"), ["6.12.111"]);
        assert_eq!(v("7.3-rc3"), ["7.3-rc3"]);
        assert!(select("longterm-5.4", &latest, &listed).is_err());
        assert!(select("bogus", &latest, &listed).is_err());
        let moved = RELEASES.replace(
            "torvalds/t/linux-7.3-rc4.tar.gz",
            "torvalds/snapshot/linux-7.3-rc4.tar.gz",
        );
        let (latest, listed, _) = parse_releases(&moved).unwrap();
        assert!(select("mainline", &latest, &listed)
            .unwrap_err()
            .to_string()
            .contains("source of 7.3-rc4"));
        assert!(parse_releases("{}").is_err());
    }

    /// A throwaway signing key in a private GNUPGHOME, and a trust file that
    /// names only it: the real verification code runs against local fixtures.
    struct Lab {
        dir: PathBuf,
        ring: Keyring,
        fpr: String,
    }

    impl Lab {
        fn new(tag: &str) -> Lab {
            use std::os::unix::fs::PermissionsExt;
            let dir = std::env::temp_dir().join(format!("shk-{tag}-{}", std::process::id()));
            let _ = std::fs::remove_dir_all(&dir);
            let home = dir.join("g");
            std::fs::create_dir_all(&home).unwrap();
            std::fs::set_permissions(&home, std::fs::Permissions::from_mode(0o700)).unwrap();
            let ring = Keyring { home };
            ring.gpg(
                &[
                    "--pinentry-mode",
                    "loopback",
                    "--passphrase",
                    "",
                    "--quick-gen-key",
                    "Test Signer <test@example.invalid>",
                    "ed25519",
                    "sign",
                    "never",
                ],
                None,
            )
            .unwrap();
            let colons = ring.gpg(&["--with-colons", "--list-keys"], None).unwrap();
            let fpr = primary_fingerprints(&String::from_utf8_lossy(&colons)).remove(0);
            Lab { dir, ring, fpr }
        }

        fn trust(&self) -> Trust {
            let mut t = trust();
            t.signers = vec![Signer {
                name: "Test Signer".into(),
                fingerprint: self.fpr.clone(),
            }];
            t
        }

        fn sh(&self, args: &[&str]) {
            let st = Command::new(args[0])
                .args(&args[1..])
                .current_dir(&self.dir)
                .env("GNUPGHOME", &self.ring.home)
                .env("GIT_CONFIG_GLOBAL", "/dev/null")
                .env("GIT_CONFIG_NOSYSTEM", "1")
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .unwrap();
            assert!(st.success(), "{args:?}");
        }

        /// A tree `linux-<ksrc>/` with two files.
        fn tree(&self, top: &str, body: &str) {
            let d = self.dir.join(top);
            std::fs::create_dir_all(d.join("kernel")).unwrap();
            std::fs::write(d.join("Makefile"), body).unwrap();
            std::fs::write(d.join("kernel/fork.c"), "int x;\n").unwrap();
        }
    }

    impl Drop for Lab {
        fn drop(&mut self) {
            let _ = Command::new("gpgconf")
                .args(["--kill", "all"])
                .env("GNUPGHOME", &self.ring.home)
                .status();
            let _ = std::fs::remove_dir_all(&self.dir);
        }
    }

    #[test]
    fn a_cdn_tarball_is_accepted_only_with_a_trusted_signature_over_its_content() {
        let lab = Lab::new("pgp");
        let k = KernelRelease::parse("7.2.8").unwrap();
        lab.tree("linux-7.2.8", "VERSION = 7\n");
        lab.sh(&["tar", "-cf", "t.tar", "linux-7.2.8"]);
        lab.sh(&[
            "gpg",
            "--batch",
            "--yes",
            "--detach-sign",
            "-o",
            "t.tar.sign",
            "t.tar",
        ]);
        lab.sh(&["xz", "-kf", "t.tar"]);
        let xz = lab.dir.join("linux-7.2.8.tar.xz");
        std::fs::rename(lab.dir.join("t.tar.xz"), &xz).unwrap();
        let sig = lab.dir.join("t.tar.sign");
        let (signer, walk) = check_pgp(&k, &xz, &sig, &lab.ring, &lab.trust()).unwrap();
        assert_eq!(signer, lab.fpr);
        walk.check("t").unwrap();
        assert_eq!(walk.entries, 4);
        // the same good signature, but the signer is not a reviewed one
        let e = check_pgp(&k, &xz, &sig, &lab.ring, &trust())
            .unwrap_err()
            .to_string();
        assert!(e.contains("reviewed kernel.org signer"), "{e}");
        // different content under the same signature
        lab.tree("linux-7.2.8", "VERSION = 8\n");
        lab.sh(&["tar", "-cf", "t.tar", "linux-7.2.8"]);
        lab.sh(&["xz", "-kf", "t.tar"]);
        std::fs::rename(lab.dir.join("t.tar.xz"), &xz).unwrap();
        let e = check_pgp(&k, &xz, &sig, &lab.ring, &lab.trust())
            .unwrap_err()
            .to_string();
        assert!(e.contains("BADSIG"), "{e}");
        // not a tarball at all: the decompressor fails
        std::fs::write(&xz, "junk").unwrap();
        assert!(check_pgp(&k, &xz, &sig, &lab.ring, &lab.trust()).is_err());
    }

    #[test]
    fn a_snapshot_is_accepted_only_as_git_archive_of_a_trusted_signed_tag() {
        let lab = Lab::new("tag");
        let k = KernelRelease::parse("7.3-rc9").unwrap();
        let repo = lab.dir.join("repo");
        std::fs::create_dir_all(&repo).unwrap();
        lab.sh(&["git", "-C", "repo", "init", "-q"]);
        std::fs::write(repo.join("Makefile"), "VERSION = 7\n").unwrap();
        lab.sh(&["git", "-C", "repo", "add", "Makefile"]);
        lab.sh(&[
            "git",
            "-C",
            "repo",
            "-c",
            "user.name=T",
            "-c",
            "user.email=t@example.invalid",
            "commit",
            "-q",
            "-m",
            "Linux 7.3-rc9",
        ]);
        let key = format!("user.signingkey={}", lab.fpr);
        lab.sh(&[
            "git",
            "-C",
            "repo",
            "-c",
            "user.name=T",
            "-c",
            "user.email=t@example.invalid",
            "-c",
            &key,
            "tag",
            "-s",
            "-m",
            "Linux 7.3-rc9",
            "v7.3-rc9",
        ]);
        let gz = lab.dir.join("linux-7.3-rc9.tar.gz");
        let snapshot = |extra: &str| {
            let head = Command::new("git")
                .args(["-C", "repo", "rev-parse", "HEAD"])
                .current_dir(&lab.dir)
                .output()
                .unwrap();
            let head = String::from_utf8(head.stdout).unwrap().trim().to_string();
            let tar = Command::new("git")
                .args([
                    "-C",
                    "repo",
                    "archive",
                    "--format=tar",
                    "--prefix=linux-7.3-rc9/",
                    &head,
                ])
                .current_dir(&lab.dir)
                .output()
                .unwrap()
                .stdout;
            let mut tar = tar;
            tar.extend_from_slice(extra.as_bytes());
            std::fs::write(lab.dir.join("s.tar"), &tar).unwrap();
            lab.sh(&["gzip", "-nf", "s.tar"]);
            std::fs::rename(lab.dir.join("s.tar.gz"), &gz).unwrap();
            head
        };
        let head = snapshot("");
        let (signer, commit, walk) =
            check_snapshot(&k, &gz, &repo, &lab.ring, &lab.trust()).unwrap();
        assert_eq!(
            (signer.as_str(), commit.as_str()),
            (lab.fpr.as_str(), head.as_str())
        );
        walk.check("t").unwrap();
        // bytes that git archive did not produce
        snapshot("x");
        let e = check_snapshot(&k, &gz, &repo, &lab.ring, &lab.trust())
            .unwrap_err()
            .to_string();
        assert!(e.contains("against git archive"), "{e}");
        snapshot("");
        // untrusted signer
        assert!(check_snapshot(&k, &gz, &repo, &lab.ring, &trust()).is_err());
        // another release's tag is not there to stand in
        let k8 = KernelRelease::parse("7.3-rc8").unwrap();
        assert!(check_snapshot(&k8, &gz, &repo, &lab.ring, &lab.trust()).is_err());
        // an annotated but unsigned tag
        lab.sh(&[
            "git",
            "-C",
            "repo",
            "-c",
            "user.name=T",
            "-c",
            "user.email=t@example.invalid",
            "tag",
            "-f",
            "-a",
            "-m",
            "Linux 7.3-rc9",
            "v7.3-rc9",
        ]);
        let e = check_snapshot(&k, &gz, &repo, &lab.ring, &lab.trust())
            .unwrap_err()
            .to_string();
        assert!(e.contains("signature"), "{e}");
    }

    #[test]
    fn verify_refuses_a_local_copy_under_another_name_before_anything_else() {
        let k = KernelRelease::parse("7.2.8").unwrap();
        let dir = std::env::temp_dir().join(format!("shk-name-{}", std::process::id()));
        let e = verify(&k, Some(Path::new("/x/linux-7.2.7.tar.xz")), &dir, &trust())
            .unwrap_err()
            .to_string();
        assert!(
            e.contains("linux-7.2.8.tar.xz") && e.contains("linux-7.2.7.tar.xz"),
            "{e}"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }
}
