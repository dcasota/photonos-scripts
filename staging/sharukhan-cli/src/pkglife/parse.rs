//! Parsers for what the guest's own tools print. Each is tested against output
//! captured from a real Photon 5.0 guest (k09, 2026-09-27), and each refuses
//! input it does not understand rather than returning an empty answer - an
//! empty answer is exactly what a vacuous check is made of.

use std::collections::{BTreeMap, BTreeSet};

/// One package as tdnf's JSON describes it.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Pkg {
    pub name: String,
    pub arch: String,
    /// Normalised: an explicit zero epoch is dropped, as rpm prints it.
    pub evr: String,
    pub repo: String,
}

impl Pkg {
    /// name-version-release.arch, the identity two package sets are compared
    /// by. The epoch is left out ON PURPOSE: tdnf's JSON omits it while rpm
    /// reports it (measured on nginx: tdnf `1.30.4-2.ph5`, rpm `1:1.30.4-2.ph5`),
    /// and one name-version-release.arch never exists with two epochs on one
    /// medium.
    pub fn key(&self) -> String {
        let vr = self.evr.split_once(':').map(|x| x.1).unwrap_or(&self.evr);
        format!("{}-{vr}.{}", self.name, self.arch)
    }
}

/// A key written by an older build (with `E:` after the name) in today's
/// epoch-free form, so baseline files stay readable.
pub fn strip_epoch_key(k: &str) -> String {
    if let Some(colon) = k.find(':') {
        let dash = k[..colon].rfind('-').map(|d| d + 1).unwrap_or(0);
        if colon > dash && k[dash..colon].chars().all(|c| c.is_ascii_digit()) {
            return format!("{}{}", &k[..dash], &k[colon + 1..]);
        }
    }
    k.to_string()
}

/// `systemctl list-unit-files -o json`: the unit file names.
pub fn unit_files_json(stdout: &str) -> Result<BTreeSet<String>, String> {
    let v: serde_json::Value = serde_json::from_str(stdout.trim())
        .map_err(|e| format!("systemctl output is not JSON ({e}): {}", head(stdout, 200)))?;
    v.as_array()
        .ok_or_else(|| "systemctl JSON is not a list".to_string())?
        .iter()
        .map(|u| {
            u.get("unit_file")
                .and_then(|x| x.as_str())
                .map(str::to_string)
                .ok_or_else(|| format!("unit file entry without a name: {u}"))
        })
        .collect()
}

pub fn normalise_evr(evr: &str) -> String {
    evr.strip_prefix("0:").unwrap_or(evr).to_string()
}

fn pkg_from(v: &serde_json::Value) -> Option<Pkg> {
    let s = |k: &str| v.get(k).and_then(|x| x.as_str()).map(str::to_string);
    Some(Pkg {
        name: s("Name")?,
        arch: s("Arch")?,
        evr: normalise_evr(&s("Evr")?),
        repo: s("Repo").unwrap_or_default(),
    })
}

/// `tdnf -j repoquery --available`: a JSON array of packages.
pub fn tdnf_list(stdout: &str) -> Result<Vec<Pkg>, String> {
    let v: serde_json::Value = serde_json::from_str(stdout.trim())
        .map_err(|e| format!("tdnf output is not JSON ({e}): {}", head(stdout, 200)))?;
    if let Some(err) = tdnf_error(&v) {
        return Err(err);
    }
    let arr = v
        .as_array()
        .ok_or_else(|| format!("tdnf output is not a JSON array: {}", head(stdout, 200)))?;
    arr.iter()
        .map(|x| pkg_from(x).ok_or_else(|| format!("package entry without Name/Arch/Evr: {x}")))
        .collect()
}

fn tdnf_error(v: &serde_json::Value) -> Option<String> {
    let code = v.get("Error")?;
    Some(format!(
        "tdnf error {}: {}",
        code,
        v.get("ErrorMessage").and_then(|m| m.as_str()).unwrap_or("")
    ))
}

/// A resolved tdnf transaction: every key tdnf printed, with its packages.
///
/// Keys are kept verbatim rather than mapped onto an enum, so a key this code
/// has never seen (an `Obsolete` list, say) is still visible to the caller's
/// policy - which only ever allows the keys it names - instead of being
/// dropped on the floor as "unknown, therefore empty".
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Txn {
    pub lists: BTreeMap<String, Vec<Pkg>>,
}

