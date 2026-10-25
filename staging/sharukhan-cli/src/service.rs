//! `sharukhan service install | status | remove`: the host services, their
//! settings and their secrets, written by sharukhan instead of by hand.
//!
//! * `install [--sync] [--escalation-key-from-env] [--guest-password-from-env]`
//!   writes the settings file (every sharukhan setting of the invoking
//!   environment, nothing secret), the unit files rendered from templates in
//!   this binary, the gate-shared mount script when the builder runs in a
//!   container, and installs this binary. `--sync` adds the sync service and
//!   its timer; a sync reaches GATE, which installs VMs, so it needs the guest
//!   password file. The secrets are taken from the invoking environment only
//!   when asked, checked (the API key against the API), and written as secret
//!   files (crate::secret) that the settings file names; their values never
//!   reach a unit file, the settings file, an argv or the output.
//!   Running it again changes only what differs, and says what that is.
//! * `status` renders what `install` would write from the settings file on
//!   disk and compares: drift is visible, nothing is changed.
//! * `remove [--sync] [--key] [--guest-password]` disables and deletes the
//!   units (only the sync ones with --sync) and, when all go, the settings
//!   file; a secret file goes only when named. The binary stays.
//! * Nothing is installed or removed while a sync run, a gate or build job or
//!   an escalation is running: those processes run the installed binary.
//! * `--root <dir>` renders into a directory instead of / and leaves systemd
//!   alone (for review and tests); `--dry-run` writes nothing.

use std::collections::BTreeMap;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const ENV_FILE: &str = "/etc/sharukhan/sharukhan.env";
pub const KEY_FILE: &str = "/etc/sharukhan/secrets/anthropic-api-key";
pub const GUEST_FILE: &str = "/etc/sharukhan/secrets/guest-password";
pub const BIN: &str = "/usr/local/libexec/sharukhan/sharukhan";
const UNIT_DIR: &str = "/etc/systemd/system";
const SHARED_SCRIPT: &str = "/usr/local/sbin/photon-mc-gate-shared";
pub const WATCH: &str = "sharukhan-watch.service";
pub const SYNC: &str = "sharukhan-sync.service";
pub const TIMER: &str = "sharukhan-sync.timer";
pub const SHARED: &str = "photon-mc-gate-shared.service";

/// The settings a service carries when the invoking environment sets them.
pub const SETTINGS: &[&str] = &[
    "BOOT_DISK_ADAPTER",
    "BOOT_DISK_SIZE",
    "BOOT_DISK_TYPE",
    "GUEST_MEM_MB",
    "GUEST_VCPUS",
    "MC_AUTHOR",
    "MC_BUILD_COMMON",
    "MC_BUILDER",
    "MC_BUILDER_DIR",
    "MC_BUILDER_SHARED_ROOT",
    "MC_BUILD_LOG_DIR",
    "MC_BUILD_ROOT",
    "MC_BUILD_THREADS",
    "MC_CANISTER_NEVR",
    "MC_CHANGELOG_AUTHOR",
    "MC_COMMON_EDITS_ALLOWED",
    "MC_DHCP_LEASES",
    "MC_ESCALATE",
    "MC_ESC_ATTEMPTS",
    "MC_ESC_FALLBACK_MODEL",
    "MC_ESC_MAX_TURNS",
    "MC_ESC_MODEL",
    "MC_ESC_TOKENS_PER_DAY",
    "MC_ESC_TOKENS_PER_ESCALATION",
    "MC_ESC_TOKENS_PER_RUN",
    "MC_ESC_WEIGHT_CACHE_READ",
    "MC_ESC_WEIGHT_CACHE_WRITE_1H",
    "MC_ESC_WEIGHT_CACHE_WRITE_5M",
    "MC_FASTLOOP_ROWS",
    "MC_FORK",
    "MC_FORK_INSTALLER",
    "MC_GATE_REPO",
    "MC_INSTALLER_BRANCH",
    "MC_INSTALL_TIMEOUT_SEC",
    "MC_IP_BASE",
    "MC_ISO_CACHE",
    "MC_ISO_STORE",
    "MC_NET_CIDR",
    "MC_NET_DNS",
    "MC_NET_GATEWAY",
    "MC_NET_PREFIX",
    "MC_NET_V6_PREFIX",
    "MC_NET_VLAN_PREFIX",
    "MC_NIC_DEV",
    "MC_NOTIFY",
    "MC_PHOTON_REMOTE",
    "MC_POI_BASE_IMAGE",
    "MC_PUBLISH_DCASOTA",
    "MC_RELEASE",
    "MC_REMASTER_PHOTON_TREE",
    "MC_REMASTER_SOURCES",
    "MC_REMASTER_WORKDIR",
    "MC_RESULTS_DIR",
    "MC_RUN_LOG_DIR",
    "MC_STAGED_ROWS",
    "MC_START_TIMEOUT",
    "MC_UPSTREAM",
    "MC_UPSTREAM_INSTALLER",
    "MC_VARIANT_PATCH_DIR",
    "MC_VM_ROOT_WSL",
    "MC_VMX_TEMPLATE",
    "MC_WORK",
    "PHOTON_KERNEL_TREE",
    "PHOTON_SCRIPTS",
    "PHOTON_TREE",
    "POI_TREE",
    "SERIAL_LOG_PREFIX",
    "SHARUKHAN_CHECK_PRS",
    "SHARUKHAN_CLI_DIR",
    "SHARUKHAN_DB",
    "SHARUKHAN_KERNEL_CACHE",
    "SHARUKHAN_MATRIX",
    "SHARUKHAN_PHOTON_REPO",
    "SHARUKHAN_ROOT",
    "SHARUKHAN_VARIANTS",
    "SHARUKHAN_WRAPPER_PROFILES",
    "SHARUKHAN_WRAPPERS",
    "SSH_KEY_DIR",
    "SSH_KEY_NAME",
    "SSH_USER",
    "VDISKMANAGER",
    "VMRUN",
];

