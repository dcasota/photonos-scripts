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
