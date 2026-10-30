//! The Azure variant's installer console, on composed media.
//!
//! Azure reads a VM's console from its first serial port: ttyS0 on x86_64,
//! ttyAMA0 on Arm64. Boot diagnostics show what the kernel writes there, and
//! the serial console talks to the getty systemd starts on every kernel
//! console. A Photon install writes no `console=` at all - not the kernel
//! package (`photon_cmdline` in linux-<uname>.cfg), not the installer's GRUB
//! entry - so an installed Azure VM shows a login on tty1 in the screenshot and
//! nothing on the serial log or console.
//!
//! The installer decides the installed system's command line
//! (`poi_kernel_cmdline`, written into its GRUB entry), and POI 2.x has no
//! kickstart key for kernel parameters. So, as `remaster` does for its Azure
//! media, a `--hyperv` build patches the installer in the composed ISO's initrd
//! with the console of the build's architecture, repacks the initrd, rewrites
//! the ISO with its boot records replayed, and reads every claim back.
//!
//! The ISO's own GRUB entry is left alone on purpose: the installer starts its
//! UI on the single active console (generate_initrd's installer script), so a
//! serial console added there could keep the installer from starting on a
//! local Hyper-V install. Only the installed system gets the serial console.

use crate::remaster::{initrd, iso, poi, Arch};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Where the installer initrd sits on Photon media, on both architectures.
pub const INITRD_ON_MEDIA: &str = "/isolinux/initrd.img";

fn extract(iso: &Path, from: &str, to: &Path) -> Result<(), String> {
    let o = Command::new("xorriso")
        .args(["-osirrox", "on", "-indev"])
        .arg(iso)
        .args(["-extract", from])
        .arg(to)
        .output()
        .map_err(|e| format!("xorriso: {e}"))?;
    if !o.status.success() || !to.is_file() {
        return Err(format!(
            "{}: cannot extract {from}: {}",
            iso.display(),
            String::from_utf8_lossy(&o.stderr).lines().last().unwrap_or("")
        ));
    }
    Ok(())
}

/// The installer package of the initrd on `iso`, unpacked under `dir`.
fn installer_of(iso: &Path, dir: &Path) -> Result<(PathBuf, PathBuf), String> {
    let img = dir.join("initrd.img");
    extract(iso, INITRD_ON_MEDIA, &img)?;
    let root = dir.join("root");
    initrd::unpack_to(&img, &root)?;
    let pkg = poi::site_packages(&root)?.join("photon_installer");
    Ok((root, pkg))
}

/// Give the installed system of `iso` the serial console of `arch`, in place.
///
/// Idempotent: an installer that already carries the line is left alone and
/// the ISO is not rewritten. `iso` is replaced only after the rewritten image
/// has been read back - installer line present, boot records unchanged.
pub fn installer_console(iso: &Path, arch: Arch, say: &mut dyn FnMut(&str)) -> Result<(), String> {
    installer_console_to(iso, iso, arch, say)
}

/// [`installer_console`] from `input` into `output`; `input` is never
/// modified when they differ.
pub fn installer_console_to(input: &Path, output: &Path, arch: Arch, say: &mut dyn FnMut(&str)) -> Result<(), String> {
    let iso = input;
    // Scratch on the Linux side: the initrd is a root with symlinks, and the
    // output may live on a Windows drive (drvfs). Beside the output otherwise,
    // so the result is a rename; from the temp directory it is a copy.
    let parent = output.parent().ok_or_else(|| format!("{}: no directory", output.display()))?;
    let base = if is_drvfs(parent) { std::env::temp_dir() } else { parent.to_path_buf() };
    let work = base.join(format!(".sharukhan-azure-{}-{}", std::process::id(), crate::job::stamp()));
    let r = (|| {
        fs::create_dir_all(&work).map_err(|e| format!("{}: {e}", work.display()))?;
        say(&format!("  azure: the installed system's console is {} ({})", arch.console(), arch.rpm()));
        let (root, pkg) = installer_of(iso, &work.join("in"))?;
        if !poi::patch_console(&pkg, arch, say)? {
            if input != output {
                fs::copy(input, output).map_err(|e| format!("{} -> {}: {e}", input.display(), output.display()))?;
            }
            return Ok(());
        }
        let new_initrd = work.join("initrd.new.img");
        initrd::repack_to(&root, &new_initrd, &work, say)?;
        let out = work.join("azure.iso");
        let plan = iso::IsoPlan {
            input: iso.to_path_buf(),
            output: out.clone(),
            rm: Vec::new(),
            rm_r: Vec::new(),
            map: vec![(new_initrd, INITRD_ON_MEDIA.to_string())],
            volid: iso::volid(iso)?,
        };
        iso::write_to(&plan, &work, say)?;

        // read back: the line is in the installer the media boots, and the
        // boot records (BIOS and EFI) are the input's
        let (_, back) = installer_of(&out, &work.join("back"))?;
        let text = fs::read_to_string(back.join("installer.py")).map_err(|e| format!("read-back: {e}"))?;
        if !text.contains(&poi::console_line(arch)) {
            return Err(format!("read-back: {} does not carry `{}`", out.display(), poi::console_line(arch)));
        }
        let (before, after) = (boot_records(&iso::el_torito(iso)?), boot_records(&iso::el_torito(&out)?));
        if before != after {
            return Err(format!("read-back: the boot records changed:\n--- before\n{before}\n--- after\n{after}"));
        }
        say("  azure: read back: installer console set, boot records unchanged");
        if fs::rename(&out, output).is_err() {
            // another file system: copy, then check the copy byte for byte
            let tmp = output.with_extension("iso.partial");
            fs::copy(&out, &tmp).map_err(|e| format!("{} -> {}: {e}", out.display(), tmp.display()))?;
            if crate::sha256::file(&tmp)? != crate::sha256::file(&out)? {
                let _ = fs::remove_file(&tmp);
                return Err(format!("{}: the copy differs from the written image", tmp.display()));
            }
            fs::rename(&tmp, output).map_err(|e| format!("{} -> {}: {e}", tmp.display(), output.display()))?;
        }
        Ok(())
    })();
    let _ = fs::remove_dir_all(&work);
    r
}

