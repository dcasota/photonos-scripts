//! The VM on disk: directory, thin boot disk, VMX, and taking it all back to a
//! fresh-disk state. Ported from mc-create-vm.sh and mc-teardown.sh.
//!
//! vm-lab splits this across a .ps1 because vmware-vdiskmanager wants Windows
//! paths. That split costs a whole second language with its own CRLF and
//! ASCII-only-for-PowerShell-5.1 constraints, and cannot be tested from the
//! Linux side at all. The .exe runs fine from WSL, so the only thing needed is
//! the path conversion - see [`crate::winpath`].

use crate::config::Config;
use crate::matrix::Permutation;
use crate::{identity, job, vmware, vmx, winpath};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub struct Vm {
    pub name: String,
    pub dir: PathBuf,
    pub vmx: PathBuf,
    pub vmdk: PathBuf,
    pub serial: PathBuf,
    /// Ordinal in permutations.tsv - the whole of this VM's identity.
    pub index: usize,
    pub mac: String,
    pub uuid: String,
    /// The address the matrix reserves for this row. Not necessarily the
    /// address the guest took: an interactive install may have taken a DHCP
    /// lease the kickstart never pinned.
    pub reserved_ip: String,
}

/// Names and addresses for one row, computed and never guessed.
pub fn plan(cfg: &Config, id: &str) -> Result<Vm, String> {
    let tsv = fs::read_to_string(&cfg.matrix_tsv)
        .map_err(|e| format!("{}: {e}", cfg.matrix_tsv.display()))?;
    let index = identity::perm_index(&tsv, id).map_err(|e| e.to_string())?;
    let name = cfg.vm_name(id);
    let dir = cfg.vm_dir(id);
    Ok(Vm {
        vmx: dir.join(format!("{name}.vmx")),
        vmdk: dir.join(format!("{name}.vmdk")),
        serial: cfg.serial_log(id),
        mac: identity::mac_for(index),
        uuid: identity::uuid_for(index),
        reserved_ip: identity::ip_for(&cfg.net_prefix, cfg.ip_base, index),
        index,
        name,
        dir,
    })
}

/// Resolve the ISO to something VMware can actually open.
///
/// photon.iso is a symlink, and a WSL symlink on drvfs is not reliably
/// followable by a Windows process, so the concrete filename goes in the VMX.
/// A path outside /mnt/<drive>/ is refused here rather than written: VMware
/// would report only "Error: The operation was canceled", which names nothing.
pub fn iso_for_vmx(iso: &Path) -> Result<String, String> {
    if !iso.is_file() {
        return Err(format!("--iso must name an existing file: {}", iso.display()));
    }
    let real = fs::canonicalize(iso).map_err(|e| format!("{}: {e}", iso.display()))?;
    winpath::win_path_checked(&real.to_string_lossy())
        .map_err(|e| format!("{e}\n       (MC_ISO_CACHE must be under /mnt/<drive>/)"))
}

/// Create or re-create one permutation's VM. Returns the VMX path.
pub fn create(
    cfg: &Config,
    p: &Permutation,
    iso: &Path,
    kickstart_json: Option<String>,
    recreate: bool,
    log: &mut dyn FnMut(&str),
) -> Result<Vm, String> {
    let vm = plan(cfg, &p.id)?;
    let iso_win = iso_for_vmx(iso)?;
    let dir_win = winpath::win_path_checked(&vm.dir.to_string_lossy())
        .map_err(|e| format!("{e}\n       (MC_VM_ROOT_WSL must be under /mnt/<drive>/)"))?;

    if vm.dir.is_dir() && recreate {
        let n = stash_contents(&vm.dir)?;
        log(&format!(
            "recreate: stashed {n} file(s), path kept stable for VMware"
        ));
    }
    fs::create_dir_all(&vm.dir).map_err(|e| format!("{}: {e}", vm.dir.display()))?;

    if vm.vmdk.exists() {
        log("disk already present, keeping it");
    } else {
        create_disk(cfg, &dir_win, &vm.name)?;
        let size = fs::metadata(&vm.vmdk).map(|m| m.len()).unwrap_or(0);
        log(&format!(
            "created thin disk: {} MB of {} (monolithicSparse, grows as the guest writes)",
            size / 1_048_576,
            cfg.boot_disk_size
        ));
    }

    let ks = match kickstart_json {
        Some(json) => {
            log(&format!("kickstart injected via guestinfo ({} bytes)", json.len()));
            Some(vmx::Kickstart { json })
        }
        None => {
            log("no kickstart - interactive permutation, the installer falls through to curses");
            None
        }
    };
    let serial_win = winpath::win_path_checked(&vm.serial.to_string_lossy())
        .map_err(|e| e.to_string())?;
    let spec = vmx::VmSpec::for_permutation(
        cfg,
        p,
        vm.mac.clone(),
        vm.uuid.clone(),
        iso_win,
        serial_win,
        ks,
    );
    let text = vmx::render(&spec)?;
    fs::write(&vm.vmx, text).map_err(|e| format!("{}: {e}", vm.vmx.display()))?;

    log(&format!(
        "vm={} ip={} mac={} vmx={}",
        vm.name,
        vm.reserved_ip,
        vm.mac,
        vm.vmx.display()
    ));
    Ok(vm)
}

