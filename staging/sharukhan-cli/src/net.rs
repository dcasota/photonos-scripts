//! The network axis: IP family, address assignment, and VLAN tagging.
//!
//! Three dimensions in ONE `permutations.tsv` column, because `matrix.rs`
//! parses positionally with `f.get(N)`: appending one optional field leaves
//! all 36 pre-existing rows untouched and still parsing, while three fields
//! would mean editing every row in a file two agents were writing to.
//! The token is dash-separated so the three dimensions stay legible:
//!
//! ```text
//! net = <family>-<assignment>-<vlan>
//!       family      : v4 | v6 | dual
//!       assignment  : dhcp | static
//!       vlan        : untag | vlanNNN   (NNN in 1..=4094)
//! ```
//!
//! The default, for a row that carries no `net` column at all, is
//! [`DEFAULT`] - which is exactly what every row did before this axis
//! existed. The column DOCUMENTS the status quo rather than changing it, and
//! `kickstart::tests::the_default_net_token_reproduces_the_legacy_dhcp_kickstart`
//! is the guard that keeps it that way.
//!
//! # Why an unknown token is an error
//!
//! `installer.py:567` validates only the TOP-LEVEL keys of a kickstart
//! (`known_keys`, which contains `'network'`); nothing in POI validates
//! anything INSIDE `network`. A misspelt `"dhcp_4"` is silently ignored and
//! produces a guest with no address and no error message anywhere. The
//! harness is therefore the only place a typo in this axis can ever be
//! caught, so [`NetSpec::from_str`] refuses what it does not recognise
//! instead of falling back to the default.

use std::fmt;
use std::str::FromStr;

/// What every row did before this axis existed.
pub const DEFAULT: &str = "v4-dhcp-untag";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Family {
    /// IPv4 only.
    V4,
    /// IPv6 only - no IPv4 address on the interface at all.
    V6,
    /// Both families on one interface.
    Dual,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Assign {
    Dhcp,
    Static,
}

/// Which of POI's two kickstart network schemas a row exercises.
///
/// These are genuinely different code paths, not two spellings of one thing:
/// `NetworkManager.__init__` sniffs the config and runs
/// `_convert_legacy_config` on the legacy shape before the single renderer
/// sees it. The split below is not arbitrary - `Legacy` is exactly the set
/// the curses configurator can produce (`netconfig.py` offers DHCP,
/// DHCP+hostname, manual static, and VLAN, and its `validate_ipaddr` hard-
/// requires four dotted decimal octets), so a `Legacy` row tests the shape a
/// mode=ui install would have written, and a `V2` row tests the shape only a
/// hand-written kickstart can reach.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Schema {
    /// `{"type": "dhcp"|"static"|"vlan", ...}` - IPv4 only, converted to v2
    /// internally by `_convert_legacy_config`.
    Legacy,
    /// `{"version": "2", "ethernets": {...}, "vlans": {...}}` - netplan-style.
    V2,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetSpec {
    pub family: Family,
    pub assign: Assign,
    /// `None` for untagged; `Some(id)` for an 802.1Q sub-interface on top of
    /// the untagged parent. The parent always stays configured: nothing on
    /// vmnet8 answers a tagged frame, so a guest whose ONLY address lived on
    /// the tag would be unreachable and therefore unverifiable.
    pub vlan: Option<u16>,
    /// The token as written in the matrix, for messages and evidence.
    pub token: String,
}

impl Default for NetSpec {
    fn default() -> Self {
        NetSpec::from_str(DEFAULT).expect("the default token must parse")
    }
}

impl fmt::Display for NetSpec {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.token)
    }
}

impl FromStr for NetSpec {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, String> {
        // '-' is the matrix's "this column does not apply" filler, and an
        // absent column arrives here as the default token already.
        let t = if s.trim().is_empty() || s.trim() == "-" { DEFAULT } else { s.trim() };

        let parts: Vec<&str> = t.split('-').collect();
        if parts.len() != 3 {
            return Err(format!(
                "net token '{t}' must be <family>-<assignment>-<vlan>, e.g. '{DEFAULT}'"
            ));
        }

