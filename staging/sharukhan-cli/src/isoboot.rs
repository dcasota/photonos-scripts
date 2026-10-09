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

/// Whether the boot menu a firmware reaches on a medium boots on its own.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BootMenu {
    /// `syslinux` or `grub`.
    pub loader: &'static str,
    /// The menu file on the medium the decision was read from.
    pub config: String,
    /// Tenths of a second until the default entry boots; `None` is a menu
    /// that waits for a key indefinitely.
    pub autoboot_ds: Option<u64>,
    /// The line that decided it, or why no line did.
    pub evidence: String,
}

impl BootMenu {
    pub fn waits_forever(&self) -> bool {
        self.autoboot_ds.is_none()
    }

    pub fn describe(&self) -> String {
        match self.autoboot_ds {
            Some(ds) => format!(
                "{} {} boots its default entry after {}.{}s ({})",
                self.loader, self.config, ds / 10, ds % 10, self.evidence
            ),
            None => format!(
                "{} {} waits for a key indefinitely ({})",
                self.loader, self.config, self.evidence
            ),
        }
    }
}

/// syslinux semantics (doc/syslinux.txt): TIMEOUT and TOTALTIMEOUT are in
/// tenths of a second, 0 or absent meaning no timeout; TOTALTIMEOUT also ends
/// a menu someone is looking at, so the shorter non-zero one decides. The
/// last occurrence of a directive wins, across included files in the order
/// syslinux reads them. `files` is that reading order: (path, text).
pub fn syslinux_menu(config: &str, files: &[(String, String)]) -> BootMenu {
    let mut timeout: Option<(u64, String)> = None;
    let mut total: Option<(u64, String)> = None;
    for (path, text) in files {
        for line in text.lines() {
            let mut w = line.split_whitespace();
            let (Some(k), Some(v)) = (w.next(), w.next()) else { continue };
            let slot = match k.to_ascii_lowercase().as_str() {
                "timeout" => &mut timeout,
                "totaltimeout" => &mut total,
                _ => continue,
            };
            if let Ok(n) = v.parse::<u64>() {
                *slot = Some((n, format!("{path}: {}", line.trim())));
            }
        }
    }
    let live = [timeout.clone(), total.clone()]
        .into_iter()
        .flatten()
        .filter(|(n, _)| *n > 0)
        .min_by_key(|(n, _)| *n);
    let (autoboot_ds, evidence) = match live {
        Some((n, e)) => (Some(n), e),
        None => (
            None,
            timeout
                .or(total)
                .map(|(_, e)| e)
                .unwrap_or_else(|| "no TIMEOUT or TOTALTIMEOUT directive".into()),
        ),
    };
    BootMenu { loader: "syslinux", config: config.into(), autoboot_ds, evidence }
}

/// The files a syslinux configuration includes, as named by INCLUDE and
/// MENU INCLUDE, relative to the configuration's directory.
pub fn syslinux_includes(text: &str) -> Vec<String> {
    text.lines()
        .filter_map(|l| {
            let w: Vec<&str> = l.split_whitespace().collect();
            match w.as_slice() {
                [k, f, ..] if k.eq_ignore_ascii_case("include") => Some(f.to_string()),
                [m, k, f, ..] if m.eq_ignore_ascii_case("menu") && k.eq_ignore_ascii_case("include") => {
                    Some(f.to_string())
                }
                _ => None,
            }
        })
        .collect()
}

/// GRUB semantics: `timeout` in seconds, -1 or unset meaning wait for a key.
/// A configuration that hands over to another one (`configfile`, `source`)
/// is refused rather than half-read: its effective timeout is not in it.
pub fn grub_menu(config: &str, text: &str) -> Result<BootMenu, String> {
    let mut last: Option<(i64, String)> = None;
    for line in text.lines() {
        let t = line.trim();
        let first = t.split_whitespace().next().unwrap_or("");
        if first == "configfile" || first == "source" {
            return Err(format!(
                "{config} hands over to another configuration ({t}); its timeout is not readable from this file"
            ));
        }
        let assign = t.strip_prefix("set ").unwrap_or(t).trim();
        if let Some(v) = assign.strip_prefix("timeout=") {
            let v = v.trim().trim_matches('"').trim_matches('\'');
            match v.parse::<i64>() {
                Ok(n) => last = Some((n, t.to_string())),
                Err(_) => return Err(format!("{config}: timeout is not a number: {t}")),
            }
        }
    }
    let (autoboot_ds, evidence) = match last {
        Some((n, e)) if n >= 0 => (Some(n as u64 * 10), e),
        Some((_, e)) => (None, e),
        None => (None, "no timeout assignment; GRUB then waits for a key".into()),
    };
    Ok(BootMenu { loader: "grub", config: config.into(), autoboot_ds, evidence })
}

/// The text of one file on the medium, or `None` if it is not there.
fn medium_text(iso: &Path, path: &str) -> Result<Option<String>, String> {
    let hit = xorriso(iso, &["-find", path, "-type", "f"])?;
    if !hit.lines().any(|x| x.trim().trim_matches('\'') == path) {
        return Ok(None);
    }
    let tmp = std::env::temp_dir().join(format!(
        "shk-isomenu-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0)
    ));
    let r = xorriso(iso, &["-extract", path, &tmp.to_string_lossy()])
        .and_then(|_| std::fs::read(&tmp).map_err(|e| format!("{}: {e}", tmp.display())));
    let _ = std::fs::remove_file(&tmp);
    Ok(Some(String::from_utf8_lossy(&r?).to_string()))
}

