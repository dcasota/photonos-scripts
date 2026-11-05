//! The kernel wrapper bases and profiles compiled into the binary (build.rs),
//! so `build-iso --kernel` and `wrapper` need no script or profile on disk.
//! A directory given explicitly (SHARUKHAN_WRAPPERS, SHARUKHAN_WRAPPER_PROFILES,
//! --wrappers, --profiles) still takes precedence: that is how a base or a
//! profile under review is used before it is compiled in.

include!(concat!(env!("OUT_DIR"), "/embedded_kernel.rs"));

fn find(table: &'static [(&'static str, &'static str)], name: &str) -> Option<&'static str> {
    table.iter().find(|(n, _)| *n == name).map(|(_, t)| *t)
}

/// The embedded base wrapper named `name` (a profile's `base.script`).
pub fn base(name: &str) -> Option<&'static str> {
    find(BASES, name)
}

/// The embedded profile file `name` (`<release>.json`).
pub fn profile(name: &str) -> Option<&'static str> {
    find(PROFILES, name)
}

/// The embedded systemd profile or signer file `name` (profiles/systemd/).
pub fn systemd_file(name: &str) -> Option<&'static str> {
    find(SYSTEMD_PROFILES, name)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every profile is embedded, and the base every profile names is too.
    #[test]
    fn every_profile_and_its_base_are_embedded() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("profiles/kernel");
        for e in std::fs::read_dir(&dir).unwrap().flatten() {
            let n = e.file_name().to_string_lossy().into_owned();
            if !n.ends_with(".json") {
                continue;
            }
            let on_disk = std::fs::read_to_string(e.path()).unwrap();
            assert_eq!(profile(&n), Some(on_disk.as_str()), "{n} is not embedded as it is on disk");
            let v: serde_json::Value = serde_json::from_str(&on_disk).unwrap();
            if let Some(b) = v["base"]["script"].as_str() {
                assert!(base(b).is_some(), "{n} names base {b}, which is not embedded");
            }
        }
    }

    /// The public copy of a base in the scripts repository, where there is
    /// one, is the embedded base: neither may drift from the other.
    #[test]
    fn a_public_copy_of_a_base_is_the_embedded_one() {
        let repo = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        for (name, text) in BASES {
            let p = repo.join(name);
            if let Ok(public) = std::fs::read_to_string(&p) {
                assert_eq!(&public, text, "{} differs from src/embedded/kernel-base/{name}", p.display());
            }
        }
    }
}
