//! Paths that come from outside the program: settings in the environment,
//! the temp directory, names read from files.
//!
//! Two failure modes this closes:
//! - a path setting (`MC_WORK=relative/../x`, a `..` component, a newline)
//!   used as given, so a typo or a crafted value lands writes, reads or
//!   removals somewhere else than the setting names;
//! - scratch directories with predictable names in the shared, world-writable
//!   temp directory, made with `remove_dir_all` + `create_dir_all`: another
//!   local user can place a symlink at that name first, and the removal or the
//!   writes then follow it.
//!
//! Every path setting is checked here before use, and every scratch directory
//! is created here: unpredictable name, `create_dir` (never an existing path),
//! mode 0700 from the start, below a temp base that is absolute, a real
//! directory, and sticky when it is world-writable.

use std::fs;
use std::path::{Component, Path, PathBuf};

/// A path value is acceptable as a setting: absolute, no `.` or `..`
/// component, no control character (a newline in a path is never meant).
pub fn check_path(what: &str, p: &Path) -> Result<(), String> {
    let s = p.to_string_lossy();
    if s.is_empty() {
        return Err(format!("{what} is empty"));
    }
    if s.chars().any(|c| c.is_control()) {
        return Err(format!("{what}: {s:?} contains a control character"));
    }
    if !p.is_absolute() {
        return Err(format!("{what}: {s} is not an absolute path"));
    }
    if p.components().any(|c| matches!(c, Component::ParentDir | Component::CurDir)) {
        return Err(format!("{what}: {s} has a . or .. component"));
    }
    Ok(())
}

/// A path setting from the environment: None when unset or empty, the
/// checked path otherwise, an error for a value that is not acceptable.
pub fn env_path(key: &str) -> Result<Option<PathBuf>, String> {
    match std::env::var_os(key) {
        None => Ok(None),
        Some(v) if v.is_empty() => Ok(None),
        Some(v) => {
            let p = PathBuf::from(v);
            check_path(key, &p)?;
            Ok(Some(p))
        }
    }
}

/// A single file name: one normal component, none of `/`, `.`, `..`, no
/// control character, not hidden. For names read from files or arguments
/// that are joined onto a directory.
pub fn check_name(what: &str, name: &str) -> Result<(), String> {
    let ok = !name.is_empty()
        && !name.starts_with('.')
        && !name.contains('/')
        && !name.chars().any(|c| c.is_control())
        && Path::new(name).components().count() == 1
        && matches!(Path::new(name).components().next(), Some(Component::Normal(_)));
    if ok {
        Ok(())
    } else {
        Err(format!("{what}: {name:?} is not a plain file name"))
    }
}

/// The directory scratch directories are made below: the temp directory,
/// checked. A world-writable one must be sticky, so nobody can remove or
/// replace what another user made in it.
pub fn temp_base() -> Result<PathBuf, String> {
    let t = std::env::temp_dir();
    check_path("the temp directory (TMPDIR)", &t)?;
    let real = fs::canonicalize(&t).map_err(|e| format!("the temp directory {}: {e}", t.display()))?;
    let md = fs::metadata(&real).map_err(|e| format!("{}: {e}", real.display()))?;
    if !md.is_dir() {
        return Err(format!("the temp directory {} is not a directory", real.display()));
    }
    use std::os::unix::fs::PermissionsExt;
    let mode = md.permissions().mode();
    if mode & 0o002 != 0 && mode & 0o1000 == 0 {
        return Err(format!("the temp directory {} is world-writable without the sticky bit", real.display()));
    }
    Ok(real)
}

/// 16 hex digits from the kernel's random source.
fn nonce() -> Result<String, String> {
    use std::io::Read;
    let mut b = [0u8; 8];
    fs::File::open("/dev/urandom").and_then(|mut f| f.read_exact(&mut b)).map_err(|e| format!("/dev/urandom: {e}"))?;
    Ok(b.iter().map(|x| format!("{x:02x}")).collect())
}

/// A new directory below `base`, named `<prefix>-<random>`, created with
/// `create_dir` (an existing path, a symlink included, is refused, never
/// reused) and mode 0700 from the start.
pub fn private_dir_in(base: &Path, prefix: &str) -> Result<PathBuf, String> {
    // a leading dot is allowed (a hidden work directory beside an output); the
    // rest is the plain-name rule
    check_name("a scratch prefix", prefix.strip_prefix('.').unwrap_or(prefix))?;
    use std::os::unix::fs::DirBuilderExt;
    for _ in 0..8 {
        let p = base.join(format!("{prefix}-{}", nonce()?));
        match fs::DirBuilder::new().mode(0o700).create(&p) {
            Ok(()) => return Ok(p),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(format!("{}: {e}", p.display())),
        }
    }
    Err(format!("no free scratch name below {}", base.display()))
}

