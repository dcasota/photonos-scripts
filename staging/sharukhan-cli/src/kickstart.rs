//! The POI kickstart for one permutation. Ported from mc-gen-kickstart.sh.
//!
//! The install-time axes live HERE, not on the media: STIG, filesystem and the
//! kickstart-only variants are injected per VM through
//! guestinfo.kickstart.data, which is why 34 permutations need only 4 ISOs.
//!
//! Every field is typed. The bash built a python dict and let json.dumps
//! decide, which is how `security.fips` came within one character of being an
//! int - see [`Security::fips`].

use serde::Serialize;

/// The eight names stigenable.py requests when the STIG menu is answered yes,
/// minus the three POI#9 dropped as redundant (libselinux-utils, ntp,
/// libgcrypt). A kickstart cannot answer that menu - it exists only in the
/// curses configurator - so a kickstart that wants STIG must list them itself.
/// That is what variant=stigpkgs reproduces, and it is a genuinely different
/// code path from the UI row, not a duplicate of it.
pub const STIG_PACKAGES: [&str; 5] = [
    "audit",
    "rsyslog",
    "openssl-fips-provider",
    "selinux-policy",
    "aide",
];

#[derive(Serialize)]
pub struct Password {
    pub crypted: bool,
    pub text: String,
}

#[derive(Serialize)]
pub struct Partition {
    pub mountpoint: String,
    pub size: u32,
    pub filesystem: String,
}

#[derive(Serialize)]
pub struct Ansible {
    pub playbook: String,
    pub logfile: String,
    pub verbosity: u32,
    #[serde(rename = "extra-vars")]
    pub extra_vars: String,
    /// PHTN-50-000245 edits tmp.mount, which is package-owned and not
    /// %config. Editing it from the playbook shows as permanent `rpm -V`
    /// drift and is reverted by the next systemd upgrade, so the build side
    /// owns it.
    #[serde(rename = "skip-tags")]
    pub skip_tags: Vec<String>,
}

/// The kickstart-only failure class. On POI 2.8 this key is present only if
/// the author writes it; POI master synthesises `selinux` for everyone. `fips`
/// is never appended on the UI path on either version, so variant=fips is
/// reachable exclusively from a kickstart.
#[derive(Serialize, Default)]
pub struct Security {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub selinux: Option<String>,
    /// MUST be a bool. POI validates with `isinstance(security['fips'], bool)`
    /// at installer.py:709, and 1 is an int: json.dumps writes it as `1`
    /// rather than `true`, the installer aborts with "fips mode must be
    /// boolean or null", and it drops to a root shell that no kickstart can
    /// answer. Typing it as `bool` is what makes that unrepresentable.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fips: Option<bool>,
}

#[derive(Serialize)]
#[serde(untagged)]
pub enum Network {
    Static {
        #[serde(rename = "type")]
        kind: &'static str,
        ip_addr: String,
        netmask: String,
        gateway: String,
        nameserver: String,
    },
    Dhcp {
        #[serde(rename = "type")]
        kind: &'static str,
    },
}

/// Field order is declaration order, which keeps a generated kickstart
/// diffable against the ones already in results/<id>/kickstart.json.
#[derive(Serialize)]
pub struct Kickstart {
    /// Carries the permutation id so a guest self-identifies in every log line
    /// it ever emits.
    pub hostname: String,
    pub password: Password,
    pub disk: String,
    pub partitions: Vec<Partition>,
    /// The ONLY package list on the installer media is
    /// /installer/packages.json. "packages_minimal.json" exists in the POI
    /// source tree but is not shipped in the initrd, and naming it aborts the
    /// install with FileNotFoundError: '/installer/packages_minimal.json'.
    pub packagelist_file: String,
    pub linux_flavor: String,
    pub bootmode: String,
    pub postinstall: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub public_key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub additional_packages: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ansible: Option<Vec<Ansible>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub security: Option<Security>,
    pub network: Network,
}

pub struct Spec<'a> {
    pub id: &'a str,
    pub fs: &'a str,
    pub stig: &'a str,
    pub variant: &'a str,
    pub password: &'a str,
    pub public_key: Option<String>,
    /// `addr/cidr`; the address before the slash is what POI is given.
    pub ip: Option<String>,
    /// Only meaningful when `ip` is set. The NAT device serves both roles.
    pub gateway: &'a str,
    pub nameserver: &'a str,
}

