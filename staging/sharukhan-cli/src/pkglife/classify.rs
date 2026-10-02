//! What a package IS, decided from what it installs - never from its name.
//!
//! The file list comes from the RPM header (before install) and from the rpm
//! database (after install); the classes follow from paths and modes alone:
//!
//! | class     | evidence                                                        |
//! |-----------|-----------------------------------------------------------------|
//! | daemon    | a unit file directly in a system unit directory                 |
//! | cli       | an executable (or a symlink) directly in /usr/bin, /usr/sbin, /bin, /sbin |
//! | library   | a `lib*.so.*` directly in /usr/lib, /usr/lib64, /lib, /lib64    |
//! | data      | none of the above: headers, documentation, data files           |
//!
//! A package can be several at once (chrony is daemon and cli); each class
//! brings its own tests.

use crate::pkglife::parse::FileEntry;
use crate::pkglife::remote::valid_unit_name;

pub const UNIT_DIRS: [&str; 3] = [
    "/usr/lib/systemd/system",
    "/lib/systemd/system",
    "/etc/systemd/system",
];
pub const USER_UNIT_DIRS: [&str; 2] = ["/usr/lib/systemd/user", "/etc/systemd/user"];
pub const BIN_DIRS: [&str; 4] = ["/usr/bin", "/usr/sbin", "/bin", "/sbin"];
pub const LIB_DIRS: [&str; 4] = ["/usr/lib", "/usr/lib64", "/lib", "/lib64"];

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct UnitFile {
    pub name: String,
    pub path: String,
    /// A symlink in a unit directory is another NAME for a unit, not a unit
    /// of its own; it is recorded, not started twice.
    pub alias: bool,
}

impl UnitFile {
    pub fn kind(&self) -> &str {
        self.name.rsplit('.').next().unwrap_or("")
    }
}

#[derive(Clone, Debug, Default)]
pub struct Classified {
    pub units: Vec<UnitFile>,
    pub user_units: Vec<String>,
    pub executables: Vec<String>,
    pub libraries: Vec<FileEntry>,
    pub boot_files: Vec<String>,
}

impl Classified {
    pub fn classes(&self) -> Vec<&'static str> {
        let mut c = Vec::new();
        if self.units.iter().any(|u| !u.alias) {
            c.push("daemon");
        }
        if !self.executables.is_empty() {
            c.push("cli");
        }
        if !self.libraries.is_empty() {
            c.push("library");
        }
        if c.is_empty() {
            c.push("data");
        }
        c
    }
}

fn is_shared_library(name: &str) -> bool {
    name.starts_with("lib") && name.contains(".so.")
}

pub fn classify(files: &[FileEntry], is_boot_path: impl Fn(&str) -> bool) -> Classified {
    let mut c = Classified::default();
    for f in files {
        if f.is_ghost() {
            // %ghost: owned but not shipped - it may not exist, and it is not
            // what the package delivers.
            continue;
        }
        if is_boot_path(&f.path) && !f.is_dir() {
            c.boot_files.push(f.path.clone());
        }
        let dir = f.dir();
        if UNIT_DIRS.contains(&dir) && (f.is_reg() || f.is_link()) && valid_unit_name(f.name()) {
            c.units.push(UnitFile {
                name: f.name().to_string(),
                path: f.path.clone(),
                alias: f.is_link(),
            });
        } else if USER_UNIT_DIRS.contains(&dir) && valid_unit_name(f.name()) {
            c.user_units.push(f.name().to_string());
        } else if BIN_DIRS.contains(&dir) && (f.is_exec() || f.is_link()) {
            c.executables.push(f.path.clone());
        } else if LIB_DIRS.contains(&dir)
            && (f.is_reg() || f.is_link())
            && is_shared_library(f.name())
        {
            c.libraries.push(f.clone());
        }
    }
    c.executables.sort();
    c.executables.dedup();
    c
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pkglife::parse::rpm_files;

    fn files(t: &str) -> Vec<FileEntry> {
        rpm_files(t).unwrap()
    }

    #[test]
    fn chrony_is_a_daemon_and_a_cli() {
        let f = files(
            "/etc/chrony.conf\t100644\tcn\t
/usr/bin/chronyc\t100755\t\t
/usr/lib/systemd/system/chrony-wait.service\t100644\t\t
/usr/lib/systemd/system/chronyd.service\t100644\t\t
/usr/sbin/chronyd\t100755\t\t
/usr/share/man/man8/chronyd.8.gz\t100644\td\t
/var/lib/chrony/drift\t100644\tg\t
",
        );
        let c = classify(&f, |_| false);
        assert_eq!(c.classes(), vec!["daemon", "cli"]);
        assert_eq!(c.units.len(), 2);
        assert_eq!(c.units[1].kind(), "service");
        assert_eq!(c.executables, vec!["/usr/bin/chronyc", "/usr/sbin/chronyd"]);
    }

    #[test]
    fn a_library_package_is_found_by_its_library_files() {
        let f = files(
            "/usr/lib/libfoo.so.1\t120777\t\tlibfoo.so.1.2.3
/usr/lib/libfoo.so.1.2.3\t100755\t\t
/usr/lib/libpython3.14.so.1.0\t100755\t\t
/usr/lib/pkgconfig/foo.pc\t100644\t\t
/usr/lib/foo/plugin.so\t100755\t\t
",
        );
        let c = classify(&f, |_| false);
        assert_eq!(c.classes(), vec!["library"]);
        assert_eq!(c.libraries.len(), 3);
    }

    #[test]
    fn nested_paths_ghosts_and_aliases_are_not_misread() {
        let f = files(
            "/usr/lib/systemd/system/multi-user.target.wants/x.service\t120777\t\t../x.service
/usr/lib/systemd/system/x.service\t100644\t\t
/usr/lib/systemd/system/y.service\t120777\t\tx.service
/usr/lib/systemd/system/x.service.d/override.conf\t100644\t\t
/usr/lib/systemd/user/x-user.service\t100644\t\t
/usr/bin/ghosted\t100755\tg\t
/usr/bin/sub/tool\t100755\t\t
/usr/bin/notexec\t100644\t\t
/usr/libexec/helper\t100755\t\t
",
        );
        let c = classify(&f, |_| false);
        assert_eq!(c.units.len(), 2);
        assert!(!c.units[0].alias && c.units[1].alias);
        assert_eq!(c.user_units, vec!["x-user.service"]);
        assert!(c.executables.is_empty(), "{:?}", c.executables);
        // a package of only an alias is not a daemon
        let only_alias = classify(&f[2..3], |_| false);
        assert_eq!(only_alias.classes(), vec!["data"]);
    }

    #[test]
    fn templates_and_boot_files_are_recognised() {
        let f = files(
            "/usr/lib/systemd/system/getty@.service\t100644\t\t
/boot/vmlinuz-6.12\t100644\t\t
/boot\t40755\t\t
/usr/share/doc/x\t100644\td\t
",
        );
        let c = classify(&f, |p| p.starts_with("/boot/"));
        assert!(c.units[0].name.contains("@."));
        assert_eq!(c.boot_files, vec!["/boot/vmlinuz-6.12"]);
        // negative control: a data-only package stays data
        let d = classify(&f[3..], |p| p.starts_with("/boot/"));
        assert_eq!(d.classes(), vec!["data"]);
        assert!(d.boot_files.is_empty());
    }
}
