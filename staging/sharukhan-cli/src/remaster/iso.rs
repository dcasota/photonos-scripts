//! Write the new ISO by replaying the input's boot image.
//!
//! `xorriso -boot_image any replay` keeps the El Torito boot catalogue and the
//! UEFI boot image (`/boot/grub2/efiboot.img`) exactly as the input had them.
//! Rebuilding the ISO from a tree instead would mean re-deriving the boot
//! setup, and getting that subtly wrong produces media that looks right and
//! does not boot.
//!
//! The argv is built as TYPED TOKENS, never a string. `-rm` takes a path LIST
//! terminated by `--`, and without the terminator the following `-map` words
//! are silently consumed as more paths to delete - which deletes the boot files
//! and reports success.

use super::{run, Ctx};
use crate::sha256;
use std::fs;
use std::path::{Path, PathBuf};

/// What the new ISO differs from the old one by.
#[derive(Debug, Clone, Default)]
pub struct IsoPlan {
    pub input: PathBuf,
    pub output: PathBuf,
    /// Files to delete, by absolute path on the medium.
    pub rm: Vec<String>,
    /// Directories to delete recursively.
    pub rm_r: Vec<String>,
    /// (source on the host, destination on the medium).
    pub map: Vec<(PathBuf, String)>,
    pub volid: String,
}

/// The volume id of the input, so the output keeps it.
///
/// Read from the medium rather than hardcoded: the installer's own
/// `photon-local.repo` and the GRUB search stanza find the media by label, so a
/// changed volid produces an ISO that boots to a shell.
/// The absolute path of a media RPM, from the repo-relative href in
/// `primary.xml`.
///
/// `href` is relative to the REPO ROOT, which on the medium is `/RPMS` - so it
/// reads `aarch64/linux-6.12.109-3.ph5.aarch64.rpm`, not
/// `RPMS/aarch64/...`. Prefixing only `/` yields `/aarch64/...`, a path that
/// does not exist on the ISO: the removals then silently do nothing while the
/// replacements are added, and the finished medium carries BOTH the old and the
/// new kernel.
pub fn media_rpm_path(href: &str) -> String {
    let h = href.trim_start_matches('/');
    // Tolerate an href that already carries the repo root, so this cannot
    // double-prefix if the metadata convention ever changes.
    match h.strip_prefix("RPMS/") {
        Some(rest) => format!("/RPMS/{rest}"),
        None => format!("/RPMS/{h}"),
    }
}

/// Read from the MEDIUM, at a fixed offset, rather than parsed out of a tool's
/// output.
///
/// ISO 9660 puts the Primary Volume Descriptor at sector 16 (2048-byte
/// sectors): byte 0 is the descriptor type (1 = primary), bytes 1..6 are the
/// signature `CD001`, and bytes 40..72 are the volume identifier, space-padded.
///
/// The first implementation ran `xorriso -toc` and scanned its output, which
/// found nothing and reported a perfectly good ISO as having no volume id:
/// xorriso prints that line on a channel the stdout-only argv runner does not
/// capture. Reading the descriptor removes the tool, the channel and the
/// output-format dependency in one go, and it can be tested against a synthetic
/// descriptor with no ISO to hand.
pub fn volid(iso: &Path) -> Result<String, String> {
    use std::io::{Read, Seek, SeekFrom};
    let mut f = fs::File::open(iso).map_err(|e| format!("{}: {e}", iso.display()))?;
    f.seek(SeekFrom::Start(16 * 2048)).map_err(|e| {
        format!(
            "{}: seeking to the primary volume descriptor: {e}",
            iso.display()
        )
    })?;
    let mut pvd = [0u8; 2048];
    f.read_exact(&mut pvd).map_err(|e| {
        format!(
            "{}: reading the primary volume descriptor: {e}",
            iso.display()
        )
    })?;
    volid_from_pvd(&pvd).map_err(|e| format!("{}: {e}", iso.display()))
}

