//! Secret files: one value per file, owned by the user that reads it, mode
//! 0600, in a directory of mode 0700. A value is read and written without
//! reaching an argv, a log or an error message; errors name the file only.
//!
//! The owner rule is "the reading user", not "root", so that the services
//! (root) and the tests (whoever runs them) apply the same check.

use std::fs;
use std::io::Write;
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::Path;

/// The effective uid of this process, from /proc (no libc in this crate).
fn euid() -> Result<u32, String> {
    fs::metadata("/proc/self").map(|m| m.uid()).map_err(|e| format!("/proc/self: {e}"))
}

/// Why `p` is not a secret file this process may trust, if it is not.
pub fn check(p: &Path) -> Result<(), String> {
    let me = euid()?;
    let m = fs::symlink_metadata(p).map_err(|e| format!("{}: {e}", p.display()))?;
    if !m.file_type().is_file() {
        return Err(format!("{}: not a regular file", p.display()));
    }
    if m.uid() != me || m.mode() & 0o077 != 0 {
        return Err(format!("{}: must be owned by uid {me} with mode 0600 (is uid {} mode {:o})", p.display(), m.uid(), m.mode() & 0o777));
    }
    if let Some(d) = p.parent() {
        let dm = fs::metadata(d).map_err(|e| format!("{}: {e}", d.display()))?;
        if dm.uid() != me || dm.mode() & 0o022 != 0 {
            return Err(format!("{}: its directory must be owned by uid {me} and writable by nobody else", p.display()));
        }
    }
    Ok(())
}

/// The value of a secret file, trimmed; checked first.
pub fn read(p: &Path) -> Result<String, String> {
    check(p)?;
    let v = fs::read_to_string(p).map_err(|e| format!("{}: {e}", p.display()))?.trim().to_string();
    if v.is_empty() {
        return Err(format!("{}: empty", p.display()));
    }
    Ok(v)
}

/// Write `value` to `p` atomically: a new 0600 file beside it, synced, then
/// renamed over it. The directory is created 0700 if missing.
pub fn write(p: &Path, value: &str) -> Result<(), String> {
    if value.trim().is_empty() || value.contains('\n') {
        return Err(format!("{}: a secret is one non-empty line", p.display()));
    }
    let dir = p.parent().ok_or_else(|| format!("{}: no directory", p.display()))?;
    if !dir.exists() {
        fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        fs::set_permissions(dir, fs::Permissions::from_mode(0o700)).map_err(|e| format!("{}: {e}", dir.display()))?;
    }
    let me = euid()?;
    let dm = fs::symlink_metadata(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    if !dm.file_type().is_dir() || dm.uid() != me || dm.mode() & 0o077 != 0 {
        return Err(format!("{}: must be a directory owned by uid {me} with mode 0700", dir.display()));
    }
    let name = p.file_name().and_then(|n| n.to_str()).ok_or_else(|| format!("{}: no file name", p.display()))?;
    let tmp = dir.join(format!(".{name}.{}.tmp", std::process::id()));
    let _ = fs::remove_file(&tmp);
    let mut f = fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&tmp).map_err(|e| format!("{}: {e}", tmp.display()))?;
    let done = f.write_all(format!("{value}\n").as_bytes()).and_then(|_| f.sync_all());
    drop(f);
    if let Err(e) = done {
        let _ = fs::remove_file(&tmp);
        return Err(format!("{}: {e}", tmp.display()));
    }
    fs::rename(&tmp, p).map_err(|e| {
        let _ = fs::remove_file(&tmp);
        format!("{}: {e}", p.display())
    })?;
    check(p)
}

/// Present and trustworthy, missing, or why not: for status lines.
pub fn describe(p: &Path) -> String {
    if fs::symlink_metadata(p).is_err() {
        return format!("{} missing", p.display());
    }
    match check(p) {
        Ok(()) => format!("{} present (0600)", p.display()),
        Err(e) => e,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_secret_is_written_private_and_read_back_checked() {
        let d = std::env::temp_dir().join(format!("shk-secret-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        let p = d.join("s").join("key");
        write(&p, "value-1").unwrap();
        assert_eq!(fs::metadata(&p).unwrap().mode() & 0o777, 0o600);
        assert_eq!(fs::metadata(p.parent().unwrap()).unwrap().mode() & 0o777, 0o700);
        assert_eq!(read(&p).unwrap(), "value-1");
        write(&p, "value-2").unwrap();
        assert_eq!(read(&p).unwrap(), "value-2", "an update replaces it");
        assert!(write(&p, "two\nlines").is_err());
        fs::set_permissions(&p, fs::Permissions::from_mode(0o644)).unwrap();
        let e = read(&p).unwrap_err();
        assert!(e.contains("mode 0600") && !e.contains("value-2"), "{e}");
        assert!(describe(&d.join("s/none")).ends_with("missing"));
        let _ = fs::remove_dir_all(&d);
    }
}