/// -t 0 is monolithicSparse: one file, thin. A fresh 32 GB disk is a few MB
/// and grows only as the guest writes. The hand-made test VM on this host is
/// monolithicFlat and commits its full size up front; 34 of those would not
/// fit in the free space on C:.
fn create_disk(cfg: &Config, dir_win: &str, name: &str) -> Result<(), String> {
    if !cfg.vdiskmanager.exists() {
        return Err(format!(
            "vmware-vdiskmanager not found at {}",
            cfg.vdiskmanager.display()
        ));
    }
    let target = format!("{dir_win}\\{name}.vmdk");
    let out = Command::new(&cfg.vdiskmanager)
        .args(["-c", "-s", &cfg.boot_disk_size, "-a", &cfg.boot_disk_adapter, "-t", &cfg.boot_disk_type])
        .arg(&target)
        .output()
        .map_err(|e| format!("running vmware-vdiskmanager: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "vmware-vdiskmanager failed for {name} (rc={}): {}",
            out.status.code().unwrap_or(-1),
            String::from_utf8_lossy(&out.stdout).trim_end_matches(['\r', '\n']).trim()
        ));
    }
    Ok(())
}

/// Stash the CONTENTS, never the directory itself.
///
/// Because headless start does not work on this host, VMs are started with
/// "gui", which leaves VMware Workstation holding the VM open in its
/// inventory. Moving the whole directory away pulls the .vmx out from under
/// it, and VMware raises a modal:
///   "An error occurred while opening configuration file ...: Could not find
///    the file."
/// That modal then blocks the NEXT power-on request, so the run waits on a VM
/// that never started. msg.autoAnswer=TRUE does not cover it - it answers VM
/// questions, not inventory-level file errors.
///
/// Keeping the path stable means VMware's open reference stays valid.
fn stash_contents(dir: &Path) -> Result<usize, String> {
    let stash = dir.join(format!("stash-{}", job::stamp()));
    fs::create_dir_all(&stash).map_err(|e| format!("{}: {e}", stash.display()))?;
    let mut moved = 0;
    for e in fs::read_dir(dir).map_err(|e| format!("{}: {e}", dir.display()))?.flatten() {
        let name = e.file_name().to_string_lossy().to_string();
        if name.starts_with("stash-") {
            continue;
        }
        if fs::rename(e.path(), stash.join(&name)).is_ok() {
            moved += 1;
        }
    }
    Ok(moved)
}

/// UEFI ignores bios.bootOrder, so the only way to stop the firmware booting
/// the PREVIOUS image out of the old ESP is to remove the NVRAM. Deleting the
/// disk alone does not help, because UEFI re-detects.
pub fn stash_nvram(vm: &Vm) -> Option<PathBuf> {
    let nvram = vm.dir.join(format!("{}.nvram", vm.name));
    if !nvram.exists() {
        return None;
    }
    let to = vm.dir.join(format!("{}.nvram.stashed-{}", vm.name, job::stamp()));
    fs::rename(&nvram, &to).ok().map(|_| to)
}

/// Detach the CDROM so a later boot cannot re-enter the installer.
pub fn detach_cdrom(vmx: &Path) -> Result<(), String> {
    let text = fs::read_to_string(vmx).map_err(|e| format!("{}: {e}", vmx.display()))?;
    let out = text.replace(
        "sata0:1.startConnected = \"TRUE\"",
        "sata0:1.startConnected = \"FALSE\"",
    );
    fs::write(vmx, out).map_err(|e| format!("{}: {e}", vmx.display()))
}

pub struct TeardownReport {
    pub stashed: usize,
    pub serial_logs_kept: usize,
    pub purged_files: usize,
    pub purged_stash_dirs: usize,
    pub was_running: bool,
}