/// A Windows drive under WSL (drvfs/9p): no place to unpack a Linux root.
fn is_drvfs(p: &Path) -> bool {
    let Ok(m) = fs::read_to_string("/proc/self/mounts") else { return false };
    let p = p.canonicalize().unwrap_or_else(|_| p.to_path_buf());
    m.lines()
        .filter_map(|l| {
            let f: Vec<&str> = l.split_whitespace().collect();
            (f.len() > 2).then(|| (f[1].to_string(), f[2].to_string()))
        })
        .filter(|(mnt, _)| p.starts_with(mnt))
        .max_by_key(|(mnt, _)| mnt.len())
        .is_some_and(|(_, ty)| ty == "9p" || ty == "drvfs")
}

/// The architecture a medium is for, from its repository (`/RPMS/<arch>`).
pub fn media_arch(iso: &Path) -> Result<Arch, String> {
    let o = Command::new("xorriso")
        .args(["-indev"])
        .arg(iso)
        .args(["-ls", "/RPMS"])
        .output()
        .map_err(|e| format!("xorriso: {e}"))?;
    let listing = String::from_utf8_lossy(&o.stdout);
    let found: Vec<Arch> = [Arch::X86_64, Arch::Aarch64]
        .into_iter()
        .filter(|a| listing.lines().any(|l| l.trim().trim_matches('\'') == a.rpm()))
        .collect();
    match found.as_slice() {
        [one] => Ok(*one),
        [] => Err(format!("{}: no /RPMS/x86_64 or /RPMS/aarch64, so not a Photon medium", iso.display())),
        _ => Err(format!("{}: carries both x86_64 and aarch64 repositories", iso.display())),
    }
}

/// `sharukhan azure-console --in <iso> --out <iso> [--arch x86_64|aarch64]`
pub fn cli(input: Option<&str>, output: Option<&str>, arch: Option<&str>) -> Result<(), String> {
    let input = Path::new(input.ok_or("azure-console needs --in <iso>")?);
    let output = Path::new(output.ok_or("azure-console needs --out <iso>")?);
    if input == output {
        return Err("--in and --out are the same file; the input stays intact".into());
    }
    if output.exists() {
        return Err(format!("{} exists; choose another --out", output.display()));
    }
    let media = media_arch(input)?;
    let a = match arch {
        None => media,
        Some(s) => {
            let a = Arch::parse(s)?;
            if a != media {
                return Err(format!("--arch {s}, but {} is a {} medium", input.display(), media.rpm()));
            }
            a
        }
    };
    installer_console_to(input, output, a, &mut |l| println!("{l}"))?;
    println!("{}", output.display());
    Ok(())
}

