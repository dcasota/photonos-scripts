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

/// The kernel profile a test run is about.
#[derive(Clone, Debug, PartialEq)]
pub struct KernelAxis {
    pub name: String,
    /// What linux(-esx) must report: Version-Release.dist.
    pub nevr: String,
    /// The Photon release whose repo would publish a canister.
    pub userland: String,
    /// Installer Release bumps the profile's pins add on top of the variant
    /// (one per installer patch they append).
    pub installer_release_bump: u32,
}

/// `--systemd <release>`: the rows run against that systemd profile's media.
#[derive(Clone, Debug, PartialEq)]
pub struct SystemdAxis {
    /// The release, `262.2`.
    pub name: String,
    /// What the guest's systemd package must report: Version-Release.dist.
    pub nevr: String,
    /// sha256 of the profile text, recorded with every ISO built from it.
    pub profile_sha256: String,
    /// The release branch the port is checked against (5.0): the build's own
    /// `release` is the port branch.
    pub base_release: String,
}

#[derive(Clone)]
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
    pub matrix_tsv: DataFile,
    /// The installer variants and the `common` branches (crate::variants).
    pub variants_file: DataFile,
    /// Which PR each oracle check proves (evidence::load_attribution).
    pub check_prs: DataFile,

    // ---- photon build tree -----------------------------------------------
    pub photon_tree: PathBuf,
    /// The photon-os-installer checkout. Several SPECS/photon-os-installer
    /// patches are copies of commits on that repository's PR branches, and a
    /// copy is a thing that can go stale.
    pub poi_tree: PathBuf,
    /// The build root holding the common and release trees, and the common
    /// tree's directory name: settings, so the harness is not pinned to one
    /// machine.
    pub build_root: PathBuf,
    pub build_common: String,
    pub release: String,
    pub photon_remote: String,
    /// The fork whose PRs the harness tests and syncs, and the repository it
    /// syncs them against (owner/name on GitHub).
    pub fork: String,
    pub upstream: String,
    /// The gate's git repository: PR branches, sync candidates, bases.
    pub gate_repo: PathBuf,
    /// The installer repositories and their branch, watched beside the fork.
    pub fork_installer: String,
    pub upstream_installer: String,
    pub installer_branch: String,
    /// Where delivered ISOs are stored (MC_ISO_STORE); none: they stay in
    /// the cache, and `sharukhan build` needs --out.
    pub iso_store: Option<PathBuf>,
    /// The matrix rows a sync's fast loop installs (MC_FASTLOOP_ROWS): a
    /// policy choice (a STIG row on the prebuilt canister, a FIPS row on the
    /// equivalent kernel), checked against the matrix before use.
    pub fastloop_rows: Vec<String>,
    /// The matrix rows installed from the staged code before an upstream PR
    /// moves (MC_STAGED_ROWS): the staged-VM verification.
    pub staged_rows: Vec<String>,
    /// Set by `--kernel <release>` on the test commands: the kernel profile
    /// whose media the rows are run against (see kbuild::apply).
    pub kernel: Option<KernelAxis>,
    pub systemd: Option<SystemdAxis>,
    /// `--baseline`: the release as upstream has it, without any PR; the
    /// gate's stage it is seeded from.
    pub baseline: Option<std::path::PathBuf>,

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
    guest_password: Option<Result<String, String>>,

    // ---- timing ----------------------------------------------------------
    pub serial_log_prefix: String,
    pub install_timeout_sec: u64,
    /// How long to wait for a started VM to appear in the inventory before
    /// calling the start a failure. The inventory is the authority; vmrun's
    /// exit code is not evidence in either direction.
    pub start_timeout_sec: u64,
}

/// The matrix, the installer variants and the check attribution, as committed
/// in sharukhan-cli/config/ and compiled into the binary.
pub const BUILTIN_MATRIX: &str = include_str!("../config/permutations.tsv");
pub const BUILTIN_VARIANTS: &str = include_str!("../config/variants.conf");
pub const BUILTIN_CHECK_PRS: &str = include_str!("../config/check-prs.tsv");

