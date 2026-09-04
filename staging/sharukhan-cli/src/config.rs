//! Paths, sizes, network and identity - the typed form of what used to be
//! config/mission-control.env.
//!
//! Every setting still reads an environment variable of the SAME NAME the bash
//! used, because the bash file's one rule was that a per-run override must
//! win: vm-lab/config/vm-lab.env assigns unconditionally and silently
//! overwrites an exported variable, so its documented overrides do not work.
//! `: "${VAR:=default}"` became `env::var(VAR).unwrap_or(default)`; nothing
//! else about the contract changed.
//!
//! One setting deliberately has NO default: see [`Config::guest_password`].

use std::env;
use std::path::PathBuf;

pub struct Config {
    // ---- host tooling ----------------------------------------------------
    pub vmrun: PathBuf,
    pub vdiskmanager: PathBuf,

    // ---- where VMs and artefacts live ------------------------------------
    /// MUST be on a Windows-visible volume. VMware cannot see a WSL path at
    /// all: an ISO at /root/... becomes the nonsense VMX value "\root\..." and
    /// vmrun fails with only "Error: The operation was canceled".
    pub vm_root: PathBuf,
    /// The host DHCP server's lease file. Read-only, and the only signal that
    /// sees an install finish as it happens - see `leases`.
    pub dhcp_leases: PathBuf,
    pub iso_cache: PathBuf,
    pub results_dir: PathBuf,
    pub build_log_dir: PathBuf,
    pub work: PathBuf,
    pub variant_patches: PathBuf,
    pub run_log_dir: PathBuf,
    pub memory_db: PathBuf,
    pub matrix_tsv: PathBuf,

    // ---- photon build tree -----------------------------------------------
    pub photon_tree: PathBuf,
    /// The photon-os-installer checkout. Several SPECS/photon-os-installer
    /// patches are copies of commits on that repository's PR branches, and a
    /// copy is a thing that can go stale.
    pub poi_tree: PathBuf,
    /// runPh5_normal.sh resolves downstream-fixes.patch RELATIVE TO ITSELF
    /// ($SCRIPT_DIR/photonos-patches/...). Two copies of both the script and
    /// the patch exist on this host and they had diverged: the scripts-repo
    /// copy carried a stale 8-file patch, /root the live 27-file one. Pointing
    /// at the wrong pair fails the build guard with "does not apply", which
    /// reads like a rebase problem rather than a path problem. `doctor`
    /// asserts the two agree.
    pub photon_scripts: PathBuf,
    /// runPh5_normal.sh's positional contract: `<scripts root> <common dir>
    /// <release> <dest> <img> <canister>`. The bash passed the first three as
    /// literals; they are settings here so the harness is not pinned to one
    /// machine, but the defaults are exactly what it passed.
    pub build_root: PathBuf,
    pub build_common: String,
    pub release: String,
    pub photon_remote: String,

    // ---- guest defaults --------------------------------------------------
    pub guest_vcpus: u32,
    pub guest_mem_mb: u32,
    pub boot_disk_size: String,
    pub boot_disk_adapter: String,
    /// -t 0 = monolithicSparse: one file, thin. The hand-made test VM on this
    /// host is monolithicFlat and commits its full size up front; 34 of those
    /// would not fit in the free space on C:.
    pub boot_disk_type: String,