/// A private scratch directory in the checked temp directory. The caller
/// removes it when done; it holds nothing another user can reach.
pub fn private_tmp(prefix: &str) -> Result<PathBuf, String> {
    private_dir_in(&temp_base()?, prefix)
}

/// The base for test scratch directories: one private directory per test
/// process below the test binary's own target directory - never the shared
/// temp directory, never a path from the environment.
#[cfg(test)]
pub fn test_base() -> PathBuf {
    static BASE: std::sync::OnceLock<PathBuf> = std::sync::OnceLock::new();
    BASE.get_or_init(|| {
        let exe = std::env::current_exe().expect("the test binary's path");
        // target/<profile>/deps/<binary>
        let target = exe.parent().and_then(|d| d.parent()).expect("target/<profile>").to_path_buf();
        let root = target.join("test-scratch");
        fs::create_dir_all(&root).expect("target/<profile>/test-scratch");
        private_dir_in(&root, &format!("run{}", std::process::id())).expect("a private test directory")
    })
    .clone()
}

/// A path a test puts into shell text it did not write itself (inside quotes
/// of a script it then runs): only characters no shell gives a meaning to, so
/// the text runs as written. Panics otherwise; the test base always passes.
#[cfg(test)]
pub fn shell_safe(p: &Path) -> String {
    let s = p.to_string_lossy().into_owned();
    assert!(
        !s.is_empty() && s.bytes().all(|b| b.is_ascii_alphanumeric() || b"/._-+".contains(&b)),
        "{s:?} has characters a shell would interpret"
    );
    s
}

/// Single-quote `s` for a POSIX shell, for the tests that run a shell
/// snippet of sharukhan's own against a path.
#[cfg(test)]
pub fn sh_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_path_setting_must_be_absolute_and_plain() {
        assert!(check_path("X", Path::new("/root/photon-mc/work")).is_ok());
        assert!(check_path("X", Path::new("relative/work")).unwrap_err().contains("not an absolute path"));
        assert!(check_path("X", Path::new("/root/../etc")).unwrap_err().contains(".."));
        assert!(check_path("X", Path::new("/root/./x")).is_ok(), "Path normalizes a ./ inside: components() drops it");
        assert!(check_path("X", Path::new("/root/a\nb")).unwrap_err().contains("control"));
        assert!(check_path("X", Path::new("")).unwrap_err().contains("empty"));
    }

    #[test]
    fn a_name_is_one_plain_component() {
        for ok in ["signers.toml", "262.2.toml", "a-b_c"] {
            assert!(check_name("n", ok).is_ok(), "{ok}");
        }
        for bad in ["", ".", "..", "../x", "a/b", "/abs", ".hidden", "a\nb"] {
            assert!(check_name("n", bad).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn a_private_dir_is_new_unpredictable_and_0700() {
        use std::os::unix::fs::PermissionsExt;
        let base = test_base();
        let a = private_dir_in(&base, "t").unwrap();
        let b = private_dir_in(&base, "t").unwrap();
        assert_ne!(a, b);
        assert_eq!(fs::metadata(&a).unwrap().permissions().mode() & 0o777, 0o700);
        let n = a.file_name().unwrap().to_string_lossy().into_owned();
        assert!(n.starts_with("t-") && n.len() == 2 + 16, "{n}");
        assert!(private_dir_in(&base, "../escape").is_err());
        assert!(private_dir_in(&base, "..").is_err());
        let h = private_dir_in(&base, ".hidden").unwrap();
        assert!(h.file_name().unwrap().to_string_lossy().starts_with(".hidden-"));
        fs::remove_dir(&h).unwrap();
        fs::remove_dir(&a).unwrap();
        fs::remove_dir(&b).unwrap();
    }

    #[test]
    fn the_test_base_is_private_and_outside_the_shared_temp_directory() {
        use std::os::unix::fs::PermissionsExt;
        let b = test_base();
        assert!(b.components().any(|c| c.as_os_str() == "test-scratch"), "{}", b.display());
        assert!(!b.starts_with(std::env::temp_dir()) || std::env::temp_dir().starts_with(b.parent().unwrap()));
        assert_eq!(fs::metadata(&b).unwrap().permissions().mode() & 0o777, 0o700);
    }

    #[test]
    #[should_panic(expected = "a shell would interpret")]
    fn a_path_with_shell_syntax_is_refused_before_it_reaches_a_script() {
        shell_safe(Path::new("/tmp/$(id)"));
    }

    #[test]
    fn the_test_base_is_shell_safe() {
        shell_safe(&test_base());
    }

    #[test]
    fn shell_quoting_survives_quotes_and_metacharacters() {
        let s = "/a b/'$(rm -rf x)';`id`";
        let out = std::process::Command::new("sh").args(["-c", &format!("printf %s {}", sh_quote(s))]).output().unwrap();
        assert_eq!(String::from_utf8(out.stdout).unwrap(), s);
    }
}