/// The GRUB menu every GRUB on Photon media reads: both the i386-pc El Torito
/// core and the EFI image are built with prefix /boot/grub2.
const GRUB_CFG: &str = "/boot/grub2/grub.cfg";

/// The boot menu `firmware` (`efi` or `bios`) reaches on `iso`, read from
/// the medium.
pub fn boot_menu(iso: &Path, layout: &Layout, firmware: &str) -> Result<BootMenu, String> {
    let grub = || -> Result<BootMenu, String> {
        let text = medium_text(iso, GRUB_CFG)?
            .ok_or_else(|| format!("{}: GRUB boots it but {GRUB_CFG} is not on it", iso.display()))?;
        grub_menu(GRUB_CFG, &text)
    };
    match firmware {
        "efi" => {
            if layout.efi.is_none() {
                return Err(format!("{}: no UEFI El Torito image, an EFI VM cannot boot it", iso.display()));
            }
            grub()
        }
        "bios" => {
            let img = layout
                .bios
                .as_ref()
                .ok_or_else(|| format!("{}: no BIOS El Torito image, a BIOS VM cannot boot it", iso.display()))?;
            match layout.bios_loader {
                Some(BiosLoader::GrubEltorito) => grub(),
                Some(BiosLoader::Syslinux) => {
                    let dir = img.path.rsplit_once('/').map(|(d, _)| d).unwrap_or("");
                    let root = format!("{dir}/isolinux.cfg");
                    let mut files = Vec::new();
                    let mut queue = vec![root.clone()];
                    while let Some(path) = queue.pop() {
                        if files.iter().any(|(p, _): &(String, String)| *p == path) || files.len() > 32 {
                            continue;
                        }
                        let text = medium_text(iso, &path)?
                            .ok_or_else(|| format!("{}: syslinux names {path}, which is not on it", iso.display()))?;
                        let mut inc: Vec<String> = syslinux_includes(&text)
                            .into_iter()
                            .map(|f| if f.starts_with('/') { f } else { format!("{dir}/{f}") })
                            .collect();
                        inc.reverse();
                        files.push((path, text));
                        queue.extend(inc);
                    }
                    Ok(syslinux_menu(&root, &files))
                }
                _ => Err(format!(
                    "{}: the BIOS loader {} is neither syslinux nor GRUB; its menu cannot be read",
                    iso.display(),
                    img.path
                )),
            }
        }
        other => Err(format!("unknown firmware '{other}' (efi | bios)")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// POI 2.8 media, verbatim: the menu is in menu.cfg, the timeout in
    /// isolinux.cfg, and 0 there is the menu that stopped b01 for 40 minutes.
    #[test]
    fn a_syslinux_timeout_of_zero_waits_forever() {
        let files = vec![
            (
                "/isolinux/isolinux.cfg".to_string(),
                "# D-I config version 2.0\ninclude menu.cfg\ndefault vesamenu.c32\nprompt 0\ntimeout 0\n".to_string(),
            ),
            ("/isolinux/menu.cfg".to_string(), "menu title Photon\ndefault install\n".to_string()),
        ];
        let m = syslinux_menu("/isolinux/isolinux.cfg", &files);
        assert!(m.waits_forever(), "{}", m.describe());
        assert!(m.evidence.contains("timeout 0"));
        assert_eq!(syslinux_includes(&files[0].1), vec!["menu.cfg"]);
    }

    #[test]
    fn syslinux_boots_after_the_shorter_live_timeout_and_the_last_directive_wins() {
        let f = |t: &str| vec![("/i/isolinux.cfg".to_string(), t.to_string())];
        assert_eq!(syslinux_menu("c", &f("TIMEOUT 50\n")).autoboot_ds, Some(50));
        assert_eq!(syslinux_menu("c", &f("timeout 50\ntimeout 0\n")).autoboot_ds, None);
        assert_eq!(syslinux_menu("c", &f("timeout 0\ntotaltimeout 300\n")).autoboot_ds, Some(300));
        assert_eq!(syslinux_menu("c", &f("timeout 80\ntotaltimeout 30\n")).autoboot_ds, Some(30));
        assert_eq!(syslinux_menu("c", &f("prompt 1\n")).autoboot_ds, None);
        assert_eq!(syslinux_includes("MENU INCLUDE /x/a.cfg\n  include b.cfg"), vec!["/x/a.cfg", "b.cfg"]);
    }

    /// The grub.cfg on both POI 2.8 and latest media, verbatim head.
    #[test]
    fn grub_reads_its_timeout_and_minus_one_or_none_waits() {
        let cfg = "set default=0\nset timeout=3\nloadfont ascii\nmenuentry \"Install\" {\n}\n";
        assert_eq!(grub_menu("g", cfg).unwrap().autoboot_ds, Some(30));
        assert!(grub_menu("g", "set timeout=-1\n").unwrap().waits_forever());
        assert!(grub_menu("g", "set default=0\n").unwrap().waits_forever());
        assert_eq!(grub_menu("g", "timeout=0\n").unwrap().autoboot_ds, Some(0));
        assert!(grub_menu("g", "set timeout=abc\n").is_err());
        assert!(grub_menu("g", "configfile /boot/grub2/other.cfg\n").is_err());
    }

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
