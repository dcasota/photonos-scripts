//! The VMware NAT DHCP lease file, read as a boot-from-disk signal.
//!
//! `install` had two ways to learn that an install had finished, and on this
//! host only one of them can ever fire:
//!
//!   (a) `root=PARTUUID=` in the serial log. The installed system is
//!       serial-silent - its cmdline carries no `console=ttyS0` - so the log
//!       stays 0 bytes for the whole run. `Facts` already documents this.
//!   (b) `vmrun getGuestIPAddress`. It works, but only once open-vm-tools has
//!       come up AND the tools channel has answered, and its latency is wild:
//!       11 minutes on the c03 run at 08:19Z, and more than the 2400s timeout
//!       on the identical run at 09:13Z, which is the first install timeout
//!       this harness has ever recorded. The guest in that run booted from
//!       disk at 09:15:19 and answered 20 SSH checks afterwards; only the
//!       detector failed.
//!
//! The lease file is a third signal with none of those properties. It is a
//! local file, written by the host's own DHCP server, and it distinguishes
//! the two boot sources by hostname:
//!
//!     09:13:54  192.168.225.186  host=photon-installer   <- live installer
//!     09:15:26  192.168.225.192  host=mc-c03             <- installed system
//!
//! The installed system takes its lease seven seconds after the kernel comes
//! up, so this sees the transition roughly as it happens.
//!
//! The trap is staleness. Leases from PREVIOUS runs of the same row are still
//! in the file under the same MAC and the same hostname, so matching on those
//! alone reports "booted" before the guest has even powered on - a false pass,
//! which is far worse than the false timeout it replaces. Every lookup here is
//! therefore bounded below by the moment the install started.

/// One lease block, with only the fields that matter here.
#[derive(Debug, PartialEq, Eq)]
pub struct Lease {
    pub ip: String,
    pub mac: String,
    pub hostname: String,
    /// `YYYY/MM/DD HH:MM:SS`, UTC, weekday stripped. Fixed width, so a string
    /// compare is a chronological compare and no date library is needed.
    pub starts: String,
}

/// The hostname the Photon installer live environment leases under. It shares
/// the row's MAC, so without this the live env is indistinguishable from the
/// installed system.
pub const INSTALLER_HOSTNAME: &str = "photon-installer";

/// UTC now in the lease file's own format, for use as the `after` bound.
pub fn now_utc() -> String {
    std::process::Command::new("date")
        .args(["-u", "+%Y/%m/%d %H:%M:%S"])
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .filter(|s| !s.is_empty())
        // An empty bound would accept every stale lease in the file. Refusing
        // to answer is the only safe failure here.
        .unwrap_or_else(|| "9999/99/99 99:99:99".into())
}

/// Parse every `lease <ip> { ... }` block. Unknown keys are ignored; a block
/// missing a field yields an empty string for it rather than being dropped,
/// so a malformed entry can never masquerade as a match.
pub fn parse(text: &str) -> Vec<Lease> {
    let mut out = Vec::new();
    let mut cur: Option<Lease> = None;
    for raw in text.lines() {
        let line = raw.trim_end_matches('\r').trim();
        if let Some(rest) = line.strip_prefix("lease ") {
            let ip = rest.split_whitespace().next().unwrap_or("").to_string();
            cur = Some(Lease { ip, mac: String::new(), hostname: String::new(), starts: String::new() });
            continue;
        }
        let Some(l) = cur.as_mut() else { continue };
        if line.starts_with('}') {
            out.push(cur.take().unwrap());
        } else if let Some(v) = line.strip_prefix("hardware ethernet ") {
            l.mac = v.trim_end_matches(';').trim().to_ascii_lowercase();
        } else if let Some(v) = line.strip_prefix("client-hostname ") {
            l.hostname = v.trim_end_matches(';').trim().trim_matches('"').to_string();
        } else if let Some(v) = line.strip_prefix("starts ") {
            // `starts 5 2026/09/04 09:15:26;` - the leading field is a weekday.
            let s = v.trim_end_matches(';').trim();
            let mut it = s.split_whitespace();
            let _weekday = it.next();
            let date = it.next().unwrap_or("");
            let time = it.next().unwrap_or("");
            if !date.is_empty() && !time.is_empty() {
                l.starts = format!("{date} {time}");
            }
        }
    }
    out
}