/// A configuration file sharukhan carries built in: its setting names a file
/// on disk that replaces it (an edit under test before it is committed and
/// compiled in); unset or empty, the built-in copy is used.
#[derive(Debug, Clone)]
pub struct DataFile {
    pub setting: &'static str,
    pub name: &'static str,
    pub path: Option<PathBuf>,
    builtin: &'static str,
}

impl DataFile {
    fn from_setting(get: Get, setting: &'static str, name: &'static str, builtin: &'static str) -> DataFile {
        let path = get(setting).filter(|v| !v.trim().is_empty()).map(PathBuf::from);
        DataFile { setting, name, path, builtin }
    }

    /// The file at `path` in place of the built-in copy (tests).
    #[cfg(test)]
    pub fn file(setting: &'static str, name: &'static str, path: PathBuf) -> DataFile {
        DataFile { setting, name, path: Some(path), builtin: "" }
    }

    /// Its text: the file's when one is set, else the built-in copy.
    pub fn text(&self) -> Result<std::borrow::Cow<'static, str>, String> {
        match &self.path {
            Some(p) => std::fs::read_to_string(p)
                .map(std::borrow::Cow::Owned)
                .map_err(|e| format!("{}: {e} ({})", p.display(), self.setting)),
            None => Ok(std::borrow::Cow::Borrowed(self.builtin)),
        }
    }

    /// What it is, for messages: the file, or the built-in copy.
    pub fn label(&self) -> String {
        match &self.path {
            Some(p) => p.display().to_string(),
            None => format!("built-in config/{}", self.name),
        }
    }
}

/// Where settings come from: the process environment for `load`, nothing at
/// all for the tests' `defaults`, so a unit test never depends on this host.
type Get<'a> = &'a dyn Fn(&str) -> Option<String>;

fn var_or(get: Get, key: &str, default: &str) -> PathBuf {
    PathBuf::from(get(key).unwrap_or_else(|| default.to_string()))
}

fn s_or(get: Get, key: &str, default: &str) -> String {
    get(key).unwrap_or_else(|| default.to_string())
}

/// A malformed number is reported, not silently replaced by the default: a
/// typo in MC_INSTALL_TIMEOUT_SEC that quietly restores 2400 would be found
/// only by watching the clock.
fn n_or<T: std::str::FromStr + Copy>(get: Get, key: &str, default: T) -> T {
    match get(key) {
        Some(v) => v.trim().parse().unwrap_or_else(|_| {
            eprintln!("sharukhan: {key}='{v}' is not a number; using the default");
            default
        }),
        None => default,
    }
}

/// Settings the bash defined and nothing ever read. Accepted silently they
/// would look like knobs; they are named instead.
const NO_EFFECT: &[&str] = &["MC_BOOT_TIMEOUT_SEC", "MC_SSH_TIMEOUT_SEC", "MC_SAMPLE_SEC"];

impl Config {
    /// A Config whose only meaningful field is the photon tree.
    ///
    /// `load()` reads the real environment and would make a unit test depend on
    /// this host; everything under test here reads `photon_tree` and nothing
    /// else, so the rest is left at its default.
    #[cfg(test)]
    pub fn for_test(tree: &std::path::Path) -> Self {
        let mut c = Config::defaults();
        c.photon_tree = tree.to_path_buf();
        c
    }

    /// Every setting at its default, the environment ignored: for tests.
    #[cfg(test)]
    pub fn defaults() -> Self {
        Config::from(&|_: &str| None)
    }

    pub fn load() -> Self {
        Config::from(&|k: &str| env::var(k).ok())
    }

