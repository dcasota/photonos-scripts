//! Talking to VMware Workstation.

use std::path::Path;
use std::process::Command;

/// Names of the VMs vmrun reports as running.
///
/// vmrun is a Windows binary: its output is CRLF-terminated, and reading it
/// without stripping '\r' makes every comparison fail while looking fine.
pub fn running(vmrun: &Path) -> Result<Vec<String>, String> {
    if !vmrun.exists() {
        return Err(format!("vmrun not found at {}", vmrun.display()));
    }
    let out = Command::new(vmrun)
        .args(["-T", "ws", "list"])
        .output()
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

/// Whether a specific VM is in the inventory.
///
/// vmrun exits 0 even when a VM did not actually come up - a stale modal in the
/// Workstation UI silently swallows the power-on - so a start must be confirmed
/// against the inventory rather than trusted from the exit code.
pub fn is_running(vmrun: &Path, vm: &str) -> bool {
    running(vmrun)
        .map(|v| v.iter().any(|l| l.to_lowercase().contains(&format!("{}.vmx", vm.to_lowercase()))))
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
pub fn start(vmrun: &Path, vmx_win: &str) -> i32 {
    Command::new(vmrun)
        .args(["-T", "ws", "start", vmx_win, "gui"])
        .output()
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
) -> Result<(u64, i32), String> {
    let rc = start(vmrun, vmx_win);
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
    Command::new(vmrun)
        .args(["-T", "ws", "stop", vmx_win, "hard"])
        .output()
        .map(|o| o.status.code().unwrap_or(-1))
        .unwrap_or(-1)
}

/// The address open-vm-tools reports, or None.
///
/// `vmx_win` must be the WINDOWS path. vmrun.exe is a Windows binary and a
/// /mnt/c/... argument names a file it cannot open, so it answers nothing -
/// which is indistinguishable from a guest that has not booted yet.
pub fn guest_ip(vmrun: &Path, vmx_win: &str, wait: bool) -> Option<String> {
    let mut cmd = Command::new(vmrun);
    cmd.args(["-T", "ws", "getGuestIPAddress", vmx_win]);
    if wait {
        cmd.arg("-wait");
    }
    let out = cmd.output().ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    let lines: Vec<&str> = text.lines().map(|l| l.trim_end_matches('\r').trim()).collect();
    let found = lines.iter().filter(|l| looks_like_ipv4(l)).next_back().map(|s| s.to_string());

    // "no address" and "an address this harness cannot reach" are different
    // facts, and the filter erases the difference. An IPv6-only guest gets an
    // answer from vmrun and then reads as if it never booted, which sends the
    // reader looking at the install instead of at the network. WSL2 here has no
    // IPv6 route, so the address is genuinely unusable - but say which it is.
    if found.is_none() {
        if let Some(other) = lines.iter().find(|l| l.contains(':') && !l.starts_with("Error")) {
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
        && parts.iter().all(|p| {
            !p.is_empty() && p.len() <= 3 && p.chars().all(|c| c.is_ascii_digit())
        })
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