impl Txn {
    pub fn get(&self, key: &str) -> &[Pkg] {
        self.lists.get(key).map(Vec::as_slice).unwrap_or(&[])
    }
    /// Every non-empty list except the allowed ones, as "Key: a, b".
    pub fn other_than(&self, allowed: &[&str]) -> Vec<String> {
        self.lists
            .iter()
            .filter(|(k, v)| !allowed.contains(&k.as_str()) && !v.is_empty())
            .map(|(k, v)| {
                format!(
                    "{k}: {}",
                    v.iter().map(Pkg::key).collect::<Vec<_>>().join(", ")
                )
            })
            .collect()
    }
}

/// `tdnf -j --assumeno install|remove ...` and the same without --assumeno.
///
/// tdnf prints its JSON on stdout and, on failure, prose on stderr. The JSON
/// is either the transaction or `{"Error":n,"ErrorMessage":...}`.
pub fn tdnf_txn(stdout: &str) -> Result<Txn, String> {
    let text = stdout.trim();
    // On a real install tdnf's scriptlets can write to stdout after the JSON
    // (chrony's %post prints "Created symlink ..."). The JSON object is the
    // first thing printed; take exactly that.
    let v: serde_json::Value = serde_json::Deserializer::from_str(text)
        .into_iter::<serde_json::Value>()
        .next()
        .ok_or_else(|| "tdnf printed nothing".to_string())?
        .map_err(|e| format!("tdnf output is not JSON ({e}): {}", head(text, 200)))?;
    if let Some(err) = tdnf_error(&v) {
        return Err(err);
    }
    let obj = v
        .as_object()
        .ok_or_else(|| format!("tdnf transaction is not a JSON object: {}", head(text, 200)))?;
    let mut t = Txn::default();
    for (k, list) in obj {
        let arr = list
            .as_array()
            .ok_or_else(|| format!("tdnf transaction key {k} is not a list"))?;
        let pkgs = arr
            .iter()
            .map(|x| pkg_from(x).ok_or_else(|| format!("{k} entry without Name/Arch/Evr: {x}")))
            .collect::<Result<Vec<_>, _>>()?;
        t.lists.insert(k.clone(), pkgs);
    }
    Ok(t)
}

/// The query format used for the installed set. EPOCH prints `(none)` when a
/// package has none, which is normalised the same way tdnf's Evr is.
pub const RPM_QA_QF: &str = "%{NAME}\\t%{EPOCH}\\t%{VERSION}-%{RELEASE}\\t%{ARCH}\\n";

/// `rpm -qa --qf RPM_QA_QF`.
pub fn rpm_qa(stdout: &str) -> Result<BTreeMap<String, Pkg>, String> {
    let mut out = BTreeMap::new();
    for line in stdout.lines().filter(|l| !l.trim().is_empty()) {
        let f: Vec<&str> = line.split('\t').collect();
        if f.len() != 4 || f[0].is_empty() {
            return Err(format!("unexpected rpm -qa line: {line:?}"));
        }
        let evr = match f[1] {
            "(none)" | "0" => f[2].to_string(),
            e => format!("{e}:{}", f[2]),
        };
        let p = Pkg {
            name: f[0].to_string(),
            arch: f[3].to_string(),
            evr,
            repo: "@System".into(),
        };
        out.insert(p.key(), p);
    }
    if out.is_empty() {
        return Err("rpm -qa listed no packages".into());
    }
    Ok(out)
}

/// One file of a package, from [`RPM_FILES_QF`].
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FileEntry {
    pub path: String,
    pub mode: u32,
    /// rpm's fflags letters: c config, d doc, g ghost, l license, ...
    pub flags: String,
    pub link_to: String,
}

impl FileEntry {
    const S_IFMT: u32 = 0o170000;
    pub fn is_dir(&self) -> bool {
        self.mode & Self::S_IFMT == 0o040000
    }
    pub fn is_reg(&self) -> bool {
        self.mode & Self::S_IFMT == 0o100000
    }
    pub fn is_link(&self) -> bool {
        self.mode & Self::S_IFMT == 0o120000
    }
    pub fn is_exec(&self) -> bool {
        self.is_reg() && self.mode & 0o111 != 0
    }
    pub fn is_ghost(&self) -> bool {
        self.flags.contains('g')
    }
    pub fn is_config(&self) -> bool {
        self.flags.contains('c')
    }
    pub fn name(&self) -> &str {
        self.path.rsplit('/').next().unwrap_or(&self.path)
    }
    pub fn dir(&self) -> &str {
        match self.path.rfind('/') {
            Some(0) => "/",
            Some(i) => &self.path[..i],
            None => "",
        }
    }
}

