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
use crate::net::{Family, NetSpec};
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

pub fn guest(
    g: &Guest,
    stig: &str,
    fs: &str,
    canister: &CanisterExpect,
    net: &NetSpec,
    c: &mut Checks,
) {
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
    let fips_on = g.run("cat /proc/sys/crypto/fips_enabled").value_or("0");
    c.check("guest.fips_enabled", "PR#24", Status::Info, "", &fips_on, "");
    let fips_on = fips_on.trim() == "1";
    let v = g
        .run("dmesg 2>/dev/null | grep -c \"canister verification passed\"")
        .value_or("0");
    c.check("guest.fips_canister", "PR#24", Status::Info, "", &v, "");
    canister_identity(g, canister, fips_on, c);

    // One row in the matrix has a link that can NEVER reach `configured`, and
    // it is environmental rather than a defect: the legacy VLAN kickstart
    // forces dhcp4 on the tagged interface, and VMware Workstation 17 has no
    // VLAN-aware switch, so nothing answers a tagged frame.
    // systemd-networkd-wait-online is enabled by preset (SPECS/systemd/
    // 10-defaults.preset) and fails on timeout, which would otherwise regress
    // this assertion for a reason that has nothing to do with any PR. It is
    // EXCLUDED here and asserted POSITIVELY in `network` instead, so the
    // expected failure is recorded rather than hidden.
    let (cmd, why) = if net.expects_wait_online_failure() {
        (
            "systemctl --failed --no-legend --no-pager 2>/dev/null \
             | grep -v systemd-networkd-wait-online | wc -l",
            "first boot may race the SELinux relabel; second boot must be clean. \
             systemd-networkd-wait-online is excluded on this row and asserted \
             separately - see net.wait_online",
        )
    } else {
        (
            "systemctl --failed --no-legend --no-pager 2>/dev/null | wc -l",
            "first boot may race the SELinux relabel; second boot must be clean",
        )
    };
    let v = g.run(cmd).value_or("?");
    c.expect("guest.failed_units", "PR#9", "0", &v, why);

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

    network(g, net, c);
}

// ---- C2. the network axis ------------------------------------------------