/// Return one permutation's VM to a fresh-disk state.
///
/// Nothing is deleted; files are renamed .stashed-<ts> and recovery is a
/// rename back. The whole disk chain goes, not just the disk: if any piece
/// survives, UEFI's removable-media fallback finds the old ESP and boots the
/// PREVIOUS image - and bios.bootOrder is ignored on EFI VMs, so that is the
/// only control there is.
///
/// The serial log and the results directory are always preserved: they are the
/// evidence the run produced.
pub fn teardown(
    cfg: &Config,
    id: &str,
    purge: bool,
    log: &mut dyn FnMut(&str),
) -> Result<TeardownReport, String> {
    let name = cfg.vm_name(id);
    let dir = cfg.vm_dir(id);
    let mut r = TeardownReport {
        stashed: 0,
        serial_logs_kept: 0,
        purged_files: 0,
        purged_stash_dirs: 0,
        was_running: false,
    };
    if !dir.is_dir() {
        log(&format!("{} does not exist, nothing to tear down", dir.display()));
        return Ok(r);
    }

    // Only ever stop our own VM. Other VMs on this host may be live CI runners.
    if vmware::is_running(&cfg.vmrun, &name) {
        r.was_running = true;
        log(&format!("stopping {name}"));
        let vmx_win = winpath::win_path(&dir.join(format!("{name}.vmx")).to_string_lossy());
        vmware::stop_hard(&cfg.vmrun, &vmx_win);
        std::thread::sleep(std::time::Duration::from_secs(3));
    }

    let ts = job::stamp();
    // Globbed by extension, not enumerated: a fixed list of two snapshot
    // deltas silently leaves an orphan on a VM that reached -000003.vmdk.
    const CHAIN: [&str; 5] = ["vmdk", "vmsn", "vmsd", "nvram", "vmss"];
    for e in fs::read_dir(&dir).map_err(|e| format!("{}: {e}", dir.display()))?.flatten() {
        let path = e.path();
        let name = e.file_name().to_string_lossy().to_string();
        if name.contains(".stashed-") {
            continue;
        }
        let ext = path.extension().map(|x| x.to_string_lossy().to_string()).unwrap_or_default();
        if path.is_file() && CHAIN.contains(&ext.as_str()) {
            let to = dir.join(format!("{name}.stashed-{ts}"));
            if fs::rename(&path, &to).is_ok() {
                r.stashed += 1;
            }
        }
        if ext == "lck" || path.is_dir() && name.ends_with(".lck") {
            let _ = fs::remove_dir_all(&path);
            let _ = fs::remove_file(&path);
        }
    }
    log(&format!("stashed {} file(s) with suffix .stashed-{ts}", r.stashed));

    r.serial_logs_kept = fs::read_dir(&dir)
        .map(|d| {
            d.flatten()
                .filter(|e| {
                    let n = e.file_name().to_string_lossy().to_string();
                    n.starts_with(&cfg.serial_log_prefix) && n.ends_with(".log")
                })
                .count()
        })
        .unwrap_or(0);
    log(&format!(
        "preserved {} serial log(s) - they are this run's evidence",
        r.serial_logs_kept
    ));

    if purge {
        for e in fs::read_dir(&dir).map_err(|e| format!("{}: {e}", dir.display()))?.flatten() {
            let name = e.file_name().to_string_lossy().to_string();
            let path = e.path();
            if name.contains(".stashed-") && path.is_file() {
                if fs::remove_file(&path).is_ok() {
                    r.purged_files += 1;
                }
            } else if name.starts_with("stash-") && path.is_dir() {
                // The in-place stashes mc-create-vm --recreate leaves behind.
                // Nine of them accumulated during one debugging session, and a
                // disk that fills is indistinguishable from a hypervisor that
                // refuses to start a VM.
                if fs::remove_dir_all(&path).is_ok() {
                    r.purged_stash_dirs += 1;
                }
            }
        }
        // Legacy sibling directories from the old move-the-whole-dir
        // behaviour, which the file-level purge above never sees.
        if let Ok(rd) = fs::read_dir(&cfg.vm_root) {
            for e in rd.flatten() {
                let n = e.file_name().to_string_lossy().to_string();
                if n.starts_with(&format!("{name}.stashed-")) && e.path().is_dir() {
                    if fs::remove_dir_all(e.path()).is_ok() {
                        r.purged_stash_dirs += 1;
                    }
                }
            }
        }
        log(&format!(
            "purged {} stashed file(s) and {} stash director(ies) to reclaim space",
            r.purged_files, r.purged_stash_dirs
        ));
    }
    Ok(r)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_wsl_iso_is_refused_with_the_reason() {
        // The file must exist for the path check to be the thing that fails,
        // so use one that always does.
        let e = iso_for_vmx(Path::new("/etc/hostname")).unwrap_err();
        assert!(e.contains("Windows-visible"), "{e}");
        assert!(iso_for_vmx(Path::new("/no/such/photon.iso"))
            .unwrap_err()
            .contains("existing file"));
    }

    #[test]
    fn detaching_the_cdrom_rewrites_only_that_line() {
        let dir = std::env::temp_dir().join(format!("sharukhan-test-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let vmx = dir.join("t.vmx");
        fs::write(
            &vmx,
            "sata0:1.startConnected = \"TRUE\"\nethernet0.startConnected = \"TRUE\"\n",
        )
        .unwrap();
        detach_cdrom(&vmx).unwrap();
        let out = fs::read_to_string(&vmx).unwrap();
        assert!(out.contains("sata0:1.startConnected = \"FALSE\""));
        assert!(out.contains("ethernet0.startConnected = \"TRUE\""));
        fs::remove_dir_all(&dir).ok();
    }
}