    // ---- network ---------------------------------------------------------
    /// VMnet8 (NAT) is 192.168.225.0/24 with DHCP .128-.254. Each permutation
    /// gets a static address BELOW the DHCP floor so it can never collide with
    /// a lease. Verified against the host: vmnetdhcp.conf declares
    /// `range 192.168.225.128 192.168.225.254`.
    pub net_prefix: String,
    /// The NAT device is both router and DNS forwarder, at .2 - NOT .1, which
    /// an earlier comment here claimed. vmnetnat.conf has
    /// `ip = 192.168.225.2/24` and vmnetdhcp.conf hands out
    /// `option routers 192.168.225.2` and the same for domain-name-servers.
    /// Now actually consumed: the static kickstart branch used to emit an
    /// empty gateway and nameserver, which yields a guest with no route.
    pub net_gateway: String,
    pub net_dns: String,
    /// The IPv4 prefix length of the NAT segment. No longer dead: the network
    /// axis turns it into the dotted netmask the legacy kickstart schema wants,
    /// and into the /NN suffix the v2 schema wants.
    pub net_cidr: u32,
    /// The IPv6 ULA prefix guests are addressed from. A ULA on purpose - this
    /// host has no IPv6 router and no DHCPv6 server in any configuration, so a
    /// global prefix would be claiming reachability that does not exist. It is
    /// configured, not routed: the address is assigned, DAD completes, and
    /// nothing off-segment can be reached with it. That is the whole of the
    /// IPv6 coverage this host can support.
    pub net_v6_prefix: String,
    /// The segment a tagged sub-interface is addressed from. Deliberately NOT
    /// the management segment: nothing on vmnet8 answers a tagged frame, so an
    /// address here can never be confused with one that works.
    pub net_vlan_prefix: String,
    pub ip_base: usize,
    /// e1000, not vmxnet3. VMware refuses to power this VM on with vmxnet3:
    ///   Vmxnet3 PCI: failed to reserve slot for vmxnet3 PCIe device
    ///   Module 'DevicePowerOn' power on failed.
    /// and vmrun reports only "Error: The operation was canceled".
    pub nic_dev: String,

    // ---- ssh -------------------------------------------------------------
    pub ssh_key_dir: PathBuf,
    /// RSA, not ed25519, and that is not a preference.
    ///
    /// A FIPS row boots with fips=1, and the installer then restricts sshd to
    /// FIPS-approved algorithms (fix/poi-fips-sshd-algorithms), whose
    /// PubkeyAcceptedAlgorithms is rsa-sha2-512, rsa-sha2-256, ecdsa-*. Ed25519
    /// is not on that list and never can be. With an ed25519 key the guest
    /// correctly refuses the harness:
    ///
    ///   Permission denied (publickey,password,keyboard-interactive).
    ///
    /// which reads exactly like a broken installer and is not one - s02 was
    /// recorded as "guest unreachable under FIPS" on that evidence. RSA is
    /// accepted by both a FIPS and a stock sshd, so one key serves every row
    /// and there is no reason to keep two.
    pub ssh_key_name: String,
    /// Stock Photon has no 'operator' user; vm-lab's default is
    /// SPAGAT-specific.
    pub ssh_user: String,
    guest_password: Option<String>,

    // ---- timing ----------------------------------------------------------
    pub serial_log_prefix: String,
    pub install_timeout_sec: u64,
    /// Three more settings the bash defined and never read. The install phase
    /// uses MC_INSTALL_TIMEOUT_SEC only; ssh's own ConnectTimeout is 10s,
    /// which is a connect timeout and not this phase budget.
    #[allow(dead_code)]
    pub boot_timeout_sec: u64,
    #[allow(dead_code)]
    pub ssh_timeout_sec: u64,
    #[allow(dead_code)]
    pub sample_sec: u64,
    /// How long to wait for a started VM to appear in the inventory before
    /// calling the start a failure. The inventory is the authority; vmrun's
    /// exit code is not evidence in either direction.
    pub start_timeout_sec: u64,
}

fn var_or(key: &str, default: &str) -> PathBuf {
    PathBuf::from(env::var(key).unwrap_or_else(|_| default.to_string()))
}

fn s_or(key: &str, default: &str) -> String {
    env::var(key).unwrap_or_else(|_| default.to_string())
}

/// A malformed number is reported, not silently replaced by the default: a
/// typo in MC_INSTALL_TIMEOUT_SEC that quietly restores 2400 would be found
/// only by watching the clock.
fn n_or<T: std::str::FromStr + Copy>(key: &str, default: T) -> T {
    match env::var(key) {
        Ok(v) => v.trim().parse().unwrap_or_else(|_| {
            eprintln!("sharukhan: {key}='{v}' is not a number; using the default");
            default
        }),
        Err(_) => default,
    }
}

impl Config {
    /// A Config whose only meaningful field is the photon tree.
    ///
    /// `load()` reads the real environment and would make a unit test depend on
    /// this host; everything under test here reads `photon_tree` and nothing
    /// else, so the rest is left at its default.
    #[cfg(test)]
    pub fn for_test(tree: &std::path::Path) -> Self {
        let mut c = Config::load();
        c.photon_tree = tree.to_path_buf();
        c
    }

