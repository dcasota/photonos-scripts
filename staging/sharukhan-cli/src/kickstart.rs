//! The POI kickstart for one permutation. Ported from mc-gen-kickstart.sh.
//!
//! The install-time axes live HERE, not on the media: STIG, filesystem and the
//! kickstart-only variants are injected per VM through
//! guestinfo.kickstart.data, which is why 34 permutations need only 4 ISOs.
//!
//! Every field is typed. The bash built a python dict and let json.dumps
//! decide, which is how `security.fips` came within one character of being an
//! int - see [`Security::fips`].

use crate::net::{Assign, Family, NetSpec, Schema};
use serde::Serialize;
use std::collections::BTreeMap;

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

/// One `ethernets.<id>` entry of the v2 (netplan-style) schema.
///
/// Every field is optional and every absent field is OMITTED rather than
/// written as null, because `networkmanager.py` tests membership
/// (`if 'dhcp4' in iface_config`) rather than truthiness: a `"gateway": null`
/// would be read as a gateway and rendered as the literal `Gateway=None`.
#[derive(Serialize)]
pub struct Iface {
    /// `match.name` must be an EXACT interface name whenever a VLAN links to
    /// this interface - `_get_vlan_iface_name` builds the tagged name from it
    /// and raises on a wildcard, so `"e*"` is legal here in general but not
    /// under a VLAN. Photon boots with `net.ifnames=0` (SPECS/systemd/
    /// systemd.cfg, and POI's own mk-setup-grub.sh), so the names are eth0/eth1.
    #[serde(rename = "match")]
    pub match_: Match,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dhcp4: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dhcp6: Option<bool>,
    /// Router Advertisement. Written explicitly as `false` on every row this
    /// harness generates, and asserted as such: `natIp6Enable = 0` in
    /// vmnetnat.conf means there is no RA on vmnet8 to accept, so a row that
    /// silently accepted RA would be claiming a capability the host does not
    /// have. `networkmanager.py` emits `IPv6AcceptRA=` unconditionally, so the
    /// value is observable in the guest either way.
    #[serde(rename = "accept-ra", skip_serializing_if = "Option::is_none")]
    pub accept_ra: Option<bool>,
    /// `addr/cidr`, IPv4 and IPv6 freely mixed - this list is the whole of the
    /// dual-stack story, since `write_network_file` emits one `Address=` per
    /// entry regardless of family.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub addresses: Option<Vec<String>>,
    /// A SCALAR, deliberately. `write_systemd_config` would iterate a list and
    /// emit two `Gateway=` lines, which is how a dual-stack row could get an
    /// IPv6 default route - but that behaviour is undocumented, untested
    /// upstream, and would be claiming a route to a router this host does not
    /// run. One IPv4 gateway, and the v6 side is left routeless on purpose.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gateway: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nameservers: Option<Nameservers>,
}

#[derive(Serialize)]
pub struct Match {
    pub name: String,
}

#[derive(Serialize)]
pub struct Nameservers {
    pub addresses: Vec<String>,
}

/// One `vlans.<id>` entry. `id` and `link` are the two keys that make it a
/// VLAN rather than another ethernet; `link` must name an id from `ethernets`
/// or `write_interfaces` raises.
#[derive(Serialize)]
pub struct Vlan {
    /// 1..=4094, enforced by `write_netdev_file`. [`crate::net::NetSpec`]
    /// rejects an out-of-range id at matrix-load time so the run fails in
    /// milliseconds instead of hours later inside the installer.
    pub id: u16,
    pub link: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dhcp4: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub addresses: Option<Vec<String>>,
}