    fn from(get: Get) -> Self {
        for k in NO_EFFECT {
            if get(k).is_some() {
                eprintln!("sharukhan: {k} is set but has no effect (no phase reads it; installs use MC_INSTALL_TIMEOUT_SEC)");
            }
        }
        let net_prefix = s_or(get, "MC_NET_PREFIX", "192.168.225");
        Config {
            vmrun: var_or(get, "VMRUN",
                "/mnt/c/Program Files/VMware/VMware Workstation/vmrun.exe",
            ),
            vdiskmanager: var_or(get, "VDISKMANAGER",
                "/mnt/c/Program Files/VMware/VMware Workstation/vmware-vdiskmanager.exe",
            ),

            vm_root: var_or(get, "MC_VM_ROOT_WSL", "/mnt/c/photon-mc/vm"),
            dhcp_leases: var_or(get, "MC_DHCP_LEASES",
                "/mnt/c/ProgramData/VMware/vmnetdhcp.leases",
            ),
            iso_cache: var_or(get, "MC_ISO_CACHE", "/mnt/c/photon-mc/iso-cache"),
            results_dir: var_or(get, "MC_RESULTS_DIR", "/root/photon-mc/results"),
            build_log_dir: var_or(get, "MC_BUILD_LOG_DIR", "/root/photon-mc/build-logs"),
            work: var_or(get, "MC_WORK", "/root/photon-mc/work"),
            variant_patches: var_or(get, "MC_VARIANT_PATCH_DIR", "/root/photon-mc/variant-patches"),
            run_log_dir: var_or(get, "MC_RUN_LOG_DIR", "/root/photon-mc/run-logs"),
            memory_db: var_or(get, "SHARUKHAN_DB", "/root/photon-mc/memory.db"),
            matrix_tsv: DataFile::from_setting(get, "SHARUKHAN_MATRIX", "permutations.tsv", BUILTIN_MATRIX),
            variants_file: DataFile::from_setting(get, "SHARUKHAN_VARIANTS", "variants.conf", BUILTIN_VARIANTS),
            check_prs: DataFile::from_setting(get, "SHARUKHAN_CHECK_PRS", "check-prs.tsv", BUILTIN_CHECK_PRS),

            photon_tree: var_or(get, "PHOTON_TREE", "/root/5.0"),
            poi_tree: var_or(get, "POI_TREE", "/root/photon-os-installer"),

            build_root: var_or(get, "MC_BUILD_ROOT", "/root"),
            build_common: s_or(get, "MC_BUILD_COMMON", "common"),
            release: s_or(get, "MC_RELEASE", "5.0"),
            photon_remote: s_or(get, "MC_PHOTON_REMOTE", "https://github.com/dcasota/photon.git"),
            fork: s_or(get, "MC_FORK", "dcasota/photon"),
            upstream: s_or(get, "MC_UPSTREAM", "vmware/photon"),
            gate_repo: var_or(get, "MC_GATE_REPO", "/root/photon-mc/gate/photon.git"),
            fork_installer: s_or(get, "MC_FORK_INSTALLER", "dcasota/photon-os-installer"),
            upstream_installer: s_or(get, "MC_UPSTREAM_INSTALLER", "vmware/photon-os-installer"),
            installer_branch: s_or(get, "MC_INSTALLER_BRANCH", "master"),
            iso_store: get("MC_ISO_STORE").filter(|v| !v.is_empty()).map(PathBuf::from),
            fastloop_rows: s_or(get, "MC_FASTLOOP_ROWS", "k03 c03").split([' ', ',']).filter(|r| !r.is_empty()).map(str::to_string).collect(),
            staged_rows: s_or(get, "MC_STAGED_ROWS", "k11").split([' ', ',']).filter(|r| !r.is_empty()).map(str::to_string).collect(),
            kernel: None,
            systemd: None,
            baseline: None,

            guest_vcpus: n_or(get, "GUEST_VCPUS", 2),
            guest_mem_mb: n_or(get, "GUEST_MEM_MB", 4096),
            boot_disk_size: s_or(get, "BOOT_DISK_SIZE", "32GB"),
            boot_disk_adapter: s_or(get, "BOOT_DISK_ADAPTER", "lsilogic"),
            boot_disk_type: s_or(get, "BOOT_DISK_TYPE", "0"),

            net_gateway: s_or(get, "MC_NET_GATEWAY", &format!("{net_prefix}.2")),
            net_dns: s_or(get, "MC_NET_DNS", &format!("{net_prefix}.2")),
            net_cidr: n_or(get, "MC_NET_CIDR", 24),
            net_v6_prefix: s_or(get, "MC_NET_V6_PREFIX", "fd00:225"),
            net_vlan_prefix: s_or(get, "MC_NET_VLAN_PREFIX", "192.168.100"),
            ip_base: n_or(get, "MC_IP_BASE", 40),
            nic_dev: s_or(get, "MC_NIC_DEV", "e1000"),
            net_prefix,

            ssh_key_dir: var_or(get, "SSH_KEY_DIR",
                &format!(
                    "{}/.ssh",
                    get("HOME").unwrap_or_else(|| "/root".into())
                ),
            ),
            ssh_key_name: s_or(get, "SSH_KEY_NAME", "photon-mc-rsa"),
            ssh_user: s_or(get, "SSH_USER", "root"),
            // the value, or a secret file holding it (the services: `sharukhan service install`)
            guest_password: get("MC_GUEST_PASSWORD").filter(|v| !v.is_empty()).map(Ok).or_else(|| {
                get("MC_GUEST_PASSWORD_FILE")
                    .filter(|v| !v.is_empty())
                    .map(|f| crate::secret::read(std::path::Path::new(&f)).map_err(|e| format!("MC_GUEST_PASSWORD_FILE: {e}")))
            }),

            serial_log_prefix: s_or(get, "SERIAL_LOG_PREFIX", "serial0"),
            install_timeout_sec: n_or(get, "MC_INSTALL_TIMEOUT_SEC", 2400),
            start_timeout_sec: n_or(get, "MC_START_TIMEOUT", 240),
        }
    }

