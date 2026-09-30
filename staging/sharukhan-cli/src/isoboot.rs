//! How an ISO boots, read from the ISO - never assumed.
//!
//! photon-os-installer 2.9 (upstream b7c9039, 2026-06-04) replaced syslinux:
//! BIOS now boots a GRUB El Torito image, `/isolinux/eltorito.img`, built by
//! `grub2-mkimage -O i386-pc-eltorito -p /boot/grub2`, and `isolinux.bin`,
//! `isolinux.cfg` and `menu.cfg` are gone. POI 2.8 media still boot syslinux
//! `/isolinux/isolinux.bin`. Which one an ISO carries is decided by the
//! installer that COMPOSED it (poiimage.rs), not by the kernel or the date.
//!
//! A tool that hardcodes one of them fails on the other: the HABv4 ISO creator
//! stopped a 7.3-rc4 run with
//!   xorriso : FAILURE : Cannot find in ISO image: -boot_image ...
//!             bin_path='/isolinux/isolinux.bin'
//! after the kernel build and MOK signing had already been paid for. The
//! remaster path never had the problem because it replays the input's boot
//! catalogue; this module gives every other caller the same facts, from the
//! El Torito catalogue itself, checked against the files it names.

use std::path::Path;
use std::process::Command;

/// What loads in BIOS mode.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BiosLoader {
    /// syslinux `isolinux.bin`; its menu is `isolinux/isolinux.cfg`.
    Syslinux,
    /// a GRUB i386-pc El Torito core image; it reads `<prefix>/grub.cfg`,
    /// the same file UEFI GRUB reads on Photon media.
    GrubEltorito,
    /// anything else, named by its path.
    Unknown,
}