/// The volume id out of a primary volume descriptor. Split out so the parsing
/// is testable without an ISO.
fn volid_from_pvd(pvd: &[u8]) -> Result<String, String> {
    if pvd.len() < 72 {
        return Err("the volume descriptor is truncated".to_string());
    }
    if pvd[0] != 1 || &pvd[1..6] != b"CD001" {
        return Err(format!(
            "no ISO 9660 primary volume descriptor at sector 16 (type {}, signature {:?})",
            pvd[0],
            String::from_utf8_lossy(&pvd[1..6])
        ));
    }
    let v = String::from_utf8_lossy(&pvd[40..72]).trim_end().to_string();
    if v.is_empty() {
        return Err("the primary volume descriptor carries an empty volume id".to_string());
    }
    Ok(v)
}

/// The xorriso argument vector.
///
/// Pure, so the `--` terminators and the boot replay can be asserted without
/// writing a 4 GB image.
pub fn argv(plan: &IsoPlan) -> Vec<String> {
    let mut v: Vec<String> = vec![
        "-indev".into(),
        plan.input.to_string_lossy().to_string(),
        "-outdev".into(),
        plan.output.to_string_lossy().to_string(),
        // Keep the El Torito catalogue and the UEFI boot image as they are.
        "-boot_image".into(),
        "any".into(),
        "replay".into(),
        // The input's boot catalogue is not at a "compliant" LBA; refusing it
        // would reject media that demonstrably boots.
        "-compliance".into(),
        "no_emul_toc".into(),
    ];
    if !plan.rm.is_empty() {
        v.push("-rm".into());
        v.extend(plan.rm.iter().cloned());
        // Without this the next -map's words become more paths to delete.
        v.push("--".into());
    }
    for d in &plan.rm_r {
        v.push("-rm_r".into());
        v.push(d.clone());
        v.push("--".into());
    }
    for (src, dst) in &plan.map {
        v.push("-map".into());
        v.push(src.to_string_lossy().to_string());
        v.push(dst.clone());
    }
    if !plan.volid.is_empty() {
        v.push("-volid".into());
        v.push(plan.volid.clone());
    }
    v.push("-commit".into());
    v
}

/// Write the ISO and its `.sha256` sidecar.
pub fn write(c: &mut Ctx, plan: &IsoPlan) -> Result<String, String> {
    if plan.output.exists() {
        // xorriso appends to an existing image rather than replacing it, which
        // would silently produce a second session.
        std::fs::remove_file(&plan.output)
            .map_err(|e| format!("removing the stale output {}: {e}", plan.output.display()))?;
    }
    let a = argv(plan);
    let refs: Vec<&str> = a.iter().map(|s| s.as_str()).collect();
    let log = c.spec.workdir.join("xorriso.log");
    c.say(&format!(
        "  writing {} ({} operations)",
        plan.output.display(),
        plan.map.len()
    ));
    super::run_logged(c, "xorriso", &refs, &log)?;

    let size = std::fs::metadata(&plan.output)
        .map(|m| m.len())
        .map_err(|e| format!("{}: {e}", plan.output.display()))?;
    if size == 0 {
        return Err(format!("{} is empty", plan.output.display()));
    }
    let sum = sha256::file(&plan.output)?;
    let name = plan
        .output
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();
    let side = PathBuf::from(format!("{}.sha256", plan.output.display()));
    std::fs::write(&side, format!("{sum}  {name}\n"))
        .map_err(|e| format!("{}: {e}", side.display()))?;
    c.say(&format!("  {} bytes, sha256 {sum}", size));
    c.say(&format!("  wrote {}", side.display()));
    Ok(sum)
}

