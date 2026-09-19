//! Rebuild the installer initrd around the new kernel's module tree.
//!
//! The installer initrd is not a dracut image: it is a fixed rootfs built at
//! ISO build time, carrying the COMPLETE module tree of the linux package under
//! `usr/lib/modules/<uname>`. Nothing regenerates it on the installed system,
//! so the tree has to be swapped here or the installer boots a kernel whose
//! modules are all for a different vermagic - which presents as a kernel that
//! finds no disks.
//!
//! `depmod` is run by the MEDIA'S OWN kmod inside the emulated root, not by the
//! host's: modules.dep format and the module signing/compression conventions
//! are kmod-version-specific, and a host-generated one can be silently
//! unreadable to the kernel that has to consume it.

use super::buildroot::chroot_capture;
use super::{ok, run, Ctx};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// Unpack the gzip'd newc cpio initrd into `dest`.
///
/// Two argv-only processes with a pipe between them rather than a shell
/// pipeline: `zcat x | cpio` under `set -o pipefail` reports SIGPIPE as
/// failure, and a composed string is how a path becomes shell syntax.
pub fn unpack(_c: &mut Ctx, initrd: &Path, dest: &Path) -> Result<usize, String> {
    fs::create_dir_all(dest).map_err(|e| format!("{}: {e}", dest.display()))?;
    let f = fs::File::open(initrd).map_err(|e| format!("{}: {e}", initrd.display()))?;
    let mut gz = Command::new("gzip")
        .args(["-dc"])
        .stdin(Stdio::from(f))
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("gzip -dc: {e}"))?;
    let out = gz.stdout.take().ok_or("gzip produced no stdout")?;
    let st = Command::new("cpio")
        .args(["-idm", "--quiet", "--no-absolute-filenames"])
        .current_dir(dest)
        .stdin(Stdio::from(out))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(|e| format!("cpio -idm: {e}"))?;
    let gzst = gz.wait().map_err(|e| format!("waiting for gzip: {e}"))?;
    if !gzst.success() {
        return Err(format!("gzip -dc failed on {}", initrd.display()));
    }
    if !st.success() {
        return Err(format!("cpio failed unpacking {}", initrd.display()));
    }
    let n = fs::read_dir(dest).map(|d| d.count()).unwrap_or(0);
    if n == 0 {
        return Err(format!("{} unpacked to nothing", initrd.display()));
    }
    Ok(n)
}

/// The module directories inside an unpacked initrd root.
pub fn module_dirs(root: &Path) -> Vec<String> {
    let base = root.join("usr/lib/modules");
    fs::read_dir(base)
        .map(|d| {
            let mut v: Vec<String> = d
                .flatten()
                .filter(|e| e.path().is_dir())
                .filter_map(|e| e.file_name().to_str().map(str::to_string))
                .collect();
            v.sort();
            v
        })
        .unwrap_or_default()
}

/// Swap the old module tree for the new one.
///
/// A missing old uname is an ERROR, not a no-op: it means this initrd is not
/// the one the media ships, and continuing would produce an initrd carrying
/// two kernels' modules or none.
pub fn swap_module_tree(
    c: &mut Ctx,
    root: &Path,
    old_uname: &str,
    new_tree: &Path,
    new_uname: &str,
) -> Result<usize, String> {
    let modules = root.join("usr/lib/modules");
    let old = modules.join(old_uname);
    if !old.is_dir() {
        return Err(format!(
            "the initrd has no usr/lib/modules/{old_uname}; it carries {:?} instead. \
             This is not the initrd from the input media.",
            module_dirs(root)
        ));
    }
    if !new_tree.is_dir() {
        return Err(format!("{} does not exist", new_tree.display()));
    }
    fs::remove_dir_all(&old).map_err(|e| format!("removing {}: {e}", old.display()))?;
    // -a: the tree carries symlinks and permissions that matter.
    run(
        "cp",
        &[
            "-a",
            &new_tree.to_string_lossy(),
            &modules.join(new_uname).to_string_lossy(),
        ],
    )?;
    let placed = count_modules(&modules.join(new_uname));
    let source = count_modules(new_tree);
    if placed != source {
        return Err(format!(
            "copied {placed} modules but the RPM tree has {source}: the copy was incomplete"
        ));
    }
    c.say(&format!(
        "  swapped usr/lib/modules/{old_uname} -> {new_uname} ({placed} modules)"
    ));
    Ok(placed)
}

fn count_modules(dir: &Path) -> usize {
    let mut n = 0;
    let mut stack = vec![dir.to_path_buf()];
    while let Some(d) = stack.pop() {
        let Ok(rd) = fs::read_dir(&d) else { continue };
        for e in rd.flatten() {
            let p = e.path();
            if p.is_dir() {
                stack.push(p);
            } else if e.file_name().to_string_lossy().contains(".ko") {
                n += 1;
            }
        }
    }
    n
}

