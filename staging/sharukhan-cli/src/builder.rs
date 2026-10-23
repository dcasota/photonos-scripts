//! The builder container: Photon's build tooling with a pinned userland.
//!
//! `make` (build.py, the package builder, poi.py) and the Python spec tools
//! (SpecData, check_spec) used to run on the host, with whatever python3 and
//! modules the host had. On 2026-10-18 another workload moved the host's
//! python3 to 3.14 without the builder's modules and left python3-xml broken
//! against an older expat; every spec check failed until a venv was patched in.
//!
//! The image is built from inputs that are all local and locked:
//!
//! * the base image `photon:5.0`, accepted only with the image ID below;
//! * RPMs resolved by `sharukhan builder lock` from `packages.txt`, each pinned
//!   to the host's version-release (a package the host lacks follows the host
//!   package built from the same source), all VMware-signed, listed with their
//!   sha256 in `rpms.sha256`;
//! * Python wheels pinned by sha256 in `wheels.lock`.
//!
//! The tag is a hash over all of them, so an unchanged definition reuses its
//! image and any change builds a new one. A new image is proven before use:
//! every tool the build calls is present and every pinned module is installed
//! at its pinned version.
//!
//! Running `make` there has one host requirement. Photon's TDNFSandbox runs
//! tdnf in a sibling container on the host's docker daemon and binds the
//! sandbox's overlay and `--bind` mounts into it, so mounts made inside the
//! builder must reach the host: the shared root must be a mount point with
//! shared propagation (photon-mc-gate-shared.service sets it at every boot),
//! and the builder mounts it with `bind-propagation=rshared`.
//!
//! `MC_BUILDER=host` (the default) keeps everything on the host; `container`
//! routes `make` and the spec tools through the image.

use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;

const DOCKERFILE: &str = include_str!("embedded/builder/Dockerfile");
const SYSTEMCTL: &str = include_str!("embedded/builder/systemctl");
const PACKAGES: &str = include_str!("embedded/builder/packages.txt");
const WHEELS: &str = include_str!("embedded/builder/wheels.lock");

/// The base image and the only image ID accepted for it.
pub const BASE_IMAGE: &str = "photon:5.0";
pub const BASE_IMAGE_ID: &str =
    "sha256:549ea0b6a67da5fd9a4ddc4ddf5d7d479b30b75af9ae3d9c5936b470fb6be323";

/// Commands build.py, the Makefile, the package builder and poi.py call.
const TOOLS: &[&str] = &[
    "bash", "jq", "g++", "make", "git", "rpm", "rpmbuild", "createrepo_c", "docker", "tdnf", "tar",
    "xz", "zstd", "bzip2", "gzip", "cpio", "patch", "sudo", "find", "sed", "gawk", "mount",
    "systemctl",
];

const REPOS: &[&str] = &[
    "--disablerepo=*",
    "--enablerepo=photon-updates",
    "--enablerepo=photon-release",
    "--enablerepo=photon",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Host,
    Container,
}

pub fn parse_mode(v: Option<&str>) -> Result<Mode, String> {
    match v.map(str::trim) {
        None | Some("") | Some("host") => Ok(Mode::Host),
        Some("container") => Ok(Mode::Container),
        Some(other) => Err(format!("MC_BUILDER={other}: valid values are host and container")),
    }
}

pub fn mode() -> Result<Mode, String> {
    parse_mode(std::env::var("MC_BUILDER").ok().as_deref())
}

pub fn shared_root() -> PathBuf {
    PathBuf::from(std::env::var("MC_BUILDER_SHARED_ROOT").unwrap_or_else(|_| "/root/photon-mc/gate".into()))
}

pub fn context_dir() -> PathBuf {
    PathBuf::from(std::env::var("MC_BUILDER_DIR").unwrap_or_else(|_| "/root/photon-mc/gate/builder".into()))
}

fn run(prog: &str, args: &[&str]) -> Result<String, String> {
    let out = Command::new(prog)
        .args(args)
        .output()
        .map_err(|e| format!("running {prog}: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "{prog} {} failed: {}",
            args.join(" "),
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&out.stdout).to_string())
}

// --- the host mount ---------------------------------------------------------