/// The secret files a service reads, named in the settings file.
pub const POINTERS: &[&str] = &["MC_ANTHROPIC_KEY_FILE", "MC_GUEST_PASSWORD_FILE"];

/// Values that never go into the settings file.
pub const SECRETS: &[&str] = &["MC_GUEST_PASSWORD", "ANTHROPIC_API_KEY", "GITHUB_TOKEN", "GH_TOKEN"];

/// The services' own options, kept in the settings file so `status` renders
/// what `install` wrote. HOME is where gh finds its login.
pub const OPTIONS: &[(&str, &str)] = &[
    ("HOME", ""),
    ("SHARUKHAN_WATCH_INTERVAL", "900"),
    ("SHARUKHAN_SYNC_EVERY", "30min"),
    ("SHARUKHAN_SYNC_QUIET", "7200"),
];

/// Where the files go: under `root` (normally /).
#[derive(Debug, Clone)]
pub struct Paths {
    pub root: PathBuf,
}

impl Paths {
    pub fn p(&self, abs: &str) -> PathBuf {
        self.root.join(abs.trim_start_matches('/'))
    }
    fn s(&self, abs: &str) -> String {
        self.p(abs).to_string_lossy().into_owned()
    }
    fn unit(&self, name: &str) -> PathBuf {
        self.p(UNIT_DIR).join(name)
    }
    fn live(&self) -> bool {
        self.root == Path::new("/")
    }
}

// --- the settings file --------------------------------------------------------

/// A value the settings file can hold: one line, nothing a shell or systemd
/// would expand or unquote, so the file can also be sourced.
pub fn valid_value(v: &str) -> bool {
    !v.chars().any(|c| c.is_control() || matches!(c, '"' | '\\' | '$' | '`'))
}

pub fn parse_env(text: &str) -> Result<BTreeMap<String, String>, String> {
    let mut m = BTreeMap::new();
    for (i, l) in text.lines().enumerate() {
        let l = l.trim();
        if l.is_empty() || l.starts_with('#') {
            continue;
        }
        let (k, v) = l.split_once('=').ok_or_else(|| format!("line {}: expected KEY=\"value\"", i + 1))?;
        let v = v.strip_prefix('"').and_then(|v| v.strip_suffix('"')).ok_or_else(|| format!("line {}: the value of {k} is not quoted", i + 1))?;
        m.insert(k.to_string(), v.to_string());
    }
    Ok(m)
}

pub fn render_env(m: &BTreeMap<String, String>) -> String {
    let mut s = String::from(
        "# Written by `sharukhan service install`; `sharukhan service status` compares it.\n\
         # The services' settings. Nothing secret: MC_*_FILE name secret files (0600).\n",
    );
    for (k, v) in m {
        s.push_str(&format!("{k}=\"{v}\"\n"));
    }
    s
}

fn known(k: &str) -> bool {
    SETTINGS.contains(&k) || POINTERS.contains(&k) || OPTIONS.iter().any(|o| o.0 == k)
}

/// What the install asks for besides the environment.
#[derive(Debug, Clone, Default)]
pub struct Opts {
    pub sync: bool,
    pub key_from_env: bool,
    pub guest_from_env: bool,
    pub unset: Vec<String>,
    pub watch_interval: Option<String>,
    pub sync_every: Option<String>,
    pub sync_quiet: Option<String>,
    pub dry_run: bool,
}

/// A systemd time span as the timer takes it: a number and a unit.
fn valid_span(v: &str) -> bool {
    let d = v.trim_end_matches(|c: char| c.is_ascii_alphabetic());
    let unit = &v[d.len()..];
    !d.is_empty() && d.chars().all(|c| c.is_ascii_digit()) && d != "0" && matches!(unit, "s" | "min" | "h" | "d")
}

