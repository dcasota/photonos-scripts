//! Deterministic per-permutation MAC, UUID and IP.
//!
//! Ported from lib/common.sh:115-127.
//!
//! VMware's manual-assignment OUI is 00:50:56:00:00:00-00:50:56:3F:FF:FF;
//! staying inside it means the address is ours and is never derived from the
//! UUID.
//!
//! The index is the permutation's ORDINAL in permutations.tsv, never a hash of
//! its id. A cksum-based index collided on this very matrix - k04/k16 and
//! k09/s02 shared an index, and therefore a MAC, a UUID and an IP - and could
//! reach .240, inside VMnet8's DHCP range of .128-.254. An ordinal is unique by
//! construction and stays bounded, so the addresses can never collide with a
//! lease or with each other.

/// The matrix would have to exceed this many rows before `MC_IP_BASE + index`
/// reached the DHCP floor at .128. The bash carried the same guard and no test;
/// the boundary is exercised below.
pub const MAX_INDEX: usize = 80;

#[derive(Debug, PartialEq, Eq)]
pub enum IdentityError {
    /// The id is not a row in permutations.tsv. Asking for a row that does not
    /// exist must never look like a clean run.
    NotInMatrix(String),
    /// The ordinal would push the static address into the DHCP range, where it
    /// could collide with a lease handed out by VMnet8.
    WouldReachDhcpRange(usize),
}

impl std::fmt::Display for IdentityError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            IdentityError::NotInMatrix(id) => {
                write!(f, "permutation '{id}' is not in the matrix")
            }
            IdentityError::WouldReachDhcpRange(n) => write!(
                f,
                "permutation ordinal {n} would push the IP into the DHCP range (max {MAX_INDEX})"
            ),
        }
    }
}

/// 1-based ordinal of `id` among the non-blank, non-comment rows of
/// permutations.tsv.
///
/// Takes the file CONTENTS rather than a path so the numbering is testable
/// without a filesystem: the ordinal is the whole identity, and getting it
/// wrong hands two permutations the same MAC.
pub fn perm_index(tsv: &str, id: &str) -> Result<usize, IdentityError> {
    let mut n = 0usize;
    for line in tsv.lines() {
        let t = line.trim();
        if t.is_empty() || t.starts_with('#') {
            continue;
        }
        n += 1;
        if t.split_whitespace().next() == Some(id) {
            if n > MAX_INDEX {
                return Err(IdentityError::WouldReachDhcpRange(n));
            }
            return Ok(n);
        }
    }
    Err(IdentityError::NotInMatrix(id.to_string()))
}

/// `00:50:56:3a:%02x:%02x` of (index / 256, index % 256).
pub fn mac_for(index: usize) -> String {
    format!("00:50:56:3a:{:02x}:{:02x}", index / 256, index % 256)
}

/// The VMX `uuid.bios` form: sixteen bytes, space-separated, with a dash
/// before the last six. Only uuid.bios is ever pinned - uuid.location is
/// VMware's own and is rewritten on first power-on.
pub fn uuid_for(index: usize) -> String {
    format!(
        "56 4d 6d 63 00 00 00 00-00 00 00 00 00 00 {:02x} {:02x}",
        index / 256,
        index % 256
    )
}

/// `${MC_NET_PREFIX}.${MC_IP_BASE + index}`, i.e. .41 upward with the shipped
/// base of 40. Below VMnet8's DHCP floor by construction.
pub fn ip_for(net_prefix: &str, ip_base: usize, index: usize) -> String {
    format!("{net_prefix}.{}", ip_base + index)
}

/// The IPv6 counterpart, on the same ordinal so a guest's two addresses share
/// one number and a human can read them as the same machine.
///
/// ALWAYS a ULA (fd00::/8), never a global prefix. This host has no IPv6
/// router and no DHCPv6 server of any kind, so a global address here would be
/// claiming reachability that does not exist - and would be routable off-host
/// if the environment ever changed underneath it. A ULA cannot be.
pub fn ip6_for(v6_prefix: &str, ip_base: usize, index: usize) -> String {
    format!("{v6_prefix}::{:x}", ip_base + index)
}

/// The second NIC's MAC, for the rows that need a management interface.
///
/// A distinct fourth octet rather than a distinct ordinal, so the two NICs of
/// one VM stay recognisably the same machine and neither can ever collide with
/// the primary space. Still inside VMware's manual-assignment OUI,
/// 00:50:56:00:00:00-00:50:56:3F:FF:FF.
pub fn mac2_for(index: usize) -> String {
    format!("00:50:56:3b:{:02x}:{:02x}", index / 256, index % 256)
}

