//! The package source: the row's own ISO, reconnected to the installed guest.
//!
//! Why this and nothing else (ADR-0008): the guest was installed from exactly
//! this medium, the VMX still names it on `sata0:1` (install only lets the
//! installer eject it), and it carries `/RPMS/repodata`. Reconnecting it makes
//! the repository the media under test BY CONSTRUCTION - no copy that could be
//! stale, no network repository that would test somebody else's build.
//!
//! "By construction" is still verified, three ways, before anything installs:
//! the VMX device must name this row's ISO; the medium the guest mounts must
//! carry the ISO's volume id; and the repository tdnf reads must list exactly
//! the RPM files the ISO holds.

use crate::guest::run_command_bounded;
use std::path::Path;
use std::process::Command;
use std::time::Duration;

/// The CD device the VMX template attaches the ISO to (src/vmx.rs).
pub const CDROM_DEVICE: &str = "sata0:1";

/// `sata0:1.fileName = "C:\...\x.iso"` from a VMX.
pub fn vmx_iso(vmx_text: &str) -> Option<String> {
    let key = format!("{CDROM_DEVICE}.fileName");
    vmx_text.lines().find_map(|l| {
        let (k, v) = l.split_once('=')?;
        (k.trim() == key).then(|| v.trim().trim_matches('"').to_string())
    })
}

/// Windows paths compare case-insensitively and with either separator.
pub fn same_windows_path(a: &str, b: &str) -> bool {
    let norm = |s: &str| s.replace('/', "\\").to_lowercase();
    norm(a) == norm(b)
}

/// The ISO's volume id, from `xorriso -pvd_info`.
pub fn volume_id(iso: &Path) -> Result<String, String> {
    let mut c = Command::new("xorriso");
    c.args(["-indev"]).arg(iso).arg("-pvd_info");
    let out = run_command_bounded(c, None, Duration::from_secs(120));
    parse_volume_id(&format!("{}\n{}", out.stdout, out.stderr)).ok_or_else(|| {
        format!(
            "xorriso printed no Volume Id for {} (exit {:?})",
            iso.display(),
            out.code
        )
    })
}

pub fn parse_volume_id(text: &str) -> Option<String> {
    text.lines().find_map(|l| {
        let (k, v) = l.split_once(':')?;
        let v = v.trim().trim_matches('\'');
        (k.trim() == "Volume Id" && !v.is_empty()).then(|| v.to_string())
    })
}

/// A volume id as it may be compared with blkid's LABEL and put on a command
/// line: ISO 9660 d-characters.
pub fn valid_volume_id(v: &str) -> bool {
    !v.is_empty()
        && v.len() <= 32
        && v.chars()
            .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_')
}

/// vmrun connect/disconnectNamedDevice on OUR VM only. vmrun's exit code is
/// not evidence (see vmware.rs); the caller proves the effect in the guest.
pub fn named_device(vmrun: &Path, vmx_win: &str, connect: bool) -> (Option<i32>, String) {
    let verb = if connect {
        "connectNamedDevice"
    } else {
        "disconnectNamedDevice"
    };
    let mut c = Command::new(vmrun);
    c.args(["-T", "ws", verb, vmx_win, CDROM_DEVICE]);
    let out = run_command_bounded(c, None, Duration::from_secs(90));
    (
        out.code,
        format!("{}{}", out.stdout, out.stderr)
            .replace('\r', "")
            .trim()
            .to_string(),
    )
}

/// The RPM file name tdnf's name/evr/arch corresponds to on the media.
pub fn rpm_file_name(name: &str, evr: &str, arch: &str) -> String {
    // The file name never carries the epoch.
    let vr = evr.split_once(':').map(|(_, r)| r).unwrap_or(evr);
    format!("{name}-{vr}.{arch}.rpm")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_vmx_names_the_iso_on_the_cd_device() {
        let vmx = "sata0:0.fileName = \"mc-k09.vmdk\"\nsata0:1.present = \"TRUE\"\n\
                   sata0:1.fileName = \"C:\\Users\\x\\photon.iso\"\nsata0:1.startConnected = \"TRUE\"\n";
        assert_eq!(vmx_iso(vmx).as_deref(), Some("C:\\Users\\x\\photon.iso"));
        assert_eq!(vmx_iso("sata0:10.fileName = \"x\"\n"), None);
        assert!(same_windows_path(
            "C:\\Users\\X\\Photon.iso",
            "c:/users/x/photon.iso"
        ));
        assert!(!same_windows_path("C:\\a.iso", "C:\\b.iso"));
    }

    #[test]
    fn volume_ids() {
        let pvd = "xorriso 1.5.6 : RockRidge filesystem manipulator\nVolume Id    : PHOTON_20260927\nVolume Set Id: \n";
        assert_eq!(parse_volume_id(pvd).as_deref(), Some("PHOTON_20260927"));
        assert_eq!(parse_volume_id("Volume Id    : \n"), None);
        assert_eq!(parse_volume_id(""), None);
        assert!(valid_volume_id("PHOTON_20260927"));
        assert!(!valid_volume_id("photon"));
        assert!(!valid_volume_id("A B"));
        assert!(!valid_volume_id(""));
    }

    #[test]
    fn rpm_file_names_drop_the_epoch() {
        assert_eq!(
            rpm_file_name("chrony", "4.3-3.ph5", "x86_64"),
            "chrony-4.3-3.ph5.x86_64.rpm"
        );
        assert_eq!(
            rpm_file_name("perl", "4:5.40-1.ph5", "x86_64"),
            "perl-5.40-1.ph5.x86_64.rpm"
        );
    }

    #[test]
    fn a_missing_iso_is_an_error_naming_it() {
        let e = volume_id(Path::new("/nonexistent/sharukhan.iso")).unwrap_err();
        assert!(e.contains("sharukhan.iso"), "{e}");
    }
}