    /// The effective path, repository and identity settings, by the
    /// environment variable that sets each - what a script driving sharukhan
    /// needs without repeating a default (`sharukhan settings`). Nothing
    /// secret: the guest password is never a setting printed here.
    pub fn effective(&self) -> Vec<(&'static str, String)> {
        let p = |v: &PathBuf| v.to_string_lossy().into_owned();
        vec![
            ("MC_RELEASE", self.release.clone()),
            ("MC_BUILD_COMMON", self.build_common.clone()),
            ("MC_BUILD_ROOT", p(&self.build_root)),
            ("PHOTON_TREE", p(&self.photon_tree)),
            ("MC_WORK", p(&self.work)),
            ("MC_GATE_REPO", p(&self.gate_repo)),
            ("MC_PHOTON_REMOTE", self.photon_remote.clone()),
            ("MC_FORK", self.fork.clone()),
            ("MC_UPSTREAM", self.upstream.clone()),
            ("MC_VARIANT_PATCH_DIR", p(&self.variant_patches)),
            ("MC_ISO_CACHE", p(&self.iso_cache)),
            ("MC_ISO_STORE", self.iso_store.as_ref().map(p).unwrap_or_default()),
            ("MC_RESULTS_DIR", p(&self.results_dir)),
            ("MC_RUN_LOG_DIR", p(&self.run_log_dir)),
            ("MC_BUILD_LOG_DIR", p(&self.build_log_dir)),
            ("MC_VM_ROOT_WSL", p(&self.vm_root)),
            ("SHARUKHAN_DB", p(&self.memory_db)),
            // empty: the copy built into sharukhan
            ("SHARUKHAN_MATRIX", self.matrix_tsv.path.as_ref().map(p).unwrap_or_default()),
            ("SHARUKHAN_VARIANTS", self.variants_file.path.as_ref().map(p).unwrap_or_default()),
            ("SHARUKHAN_CHECK_PRS", self.check_prs.path.as_ref().map(p).unwrap_or_default()),
            ("MC_FASTLOOP_ROWS", self.fastloop_rows.join(" ")),
            ("MC_STAGED_ROWS", self.staged_rows.join(" ")),
        ]
    }