/// POI accepts two network schemas and sniffs which one it was given:
/// `NetworkManager.__init__` runs `_convert_legacy_config` when the config has
/// a `type` key or `version` is "1". They are genuinely different code paths,
/// and which one a row exercises is decided by [`crate::net::NetSpec::schema`].
///
/// `Dhcp` is the shape all 36 pre-axis rows emit and must keep emitting byte
/// for byte - see `the_default_net_token_reproduces_the_legacy_dhcp_kickstart`.
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
    /// Legacy `type: vlan`. Carries ONLY the id: `_convert_legacy_config`
    /// hardcodes `dhcp4: True` on both the eth0 parent and the tagged
    /// interface, with no way to ask for anything else. That is why a static
    /// address on a tag has to go through the v2 schema instead.
    Vlan {
        #[serde(rename = "type")]
        kind: &'static str,
        /// A STRING. `_convert_legacy_config` does `int(vlan_id)` itself, and
        /// ks_config.md documents it as "ID String".
        vlan_id: String,
    },
    Dhcp {
        #[serde(rename = "type")]
        kind: &'static str,
    },
    V2 {
        version: &'static str,
        /// BTreeMap, not HashMap: the key order is the emitted order, and a
        /// kickstart whose keys shuffle between runs is not diffable against
        /// the copy stored in results/<id>/kickstart.json.
        ethernets: BTreeMap<String, Iface>,
        #[serde(skip_serializing_if = "Option::is_none")]
        vlans: Option<BTreeMap<String, Vlan>>,
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
    /// The network axis. THIS is what decides the shape of the emitted
    /// `network` block - not the presence of an address. A row whose axis says
    /// dhcp emits dhcp even if an address was handed in, so a stray value can
    /// never turn a DHCP row into a static one behind the matrix's back.
    pub net: &'a NetSpec,
    /// `addr/cidr` for the primary interface. Required when the axis says
    /// static and the family includes IPv4.
    pub ip: Option<String>,
    /// `addr/cidr` for the primary interface's IPv6 address. Required when the
    /// axis says static and the family includes IPv6. Always a ULA
    /// (fd00::/8): the host has no IPv6 router, so a global prefix here would
    /// be claiming reachability that does not exist.
    pub ip6: Option<String>,
    /// `addr/cidr` for the tagged sub-interface, on a v2 VLAN row. It lives on
    /// its own private /24 so it can never be mistaken for the management
    /// segment, and it is STATIC so the link reaches `configured` without a
    /// server - nothing on vmnet8 answers a tagged frame.
    pub vlan_ip: Option<String>,
    /// The IPv4 prefix length. The NAT segment is a /24; this is the only
    /// place that number turns into the dotted netmask the legacy schema wants.
    pub cidr: u32,
    /// Only meaningful when an address is configured. The NAT device serves
    /// both roles.
    pub gateway: &'a str,
    pub nameserver: &'a str,
}

/// The legacy schema wants a dotted-quad netmask; everything else wants a
/// prefix length. `netmask_to_cidr` in networkmanager.py converts the other
/// way and does it by splitting on '.', which is also why the legacy schema
/// cannot express an IPv6 address at all.
fn cidr_to_netmask(cidr: u32) -> String {
    let bits: u32 = if cidr >= 32 { u32::MAX } else { !(u32::MAX >> cidr) };
    format!(
        "{}.{}.{}.{}",
        bits >> 24,
        (bits >> 16) & 0xff,
        (bits >> 8) & 0xff,
        bits & 0xff
    )
}