/// Run the MEDIA'S depmod against the new tree, inside the emulated root.
pub fn depmod(c: &mut Ctx, root: &Path, uname: &str) -> Result<(), String> {
    let br = c.spec.buildroot();
    let at = br.join("initrdroot");
    fs::create_dir_all(&at).map_err(|e| format!("{}: {e}", at.display()))?;
    let mounted = !ok("mountpoint", &["-q", &at.to_string_lossy()]);
    if mounted {
        run(
            "mount",
            &["--bind", &root.to_string_lossy(), &at.to_string_lossy()],
        )?;
    }
    let r = chroot_capture(&br, &["/usr/sbin/depmod", "-b", "/initrdroot", uname]);
    // Always unmount, including on failure: a leaked bind mount on a shared
    // host outlives this process and blocks the next run.
    let _ = run("umount", &[&at.to_string_lossy()]);
    r.map_err(|e| format!("depmod for {uname}: {e}"))?;
    let dep = root.join("usr/lib/modules").join(uname).join("modules.dep");
    let size = fs::metadata(&dep).map(|m| m.len()).unwrap_or(0);
    if size == 0 {
        return Err(format!("{} is empty after depmod", dep.display()));
    }
    c.say(&format!(
        "  depmod wrote modules.dep ({size} bytes) with the media's own kmod"
    ));
    Ok(())
}

/// Repack as a gzip'd newc cpio.
///
/// The file list is built and sorted HERE, in byte order, rather than by
/// `find | sort` in a shell: the locale changes `sort`'s order, and an initrd
/// whose entries are ordered differently is a different image for no reason.
pub fn repack(c: &mut Ctx, root: &Path, out: &Path) -> Result<u64, String> {
    let mut names: Vec<Vec<u8>> = Vec::new();
    collect(root, root, &mut names)?;
    names.sort();
    let mut list = Vec::with_capacity(names.len() * 32);
    for n in &names {
        list.extend_from_slice(n);
        list.push(b'\n');
    }
    let listfile = c.spec.workdir.join("initrd.filelist");
    fs::write(&listfile, &list).map_err(|e| format!("{}: {e}", listfile.display()))?;

    if let Some(p) = out.parent() {
        fs::create_dir_all(p).map_err(|e| format!("{}: {e}", p.display()))?;
    }
    let lf = fs::File::open(&listfile).map_err(|e| format!("{e}"))?;
    let mut cpio = Command::new("cpio")
        .args(["-o", "-H", "newc", "--quiet"])
        .current_dir(root)
        .stdin(Stdio::from(lf))
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("cpio -o: {e}"))?;
    let archive = cpio.stdout.take().ok_or("cpio produced no stdout")?;
    let outf = fs::File::create(out).map_err(|e| format!("{}: {e}", out.display()))?;
    // -n: no timestamp or name in the gzip header, so the same input gives the
    // same output. -9 to match what the media ships.
    let st = Command::new("gzip")
        .args(["-9", "-n", "-c"])
        .stdin(Stdio::from(archive))
        .stdout(Stdio::from(outf))
        .stderr(Stdio::null())
        .status()
        .map_err(|e| format!("gzip -9: {e}"))?;
    let cst = cpio.wait().map_err(|e| format!("waiting for cpio: {e}"))?;
    if !cst.success() || !st.success() {
        return Err("repacking the initrd failed".to_string());
    }
    let size = fs::metadata(out).map(|m| m.len()).unwrap_or(0);
    if size == 0 {
        return Err(format!("{} is empty", out.display()));
    }
    c.say(&format!(
        "  repacked {} entries into {} ({size} bytes)",
        names.len(),
        out.display()
    ));
    Ok(size)
}

fn collect(root: &Path, dir: &Path, out: &mut Vec<Vec<u8>>) -> Result<(), String> {
    use std::os::unix::ffi::OsStrExt;
    for e in fs::read_dir(dir)
        .map_err(|e| format!("{}: {e}", dir.display()))?
        .flatten()
    {
        let p = e.path();
        let Ok(rel) = p.strip_prefix(root) else {
            continue;
        };
        out.push(rel.as_os_str().as_bytes().to_vec());
        // symlink_metadata: a symlink to a directory must be archived as a
        // symlink, not descended into.
        let md = fs::symlink_metadata(&p).map_err(|e| format!("{}: {e}", p.display()))?;
        if md.is_dir() {
            collect(root, &p, out)?;
        }
    }
    Ok(())
}