    /// `effective()` as shell assignments, single-quoted so any value is
    /// taken literally when sourced.
    pub fn effective_shell(&self) -> String {
        self.effective()
            .into_iter()
            .map(|(k, v)| format!("{k}='{}'\n", v.replace('\'', "'\\''")))
            .collect()
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
        match &self.guest_password {
            Some(Ok(v)) => Ok(v.as_str()),
            Some(Err(e)) => Err(e.clone()),
            None => Err("MC_GUEST_PASSWORD is not set (nor MC_GUEST_PASSWORD_FILE). It is the root password of every VM this harness \
                 installs, so it has no default and is never written down here. Export it for the \
                 run, e.g. `read -rs MC_GUEST_PASSWORD; export MC_GUEST_PASSWORD`."
                .to_string()),
        }
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
        self.vm_dir(id)
            .join(format!("{}-{vm}.log", self.serial_log_prefix))
    }
    /// The ISO cache key is the set of BUILD-time axes and nothing else: iso
    /// type, installer version, canister. Rows that need a locally built
    /// canister must not silently reuse the prebuilt ISO - that is how an axis
    /// ends up never exercised.
    pub fn iso_dir(&self, iso_type: &str, poi: &str, canister: &str) -> PathBuf {
        self.iso_cache
            .join(format!("{iso_type}-poi{poi}-{canister}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_configuration_files_are_built_in_unless_a_setting_names_one() {
        let c = Config::defaults();
        for f in [&c.matrix_tsv, &c.variants_file, &c.check_prs] {
            assert!(f.path.is_none(), "{}", f.setting);
            assert!(f.label().starts_with("built-in config/"), "{}", f.label());
            assert!(!f.text().unwrap().is_empty());
        }
        // every built-in copy is valid as it is compiled in
        assert!(crate::matrix::load_file(&c.matrix_tsv).unwrap().len() > 10);
        crate::variants::load_file(&c.variants_file).unwrap();
        assert!(!crate::evidence::load_attribution_file(&c.check_prs).unwrap().is_empty());

        // an empty setting is unset; a set one replaces the built-in copy, and
        // a missing file is an error that names the setting, never a fallback
        let empty = Config::from(&|k: &str| (k == "SHARUKHAN_MATRIX").then(|| " ".to_string()));
        assert!(empty.matrix_tsv.path.is_none());
        let d = std::env::temp_dir().join(format!("shk-datafile-{}", std::process::id()));
        std::fs::create_dir_all(&d).unwrap();
        let f = d.join("m.tsv");
        std::fs::write(&f, "x").unwrap();
        let fs = f.display().to_string();
        let set = Config::from(&|k: &str| (k == "SHARUKHAN_MATRIX").then(|| fs.clone()));
        assert_eq!(set.matrix_tsv.text().unwrap(), "x");
        assert_eq!(set.matrix_tsv.label(), fs);
        std::fs::remove_file(&f).unwrap();
        let e = set.matrix_tsv.text().unwrap_err();
        assert!(e.contains("SHARUKHAN_MATRIX"), "{e}");
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn paths_are_derived_consistently() {
        let c = Config::defaults();
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
        let c = Config::defaults();
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

    #[test]
    fn the_effective_settings_are_the_configured_ones_and_never_a_secret() {
        let c = Config::from(&|k: &str| match k {
            "MC_WORK" => Some("/w/work".into()),
            "MC_ISO_STORE" => Some("/iso/it's".into()),
            "MC_GUEST_PASSWORD" => Some("secret-value".into()),
            _ => None,
        });
        let e = c.effective();
        let get = |k: &str| e.iter().find(|(n, _)| *n == k).map(|(_, v)| v.clone()).unwrap();
        assert_eq!(get("MC_WORK"), "/w/work");
        assert_eq!(get("MC_RELEASE"), "5.0", "a default, as Config uses it");
        let sh = c.effective_shell();
        assert!(sh.contains("MC_ISO_STORE='/iso/it'\\''s'\n"), "{sh}");
        assert!(!sh.contains("secret-value") && !sh.contains("PASSWORD"));
        // every name is a setting the services carry, so service install and this agree
        for (k, _) in &e {
            assert!(crate::service::SETTINGS.contains(k), "{k} is not a service setting");
        }
    }

    /// The password has no default. This test is the guard against someone
    /// restoring one "just for convenience".
    #[test]
    fn guest_password_has_no_default() {
        let mut c = Config::defaults();
        c.guest_password = None;
        let e = c.guest_password().unwrap_err();
        assert!(e.contains("MC_GUEST_PASSWORD"));
        c.guest_password = Some(Ok("x".into()));
        assert_eq!(c.guest_password().unwrap(), "x");
    }
}