impl BiosLoader {
    pub fn as_str(&self) -> &'static str {
        match self {
            BiosLoader::Syslinux => "syslinux",
            BiosLoader::GrubEltorito => "grub-eltorito",
            BiosLoader::Unknown => "unknown",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BootImage {
    /// Absolute path on the medium.
    pub path: String,
    /// El Torito load size in 512-byte sectors, as recorded.
    pub load_size: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Layout {
    pub catalog: Option<String>,
    pub bios: Option<BootImage>,
    pub bios_loader: Option<BiosLoader>,
    pub efi: Option<BootImage>,
    /// Whether the medium carries an MBR/GPT system area (hybrid boot).
    pub hybrid: bool,
}

impl Layout {
    /// The mkisofs-style El Torito options that reproduce this layout from an
    /// extracted tree - with the EFI image's load size left for xorriso to
    /// compute, because a caller that re-signs efiboot.img changes its size.
    pub fn mkisofs_boot_args(&self) -> Vec<String> {
        let mut v = Vec::new();
        if let Some(c) = &self.catalog {
            v.extend(["-c".to_string(), rel(c)]);
        }
        if let Some(b) = &self.bios {
            v.extend(["-b".to_string(), rel(&b.path)]);
            v.extend(["-no-emul-boot", "-boot-load-size", "4", "-boot-info-table"].map(String::from));
            if self.efi.is_some() {
                v.push("-eltorito-alt-boot".into());
            }
        }
        if let Some(e) = &self.efi {
            v.extend(["-e".to_string(), rel(&e.path), "-no-emul-boot".to_string()]);
        }
        v
    }

    pub fn to_json(&self) -> serde_json::Value {
        let img = |i: &Option<BootImage>| {
            i.as_ref().map(|i| serde_json::json!({"path": i.path, "load_size": i.load_size}))
        };
        serde_json::json!({
            "catalog": self.catalog,
            "bios": img(&self.bios),
            "bios_loader": self.bios_loader.as_ref().map(|l| l.as_str()),
            "efi": img(&self.efi),
            "hybrid": self.hybrid,
            "mkisofs_boot_args": self.mkisofs_boot_args(),
        })
    }
}

fn rel(p: &str) -> String {
    p.trim_start_matches('/').to_string()
}

/// Parse `xorriso -report_el_torito plain`.
pub fn parse_report(text: &str) -> Layout {
    let mut catalog = None;
    // entry number -> (platform, load size)
    let mut entries: Vec<(u32, String, Option<u32>)> = Vec::new();
    let mut paths: Vec<(u32, String)> = Vec::new();
    for line in text.lines() {
        let Some((key, val)) = line.split_once(':') else { continue };
        let key = key.trim();
        let f: Vec<&str> = val.split_whitespace().collect();
        match key {
            "El Torito cat path" => catalog = f.first().map(|s| s.to_string()),
            // "El Torito boot img :   1  BIOS  y   none  0x0000  0x00      4   1735"
            "El Torito boot img" if f.len() >= 7 => {
                if let Ok(n) = f[0].parse::<u32>() {
                    entries.push((n, f[1].to_string(), f[6].parse().ok()));
                }
            }
            "El Torito img path" if f.len() >= 2 => {
                if let Ok(n) = f[0].parse::<u32>() {
                    paths.push((n, f[1].to_string()));
                }
            }
            _ => {}
        }
    }
    let find = |plat: &str| {
        entries.iter().find(|(_, p, _)| p == plat).and_then(|(n, _, ls)| {
            paths
                .iter()
                .find(|(pn, _)| pn == n)
                .map(|(_, path)| BootImage { path: path.clone(), load_size: *ls })
        })
    };
    Layout { catalog, bios: find("BIOS"), bios_loader: None, efi: find("UEFI"), hybrid: false }
}

/// Which loader a BIOS boot image is, by its content: syslinux's
/// isolinux.bin carries "ISOLINUX"; a GRUB i386-pc-eltorito image starts with
/// cdboot.img, whose only plain strings are its two error messages ("no boot
/// info", "cdrom read fails", grub-core/boot/i386/pc/cdboot.S) - the core image
/// behind it is compressed, so "GRUB" itself is not in it. Matched on content,
/// not on the file name, which says nothing binding.
pub fn classify_bios_image(bytes: &[u8]) -> BiosLoader {
    let has = |needle: &[u8]| bytes.windows(needle.len()).any(|w| w == needle);
    if has(b"ISOLINUX") {
        BiosLoader::Syslinux
    } else if has(b"no boot info") && has(b"cdrom read fails") {
        BiosLoader::GrubEltorito
    } else {
        BiosLoader::Unknown
    }
}

fn xorriso(iso: &Path, args: &[&str]) -> Result<String, String> {
    let out = Command::new("xorriso")
        .args(["-osirrox", "on", "-indev"])
        .arg(iso)
        .args(args)
        .output()
        .map_err(|e| format!("running xorriso: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "xorriso on {} failed: {}",
            iso.display(),
            String::from_utf8_lossy(&out.stderr).lines().last().unwrap_or("")
        ));
    }
    Ok(String::from_utf8_lossy(&out.stdout).to_string())
}

/// The layout of `iso`, with every path it names proven present and the BIOS
/// loader identified from the image's own bytes.
pub fn read(iso: &Path) -> Result<Layout, String> {
    if !iso.is_file() {
        return Err(format!("{}: not a file", iso.display()));
    }
    let mut l = parse_report(&xorriso(iso, &["-report_el_torito", "plain"])?);
    if l.bios.is_none() && l.efi.is_none() {
        return Err(format!("{} carries no El Torito boot image", iso.display()));
    }
    // The catalogue is a boot-catalogue node, not a regular file, so only its
    // presence is checked; the two images must be regular files.
    let named: Vec<(String, bool)> = [
        l.catalog.clone().map(|c| (c, false)),
        l.bios.as_ref().map(|b| (b.path.clone(), true)),
        l.efi.as_ref().map(|e| (e.path.clone(), true)),
    ]
    .into_iter()
    .flatten()
    .collect();
    for (p, regular) in &named {
        let mut a = vec!["-find", p.as_str()];
        if *regular {
            a.extend(["-type", "f"]);
        }
        let hit = xorriso(iso, &a)?;
        if !hit.lines().any(|x| x.trim().trim_matches('\'') == p) {
            return Err(format!("{}: El Torito names {p}, which is not on the medium", iso.display()));
        }
    }
    if let Some(b) = &l.bios {
        let tmp = std::env::temp_dir().join(format!(
            "shk-isoboot-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or(0)
        ));
        let r = xorriso(iso, &["-extract", &b.path, &tmp.to_string_lossy()])
            .and_then(|_| std::fs::read(&tmp).map_err(|e| format!("{}: {e}", tmp.display())));
        let _ = std::fs::remove_file(&tmp);
        l.bios_loader = Some(classify_bios_image(&r?));
    }
    let sa = xorriso(iso, &["-report_system_area", "plain"])?;
    l.hybrid = sa.lines().any(|x| x.starts_with("System area options") || x.contains("MBR partition") || x.contains("GPT"));
    Ok(l)
}

#[cfg(test)]
mod tests {
    use super::*;

    // Verbatim `-report_el_torito plain` of the two layouts on Ph-Builds.
    const GRUB: &str = "El Torito catalog  : 198  1
El Torito cat path : /isolinux/boot.cat
El Torito images   :   N  Pltf  B   Emul  Ld_seg  Hdpt  Ldsiz         LBA
El Torito boot img :   1  BIOS  y   none  0x0000  0x00      4        1735
El Torito boot img :   2  UEFI  y   none  0x0000  0x00   6144         199
El Torito img path :   1  /isolinux/eltorito.img
El Torito img path :   2  /boot/grub2/efiboot.img
";
    const SYSLINUX: &str = "El Torito catalog  : 61  1
El Torito cat path : /isolinux/boot.cat
El Torito images   :   N  Pltf  B   Emul  Ld_seg  Hdpt  Ldsiz         LBA
El Torito boot img :   1  BIOS  y   none  0x0000  0x00      4          62
El Torito boot img :   2  UEFI  y   none  0x0000  0x00   6144          81
El Torito img path :   1  /isolinux/isolinux.bin
El Torito img path :   2  /boot/grub2/efiboot.img
";
    const EFI_ONLY: &str = "El Torito cat path : /boot.cat
El Torito boot img :   1  UEFI  y   none  0x0000  0x00   6144         81
El Torito img path :   1  /boot/grub2/efiboot.img
";

    #[test]
    fn both_layouts_are_read_from_the_catalogue() {
        let g = parse_report(GRUB);
        assert_eq!(g.catalog.as_deref(), Some("/isolinux/boot.cat"));
        assert_eq!(g.bios.as_ref().unwrap().path, "/isolinux/eltorito.img");
        assert_eq!(g.efi.as_ref().unwrap(), &BootImage { path: "/boot/grub2/efiboot.img".into(), load_size: Some(6144) });
        let s = parse_report(SYSLINUX);
        assert_eq!(s.bios.as_ref().unwrap().path, "/isolinux/isolinux.bin");
        assert_eq!(s.bios.as_ref().unwrap().load_size, Some(4));
    }

    #[test]
    fn boot_args_follow_the_medium_and_leave_the_efi_size_to_xorriso() {
        let a = parse_report(GRUB).mkisofs_boot_args().join(" ");
        assert_eq!(
            a,
            "-c isolinux/boot.cat -b isolinux/eltorito.img -no-emul-boot -boot-load-size 4 \
-boot-info-table -eltorito-alt-boot -e boot/grub2/efiboot.img -no-emul-boot"
        );
        assert!(parse_report(SYSLINUX).mkisofs_boot_args().join(" ").contains("-b isolinux/isolinux.bin "));
        // an EFI-only medium gets no BIOS entry and no alt-boot separator
        let e = parse_report(EFI_ONLY).mkisofs_boot_args().join(" ");
        assert_eq!(e, "-c boot.cat -e boot/grub2/efiboot.img -no-emul-boot");
    }

    #[test]
    fn the_bios_loader_is_classified_by_content() {
        assert_eq!(classify_bios_image(b"\xfa\x31..ISOLINUX 6.04.."), BiosLoader::Syslinux);
        assert_eq!(
            classify_bios_image(b"\xe8\x00\x00\xeb;..no boot info\x00cdrom read fails\x00loading"),
            BiosLoader::GrubEltorito
        );
        // one message alone is not enough
        assert_eq!(classify_bios_image(b"..no boot info.."), BiosLoader::Unknown);
        assert_eq!(classify_bios_image(b"\x00\x01\x02"), BiosLoader::Unknown);
    }
}
