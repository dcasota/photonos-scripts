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
pub fn volid(iso: &Path) -> Result<String, String> {
    let out = run("xorriso", &["-indev", &iso.to_string_lossy(), "-toc"])?;
    for line in out.lines() {
        if let Some(rest) = line.split_once("Volume id") {
            let v = rest.1.trim_start_matches([':', ' ']).trim();
            let v = v.trim_matches('\'').to_string();
            if !v.is_empty() {
                return Ok(v);
            }
        }
    }
    Err(format!("no volume id in the table of contents of {}", iso.display()))
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
    c.say(&format!("  writing {} ({} operations)", plan.output.display(), plan.map.len()));
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
        &["-indev", &iso.to_string_lossy(), "-report_el_torito", "plain"],
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
            "linux", "linux-devel", "linux-docs", "linux-drivers-gpu", "linux-drivers-sound",
            "linux-tools", "linux-python3-perf", "bpftool",
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
        p.map.push((PathBuf::from("/new/repodata"), "/RPMS/repodata".into()));
        p.map.push((PathBuf::from("/new/vmlinuz"), "/isolinux/vmlinuz".into()));
        p.map.push((PathBuf::from("/new/initrd.img"), "/isolinux/initrd.img".into()));
        p
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
        for s in ["linux", "linux-devel", "linux-tools", "bpftool", "linux-python3-perf"] {
            assert!(
                joined.contains(&format!("/RPMS/aarch64/{s}-6.12.109-3.ph5.aarch64.rpm")),
                "{s} is not removed"
            );
            assert!(
                joined.contains(&format!("/RPMS/aarch64/{s}-6.12.109-4.azure.ph5.aarch64.rpm")),
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
                assert!(terminated, "the {tok} list at {i} is not terminated by --: {a:?}");
            }
        }
        // and a plan with nothing to remove emits no dangling -rm at all
        let empty = IsoPlan { input: "/a".into(), output: "/b".into(), ..Default::default() };
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
                assert!(!a[i + 1].starts_with('-'), "source looks like a flag: {}", a[i + 1]);
                assert!(a[i + 2].starts_with('/'), "destination must be absolute: {}", a[i + 2]);
            }
        }
    }
}