/// A scalar tag inside an array iterator must be written `%{=TAG}`; the
/// array tags here all have one entry per file, so this is safe.
pub const RPM_FILES_QF: &str =
    "[%{FILENAMES}\\t%{FILEMODES:octal}\\t%{FILEFLAGS:fflags}\\t%{FILELINKTOS}\\n]";

/// `rpm -q[p] --qf RPM_FILES_QF`. A package with no files prints nothing,
/// which is a valid answer (meta-packages exist), so emptiness is not an error
/// here; malformed lines are.
pub fn rpm_files(stdout: &str) -> Result<Vec<FileEntry>, String> {
    let mut out = Vec::new();
    for line in stdout.lines().filter(|l| !l.is_empty()) {
        if line == "(contains no files)" {
            continue;
        }
        // Split from the right: the path is the only field that could carry a
        // tab, and it comes first.
        let mut it = line.rsplitn(4, '\t');
        let link_to = it.next();
        let flags = it.next();
        let mode = it.next();
        let path = it.next();
        let (Some(path), Some(mode), Some(flags), Some(link_to)) = (path, mode, flags, link_to)
        else {
            return Err(format!("unexpected rpm file line: {line:?}"));
        };
        if !path.starts_with('/') {
            return Err(format!("rpm file path is not absolute: {line:?}"));
        }
        let mode = u32::from_str_radix(mode, 8)
            .map_err(|_| format!("rpm file mode is not octal: {line:?}"))?;
        out.push(FileEntry {
            path: path.to_string(),
            mode,
            flags: flags.to_string(),
            link_to: link_to.to_string(),
        });
    }
    Ok(out)
}

/// One line of `rpm -V`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Verify {
    /// attrs is the 9-character column ("S.5....T."), or "missing".
    File {
        attrs: String,
        marker: char,
        path: String,
    },
    /// Anything else rpm -V said: unsatisfied dependencies, scriptlet output,
    /// errors. Never silently dropped.
    Other(String),
}

pub fn rpm_verify(stdout: &str) -> Vec<Verify> {
    let mut out = Vec::new();
    for line in stdout.lines() {
        if line.trim().is_empty() {
            continue;
        }
        // "S.5....T.  c /etc/fstab", ".M.......    /proc", "missing   c /x"
        let parsed = line.find(" /").and_then(|i| {
            let (head, path) = (&line[..i], &line[i + 1..]);
            let mut words = head.split_whitespace();
            let attrs = words.next()?;
            let marker = match words.next() {
                Some(m) if m.chars().count() == 1 => m.chars().next()?,
                Some(_) => return None,
                None => ' ',
            };
            if words.next().is_some() {
                return None;
            }
            let well_formed = attrs == "missing"
                || (attrs.len() == 9 && attrs.chars().all(|c| "SM5DLUGTP.?".contains(c)));
            well_formed.then(|| Verify::File {
                attrs: attrs.to_string(),
                marker,
                path: path.to_string(),
            })
        });
        out.push(parsed.unwrap_or_else(|| Verify::Other(line.to_string())));
    }
    out
}

/// `systemctl show -p A,B,... <one unit>`: key=value lines. Several units are
/// separated by a blank line; this takes the first block only, because the
/// callers ask for one unit at a time and a second block would be a bug.
pub fn systemctl_show(stdout: &str) -> Result<BTreeMap<String, String>, String> {
    let mut m = BTreeMap::new();
    for line in stdout.lines() {
        if line.is_empty() {
            if m.is_empty() {
                continue;
            }
            break;
        }
        let (k, v) = line
            .split_once('=')
            .ok_or_else(|| format!("systemctl show line without '=': {line:?}"))?;
        m.insert(k.to_string(), v.to_string());
    }
    if m.is_empty() {
        return Err("systemctl show printed no properties".into());
    }
    Ok(m)
}

