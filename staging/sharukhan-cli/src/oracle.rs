//! The pass/fail assertions. Ported from lib/oracle.sh.
//!
//! Every assertion names the PR it proves. That is the point: a run does not
//! report "something broke", it reports "PR #22 regressed", because making PR
//! issues identifiable is the whole purpose of the harness.
//!
//! The permutation matrix supplies a *dependency-resolution* oracle only
//! (Error(1011) vs Error(1032), media RPM presence). It supplies nothing for
//! dmesg / journalctl / /var/log, so sections C and D collect that evidence
//! and assert only where the assertion is cheap and unambiguous.

use crate::evidence::{Checks, Status};
use crate::guest::Guest;
use crate::serial;
use std::path::Path;
use std::process::Command;

// ---- A. media, before any VM exists -------------------------------------

/// Six packages the matrix records as ABSENT from minimal media. Their
/// presence is what POI#11 (the doc's FIX-1b) delivers, and their absence is
/// the root cause of matrix rows 3,4,7,8 - and, via selinux-policy, 5,6.
pub const STIG_MEDIA_PKGS: [&str; 5] = [
    "rsyslog",
    "openssl-fips-provider",
    "selinux-policy",
    "libselinux-utils",
    "aide",
];

/// Every RPM basename under /RPMS on an ISO.
///
/// xorriso writes its banner and progress to stderr and exits 0 for an empty
/// result, so the exit code says nothing; parse stdout. The names come back
/// quoted, hence the trim.
pub fn media_rpms(iso: &Path) -> Vec<String> {
    let out = Command::new("xorriso")
        .args(["-osirrox", "on", "-indev"])
        .arg(iso)
        .args(["-find", "/RPMS", "-name", "*.rpm"])
        .output();
    let Ok(out) = out else { return Vec::new() };
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter_map(|l| l.trim().rsplit('/').next().map(|n| n.trim_matches('\'').to_string()))
        .filter(|n| n.ends_with(".rpm"))
        .collect()
}

/// `^<name>-[0-9]` - an RPM filename belongs to package `name` only when the
/// next field is the version. A plain `contains` matches
/// `selinux-policy-devel` for `selinux-policy`, and `libselinux` for
/// `libselinux-utils` in the other direction.
pub fn rpm_is(file: &str, name: &str) -> bool {
    match file.strip_prefix(name) {
        Some(rest) => rest.starts_with('-') && rest[1..].starts_with(|c: char| c.is_ascii_digit()),
        None => false,
    }
}

pub fn media(iso: &Path, iso_type: &str, c: &mut Checks) {
    let list = media_rpms(iso);
    c.check("media.rpm_count", "-", Status::Info, "", &list.len().to_string(), "RPMs on media");

    // Negative control: a name that must never resolve. Without it a broken
    // extraction would make every presence check vacuously pass.
    let ctl = list.iter().filter(|f| rpm_is(f, "zzz-not-a-real-package")).count();
    c.expect("media.negative_control", "-", "0", &ctl.to_string(), "control must find nothing");

    let mut missing: Vec<&str> = STIG_MEDIA_PKGS
        .iter()
        .copied()
        .filter(|p| !list.iter().any(|f| rpm_is(f, p)))
        .collect();
    // ntp is a capability satisfied by ntpsec; no package is literally named ntp.
    if !list.iter().any(|f| rpm_is(f, "ntpsec")) {
        missing.push("ntpsec");
    }
    c.expect(
        "media.stig_packages",
        "POI#11",
        "",
        &missing.join(" "),
        &format!("STIG set must be on the media for {iso_type}"),
    );

    // Stale-RPM shadowing: tdnf picks the highest release, so a months-old
    // photon-os-installer left in stage/RPMS silently wins and ends up on the
    // ISO. Record what actually shipped.
    let poi = list
        .iter()
        .find(|f| rpm_is(f, "photon-os-installer"))
        .cloned()
        .unwrap_or_else(|| "ABSENT".to_string());
    c.check("media.poi_rpm", "-", Status::Info, "", &poi, "installer actually on the media");
}

// ---- B. install phase, from the serial log ------------------------------