pub fn build(s: &Spec) -> Kickstart {
    let partitions = vec![
        Partition { mountpoint: "/boot/efi".into(), size: 512, filesystem: "vfat".into() },
        Partition { mountpoint: "/boot".into(), size: 1024, filesystem: "ext4".into() },
        // size 0 = the rest of the disk. This is the filesystem axis.
        Partition { mountpoint: "/".into(), size: 0, filesystem: s.fs.into() },
    ];

    let postinstall = vec![
        "#!/bin/sh".to_string(),
        format!("echo mc-{} > /etc/mission-control-permutation", s.id),
        "systemctl enable sshd.service".to_string(),
        // Make the INSTALLED system serial-visible too. Remastering the ISO
        // only fixes the installer; after the reboot the target has its own
        // grub, so the serial log goes silent exactly when verification needs
        // it and the boot-source oracle can never observe root=PARTUUID=.
        "sed -i 's|^\\(GRUB_CMDLINE_LINUX=.*\\)\"$|\\1 console=ttyS0,115200n8\"|' /etc/default/grub 2>/dev/null || true".to_string(),
        "grep -q console=ttyS0 /boot/grub2/grub.cfg || sed -i 's|\\(^\\s*linux .*root=PARTUUID=[^ ]*\\)|\\1 console=ttyS0,115200n8|' /boot/grub2/grub.cfg 2>/dev/null || true".to_string(),
        // Root ssh is how verification gets in. This is a disposable lab VM on
        // a host-only NAT segment, torn down after the run.
        "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config".to_string(),
    ];

    // variant=stigpkgs is the kickstart expression of "STIG = yes".
    let stig_wanted = s.variant == "stigpkgs" || s.stig == "yes";
    let (additional_packages, ansible) = if stig_wanted {
        (
            Some(STIG_PACKAGES.iter().map(|p| p.to_string()).collect()),
            Some(vec![Ansible {
                playbook: "/usr/share/ansible/stig-hardening/playbook.yml".into(),
                logfile: "ansible-stig.log".into(),
                verbosity: 2,
                extra_vars: "@/usr/share/ansible/stig-hardening/vars-chroot.yml".into(),
                skip_tags: vec!["PHTN-50-000245".into()],
            }]),
        )
    } else {
        (None, None)
    };

    let security = match s.variant {
        "selinux" => Some(Security { selinux: Some("permissive".into()), ..Default::default() }),
        "fips" => Some(Security { fips: Some(true), ..Default::default() }),
        _ => None,
    };

    let network = match &s.ip {
        Some(ip) => Network::Static {
            kind: "static",
            ip_addr: ip.split('/').next().unwrap_or(ip).to_string(),
            netmask: "255.255.255.0".into(),
            // The bash left these empty, which produces a guest with no route
            // and no resolver - it boots, then fails every check that needs the
            // network, which reads like a broken image rather than a broken
            // kickstart. VMnet8's NAT device is both router and DNS forwarder;
            // vmnetnat.conf has `ip = 192.168.225.2/24` and vmnetdhcp.conf
            // hands leases `option routers`/`domain-name-servers 192.168.225.2`.
            gateway: s.gateway.to_string(),
            nameserver: s.nameserver.to_string(),
        },
        None => Network::Dhcp { kind: "dhcp" },
    };

    Kickstart {
        hostname: format!("mc-{}", s.id),
        password: Password { crypted: false, text: s.password.to_string() },
        disk: "/dev/sda".into(),
        partitions,
        packagelist_file: "packages.json".into(),
        linux_flavor: "linux-esx".into(),
        bootmode: "efi".into(),
        postinstall,
        public_key: s.public_key.clone().filter(|k| !k.trim().is_empty()),
        additional_packages,
        ansible,
        security,
        network,
    }
}

/// Four-space indent, matching what json.dumps(indent=4) wrote, so an existing
/// kickstart.json and a regenerated one differ only where the content differs.
pub fn to_json(ks: &Kickstart) -> Result<String, String> {
    let mut buf = Vec::new();
    let fmt = serde_json::ser::PrettyFormatter::with_indent(b"    ");
    let mut ser = serde_json::Serializer::with_formatter(&mut buf, fmt);
    ks.serialize(&mut ser).map_err(|e| format!("serialising kickstart: {e}"))?;
    String::from_utf8(buf).map_err(|e| format!("kickstart is not UTF-8: {e}"))
}

