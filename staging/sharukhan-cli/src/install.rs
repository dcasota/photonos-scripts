//! Running one install. Ported from mc-install.sh.
//!
//! vm-lab delegates this to spagat-vm-orchestrator, a cargo artifact of a repo
//! we do not have. Everything it did is reachable with vmrun plus VMX edits;
//! the only genuinely non-trivial piece is deciding when an install has
//! FINISHED, which is done here by watching the boot source change in the
//! serial log.

use crate::config::Config;
use crate::vm::Vm;
use crate::{leases, serial, vm, vmware, winpath};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    /// Kickstart via guestinfo; nobody at the console.
    Auto,
    /// A human drives the curses configurator. The STIG menu is reachable
    /// ONLY from there - stigenable.py is not callable from a kickstart - so
    /// the mode=ui rows cannot be automated at all.
    Interactive,
}

/// What the install phase PROVED, written beside the VM as mc-facts.env.
///
/// mc-verify used to re-derive both facts from scratch and got them wrong: the
/// installed system is serial-silent unless the kickstart's grub edit takes,
/// so `root=PARTUUID=` never appears, and re-querying the guest IP races
/// against first boot. That produced a false k01 FAIL(2). Evidence observed
/// here is authoritative; a later phase must not overturn it by failing to
/// reproduce it.
#[derive(Debug, Default, Clone)]
pub struct Facts {
    pub install_result: String,
    pub guest_ip: String,
}

pub const INSTALLED: &str = "installed";
pub const ERROR_1011: &str = "error1011";
pub const TIMEOUT: &str = "timeout";

pub fn facts_path(dir: &Path) -> PathBuf {
    dir.join("mc-facts.env")
}

/// Kept as KEY=VALUE lines under the name the bash used. The file is the
/// contract between two phases, and an operator reads it with `cat`.
pub fn write_facts(dir: &Path, f: &Facts) -> Result<(), String> {
    let p = facts_path(dir);
    fs::write(
        &p,
        format!(
            "MC_INSTALL_RESULT={}\nMC_GUEST_IP={}\n",
            f.install_result, f.guest_ip
        ),
    )
    .map_err(|e| format!("{}: {e}", p.display()))
}

pub fn read_facts(dir: &Path) -> Option<Facts> {
    let text = fs::read_to_string(facts_path(dir)).ok()?;
    let mut f = Facts::default();
    for line in text.lines() {
        match line.split_once('=') {
            Some(("MC_INSTALL_RESULT", v)) => f.install_result = v.trim().to_string(),
            Some(("MC_GUEST_IP", v)) => f.guest_ip = v.trim().to_string(),
            _ => {}
        }
    }
    Some(f)
}

pub struct Opts {
    pub mode: Mode,
    pub timeout_sec: u64,
    /// Leave the VM running for a human to drive and return immediately. Used
    /// for the UI rows, where blocking would hide the operator instructions
    /// behind a poll loop.
    pub no_wait: bool,
    /// Whether this row's VMX carries a second NIC (the network axis's
    /// management interface for an IPv6-only guest).
    ///
    /// Carried only so a power-on failure can say so. No VM on this host has
    /// ever had two NICs, so if such a row refuses to start, the two-NIC VMX is
    /// by far the likeliest cause - and a run that reported it as a plain
    /// power-on failure would send someone hunting through POI for a defect
    /// that is not there.
    pub second_nic: bool,
}

/// Does this row need a console, or can it run on a host with nobody logged in?
///
/// Only the operator-driven rows do. The STIG menu is reachable only from the
/// curses configurator, so a mode=ui row must have a visible console; a
/// mode=ks row is driven entirely by a kickstart over guestinfo and says of
/// itself that no console interaction is needed.
///
/// This is a policy, not a detail: 27 of the 43 rows are mode=ks, and starting
/// them with `gui` makes every one of them depend on somebody being logged
/// into Windows. On a host without a session vmrun exits 255 and the row fails
/// as "never appeared in the inventory - check for a modal dialog", naming a
/// dialog that does not exist.
pub fn needs_console(mode: Mode) -> bool {
    matches!(mode, Mode::Interactive)
}

