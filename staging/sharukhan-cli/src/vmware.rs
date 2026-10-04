//! Talking to VMware Workstation.

use std::path::Path;
use std::process::{Command, Output};

/// Run a Windows program and collect its output, retrying while WSL interop
/// to Windows does not answer (only WSL's own "UtilAcceptVsock ... accept4
/// failed" on stderr counts; the program never ran then). Anything the
/// program itself returns, success or failure, is returned at once.
pub fn win_output(program: &Path, args: &[&str]) -> std::io::Result<Output> {
    let mut attempt = 0;
    loop {
        attempt += 1;
        let out = Command::new(program).args(args).output()?;
        if out.status.success()
            || !crate::vm::interop_unavailable(&out.stderr)
            || attempt >= crate::vm::INTEROP_ATTEMPTS
        {
            return Ok(out);
        }
        eprintln!(
            "[mc] {}: WSL interop to Windows did not answer (attempt {attempt}/{}); retrying in {}s",
            program.file_name().unwrap_or_default().to_string_lossy(),
            crate::vm::INTEROP_ATTEMPTS,
            crate::vm::INTEROP_PAUSE.as_secs()
        );
        std::thread::sleep(crate::vm::INTEROP_PAUSE);
    }
}

/// Names of the VMs vmrun reports as running.
///
/// vmrun is a Windows binary: its output is CRLF-terminated, and reading it
/// without stripping '\r' makes every comparison fail while looking fine.
pub fn running(vmrun: &Path) -> Result<Vec<String>, String> {
    if !vmrun.exists() {
        return Err(format!("vmrun not found at {}", vmrun.display()));
    }
    let out = win_output(vmrun, &["-T", "ws", "list"])
        .map_err(|e| format!("running vmrun: {e}"))?;
    if !out.status.success() {
        return Err(format!("vmrun exited {}", out.status));
    }
    Ok(String::from_utf8_lossy(&out.stdout)
        .lines()
        .map(|l| l.trim_end_matches('\r').trim().to_string())
        .filter(|l| l.ends_with(".vmx"))
        .collect())
}

/// Whether a specific VM is in the inventory - or Err when vmrun could not
/// say. Callers that are about to move a VM's files must treat Err as "maybe
/// running", never as "stopped".
pub fn running_state(vmrun: &Path, vm: &str) -> Result<bool, String> {
    running(vmrun).map(|v| {
        v.iter()
            .any(|l| l.to_lowercase().contains(&format!("{}.vmx", vm.to_lowercase())))
    })
}

/// Stop our VM and prove it is gone before anyone moves its files: Ok(true)
/// when it was running and is now stopped, Ok(false) when it was not running,
/// Err when its state is unknown or it is still running after the stop.
pub fn ensure_stopped(vmrun: &Path, vmx_win: &str, vm: &str) -> Result<bool, String> {
    match running_state(vmrun, vm)? {
        false => Ok(false),
        true => {
            stop_hard(vmrun, vmx_win);
            for _ in 0..24 {
                std::thread::sleep(std::time::Duration::from_secs(5));
                if !running_state(vmrun, vm)? {
                    return Ok(true);
                }
            }
            Err(format!("{vm} is still running 2 minutes after a hard stop"))
        }
    }
}

/// Whether a specific VM is in the inventory.
///
/// vmrun exits 0 even when a VM did not actually come up - a stale modal in the
/// Workstation UI silently swallows the power-on - so a start must be confirmed
/// against the inventory rather than trusted from the exit code.
pub fn is_running(vmrun: &Path, vm: &str) -> bool {
    running(vmrun)
        .map(|v| {
            v.iter().any(|l| {
                l.to_lowercase()
                    .contains(&format!("{}.vmx", vm.to_lowercase()))
            })
        })
        .unwrap_or(false)
}

/// Issue a power-on and ignore what vmrun claims.
///
/// vmrun's exit code is not evidence in EITHER direction. It exits 0 when a
/// stale modal in the Workstation UI has silently swallowed the power-on, and
/// it exits non-zero when the VM is merely slow to start - attaching a 3.9G
/// full ISO trips its internal timeout while VMware carries on powering the VM
/// up regardless. Both were observed on this host. Trusting the exit code once
/// cost a full 40-minute timeout waiting on a VM that never existed.
///
/// `gui`, not `nogui`: on this host `vmrun -T ws start <vmx> nogui` fails with
/// "Error: Unknown error" and does not even create a vmware.log, while the
/// identical VMX starts fine with "gui". Headless start needs VMware
/// Workstation Server / shared-VM support, which is not enabled here.
pub fn start_how(gui: bool) -> &'static str {
    if gui {
        "gui"
    } else {
        "nogui"
    }
}

pub fn start(vmrun: &Path, vmx_win: &str, gui: bool) -> i32 {
    // `gui` needs an interactive Windows desktop session to attach to. Without
    // one - a detached WSL shell, a disconnected RDP session, the machine
    // locked - vmrun exits 255 and the VM never enters the inventory, which
    // the caller can only report as "never appeared ... check for a modal
    // dialog". There is no dialog; there is no session.
    //
    // A mode=ks row is driven entirely by a kickstart delivered over
    // guestinfo and says so itself: "no console interaction is needed". It has
    // nothing to show anyone, so it starts headless and runs on a host with
    // nobody logged in. A mode=ui row genuinely needs the console - the STIG
    // menu is reachable only from the curses configurator - so it keeps the
    // GUI and fails loudly when there is no session to give it.
    let how = start_how(gui);
    win_output(vmrun, &["-T", "ws", "start", vmx_win, how])
        .map(|o| o.status.code().unwrap_or(-1))
        .unwrap_or(-1)
}