pub fn render(s: &Spec) -> Result<String, String> {
    to_json(&build(s))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spec<'a>(variant: &'a str, stig: &'a str, fs: &'a str) -> Spec<'a> {
        Spec {
            id: "k03",
            fs,
            stig,
            variant,
            password: "not-a-real-password",
            public_key: Some("ssh-ed25519 AAAA photon-mc@host".into()),
            ip: None,
            gateway: "192.168.225.2",
            nameserver: "192.168.225.2",
        }
    }

    /// The evidence copy of a kickstart is the file a report cites. It must
    /// carry the structure and not the secret - scrubbing the tree afterwards
    /// does not hold, because the next run writes the password straight back.
    #[test]
    fn a_redacted_kickstart_keeps_its_shape_and_loses_its_secret() {
        let mut sp = spec("none", "none", "ext4");
        sp.password = "a-real-looking-password";
        let real = render(&sp).unwrap();
        sp.password = "***REDACTED***";
        let safe = render(&sp).unwrap();
        assert!(real.contains("a-real-looking-password"));
        assert!(!safe.contains("a-real-looking-password"), "secret survived: {safe}");
        assert!(safe.contains("***REDACTED***"), "{safe}");
        // structure identical: same lines, same order, one value differs
        let (a, b): (Vec<_>, Vec<_>) = (real.lines().collect(), safe.lines().collect());
        assert_eq!(a.len(), b.len(), "redaction changed the shape");
        assert_eq!(
            a.iter().zip(&b).filter(|(x, y)| x != y).count(),
            1,
            "redaction touched more than the password"
        );
    }

    /// A static guest with an empty gateway boots and then fails every check
    /// that needs the network, which reads like a broken image rather than a
    /// broken kickstart. The bash emitted empty strings here.
    #[test]
    fn a_static_address_carries_a_route_and_a_resolver() {
        let mut sp = spec("none", "none", "ext4");
        sp.ip = Some("192.168.225.52/24".into());
        let out = render(&sp).unwrap();
        assert!(out.contains("\"type\": \"static\""), "{out}");
        assert!(out.contains("\"ip_addr\": \"192.168.225.52\""), "{out}");
        assert!(out.contains("\"gateway\": \"192.168.225.2\""), "{out}");
        assert!(out.contains("\"nameserver\": \"192.168.225.2\""), "{out}");
        assert!(!out.contains("\"gateway\": \"\""), "empty gateway regressed: {out}");
    }

    /// The bug this type exists to prevent: `1` is an int, POI's
    /// isinstance(..., bool) rejects it, and the installer drops to a root
    /// shell no kickstart can answer.
    #[test]
    fn fips_is_a_json_bool_not_a_one() {
        let j = render(&spec("fips", "no", "ext4")).unwrap();
        assert!(j.contains("\"fips\": true"), "{j}");
        assert!(!j.contains("\"fips\": 1"));
        // Only the requested key is written; POI 2.8 treats an absent selinux
        // key differently from a present one.
        assert!(!j.contains("selinux"));
    }

    #[test]
    fn selinux_variant_writes_only_selinux() {
        let j = render(&spec("selinux", "no", "ext4")).unwrap();
        assert!(j.contains("\"selinux\": \"permissive\""));
        assert!(!j.contains("fips"));
    }

    #[test]
    fn stig_is_five_packages_and_a_skipped_tag() {
        let ks = build(&spec("stigpkgs", "no", "ext4"));
        assert_eq!(ks.additional_packages.as_ref().unwrap().len(), 5);
        let a = &ks.ansible.as_ref().unwrap()[0];
        assert_eq!(a.skip_tags, vec!["PHTN-50-000245".to_string()]);
        // stig=yes reaches the same place from the other direction.
        assert!(build(&spec("none", "yes", "ext4")).additional_packages.is_some());
        // and a row that asks for neither must not silently get them.
        assert!(build(&spec("none", "no", "ext4")).additional_packages.is_none());
        assert!(build(&spec("none", "no", "ext4")).ansible.is_none());
    }

    #[test]
    fn the_filesystem_axis_reaches_the_root_partition() {
        let ks = build(&spec("none", "no", "btrfs"));
        let root = ks.partitions.iter().find(|p| p.mountpoint == "/").unwrap();
        assert_eq!(root.filesystem, "btrfs");
        assert_eq!(root.size, 0);
        // /boot stays ext4 whatever the axis says: grub reads it.
        assert_eq!(ks.partitions[1].filesystem, "ext4");
    }

    #[test]
    fn the_password_comes_from_the_caller_and_is_never_defaulted() {
        let j = render(&spec("none", "no", "ext4")).unwrap();
        assert!(j.contains("\"text\": \"not-a-real-password\""));
        assert!(j.contains("\"crypted\": false"));
    }

    #[test]
    fn a_key_is_written_only_when_there_is_one() {
        let mut s = spec("none", "no", "ext4");
        assert!(render(&s).unwrap().contains("public_key"));
        s.public_key = None;
        assert!(!render(&s).unwrap().contains("public_key"));
        s.public_key = Some("   ".into());
        assert!(!render(&s).unwrap().contains("public_key"));
    }

    #[test]
    fn static_network_drops_the_cidr_suffix() {
        let mut s = spec("none", "no", "ext4");
        s.ip = Some("192.168.225.43/24".into());
        let j = render(&s).unwrap();
        assert!(j.contains("\"ip_addr\": \"192.168.225.43\""), "{j}");
        assert!(j.contains("\"type\": \"static\""));
        s.ip = None;
        assert!(render(&s).unwrap().contains("\"type\": \"dhcp\""));
    }

    #[test]
    fn the_hostname_and_marker_carry_the_permutation_id() {
        let ks = build(&spec("none", "no", "ext4"));
        assert_eq!(ks.hostname, "mc-k03");
        assert!(ks
            .postinstall
            .iter()
            .any(|l| l.contains("echo mc-k03 > /etc/mission-control-permutation")));
        // The installed system must keep a serial console, or the
        // boot-source oracle can never observe root=PARTUUID=.
        assert!(ks.postinstall.iter().any(|l| l.contains("console=ttyS0,115200n8")));
    }

    #[test]
    fn the_only_package_list_on_the_media_is_named() {
        assert_eq!(build(&spec("none", "no", "ext4")).packagelist_file, "packages.json");
    }
}