/// What the installer's `network` config actually produced in the guest.
///
/// Every assertion here is guest-local by design. On this host the network
/// axis can prove what POI CONFIGURED but not, for most of it, that traffic
/// flows - see the matrix notes for the three IPv6 blockers and the absence of
/// any VLAN backing in Workstation 17. Asserting reachability we cannot have
/// would fail rows for the environment's reasons rather than POI's, which is
/// the one thing this harness exists not to do.
pub fn network(g: &Guest, net: &NetSpec, c: &mut Checks) {
    c.check("net.axis", "-", Status::Info, "", &net.to_string(), "the row's network token");

    // `setup_network(do_clean=True)` DELETES everything in the target's
    // /etc/systemd/network before writing its own files. The shipped
    // 99-dhcp-en.network surviving is the unambiguous signal that
    // _setup_network never ran at all - which otherwise looks exactly like a
    // working DHCP guest, because the shipped file also does DHCP.
    let files = g.run("ls -1 /etc/systemd/network/ 2>/dev/null | tr '\\n' ' '").value_or("none");
    c.check(
        "net.config_files",
        "-",
        Status::Info,
        "",
        &files,
        "POI writes 50-<ks id>.{network,netdev} after clearing the directory",
    );
    let v = g
        .run("ls /etc/systemd/network/99-dhcp-en.network >/dev/null 2>&1 && echo present || echo absent")
        .value_or("?");
    c.expect(
        "net.shipped_default_cleared",
        "-",
        "absent",
        &v,
        "the OS-shipped 99-dhcp-en.network must be gone: its survival means \
         _setup_network never ran, which looks identical to a working DHCP guest",
    );

    // RA is refused on every row this harness generates, and that is a claim
    // about the HOST as much as the guest: vmnetnat.conf has natIp6Enable = 0,
    // so there is no router advertisement on vmnet8 to accept. POI writes
    // IPv6AcceptRA= unconditionally, so the value is always observable.
    let v = g
        .run("grep -h '^IPv6AcceptRA=' /etc/systemd/network/*.network 2>/dev/null | sort -u | tr '\\n' ' '")
        .value_or("absent");
    c.check(
        "net.accept_ra",
        "-",
        Status::Info,
        "",
        &v,
        "no RA exists on vmnet8 to accept (natIp6Enable = 0), so every row asks for 'no'",
    );

    // --- IPv4 ------------------------------------------------------------
    let want_v4 = matches!(net.family, Family::V4 | Family::Dual);
    // Every address, not just the first: a static row that ALSO kept a DHCP
    // lease is the interesting failure, and `$3` alone would hide it.
    let v4 = g
        .run("ip -4 -brief addr show eth0 2>/dev/null | awk '{for(i=3;i<=NF;i++) printf \"%s \", $i}'")
        .value_or("");
    if want_v4 {
        c.check(
            "net.v4_addr",
            "-",
            if v4.trim().is_empty() { Status::Fail } else { Status::Pass },
            "an IPv4 address on eth0",
            v4.trim(),
            "the family axis says this interface carries IPv4",
        );
        let gw = g.run("ip -4 route show default 2>/dev/null | awk '{print $3}'").value_or("none");
        c.check(
            "net.v4_default_route",
            "-",
            if gw == "none" { Status::Fail } else { Status::Pass },
            "a default gateway",
            &gw,
            "VMnet8's NAT device at .2 is both router and DNS forwarder",
        );
        // DNS= in a .network file is inert unless resolved is running.
        // systemd-resolved IS enabled by preset in Photon 5.0, so this is the
        // check that proves the kickstart's nameserver actually took effect.
        let v = g
            .run("getent hosts photon.org >/dev/null 2>&1 && echo ok || echo fail")
            .value_or("?");
        c.expect(
            "net.dns_resolves",
            "-",
            "ok",
            &v,
            "DNS= is inert without systemd-resolved, which Photon enables by preset",
        );
    } else {
        // The point of an IPv6-only row: a dual-stack guest that silently
        // ignored its v6 address would still look healthy, so only an
        // interface with NO IPv4 at all can expose that.
        c.expect(
            "net.v4_absent_on_eth0",
            "-",
            "",
            v4.trim(),
            "the family axis says IPv6 only, so eth0 must carry no IPv4 address",
        );
        let mgmt = g
            .run("ip -4 -brief addr show eth1 2>/dev/null | awk '{print $3}'")
            .value_or("none");
        c.check(
            "net.management_nic",
            "-",
            if mgmt == "none" { Status::Fail } else { Status::Pass },
            "an IPv4 lease on eth1",
            &mgmt,
            "the only path this harness has to an IPv6-only guest",
        );
    }

    // --- IPv6 ------------------------------------------------------------
    if matches!(net.family, Family::V6 | Family::Dual) {
        let v6 = g
            .run("ip -6 -brief addr show eth0 scope global 2>/dev/null | awk '{print $3}'")
            .value_or("");
        c.check(
            "net.v6_addr",
            "-",
            if v6.trim().is_empty() { Status::Fail } else { Status::Pass },
            "a global IPv6 address on eth0",
            v6.trim(),
            "a ULA: this host runs no IPv6 router, so the address is configured, not routed",
        );
        // `tentative` is the silent-failure signature - the address is listed,
        // looks right, and is not usable because DAD never completed.
        let v = g.run("ip -6 addr show eth0 2>/dev/null | grep -c tentative").value_or("?");
        c.expect(
            "net.v6_dad_complete",
            "-",
            "0",
            &v,
            "an address stuck at 'tentative' is listed but unusable",
        );
        // The strongest IPv6 dataplane proof available on this host: no
        // router, no DHCPv6 server and no peer, so the furthest a packet can
        // travel is the guest's own stack. It still distinguishes an address
        // the kernel accepted from one merely written to a file.
        let v = g
            .run(
                "a=$(ip -6 -brief addr show eth0 scope global 2>/dev/null | awk '{print $3}' \
                 | cut -d/ -f1); [ -n \"$a\" ] && ping -6 -c1 -W2 \"$a\" >/dev/null 2>&1 \
                 && echo ok || echo fail",
            )
            .value_or("?");
        c.expect(
            "net.v6_addr_live",
            "-",
            "ok",
            &v,
            "the address answers in the kernel, not just in a config file; \
             off-segment IPv6 is untestable here (no router, no DHCPv6, and WSL2 \
             in NAT mode has no IPv6 stack)",
        );
    }

    // --- VLAN -------------------------------------------------------------
    let Some(vif) = net.vlan_iface() else { return };
    let id = net.vlan.unwrap_or(0);

    // The direct, unambiguous "the tag is real" assertion: not that a file
    // says 100, but that the kernel built an 802.1Q link with that id.
    let v = g
        .run(&format!(
            "ip -d link show {vif} 2>/dev/null | grep -c 'vlan protocol 802.1Q id {id}'"
        ))
        .value_or("0");
    c.expect(
        "net.vlan_link",
        "-",
        "1",
        &v,
        "the tagged interface exists in the kernel with the id the matrix asked for",
    );
    let v = g.run("lsmod 2>/dev/null | grep -c '^8021q'").value_or("0");
    c.expect(
        "net.vlan_module",
        "-",
        "1",
        &v,
        "CONFIG_VLAN_8021Q=m in linux-esx; creating the netdev must auto-load it",
    );
    let v = g
        .run(&format!(
            "grep -lh '^Id={id}$' /etc/systemd/network/*.netdev 2>/dev/null | wc -l"
        ))
        .value_or("0");
    c.expect(
        "net.vlan_netdev",
        "-",
        "1",
        &v,
        "write_netdev_file emits [NetDev] Kind=vlan plus [VLAN] Id=<n>",
    );
    // The parent-side half of the pairing, from _find_vlan_configs ->
    // _get_vlan_iface_name. Its absence means the link resolved to a name POI
    // could not build the tag from.
    let v = g
        .run("grep -h '^VLAN=' /etc/systemd/network/*.network 2>/dev/null | tr '\\n' ' '")
        .value_or("absent");
    c.expect(
        "net.vlan_parent_ref",
        "-",
        // No trailing space: `value_or` trims, so an expected value carrying
        // the separator the `tr` left behind would never compare equal.
        &format!("VLAN={vif}"),
        &v,
        "the parent interface must name the tag it carries",
    );

    // Whether the tag has an address depends on which schema the row uses, and
    // that difference IS the row's finding.
    let addr = g
        .run(&format!("ip -4 -brief addr show {vif} 2>/dev/null | awk '{{print $3}}'"))
        .value_or("");
    if net.expects_wait_online_failure() {
        // Legacy `type: vlan` forces dhcp4 on the tag and nothing on vmnet8
        // answers a tagged frame - VMware Workstation 17 has no VLAN-aware
        // switch. ENVIRONMENTAL, not a POI defect: unlike s02, no change to
        // Photon or the installer would make this succeed here.
        c.expect(
            "net.vlan_addr_absent",
            "-",
            "",
            addr.trim(),
            "expected: the legacy schema forces DHCP on the tag and Workstation \
             has no VLAN-aware switch to answer it. Environmental, not a defect",
        );
        let v = g
            .run("systemctl is-failed systemd-networkd-wait-online.service 2>/dev/null")
            .value_or("?");
        c.expect(
            "net.wait_online",
            "-",
            "failed",
            &v,
            "asserted positively so the expected failure is recorded, not hidden: \
             the stranded link can never reach 'configured', and RequiredForOnline= \
             is unreachable from the kickstart schema - see \
             /root/photon-mc/poi-gap-requiredforonline.md",
        );
    } else {
        c.check(
            "net.vlan_addr",
            "-",
            if addr.trim().is_empty() { Status::Fail } else { Status::Pass },
            "a static address on the tag",
            addr.trim(),
            "static on purpose: a DHCP tag could never reach 'configured' here, \
             and would fail systemd-networkd-wait-online",
        );
        let v = g
            .run("systemctl is-active systemd-networkd-wait-online.service 2>/dev/null")
            .value_or("?");
        c.expect(
            "net.wait_online",
            "-",
            "active",
            &v,
            "every managed link must reach 'configured' when the tag is static",
        );
    }
}