/// The address the INSTALLED system holds, or None.
///
/// Requires all three of: the row's MAC, a hostname that is the row's VM name
/// (which is what the kickstart sets, and what the live env is not), and a
/// start time strictly after `after`. A row whose guest sets some other
/// hostname simply gets no answer here and falls through to the other signals
/// - silence is correct, a guess is not.
pub fn installed_ip(text: &str, mac: &str, vm_name: &str, after: &str) -> Option<String> {
    let mac = mac.to_ascii_lowercase();
    parse(text)
        .into_iter()
        // The installer hostname is excluded explicitly rather than relying on
        // it differing from the VM name. A row whose kickstart failed to set a
        // hostname, or a VM named after the installer, would otherwise let the
        // live environment answer for the installed system.
        .filter(|l| l.hostname != INSTALLER_HOSTNAME)
        .filter(|l| l.mac == mac && l.hostname == vm_name && l.starts.as_str() > after)
        .max_by(|a, b| a.starts.cmp(&b.starts))
        .map(|l| l.ip)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The real file from the 09:13Z c03 run, trimmed to the blocks that
    /// matter: one stale lease from the 08:19Z run, the live installer, and
    /// the installed system.
    const SAMPLE: &str = r#"
lease 192.168.225.191 {
	starts 5 2026/09/04 08:21:58;
	ends 5 2026/09/04 08:51:58;
	hardware ethernet 00:50:56:3a:00:2a;
	client-hostname "mc-c03";
}
lease 192.168.225.186 {
	starts 5 2026/09/04 09:13:54;
	ends 5 2026/09/04 09:43:54;
	hardware ethernet 00:50:56:3a:00:2a;
	client-hostname "photon-installer";
}
lease 192.168.225.192 {
	starts 5 2026/09/04 09:15:26;
	ends 5 2026/09/04 09:45:26;
	hardware ethernet 00:50:56:3a:00:2a;
	client-hostname "mc-c03";
}
lease 192.168.225.150 {
	starts 5 2026/09/04 09:15:26;
	ends 5 2026/09/04 09:45:26;
	hardware ethernet 00:50:56:ab:cd:ef;
	client-hostname "spagat-runner-2";
}
"#;

    #[test]
    fn parses_every_block_with_its_fields() {
        let l = parse(SAMPLE);
        assert_eq!(l.len(), 4);
        assert_eq!(l[2].ip, "192.168.225.192");
        assert_eq!(l[2].mac, "00:50:56:3a:00:2a");
        assert_eq!(l[2].hostname, "mc-c03");
        assert_eq!(l[2].starts, "2026/09/04 09:15:26");
    }

    #[test]
    fn finds_the_installed_system_and_not_the_installer() {
        // the 09:13Z install began at 09:13:34
        let ip = installed_ip(SAMPLE, "00:50:56:3a:00:2a", "mc-c03", "2026/09/04 09:13:34");
        assert_eq!(ip.as_deref(), Some("192.168.225.192"));
    }

    /// The whole reason for the `after` bound. Before this run's guest has
    /// taken any lease, the file still holds the PREVIOUS run's lease for the
    /// same MAC and the same hostname. Answering from it would report an
    /// install finished that has not started.
    #[test]
    fn a_stale_lease_from_the_previous_run_is_not_an_answer() {
        let only_stale = SAMPLE
            .split("lease 192.168.225.186")
            .next()
            .unwrap();
        assert!(only_stale.contains("192.168.225.191"));
        let ip = installed_ip(only_stale, "00:50:56:3a:00:2a", "mc-c03", "2026/09/04 09:13:34");
        assert_eq!(ip, None, "a lease that predates the install proves nothing");
    }

    #[test]
    fn the_live_installer_is_never_mistaken_for_the_installed_system() {
        // only the installer has leased since the install began
        let upto_installer = SAMPLE.split("lease 192.168.225.192").next().unwrap();
        let ip = installed_ip(upto_installer, "00:50:56:3a:00:2a", "mc-c03", "2026/09/04 09:13:34");
        assert_eq!(ip, None);
        // and it is the hostname that separates them, not the timing
        let l = parse(upto_installer);
        assert!(l.iter().any(|x| x.hostname == INSTALLER_HOSTNAME));
    }

    /// Defence in depth: even if a row were named for the installer, the live
    /// environment must not answer for the installed system.
    #[test]
    fn a_vm_named_like_the_installer_still_gets_no_answer_from_the_live_env() {
        let ip = installed_ip(
            SAMPLE,
            "00:50:56:3a:00:2a",
            INSTALLER_HOSTNAME,
            "2026/09/04 09:13:34",
        );
        assert_eq!(ip, None);
    }

    #[test]
    fn another_vms_lease_is_ignored_even_at_the_same_instant() {
        let ip = installed_ip(SAMPLE, "00:50:56:ab:cd:ef", "mc-c03", "2026/09/04 09:13:34");
        assert_eq!(ip, None);
    }

    #[test]
    fn the_newest_matching_lease_wins() {
        let renewed = format!(
            "{SAMPLE}\nlease 192.168.225.192 {{\n\tstarts 5 2026/09/04 09:45:26;\n\thardware ethernet 00:50:56:3a:00:2a;\n\tclient-hostname \"mc-c03\";\n}}\n"
        );
        let ip = installed_ip(&renewed, "00:50:56:3a:00:2a", "mc-c03", "2026/09/04 09:13:34");
        assert_eq!(ip.as_deref(), Some("192.168.225.192"));
    }

    /// If `date` cannot be run the bound must reject everything rather than
    /// accept everything.
    #[test]
    fn the_fallback_bound_accepts_nothing() {
        let ip = installed_ip(SAMPLE, "00:50:56:3a:00:2a", "mc-c03", "9999/99/99 99:99:99");
        assert_eq!(ip, None);
    }

    #[test]
    fn crlf_from_a_windows_written_file_parses() {
        let dos = SAMPLE.replace('\n', "\r\n");
        let ip = installed_ip(&dos, "00:50:56:3a:00:2a", "mc-c03", "2026/09/04 09:13:34");
        assert_eq!(ip.as_deref(), Some("192.168.225.192"));
    }
}

#[cfg(test)]
mod live_check {
    /// One-off: run the parser over the host's actual lease file.
    #[test]
    #[ignore]
    fn dump_real_file() {
        let p = "/mnt/c/ProgramData/VMware/vmnetdhcp.leases";
        let Ok(t) = std::fs::read_to_string(p) else { return };
        let all = super::parse(&t);
        eprintln!("parsed {} lease block(s)", all.len());
        for l in all.iter().filter(|l| l.mac == "00:50:56:3a:00:2a") {
            eprintln!("  {} {} {} {}", l.starts, l.ip, l.mac, l.hostname);
        }
        eprintln!(
            "installed_ip after 09:13:34 = {:?}",
            super::installed_ip(&t, "00:50:56:3a:00:2a", "mc-c03", "2026/09/04 09:13:34")
        );
        eprintln!(
            "installed_ip after 10:00:00 = {:?}",
            super::installed_ip(&t, "00:50:56:3a:00:2a", "mc-c03", "2026/09/04 10:00:00")
        );
    }
}