/// Does an SSH server answer at `ip`?
///
/// The fourth completion signal, and the only one that works for a row with a
/// STATIC address. Such a guest takes no DHCP lease once installed, so the
/// lease signal cannot fire for it: on n01-n04 the last lease stays
/// `photon-installer` for the whole run. n01 was rescued by the tools probe
/// after ~20 minutes and n02 was not rescued at all, timing out on an install
/// that had in fact finished - the same false timeout the lease signal was
/// added to end, on the rows it could not reach.
///
/// The row's reserved address is the discriminator. It sits BELOW the DHCP
/// floor, so the pool never hands it out, and the installer live environment
/// takes a pool lease rather than the static address - so nothing answers here
/// until the installed system has configured its own network. A DHCP row never
/// configures it at all, so this simply never fires there.
///
/// The banner is checked, not just the connection: a listener on port 22 that
/// is not SSH is not a booted guest, and accepting a bare TCP handshake as
/// proof of boot is how a detector starts lying again.
fn ssh_answers(ip: &str, timeout: std::time::Duration) -> bool {
    use std::io::Read;
    let Ok(addr) = format!("{ip}:22").parse::<std::net::SocketAddr>() else { return false };
    let Ok(mut sock) = std::net::TcpStream::connect_timeout(&addr, timeout) else { return false };
    let _ = sock.set_read_timeout(Some(timeout));
    let mut buf = [0u8; 64];
    match sock.read(&mut buf) {
        Ok(n) => is_ssh_banner(&buf[..n]),
        Err(_) => false,
    }
}

/// An SSH server announces itself before anything else, per RFC 4253.
fn is_ssh_banner(b: &[u8]) -> bool {
    b.starts_with(b"SSH-")
}