    pub fn load() -> Self {
        let here = env::var("SHARUKHAN_ROOT")
            .unwrap_or_else(|_| "/root/photonos-scripts/staging/mission-control".to_string());
        let net_prefix = s_or("MC_NET_PREFIX", "192.168.225");
        Config {
            vmrun: var_or(
                "VMRUN",
                "/mnt/c/Program Files/VMware/VMware Workstation/vmrun.exe",
            ),
            vdiskmanager: var_or(
                "VDISKMANAGER",
                "/mnt/c/Program Files/VMware/VMware Workstation/vmware-vdiskmanager.exe",
            ),

            vm_root: var_or("MC_VM_ROOT_WSL", "/mnt/c/photon-mc/vm"),
            dhcp_leases: var_or(
                "MC_DHCP_LEASES",
                "/mnt/c/ProgramData/VMware/vmnetdhcp.leases",
            ),
            iso_cache: var_or("MC_ISO_CACHE", "/mnt/c/photon-mc/iso-cache"),
            results_dir: var_or("MC_RESULTS_DIR", "/root/photon-mc/results"),
            build_log_dir: var_or("MC_BUILD_LOG_DIR", "/root/photon-mc/build-logs"),
            work: var_or("MC_WORK", "/root/photon-mc/work"),
            variant_patches: var_or("MC_VARIANT_PATCH_DIR", "/root/photon-mc/variant-patches"),
            run_log_dir: var_or("MC_RUN_LOG_DIR", "/root/photon-mc/run-logs"),
            memory_db: var_or("SHARUKHAN_DB", "/root/photon-mc/memory.db"),
            matrix_tsv: var_or(
                "SHARUKHAN_MATRIX",
                &format!("{here}/config/permutations.tsv"),
            ),

            photon_tree: var_or("PHOTON_TREE", "/root/5.0"),
            poi_tree: var_or("POI_TREE", "/root/photon-os-installer"),
            photon_scripts: var_or("PHOTON_SCRIPTS", "/root"),

            build_root: var_or("MC_BUILD_ROOT", "/root"),
            build_common: s_or("MC_BUILD_COMMON", "common"),
            release: s_or("MC_RELEASE", "5.0"),
            photon_remote: s_or("MC_PHOTON_REMOTE", "https://github.com/dcasota/photon.git"),

            guest_vcpus: n_or("GUEST_VCPUS", 2),
            guest_mem_mb: n_or("GUEST_MEM_MB", 4096),
            boot_disk_size: s_or("BOOT_DISK_SIZE", "32GB"),
            boot_disk_adapter: s_or("BOOT_DISK_ADAPTER", "lsilogic"),
            boot_disk_type: s_or("BOOT_DISK_TYPE", "0"),

            net_gateway: s_or("MC_NET_GATEWAY", &format!("{net_prefix}.2")),
            net_dns: s_or("MC_NET_DNS", &format!("{net_prefix}.2")),
            net_cidr: n_or("MC_NET_CIDR", 24),
            net_v6_prefix: s_or("MC_NET_V6_PREFIX", "fd00:225"),
            net_vlan_prefix: s_or("MC_NET_VLAN_PREFIX", "192.168.100"),
            ip_base: n_or("MC_IP_BASE", 40),
            nic_dev: s_or("MC_NIC_DEV", "e1000"),
            net_prefix,

            ssh_key_dir: var_or(
                "SSH_KEY_DIR",
                &format!("{}/.ssh", env::var("HOME").unwrap_or_else(|_| "/root".into())),
            ),
            ssh_key_name: s_or("SSH_KEY_NAME", "photon-mc-rsa"),
            ssh_user: s_or("SSH_USER", "root"),
            guest_password: env::var("MC_GUEST_PASSWORD").ok().filter(|v| !v.is_empty()),

            serial_log_prefix: s_or("SERIAL_LOG_PREFIX", "serial0"),
            install_timeout_sec: n_or("MC_INSTALL_TIMEOUT_SEC", 2400),
            boot_timeout_sec: n_or("MC_BOOT_TIMEOUT_SEC", 600),
            ssh_timeout_sec: n_or("MC_SSH_TIMEOUT_SEC", 300),
            sample_sec: n_or("MC_SAMPLE_SEC", 25),
            start_timeout_sec: n_or("MC_START_TIMEOUT", 240),
        }
    }