/// Undo mountinfo's octal escapes (`\040` for a space).
fn unescape(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'\\' && i + 3 < b.len() {
            if let Ok(v) = u8::from_str_radix(&s[i + 1..i + 4], 8) {
                out.push(v);
                i += 4;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).to_string()
}

/// The propagation of the mount AT `mount_point` in a mountinfo text: the
/// last entry for that point, which is the one on top of the stack. None
/// when the path is not a mount point.
pub fn propagation(mountinfo: &str, mount_point: &Path) -> Option<String> {
    let want = mount_point.to_string_lossy();
    let mut found = None;
    for line in mountinfo.lines() {
        let f: Vec<&str> = line.split(' ').collect();
        if f.len() < 7 || unescape(f[4]) != want {
            continue;
        }
        let optional: Vec<&str> = f[6..].iter().take_while(|x| **x != "-").copied().collect();
        let kind = if optional.iter().any(|o| o.starts_with("shared:")) {
            "shared"
        } else if optional.iter().any(|o| o.starts_with("master:")) {
            "slave"
        } else if optional.iter().any(|o| *o == "unbindable") {
            "unbindable"
        } else {
            "private"
        };
        found = Some(kind.to_string());
    }
    found
}

/// The shared root must be a shared mount in THIS mount namespace, which for
/// sharukhan is the host's (the gate scripts nsenter into it).
pub fn check_shared(root: &Path) -> Result<(), String> {
    let info = fs::read_to_string("/proc/self/mountinfo").map_err(|e| format!("/proc/self/mountinfo: {e}"))?;
    match propagation(&info, root) {
        Some(p) if p == "shared" => Ok(()),
        p => Err(format!(
            "{} is {} in this mount namespace, but the builder container needs it shared: \
             Photon's tdnf sandbox runs in a sibling container that must see the mounts the build makes there. \
             Run `systemctl start photon-mc-gate-shared` (it runs at every boot), and run sharukhan in the host mount namespace",
            root.display(),
            p.map(|p| format!("a {p} mount")).unwrap_or_else(|| "not a mount point".into())
        )),
    }
}

// --- locked inputs ----------------------------------------------------------

/// `(sha256, file)` entries of a sha256sum-style lock.
pub fn parse_lock(text: &str) -> Result<Vec<(String, String)>, String> {
    let mut out = Vec::new();
    for l in text.lines().map(str::trim).filter(|l| !l.is_empty() && !l.starts_with('#')) {
        let mut f = l.split_whitespace();
        let (Some(h), Some(name), None) = (f.next(), f.next(), f.next()) else {
            return Err(format!("malformed lock line: {l}"));
        };
        if h.len() != 64 || !h.bytes().all(|c| c.is_ascii_hexdigit()) || name.contains('/') {
            return Err(format!("malformed lock line: {l}"));
        }
        out.push((h.to_lowercase(), name.to_string()));
    }
    if out.is_empty() {
        return Err("the lock lists nothing".into());
    }
    Ok(out)
}

/// `(requirement, sha256, file)` of wheels.lock.
pub fn wheel_pins(text: &str) -> Result<Vec<(String, String, String)>, String> {
    let mut out = Vec::new();
    for l in text.lines().map(str::trim).filter(|l| !l.is_empty() && !l.starts_with('#')) {
        let f: Vec<&str> = l.split_whitespace().collect();
        if f.len() != 3 || !f[0].contains("==") || f[1].len() != 64 {
            return Err(format!("malformed wheels.lock line: {l}"));
        }
        out.push((f[0].to_string(), f[1].to_lowercase(), f[2].to_string()));
    }
    Ok(out)
}

/// Every locked file is present with its hash, and nothing else of `ext` is
/// in `dir`: an extra RPM would be installed by the `*.rpm` glob unverified.
pub fn verify_dir(dir: &Path, lock: &[(String, String)], ext: &str) -> Result<(), String> {
    for (h, name) in lock {
        let p = dir.join(name);
        let got = crate::sha256::file(&p).map_err(|e| format!("{}: {e}", p.display()))?;
        if &got != h {
            return Err(format!("{}: sha256 {got} does not match the lock ({h})", p.display()));
        }
    }
    let rd = fs::read_dir(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    for e in rd.flatten() {
        let n = e.file_name().to_string_lossy().to_string();
        if n.ends_with(ext) && !lock.iter().any(|(_, l)| *l == n) {
            return Err(format!("{}: {n} is not in the lock", dir.display()));
        }
    }
    Ok(())
}

/// What the image is built from, hashed: the tag and the image label.
pub fn inputs_hash(base_id: &str, rpms_lock: &str, wheels_lock: &str) -> String {
    let mut all = String::new();
    for part in [base_id, DOCKERFILE, SYSTEMCTL, PACKAGES, rpms_lock, wheels_lock] {
        all.push_str(&format!("{}\n{}\n", part.len(), part));
    }
    crate::sha256::bytes(all.as_bytes())[..16].to_string()
}

fn write_if_changed(p: &Path, text: &str, mode: u32) -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt;
    if fs::read_to_string(p).ok().as_deref() != Some(text) {
        fs::write(p, text).map_err(|e| format!("{}: {e}", p.display()))?;
    }
    fs::set_permissions(p, fs::Permissions::from_mode(mode)).map_err(|e| format!("{}: {e}", p.display()))
}

fn wheels_sha256() -> Result<String, String> {
    Ok(wheel_pins(WHEELS)?
        .iter()
        .map(|(_, h, f)| format!("{h}  {f}\n"))
        .collect())
}

/// Download any pinned wheel that is missing or does not match its hash.
fn fetch_wheels(ctx: &Path, log: &mut dyn FnMut(&str)) -> Result<(), String> {
    let dir = ctx.join("wheels");
    fs::create_dir_all(&dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    for (req, h, f) in wheel_pins(WHEELS)? {
        let p = dir.join(&f);
        if crate::sha256::file(&p).ok().as_deref() == Some(h.as_str()) {
            continue;
        }
        let _ = fs::remove_file(&p);
        log(&format!("  fetching {req}"));
        run(
            "python3",
            &["-m", "pip", "download", "--quiet", "--only-binary=:all:", "--no-deps", "--python-version", "3.14",
              "--platform", "manylinux_2_17_x86_64", "--dest", &dir.to_string_lossy(), &req],
        )?;
        let got = crate::sha256::file(&p).map_err(|e| format!("{req}: expected {f}: {e}"))?;
        if got != h {
            let _ = fs::remove_file(&p);
            return Err(format!("{f}: sha256 {got} does not match wheels.lock ({h})"));
        }
    }
    Ok(())
}

// --- the image --------------------------------------------------------------

static IMAGE: Mutex<Option<String>> = Mutex::new(None);

fn label(image: &str) -> Option<String> {
    run("docker", &["image", "inspect", image, "--format", "{{index .Config.Labels \"sharukhan.inputs\"}}"])
        .ok()
        .map(|s| s.trim().to_string())
}

/// The builder image for the current definition and locks, built and proven
/// if it does not exist yet. Cached for the process.
pub fn ensure(log: &mut dyn FnMut(&str)) -> Result<String, String> {
    if let Some(t) = IMAGE.lock().map_err(|_| "builder image lock poisoned")?.clone() {
        return Ok(t);
    }
    let ctx = context_dir();
    fs::create_dir_all(&ctx).map_err(|e| format!("{}: {e}", ctx.display()))?;
    write_if_changed(&ctx.join("Dockerfile"), DOCKERFILE, 0o644)?;
    write_if_changed(&ctx.join("systemctl"), SYSTEMCTL, 0o755)?;
    let wheels_lock = wheels_sha256()?;
    write_if_changed(&ctx.join("wheels.sha256"), &wheels_lock, 0o644)?;
    let rpms_lock = fs::read_to_string(ctx.join("rpms.sha256")).map_err(|_| {
        format!("{} has no rpms.sha256: run `sharukhan builder lock` first", ctx.display())
    })?;

    let base_id = run("docker", &["image", "inspect", BASE_IMAGE, "--format", "{{.Id}}"])
        .map_err(|e| format!("the base image {BASE_IMAGE}: {e}"))?
        .trim()
        .to_string();
    if base_id != BASE_IMAGE_ID {
        return Err(format!(
            "{BASE_IMAGE} is {base_id}, not the pinned {BASE_IMAGE_ID}: the builder is defined on that image only"
        ));
    }
    let hash = inputs_hash(&base_id, &rpms_lock, &wheels_lock);
    let tag = format!("sharukhan/photon-builder:{hash}");
    if label(&tag).as_deref() == Some(hash.as_str()) {
        *IMAGE.lock().map_err(|_| "builder image lock poisoned")? = Some(tag.clone());
        return Ok(tag);
    }

    log(&format!("  building the builder image {tag}"));
    verify_dir(&ctx.join("rpms"), &parse_lock(&rpms_lock)?, ".rpm")?;
    fetch_wheels(&ctx, log)?;
    verify_dir(&ctx.join("wheels"), &parse_lock(&wheels_lock)?, ".whl")?;
    let base_tag = format!("sharukhan/photon-base:5.0-{}", &base_id[7..19]);
    run("docker", &["tag", BASE_IMAGE, &base_tag])?;
    let out = Command::new("docker")
        .args(["build", "--network", "none", "--label", &format!("sharukhan.inputs={hash}")])
        .args(["--build-arg", &format!("BASE={base_tag}"), "-t", &tag])
        .arg(&ctx)
        .env("DOCKER_BUILDKIT", "1")
        .output()
        .map_err(|e| format!("running docker build: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "docker build of {tag} failed: {}",
            String::from_utf8_lossy(&out.stderr).lines().rev().take(8).collect::<Vec<_>>().join(" | ")
        ));
    }
    if let Err(e) = prove(&tag) {
        let _ = run("docker", &["rmi", &tag]);
        return Err(format!("{tag} was built but fails its proof, removed: {e}"));
    }
    log(&format!("  {tag}: every tool present, every pinned module at its version"));
    *IMAGE.lock().map_err(|_| "builder image lock poisoned")? = Some(tag.clone());
    Ok(tag)
}

fn normalize(name: &str) -> String {
    name.to_lowercase().replace(['_', '.'], "-")
}

/// A new image is used only if every tool is there and pip reports every
/// pinned module at exactly its pinned version.
fn prove(tag: &str) -> Result<(), String> {
    let script = format!(
        "for t in {}; do command -v $t >/dev/null || echo MISSING $t; done; python3 -m pip list --format=freeze 2>/dev/null",
        TOOLS.join(" ")
    );
    let out = run("docker", &["run", "--rm", "--network", "none", tag, "sh", "-c", &script])?;
    let missing: Vec<&str> = out.lines().filter_map(|l| l.strip_prefix("MISSING ")).collect();
    if !missing.is_empty() {
        return Err(format!("missing tools: {}", missing.join(" ")));
    }
    let installed: Vec<(String, String)> = out
        .lines()
        .filter_map(|l| l.split_once("=="))
        .map(|(n, v)| (normalize(n), v.trim().to_string()))
        .collect();
    for (req, _, _) in wheel_pins(WHEELS)? {
        let (n, v) = req.split_once("==").unwrap_or((&req, ""));
        match installed.iter().find(|(i, _)| *i == normalize(n)) {
            Some((_, got)) if got == v => {}
            Some((_, got)) => return Err(format!("{n} is {got}, pinned {v}")),
            None => return Err(format!("{n} is not installed")),
        }
    }
    Ok(())
}

// --- running ----------------------------------------------------------------

fn under(p: &Path, root: &Path) -> bool {
    p.starts_with(root)
}

/// `make <args>` in `release`: on the host (`sudo make`, as before) or in the
/// builder container.
pub fn make_command(release: &Path, args: &[&str], log: &mut dyn FnMut(&str)) -> Result<Command, String> {
    match mode()? {
        Mode::Host => {
            let mut c = Command::new("sudo");
            c.arg("make").args(args).current_dir(release);
            Ok(c)
        }
        Mode::Container => {
            let root = shared_root();
            if !under(release, &root) {
                return Err(format!(
                    "{} is outside the builder's shared root {}: the container sees only that tree",
                    release.display(),
                    root.display()
                ));
            }
            check_shared(&root)?;
            let image = ensure(log)?;
            Ok(container_make(&image, &root, release, args))
        }
    }
}

pub fn container_make(image: &str, root: &Path, release: &Path, args: &[&str]) -> Command {
    let mut c = Command::new("docker");
    c.args(["run", "--rm", "--privileged", "--network", "host"])
        .args(["-v", "/var/run/docker.sock:/var/run/docker.sock"])
        .arg("--mount")
        .arg(format!(
            "type=bind,src={r},dst={r},bind-propagation=rshared",
            r = root.display()
        ))
        .arg("-w")
        .arg(release)
        .arg(image)
        .arg("make")
        .args(args);
    c
}

/// `sh <script> <args>` with `envs`: on the host, or in the builder container
/// like `make` (the script runs make itself), with `extra` directories outside
/// the shared root (an ISO destination) bind-mounted at the same paths.
pub fn script_command(
    script: &Path,
    args: &[OsString],
    envs: &[(&str, &str)],
    extra: &[PathBuf],
    log: &mut dyn FnMut(&str),
) -> Result<Command, String> {
    match mode()? {
        Mode::Host => {
            let mut c = Command::new("sh");
            c.arg(script).args(args);
            for (k, v) in envs {
                c.env(k, v);
            }
            Ok(c)
        }
        Mode::Container => {
            let root = shared_root();
            if !under(script, &root) {
                return Err(format!(
                    "{} is outside the builder's shared root {}",
                    script.display(),
                    root.display()
                ));
            }
            check_shared(&root)?;
            let image = ensure(log)?;
            Ok(container_script(&image, &root, script, args, envs, extra))
        }
    }
}

pub fn container_script(
    image: &str,
    root: &Path,
    script: &Path,
    args: &[OsString],
    envs: &[(&str, &str)],
    extra: &[PathBuf],
) -> Command {
    let mut c = Command::new("docker");
    c.args(["run", "--rm", "--privileged", "--network", "host"])
        .args(["-v", "/var/run/docker.sock:/var/run/docker.sock"])
        .arg("--mount")
        .arg(format!(
            "type=bind,src={r},dst={r},bind-propagation=rshared",
            r = root.display()
        ));
    for d in extra.iter().filter(|d| !under(d, root)) {
        c.arg("-v").arg(format!("{0}:{0}", d.display()));
    }
    for (k, v) in envs {
        c.arg("-e").arg(format!("{k}={v}"));
    }
    c.arg("-w").arg(root).arg(image).arg("sh").arg(script).args(args);
    c
}

/// The directories a Python tool needs to see: the shared root, `cwd`, and
/// for every absolute path argument outside the root its nearest existing
/// directory. `/` itself is never mounted.
pub fn python_mounts(root: &Path, cwd: &Path, args: &[OsString]) -> Result<Vec<PathBuf>, String> {
    let mut dirs = vec![root.to_path_buf()];
    let mut want = vec![cwd.to_path_buf()];
    want.extend(args.iter().map(PathBuf::from).filter(|p| p.is_absolute()));
    for p in want {
        if under(&p, root) {
            continue;
        }
        let mut d = p.clone();
        while !d.is_dir() {
            match d.parent() {
                Some(up) => d = up.to_path_buf(),
                None => break,
            }
        }
        if d == Path::new("/") || d.as_os_str().is_empty() {
            return Err(format!("{}: refusing to mount / into the builder", p.display()));
        }
        if !dirs.iter().any(|x| d.starts_with(x)) {
            dirs.retain(|x| !x.starts_with(&d));
            dirs.push(d);
        }
    }
    Ok(dirs)
}

/// `python3 <args>` in `cwd`: on the host or in the builder container, with no
/// network and only the directories the call names.
pub fn python_command(cwd: &Path, args: &[OsString], log: &mut dyn FnMut(&str)) -> Result<Command, String> {
    match mode()? {
        Mode::Host => {
            let mut c = Command::new("python3");
            c.args(args).current_dir(cwd);
            Ok(c)
        }
        Mode::Container => {
            let root = shared_root();
            let image = ensure(log)?;
            let mut c = Command::new("docker");
            c.args(["run", "--rm", "--network", "none"]);
            for d in python_mounts(&root, cwd, args)? {
                c.arg("-v").arg(format!("{0}:{0}", d.display()));
            }
            c.arg("-w").arg(cwd).arg(image).arg("python3").args(args);
            Ok(c)
        }
    }
}

// --- lock -------------------------------------------------------------------

fn host_vr(name: &str) -> Option<(String, String)> {
    let out = Command::new("rpm")
        .args(["-q", "--qf", "%{VERSION}-%{RELEASE} %{SOURCERPM}\n", name])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let l = String::from_utf8_lossy(&out.stdout).lines().next()?.to_string();
    let (vr, src) = l.split_once(' ')?;
    Some((vr.to_string(), src.to_string()))
}

/// The NEVR to request for `name`: the host's when it has the package, else
/// the host's version-release of the package built from the same source,
/// unless that source family was moved to the repo version.
fn pin(name: &str, unpinned: &[String]) -> (String, Option<String>) {
    let mut h = host_vr(name);
    if h.is_none() {
        let mut p = name;
        while let Some((up, _)) = p.rsplit_once('-') {
            p = up;
            if let Some(x) = host_vr(p) {
                h = Some(x);
                break;
            }
        }
    }
    match h {
        Some((vr, src)) if !unpinned.contains(&src) => (format!("{name}-{vr}"), Some(src)),
        _ => (name.to_string(), None),
    }
}

/// Names in tdnf's "Installing:" table.
pub fn transaction_names(text: &str) -> Vec<String> {
    let body = text.split_once("Installing:").map(|(_, b)| b).unwrap_or("");
    let mut out: Vec<String> = body
        .lines()
        .take_while(|l| !l.starts_with("Total"))
        .filter_map(|l| {
            let f: Vec<&str> = l.split_whitespace().collect();
            (f.len() >= 5 && (f[1] == "x86_64" || f[1] == "noarch")).then(|| f[0].to_string())
        })
        .collect();
    out.sort();
    out.dedup();
    out
}

fn tdnf(root: &Path, args: &[&str]) -> std::process::Output {
    Command::new("tdnf")
        .arg("--installroot")
        .arg(root)
        .args(["--releasever", "5.0"])
        .args(REPOS)
        .args(args)
        .output()
        .unwrap_or_else(|e| std::process::Output {
            status: std::os::unix::process::ExitStatusExt::from_raw(127 << 8),
            stdout: vec![],
            stderr: format!("running tdnf: {e}").into_bytes(),
        })
}

fn scratch(ctx: &Path, prefix: &str) -> Result<PathBuf, String> {
    let p = ctx.join(format!(".{prefix}.{}", std::process::id()));
    let _ = fs::remove_dir_all(&p);
    fs::create_dir_all(&p).map_err(|e| format!("{}: {e}", p.display()))?;
    Ok(p)
}

/// Resolve packages.txt into a signed, pinned RPM set in `<ctx>/rpms` and
/// write `rpms.sha256`; fetch the pinned wheels.
pub fn lock(log: &mut dyn FnMut(&str)) -> Result<(), String> {
    let ctx = context_dir();
    fs::create_dir_all(&ctx).map_err(|e| format!("{}: {e}", ctx.display()))?;
    let top: Vec<String> = PACKAGES
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .map(str::to_string)
        .collect();
    let mut unpinned: Vec<String> = Vec::new();
    let mut fetched: Option<PathBuf> = None;
    for _ in 0..10 {
        // Resolve without downloading: the repo metadata can name a file the
        // mirror lacks (gdb-minimal-17.1-4 on 2026-10-23); only the pinned set
        // is fetched. --assumeno makes tdnf exit non-zero by design.
        let ir = scratch(&ctx, "ir")?;
        let req: Vec<String> = top.iter().map(|n| pin(n, &unpinned).0).collect();
        let mut a = vec!["--assumeno", "install"];
        a.extend(req.iter().map(String::as_str));
        let o = tdnf(&ir, &a);
        let _ = fs::remove_dir_all(&ir);
        let mut names = transaction_names(&String::from_utf8_lossy(&o.stdout));
        names.extend(top.iter().cloned());
        names.sort();
        names.dedup();
        let pins: Vec<(String, String, Option<String>)> = names
            .iter()
            .map(|n| {
                let (p, src) = pin(n, &unpinned);
                (n.clone(), p, src)
            })
            .collect();
        let ir = scratch(&ctx, "ir")?;
        let dl = scratch(&ctx, "new")?;
        let dls = dl.to_string_lossy().to_string();
        let mut a = vec!["-y", "--downloadonly", "--downloaddir", dls.as_str(), "install"];
        a.extend(pins.iter().map(|(_, p, _)| p.as_str()));
        let o = tdnf(&ir, &a);
        let _ = fs::remove_dir_all(&ir);
        if o.status.success() {
            fetched = Some(dl);
            break;
        }
        let _ = fs::remove_dir_all(&dl);
        let text = format!("{}{}", String::from_utf8_lossy(&o.stdout), String::from_utf8_lossy(&o.stderr));
        let mut moved: Vec<String> = Vec::new();
        for (n, p, src) in &pins {
            let named = text.contains(&format!("Package '{p}' not found"))
                || text.contains(&format!("provided by {n}-"));
            if let (true, Some(s)) = (named, src) {
                if !moved.contains(s) && !unpinned.contains(s) {
                    moved.push(s.clone());
                }
            }
        }
        if moved.is_empty() {
            let tail: Vec<&str> = text.lines().rev().take(4).collect();
            return Err(format!("tdnf could not fetch the pinned set: {}", tail.join(" | ")));
        }
        log(&format!("  moving to the repo version: {}", moved.join(" ")));
        unpinned.extend(moved);
    }
    let dl = fetched.ok_or("no consistent RPM set after 10 attempts")?;
    let mut files: Vec<PathBuf> = fs::read_dir(&dl)
        .map_err(|e| format!("{}: {e}", dl.display()))?
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|x| x == "rpm"))
        .collect();
    files.sort();
    let mut seen: Vec<String> = Vec::new();
    for f in &files {
        let fs_ = f.to_string_lossy().to_string();
        let n = run("rpm", &["-qp", "--qf", "%{NAME}", &fs_])?;
        if seen.contains(&n) {
            return Err(format!("several versions of {n} in the set"));
        }
        seen.push(n);
        let k = run("rpm", &["-K", &fs_])?;
        if !k.trim_end().ends_with("digests signatures OK") {
            return Err(format!("{}: no valid VMware signature", f.display()));
        }
    }
    let rpms = ctx.join("rpms");
    fs::create_dir_all(&rpms).map_err(|e| format!("{}: {e}", rpms.display()))?;
    for e in fs::read_dir(&rpms).map_err(|e| format!("{}: {e}", rpms.display()))?.flatten() {
        if e.path().extension().is_some_and(|x| x == "rpm") {
            fs::remove_file(e.path()).map_err(|er| format!("{}: {er}", e.path().display()))?;
        }
    }
    let mut lock = String::new();
    for f in &files {
        let name = f.file_name().unwrap_or_default().to_string_lossy().to_string();
        let h = crate::sha256::file(f)?;
        fs::rename(f, rpms.join(&name)).map_err(|e| format!("{name}: {e}"))?;
        lock.push_str(&format!("{h}  {name}\n"));
    }
    let _ = fs::remove_dir_all(&dl);
    fs::write(ctx.join("rpms.sha256"), &lock).map_err(|e| format!("rpms.sha256: {e}"))?;
    fetch_wheels(&ctx, log)?;
    log(&format!(
        "locked {} RPMs (all VMware-signed) and {} wheels in {}; source families moved to the repo version: {}",
        files.len(),
        wheel_pins(WHEELS)?.len(),
        ctx.display(),
        if unpinned.is_empty() { "none".to_string() } else { unpinned.join(" ") }
    ));
    Ok(())
}