/// Start, then believe only the inventory.
///
/// Returns how long the VM took to appear. The caller gets the vmrun exit code
/// too, but only to print it: the inventory is the authority.
pub fn start_verified(
    vmrun: &Path,
    vmx_win: &str,
    vm: &str,
    timeout_secs: u64,
    gui: bool,
) -> Result<(u64, i32), String> {
    let rc = start(vmrun, vmx_win, gui);
    let mut waited = 0;
    while waited < timeout_secs {
        if is_running(vmrun, vm) {
            return Ok((waited, rc));
        }
        std::thread::sleep(std::time::Duration::from_secs(5));
        waited += 5;
    }
    Err(format!(
        "{vm} never appeared in the inventory after {waited}s (vmrun rc={rc}) - check for a \
         modal dialog in the VMware Workstation UI"
    ))
}

/// Power off one VM, hard. Only ever called with our own VM's path: other VMs
/// on this host may be live CI runners.
pub fn stop_hard(vmrun: &Path, vmx_win: &str) -> i32 {
    win_output(vmrun, &["-T", "ws", "stop", vmx_win, "hard"])
        .map(|o| o.status.code().unwrap_or(-1))
        .unwrap_or(-1)
}

/// The address open-vm-tools reports, or None.
///
/// `vmx_win` must be the WINDOWS path. vmrun.exe is a Windows binary and a
/// /mnt/c/... argument names a file it cannot open, so it answers nothing -
/// which is indistinguishable from a guest that has not booted yet.
pub fn guest_ip(vmrun: &Path, vmx_win: &str, wait: bool) -> Option<String> {
    let mut args = vec!["-T", "ws", "getGuestIPAddress", vmx_win];
    if wait {
        args.push("-wait");
    }
    let out = win_output(vmrun, &args).ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    let lines: Vec<&str> = text
        .lines()
        .map(|l| l.trim_end_matches('\r').trim())
        .collect();
    let found = lines
        .iter()
        .filter(|l| looks_like_ipv4(l))
        .next_back()
        .map(|s| s.to_string());

    // "no address" and "an address this harness cannot reach" are different
    // facts, and the filter erases the difference. An IPv6-only guest gets an
    // answer from vmrun and then reads as if it never booted, which sends the
    // reader looking at the install instead of at the network. WSL2 here has no
    // IPv6 route, so the address is genuinely unusable - but say which it is.
    if found.is_none() {
        if let Some(other) = lines
            .iter()
            .find(|l| l.contains(':') && !l.starts_with("Error"))
        {
            eprintln!(
                "[mc] vmrun answered {other:?}, which is not IPv4; this harness reaches guests \
                 over IPv4 only, so it is being ignored rather than used"
            );
        }
    }
    found
}

/// Four dot-separated decimal octets. vmrun prints its errors on stdout too
/// ("Error: The operation was canceled"), so a substring match on '.' would
/// take an error message for an address.
pub fn looks_like_ipv4(s: &str) -> bool {
    let parts: Vec<&str> = s.split('.').collect();
    parts.len() == 4
        && parts
            .iter()
            .all(|p| !p.is_empty() && p.len() <= 3 && p.chars().all(|c| c.is_ascii_digit()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_real_addresses_are_addresses() {
        assert!(looks_like_ipv4("192.168.225.41"));
        assert!(looks_like_ipv4("10.0.0.1"));
        assert!(!looks_like_ipv4("Error: The operation was canceled"));
        assert!(!looks_like_ipv4("192.168.225"));
        assert!(!looks_like_ipv4("192.168.225.41.9"));
        assert!(!looks_like_ipv4("mc-k01.vmx"));
        assert!(!looks_like_ipv4(""));
    }
}

#[cfg(test)]
mod stop_tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    /// A vmrun stand-in: `list` prints the VM while the state file exists
    /// (or fails when told to), `stop` removes the state file.
    fn fake_vmrun(dir: &std::path::Path, running: bool, list_fails: bool) -> std::path::PathBuf {
        let state = dir.join("running");
        if running {
            std::fs::write(&state, "").unwrap();
        }
        let script = dir.join("vmrun");
        let list = if list_fails {
            "echo 'Error: unable to connect' >&2; exit 255".to_string()
        } else {
            format!(
                "if [ -e {s} ]; then echo 'Total running VMs: 1'; echo 'C:\\vm\\mc-k02\\mc-k02.vmx'; else echo 'Total running VMs: 0'; fi",
                s = state.display()
            )
        };
        std::fs::write(
            &script,
            format!(
                "#!/bin/sh\ncase \"$3\" in\n list) {list} ;;\n stop) echo stop >> {d}/stops; rm -f {s} ;;\nesac\n",
                d = dir.display(),
                s = state.display()
            ),
        )
        .unwrap();
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
        script
    }

    #[test]
    fn files_move_only_once_the_vm_is_proven_stopped() {
        let base = std::env::temp_dir().join(format!("shk-stop-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        for (case, running, fails) in [("off", false, false), ("on", true, false), ("unknown", true, true)] {
            let d = base.join(case);
            std::fs::create_dir_all(&d).unwrap();
            let v = fake_vmrun(&d, running, fails);
            let r = ensure_stopped(&v, "C:\\vm\\mc-k02\\mc-k02.vmx", "mc-k02");
            let stops = std::fs::read_to_string(d.join("stops")).unwrap_or_default();
            match case {
                "off" => {
                    assert_eq!(r, Ok(false));
                    assert!(stops.is_empty());
                }
                "on" => {
                    assert_eq!(r, Ok(true));
                    assert_eq!(stops.lines().count(), 1);
                }
                _ => {
                    // vmrun could not answer: never "stopped", never stopped blind
                    assert!(r.is_err(), "{r:?}");
                    assert!(stops.is_empty());
                }
            }
        }
        let _ = std::fs::remove_dir_all(&base);
    }
}