    /// The root password baked into a generated kickstart, and the one an
    /// operator types at the curses configurator.
    ///
    /// REQUIRED, with no default. The bash defaulted it to a literal in a
    /// checked-in file, which is the single reason this harness could not be
    /// published: a throwaway lab password in version control is still a
    /// credential in version control. Nothing here guesses one - a run without
    /// MC_GUEST_PASSWORD stops before it creates a VM whose password nobody
    /// recorded.
    pub fn guest_password(&self) -> Result<&str, String> {
        self.guest_password.as_deref().ok_or_else(|| {
            "MC_GUEST_PASSWORD is not set. It is the root password of every VM this harness \
             installs, so it has no default and is never written down here. Export it for the \
             run, e.g. `read -rs MC_GUEST_PASSWORD; export MC_GUEST_PASSWORD`."
                .to_string()
        })
    }

    /// Path of the lab keypair. Key-only auth is the whole story: the
    /// kickstart injects `public_key`, so no password ever reaches a command
    /// line (which is why sshpass is gone).
    pub fn ssh_key(&self) -> PathBuf {
        self.ssh_key_dir.join(&self.ssh_key_name)
    }
    pub fn ssh_pubkey(&self) -> PathBuf {
        self.ssh_key_dir.join(format!("{}.pub", self.ssh_key_name))
    }

    /// Where one permutation's VM lives. The VM name is the permutation id
    /// prefixed, so a guest self-identifies in every log line it emits.
    pub fn vm_name(&self, id: &str) -> String {
        format!("mc-{id}")
    }
    pub fn vm_dir(&self, id: &str) -> PathBuf {
        self.vm_root.join(self.vm_name(id))
    }
    pub fn vmx_path(&self, id: &str) -> PathBuf {
        let vm = self.vm_name(id);
        self.vm_dir(id).join(format!("{vm}.vmx"))
    }
    pub fn serial_log(&self, id: &str) -> PathBuf {
        let vm = self.vm_name(id);
        self.vm_dir(id).join(format!("{}-{vm}.log", self.serial_log_prefix))
    }
    /// The ISO cache key is the set of BUILD-time axes and nothing else: iso
    /// type, installer version, canister. Rows that need a locally built
    /// canister must not silently reuse the prebuilt ISO - that is how an axis
    /// ends up never exercised.
    pub fn iso_dir(&self, iso_type: &str, poi: &str, canister: &str) -> PathBuf {
        self.iso_cache.join(format!("{iso_type}-poi{poi}-{canister}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paths_are_derived_consistently() {
        let c = Config::load();
        let dir = c.vm_dir("k01");
        assert_eq!(c.vmx_path("k01"), dir.join("mc-k01.vmx"));
        assert!(c
            .serial_log("k01")
            .to_string_lossy()
            .ends_with("-mc-k01.log"));
        assert!(c
            .iso_dir("minimal", "2.8", "prebuilt")
            .to_string_lossy()
            .ends_with("minimal-poi2.8-prebuilt"));
    }

    /// The default ssh key must be usable on a FIPS row.
    ///
    /// s02 spent three runs recorded as "guest unreachable under FIPS" because
    /// the harness offered an ed25519 key to an sshd whose
    /// PubkeyAcceptedAlgorithms is rsa-sha2-*/ecdsa-* . The guest was right to
    /// refuse it, and the harness reported it as an installer defect. Ed25519
    /// is not FIPS-approved and cannot be made so, hence this guard.
    #[test]
    fn the_default_ssh_key_is_fips_usable() {
        let c = Config::load();
        let name = c.ssh_key_name.to_ascii_lowercase();
        assert!(
            !name.contains("ed25519"),
            "an ed25519 key cannot authenticate to a FIPS guest: {name}"
        );
        assert!(
            name.contains("rsa") || name.contains("ecdsa"),
            "the default key must be an algorithm a FIPS sshd accepts: {name}"
        );
    }

    /// The password has no default. This test is the guard against someone
    /// restoring one "just for convenience".
    #[test]
    fn guest_password_has_no_default() {
        let mut c = Config::load();
        c.guest_password = None;
        let e = c.guest_password().unwrap_err();
        assert!(e.contains("MC_GUEST_PASSWORD"));
        c.guest_password = Some("x".into());
        assert_eq!(c.guest_password().unwrap(), "x");
    }
}