/// `systemctl list-units ... -o json`: the unit names.
pub fn unit_list_json(stdout: &str) -> Result<BTreeSet<String>, String> {
    let v: serde_json::Value = serde_json::from_str(stdout.trim())
        .map_err(|e| format!("systemctl output is not JSON ({e}): {}", head(stdout, 200)))?;
    let arr = v
        .as_array()
        .ok_or_else(|| "systemctl JSON is not a list".to_string())?;
    arr.iter()
        .map(|u| {
            u.get("unit")
                .and_then(|x| x.as_str())
                .map(str::to_string)
                .ok_or_else(|| format!("unit entry without a name: {u}"))
        })
        .collect()
}

/// The cursor `journalctl -n 0 --show-cursor` prints on its last line.
pub fn cursor(stdout: &str) -> Result<String, String> {
    let c = stdout
        .lines()
        .filter_map(|l| l.strip_prefix("-- cursor: "))
        .next_back()
        .map(str::trim)
        .filter(|c| !c.is_empty())
        .ok_or_else(|| format!("journalctl printed no cursor: {}", head(stdout, 200)))?;
    // A cursor goes back onto a command line; it is quoted there, but a value
    // that is not the key=value;... shape is not a cursor at all.
    if !c
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || "=;".contains(ch))
    {
        return Err(format!("not a journal cursor: {c:?}"));
    }
    Ok(c.to_string())
}

/// One journal entry, from `journalctl -o json`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct JEntry {
    pub priority: u8,
    pub message: String,
    /// _SYSTEMD_UNIT, or UNIT for systemd's own messages about a unit.
    pub unit: String,
    pub identifier: String,
    pub realtime_us: u64,
    /// COREDUMP_UNIT: the unit whose process systemd-coredump reports.
    pub coredump_unit: String,
    /// _UID and _EXE of the sender, which journald records from the
    /// process itself even when it can no longer tell its unit.
    pub uid: Option<u32>,
    pub exe: String,
}

impl JEntry {
    pub fn line(&self) -> String {
        let who = if self.identifier.is_empty() {
            &self.unit
        } else {
            &self.identifier
        };
        format!("<{}> {}: {}", self.priority, who, self.message)
    }
}

/// journald stores a MESSAGE that is not valid UTF-8 as an array of bytes, and
/// a missing or oversized one as null. Both are still a message.
fn json_message(v: Option<&serde_json::Value>) -> String {
    match v {
        Some(serde_json::Value::String(s)) => s.clone(),
        Some(serde_json::Value::Array(a)) => {
            let bytes: Vec<u8> = a
                .iter()
                .filter_map(|b| b.as_u64().and_then(|n| u8::try_from(n).ok()))
                .collect();
            String::from_utf8_lossy(&bytes).to_string()
        }
        Some(serde_json::Value::Null) | None => "(no message)".into(),
        Some(other) => other.to_string(),
    }
}

pub fn journal_json(stdout: &str) -> Result<Vec<JEntry>, String> {
    let mut out = Vec::new();
    for line in stdout.lines().filter(|l| !l.trim().is_empty()) {
        // "-- No entries --" is journalctl's way of saying none.
        if line.starts_with("-- ") {
            continue;
        }
        let v: serde_json::Value = serde_json::from_str(line)
            .map_err(|e| format!("journal line is not JSON ({e}): {}", head(line, 200)))?;
        let s = |k: &str| {
            v.get(k)
                .and_then(|x| x.as_str())
                .map(str::to_string)
                .unwrap_or_default()
        };
        let priority = s("PRIORITY").parse::<u8>().unwrap_or(6);
        let unit = {
            let u = s("_SYSTEMD_UNIT");
            let owner = s("UNIT");
            // pid 1's messages about a unit carry the unit in UNIT and
            // init.scope in _SYSTEMD_UNIT; attribute them to the unit.
            if !owner.is_empty() && (u.is_empty() || u == "init.scope") {
                owner
            } else {
                u
            }
        };
        out.push(JEntry {
            priority,
            message: json_message(v.get("MESSAGE")),
            unit,
            identifier: s("SYSLOG_IDENTIFIER"),
            realtime_us: s("__REALTIME_TIMESTAMP").parse().unwrap_or(0),
            coredump_unit: s("COREDUMP_UNIT"),
            uid: s("_UID").parse().ok(),
            exe: s("_EXE"),
        });
    }
    Ok(out)
}