/// The settings the services get: the existing file, then every setting of
/// the invoking environment, then the options. Returns notes on what changed.
pub fn settings(env: &dyn Fn(&str) -> Option<String>, existing: &BTreeMap<String, String>, o: &Opts, paths: &Paths) -> Result<(BTreeMap<String, String>, Vec<String>), String> {
    let mut m = BTreeMap::new();
    let mut notes = Vec::new();
    for (k, v) in existing {
        if known(k) {
            m.insert(k.clone(), v.clone());
        } else {
            notes.push(format!("{k} dropped: not a sharukhan setting"));
        }
    }
    let set = |m: &mut BTreeMap<String, String>, notes: &mut Vec<String>, k: &str, v: String| {
        match m.get(k) {
            Some(old) if *old == v => {}
            Some(_) => notes.push(format!("{k} changed")),
            None => notes.push(format!("{k} set")),
        }
        m.insert(k.to_string(), v);
    };
    for k in SETTINGS.iter().chain(POINTERS) {
        if let Some(v) = env(k).filter(|v| !v.is_empty()) {
            set(&mut m, &mut notes, k, v);
        }
    }
    for (k, default) in OPTIONS {
        let flag = match *k {
            "SHARUKHAN_WATCH_INTERVAL" => o.watch_interval.clone(),
            "SHARUKHAN_SYNC_EVERY" => o.sync_every.clone(),
            "SHARUKHAN_SYNC_QUIET" => o.sync_quiet.clone(),
            _ => env(k).filter(|v| !v.is_empty()),
        };
        match flag {
            Some(v) => set(&mut m, &mut notes, k, v),
            None if !m.contains_key(*k) && !default.is_empty() => set(&mut m, &mut notes, k, default.to_string()),
            None => {}
        }
    }
    if o.key_from_env {
        set(&mut m, &mut notes, "MC_ANTHROPIC_KEY_FILE", paths.s(KEY_FILE));
    }
    if o.guest_from_env {
        set(&mut m, &mut notes, "MC_GUEST_PASSWORD_FILE", paths.s(GUEST_FILE));
    }
    for k in &o.unset {
        if !known(k) {
            return Err(format!("--unset {k}: not a sharukhan setting"));
        }
        if m.remove(k).is_some() {
            notes.push(format!("{k} unset"));
        }
    }
    // checks: nothing secret, nothing a file cannot hold, options in range
    for k in SECRETS {
        if m.contains_key(*k) {
            return Err(format!("{k} is secret and never goes into the settings file"));
        }
    }
    for (k, v) in &m {
        if !valid_value(v) {
            return Err(format!("{k}: the value holds a quote, backslash, $, ` or a control character"));
        }
    }
    if !m.contains_key("HOME") {
        return Err("HOME is not set: the services need it to find gh's login".into());
    }
    let num = |k: &str| m.get(k).map(|v| v.parse::<u64>().ok().filter(|n| *n > 0).ok_or_else(|| format!("{k}={v}: a positive number of seconds"))).transpose();
    num("SHARUKHAN_WATCH_INTERVAL")?;
    num("SHARUKHAN_SYNC_QUIET")?;
    if let Some(v) = m.get("SHARUKHAN_SYNC_EVERY") {
        if !valid_span(v) {
            return Err(format!("SHARUKHAN_SYNC_EVERY={v}: a time span like 30min, 1h or 900s"));
        }
    }
    crate::builder::parse_mode(m.get("MC_BUILDER").map(String::as_str))?;
    crate::escalate::parse_enabled(m.get("MC_ESCALATE").map(String::as_str))?;
    if let Some(n) = m.get("MC_NOTIFY") {
        crate::watch::parse_channels(Some(n))?;
    }
    Ok((m, notes))
}

// --- the units ----------------------------------------------------------------

const HEADER: &str = "# Written by `sharukhan service install`; `sharukhan service status` compares it.\n";

/// A file `install` writes: where, what, its mode.
#[derive(Debug, Clone, PartialEq)]
pub struct File {
    pub path: PathBuf,
    pub text: String,
    pub mode: u32,
}

fn shared_root(m: &BTreeMap<String, String>) -> String {
    m.get("MC_BUILDER_SHARED_ROOT").cloned().unwrap_or_else(|| crate::builder::DEFAULT_SHARED_ROOT.to_string())
}

fn container(m: &BTreeMap<String, String>) -> bool {
    crate::builder::parse_mode(m.get("MC_BUILDER").map(String::as_str)) == Ok(crate::builder::Mode::Container)
}

/// Every file of the services for these settings.
pub fn files(paths: &Paths, m: &BTreeMap<String, String>, sync: bool) -> Vec<File> {
    let bin = paths.s(BIN);
    let env = paths.s(ENV_FILE);
    let opt = |k: &str| m.get(k).cloned().unwrap_or_default();
    let mut v = vec![File { path: paths.p(ENV_FILE), text: render_env(m), mode: 0o644 }];
    let shared = container(m);
    if shared {
        let d = shared_root(m);
        v.push(File {
            path: paths.p(SHARED_SCRIPT),
            text: format!(
                "#!/bin/bash\n{}\
                 # Make {d} a bind mount with shared propagation. The sharukhan builder\n\
                 # container runs Photon's package builder, whose tdnf sandbox is a sibling container on the\n\
                 # host's docker daemon; mounts the builder makes under this directory must reach the host.\n\
                 # WSL's root mount is private and a WSL restart drops the bind, so this runs at every boot.\n\
                 # Idempotent: an existing bind is kept, only its propagation is (re)set and then verified.\n\
                 set -euo pipefail\n\
                 d={d}\n\
                 [ -d \"$d\" ] || {{ echo \"$d does not exist\" >&2; exit 1; }}\n\
                 mountpoint -q \"$d\" || mount --bind \"$d\" \"$d\"\n\
                 mount --make-rshared \"$d\"\n\
                 p=$(findmnt -n -o PROPAGATION --mountpoint \"$d\")\n\
                 [ \"$p\" = shared ] || {{ echo \"$d propagation is '$p', not shared\" >&2; exit 1; }}\n\
                 echo \"$d: bind mount, propagation $p\"\n",
                HEADER
            ),
            mode: 0o755,
        });
        v.push(File {
            path: paths.unit(SHARED),
            text: format!(
                "{HEADER}[Unit]\nDescription=Shared bind mount of {d} for the sharukhan builder container\nAfter=local-fs.target\nBefore=docker.service\nRequiresMountsFor={d}\n\n\
                 [Service]\nType=oneshot\nRemainAfterExit=yes\nExecStart={}\n\n[Install]\nWantedBy=multi-user.target\n",
                paths.s(SHARED_SCRIPT)
            ),
            mode: 0o644,
        });
    }
    v.push(File {
        path: paths.unit(WATCH),
        text: format!(
            "{HEADER}[Unit]\nDescription=sharukhan watch: fork and upstream heads and the fork's PRs as events in memory.db\nAfter=network-online.target\nWants=network-online.target\n\n\
             [Service]\nType=simple\n# gh reads its on-disk login under HOME; no token is passed in the environment.\nEnvironmentFile={env}\nExecStart={bin} watch --interval {}\nRestart=on-failure\nRestartSec=300\nNice=10\n\n\
             [Install]\nWantedBy=multi-user.target\n",
            opt("SHARUKHAN_WATCH_INTERVAL")
        ),
        mode: 0o644,
    });
    if sync {
        let after = if shared { format!("docker.service {SHARED} {WATCH}") } else { format!("docker.service {WATCH}") };
        v.push(File {
            path: paths.unit(SYNC),
            text: format!(
                "{HEADER}[Unit]\nDescription=sharukhan sync auto: start a sync when the fork's base moved and stayed quiet\nAfter=network-online.target {after}\nWants=network-online.target\n\n\
                 [Service]\nType=oneshot\nEnvironmentFile={env}\nExecStart={bin} sync auto\n# builds and the gate take hours; a oneshot never overlaps itself\nTimeoutStartSec=infinity\nNice=5\n"
            ),
            mode: 0o644,
        });
        let every = opt("SHARUKHAN_SYNC_EVERY");
        v.push(File {
            path: paths.unit(TIMER),
            text: format!(
                "{HEADER}[Unit]\nDescription=Check every {every} whether a sync should start\n\n[Timer]\nOnBootSec=15min\nOnUnitActiveSec={every}\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n"
            ),
            mode: 0o644,
        });
    }
    v
}