/// The El Torito record of a finished ISO, for the verify step.
pub fn el_torito(iso: &Path) -> Result<String, String> {
    let out = run(
        "xorriso",
        &[
            "-indev",
            &iso.to_string_lossy(),
            "-report_el_torito",
            "plain",
        ],
    )?;
    let lines: Vec<&str> = out
        .lines()
        .filter(|l| l.contains("El Torito") && (l.contains("img") || l.contains("cat")))
        .collect();
    if lines.is_empty() {
        return Err(format!(
            "{} reports no El Torito boot record: it would not boot on UEFI",
            iso.display()
        ));
    }
    Ok(lines.join("\n"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn plan() -> IsoPlan {
        let subpkgs = [
            "linux",
            "linux-devel",
            "linux-docs",
            "linux-drivers-gpu",
            "linux-drivers-sound",
            "linux-tools",
            "linux-python3-perf",
            "bpftool",
        ];
        let mut p = IsoPlan {
            input: "/in.iso".into(),
            output: "/out.iso".into(),
            volid: "PHOTON_20250221".into(),
            ..Default::default()
        };
        for s in subpkgs {
            p.rm.push(format!("/RPMS/aarch64/{s}-6.12.109-3.ph5.aarch64.rpm"));
            p.map.push((
                PathBuf::from(format!("/new/{s}-6.12.109-4.azure.ph5.aarch64.rpm")),
                format!("/RPMS/aarch64/{s}-6.12.109-4.azure.ph5.aarch64.rpm"),
            ));
        }
        p.rm_r.push("/RPMS/repodata".into());
        p.map
            .push((PathBuf::from("/new/repodata"), "/RPMS/repodata".into()));
        p.map
            .push((PathBuf::from("/new/vmlinuz"), "/isolinux/vmlinuz".into()));
        p.map.push((
            PathBuf::from("/new/initrd.img"),
            "/isolinux/initrd.img".into(),
        ));
        p
    }

    /// The href in primary.xml is relative to the REPO ROOT (/RPMS), so a bare
    /// `/` prefix names a path that is not on the medium. xorriso then removes
    /// nothing while the replacements are still added, and the ISO ships both
    /// the old and the new kernel - which verify catches only because it
    /// insists on exactly one kernel package.
    #[test]
    fn a_media_rpm_path_is_anchored_at_the_repo_root_not_the_iso_root() {
        assert_eq!(
            media_rpm_path("aarch64/linux-6.12.109-3.ph5.aarch64.rpm"),
            "/RPMS/aarch64/linux-6.12.109-3.ph5.aarch64.rpm"
        );
        // The bug this pins: NOT /aarch64/...
        assert_ne!(
            media_rpm_path("aarch64/linux-6.12.109-3.ph5.aarch64.rpm"),
            "/aarch64/linux-6.12.109-3.ph5.aarch64.rpm"
        );
        // A leading slash must not produce a doubled one.
        assert_eq!(media_rpm_path("/aarch64/x.rpm"), "/RPMS/aarch64/x.rpm");
        // Nor may an href that already names the repo root double-prefix.
        assert_eq!(media_rpm_path("RPMS/aarch64/x.rpm"), "/RPMS/aarch64/x.rpm");
        assert_eq!(media_rpm_path("noarch/y.rpm"), "/RPMS/noarch/y.rpm");
    }

    /// The installer finds the media by label - `photon-local.repo` and the
    /// GRUB search stanza both key on it - so a lost volume id yields an ISO
    /// that boots to a shell. Reading it from the descriptor also removes the
    /// dependency on which channel a tool prints it to, which is what broke
    /// the first implementation.
    #[test]
    fn the_volume_id_is_read_from_the_primary_volume_descriptor() {
        let mut pvd = vec![0u8; 2048];
        pvd[0] = 1;
        pvd[1..6].copy_from_slice(b"CD001");
        // 32 bytes, space padded, exactly as mkisofs writes it.
        let label = b"PHOTON_20250221                 ";
        pvd[40..72].copy_from_slice(label);
        assert_eq!(volid_from_pvd(&pvd).unwrap(), "PHOTON_20250221");

        // A descriptor that is not a PVD must be refused, not read as garbage:
        // it means the offset assumption is wrong for this medium.
        let mut bad = pvd.clone();
        bad[0] = 2; // supplementary volume descriptor
        let e = volid_from_pvd(&bad).unwrap_err();
        assert!(e.contains("primary volume descriptor"), "{e}");

        let mut nosig = pvd.clone();
        nosig[1..6].copy_from_slice(b"XXXXX");
        assert!(volid_from_pvd(&nosig).is_err());

        // An all-blank label is an error rather than an empty string silently
        // becoming the new volume id.
        let mut blank = pvd.clone();
        blank[40..72].copy_from_slice(&[b' '; 32]);
        assert!(volid_from_pvd(&blank).unwrap_err().contains("empty"));

        assert!(
            volid_from_pvd(&pvd[..20]).is_err(),
            "a truncated descriptor is an error"
        );
    }

    #[test]
    fn xorriso_argv_replaces_every_subpackage_and_keeps_boot_image_replay() {
        let a = argv(&plan());
        let joined = a.join(" ");

        // The boot catalogue and UEFI image are replayed, never rebuilt.
        let bi = a.iter().position(|x| x == "-boot_image").unwrap();
        assert_eq!(a[bi + 1], "any");
        assert_eq!(a[bi + 2], "replay");

        // Every one of the eight packages is both removed and replaced,
        // including bpftool, whose name does not start with linux.
        for s in [
            "linux",
            "linux-devel",
            "linux-tools",
            "bpftool",
            "linux-python3-perf",
        ] {
            assert!(
                joined.contains(&format!("/RPMS/aarch64/{s}-6.12.109-3.ph5.aarch64.rpm")),
                "{s} is not removed"
            );
            assert!(
                joined.contains(&format!(
                    "/RPMS/aarch64/{s}-6.12.109-4.azure.ph5.aarch64.rpm"
                )),
                "{s} is not replaced"
            );
        }
        // The volume id survives: the installer finds the media by label.
        assert!(joined.contains("-volid PHOTON_20250221"), "{joined}");
        assert_eq!(a.last().unwrap(), "-commit");
    }

    /// `-rm` takes a path LIST. Without the `--` terminator the following
    /// `-map` words are consumed as more paths to delete - which removes the
    /// boot files and still reports success.
    #[test]
    fn every_removal_list_is_terminated_before_the_next_operation() {
        let a = argv(&plan());
        for (i, tok) in a.iter().enumerate() {
            if tok == "-rm" || tok == "-rm_r" {
                // Scan forward to the next operation; a `--` must come first.
                let mut j = i + 1;
                let mut terminated = false;
                while j < a.len() {
                    if a[j] == "--" {
                        terminated = true;
                        break;
                    }
                    if a[j].starts_with('-') && a[j] != "--" && !a[j].starts_with("/RPMS") {
                        break;
                    }
                    j += 1;
                }
                assert!(
                    terminated,
                    "the {tok} list at {i} is not terminated by --: {a:?}"
                );
            }
        }
        // and a plan with nothing to remove emits no dangling -rm at all
        let empty = IsoPlan {
            input: "/a".into(),
            output: "/b".into(),
            ..Default::default()
        };
        let e = argv(&empty);
        assert!(!e.contains(&"-rm".to_string()), "{e:?}");
        assert!(!e.contains(&"--".to_string()), "{e:?}");
    }

    /// `-map` takes exactly two arguments. A source with no destination would
    /// make the next flag the destination.
    #[test]
    fn every_map_carries_exactly_a_source_and_a_destination() {
        let a = argv(&plan());
        let n = a.iter().filter(|x| *x == "-map").count();
        assert_eq!(n, plan().map.len());
        for (i, tok) in a.iter().enumerate() {
            if tok == "-map" {
                assert!(i + 2 < a.len(), "truncated -map");
                assert!(
                    !a[i + 1].starts_with('-'),
                    "source looks like a flag: {}",
                    a[i + 1]
                );
                assert!(
                    a[i + 2].starts_with('/'),
                    "destination must be absolute: {}",
                    a[i + 2]
                );
            }
        }
    }
}
