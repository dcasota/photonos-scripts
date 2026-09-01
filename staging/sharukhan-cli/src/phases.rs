//! The per-phase entry points: what used to be one bash script each.
//!
//! Each of these is callable on its own - an operator driving a mode=ui row
//! needs `install --mode interactive`, then `card`, then `verify`, hours
//! apart - and `run` calls the same functions in sequence for the autonomous
//! rows. There is one implementation, not two.

use crate::config::Config;
use crate::matrix::Permutation;
use crate::{build, card, install, kickstart, matrix, verify, vm};
use std::fs;
use std::path::PathBuf;

pub fn row(cfg: &Config, id: &str) -> Result<Permutation, String> {
    let all = matrix::load(&cfg.matrix_tsv)?;
    all.into_iter()
        .find(|p| p.id == id)
        .ok_or_else(|| format!("permutation '{id}' is not in {}", cfg.matrix_tsv.display()))
}

pub fn logger() -> impl FnMut(&str) {
    |m: &str| println!("[mc] {m}")
}

/// The kickstart for one row.
///
/// The public key is what makes password-free ssh work, and is why sshpass is
/// gone: the password is configured once, inside the kickstart, and never
/// appears on a command line where /proc would expose it to every process on
/// the host.
pub fn kickstart_json(cfg: &Config, p: &Permutation) -> Result<String, String> {
    build_kickstart(cfg, p, Secrets::Real)
}

/// What the evidence copy of a kickstart is allowed to contain.
///
/// The kickstart carries the guest root password in cleartext, and the copy
/// written beside the run's results is the file a report cites. Scrubbing the
/// tree afterwards does not hold: the next run writes the secret straight back.
/// So the redaction happens at the point of writing, and only for the copy the
/// guest never sees.
#[derive(Clone, Copy, PartialEq)]
pub enum Secrets {
    Real,
    Redacted,
}

pub const REDACTED: &str = "***REDACTED***";

fn build_kickstart(cfg: &Config, p: &Permutation, secrets: Secrets) -> Result<String, String> {
    let real = cfg.guest_password()?;
    let password = match secrets {
        Secrets::Real => real,
        Secrets::Redacted => REDACTED,
    };
    let pubkey = fs::read_to_string(cfg.ssh_pubkey())
        .ok()
        .map(|k| k.trim().to_string())
        .filter(|k| !k.is_empty());
    if pubkey.is_none() {
        eprintln!(
            "sharukhan: no public key at {} - the guest will accept no key and verification \
             will fail at guest.ssh. Create one with `ssh-keygen -t ed25519 -f {}`.",
            cfg.ssh_pubkey().display(),
            cfg.ssh_key().display()
        );
    }
    // The matrix never pins an address in the kickstart: rows take a DHCP
    // lease and the reserved .4x address is used for identity (MAC/UUID)
    // only. See the report note - this is bash behaviour, preserved.
    kickstart::render(&kickstart::Spec {
        id: &p.id,
        fs: &p.fs,
        stig: &p.stig,
        variant: &p.variant,
        password,
        public_key: pubkey,
        ip: None,
        gateway: &cfg.net_gateway,
        nameserver: &cfg.net_dns,
    })
}