// --- what is running ------------------------------------------------------------

/// What runs the installed binary now, if anything: a sync run, a job, an
/// escalation. Replacing the binary or the units under them is refused.
pub fn busy(db: &Path) -> Result<Vec<String>, String> {
    if !db.exists() {
        return Ok(Vec::new());
    }
    let c = crate::job::open_rw(db)?;
    let alive = |pid: Option<i64>| pid.is_some_and(|p| crate::proc::alive(p as i32) && crate::proc::looks_like_sharukhan(p as i32));
    let mut v = Vec::new();
    let has = |t: &str| c.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1").and_then(|mut s| s.exists([t])).unwrap_or(false);
    if has("sync_run") {
        let rows: Vec<(i64, Option<i64>)> = c
            .prepare("SELECT id, pid FROM sync_run WHERE state = 'running'")
            .and_then(|mut s| s.query_map([], |r| Ok((r.get(0)?, r.get(1)?))).map(|x| x.flatten().collect()))
            .map_err(|e| format!("{e}"))?;
        v.extend(rows.into_iter().filter(|r| alive(r.1)).map(|r| format!("sync run {}", r.0)));
    }
    v.extend(crate::job::live(&c)?);
    if has("escalation") {
        let rows: Vec<(i64, i64, Option<i64>)> = c
            .prepare("SELECT run_id, pr, pid FROM escalation WHERE outcome = 'running'")
            .and_then(|mut s| s.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).map(|x| x.flatten().collect()))
            .map_err(|e| format!("{e}"))?;
        v.extend(rows.into_iter().filter(|r| alive(r.2)).map(|r| format!("escalation of run {} #{}", r.0, r.1)));
    }
    Ok(v)
}

// --- writing --------------------------------------------------------------------

fn write_atomic(p: &Path, data: &[u8], mode: u32) -> Result<(), String> {
    let dir = p.parent().ok_or_else(|| format!("{}: no directory", p.display()))?;
    fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    let tmp = dir.join(format!(".{}.{}.new", p.file_name().and_then(|n| n.to_str()).unwrap_or("f"), std::process::id()));
    fs::write(&tmp, data).map_err(|e| format!("{}: {e}", tmp.display()))?;
    let done = fs::set_permissions(&tmp, fs::Permissions::from_mode(mode)).and_then(|_| fs::File::open(&tmp)?.sync_all()).and_then(|_| fs::rename(&tmp, p));
    if let Err(e) = done {
        let _ = fs::remove_file(&tmp);
        return Err(format!("{}: {e}", p.display()));
    }
    Ok(())
}

/// The lines of `new` that `old` lacks and the reverse, for a short report.
fn changed_lines(old: &str, new: &str) -> Vec<String> {
    let o: Vec<&str> = old.lines().collect();
    let n: Vec<&str> = new.lines().collect();
    let mut v: Vec<String> = o.iter().filter(|l| !n.contains(l)).map(|l| format!("    - {l}")).collect();
    v.extend(n.iter().filter(|l| !o.contains(l)).map(|l| format!("    + {l}")));
    v
}

#[derive(Debug, PartialEq)]
pub enum State {
    Current,
    Missing,
    Differs(Vec<String>),
}

pub fn compare(f: &File) -> State {
    match fs::read_to_string(&f.path) {
        Err(_) => State::Missing,
        Ok(t) if t == f.text => {
            let mode_ok = fs::metadata(&f.path).map(|m| m.permissions().mode() & 0o777 == f.mode).unwrap_or(false);
            if mode_ok {
                State::Current
            } else {
                State::Differs(vec![format!("    mode is not {:o}", f.mode)])
            }
        }
        Ok(t) => State::Differs(changed_lines(&t, &f.text)),
    }
}

fn systemctl(args: &[&str]) -> Result<String, String> {
    let o = Command::new("systemctl").args(args).output().map_err(|e| format!("systemctl: {e}"))?;
    if !o.status.success() {
        return Err(format!("systemctl {}: {}", args.join(" "), String::from_utf8_lossy(&o.stderr).trim()));
    }
    Ok(String::from_utf8_lossy(&o.stdout).trim().to_string())
}

fn unit_state(name: &str) -> String {
    let q = |a: &str| Command::new("systemctl").args([a, name]).output().map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string()).unwrap_or_default();
    format!("{}, {}", q("is-enabled"), q("is-active"))
}

fn same_file(a: &Path, b: &Path) -> bool {
    matches!((fs::canonicalize(a), fs::canonicalize(b)), (Ok(x), Ok(y)) if x == y)
}