/// The El Torito report without block addresses: a rewritten image moves
/// the boot images and the catalogue, which is not a change of what boots.
/// Platform, bootability, emulation, load size and image paths must hold.
fn boot_records(report: &str) -> String {
    report
        .lines()
        .map(|l| {
            let mut w: Vec<&str> = l.split_whitespace().collect();
            if l.starts_with("El Torito boot img :") {
                // `... <load size> <LBA>`: the address is the last column
                w.pop();
                w.join(" ")
            } else if l.starts_with("El Torito catalog  :") {
                // `El Torito catalog : <LBA> <blocks>`: the address follows the colon
                if let Some(i) = w.iter().position(|x| *x == ":") {
                    if i + 1 < w.len() {
                        w.remove(i + 1);
                    }
                }
                w.join(" ")
            } else {
                l.split_whitespace().collect::<Vec<_>>().join(" ")
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn boot_records_ignore_addresses_and_keep_what_boots() {
        let a = "El Torito catalog  : 33  1\nEl Torito boot img :   1  BIOS  y   none  0x0000  0x00      4          35\nEl Torito img path :   1  /isolinux/eltorito.img";
        let moved = a.replace("4          35", "4          36").replace("catalog  : 33", "catalog  : 40");
        assert_eq!(boot_records(a), boot_records(&moved));
        let lost_efi = format!("{a}\nEl Torito boot img :   2  UEFI  y   none  0x0000  0x00      4          34");
        assert_ne!(boot_records(a), boot_records(&lost_efi));
        let not_bootable = a.replace("BIOS  y", "BIOS  n");
        assert_ne!(boot_records(a), boot_records(&not_bootable));
    }

    fn have(prog: &str) -> bool {
        Command::new(prog).arg("--version").output().map(|o| o.status.success()).unwrap_or(false)
    }

    /// A small medium: an initrd whose installer carries the anchor, a GRUB
    /// file, no boot records. The step must set the console of the arch, keep
    /// every other file, and be a no-op the second time.
    #[test]
    fn the_installed_systems_console_follows_the_arch_and_reads_back() {
        if !(have("xorriso") && have("cpio") && have("gzip")) {
            eprintln!("skipped: xorriso, cpio or gzip missing");
            return;
        }
        for arch in [Arch::X86_64, Arch::Aarch64] {
            let d = std::env::temp_dir().join(format!("shk-azure-{}-{}-{}", std::process::id(), crate::job::stamp(), arch.console()));
            let _ = fs::remove_dir_all(&d);
            let pkg = d.join("rd/usr/lib/python3.14/site-packages/photon_installer");
            fs::create_dir_all(&pkg).unwrap();
            fs::write(pkg.join("installer.py"), "class Installer:\n    def __init__(self):\n        self.poi_kernel_cmdline = \"\"\n").unwrap();
            fs::create_dir_all(d.join("rd/etc")).unwrap();
            fs::write(d.join("rd/etc/hostname"), "photon-installer\n").unwrap();
            let media = d.join("media");
            fs::create_dir_all(media.join("isolinux")).unwrap();
            fs::create_dir_all(media.join("boot/grub2")).unwrap();
            fs::write(media.join("boot/grub2/grub.cfg"), "linux /isolinux/vmlinuz root=/dev/ram0\n").unwrap();
            // stand-ins for the BIOS and EFI boot images, so the medium has
            // both El Torito records the real one carries
            fs::write(media.join("isolinux/eltorito.img"), vec![0u8; 2048]).unwrap();
            fs::write(media.join("boot/efiboot.img"), vec![0u8; 2048]).unwrap();
            initrd::repack_to(&d.join("rd"), &media.join("isolinux/initrd.img"), &d, &mut |_| {}).unwrap();
            let iso = d.join("photon.iso");
            let st = Command::new("xorriso")
                .args(["-as", "mkisofs", "-quiet", "-V", "PHOTON_TEST", "-c", "isolinux/boot.cat", "-b", "isolinux/eltorito.img"])
                .args(["-no-emul-boot", "-eltorito-alt-boot", "-e", "boot/efiboot.img", "-no-emul-boot", "-o"])
                .arg(&iso)
                .arg(&media)
                .status()
                .unwrap();
            assert!(st.success());
            fs::set_permissions(&iso, fs::Permissions::from_mode(0o644)).unwrap();

            let mut lines = Vec::new();
            installer_console(&iso, arch, &mut |l| lines.push(l.to_string())).unwrap();
            let back = d.join("back");
            fs::create_dir_all(&back).unwrap();
            let (root, pkg) = installer_of(&iso, &back).unwrap();
            let text = fs::read_to_string(pkg.join("installer.py")).unwrap();
            assert!(text.contains(&format!("console={},115200n8", arch.console())), "{text}");
            assert!(!text.contains(match arch { Arch::X86_64 => "ttyAMA0", Arch::Aarch64 => "ttyS0" }), "{text}");
            assert_eq!(fs::read_to_string(root.join("etc/hostname")).unwrap(), "photon-installer\n");
            assert_eq!(iso::volid(&iso).unwrap(), "PHOTON_TEST");
            // a second run changes nothing
            let sum = crate::sha256::file(&iso).unwrap();
            installer_console(&iso, arch, &mut |_| {}).unwrap();
            assert_eq!(crate::sha256::file(&iso).unwrap(), sum);
            assert!(fs::read_dir(&d).unwrap().flatten().all(|e| !e.file_name().to_string_lossy().starts_with(".sharukhan-azure")));
            let _ = fs::remove_dir_all(&d);
        }
    }
}
