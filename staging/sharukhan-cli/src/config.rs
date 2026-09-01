//! Paths and settings.
//!
//! These default to the same locations the bash harness uses, and every one can
//! be overridden by an environment variable of the same name. Nothing is
//! hard-coded to a single machine.

use std::env;
use std::path::PathBuf;

pub struct Config {
    pub photon_tree: PathBuf,
    pub matrix_tsv: PathBuf,
    pub results_dir: PathBuf,
    pub memory_db: PathBuf,
    pub iso_cache: PathBuf,
    pub variant_patches: PathBuf,
    pub vm_root: PathBuf,
    pub vmrun: PathBuf,
    /// Where the mission-control scripts live. `run` shells out to them; it
    /// builds and installs nothing itself.
    pub mc_bin: PathBuf,
    /// Where `run` writes its own log. Separate from MC_RESULTS_DIR, which is
    /// per-permutation evidence written by mc-verify.sh.
    pub run_log_dir: PathBuf,
}

fn var_or(key: &str, default: &str) -> PathBuf {
    PathBuf::from(env::var(key).unwrap_or_else(|_| default.to_string()))
}

impl Config {
    pub fn load() -> Self {
        let here = env::var("SHARUKHAN_ROOT")
            .unwrap_or_else(|_| "/root/photonos-scripts/staging/mission-control".to_string());
        Config {
            photon_tree: var_or("PHOTON_TREE", "/root/5.0"),
            matrix_tsv: var_or(
                "SHARUKHAN_MATRIX",
                &format!("{here}/config/permutations.tsv"),
            ),
            results_dir: var_or("MC_RESULTS_DIR", "/root/photon-mc/results"),
            memory_db: var_or("SHARUKHAN_DB", "/root/photon-mc/memory.db"),
            iso_cache: var_or("MC_ISO_CACHE", "/mnt/c/photon-mc/iso-cache"),
            variant_patches: var_or("MC_VARIANT_PATCH_DIR", "/root/photon-mc/variant-patches"),
            vm_root: var_or("MC_VM_ROOT_WSL", "/mnt/c/photon-mc/vm"),
            vmrun: var_or(
                "VMRUN",
                "/mnt/c/Program Files/VMware/VMware Workstation/vmrun.exe",
            ),
            mc_bin: var_or("MC_BIN", &format!("{here}/bin")),
            run_log_dir: var_or("MC_RUN_LOG_DIR", "/root/photon-mc/run-logs"),
        }
    }
}