        let family = match parts[0] {
            "v4" => Family::V4,
            "v6" => Family::V6,
            "dual" => Family::Dual,
            other => {
                return Err(format!(
                    "net token '{t}': unknown family '{other}' (want v4, v6 or dual)"
                ))
            }
        };
        let assign = match parts[1] {
            "dhcp" => Assign::Dhcp,
            "static" => Assign::Static,
            other => {
                return Err(format!(
                    "net token '{t}': unknown assignment '{other}' (want dhcp or static)"
                ))
            }
        };
        let vlan = match parts[2] {
            "untag" => None,
            v => {
                let digits = v.strip_prefix("vlan").ok_or_else(|| {
                    format!("net token '{t}': unknown vlan field '{v}' (want untag or vlanNNN)")
                })?;
                let id: u16 = digits.parse().map_err(|_| {
                    format!("net token '{t}': '{digits}' is not a VLAN id")
                })?;
                // The same range write_netdev_file enforces. Catching it here
                // means the run fails in milliseconds rather than hours later
                // inside the installer.
                if !(1..=4094).contains(&id) {
                    return Err(format!(
                        "net token '{t}': VLAN id {id} is outside 1..=4094"
                    ));
                }
                Some(id)
            }
        };

        Ok(NetSpec { family, assign, vlan, token: t.to_string() })
    }
}

impl NetSpec {
    /// True for the token every pre-existing row uses. The one row shape whose
    /// generated kickstart must never change by so much as a byte.
    pub fn is_default(&self) -> bool {
        self.family == Family::V4 && self.assign == Assign::Dhcp && self.vlan.is_none()
    }

    /// Which POI schema this row's kickstart is written in. See [`Schema`].
    ///
    /// Legacy covers precisely what the curses configurator can express;
    /// everything else needs v2. The one v4 combination legacy CANNOT express
    /// is a static address on a VLAN: `_convert_legacy_config` hardcodes
    /// `dhcp4: True` on both the parent and the tag for `type: vlan`, with no
    /// way to say otherwise.
    pub fn schema(&self) -> Schema {
        match (self.family, self.assign, self.vlan) {
            (Family::V4, Assign::Static, Some(_)) => Schema::V2,
            (Family::V4, _, _) => Schema::Legacy,
            _ => Schema::V2,
        }
    }

    /// Whether the guest needs a second NIC purely so the harness can reach it.
    ///
    /// An IPv6-only guest is unreachable from here for three independent
    /// reasons - see `docs`/the matrix notes - so its management path has to be
    /// a separate IPv4 interface. Without one the row could be installed and
    /// never verified, which is worse than not running it.
    pub fn needs_second_nic(&self) -> bool {
        self.family == Family::V6
    }