/// Install or update; returns the report lines.
pub fn install(paths: &Paths, o: &Opts, env: &dyn Fn(&str) -> Option<String>, db: &Path) -> Result<Vec<String>, String> {
    let mut out = Vec::new();
    if paths.live() && !crate::syncrun::in_host_namespace() {
        return Err("run `sharukhan service install` in the host mount namespace (nsenter --target 1 --mount)".into());
    }
    let running = busy(db)?;
    if !running.is_empty() {
        return Err(format!("{} running on the installed binary; install when it is finished", running.join(", ")));
    }
    let existing = match fs::read_to_string(paths.p(ENV_FILE)) {
        Ok(t) => parse_env(&t).map_err(|e| format!("{}: {e}", paths.p(ENV_FILE).display()))?,
        Err(_) => BTreeMap::new(),
    };
    let had_sync = paths.unit(SYNC).exists() || paths.unit(TIMER).exists();
    let (m, notes) = settings(env, &existing, o, paths)?;

    // the secrets, checked before anything is written
    let key = if o.key_from_env {
        let k = env("ANTHROPIC_API_KEY").map(|k| k.trim().to_string()).filter(|k| !k.is_empty()).ok_or("--escalation-key-from-env: ANTHROPIC_API_KEY is not set")?;
        if !crate::escalate::key_shape_ok(&k) {
            return Err("--escalation-key-from-env: ANTHROPIC_API_KEY does not have the shape of an Anthropic API key".into());
        }
        crate::escalate::key_accepted(&k)?;
        out.push("API key: accepted by the API".into());
        Some(k)
    } else {
        None
    };
    let guest = if o.guest_from_env {
        Some(env("MC_GUEST_PASSWORD").filter(|v| !v.is_empty()).ok_or("--guest-password-from-env: MC_GUEST_PASSWORD is not set")?)
    } else {
        None
    };
    let sync = o.sync || had_sync;
    if sync && guest.is_none() {
        match m.get("MC_GUEST_PASSWORD_FILE") {
            None => return Err("a sync reaches GATE, which installs VMs: pass --guest-password-from-env (MC_GUEST_PASSWORD set) or set MC_GUEST_PASSWORD_FILE".into()),
            Some(p) => crate::secret::check(Path::new(p)).map_err(|e| format!("MC_GUEST_PASSWORD_FILE: {e}"))?,
        }
    }
    if key.is_none() {
        if let Some(p) = m.get("MC_ANTHROPIC_KEY_FILE") {
            crate::secret::check(Path::new(p)).map_err(|e| format!("MC_ANTHROPIC_KEY_FILE: {e}"))?;
        } else if sync && crate::escalate::parse_enabled(m.get("MC_ESCALATE").map(String::as_str))? {
            out.push("note: no API key file: a sync that stops for a decision parks its escalation (--escalation-key-from-env)".into());
        }
    }
    if had_sync && !o.sync {
        out.push("note: the sync units are installed and kept current; `sharukhan service remove --sync` removes them".into());
    }
    for n in &notes {
        out.push(format!("setting: {n}"));
    }

    let wanted = files(paths, &m, sync);
    let mut changed: Vec<PathBuf> = Vec::new();
    for f in &wanted {
        match compare(f) {
            State::Current => out.push(format!("{}: unchanged", f.path.display())),
            State::Missing => {
                out.push(format!("{}: created", f.path.display()));
                changed.push(f.path.clone());
            }
            State::Differs(lines) => {
                out.push(format!("{}: updated", f.path.display()));
                out.extend(lines);
                changed.push(f.path.clone());
            }
        }
    }
    let exe = std::env::current_exe().map_err(|e| format!("current_exe: {e}"))?;
    let bin = paths.p(BIN);
    let bin_changes = !same_file(&exe, &bin) && (!bin.exists() || crate::sha256::file(&exe)? != crate::sha256::file(&bin)?);
    out.push(format!("{}: {}", bin.display(), if bin_changes { "replaced by this build" } else { "is this build" }));
    if o.dry_run {
        out.push("dry run: nothing written".into());
        return Ok(out);
    }

    if let Some(k) = &key {
        crate::secret::write(&paths.p(KEY_FILE), k)?;
        out.push(format!("{}: written (0600)", paths.p(KEY_FILE).display()));
    }
    if let Some(g) = &guest {
        crate::secret::write(&paths.p(GUEST_FILE), g)?;
        out.push(format!("{}: written (0600)", paths.p(GUEST_FILE).display()));
    }
    if bin_changes {
        let data = fs::read(&exe).map_err(|e| format!("{}: {e}", exe.display()))?;
        write_atomic(&bin, &data, 0o755)?;
    }
    for f in wanted.iter().filter(|f| changed.contains(&f.path)) {
        write_atomic(&f.path, f.text.as_bytes(), f.mode)?;
    }
    if !paths.live() {
        out.push(format!("--root {}: systemd left alone", paths.root.display()));
        return Ok(out);
    }
    systemctl(&["daemon-reload"])?;
    let shared = container(&m);
    let touched = |name: &str| changed.iter().any(|p| p.ends_with(name));
    if shared {
        systemctl(&["enable", "--now", SHARED])?;
        if touched(SHARED) || touched("photon-mc-gate-shared") {
            systemctl(&["restart", SHARED])?;
        }
    }
    systemctl(&["enable", "--now", WATCH])?;
    if touched(WATCH) || touched("sharukhan.env") || bin_changes {
        systemctl(&["restart", WATCH])?;
        out.push(format!("{WATCH}: restarted"));
    }
    if sync {
        systemctl(&["enable", "--now", TIMER])?;
    }
    for u in [Some(SHARED).filter(|_| shared), Some(WATCH), Some(TIMER).filter(|_| sync)].into_iter().flatten() {
        out.push(format!("{u}: {}", unit_state(u)));
    }
    Ok(out)
}