/// The pids the kernel's OOM killer took out of a memory cgroup of the
/// harness's own units, from its `oom-kill:` lines (`..,oom_memcg=<cgroup>,
/// ..,pid=<n>,..`).
pub fn harness_oom_pids(kernel: &[JEntry], prefix: &str) -> BTreeSet<u32> {
    let memcg = format!("oom_memcg=/system.slice/{prefix}");
    kernel
        .iter()
        .filter(|e| e.message.contains("oom-kill:") && e.message.contains(&memcg))
        .filter_map(|e| {
            e.message
                .split(',')
                .find_map(|kv| kv.trim().strip_prefix("pid="))
                .and_then(|p| p.parse().ok())
        })
        .collect()
}

/// The pid in the kernel's "Memory cgroup out of memory: Killed process <pid>
/// (<comm>) ..." line.
pub fn oom_killed_pid(message: &str) -> Option<u32> {
    message
        .split_once("Killed process ")?
        .1
        .split_whitespace()
        .next()?
        .parse()
        .ok()
}

/// `ss -Hltnp` lines: the pids listening on a TCP port.
pub fn listeners_on_port(stdout: &str, port: u16) -> Vec<u32> {
    let want = format!(":{port}");
    let mut pids = Vec::new();
    for line in stdout.lines() {
        let cols: Vec<&str> = line.split_whitespace().collect();
        // State Recv-Q Send-Q Local:Port Peer:Port Process
        let Some(local) = cols.get(3) else { continue };
        if !local.ends_with(&want) {
            continue;
        }
        let mut rest = line;
        while let Some(i) = rest.find("pid=") {
            rest = &rest[i + 4..];
            let n: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
            if let Ok(p) = n.parse() {
                if !pids.contains(&p) {
                    pids.push(p);
                }
            }
        }
    }
    pids
}

/// The systemd unit a process belongs to, from `/proc/<pid>/cgroup` under
/// cgroup v2: `0::/system.slice/sshd.service`.
pub fn unit_of_cgroup(text: &str) -> Option<String> {
    let path = text.lines().find_map(|l| l.strip_prefix("0::"))?;
    let last = path.trim().rsplit('/').next()?;
    crate::pkglife::remote::valid_unit_name(last).then(|| last.to_string())
}

/// "<pid> <exe>" lines from the process walk; " (deleted)" is kept so a
/// process still running a removed binary is visible as exactly that.
pub fn exe_list(stdout: &str) -> Vec<(u32, String)> {
    stdout
        .lines()
        .filter_map(|l| {
            let (pid, exe) = l.split_once(' ')?;
            Some((pid.parse().ok()?, exe.to_string()))
        })
        .collect()
}