/// The `network` block for one row.
///
/// Separated from [`build`] so the whole decision is testable as a value, and
/// so the two schemas sit side by side where the difference between them is
/// visible.
fn build_network(s: &Spec) -> Result<Network, String> {
    let want_v4 = matches!(s.net.family, Family::V4 | Family::Dual);
    let want_v6 = matches!(s.net.family, Family::V6 | Family::Dual);
    let is_static = s.net.assign == Assign::Static;

    // A static row with no address would install a guest with no route and no
    // resolver: it boots, then fails every check that needs the network, which
    // reads like a broken image rather than a broken kickstart. That was the
    // bash's behaviour with an empty gateway, and it cost hours.
    let need = |what: &str, v: &Option<String>| -> Result<String, String> {
        v.clone().ok_or_else(|| {
            format!(
                "net={}: the axis says static but no {what} address was supplied",
                s.net
            )
        })
    };

    match s.net.schema() {
        Schema::Legacy => Ok(match (s.net.vlan, is_static) {
            // _convert_legacy_config forces dhcp4 on BOTH the eth0 parent and
            // the tag; the id is the only thing this shape can carry.
            (Some(id), _) => Network::Vlan { kind: "vlan", vlan_id: id.to_string() },
            (None, true) => {
                let ip = need("IPv4", &s.ip)?;
                Network::Static {
                    kind: "static",
                    ip_addr: ip.split('/').next().unwrap_or(&ip).to_string(),
                    netmask: cidr_to_netmask(s.cidr),
                    // The bash left these empty, which produces a guest with no
                    // route and no resolver. VMnet8's NAT device is both router
                    // and DNS forwarder; vmnetnat.conf has `ip =
                    // 192.168.225.2/24` and vmnetdhcp.conf hands leases
                    // `option routers`/`domain-name-servers 192.168.225.2`.
                    gateway: s.gateway.to_string(),
                    nameserver: s.nameserver.to_string(),
                }
            }
            (None, false) => Network::Dhcp { kind: "dhcp" },
        }),
        Schema::V2 => {
            let mut addresses = Vec::new();
            if want_v4 && is_static {
                addresses.push(need("IPv4", &s.ip)?);
            }
            if want_v6 && is_static {
                addresses.push(need("IPv6", &s.ip6)?);
            }

            let mut ethernets = BTreeMap::new();
            ethernets.insert(
                "id0".to_string(),
                Iface {
                    match_: Match { name: "eth0".into() },
                    dhcp4: Some(want_v4 && !is_static),
                    dhcp6: Some(want_v6 && !is_static),
                    // No RA exists on vmnet8 to accept - natIp6Enable = 0 - so
                    // this is false everywhere and asserted as such.
                    accept_ra: Some(false),
                    addresses: (!addresses.is_empty()).then_some(addresses),
                    // A route and a resolver only where there is an IPv4 path
                    // to reach them by. An IPv6-only interface here has no
                    // gateway on purpose: the host runs no IPv6 router, and
                    // writing one would be inventing a route.
                    gateway: want_v4.then(|| s.gateway.to_string()),
                    nameservers: want_v4.then(|| Nameservers {
                        addresses: vec![s.nameserver.to_string()],
                    }),
                },
            );

            // The management interface. An IPv6-only guest is unreachable from
            // WSL2 for three independent reasons, so without this NIC the row
            // could be installed and never verified.
            if s.net.needs_second_nic() {
                ethernets.insert(
                    "id1".to_string(),
                    Iface {
                        match_: Match { name: "eth1".into() },
                        dhcp4: Some(true),
                        dhcp6: Some(false),
                        accept_ra: Some(false),
                        addresses: None,
                        gateway: None,
                        nameservers: None,
                    },
                );
            }

            let vlans = match s.net.vlan {
                None => None,
                Some(id) => {
                    let mut m = BTreeMap::new();
                    m.insert(
                        format!("vlan{id}"),
                        Vlan {
                            id,
                            // Must name an id from `ethernets`, and that
                            // interface must carry a non-wildcard match.name -
                            // _get_vlan_iface_name builds "eth0.<id>" from it.
                            link: "id0".to_string(),
                            dhcp4: Some(false),
                            addresses: Some(vec![need("VLAN", &s.vlan_ip)?]),
                        },
                    );
                    Some(m)
                }
            };

            Ok(Network::V2 { version: "2", ethernets, vlans })
        }
    }
}