#[cfg(test)]
mod tests {
    use super::*;

    const TSV: &str = "\
# a comment
#id      iso_type
p01      minimal
p02      minimal

k01      minimal
s02      minimal
";

    #[test]
    fn ordinal_skips_blank_and_comment_lines() {
        assert_eq!(perm_index(TSV, "p01"), Ok(1));
        assert_eq!(perm_index(TSV, "p02"), Ok(2));
        assert_eq!(perm_index(TSV, "k01"), Ok(3));
        assert_eq!(perm_index(TSV, "s02"), Ok(4));
    }

    #[test]
    fn unknown_id_is_an_error_not_a_zero() {
        assert_eq!(
            perm_index(TSV, "zz9"),
            Err(IdentityError::NotInMatrix("zz9".into()))
        );
    }

    /// The guard the bash carried untested: 80 is allowed, 81 is refused,
    /// because MC_IP_BASE + 81 = .121 is one row from the .128 DHCP floor
    /// and every row after it is inside the range.
    #[test]
    fn dhcp_boundary() {
        let rows: String = (1..=81).map(|i| format!("row{i}\tminimal\n")).collect();
        assert_eq!(perm_index(&rows, "row80"), Ok(80));
        assert_eq!(
            perm_index(&rows, "row81"),
            Err(IdentityError::WouldReachDhcpRange(81))
        );
    }

    #[test]
    fn mac_and_uuid_split_on_256() {
        assert_eq!(mac_for(1), "00:50:56:3a:00:01");
        assert_eq!(mac_for(80), "00:50:56:3a:00:50");
        // Beyond the matrix guard, but the arithmetic is the point: the high
        // byte must carry, not wrap into the low one.
        assert_eq!(mac_for(256), "00:50:56:3a:01:00");
        assert_eq!(mac_for(300), "00:50:56:3a:01:2c");
        assert_eq!(
            uuid_for(1),
            "56 4d 6d 63 00 00 00 00-00 00 00 00 00 00 00 01"
        );
        assert_eq!(
            uuid_for(300),
            "56 4d 6d 63 00 00 00 00-00 00 00 00 00 00 01 2c"
        );
    }

    #[test]
    fn ip_is_base_plus_ordinal() {
        assert_eq!(ip_for("192.168.225", 40, 1), "192.168.225.41");
        assert_eq!(ip_for("192.168.225", 40, 80), "192.168.225.120");
    }

    /// The two families share one ordinal, and the v6 side is hex because that
    /// is how an IPv6 address is written - .77 and ::4d are the same machine.
    #[test]
    fn the_v6_address_shares_the_ordinal_and_stays_a_ula() {
        assert_eq!(ip6_for("fd00:225", 40, 1), "fd00:225::29");
        assert_eq!(ip6_for("fd00:225", 40, 37), "fd00:225::4d");
        // fd00::/8 is unique-local. A global prefix here would claim a route
        // this host has no router for.
        assert!(ip6_for("fd00:225", 40, 1).starts_with("fd"));
    }

    /// The management NIC can never collide with the primary one, on any row.
    #[test]
    fn the_second_nic_has_its_own_address_space() {
        for i in 1..=MAX_INDEX {
            assert_ne!(mac_for(i), mac2_for(i));
        }
        assert_eq!(mac2_for(1), "00:50:56:3b:00:01");
        // still inside VMware's manual OUI: the fourth octet must stay <= 0x3f
        assert!(u8::from_str_radix(&mac2_for(1)[9..11], 16).unwrap() <= 0x3f);
    }

    /// Every id in the shipped matrix must have a distinct address. This is the
    /// collision the cksum index produced.
    #[test]
    fn shipped_matrix_has_no_collisions() {
        let tsv = include_str!("../../mission-control/config/permutations.tsv");
        let mut macs = Vec::new();
        for line in tsv.lines() {
            let t = line.trim();
            if t.is_empty() || t.starts_with('#') {
                continue;
            }
            let id = t.split_whitespace().next().unwrap();
            let i = perm_index(tsv, id).expect("every shipped row must have an ordinal");
            macs.push(mac_for(i));
        }
        let mut sorted = macs.clone();
        sorted.sort();
        sorted.dedup();
        assert_eq!(sorted.len(), macs.len(), "two rows share a MAC");
    }
}