/// Compare what is installed with what `install` would write from the
/// settings file on disk. Returns the lines and whether anything differs.
pub fn status(paths: &Paths) -> Result<(Vec<String>, bool), String> {
    let envp = paths.p(ENV_FILE);
    let Ok(text) = fs::read_to_string(&envp) else {
        return Ok((vec![format!("{} missing: not installed by `sharukhan service install`", envp.display())], true));
    };
    let m = parse_env(&text).map_err(|e| format!("{}: {e}", envp.display()))?;
    let sync = paths.unit(SYNC).exists() || paths.unit(TIMER).exists();
    let mut out = Vec::new();
    let mut drift = false;
    for f in files(paths, &m, sync) {
        match compare(&f) {
            State::Current => out.push(format!("{}: current", f.path.display())),
            State::Missing => {
                drift = true;
                out.push(format!("{}: missing", f.path.display()));
            }
            State::Differs(lines) => {
                drift = true;
                out.push(format!("{}: differs from what install writes", f.path.display()));
                out.extend(lines);
            }
        }
    }
    for k in POINTERS {
        if let Some(p) = m.get(*k) {
            let d = crate::secret::describe(Path::new(p));
            drift |= !d.ends_with("present (0600)");
            out.push(format!("{k}: {d}"));
        }
    }
    let exe = std::env::current_exe().map_err(|e| format!("current_exe: {e}"))?;
    let bin = paths.p(BIN);
    let same = same_file(&exe, &bin) || (bin.exists() && crate::sha256::file(&exe)? == crate::sha256::file(&bin)?);
    out.push(format!("{}: {}", bin.display(), if same { "is this build" } else { "differs from this build" }));
    if paths.live() {
        let shared = container(&m);
        for u in [Some(SHARED).filter(|_| shared), Some(WATCH), Some(SYNC).filter(|_| sync), Some(TIMER).filter(|_| sync)].into_iter().flatten() {
            out.push(format!("{u}: {}", unit_state(u)));
        }
    }
    Ok((out, drift))
}

pub fn remove(paths: &Paths, sync_only: bool, key: bool, guest: bool, dry_run: bool, db: &Path) -> Result<Vec<String>, String> {
    if paths.live() && !crate::syncrun::in_host_namespace() {
        return Err("run `sharukhan service remove` in the host mount namespace (nsenter --target 1 --mount)".into());
    }
    let running = busy(db)?;
    if !running.is_empty() {
        return Err(format!("{} running; remove when it is finished", running.join(", ")));
    }
    let mut units = vec![TIMER, SYNC];
    if !sync_only {
        units.extend([WATCH, SHARED]);
    }
    let mut out = Vec::new();
    let mut gone: Vec<PathBuf> = units.iter().map(|u| paths.unit(u)).collect();
    if !sync_only {
        gone.push(paths.p(SHARED_SCRIPT));
        gone.push(paths.p(ENV_FILE));
    }
    if key {
        gone.push(paths.p(KEY_FILE));
    }
    if guest {
        gone.push(paths.p(GUEST_FILE));
    }
    let present: Vec<&PathBuf> = gone.iter().filter(|p| p.exists()).collect();
    for p in &present {
        out.push(format!("{}: {}", p.display(), if dry_run { "would be removed" } else { "removed" }));
    }
    // a kept settings file must not name a removed secret
    let envp = paths.p(ENV_FILE);
    let mut kept_env = None;
    if sync_only && (key || guest) {
        if let Ok(t) = fs::read_to_string(&envp) {
            let mut m = parse_env(&t)?;
            if key && m.remove("MC_ANTHROPIC_KEY_FILE").is_some() {
                out.push("MC_ANTHROPIC_KEY_FILE removed from the settings".into());
            }
            if guest && m.remove("MC_GUEST_PASSWORD_FILE").is_some() {
                out.push("MC_GUEST_PASSWORD_FILE removed from the settings".into());
            }
            kept_env = Some(render_env(&m));
        }
    }
    if dry_run {
        out.push("dry run: nothing changed".into());
        return Ok(out);
    }
    if paths.live() {
        for u in &units {
            if paths.unit(u).exists() {
                systemctl(&["disable", "--now", u])?;
            }
        }
    }
    for p in present {
        fs::remove_file(p).map_err(|e| format!("{}: {e}", p.display()))?;
    }
    if let Some(t) = kept_env {
        write_atomic(&envp, t.as_bytes(), 0o644)?;
    }
    if paths.live() {
        systemctl(&["daemon-reload"])?;
    }
    out.push(format!("{} stays (`sharukhan service install` puts the rest back)", paths.p(BIN).display()));
    Ok(out)
}

