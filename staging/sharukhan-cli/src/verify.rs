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
    //
    // The kernel NEVR is read from this row's VARIANT PATCH, not from the
    // pristine spec: the patch is what sets Release, and `resolve` resets SPECS
    // to pristine between builds, so a detection taken from the tree answers
    // for a kernel nobody built. That is the same mistake `detect_for` exists
    // to prevent, and it reached here too.
    //
    // An `equivalent` row must ask for the nevr the EMBEDDED patch produces.
    // That patch is applied on top of the variant patch and bumps Release
    // again (linux 3 -> 4), so `kernel_nevr` - which deliberately does not
    // read it - answers for a kernel this row never booted. The build path
    // already uses `equivalent_kernel_nevr` for exactly this reason, and its
    // own doc comment predicts the consequence of getting it wrong here:
    // "the guest-side assertion would then correctly fail". It did: c03 read
    // expected=6.12.107-3.ph5 against an actual of 6.12.107-4.ph5, marking a
    // correctly linked canister as a failure.
    let patch = cfg.variant_patches.join(format!("poi-{}.patch", p.poi));
    let kernel = if p.canister == "equivalent" {
        crate::build::equivalent_kernel_nevr(cfg, &patch)
    } else {
        crate::build::kernel_nevr(cfg, &patch)
    };
    let origin = crate::canister::detect_for(
        cfg,
        std::env::consts::ARCH,
        kernel.as_deref().ok(),
    )
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
        &format!(
            "which canister this kernel carries with canister={}; only 'certified' \
             may be reported as compliant",
            p.canister
        ),
    );
    // What guest.canister_based_on must read. Decided from the row's axis, not
    // from what the guest happens to say: an equivalent build that fell back to
    // the certified canister has to FAIL, and it can only do that against an
    // expectation formed before the answer is seen.
    let want = oracle::canister_expectation(&p.canister, kernel);

    // --- media -----------------------------------------------------------
    // Do not hardcode the canister mode: an ISO built with --canister
    // build|acvp|kat lives under a different cache key, and silently reading
    // the prebuilt one would verify an artefact the permutation never used.
    let iso = cfg.iso_dir(&p.iso_type, &p.poi, &p.canister).join("photon.iso");
    if iso.is_file() {
        // Both ISO types. This was `if p.iso_type == "minimal"`, inherited from
        // the bash with no reason recorded, and it dropped four checks from
        // every full row SILENTLY - the count fell from 37 to 33 with not even
        // a Skip to say why. Among them media.poi_rpm, which is what caught a
        // 2.9-4 installer shipping on an ISO built for the 2.8 variant, and
        // media.negative_control, which exists so a broken extraction cannot
        // make every presence check vacuously pass. The full media carries
        // 1927 RPMs against the minimal's 290: it is the likelier place for a
        // stale one to hide, not the safer one.
        //
        // Only the STIG set was ever minimal-specific - its list is documented
        // as what the matrix records ABSENT from minimal media - and it is
        // satisfied on the full media too, verified against the built ISO.
        oracle::media(&iso, &p.iso_type, &mut c);
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
        oracle::guest(&g, &p.stig, &p.fs, &want, &p.net, &mut c);
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