pub fn run(
    cfg: &Config,
    vmrow: &Vm,
    o: &Opts,
    log: &mut dyn FnMut(&str),
) -> Result<Facts, String> {
    if !vmrow.vmx.is_file() {
        return Err(format!(
            "no VMX at {} - create the VM first",
            vmrow.vmx.display()
        ));
    }
    let vmx_win = winpath::win_path_checked(&vmrow.vmx.to_string_lossy())
        .map_err(|e| e.to_string())?;

    if let Some(to) = vm::stash_nvram(vmrow) {
        log(&format!(
            "stashed NVRAM as {} so UEFI cannot fall back to a previous image",
            to.file_name().unwrap_or_default().to_string_lossy()
        ));
    }

    // Truncate: the growth of this file from here is the liveness instrument.
    let _ = fs::write(&vmrow.serial, b"");

    // Only an Interactive row needs a console; an Auto row starts headless so
    // it does not depend on somebody being logged into Windows.
    let (waited, rc) = vmware::start_verified(
        &cfg.vmrun,
        &vmx_win,
        &vmrow.name,
        cfg.start_timeout_sec,
        needs_console(o.mode),
    )
    .map_err(|e| {
        if o.second_nic {
            format!(
                "{e}\n       This row's VMX carries a SECOND NIC (network axis: an \n\
                 IPv6-only guest has no other path this harness can reach it by), and no \n\
                 VM on this host has ever had two. Treat the row as unrunnable here on the \n\
                 c02 precedent rather than as a POI defect."
            )
        } else {
            e
        }
    })?;
    log(&format!(
        "{} confirmed running after {waited}s (vmrun rc={rc}, which is not evidence either way)",
        vmrow.name
    ));

    if o.mode == Mode::Interactive {
        log("interactive permutation: the console is up and waiting for the operator");
        log("`sharukhan card --id <id>` prints exactly what to enter");
    } else {
        log("kickstart supplied via guestinfo; no console interaction is needed");
    }

    if o.no_wait {
        log("--no-wait: leaving the VM up for the operator, recording no facts yet");
        return Ok(Facts { install_result: "waiting".into(), guest_ip: String::new() });
    }

    // --- completion detection -------------------------------------------
    // root=/dev/ram0 is the installer live environment; root=PARTUUID= is the
    // installed system. That transition is the only unambiguous "the install
    // finished and the machine came back on its own" signal.
    log(&format!(
        "waiting up to {}s for the guest to boot off disk",
        o.timeout_sec
    ));
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(o.timeout_sec);
    // Bound for the lease signal. Taken BEFORE the guest can lease anything,
    // so a lease left in the file by a previous run of this row - same MAC,
    // same hostname - can never be read as this install finishing.
    let started_at = leases::now_utc();
    let mut last_size = 0u64;
    let mut stalled = 0u32;
    let mut facts = Facts { install_result: TIMEOUT.into(), guest_ip: String::new() };
    while std::time::Instant::now() < deadline {
        std::thread::sleep(std::time::Duration::from_secs(15));
        let size = fs::metadata(&vmrow.serial).map(|m| m.len()).unwrap_or(0);
        if size == last_size {
            stalled += 1;
        } else {
            stalled = 0;
        }
        last_size = size;

        let text = serial::read_clean(&vmrow.serial);
        // Two independent completion signals, because either alone is fragile:
        //  (a) the boot source moves from the installer live env to the disk.
        //      Only visible if the INSTALLED system also has a serial console,
        //      which the kickstart arranges - a stock target is silent here.
        //  (b) the guest answers as a booted machine. open-vm-tools is in the
        //      minimal package set, so a reachable IP means the install
        //      finished and the target came up on its own.
        //  (c) the host's DHCP server hands this row's MAC a lease under the
        //      VM's own hostname. The live installer leases under
        //      `photon-installer`, so the two boot sources are distinguishable,
        //      and the installed system leases within seconds of the kernel
        //      coming up. Checked FIRST because it is a local file read, and
        //      because (a) cannot fire on a serial-silent target while (b) has
        //      taken anywhere from 11 minutes to longer than this timeout.
        if let Ok(text) = fs::read_to_string(&cfg.dhcp_leases) {
            if let Some(ip) = leases::installed_ip(&text, &vmrow.mac, &vmrow.name, &started_at) {
                log(&format!(
                    "{} leased {ip} under its own hostname: the installed system is up",
                    vmrow.name
                ));
                facts.guest_ip = ip;
                facts.install_result = INSTALLED.into();
                break;
            }
        }
        //  (d) the row's reserved address answers SSH. Static rows take no
        //      lease, so (c) cannot reach them; this is the signal that can.
        if !vmrow.reserved_ip.is_empty()
            && ssh_answers(&vmrow.reserved_ip, std::time::Duration::from_secs(2))
        {
            log(&format!(
                "{} answers SSH at its reserved address {}: the installed system is up",
                vmrow.name, vmrow.reserved_ip
            ));
            facts.guest_ip = vmrow.reserved_ip.clone();
            facts.install_result = INSTALLED.into();
            break;
        }
        if serial::count(&text, "root=PARTUUID=") > 0 {
            facts.install_result = INSTALLED.into();
            break;
        }
        if let Some(ip) = vmware::guest_ip(&cfg.vmrun, &vmx_win, false) {
            log(&format!("guest reachable at {ip}"));
            facts.guest_ip = ip;
            facts.install_result = INSTALLED.into();
            break;
        }
        if serial::count(&text, "Error(1011)") > 0 {
            facts.install_result = ERROR_1011.into();
            break;
        }
        // A long quiet stretch is not proof of a stall - no growth is not by
        // itself a hang - so this only reports, never aborts.
        if stalled % 20 == 19 {
            // Say what each signal reports, not just that nothing happened.
            // The 09:13Z c03 timeout printed six identical quiet lines over 40
            // minutes while the guest was up and leased the whole time, and
            // the log gave a reader nothing to tell those two cases apart.
            let leased = fs::read_to_string(&cfg.dhcp_leases)
                .map(|t| {
                    leases::parse(&t)
                        .into_iter()
                        .filter(|l| l.mac.eq_ignore_ascii_case(&vmrow.mac))
                        .map(|l| format!("{}@{} {}", l.hostname, l.starts, l.ip))
                        .next_back()
                        .unwrap_or_else(|| "no lease for this MAC".into())
                })
                .unwrap_or_else(|e| format!("lease file unreadable: {e}"));
            log(&format!(
                "still waiting: serial size={size}, tools ip={}, ssh at {} {}, last lease {leased}",
                vmware::guest_ip(&cfg.vmrun, &vmx_win, false).unwrap_or_else(|| "none".into()),
                vmrow.reserved_ip,
                if ssh_answers(&vmrow.reserved_ip, std::time::Duration::from_secs(2)) {
                    "answers"
                } else {
                    "silent"
                },
            ));
        }
    }

    match facts.install_result.as_str() {
        INSTALLED => log("install completed: guest is booting from disk"),
        ERROR_1011 => log(
            "install FAILED with Error(1011) - a package the installer requested is not on the media",
        ),
        _ => log(&format!(
            "timed out after {}s with no boot-from-disk transition",
            o.timeout_sec
        )),
    }

    write_facts(&vmrow.dir, &facts)?;
    if let Err(e) = vm::detach_cdrom(&vmrow.vmx) {
        log(&format!("could not detach the CDROM: {e}"));
    }
    Ok(facts)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A bare TCP handshake is not proof of a booted guest. Accepting one
    /// would let any listener on port 22 - a forwarder, a scanner, a stale
    /// tunnel - end the wait and report an install that never finished.
    #[test]
    fn only_a_real_ssh_banner_counts() {
        assert!(is_ssh_banner(b"SSH-2.0-OpenSSH_9.6\r\n"));
        assert!(is_ssh_banner(b"SSH-1.99-Something"));
        assert!(!is_ssh_banner(b""));
        assert!(!is_ssh_banner(b"HTTP/1.1 200 OK"));
        assert!(!is_ssh_banner(b"220 ftp ready"));
        // truncated to less than the prefix
        assert!(!is_ssh_banner(b"SS"));
    }

    /// An unreachable address must answer false quickly rather than block the
    /// wait loop. 192.0.2.0/24 is TEST-NET-1 and is guaranteed unroutable.
    #[test]
    fn an_unreachable_address_does_not_answer() {
        let t = std::time::Instant::now();
        assert!(!ssh_answers("192.0.2.1", std::time::Duration::from_millis(300)));
        assert!(t.elapsed() < std::time::Duration::from_secs(5), "must not hang the loop");
    }

    /// A DHCP row still has a reserved address recorded, and nothing is
    /// listening on it. The probe must be inert there, not a false positive.
    #[test]
    fn an_empty_address_is_never_probed() {
        assert!(!ssh_answers("", std::time::Duration::from_millis(100)));
    }

    use super::*;

    #[test]
    fn facts_round_trip_in_the_format_the_operator_reads() {
        let d = std::env::temp_dir().join(format!("sharukhan-facts-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        write_facts(
            &d,
            &Facts { install_result: INSTALLED.into(), guest_ip: "192.168.225.43".into() },
        )
        .unwrap();
        let text = fs::read_to_string(facts_path(&d)).unwrap();
        assert_eq!(text, "MC_INSTALL_RESULT=installed\nMC_GUEST_IP=192.168.225.43\n");
        let f = read_facts(&d).unwrap();
        assert_eq!(f.install_result, "installed");
        assert_eq!(f.guest_ip, "192.168.225.43");
        fs::remove_dir_all(&d).ok();
    }

    /// An install that never found an address still records the result. The
    /// empty IP is a fact too: verify must fall back to asking vmrun, not
    /// assume the phase failed.
    #[test]
    fn an_empty_ip_is_still_a_recorded_fact() {
        let d = std::env::temp_dir().join(format!("sharukhan-facts2-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        write_facts(&d, &Facts { install_result: TIMEOUT.into(), guest_ip: String::new() }).unwrap();
        let f = read_facts(&d).unwrap();
        assert_eq!(f.install_result, "timeout");
        assert!(f.guest_ip.is_empty());
        assert!(read_facts(Path::new("/no/such/vm")).is_none());
        fs::remove_dir_all(&d).ok();
    }
}

#[cfg(test)]
mod start_mode_tests {
    use super::*;

    /// 27 unattended rows must not require a Windows desktop session.
    #[test]
    fn only_the_operator_driven_rows_need_a_console() {
        assert!(needs_console(Mode::Interactive), "mode=ui drives the curses configurator");
        assert!(!needs_console(Mode::Auto), "mode=ks is kickstart over guestinfo");
        assert_eq!(crate::vmware::start_how(needs_console(Mode::Auto)), "nogui");
        assert_eq!(crate::vmware::start_how(needs_console(Mode::Interactive)), "gui");
    }
}