/// Write the kickstart where the evidence for this row lives, so what was
/// installed can be read back beside what it produced.
pub fn write_kickstart(cfg: &Config, p: &Permutation) -> Result<PathBuf, String> {
    // Evidence copy: same structure, no secret. What the guest is actually
    // given is built separately at the point of injection.
    let json = build_kickstart(cfg, p, Secrets::Redacted)?;
    let dir = cfg.results_dir.join(&p.id);
    fs::create_dir_all(&dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    let path = dir.join("kickstart.json");
    fs::write(&path, format!("{json}\n")).map_err(|e| format!("{}: {e}", path.display()))?;
    Ok(path)
}

pub fn cmd_kickstart(cfg: &Config, id: &str) -> Result<(), String> {
    let p = row(cfg, id)?;
    println!("{}", kickstart_json(cfg, &p)?);
    Ok(())
}

pub fn cmd_create_vm(
    cfg: &Config,
    id: &str,
    iso: Option<&str>,
    ks_file: Option<&str>,
    recreate: bool,
    allow_build: bool,
) -> Result<(), String> {
    let p = row(cfg, id)?;
    let iso_path = match iso {
        Some(i) => PathBuf::from(i),
        None => build::resolve(
            cfg,
            &build::IsoRequest {
                iso_type: p.iso_type.clone(),
                poi: p.poi.clone(),
                canister: p.canister.clone(),
            },
            false,
            allow_build,
            &mut logger(),
        )?,
    };
    let ks = match (ks_file, p.mode.as_str()) {
        (Some(f), _) => Some(fs::read_to_string(f).map_err(|e| format!("{f}: {e}"))?),
        (None, "ks") => Some(kickstart_json(cfg, &p)?),
        // mode=ui: no kickstart at all. That absence is what selects the
        // curses configurator, which is the only place the STIG menu exists.
        (None, _) => None,
    };
    let v = vm::create(cfg, &p, &iso_path, ks, recreate, &mut logger())?;
    println!("{}", v.vmx.display());
    Ok(())
}

pub fn cmd_install(
    cfg: &Config,
    id: &str,
    mode: Option<&str>,
    timeout: Option<u64>,
    no_wait: bool,
) -> Result<(), String> {
    let p = row(cfg, id)?;
    let v = vm::plan(cfg, id)?;
    let mode = match mode.unwrap_or(if p.mode == "ui" { "interactive" } else { "auto" }) {
        "auto" => install::Mode::Auto,
        "interactive" => install::Mode::Interactive,
        other => return Err(format!("unknown --mode '{other}' (auto or interactive)")),
    };
    if mode == install::Mode::Interactive {
        println!("{}", card_text(cfg, &p, &v)?);
    }
    let facts = install::run(
        cfg,
        &v,
        &install::Opts {
            mode,
            timeout_sec: timeout.unwrap_or(cfg.install_timeout_sec),
            no_wait,
        },
        &mut logger(),
    )?;
    println!("{}", facts.install_result);
    if facts.install_result == install::INSTALLED || facts.install_result == "waiting" {
        Ok(())
    } else {
        Err(format!("{id}: install result {}", facts.install_result))
    }
}

pub fn cmd_verify(cfg: &Config, id: &str, ip: Option<&str>) -> Result<(), String> {
    let p = row(cfg, id)?;
    let v = verify::run(cfg, &p, ip, &crate::job::stamp(), &mut logger())?;
    println!("evidence: {}", v.checks.path.display());
    println!("logs:     {}", v.harvest.display());
    if v.checks.fail == 0 {
        Ok(())
    } else {
        Err(format!("{id}: {} failing check(s)", v.checks.fail))
    }
}

pub fn cmd_teardown(cfg: &Config, id: &str, purge: bool) -> Result<(), String> {
    // Accept an id that is not in the matrix: a VM directory can outlive the
    // row that made it, and refusing to clean one up would be unhelpful.
    let _ = row(cfg, id);
    vm::teardown(cfg, id, purge, &mut logger())?;
    Ok(())
}

pub fn cmd_card(cfg: &Config, id: &str) -> Result<(), String> {
    let p = row(cfg, id)?;
    let v = vm::plan(cfg, id)?;
    println!("{}", card_text(cfg, &p, &v)?);
    Ok(())
}

fn card_text(cfg: &Config, p: &Permutation, v: &vm::Vm) -> Result<String, String> {
    Ok(card::render(
        p,
        &v.name,
        v.index,
        &v.reserved_ip,
        cfg.guest_password()?,
    ))
}

pub fn cmd_build_iso(
    cfg: &Config,
    iso_type: &str,
    poi: &str,
    canister: &str,
    force: bool,
    allow_build: bool,
) -> Result<(), String> {
    let iso = build::resolve(
        cfg,
        &build::IsoRequest {
            iso_type: iso_type.to_string(),
            poi: poi.to_string(),
            canister: canister.to_string(),
        },
        force,
        allow_build,
        &mut logger(),
    )?;
    println!("{}", iso.display());
    Ok(())
}

pub fn cmd_variant_patches(cfg: &Config) -> Result<(), String> {
    build::make_variant_patches(cfg, &mut logger())
}

/// Create the lab keypair if it is missing. `ssh-keygen` is part of the same
/// OpenSSH the harness deliberately keeps exec'ing.
pub fn ensure_ssh_key(cfg: &Config, log: &mut dyn FnMut(&str)) -> Result<(), String> {
    let key = cfg.ssh_key();
    if key.exists() {
        return Ok(());
    }
    fs::create_dir_all(&cfg.ssh_key_dir).map_err(|e| format!("{}: {e}", cfg.ssh_key_dir.display()))?;
    let host = std::process::Command::new("hostname")
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default();
    let ok = std::process::Command::new("ssh-keygen")
        .args(["-t", "ed25519", "-N", "", "-C", &format!("photon-mc@{host}"), "-f"])
        .arg(&key)
        .output()
        .map_err(|e| format!("running ssh-keygen: {e}"))?;
    if !ok.status.success() {
        return Err(format!(
            "ssh-keygen failed: {}",
            String::from_utf8_lossy(&ok.stderr).trim()
        ));
    }
    log(&format!("created lab keypair {}", key.display()));
    Ok(())
}
