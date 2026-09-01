//! The operator card. Ported from mc-operator-card.sh.
//!
//! Generated from permutations.tsv, never hand-written, so the instructions
//! cannot drift from the matrix they are supposed to exercise. A mode=ui row
//! exists precisely because the STIG menu lives only in the curses
//! configurator: no kickstart can answer it, so a human has to, and what they
//! type is part of the experiment.

use crate::matrix::Permutation;

/// `password` is passed in rather than read here, so the one place that
/// decides a missing MC_GUEST_PASSWORD is fatal stays in
/// [`crate::config::Config::guest_password`].
pub fn render(p: &Permutation, vm: &str, index: usize, ip: &str, password: &str) -> String {
    let stig_line = if p.stig == "yes" {
        "YES  <-- the axis under test"
    } else {
        "NO"
    };
    format!(
        "PERMUTATION {id}   (ISO {iso} / installer {poi} / STIG {stig} / {fs} / interactive)

  VM name       : {vm}   (matrix ordinal {index}, reserved address {ip})
  Console       : VMware Workstation -> {vm}
  Matrix says   : {doc}        Expected with the PRs: {expect}

  ENTER IN THE INSTALLER
    1. License                 accept
    2. Disk                    /dev/sda  ->  choose CUSTOM partitioning
                               (auto-partition always makes ext4, so a
                                filesystem row can only be reached by hand)
       /boot/efi   512 MB  vfat
       /boot      1024 MB  ext4
       /             rest  {fs}      <-- the axis under test
    3. Hostname                {vm}
    4. Root password           {password}
    5. \"Apply STIG hardening\"  {stig_line}
       (this menu is the reason {id} cannot be automated: it exists only in
        the curses configurator, so no kickstart can answer it)
    6. Let it install and reboot on its own.

  Then: sharukhan verify --id {id}
",
        id = p.id,
        iso = p.iso_type,
        poi = p.poi,
        stig = p.stig,
        fs = p.fs,
        doc = p.doc,
        expect = p.expect,
        vm = vm,
        index = index,
        ip = ip,
        password = password,
        stig_line = stig_line,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(stig: &str, fs: &str) -> Permutation {
        Permutation {
            id: "p04".into(),
            iso_type: "minimal".into(),
            poi: "2.8".into(),
            stig: stig.into(),
            fs: fs.into(),
            mode: "ui".into(),
            variant: "-".into(),
            doc: "fails".into(),
            expect: "pass".into(),
            canister: "prebuilt".into(),
        }
    }

    /// The card is the experiment. If the filesystem or the STIG answer it
    /// tells the operator to choose does not come from the row, the run tests
    /// something other than the row.
    #[test]
    fn the_axes_come_from_the_row() {
        let t = render(&row("yes", "btrfs"), "mc-p04", 4, "192.168.225.44", "pw");
        assert!(t.contains("/             rest  btrfs"));
        assert!(t.contains("\"Apply STIG hardening\"  YES"));
        let t = render(&row("no", "ext4"), "mc-p04", 4, "192.168.225.44", "pw");
        assert!(t.contains("/             rest  ext4"));
        assert!(t.contains("\"Apply STIG hardening\"  NO"));
        assert!(!t.contains("the axis under test\n       (this menu"));
    }

    #[test]
    fn the_operator_is_told_the_password_that_was_actually_configured() {
        let t = render(&row("no", "ext4"), "mc-p04", 4, "192.168.225.44", "from-the-env");
        assert!(t.contains("Root password           from-the-env"));
    }

    #[test]
    fn doc_and_expect_are_both_shown_because_their_difference_is_the_point() {
        let t = render(&row("no", "ext4"), "mc-p04", 4, "192.168.225.44", "pw");
        assert!(t.contains("Matrix says   : fails"));
        assert!(t.contains("Expected with the PRs: pass"));
    }
}