/// `sharukhan builder lock | ensure | status`
pub fn cli(args: &[String]) -> u8 {
    let mut log = |l: &str| println!("{l}");
    let r = match args.first().map(String::as_str) {
        Some("lock") => lock(&mut log),
        Some("ensure") => ensure(&mut log).map(|t| println!("{t}")),
        Some("status") => {
            let root = shared_root();
            println!("mode: {:?} (MC_BUILDER)", mode().unwrap_or(Mode::Host));
            println!("shared root: {} - {}", root.display(), match check_shared(&root) {
                Ok(()) => "shared".to_string(),
                Err(e) => e,
            });
            Ok(())
        }
        _ => Err("usage: sharukhan builder lock | ensure | status".into()),
    };
    match r {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("sharukhan builder: {e}");
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_mode_defaults_to_the_host_and_refuses_unknown_values() {
        assert_eq!(parse_mode(None).unwrap(), Mode::Host);
        assert_eq!(parse_mode(Some("host")).unwrap(), Mode::Host);
        assert_eq!(parse_mode(Some("container")).unwrap(), Mode::Container);
        assert!(parse_mode(Some("docker")).unwrap_err().contains("host and container"));
    }

    #[test]
    fn propagation_is_read_from_the_top_mount_at_that_point() {
        let info = "\
22 1 8:32 / / rw,relatime - ext4 /dev/sdc rw
95 22 8:32 /root/photon-mc/gate /root/photon-mc/gate rw,relatime - ext4 /dev/sdc rw
96 22 8:32 /root/photon-mc/gate /root/photon-mc/gate rw,relatime shared:401 - ext4 /dev/sdc rw
97 22 0:50 / /mnt/a\\040b rw master:3 - 9p x rw
";
        assert_eq!(propagation(info, Path::new("/root/photon-mc/gate")).as_deref(), Some("shared"));
        assert_eq!(propagation(info, Path::new("/")).as_deref(), Some("private"));
        assert_eq!(propagation(info, Path::new("/mnt/a b")).as_deref(), Some("slave"));
        assert_eq!(propagation(info, Path::new("/root")), None);
    }

    #[test]
    fn a_lock_is_strict_and_a_directory_must_match_it_exactly() {
        assert!(parse_lock("abc  x.rpm\n").is_err());
        assert!(parse_lock("# only a comment\n").is_err());
        let t = std::env::temp_dir().join(format!("shk-builder-lock-{}", std::process::id()));
        let _ = fs::remove_dir_all(&t);
        fs::create_dir_all(&t).unwrap();
        fs::write(t.join("a.rpm"), "A").unwrap();
        let lock = parse_lock(&format!("{}  a.rpm\n", crate::sha256::bytes(b"A"))).unwrap();
        assert!(verify_dir(&t, &lock, ".rpm").is_ok());
        fs::write(t.join("b.rpm"), "B").unwrap();
        assert!(verify_dir(&t, &lock, ".rpm").unwrap_err().contains("b.rpm is not in the lock"));
        fs::remove_file(t.join("b.rpm")).unwrap();
        fs::write(t.join("a.rpm"), "changed").unwrap();
        assert!(verify_dir(&t, &lock, ".rpm").unwrap_err().contains("does not match the lock"));
        let _ = fs::remove_dir_all(&t);
    }

    #[test]
    fn the_embedded_wheel_pins_parse_and_the_hash_follows_every_input() {
        let pins = wheel_pins(WHEELS).unwrap();
        assert!(pins.iter().any(|(r, _, _)| r.starts_with("license_expression==")));
        let a = inputs_hash(BASE_IMAGE_ID, "x  a.rpm\n", "y  b.whl\n");
        assert_eq!(a, inputs_hash(BASE_IMAGE_ID, "x  a.rpm\n", "y  b.whl\n"));
        assert_ne!(a, inputs_hash(BASE_IMAGE_ID, "x  c.rpm\n", "y  b.whl\n"));
        assert_ne!(a, inputs_hash("sha256:other", "x  a.rpm\n", "y  b.whl\n"));
        assert_eq!(a.len(), 16);
    }

    #[test]
    fn tdnfs_transaction_table_is_read_for_names_only() {
        let t = "Installing:\ngdb-minimal      x86_64       17.1-4.ph5       photon-updates  10.26M     3.66M\n\
                 ca-certificates  noarch  20260414-2.ph5  photon  1M  1M\nTotal installed size: 1M\n";
        assert_eq!(transaction_names(t), vec!["ca-certificates", "gdb-minimal"]);
        assert!(transaction_names("nothing to do").is_empty());
    }

    #[test]
    fn the_container_make_mounts_the_shared_root_with_propagation_and_the_socket() {
        let c = container_make("img:x", Path::new("/r"), Path::new("/r/5.0"), &["-j8", "tini"]);
        let a: Vec<String> = c.get_args().map(|s| s.to_string_lossy().to_string()).collect();
        let j = a.join(" ");
        assert!(j.contains("--privileged"));
        assert!(j.contains("/var/run/docker.sock:/var/run/docker.sock"));
        assert!(j.contains("type=bind,src=/r,dst=/r,bind-propagation=rshared"));
        assert!(j.ends_with("-w /r/5.0 img:x make -j8 tini"), "{j}");
    }

    #[test]
    fn a_container_script_gets_its_environment_and_its_destination() {
        let c = container_script(
            "img:x",
            Path::new("/r"),
            Path::new("/r/work/run.sh"),
            &["/r/build-root".into(), "/mnt/c/iso".into()],
            &[("MC_POI_IMAGE", "poi:1")],
            &[PathBuf::from("/mnt/c/iso"), PathBuf::from("/r/inside")],
        );
        let j: Vec<String> = c.get_args().map(|s| s.to_string_lossy().to_string()).collect();
        let j = j.join(" ");
        assert!(j.contains("-v /mnt/c/iso:/mnt/c/iso"), "{j}");
        assert!(!j.contains("/r/inside:/r/inside"), "{j}");
        assert!(j.contains("-e MC_POI_IMAGE=poi:1"), "{j}");
        assert!(j.ends_with("img:x sh /r/work/run.sh /r/build-root /mnt/c/iso"), "{j}");
    }

    #[test]
    fn a_python_call_mounts_only_what_it_names_and_never_root() {
        let t = std::env::temp_dir().join(format!("shk-builder-py-{}", std::process::id()));
        fs::create_dir_all(t.join("a/b")).unwrap();
        let args: Vec<OsString> = vec![
            "-c".into(),
            t.join("a/b/missing.txt").into(),
            t.join("a").into(),
            "/r/inside".into(),
        ];
        let m = python_mounts(Path::new("/r"), Path::new("/r/x"), &args).unwrap();
        assert_eq!(m, vec![PathBuf::from("/r"), t.join("a")]);
        let bad: Vec<OsString> = vec!["/no-such-top-level-dir/x".into()];
        assert!(python_mounts(Path::new("/r"), Path::new("/r"), &bad).unwrap_err().contains("refusing to mount /"));
        let _ = fs::remove_dir_all(&t);
    }
}