pub fn build(s: &Spec) -> Result<Kickstart, String> {
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

    let network = build_network(s)?;

    Ok(Kickstart {
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
    })
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
    to_json(&build(s)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    use std::str::FromStr;

    /// The default network axis, as a value with a lifetime the fixtures can
    /// borrow. Every pre-axis test borrows this, so those tests keep asserting
    /// about exactly the row shape they always did.
    fn dflt() -> NetSpec {
        NetSpec::default()
    }

    fn net(token: &str) -> NetSpec {
        NetSpec::from_str(token).unwrap()
    }

    fn spec<'a>(variant: &'a str, stig: &'a str, fs: &'a str, n: &'a NetSpec) -> Spec<'a> {
        Spec {
            id: "k03",
            fs,
            stig,
            variant,
            password: "not-a-real-password",
            public_key: Some("ssh-ed25519 AAAA photon-mc@host".into()),
            net: n,
            ip: None,
            ip6: None,
            vlan_ip: None,
            cidr: 24,
            gateway: "192.168.225.2",
            nameserver: "192.168.225.2",
        }
    }

    /// THE guard for the 36 rows that existed before this axis did.
    ///
    /// Every one of them carries no `net` column, lands on `net::DEFAULT`, and
    /// must emit the kickstart it always emitted - byte for byte, including
    /// key order and indentation, because results/<id>/kickstart.json holds
    /// stored copies that a report cites and a run is diffed against. The
    /// network axis is allowed to add rows; it is not allowed to change one.
    #[test]
    fn the_default_net_token_reproduces_the_legacy_dhcp_kickstart_byte_for_byte() {
        let d = dflt();
        let out = render(&spec("none", "no", "ext4", &d)).unwrap();

        // The exact tail of the document, at the exact indentation
        // json.dumps(indent=4) wrote.
        assert!(
            out.ends_with("    \"network\": {\n        \"type\": \"dhcp\"\n    }\n}"),
            "the default row's network block changed:\n{out}"
        );
        // Not one byte of the v2 schema may appear on a default row.
        for forbidden in ["version", "ethernets", "vlans", "accept-ra", "dhcp4", "dhcp6",
                          "addresses", "match", "static", "vlan_id"] {
            assert!(!out.contains(forbidden), "v2 key '{forbidden}' leaked into a default row:\n{out}");
        }
        // And the top-level key order is the stored order.
        let keys: Vec<&str> = out
            .lines()
            .filter(|l| l.starts_with("    \""))
            .map(|l| l.trim().trim_start_matches('"').split('"').next().unwrap())
            .collect();
        assert_eq!(
            keys,
            vec![
                "hostname", "password", "disk", "partitions", "packagelist_file",
                "linux_flavor", "bootmode", "postinstall", "public_key", "network",
            ],
            "field order is the stored format and must not move"
        );
    }

    /// The axis decides the shape, never a stray value. A DHCP row that
    /// happened to be handed an address must still emit DHCP - otherwise the
    /// matrix says one thing and the guest does another, and every check
    /// downstream reports on an axis nobody selected.
    #[test]
    fn an_address_cannot_turn_a_dhcp_row_into_a_static_one() {
        let d = dflt();
        let mut sp = spec("none", "no", "ext4", &d);
        sp.ip = Some("192.168.225.52/24".into());
        sp.ip6 = Some("fd00:225::52/64".into());
        let out = render(&sp).unwrap();
        assert!(out.contains("\"type\": \"dhcp\""), "{out}");
        assert!(!out.contains("192.168.225.52"), "{out}");
    }

    /// The mirror image: a static row with nothing to configure must be
    /// refused, not installed. A guest with no route and no resolver boots and
    /// then fails every check that needs the network, which reads like a broken
    /// image rather than a broken kickstart.
    #[test]
    fn a_static_row_with_no_address_is_refused_rather_than_installed() {
        for token in ["v4-static-untag", "v6-static-untag", "dual-static-untag",
                      "v4-static-vlan100"] {
            let n = net(token);
            let e = render(&spec("none", "no", "ext4", &n)).unwrap_err();
            assert!(e.contains(token), "error must name the axis: {e}");
        }
    }

    /// The evidence copy of a kickstart is the file a report cites. It must
    /// carry the structure and not the secret - scrubbing the tree afterwards
    /// does not hold, because the next run writes the password straight back.
    #[test]
    fn a_redacted_kickstart_keeps_its_shape_and_loses_its_secret() {
        let d = dflt();
        let mut sp = spec("none", "none", "ext4", &d);
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
        let n = net("v4-static-untag");
        let mut sp = spec("none", "none", "ext4", &n);
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
        let d = dflt();
        let j = render(&spec("fips", "no", "ext4", &d)).unwrap();
        assert!(j.contains("\"fips\": true"), "{j}");
        assert!(!j.contains("\"fips\": 1"));
        // Only the requested key is written; POI 2.8 treats an absent selinux
        // key differently from a present one.
        assert!(!j.contains("selinux"));
    }

    #[test]
    fn selinux_variant_writes_only_selinux() {
        let d = dflt();
        let j = render(&spec("selinux", "no", "ext4", &d)).unwrap();
        assert!(j.contains("\"selinux\": \"permissive\""));
        assert!(!j.contains("fips"));
    }

    #[test]
    fn stig_is_five_packages_and_a_skipped_tag() {
        let d = dflt();
        let ks = build(&spec("stigpkgs", "no", "ext4", &d)).unwrap();
        assert_eq!(ks.additional_packages.as_ref().unwrap().len(), 5);
        let a = &ks.ansible.as_ref().unwrap()[0];
        assert_eq!(a.skip_tags, vec!["PHTN-50-000245".to_string()]);
        // stig=yes reaches the same place from the other direction.
        assert!(build(&spec("none", "yes", "ext4", &d)).unwrap().additional_packages.is_some());
        // and a row that asks for neither must not silently get them.
        assert!(build(&spec("none", "no", "ext4", &d)).unwrap().additional_packages.is_none());
        assert!(build(&spec("none", "no", "ext4", &d)).unwrap().ansible.is_none());
    }

    #[test]
    fn the_filesystem_axis_reaches_the_root_partition() {
        let d = dflt();
        let ks = build(&spec("none", "no", "btrfs", &d)).unwrap();
        let root = ks.partitions.iter().find(|p| p.mountpoint == "/").unwrap();
        assert_eq!(root.filesystem, "btrfs");
        assert_eq!(root.size, 0);
        // /boot stays ext4 whatever the axis says: grub reads it.
        assert_eq!(ks.partitions[1].filesystem, "ext4");
    }

    #[test]
    fn the_password_comes_from_the_caller_and_is_never_defaulted() {
        let d = dflt();
        let j = render(&spec("none", "no", "ext4", &d)).unwrap();
        assert!(j.contains("\"text\": \"not-a-real-password\""));
        assert!(j.contains("\"crypted\": false"));
    }

    #[test]
    fn a_key_is_written_only_when_there_is_one() {
        let d = dflt();
        let mut s = spec("none", "no", "ext4", &d);
        assert!(render(&s).unwrap().contains("public_key"));
        s.public_key = None;
        assert!(!render(&s).unwrap().contains("public_key"));
        s.public_key = Some("   ".into());
        assert!(!render(&s).unwrap().contains("public_key"));
    }

    #[test]
    fn static_network_drops_the_cidr_suffix() {
        // The legacy schema wants a bare address and a dotted netmask;
        // netmask_to_cidr converts the other way by splitting on '.', which is
        // also why this shape can never carry an IPv6 address.
        let n = net("v4-static-untag");
        let mut sp = spec("none", "no", "ext4", &n);
        sp.ip = Some("192.168.225.43/24".into());
        let j = render(&sp).unwrap();
        assert!(j.contains("\"ip_addr\": \"192.168.225.43\""), "{j}");
        assert!(j.contains("\"netmask\": \"255.255.255.0\""), "{j}");
        assert!(j.contains("\"type\": \"static\""));
        // and the prefix length is the only place that netmask comes from
        sp.cidr = 16;
        assert!(render(&sp).unwrap().contains("\"netmask\": \"255.255.0.0\""));

        let d = dflt();
        assert!(render(&spec("none", "no", "ext4", &d)).unwrap().contains("\"type\": \"dhcp\""));
    }

    #[test]
    fn the_hostname_and_marker_carry_the_permutation_id() {
        let d = dflt();
        let ks = build(&spec("none", "no", "ext4", &d)).unwrap();
        assert_eq!(ks.hostname, "mc-k03");
        assert!(ks
            .postinstall
            .iter()
            .any(|l| l.contains("echo mc-k03 > /etc/mission-control-permutation")));
        // The installed system must keep a serial console, or the
        // boot-source oracle can never observe root=PARTUUID=.
        assert!(ks.postinstall.iter().any(|l| l.contains("console=ttyS0,115200n8")));
    }

    // ---- the network axis ------------------------------------------------

    fn ks_for<'a>(n: &'a NetSpec) -> String {
        let mut sp = spec("none", "no", "ext4", n);
        sp.ip = Some("192.168.225.78/24".into());
        sp.ip6 = Some("fd00:225::78/64".into());
        sp.vlan_ip = Some("192.168.100.78/24".into());
        render(&sp).unwrap()
    }

    /// n02. The whole dual-stack story is one `addresses` list:
    /// `write_network_file` emits one `Address=` per entry and does not care
    /// which family it is. If the two families ever landed in two interfaces
    /// or two files, the row would stop testing what it claims to.
    #[test]
    fn a_dual_stack_interface_carries_both_families_in_one_addresses_list() {
        let n = net("dual-static-untag");
        let j = ks_for(&n);
        assert!(j.contains("\"version\": \"2\""), "{j}");
        assert!(j.contains("192.168.225.78/24"), "{j}");
        assert!(j.contains("fd00:225::78/64"), "{j}");
        // exactly one interface, and therefore exactly one 50-*.network file
        assert_eq!(j.matches("\"match\"").count(), 1, "{j}");
        // one IPv4 gateway, never a list: write_systemd_config would iterate a
        // list and emit a second Gateway= line, which would be claiming a route
        // to an IPv6 router this host does not run.
        assert!(j.contains("\"gateway\": \"192.168.225.2\""), "{j}");
        assert_eq!(j.matches("\"gateway\"").count(), 1, "{j}");
        // and RA is refused explicitly: natIp6Enable = 0, so there is none.
        assert!(j.contains("\"accept-ra\": false"), "{j}");
    }

    /// n03. The point of the row is an interface with NO IPv4 whatsoever - a
    /// dual-stack guest that silently ignored its v6 address would still look
    /// healthy, so only this shape can expose that. The management NIC is what
    /// keeps the row verifiable at all.
    #[test]
    fn an_ipv6_only_row_carries_no_ipv4_and_gains_a_management_nic() {
        let n = net("v6-static-untag");
        let j = ks_for(&n);
        assert!(j.contains("fd00:225::78/64"), "{j}");
        assert!(!j.contains("192.168.225.78"), "an IPv4 address leaked in:\n{j}");
        // no gateway and no resolver on the v6 side: the host runs no IPv6
        // router, and writing one would be inventing a route.
        assert!(!j.contains("\"gateway\""), "{j}");
        // two interfaces: eth0 under test, eth1 so ssh has a path.
        assert!(j.contains("\"eth0\"") && j.contains("\"eth1\""), "{j}");
        assert_eq!(j.matches("\"match\"").count(), 2, "{j}");
        assert!(j.contains("\"dhcp4\": true"), "the management NIC must lease:\n{j}");
    }

    /// n04. `_get_vlan_iface_name` builds the tagged name from the PARENT's
    /// match.name and raises on a wildcard, so the link must resolve to an
    /// exact name. Photon boots net.ifnames=0, so that name is eth0.
    #[test]
    fn a_vlan_row_links_to_a_non_wildcard_parent_and_stays_static() {
        let n = net("v4-static-vlan100");
        let j = ks_for(&n);
        assert!(j.contains("\"vlans\""), "{j}");
        assert!(j.contains("\"id\": 100"), "the id is an int, not a string:\n{j}");
        assert!(j.contains("\"link\": \"id0\""), "{j}");
        assert!(j.contains("\"name\": \"eth0\""), "a wildcard parent would raise in POI:\n{j}");
        assert!(!j.contains("\"e*\""), "{j}");
        // Static on the tag, deliberately: nothing on vmnet8 answers a tagged
        // frame, so a DHCP tag would never reach `configured` and
        // systemd-networkd-wait-online would fail - regressing the unrelated
        // guest.failed_units assertion.
        assert!(j.contains("192.168.100.78/24"), "{j}");
        assert!(!n.expects_wait_online_failure());
    }

    /// n05. The legacy shape carries the id and nothing else:
    /// `_convert_legacy_config` hardcodes dhcp4 on both the parent and the tag.
    /// That is the entire reason a static tag has to use the v2 schema.
    #[test]
    fn the_legacy_vlan_row_can_carry_only_an_id() {
        let n = net("v4-dhcp-vlan100");
        let j = ks_for(&n);
        assert!(j.contains("\"type\": \"vlan\""), "{j}");
        assert!(j.contains("\"vlan_id\": \"100\""), "the id is a string here:\n{j}");
        // nothing else fits in this shape - no address, no schema version
        assert!(!j.contains("\"version\""), "{j}");
        assert!(!j.contains("\"addresses\""), "{j}");
        assert!(!j.contains("192.168."), "{j}");
        // and this row is the one whose link can never configure
        assert!(n.expects_wait_online_failure());
    }

    /// The v2 rows must never write a hostname inside `network`.
    /// `NetworkManager.set_hostname` would append a SECOND 127.0.0.1 entry to
    /// /etc/hosts on top of the one m_updatehostname.py already writes from the
    /// top-level key.
    #[test]
    fn the_hostname_stays_top_level_and_is_never_duplicated_into_network() {
        for token in ["dual-static-untag", "v6-static-untag", "v4-static-vlan100"] {
            let n = net(token);
            let j = ks_for(&n);
            assert_eq!(j.matches("\"hostname\"").count(), 1, "{token}:\n{j}");
        }
    }

    #[test]
    fn the_only_package_list_on_the_media_is_named() {
        let d = dflt();
        assert_eq!(build(&spec("none", "no", "ext4", &d)).unwrap().packagelist_file, "packages.json");
    }
}