/// `install_result` is what the install phase OBSERVED, not a re-derivation.
/// Passing it in is the fix for a false k01 FAIL(2): the installed system is
/// serial-silent unless the kickstart's grub edit takes, so `root=PARTUUID=`
/// can be legitimately absent from a machine that booted perfectly well.
pub fn install(serial_path: &Path, install_result: Option<&str>, c: &mut Checks) {
    if !serial_path.exists() {
        c.check(
            "install.serial_log",
            "-",
            Status::Fail,
            "present",
            "missing",
            &serial_path.display().to_string(),
        );
        return;
    }
    let text = serial::read_clean(serial_path);

    // Error(1011) is a genuine resolution failure. Error(1032) is only ever a
    // --assumeno dry-run artefact and must NOT be treated as a real-install
    // signal. Never match a specific package name: list(set(packages)) makes
    // which of the six tdnf reports first non-deterministic.
    let e1011 = serial::count(&text, "Error(1011)");
    c.expect("install.no_error_1011", "POI#11", "0", &e1011.to_string(), "No matching packages");

    let efail = serial::count(&text, "Failed to install some packages");
    c.expect("install.packages_installed", "POI#11", "0", &efail.to_string(), "");

    // The i18n error proves the locale.conf ordering fix did NOT apply.
    let i18n = serial::count(&text, "i18n_vars not set");
    c.expect(
        "install.no_i18n_error",
        "POI#10",
        "0",
        &i18n.to_string(),
        "dracut 20i18n needs /etc/locale.conf at initrd build time",
    );

    // The single most valuable completion signal: the boot source moves from
    // the installer live env to the installed disk.
    let ram = serial::count(&text, "root=/dev/ram0");
    let parts = serial::count(&text, "root=PARTUUID=");
    c.check("install.boot_ram0", "-", Status::Info, "", &ram.to_string(), "installer live-env boots");

    // Two independent proofs, either sufficient. The serial marker only
    // appears if the INSTALLED system has a serial console; a target whose
    // grub edit did not take is silent here even though it booted perfectly
    // well. In that case the guest answering on the network is the stronger
    // evidence, so accept it.
    let booted = if parts > 0 || install_result == Some("installed") { "yes" } else { "no" };
    c.expect(
        "install.booted_from_disk",
        "-",
        "yes",
        booted,
        "root=PARTUUID= in serial, or the guest answered as a booted machine",
    );

    let ansfail = serial::count(&text, "AssertionError");
    c.expect(
        "install.ansible_no_assert",
        "PR#9",
        "0",
        &ansfail.to_string(),
        "installer.py asserts on playbook returncode",
    );
}

// ---- C. post-boot, over ssh ---------------------------------------------