// ---- D. log harvest ------------------------------------------------------

/// The matrix defines no dmesg/journalctl//var/log criteria at all, so this
/// COLLECTS the evidence rather than asserting on it - except the two counts,
/// which are cheap regression detectors.
/// What `guest.canister_based_on` is allowed to read on this row.
///
/// The canister lagging the kernel is the DESIGNED state on a `prebuilt` row -
/// 6.12.60 linked into 6.12.103 is correct, not a defect - so there is nothing
/// to assert there. On an `equivalent` row it is the entire point: phase A
/// stamps the canister with the kernel it was really built from
/// (`canister_stamp_real=1` + `fips_certified_override=<NEVR>`, which
/// linux.spec seds into `FIPS_KERNEL_VERSION` in crypto/fips_integrity.c, which
/// is what the boot line prints as "based on"). Without asserting it, an
/// equivalent build that silently fell back to the certified canister is
/// indistinguishable from one that worked - i.e. a twelve-hour duplicate of
/// k09, which is exactly what canister=build turned out to be.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CanisterExpect {
    /// The row does not vary the canister axis: record which canister booted,
    /// assert nothing.
    Record,
    /// An `equivalent` row: the canister MUST name this kernel NEVR.
    BuiltFrom(String),
    /// An `equivalent` row whose kernel NEVR could not be read. Recorded, never
    /// guessed: asserting against a NEVR we had to invent would fail rows for
    /// the harness's own reason rather than the build's.
    Unresolved(String),
}

