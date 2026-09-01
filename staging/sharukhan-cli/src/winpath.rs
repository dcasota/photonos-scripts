//! WSL path -> Windows path.
//!
//! vmrun.exe and vmware-vdiskmanager.exe are Windows binaries: they are handed
//! `C:\photon-mc\vm\...`, never `/mnt/c/...`.
//!
//! The bash form used `tr`, not sed's `\U`, because /usr/bin/sed on this host
//! is toybox in a non-interactive shell and emits a literal "U" for that GNU
//! extension. Irrelevant in Rust - `to_ascii_uppercase` is not a sed dialect -
//! but the note stays because the next person to reach for `sed -E 's/\U…'`
//! anywhere in this project will hit it again.

/// A path VMware cannot see.
///
/// Without this guard an ISO at /root/... reaches the VMX as the nonsense
/// value "\root\...", and vmrun reports only "Error: The operation was
/// canceled" - which says nothing at all about the cause. A \\wsl$\ UNC path
/// is no better: it yields "DISKUTIL: sata0:1 capacity=0".
#[derive(Debug, PartialEq, Eq)]
pub struct NotWindowsVisible {
    pub path: String,
}

impl std::fmt::Display for NotWindowsVisible {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{} is not on a Windows-visible volume. VMware runs on Windows and cannot read a \
             WSL path; put it under /mnt/<drive>/.",
            self.path
        )
    }
}

/// `/mnt/c/foo/bar` -> `C:\foo\bar`. Anything else is converted
/// slash-for-backslash, which is what the bash did and is only ever useful for
/// display - see [`win_path_checked`] for the form that refuses.
pub fn win_path(p: &str) -> String {
    match drive_of(p) {
        Some((drive, rest)) => format!("{}:{}", drive, rest.replace('/', "\\")),
        None => p.replace('/', "\\"),
    }
}

/// The same conversion, but a path VMware cannot see is a typed error rather
/// than a plausible-looking string.
pub fn win_path_checked(p: &str) -> Result<String, NotWindowsVisible> {
    match drive_of(p) {
        Some((drive, rest)) => Ok(format!("{}:{}", drive, rest.replace('/', "\\"))),
        None => Err(NotWindowsVisible { path: p.to_string() }),
    }
}

/// Splits `/mnt/c/foo` into ('C', "/foo"). A bare `/mnt/c` with nothing after
/// it is not a mount VMware can be pointed at, so it does not match - the bash
/// pattern `/mnt/?/*` required the trailing component too.
fn drive_of(p: &str) -> Option<(char, &str)> {
    let rest = p.strip_prefix("/mnt/")?;
    let mut chars = rest.chars();
    let drive = chars.next()?;
    if !drive.is_ascii_alphabetic() {
        return None;
    }
    let after = &rest[drive.len_utf8()..];
    if !after.starts_with('/') || after.len() < 2 {
        return None;
    }
    Some((drive.to_ascii_uppercase(), after))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mnt_drive_becomes_a_windows_path() {
        assert_eq!(win_path("/mnt/c/foo/bar"), "C:\\foo\\bar");
        assert_eq!(win_path("/mnt/c/photon-mc/vm/mc-k01/mc-k01.vmx"),
                   "C:\\photon-mc\\vm\\mc-k01\\mc-k01.vmx");
        assert_eq!(win_path("/mnt/d/x"), "D:\\x");
    }

    #[test]
    fn a_wsl_path_is_refused_not_mangled() {
        let e = win_path_checked("/root/photon-mc/iso-cache/photon.iso").unwrap_err();
        assert_eq!(e.path, "/root/photon-mc/iso-cache/photon.iso");
        // The bash produced this string and handed it to VMware, which then
        // failed with a message naming nothing.
        assert_eq!(win_path("/root/x.iso"), "\\root\\x.iso");
    }

    #[test]
    fn a_bare_mount_point_is_not_a_file_vmware_can_open() {
        assert!(win_path_checked("/mnt/c").is_err());
        assert!(win_path_checked("/mnt/c/").is_err());
        assert!(win_path_checked("/mnt/").is_err());
    }

    #[test]
    fn checked_and_unchecked_agree_where_both_succeed() {
        for p in ["/mnt/c/a/b", "/mnt/e/one/two/three.iso"] {
            assert_eq!(win_path(p), win_path_checked(p).unwrap());
        }
    }
}