/// What SELinux mode the installed system is SUPPOSED to be in.
///
/// This is the oracle that was WRONG. It asserted Enforcing whenever STIG was
/// requested and produced four false failures (k11/k12/k15/k16) that were
/// briefly reported as a Photon compliance defect.
///
/// `249ac3ff4 "91/92: selinux-policy: Mark disabled in 91 and permissive in
/// 92"` gives a tri-state keyed to the build subrelease:
///
/// | | SPECS/selinux-policy | SPECS/90/… | SPECS/91/… |
/// |---|---|---|---|
/// | gate | `>= 92` | `<= 90` | `== 91` |
/// | SELINUX= | permissive | enforcing | disabled |
///
/// So a default subrelease-92 install boots Permissive BY DESIGN. The four
/// minimal-ISO STIG rows that booted Enforcing only did so because those ISOs
/// carried a stale selinux-policy-43.6-3 left in stage/RPMS from June: same
/// playbook, same package names, opposite outcome, and the release number was
/// the whole difference.
///
/// Hence the order below. The shipped /etc/selinux/config is the package's own
/// statement of intent and wins outright; the subrelease is only the fallback
/// for a guest that could not be read. Neither is guessed - an unreadable
/// guest yields Unknown, which is recorded as evidence rather than asserted.
#[derive(Debug, PartialEq, Eq)]
pub enum Expected {
    Mode(&'static str),
    Unknown(String),
}

pub fn expected_selinux(shipped_config: Option<&str>, subrelease: Option<u32>) -> Expected {
    if let Some(text) = shipped_config {
        if let Some(mode) = text
            .lines()
            .map(str::trim)
            .filter(|l| !l.starts_with('#'))
            .find_map(|l| l.strip_prefix("SELINUX="))
        {
            return match mode.trim().to_ascii_lowercase().as_str() {
                "enforcing" => Expected::Mode("Enforcing"),
                "permissive" => Expected::Mode("Permissive"),
                "disabled" => Expected::Mode("Disabled"),
                other => Expected::Unknown(format!("/etc/selinux/config says SELINUX={other}")),
            };
        }
    }
    match subrelease {
        Some(n) if n <= 90 => Expected::Mode("Enforcing"),
        Some(91) => Expected::Mode("Disabled"),
        Some(_) => Expected::Mode("Permissive"),
        None => Expected::Unknown(
            "neither /etc/selinux/config nor /etc/tdnf/vars/subrelease could be read".into(),
        ),
    }
}

pub fn guest(g: &Guest, stig: &str, fs: &str, c: &mut Checks) {
    let v = g.run("findmnt -no FSTYPE /").value_or("unknown");
    c.expect("guest.root_fstype", "-", fs, &v, "the filesystem axis actually took effect");

    // --- SELinux ---------------------------------------------------------
    let policy = g.run("rpm -q selinux-policy").value_or("absent");
    c.check(
        "guest.selinux_policy",
        "PR#9",
        Status::Info,
        "",
        &policy,
        "the package that ships /etc/selinux/config, and therefore the default mode",
    );
    let config = g.run("cat /etc/selinux/config");
    let subrelease = g.run("cat /etc/tdnf/vars/subrelease");
    let sub = subrelease.trimmed().parse::<u32>().ok();
    let running = g.run("getenforce").value_or("unknown");
    let expected = expected_selinux(
        if config.ok { Some(config.stdout.as_str()) } else { None },
        sub,
    );
    match (&expected, stig) {
        (Expected::Mode(m), "yes") => c.expect(
            "guest.selinux",
            "PR#9",
            m,
            &running,
            "the mode selinux-policy ships at this subrelease - permissive on >= 92 BY DESIGN",
        ),
        (Expected::Mode(m), _) => c.check(
            "guest.selinux",
            "PR#9",
            Status::Info,
            m,
            &running,
            "not a STIG row; recorded, not asserted",
        ),
        (Expected::Unknown(why), _) => {
            c.check("guest.selinux", "PR#9", Status::Info, "", &running, why)
        }
    }

    // PR#22: both group regressions are visible in the journal of every boot.
    let v = g
        .run("journalctl -b --no-pager 2>/dev/null | grep -c \"Unknown group 'render'\"")
        .value_or("?");
    c.expect(
        "guest.no_render_group",
        "PR#22",
        "0",
        &v,
        "dangling accel rule in 50-udev-default.rules",
    );
    let v = g
        .run("journalctl -b --no-pager 2>/dev/null | grep -c \"resolve group 'systemd-journal'\"")
        .value_or("?");
    c.expect(
        "guest.no_journal_group",
        "PR#22",
        "0",
        &v,
        "initrd sysusers snippet emptied by systemd patch 0004",
    );

    // PR#22 again: /tmp hardening is delivered at BUILD time because tmp.mount
    // is package-owned and not %config; the installer deliberately skips the
    // equivalent ansible control PHTN-50-000245.
    if stig == "yes" {
        let v = g.run("findmnt -no OPTIONS /tmp | grep -c noexec").value_or("0");
        c.check(
            "guest.tmp_noexec",
            "PR#22",
            Status::Info,
            "",
            &v,
            "1 once STIG_HARDEN builds are enabled",
        );

        // POI#9: exactly five STIG packages requested, not eight.
        let v = g
            .run("zcat /var/log/poi/manifest.json.gz 2>/dev/null | python3 -c \"import json,sys;print(len(json.load(sys.stdin)['install_config'].get('additional_packages',[])))\"")
            .value_or("?");
        c.expect(
            "guest.stig_pkg_count",
            "POI#9",
            "5",
            &v,
            "libselinux-utils, ntp, libgcrypt dropped as redundant",
        );
    }

    // The matrix's own cheap assertion: stig-hardening runs from the initrd
    // and must never land on the target.
    let v = g
        .run("rpm -q stig-hardening >/dev/null 2>&1 && echo installed || echo absent")
        .value_or("?");
    c.expect(
        "guest.stig_not_on_target",
        "-",
        "absent",
        &v,
        "stig-hardening is not in KS_STIG_PACKAGES",
    );

    // PR#21: versioned libgcrypt only at subrelease >= 91.
    let v = g
        .run("rpm -q --requires aide 2>/dev/null | grep -c \"libgcrypt >= 1.10.4\"")
        .value_or("0");
    c.check(
        "guest.aide_libgcrypt",
        "PR#21",
        Status::Info,
        "",
        &v,
        "1 only when built at subrelease >= 91",
    );

    // POI#9 counterpart: time sync works without ntp being installed.
    let v = g.run("timedatectl show -p NTPSynchronized --value").value_or("?");
    c.check("guest.time_synced", "POI#9", Status::Info, "", &v, "systemd-timesyncd, not ntp");

    // Canister/FIPS, when the ISO was built with one.
    let v = g.run("cat /proc/sys/crypto/fips_enabled").value_or("0");
    c.check("guest.fips_enabled", "PR#24", Status::Info, "", &v, "");
    let v = g
        .run("dmesg 2>/dev/null | grep -c \"canister verification passed\"")
        .value_or("0");
    c.check("guest.fips_canister", "PR#24", Status::Info, "", &v, "");

    let v = g
        .run("systemctl --failed --no-legend --no-pager 2>/dev/null | wc -l")
        .value_or("?");
    c.expect(
        "guest.failed_units",
        "PR#9",
        "0",
        &v,
        "first boot may race the SELinux relabel; second boot must be clean",
    );

    let v = g
        .run("journalctl -b --no-pager 2>/dev/null | grep -ci \"avc: *denied\"")
        .value_or("?");
    c.check(
        "guest.avc_denials",
        "PR#9",
        Status::Info,
        "",
        &v,
        "non-zero on first boot is the documented relabel race",
    );
}

// ---- D. log harvest ------------------------------------------------------

/// The matrix defines no dmesg/journalctl//var/log criteria at all, so this
/// COLLECTS the evidence rather than asserting on it - except the two counts,
/// which are cheap regression detectors.
pub fn harvest(g: &Guest, dest: &Path, secret: Option<&str>, c: &mut Checks) {
    if let Err(e) = std::fs::create_dir_all(dest) {
        c.check(
            "logs.harvest_dir",
            "-",
            Status::Fail,
            "created",
            &format!("{e}"),
            &dest.display().to_string(),
        );
        return;
    }
    // POI records the kickstart it was given into /var/log/poi/manifest.json.gz,
    // password and all, so collecting guest logs verbatim copies the credential
    // straight back into the evidence tree. Redact on capture: scrubbing the
    // tree afterwards cannot hold, because the next run writes it back.
    fn scrub(secret: Option<&str>, s: &str) -> String {
        match secret {
            Some(pw) if !pw.is_empty() => s.replace(pw, crate::phases::REDACTED),
            _ => s.to_string(),
        }
    }

    const FILES: [(&str, &str); 9] = [
        ("dmesg", "dmesg.txt"),
        ("journalctl -b --no-pager", "journal-boot.txt"),
        ("journalctl -p err -b --no-pager", "journal-err.txt"),
        ("systemctl --failed --no-pager", "failed-units.txt"),
        ("rpm -qa | sort", "rpm-qa.txt"),
        ("cat /proc/cmdline", "cmdline.txt"),
        ("findmnt -A", "mounts.txt"),
        ("cat /var/log/mkinitrd-*.log 2>/dev/null", "varlog-mkinitrd.txt"),
        ("zcat /var/log/poi/manifest.json.gz 2>/dev/null", "poi-manifest.json"),
    ];
    for (cmd, name) in FILES {
        let _ = std::fs::write(dest.join(name), scrub(secret, &g.run(cmd).stdout));
    }
    for f in ["installer.log", "ansible-stig.log", "messages"] {
        let _ = std::fs::write(
            dest.join(format!("varlog-{f}")),
            scrub(secret, &g.run(&format!("cat /var/log/{f} 2>/dev/null")).stdout),
        );
    }

    let dmesg = std::fs::read_to_string(dest.join("dmesg.txt")).unwrap_or_default();
    let bug = dmesg
        .lines()
        .filter(|l| {
            ["] BUG", "] WARNING", "] Oops", "] Call Trace"]
                .iter()
                .any(|p| l.contains(p))
        })
        .count();
    c.expect("logs.dmesg_no_bug", "-", "0", &bug.to_string(), "kernel BUG/WARNING/Oops in dmesg");
    let errs = std::fs::read_to_string(dest.join("journal-err.txt"))
        .map(|t| t.lines().count())
        .unwrap_or(0);
    c.check(
        "logs.journal_err_lines",
        "-",
        Status::Info,
        "",
        &errs.to_string(),
        "harvested to journal-err.txt",
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::evidence::Checks;

    fn scratch(tag: &str) -> std::path::PathBuf {
        let d = std::env::temp_dir().join(format!("sharukhan-or-{}-{tag}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn checks(d: &Path) -> Checks {
        let mut c = Checks::init(d, "k01", "20260901T000000Z").unwrap();
        c.echo = false;
        c
    }

    fn status_of(c: &Checks, id: &str) -> String {
        let text = std::fs::read_to_string(&c.path).unwrap();
        let want = format!("\"check\":\"{id}\"");
        let line = text.lines().find(|l| l.contains(&want)).unwrap_or("");
        let i = line.find("\"status\":\"").unwrap() + 10;
        line[i..].split('"').next().unwrap().to_string()
    }

    /// The false k01 FAIL(2). The installed system is serial-silent unless the
    /// kickstart's grub edit takes, so root=PARTUUID= is absent from a machine
    /// that booted perfectly well - and the install phase had already watched
    /// it answer as a booted machine. Re-deriving the fact overturned it.
    #[test]
    fn what_the_install_phase_proved_is_not_overturned_here() {
        let d = scratch("install");
        let serial = d.join("serial0.log");
        std::fs::write(&serial, "linux root=/dev/ram0 quiet\nInstaller finished\n").unwrap();

        let mut c = checks(&d);
        install(&serial, Some("installed"), &mut c);
        assert_eq!(status_of(&c, "install.booted_from_disk"), "pass");

        let mut c = checks(&d);
        install(&serial, None, &mut c);
        assert_eq!(status_of(&c, "install.booted_from_disk"), "fail");

        // The serial marker alone is sufficient too - either proof will do.
        std::fs::write(&serial, "linux root=PARTUUID=abc console=ttyS0\n").unwrap();
        let mut c = checks(&d);
        install(&serial, None, &mut c);
        assert_eq!(status_of(&c, "install.booted_from_disk"), "pass");
        std::fs::remove_dir_all(&d).ok();
    }

    /// Error(1032) is a --assumeno dry-run artefact and must never read as a
    /// real-install failure; Error(1011) always is.
    #[test]
    fn only_1011_counts_as_a_resolution_failure() {
        let d = scratch("1011");
        let serial = d.join("serial0.log");
        std::fs::write(&serial, "tdnf: Error(1032) something\nroot=PARTUUID=x\n").unwrap();
        let mut c = checks(&d);
        install(&serial, None, &mut c);
        assert_eq!(status_of(&c, "install.no_error_1011"), "pass");

        std::fs::write(&serial, "tdnf: Error(1011) No matching packages\n").unwrap();
        let mut c = checks(&d);
        install(&serial, None, &mut c);
        assert_eq!(status_of(&c, "install.no_error_1011"), "fail");
        std::fs::remove_dir_all(&d).ok();
    }

    /// A serial log full of NULs must not make every count read zero. That is
    /// the toybox-grep trap, and it makes an oracle pass vacuously.
    #[test]
    fn a_nul_bearing_serial_log_still_reports_its_errors() {
        let d = scratch("nul");
        let serial = d.join("serial0.log");
        std::fs::write(&serial, b"\x00\x00Error(1011)\x00 No matching packages\n\x00").unwrap();
        let mut c = checks(&d);
        install(&serial, None, &mut c);
        assert_eq!(status_of(&c, "install.no_error_1011"), "fail");
        std::fs::remove_dir_all(&d).ok();
    }

    #[test]
    fn a_missing_serial_log_is_a_failure_not_a_silent_pass() {
        let d = scratch("missing");
        let mut c = checks(&d);
        install(&d.join("no-such.log"), Some("installed"), &mut c);
        assert_eq!(status_of(&c, "install.serial_log"), "fail");
        assert_eq!(c.total(), 1);
        std::fs::remove_dir_all(&d).ok();
    }

    #[test]
    fn an_rpm_belongs_to_a_package_only_at_a_version_boundary() {
        assert!(rpm_is("selinux-policy-43.6-4.ph5.noarch.rpm", "selinux-policy"));
        assert!(!rpm_is("selinux-policy-devel-43.6-4.ph5.noarch.rpm", "selinux-policy"));
        assert!(rpm_is("libselinux-utils-3.10-4.ph5.x86_64.rpm", "libselinux-utils"));
        assert!(!rpm_is("libselinux-3.10-4.ph5.x86_64.rpm", "libselinux-utils"));
        assert!(!rpm_is("libselinux-utils-3.10-4.ph5.x86_64.rpm", "libselinux"));
        assert!(rpm_is("photon-os-installer-2.9-3.ph5.noarch.rpm", "photon-os-installer"));
    }

    /// The correction. Enforcing on >= 92 is the wrong expectation and cost
    /// four false failures.
    #[test]
    fn subrelease_92_expects_permissive_not_enforcing() {
        assert_eq!(expected_selinux(None, Some(92)), Expected::Mode("Permissive"));
        assert_eq!(expected_selinux(None, Some(100)), Expected::Mode("Permissive"));
        assert_eq!(expected_selinux(None, Some(91)), Expected::Mode("Disabled"));
        assert_eq!(expected_selinux(None, Some(90)), Expected::Mode("Enforcing"));
        assert_eq!(expected_selinux(None, Some(89)), Expected::Mode("Enforcing"));
    }

    /// The stale-RPM case: a subrelease-92 build that carried the June
    /// selinux-policy-43.6-3 really does ship enforcing, and the file it
    /// installed says so. The shipped config outranks the subrelease.
    #[test]
    fn the_shipped_config_outranks_the_subrelease() {
        let cfg = "# comment\nSELINUX=enforcing\nSELINUXTYPE=default\n";
        assert_eq!(expected_selinux(Some(cfg), Some(92)), Expected::Mode("Enforcing"));
        assert_eq!(
            expected_selinux(Some("SELINUX=permissive\n"), Some(90)),
            Expected::Mode("Permissive")
        );
        assert_eq!(
            expected_selinux(Some("SELINUX=disabled\n"), None),
            Expected::Mode("Disabled")
        );
    }

    /// A commented-out setting is not a setting. /etc/selinux/config ships
    /// with the alternatives listed in comments above the live line.
    #[test]
    fn commented_lines_are_not_the_setting() {
        let cfg = "# SELINUX=enforcing\n# SELINUX=disabled\nSELINUX=permissive\n";
        assert_eq!(expected_selinux(Some(cfg), None), Expected::Mode("Permissive"));
    }

    /// Unreadable is recorded, never guessed: an oracle that invents an
    /// expectation is how the wrong one got shipped in the first place.
    #[test]
    fn nothing_readable_yields_no_expectation() {
        match expected_selinux(None, None) {
            Expected::Unknown(why) => assert!(why.contains("subrelease")),
            other => panic!("expected Unknown, got {other:?}"),
        }
        match expected_selinux(Some("SELINUX=banana\n"), None) {
            Expected::Unknown(why) => assert!(why.contains("banana")),
            other => panic!("expected Unknown, got {other:?}"),
        }
    }
}
