//! Running the oracle against one installed permutation and harvesting its
//! logs. Ported from mc-verify.sh.
//!
//! This phase CONSUMES what the install phase proved (mc-facts.env) and does
//! not re-derive it. Re-deriving is what produced a false k01 FAIL(2): the
//! installed system is serial-silent unless the kickstart's grub edit takes,
//! and re-querying the guest IP races first boot.

use crate::config::Config;
use crate::evidence::{Checks, Status};
use crate::guest::Guest;
use crate::matrix::Permutation;
use crate::{install, oracle, vmware, winpath};
use std::fs;
use std::path::PathBuf;

pub struct Verified {
    pub checks: Checks,
    pub harvest: PathBuf,
}

pub fn run(
    cfg: &Config,
    p: &Permutation,
    ip_override: Option<&str>,
    stamp: &str,
    log: &mut dyn FnMut(&str),
) -> Result<Verified, String> {
    let dir = cfg.vm_dir(&p.id);
    let serial = cfg.serial_log(&p.id);

    let mut c = Checks::init(&cfg.results_dir, &p.id, stamp)?;
    // Reports are versioned too: harvested logs live beside the checks file
    // that names them, and logs-latest is a pointer, never storage.
    let harvest = cfg.results_dir.join(&p.id).join(format!("logs-{stamp}"));
    fs::create_dir_all(&harvest).map_err(|e| format!("{}: {e}", harvest.display()))?;
    let link = cfg.results_dir.join(&p.id).join("logs-latest");
    let _ = fs::remove_file(&link);
    let _ = std::os::unix::fs::symlink(format!("logs-{stamp}"), &link);

    log(&format!(
        "== {}  iso={} poi={} stig={} fs={} mode={} ==",
        p.id, p.iso_type, p.poi, p.stig, p.fs, p.mode
    ));
    c.check(
        "meta.doc_verdict",
        "-",
        Status::Info,
        "",
        &p.doc,
        "what ISO-PERMUTATION-MATRIX.md records",
    );
    c.check(
        "meta.expected",
        "-",
        Status::Info,
        "",
        &p.expect,
        "expected with all PRs applied",
    );
    // Provenance for every FIPS verdict in this file. A canister built locally
    // is functionally equivalent and carries NO CMVP certificate, so a result
    // taken against one must never be read as a compliance claim. Recording it
    // here means the evidence carries the caveat, not just the report that
    // cites it.
    let origin = crate::canister::detect(cfg, std::env::consts::ARCH)
        .map(|st| {
            let label = st.label();
            if st.is_validated() {
                label.to_string()
            } else {
                format!("{label} (NOT CMVP validated)")
            }
        })
        .unwrap_or_else(|e| format!("unknown ({e})"));
    c.check(
        "meta.canister_origin",
        "PR#24",
        Status::Info,
        "",
        &origin,
        "which canister this kernel carries; only 'certified' may be reported as compliant",
    );

    // --- media -----------------------------------------------------------
    // Do not hardcode the canister mode: an ISO built with --canister
    // build|acvp|kat lives under a different cache key, and silently reading
    // the prebuilt one would verify an artefact the permutation never used.
    let iso = cfg.iso_dir(&p.iso_type, &p.poi, &p.canister).join("photon.iso");
    if iso.is_file() {
        if p.iso_type == "minimal" {
            oracle::media(&iso, &p.iso_type, &mut c);
        }
    } else {
        c.check(
            "media.iso",
            "-",
            Status::Skip,
            "",
            "",
            &format!("no cached ISO at {}", iso.display()),
        );
    }

    // --- what the install phase established -------------------------------
    let facts = install::read_facts(&dir);
    let install_result = facts.as_ref().map(|f| f.install_result.clone());
    let mut ip = ip_override.map(str::to_string).unwrap_or_default();
    if ip.is_empty() {
        if let Some(f) = &facts {
            if !f.guest_ip.is_empty() {
                ip = f.guest_ip.clone();
            }
        }
    }

    // --- install phase ----------------------------------------------------
    let _ = fs::copy(&serial, harvest.join("serial.log"));
    oracle::install(&serial, install_result.as_deref(), &mut c);

    // --- guest ------------------------------------------------------------
    // Discover the address rather than assuming it: an interactive install may
    // have taken a DHCP lease the kickstart never pinned. vmrun.exe is a
    // Windows binary, so it is asked with the WINDOWS path - handed a
    // /mnt/c/... argument it names a file it cannot open and answers nothing,
    // which is indistinguishable from a guest that has not booted.
    if ip.is_empty() {
        if let Ok(vmx_win) = winpath::win_path_checked(&cfg.vmx_path(&p.id).to_string_lossy()) {
            if let Some(found) = vmware::guest_ip(&cfg.vmrun, &vmx_win, true) {
                ip = found;
            }
        }
    }

    if ip.is_empty() {
        c.check(
            "guest.ip",
            "-",
            Status::Fail,
            "discovered",
            "none",
            "vmrun getGuestIPAddress returned nothing and the install recorded no address",
        );
        log(&c.summary());
        return Ok(Verified { checks: c, harvest });
    }

    c.check("guest.ip", "-", Status::Info, "", &ip, "");
    let g = Guest::new(&cfg.ssh_user, &ip, &cfg.ssh_key(), 10);
    let probe = g.reachable();
    if probe.ok {
        oracle::guest(&g, &p.stig, &p.fs, &mut c);
        oracle::harvest(&g, &harvest, cfg.guest_password().ok(), &mut c);
    } else {
        // ssh's own words are the finding, not a footnote to it: s02 is
        // unreachable because FIPS-constrained crypto refuses the algorithms
        // sshd advertised, and the ONLY thing that says so is this text.
        let why = probe.stderr.trim();
        let _ = fs::write(harvest.join("ssh-error.txt"), &probe.stderr);
        c.check(
            "guest.ssh",
            "-",
            Status::Fail,
            "reachable",
            "unreachable",
            &format!("no ssh to {ip} as {}: {why}", cfg.ssh_user),
        );
    }

    log(&c.summary());
    Ok(Verified { checks: c, harvest })
}