/// Decide the expectation from the row's canister axis and the kernel NEVR the
/// build is about.
///
/// `kernel_nevr` is a Result because it is read from the variant patch, which
/// can be missing; and an Ok("") is treated as unreadable too, because an empty
/// expected value would silently pass against an empty actual.
pub fn canister_expectation(
    canister: &str,
    kernel_nevr: Result<String, String>,
) -> CanisterExpect {
    if canister != "equivalent" {
        return CanisterExpect::Record;
    }
    match kernel_nevr {
        Ok(n) if !n.trim().is_empty() => CanisterExpect::BuiltFrom(n.trim().to_string()),
        Ok(_) => CanisterExpect::Unresolved(
            "canister=equivalent, but the kernel NEVR under test came back empty, \
             so there is nothing to compare the boot line against"
                .into(),
        ),
        Err(e) => CanisterExpect::Unresolved(format!(
            "canister=equivalent, but the kernel NEVR under test could not be read \
             ({e}), so the boot line is recorded rather than asserted"
        )),
    }
}

/// Section E - WHICH canister the guest is actually running.
///
/// Three POSITIVE checks, not a hunt for absent errors, because the canister is
/// unusually cooperative: `crypto/fips_integrity.c` announces itself at boot
///
///     FIPS(fips_canister_init): canister 6.12 found (based on 6.12.103-12.ph5)
///
/// and calls `panic()` when integrity fails. So a guest that reaches a login
/// prompt has ALREADY passed canister integrity - that is check one, free.
///
/// The line's "based on" version is the only thing that distinguishes a locally
/// built canister from the prebuilt one. Without it, a build that silently fell
/// back to the certified canister looks exactly like a successful one; that is
/// precisely how a twelve-hour run once re-tested the path already covered by
/// every other row.
pub fn canister_identity(g: &Guest, want: &CanisterExpect, fips_on: bool, c: &mut Checks) {
    let dmesg = g.run("dmesg 2>/dev/null | grep -i canister").value_or("");
    let parsed = crate::canister::parse_boot_line(&dmesg);
    match &parsed {
        Some((canister, _)) => c.check(
            "guest.canister_version",
            "PR#24",
            Status::Info,
            "",
            canister,
            "FIPS_CANISTER_VERSION reported by the running kernel",
        ),
        None => c.check(
            "guest.canister_version",
            "PR#24",
            Status::Info,
            "",
            "absent",
            "no FIPS canister line in dmesg: either a non-FIPS kernel or a \
             non-canister build",
        ),
    }

    // "absent", not "", when there is no line at all: on an `equivalent` row a
    // missing canister is a FAILURE of the mode, and an empty actual against a
    // non-empty expected has to read as one rather than as a blank field.
    let based_on = parsed.as_ref().map(|(_, k)| k.as_str()).unwrap_or("absent");
    let (status, expected, detail) = based_on_check(want, based_on, fips_on);
    c.check("guest.canister_based_on", "PR#24", status, &expected, based_on, &detail);
}