pub fn cli(cfg: &crate::config::Config, args: &[String]) -> Result<(), String> {
    let usage = "sharukhan service install [--sync] [--escalation-key-from-env] [--guest-password-from-env] [--unset KEY]... \
                 [--watch-interval S] [--sync-every SPAN] [--sync-quiet S] [--root DIR] [--dry-run]\n\
                 sharukhan service status [--root DIR]\n\
                 sharukhan service remove [--sync] [--key] [--guest-password] [--root DIR] [--dry-run]";
    let has = |f: &str| args.iter().any(|a| a == f);
    let val = |f: &str| args.iter().position(|a| a == f).and_then(|i| args.get(i + 1)).cloned();
    let root = PathBuf::from(val("--root").unwrap_or_else(|| "/".into()));
    if !root.is_absolute() {
        return Err("--root takes an absolute directory".into());
    }
    let paths = Paths { root };
    // every argument must be understood: a typo is not a default
    let flags = ["--sync", "--escalation-key-from-env", "--guest-password-from-env", "--dry-run", "--key", "--guest-password"];
    let valued = ["--unset", "--watch-interval", "--sync-every", "--sync-quiet", "--root"];
    let mut i = 1;
    while i < args.len() {
        if valued.contains(&args[i].as_str()) {
            i += 2;
        } else if flags.contains(&args[i].as_str()) {
            i += 1;
        } else {
            return Err(format!("{}: unknown argument\n{usage}", args[i]));
        }
    }
    let lines = match args.first().map(String::as_str) {
        Some("install") => {
            let o = Opts {
                sync: has("--sync"),
                key_from_env: has("--escalation-key-from-env"),
                guest_from_env: has("--guest-password-from-env"),
                unset: args.iter().enumerate().filter(|(_, a)| *a == "--unset").filter_map(|(i, _)| args.get(i + 1).cloned()).collect(),
                watch_interval: val("--watch-interval"),
                sync_every: val("--sync-every"),
                sync_quiet: val("--sync-quiet"),
                dry_run: has("--dry-run"),
            };
            install(&paths, &o, &|k| std::env::var(k).ok(), &cfg.memory_db)?
        }
        Some("status") => {
            let (lines, drift) = status(&paths)?;
            for l in lines {
                println!("{l}");
            }
            return if drift { Err("the installed services differ from what `sharukhan service install` writes".into()) } else { Ok(()) };
        }
        Some("remove") => remove(&paths, has("--sync"), has("--key"), has("--guest-password"), has("--dry-run"), &cfg.memory_db)?,
        _ => return Err(usage.into()),
    };
    for l in lines {
        println!("{l}");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("shk-service-{tag}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    fn env_of(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
        let m: BTreeMap<String, String> = pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
        move |k: &str| m.get(k).cloned()
    }

    /// Every environment variable the sources read is classified: a setting
    /// the services carry, a secret pointer, a secret, an option, or named
    /// here as not a service setting. A new setting cannot be forgotten.
    #[test]
    fn every_variable_the_code_reads_is_classified() {
        let not_settings = [
            "PATH",
            "MESSAGE",
            "XDG_CACHE_HOME",
            "SHK_CONSOLE_VMX",
            "SHK_ISO",
            "MC_TEST_ISO_MOUNT",
            "MC_TEST_KERNEL_IMAGE",
            "SHARUKHAN_LIVE_BUILD_ROOT",
            "SHARUKHAN_LIVE_REPO",
            "SHARUKHAN_LIVE_SPECS",
            // kernel config symbols read with Config::get, not the environment
            "HYPERV",
            "HYPERV_STORAGE",
            "LOCALVERSION",
        ];
        let src = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
        let mut stack = vec![src];
        let mut names = std::collections::BTreeSet::new();
        while let Some(d) = stack.pop() {
            for e in fs::read_dir(&d).unwrap().flatten() {
                let p = e.path();
                if p.is_dir() {
                    stack.push(p);
                    continue;
                }
                if p.extension().and_then(|x| x.to_str()) != Some("rs") || p.ends_with("service.rs") {
                    continue;
                }
                let t = fs::read_to_string(&p).unwrap();
                for pat in ["var(\"", "var_os(\"", "get(\"", "get, \"", " n(\"", " s(\"", " f(\""] {
                    for (i, _) in t.match_indices(pat) {
                        // a method call (`.get("FIELD")`) reads JSON or a kernel config, not the environment
                        if pat == "get(\"" && t[..i].ends_with('.') {
                            continue;
                        }
                        // short helper closures (`n("X")`) read the environment only in a file that reads it
                        if pat.starts_with(' ') && !t.contains("env::var") {
                            continue;
                        }
                        let rest = &t[i + pat.len()..];
                        let name: String = rest.chars().take_while(|c| *c != '"').collect();
                        if name.len() >= 3 && name.chars().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_') && name.contains('_') || ["VMRUN", "HOME"].contains(&name.as_str()) {
                            names.insert(name);
                        }
                    }
                }
            }
        }
        let unclassified: Vec<&String> = names
            .iter()
            .filter(|n| !known(n) && !SECRETS.contains(&n.as_str()) && !not_settings.contains(&n.as_str()))
            .collect();
        assert!(unclassified.is_empty(), "classify in service.rs: {unclassified:?}");
        assert!(names.len() > 60, "the scan found {} names: it no longer sees the reads", names.len());
    }

    #[test]
    fn settings_take_the_environment_and_never_a_secret() {
        let paths = Paths { root: "/".into() };
        let env = env_of(&[("HOME", "/root"), ("MC_ISO_STORE", "/mnt/c/x"), ("MC_GUEST_PASSWORD", "pw"), ("ANTHROPIC_API_KEY", "k"), ("UNRELATED", "u"), ("MC_AUTHOR", "A B <a@b>")]);
        let mut existing = BTreeMap::new();
        existing.insert("MC_WORK".to_string(), "/w".to_string());
        existing.insert("STALE".to_string(), "x".to_string());
        let o = Opts { key_from_env: true, guest_from_env: true, ..Opts::default() };
        let (m, notes) = settings(&env, &existing, &o, &paths).unwrap();
        assert_eq!(m.get("MC_ISO_STORE").unwrap(), "/mnt/c/x");
        assert_eq!(m.get("MC_WORK").unwrap(), "/w", "kept from the file");
        assert_eq!(m.get("MC_ANTHROPIC_KEY_FILE").unwrap(), KEY_FILE);
        assert_eq!(m.get("MC_GUEST_PASSWORD_FILE").unwrap(), GUEST_FILE);
        assert_eq!(m.get("SHARUKHAN_SYNC_EVERY").unwrap(), "30min");
        assert!(!m.contains_key("MC_GUEST_PASSWORD") && !m.contains_key("ANTHROPIC_API_KEY") && !m.contains_key("UNRELATED") && !m.contains_key("STALE"));
        assert!(notes.iter().any(|n| n == "STALE dropped: not a sharukhan setting"));
        let text = render_env(&m);
        assert!(!text.contains("=\"pw\"") && !text.contains("=\"k\""));
        assert_eq!(parse_env(&text).unwrap(), m, "the file reads back as written");
        // refusals
        let bad = env_of(&[("HOME", "/root"), ("MC_AUTHOR", "a\"b")]);
        assert!(settings(&bad, &BTreeMap::new(), &Opts::default(), &paths).unwrap_err().contains("MC_AUTHOR"));
        let bad = env_of(&[("HOME", "/root"), ("MC_ESCALATE", "maybe")]);
        assert!(settings(&bad, &BTreeMap::new(), &Opts::default(), &paths).is_err());
        let o = Opts { sync_every: Some("30".into()), ..Opts::default() };
        assert!(settings(&env_of(&[("HOME", "/root")]), &BTreeMap::new(), &o, &paths).unwrap_err().contains("SHARUKHAN_SYNC_EVERY"));
        let o = Opts { unset: vec!["NOPE".into()], ..Opts::default() };
        assert!(settings(&env_of(&[("HOME", "/root")]), &BTreeMap::new(), &o, &paths).is_err());
        assert!(settings(&env_of(&[]), &BTreeMap::new(), &Opts::default(), &paths).unwrap_err().contains("HOME"));
        assert!(valid_span("30min") && valid_span("1h") && !valid_span("0min") && !valid_span("min") && !valid_span("5 min"));
    }

    #[test]
    fn units_follow_the_settings() {
        let paths = Paths { root: "/".into() };
        let env = env_of(&[("HOME", "/root"), ("MC_BUILDER", "container"), ("MC_BUILDER_SHARED_ROOT", "/g")]);
        let (m, _) = settings(&env, &BTreeMap::new(), &Opts { sync_every: Some("1h".into()), ..Opts::default() }, &paths).unwrap();
        let f = files(&paths, &m, true);
        let names: Vec<String> = f.iter().map(|f| f.path.to_string_lossy().into_owned()).collect();
        assert_eq!(
            names,
            [ENV_FILE, SHARED_SCRIPT, "/etc/systemd/system/photon-mc-gate-shared.service", "/etc/systemd/system/sharukhan-watch.service", "/etc/systemd/system/sharukhan-sync.service", "/etc/systemd/system/sharukhan-sync.timer"]
        );
        assert!(f[1].text.contains("\nd=/g\n") && f[1].mode == 0o755);
        assert!(f[3].text.contains(&format!("ExecStart={BIN} watch --interval 900")) && f[3].text.contains(&format!("EnvironmentFile={ENV_FILE}")));
        assert!(f[4].text.contains(&format!("ExecStart={BIN} sync auto")) && f[4].text.contains(SHARED));
        assert!(f[5].text.contains("OnUnitActiveSec=1h"));
        for x in &f {
            assert!(!x.text.contains("source") && !x.text.contains("env-isolated"), "no shell profile is sourced");
        }
        let host = env_of(&[("HOME", "/root")]);
        let (m, _) = settings(&host, &BTreeMap::new(), &Opts::default(), &paths).unwrap();
        assert_eq!(files(&paths, &m, false).len(), 2, "host builder, no sync: settings and watch only");
    }

    #[test]
    fn install_into_a_root_writes_once_and_status_then_agrees() {
        let d = tmp("install");
        let paths = Paths { root: d.clone() };
        let db = d.join("no.db");
        let env = env_of(&[("HOME", "/root"), ("MC_GUEST_PASSWORD", "guest-secret"), ("MC_ISO_STORE", "/iso")]);
        // a sync without a guest password is refused before anything is written
        let e = install(&paths, &Opts { sync: true, ..Opts::default() }, &env, &db).unwrap_err();
        assert!(e.contains("guest-password-from-env"), "{e}");
        assert!(!paths.p(ENV_FILE).exists());
        let o = Opts { sync: true, guest_from_env: true, ..Opts::default() };
        let dry = install(&paths, &Opts { dry_run: true, ..o.clone() }, &env, &db).unwrap();
        assert!(dry.iter().any(|l| l == "dry run: nothing written") && !paths.p(ENV_FILE).exists());
        let out = install(&paths, &o, &env, &db).unwrap();
        assert!(out.iter().all(|l| !l.contains("guest-secret")), "the secret is never reported");
        assert_eq!(crate::secret::read(&paths.p(GUEST_FILE)).unwrap(), "guest-secret");
        let envtext = fs::read_to_string(paths.p(ENV_FILE)).unwrap();
        assert!(!envtext.contains("guest-secret") && envtext.contains("MC_GUEST_PASSWORD_FILE="));
        let (lines, drift) = status(&paths).unwrap();
        assert!(!drift, "{lines:?}");
        // again: nothing changes; the sync units are kept without --sync
        let again = install(&paths, &Opts::default(), &env_of(&[("HOME", "/root")]), &db).unwrap();
        assert!(again.iter().filter(|l| l.ends_with(": created") || l.ends_with(": updated")).count() == 0, "{again:?}");
        // a hand edit is drift
        fs::write(paths.unit(TIMER), "edited\n").unwrap();
        let (lines, drift) = status(&paths).unwrap();
        assert!(drift && lines.iter().any(|l| l.contains("differs")));
        // remove the sync part with its secret: the settings stop naming it
        remove(&paths, true, false, true, false, &db).unwrap();
        assert!(!paths.unit(SYNC).exists() && !paths.p(GUEST_FILE).exists() && paths.unit(WATCH).exists());
        assert!(!fs::read_to_string(paths.p(ENV_FILE)).unwrap().contains("MC_GUEST_PASSWORD_FILE"));
        remove(&paths, false, false, false, false, &db).unwrap();
        assert!(!paths.unit(WATCH).exists() && !paths.p(ENV_FILE).exists());
        let _ = fs::remove_dir_all(&d);
    }
}