pub fn head(s: &str, n: usize) -> String {
    let t: String = s.chars().take(n).collect();
    if s.chars().count() > n {
        format!("{t}...")
    } else {
        t
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ---- captured on k09, 2026-09-27 ------------------------------------
    const REPOQUERY: &str = r#"[{"Nevra":"7zip-26.01-2.ph5.x86_64","Name":"7zip","Arch":"x86_64","Evr":"26.01-2.ph5","Repo":"sharukhan-media"},{"Nevra":"Linux-PAM-1.7.2-4.ph5.x86_64","Name":"Linux-PAM","Arch":"x86_64","Evr":"1.7.2-4.ph5","Repo":"sharukhan-media"},{"Nevra":"WALinuxAgent-2.15.0.1-2.ph5.noarch","Name":"WALinuxAgent","Arch":"noarch","Evr":"2.15.0.1-2.ph5","Repo":"sharukhan-media"}]"#;
    const TXN_INSTALL: &str = r#"{"Install":[{"Name":"chrony","Arch":"x86_64","Evr":"4.3-3.ph5","InstallSize":582137,"Repo":"sharukhan-media"}]}Created symlink '/etc/systemd/system/multi-user.target.wants/chronyd.service' → '/usr/lib/systemd/system/chronyd.service'.
Created symlink '/etc/systemd/system/multi-user.target.wants/chrony-wait.service' → '/usr/lib/systemd/system/chrony-wait.service'."#;
    const TXN_REMOVE_BASH: &str = r#"{"Install":[{"Name":"toybox","Arch":"x86_64","Evr":"0.8.9-16.ph5","InstallSize":554176,"Repo":"sharukhan-media"}],"Remove":[{"Name":"xmlsec1","Arch":"x86_64","Evr":"1.3.11-1.ph5","InstallSize":1225980,"Repo":"@System"},{"Name":"which","Arch":"x86_64","Evr":"2.21-9.ph5","InstallSize":34267,"Repo":"@System"}]}"#;
    const TXN_ERROR: &str = r#"{"Error":1011,"ErrorMessage":"No matching packages"}"#;
    const CHRONY_FILES: &str = "/etc/chrony.conf\t100644\tcn\t
/etc/chrony.keys\t100640\tcn\t
/usr/bin/chronyc\t100755\t\t
/usr/lib/systemd/system/chrony-wait.service\t100644\t\t
/usr/lib/systemd/system/chronyd.service\t100644\t\t
/usr/sbin/chronyd\t100755\t\t
/usr/share/doc/chrony-4.3\t40755\t\t
/usr/share/doc/chrony-4.3/FAQ\t100644\td\t
/var/lib/chrony/drift\t100644\tg\t
/var/log/chrony\t40755\t\t
";
    const RPM_VA: &str = "S.5....T.  c /etc/fstab
....L....  c /etc/mtab
.M.......  g /mnt/cdrom
.M.......    /proc
missing     /run/media/cdrom
SM5...GT.    /var/log/wtmp
Unsatisfied dependencies for chrony-4.3-3.ph5.x86_64:
	libfoo.so.1()(64bit) is needed by chrony-4.3-3.ph5.x86_64
";
    const SHOW: &str = "Type=forking
RemainAfterExit=no
MainPID=2903
Result=success
Id=chronyd.service
Conflicts=ntpd.service systemd-timesyncd.service shutdown.target
LoadState=loaded
ActiveState=active
SubState=running
UnitFileState=enabled
NeedDaemonReload=yes
ConditionResult=yes
";
    const CURSOR: &str = "-- No entries --
-- cursor: s=9f69953a8c914d24862e25f9dfa62e75;i=c1b;b=da626373f4dd4605ae60fc2a650fc58d;m=9e7e59c;t=65c7dcf07808c;x=254da256d10e6ee1
";
    const JOURNAL: &str = r#"{"_SYSTEMD_UNIT":"init.scope","UNIT":"chronyd.service","PRIORITY":"6","SYSLOG_IDENTIFIER":"systemd","MESSAGE":"Starting NTP client/server...","__REALTIME_TIMESTAMP":"1790545284813130"}
{"_SYSTEMD_UNIT":"chronyd.service","SYSLOG_IDENTIFIER":"chronyd","PRIORITY":"4","MESSAGE":"Running with root privileges","__REALTIME_TIMESTAMP":"1790545284861550"}
{"_SYSTEMD_UNIT":"x.service","PRIORITY":"3","MESSAGE":[104,105,255],"__REALTIME_TIMESTAMP":"1"}
{"_SYSTEMD_UNIT":"y.service","PRIORITY":"2","MESSAGE":null}
"#;

    #[test]
    fn repoquery_json_lists_every_package() {
        let v = tdnf_list(REPOQUERY).unwrap();
        assert_eq!(v.len(), 3);
        assert_eq!(v[2].key(), "WALinuxAgent-2.15.0.1-2.ph5.noarch");
        assert_eq!(v[0].repo, "sharukhan-media");
    }

    #[test]
    fn a_tdnf_error_is_an_error_not_an_empty_list() {
        assert!(tdnf_list(TXN_ERROR).unwrap_err().contains("1011"));
        assert!(tdnf_txn(TXN_ERROR)
            .unwrap_err()
            .contains("No matching packages"));
        assert!(tdnf_list("").is_err());
        assert!(tdnf_list("{}").is_err());
        assert!(tdnf_txn("").is_err());
        assert!(tdnf_txn("[1]").is_err());
        assert!(tdnf_list(r#"[{"Name":"x"}]"#).is_err());
    }

    #[test]
    fn the_transaction_json_is_taken_even_with_scriptlet_output_after_it() {
        let t = tdnf_txn(TXN_INSTALL).unwrap();
        assert_eq!(t.get("Install").len(), 1);
        assert_eq!(t.get("Install")[0].key(), "chrony-4.3-3.ph5.x86_64");
        assert!(t.other_than(&["Install"]).is_empty());
    }

    #[test]
    fn a_transaction_that_removes_anything_names_it() {
        let t = tdnf_txn(TXN_REMOVE_BASH).unwrap();
        let other = t.other_than(&["Install"]);
        assert_eq!(other.len(), 1);
        assert!(other[0].starts_with("Remove: xmlsec1-1.3.11-1.ph5.x86_64"));
        // an unknown key is policy's business, not silently dropped
        let t =
            tdnf_txn(r#"{"Obsolete":[{"Name":"a","Arch":"x","Evr":"1-1"}],"Install":[]}"#).unwrap();
        assert_eq!(
            t.other_than(&["Install"]),
            vec!["Obsolete: a-1-1.x".to_string()]
        );
    }

    #[test]
    fn epochs_are_normalised_identically_on_both_sides() {
        assert_eq!(normalise_evr("0:1.2-3"), "1.2-3");
        assert_eq!(normalise_evr("2:1.2-3"), "2:1.2-3");
        let qa = rpm_qa(
            "bash\t(none)\t5.2-1.ph5\tx86_64\nperl\t4\t5.40-1.ph5\tx86_64\nzero\t0\t1-1\tnoarch\n",
        )
        .unwrap();
        assert!(qa.contains_key("bash-5.2-1.ph5.x86_64"));
        assert!(qa.contains_key("perl-5.40-1.ph5.x86_64"));
        assert_eq!(qa["perl-5.40-1.ph5.x86_64"].evr, "4:5.40-1.ph5");
        assert!(qa.contains_key("zero-1-1.noarch"));
        assert!(rpm_qa("").is_err());
        assert!(rpm_qa("bash 5.2").is_err());
    }

    #[test]
    fn file_lists_carry_type_mode_and_flags() {
        let f = rpm_files(CHRONY_FILES).unwrap();
        assert_eq!(f.len(), 10);
        let chronyd = f.iter().find(|e| e.path == "/usr/sbin/chronyd").unwrap();
        assert!(chronyd.is_exec() && chronyd.is_reg() && !chronyd.is_dir());
        assert_eq!(chronyd.dir(), "/usr/sbin");
        assert_eq!(chronyd.name(), "chronyd");
        assert!(f[0].is_config() && !f[0].is_exec());
        assert!(f
            .iter()
            .find(|e| e.path.ends_with("drift"))
            .unwrap()
            .is_ghost());
        assert!(f
            .iter()
            .find(|e| e.path == "/var/log/chrony")
            .unwrap()
            .is_dir());
        assert!(rpm_files("(contains no files)\n").unwrap().is_empty());
        assert!(rpm_files("relative\t100644\t\t\n").is_err());
        assert!(rpm_files("/x\tnotoctal\t\t\n").is_err());
        assert!(rpm_files("/x\t100644\n").is_err());
    }

    #[test]
    fn rpm_verify_keeps_every_line_and_its_marker() {
        let v = rpm_verify(RPM_VA);
        assert_eq!(v.len(), 8);
        assert_eq!(
            v[0],
            Verify::File {
                attrs: "S.5....T.".into(),
                marker: 'c',
                path: "/etc/fstab".into()
            }
        );
        assert_eq!(
            v[3],
            Verify::File {
                attrs: ".M.......".into(),
                marker: ' ',
                path: "/proc".into()
            }
        );
        assert!(matches!(&v[4], Verify::File { attrs, .. } if attrs == "missing"));
        // the dependency complaint is not a file line and is not dropped
        assert!(matches!(&v[6], Verify::Other(s) if s.starts_with("Unsatisfied")));
        assert!(matches!(&v[7], Verify::Other(_)));
    }

    #[test]
    fn systemctl_show_is_a_map_and_empty_is_an_error() {
        let m = systemctl_show(SHOW).unwrap();
        assert_eq!(m["ActiveState"], "active");
        assert_eq!(
            m["Conflicts"],
            "ntpd.service systemd-timesyncd.service shutdown.target"
        );
        assert!(systemctl_show("").is_err());
        assert!(systemctl_show("garbage").is_err());
        let two = systemctl_show("A=1\n\nA=2\n").unwrap();
        assert_eq!(two["A"], "1");
    }

    #[test]
    fn failed_units_json() {
        assert!(unit_list_json("[]").unwrap().is_empty());
        let s = unit_list_json(
            r#"[{"unit":"x.service","load":"loaded","active":"failed","sub":"failed","description":"X"}]"#,
        )
        .unwrap();
        assert!(s.contains("x.service"));
        assert!(unit_list_json("").is_err());
        assert!(unit_list_json(r#"[{"load":"x"}]"#).is_err());
    }

    #[test]
    fn the_cursor_is_found_and_validated() {
        assert!(cursor(CURSOR).unwrap().starts_with("s=9f69953a"));
        assert!(cursor("-- No entries --\n").is_err());
        assert!(cursor("-- cursor: s=1;$(reboot)\n").is_err());
    }

    #[test]
    fn journal_entries_attribute_pid1_messages_to_their_unit() {
        let j = journal_json(JOURNAL).unwrap();
        assert_eq!(j.len(), 4);
        assert_eq!(j[0].unit, "chronyd.service");
        assert_eq!(j[0].priority, 6);
        assert_eq!(j[1].priority, 4);
        assert_eq!(j[2].message, "hi\u{fffd}");
        assert_eq!(j[3].message, "(no message)");
        assert!(j[1]
            .line()
            .contains("chronyd: Running with root privileges"));
        assert!(journal_json("-- No entries --\n").unwrap().is_empty());
        assert!(journal_json("not json\n").is_err());
    }

    #[test]
    fn the_ssh_listener_is_found_by_port_not_by_name() {
        let ss = "LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:((\"sshd\",pid=812,fd=3))
LISTEN 0 128 [::]:22 [::]:* users:((\"sshd\",pid=812,fd=4))
LISTEN 0 4096 127.0.0.54:53 0.0.0.0:* users:((\"systemd-resolve\",pid=600,fd=21))
LISTEN 0 128 0.0.0.0:2222 0.0.0.0:* users:((\"other\",pid=9,fd=3))";
        assert_eq!(listeners_on_port(ss, 22), vec![812]);
        assert_eq!(listeners_on_port(ss, 53), vec![600]);
        assert!(listeners_on_port(ss, 80).is_empty());
        assert_eq!(
            unit_of_cgroup("0::/system.slice/sshd.service\n").as_deref(),
            Some("sshd.service")
        );
        assert_eq!(
            unit_of_cgroup("0::/user.slice/user-0.slice/session-3.scope"),
            Some("session-3.scope".into())
        );
        assert_eq!(unit_of_cgroup("12:pids:/x\n"), None);
    }

    #[test]
    fn process_listings() {
        let e = exe_list("1 /usr/lib/systemd/systemd\n2903 /usr/sbin/chronyd (deleted)\nbad\n");
        assert_eq!(e.len(), 2);
        assert_eq!(e[1], (2903, "/usr/sbin/chronyd (deleted)".into()));
    }

    #[test]
    fn keys_are_epoch_free_on_both_sides() {
        // nginx on the 5.0 media: tdnf omits the epoch rpm reports
        let t = tdnf_txn(
            r#"{"Install":[{"Name":"nginx","Arch":"x86_64","Evr":"1.30.4-2.ph5","Repo":"m"}]}"#,
        )
        .unwrap();
        let q = rpm_qa("nginx\t1\t1.30.4-2.ph5\tx86_64\n").unwrap();
        assert!(q.contains_key(&t.get("Install")[0].key()));
        assert_eq!(
            strip_epoch_key("nginx-1:1.30.4-2.ph5.x86_64"),
            "nginx-1.30.4-2.ph5.x86_64"
        );
        assert_eq!(
            strip_epoch_key("bash-5.3-1.ph5.x86_64"),
            "bash-5.3-1.ph5.x86_64"
        );
        // a colon that is not an epoch is left alone
        assert_eq!(strip_epoch_key("a-b:c-1.x"), "a-b:c-1.x");
    }

    #[test]
    fn unit_files_json_lists_names() {
        let s = unit_files_json(
            r#"[{"unit_file":"auditd.service","state":"enabled","preset":"enabled"}]"#,
        )
        .unwrap();
        assert!(s.contains("auditd.service"));
        assert!(unit_files_json("[{}]").is_err());
        assert!(unit_files_json("x").is_err());
    }

    #[test]
    fn head_marks_truncation() {
        assert_eq!(head("abc", 5), "abc");
        assert_eq!(head("abcdef", 3), "abc...");
    }
}