/// The `guest.canister_based_on` verdict, decided without a guest so it can be
/// tested. Returns (status, expected, detail); the actual is the caller's
/// `based_on`.
///
/// Deliberately NOT `Checks::expect`: only the BuiltFrom arm may ever fail, and
/// routing the other two arms through an equality test would make a prebuilt row
/// fail for reading exactly what it is supposed to read.
/// `fips_on` is `/proc/sys/crypto/fips_enabled`. It decides whether a missing
/// line is EVIDENCE OF ABSENCE or merely ABSENCE OF EVIDENCE, and those must
/// not be scored the same way.
///
/// crypto/fips_integrity.c prints `found (based on %s)` from the FIPS self-test
/// path, which only runs when the kernel booted with `fips=1`. On a row whose
/// kickstart does not request FIPS the kernel emits no FIPS output at all, so
/// the stamp cannot appear no matter which canister is linked. c01 proved this
/// the expensive way on 2026-09-02: a correct equivalent build, the right
/// linux-esx installed and booted, and a FAIL that meant nothing but "this row
/// does not boot FIPS".
///
/// Only a row that CAN produce the stamp is allowed to fail for its absence.
/// A wrong stamp is still a hard failure whatever the FIPS state, because that
/// is a contradiction rather than a silence.
pub fn based_on_check(
    want: &CanisterExpect,
    based_on: &str,
    fips_on: bool,
) -> (Status, String, String) {
    if let CanisterExpect::BuiltFrom(nevr) = want {
        if !fips_on && based_on == "absent" {
            return (
                Status::Info,
                nevr.clone(),
                "UNPROVEN: the running kernel prints the canister stamp only \
                 during the FIPS self-test, and this row booted without fips=1 \
                 (/proc/sys/crypto/fips_enabled=0), so the evidence cannot \
                 exist here. The canister linkage is proved at build time only. \
                 A ks_variant=fips row is what would settle it at runtime"
                    .into(),
            );
        }
    }
    match want {
        CanisterExpect::Record => (
            Status::Info,
            String::new(),
            "the kernel the canister was built from - this is what tells a \
             locally built canister apart from the prebuilt one"
                .into(),
        ),
        CanisterExpect::BuiltFrom(nevr) => (
            if based_on == nevr { Status::Pass } else { Status::Fail },
            nevr.clone(),
            "an equivalent canister is stamped with the kernel it was really \
             built from (canister_stamp_real=1 -> FIPS_KERNEL_VERSION), so \
             anything else here means the build fell back to the certified \
             canister and the row is a slow duplicate of the prebuilt one"
                .into(),
        ),
        CanisterExpect::Unresolved(why) => (Status::Info, String::new(), why.clone()),
    }
}

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

    const FILES: [(&str, &str); 12] = [
        ("dmesg", "dmesg.txt"),
        ("journalctl -b --no-pager", "journal-boot.txt"),
        ("journalctl -p err -b --no-pager", "journal-err.txt"),
        ("systemctl --failed --no-pager", "failed-units.txt"),
        ("rpm -qa | sort", "rpm-qa.txt"),
        ("cat /proc/cmdline", "cmdline.txt"),
        ("findmnt -A", "mounts.txt"),
        ("cat /var/log/mkinitrd-*.log 2>/dev/null", "varlog-mkinitrd.txt"),
        ("zcat /var/log/poi/manifest.json.gz 2>/dev/null", "poi-manifest.json"),
        // The network axis asserts on what POI wrote into
        // /etc/systemd/network; the directory listing is what makes a failed
        // assertion readable afterwards without another run.
        (
            "ls -la /etc/systemd/network/ 2>/dev/null; \
             echo; for f in /etc/systemd/network/*; do echo \"== $f\"; cat \"$f\"; done 2>/dev/null",
            "systemd-network.txt",
        ),
        (
            "networkctl --no-pager 2>/dev/null; echo; ip -d addr 2>/dev/null; \
             echo; ip -4 route 2>/dev/null; echo; ip -6 route 2>/dev/null; \
             echo; resolvectl status 2>/dev/null",
            "network-state.txt",
        ),
        // cloud-init is in the `minimal` meta-package (SPECS/minimal/
        // minimal.spec). If it ever runs a datasource on first boot it can
        // rewrite /etc/systemd/network underneath everything asserted above,
        // and a static row would then show a mysteriously wrong address with
        // nothing in the evidence to explain it. Collected, not asserted.
        (
            "cloud-init status --long 2>/dev/null; echo; \
             ls -la /etc/cloud/cloud.cfg.d/ 2>/dev/null",
            "cloud-init.txt",
        ),
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

    // ---- the canister axis ----------------------------------------------

    /// The regression this exists to stop. Before it, `guest.canister_based_on`
    /// was Info on every row, so an `equivalent` build that silently linked the
    /// certified 6.12.60-18.ph5 produced the same evidence as one that worked -
    /// a twelve-hour duplicate of k09 that nothing in the harness could name.
    #[test]
    fn an_equivalent_row_that_booted_the_certified_canister_fails() {
        let want = canister_expectation("equivalent", Ok("6.12.103-14.ph5".into()));
        assert_eq!(want, CanisterExpect::BuiltFrom("6.12.103-14.ph5".into()));

        let (st, exp, _) = based_on_check(&want, "6.12.60-18.ph5", true);
        assert!(st == Status::Fail, "the fallback to the certified canister must fail");
        assert_eq!(exp, "6.12.103-14.ph5");

        let (st, _, _) = based_on_check(&want, "6.12.103-14.ph5", true);
        assert!(st == Status::Pass, "a canister built from the kernel under test must pass");
    }

    /// A `prebuilt` row legitimately boots a canister built from an OLDER
    /// kernel - 6.12.60 linked into 6.12.103 is the DESIGNED state - so the
    /// same value that fails above must not fail here. Asserting on every row
    /// would fail all 34 prebuilt rows for being correct.
    #[test]
    fn a_prebuilt_row_records_its_canister_and_never_fails_on_it() {
        for axis in ["prebuilt", "fips0-aarch64", "build", "acvp", "kat"] {
            let want = canister_expectation(axis, Ok("6.12.103-14.ph5".into()));
            assert_eq!(want, CanisterExpect::Record, "{axis} must not be asserted");
            for seen in ["6.12.60-18.ph5", "6.12.103-14.ph5", "absent"] {
                let (st, exp, _) = based_on_check(&want, seen, false);
                assert!(st == Status::Info, "{axis}/{seen} must stay informational");
                assert!(exp.is_empty(), "a recorded check states no expectation");
            }
        }
    }

    /// A missing canister line means different things depending on whether the
    /// row could have produced one, and the oracle must not conflate them.
    ///
    /// The original version of this test asserted that absence always fails an
    /// equivalent row, reasoning that a non-FIPS kernel and an unreadable dmesg
    /// both mean "cannot be shown to work". c01 disproved that on 2026-09-02:
    /// a correct equivalent build, linux-esx-6.12.103-14 installed and booted,
    /// and a FAIL whose only content was that the row does not boot fips=1.
    /// The kernel prints the stamp from the FIPS self-test, so on a row without
    /// fips=1 no canister on earth would produce it.
    #[test]
    fn absence_fails_only_where_the_stamp_could_have_appeared() {
        let eq = canister_expectation("equivalent", Ok("6.12.103-14.ph5".into()));

        // Booted fips=1 and still no stamp: the mode genuinely did not work.
        assert!(based_on_check(&eq, "absent", true).0 == Status::Fail);

        // Booted without fips=1: unobtainable, not contradicted. This is c01.
        let (st, exp, why) = based_on_check(&eq, "absent", false);
        assert!(st == Status::Info, "a row that cannot emit the stamp must not fail for it");
        assert_eq!(exp, "6.12.103-14.ph5", "the expectation is still stated, just not asserted");
        assert!(why.contains("UNPROVEN"), "the detail must say the claim is unproven, not fine");

        // A WRONG stamp is a contradiction, and fails whatever the FIPS state:
        // the kernel emitted an identity, and it was the certified canister.
        assert!(based_on_check(&eq, "6.12.60-18.ph5", false).0 == Status::Fail);

        let pre = canister_expectation("prebuilt", Ok("6.12.103-14.ph5".into()));
        assert!(based_on_check(&pre, "absent", true).0 == Status::Info);
        assert!(based_on_check(&pre, "absent", false).0 == Status::Info);
    }

    /// An unreadable kernel NEVR must never become an expectation. Asserting
    /// against a NEVR the harness invented would fail the row for the harness's
    /// own reason, which is exactly the failure mode the SELinux oracle taught.
    #[test]
    fn an_unreadable_kernel_nevr_is_recorded_rather_than_asserted() {
        for got in [Err("no variant patch".to_string()), Ok(String::new()), Ok("   ".into())] {
            let want = canister_expectation("equivalent", got);
            match &want {
                CanisterExpect::Unresolved(why) => {
                    assert!(why.contains("equivalent"), "the detail must say why: {why}")
                }
                other => panic!("expected Unresolved, got {other:?}"),
            }
            // and it must not fail the row
            assert!(based_on_check(&want, "6.12.60-18.ph5", false).0 == Status::Info);
        }
    }

    /// Phase A is conditional, and the assertion has to hold in BOTH plans.
    /// When a canister is published at the kernel level under test the build
    /// links it and skips phase A - and that canister is stamped with the same
    /// NEVR, so the expected value is unchanged. If it ever were not, the check
    /// firing is the finding.
    #[test]
    fn the_expectation_is_the_same_whether_or_not_phase_a_ran() {
        let kernel = "6.12.103-14.ph5";
        let want = canister_expectation("equivalent", Ok(kernel.into()));
        // Plan::BuildThenLink: phase A stamped the kernel it built from.
        assert!(based_on_check(&want, kernel, true).0 == Status::Pass);
        // Plan::LinkPublished: the published canister IS at this NEVR.
        assert!(based_on_check(&want, kernel, true).0 == Status::Pass);
    }

    /// The end-to-end shape, from a real boot line to a verdict: the string the
    /// kernel prints is what the assertion is made against, so a change to
    /// either half has to break this test.
    #[test]
    fn the_verdict_is_taken_from_the_kernels_own_boot_line() {
        let certified =
            "[    1.2] FIPS(fips_canister_init): canister 6.12 found (based on 6.12.60-18.ph5)";
        let local =
            "[    1.2] FIPS(fips_canister_init): canister 6.12 found (based on 6.12.103-14.ph5)";
        let want = canister_expectation("equivalent", Ok("6.12.103-14.ph5".into()));
        let read = |d: &str| {
            crate::canister::parse_boot_line(d)
                .map(|(_, k)| k)
                .unwrap_or_else(|| "absent".into())
        };
        assert!(based_on_check(&want, &read(certified), true).0 == Status::Fail);
        assert!(based_on_check(&want, &read(local), true).0 == Status::Pass);
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