    /// Why this row cannot run on this host, if it cannot.
    ///
    /// Environmental, not a POI defect. Kept as a reason string rather than a
    /// bool so `plan` can print WHY a row is absent - a year from now the
    /// reason is the only part that is hard to reconstruct.
    pub fn unrunnable_reason(&self) -> Option<&'static str> {
        match (self.family, self.assign) {
            (Family::V6, Assign::Dhcp) | (Family::Dual, Assign::Dhcp) => Some(
                "no DHCPv6 server exists on this host in any configuration: \
                 VMnetDHCP.exe is an IPv4-only ISC 2.0 server and vmnetdhcp.conf \
                 declares only IPv4 subnets",
            ),
            _ => None,
        }
    }

    /// The systemd-networkd link name of the tagged interface, if any.
    /// `_get_vlan_iface_name` builds it as `<parent name>.<id>`, and the parent
    /// is always eth0 (Photon boots with `net.ifnames=0`).
    pub fn vlan_iface(&self) -> Option<String> {
        self.vlan.map(|id| format!("eth0.{id}"))
    }

    /// Whether some managed link on this row can never reach `configured`, and
    /// `systemd-networkd-wait-online.service` will therefore fail.
    ///
    /// `_convert_legacy_config` forces `dhcp4: True` on a legacy VLAN's tagged
    /// interface, and nothing on vmnet8 answers a tagged frame - VMware
    /// Workstation 17 has no VLAN-aware switch at all. There is no kickstart-
    /// level remedy: `networkmanager.py` writes only [Match], [Network],
    /// [NetDev] and [VLAN] sections, so `RequiredForOnline=` is unreachable
    /// from the ks schema. See /root/photon-mc/poi-gap-requiredforonline.md.
    ///
    /// This is ENVIRONMENTAL, not a POI defect - unlike s02, which is a real
    /// one. A reader who cannot tell those apart will eventually fix the wrong
    /// thing, which is why the distinction is stated here and in the matrix.
    pub fn expects_wait_online_failure(&self) -> bool {
        self.schema() == Schema::Legacy && self.vlan.is_some()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_default_token_is_what_every_pre_existing_row_did() {
        let n = NetSpec::default();
        assert!(n.is_default());
        assert_eq!(n.schema(), Schema::Legacy);
        assert_eq!(n.token, "v4-dhcp-untag");
        // an absent column and an explicit '-' must both land on the default
        assert_eq!(NetSpec::from_str("").unwrap(), n);
        assert_eq!(NetSpec::from_str("-").unwrap(), n);
        assert_eq!(NetSpec::from_str("v4-dhcp-untag").unwrap(), n);
    }

    /// The reason this parser exists. POI validates only the top-level keys of
    /// a kickstart, so a typo INSIDE `network` is silently ignored and yields a
    /// guest with no address and no error. This is the only place it can fail
    /// loudly.
    #[test]
    fn an_unknown_token_is_refused_rather_than_defaulted() {
        for bad in [
            "v5-dhcp-untag",
            "v4-dhpc-untag",
            "v4-dhcp-tagged",
            "v4-dhcp",
            "v4-dhcp-untag-extra",
            "v4-static-vlan0",
            "v4-static-vlan4095",
            "v4-static-vlanx",
        ] {
            let e = NetSpec::from_str(bad).unwrap_err();
            assert!(e.contains(bad), "error must quote the token: {e}");
        }
        // and the boundaries themselves are legal
        assert_eq!(NetSpec::from_str("v4-static-vlan1").unwrap().vlan, Some(1));
        assert_eq!(NetSpec::from_str("v4-static-vlan4094").unwrap().vlan, Some(4094));
    }

    /// Legacy is exactly what the curses configurator can produce. The single
    /// v4 combination it cannot reach is a static address on a tag, because
    /// `_convert_legacy_config` hardcodes dhcp4 on both parent and VLAN.
    #[test]
    fn the_schema_split_follows_what_the_installer_ui_can_express() {
        let s = |t: &str| NetSpec::from_str(t).unwrap().schema();
        assert_eq!(s("v4-dhcp-untag"), Schema::Legacy);
        assert_eq!(s("v4-static-untag"), Schema::Legacy);
        assert_eq!(s("v4-dhcp-vlan100"), Schema::Legacy);
        assert_eq!(s("v4-static-vlan100"), Schema::V2);
        assert_eq!(s("dual-static-untag"), Schema::V2);
        assert_eq!(s("v6-static-untag"), Schema::V2);
    }

    #[test]
    fn only_an_ipv6_only_row_needs_a_management_nic() {
        let n = |t: &str| NetSpec::from_str(t).unwrap();
        assert!(n("v6-static-untag").needs_second_nic());
        // dual-stack keeps its IPv4 address, so ssh has a path already
        assert!(!n("dual-static-untag").needs_second_nic());
        assert!(!n("v4-static-untag").needs_second_nic());
    }

    /// The three IPv6 blockers on this host are absolute for DHCPv6: there is
    /// no server to lease from, whatever else is configured. Such a row must
    /// be recorded as unrunnable rather than run and failed, on the c02
    /// precedent.
    #[test]
    fn a_dhcpv6_row_is_unrunnable_and_says_why() {
        let n = |t: &str| NetSpec::from_str(t).unwrap();
        assert!(n("v6-dhcp-untag").unrunnable_reason().is_some());
        assert!(n("dual-dhcp-untag").unrunnable_reason().is_some());
        assert!(n("v6-static-untag").unrunnable_reason().is_none());
        assert!(n("v4-dhcp-untag").unrunnable_reason().is_none());
    }

    /// The wait-online collision, which would otherwise regress the unrelated
    /// guest.failed_units assertion. Only the legacy VLAN row has a link that
    /// can never configure; the v2 VLAN row puts a static address on the tag
    /// precisely so it can.
    #[test]
    fn only_the_legacy_vlan_row_strands_a_link() {
        let n = |t: &str| NetSpec::from_str(t).unwrap();
        assert!(n("v4-dhcp-vlan100").expects_wait_online_failure());
        assert!(!n("v4-static-vlan100").expects_wait_online_failure());
        assert!(!n("v4-dhcp-untag").expects_wait_online_failure());
        assert_eq!(n("v4-dhcp-vlan100").vlan_iface().unwrap(), "eth0.100");
        assert_eq!(n("v4-dhcp-untag").vlan_iface(), None);
    }
}