/// Extract `lib/modules/<uname>` and `/boot` out of a built kernel RPM.
pub fn unpack_rpm(c: &mut Ctx, rpm: &Path, dest: &Path) -> Result<PathBuf, String> {
    fs::create_dir_all(dest).map_err(|e| format!("{}: {e}", dest.display()))?;
    let f = fs::File::open(rpm).map_err(|e| format!("{}: {e}", rpm.display()))?;
    let mut r2c = Command::new("rpm2cpio")
        .stdin(Stdio::from(f))
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("rpm2cpio: {e}"))?;
    let out = r2c.stdout.take().ok_or("rpm2cpio produced no stdout")?;
    let st = Command::new("cpio")
        .args(["-idm", "--quiet"])
        .current_dir(dest)
        .stdin(Stdio::from(out))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(|e| format!("cpio: {e}"))?;
    let _ = r2c.wait();
    if !st.success() {
        return Err(format!("could not unpack {}", rpm.display()));
    }
    let _ = c;
    Ok(dest.to_path_buf())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fake_initrd(root: &Path, uname: &str, n: usize) {
        let m = root
            .join("usr/lib/modules")
            .join(uname)
            .join("kernel/drivers");
        fs::create_dir_all(&m).unwrap();
        for i in 0..n {
            fs::write(m.join(format!("mod{i}.ko.xz")), "x").unwrap();
        }
        fs::create_dir_all(root.join("etc")).unwrap();
        fs::write(root.join("etc/hostname"), "photon-installer\n").unwrap();
    }

    /// A missing old uname means this is not the media's initrd. Continuing
    /// would leave an initrd carrying two kernels' modules, or none, and the
    /// symptom at boot is "no disks found".
    #[test]
    fn initrd_module_dir_swap_rejects_a_missing_old_uname() {
        let d = std::env::temp_dir().join(format!("shk-initrd-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        let root = d.join("root");
        let newt = d.join("new/6.12.109-4.azure.ph5");
        fake_initrd(&root, "6.12.109-3.ph5", 4);
        fs::create_dir_all(&newt).unwrap();
        fs::write(newt.join("a.ko.xz"), "x").unwrap();

        let spec = crate::remaster::tests_support::spec();
        let mut seen = Vec::new();
        let mut c = Ctx {
            spec: &spec,
            log: &mut |l: &str| seen.push(l.to_string()),
            old_uname: String::new(),
            new_uname: String::new(),
        };

        let e = swap_module_tree(
            &mut c,
            &root,
            "6.1.128-1.ph5",
            &newt,
            "6.12.109-4.azure.ph5",
        )
        .unwrap_err();
        assert!(e.contains("6.1.128-1.ph5"), "{e}");
        assert!(
            e.contains("6.12.109-3.ph5"),
            "the error must say what IS there: {e}"
        );

        // The real uname works, and leaves exactly one module directory.
        let n = swap_module_tree(
            &mut c,
            &root,
            "6.12.109-3.ph5",
            &newt,
            "6.12.109-4.azure.ph5",
        )
        .unwrap();
        assert_eq!(n, 1);
        assert_eq!(module_dirs(&root), vec!["6.12.109-4.azure.ph5".to_string()]);
        let _ = fs::remove_dir_all(&d);
    }

    /// The entry list is sorted in BYTE order here rather than by `sort` in a
    /// shell, because the locale changes the order and an initrd that differs
    /// only in entry order is a gratuitously different image.
    #[test]
    fn the_repack_file_list_is_byte_sorted_and_relative() {
        let d = std::env::temp_dir().join(format!("shk-initlist-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        for sub in ["usr/lib", "etc"] {
            fs::create_dir_all(d.join(sub)).unwrap();
        }
        for f in ["etc/Zfile", "etc/afile", "usr/lib/x"] {
            fs::write(d.join(f), "x").unwrap();
        }
        let mut names = Vec::new();
        collect(&d, &d, &mut names).unwrap();
        names.sort();
        let as_str: Vec<String> = names
            .iter()
            .map(|n| String::from_utf8_lossy(n).to_string())
            .collect();
        // relative, never absolute - an absolute entry unpacks over the host
        assert!(as_str.iter().all(|n| !n.starts_with('/')), "{as_str:?}");
        // byte order puts uppercase before lowercase; a locale-aware sort does not
        let zi = as_str.iter().position(|n| n == "etc/Zfile").unwrap();
        let ai = as_str.iter().position(|n| n == "etc/afile").unwrap();
        assert!(zi < ai, "byte order, not locale order: {as_str:?}");
        assert!(
            as_str.contains(&"usr/lib".to_string()),
            "directories are entries too"
        );
        let _ = fs::remove_dir_all(&d);
    }
}
