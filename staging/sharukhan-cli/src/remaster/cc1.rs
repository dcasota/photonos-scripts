//! The native-cc1 accelerator, and the gate that decides whether it may be used.
//!
//! Under qemu-user the kernel compiles at roughly a tenth of native speed. An
//! x86_64-hosted cross `cc1`, built from the SAME gcc source the media's
//! compiler came from, removes most of that - but only if it produces the same
//! code. "Same compiler version" is not evidence: gcc's configure silently
//! disables SHF_MERGE, SHF_LINK_ORDER, CFI directives and LEB128 support when
//! it cannot find a target assembler, and the resulting cc1 emits different
//! code while reporting the same version.
//!
//! So the swap is GATED ON BYTE IDENTITY. Real kernel translation units that
//! the emulated compiler already built are recompiled with the native cc1 and
//! compared byte for byte. Any difference at all refuses the swap. This module
//! will take the slow path rather than ship a kernel it cannot prove.
//!
//! Only `-nostdinc` compiles are routed to it: that is the kernel and the
//! out-of-tree ENA/EFA/viomem modules. Userspace (perf, bpftool, host tools)
//! stays on the media's own compiler, and `as`/`ld` are never swapped - Photon
//! patches gas's DWARF output, so a different assembler would change the
//! objects even with an identical compiler.

use super::buildroot::chroot_capture;
use super::{ok, run, Ctx};
use std::fs;
use std::path::{Path, PathBuf};

/// How many translation units must come back identical before the swap is
/// allowed. Below this the sample is not evidence.
pub const MIN_IDENTICAL: usize = 5;

/// Translation units worth testing first: a scheduler core, memory
/// management, arch code, crypto, two filesystems, networking and a driver.
/// Chosen to span the code generation features that differ when a probe was
/// missed - CFI, LEB128, mergeable sections, atomics.
const PREFERRED: &[&str] = &[
    "kernel/sched/core.o",
    "mm/page_alloc.o",
    "arch/arm64/kernel/setup.o",
    "crypto/aes_generic.o",
    "fs/ext4/inode.o",
    "fs/xfs/xfs_trace.o",
    "net/ipv4/tcp.o",
    "net/core/dev.o",
    "mm/memcontrol.o",
    "lib/string.o",
    "drivers/hv/vmbus_drv.o",
    "drivers/scsi/storvsc_drv.o",
];

/// Where a built cross cc1 is looked for.
pub fn native_cc1(workdir: &Path) -> Option<PathBuf> {
    let p = workdir.join("xgcc/build/gcc/cc1");
    if p.is_file() {
        Some(p)
    } else {
        None
    }
}

/// The media compiler's cc1 directory, discovered rather than named: it
/// carries the gcc version (12.5.0 here, 12.2.0 on the previous media) and
/// hardcoding it silently disables the accelerator on the next ISO.
pub fn cc1_dir(br: &Path) -> Result<PathBuf, String> {
    let root = br.join("usr/libexec/gcc");
    let mut hits = Vec::new();
    for target in fs::read_dir(&root).map_err(|e| format!("{}: {e}", root.display()))?.flatten() {
        for ver in fs::read_dir(target.path()).into_iter().flatten().flatten() {
            if ver.path().join("cc1").is_file() {
                hits.push(ver.path());
            }
        }
    }
    match hits.len() {
        1 => Ok(hits.remove(0)),
        0 => Err(format!("no cc1 under {}", root.display())),
        _ => Err(format!(
            "{} cc1 installations under {}; which compiler the build uses is ambiguous",
            hits.len(),
            root.display()
        )),
    }
}

/// The compile command recorded for an object by kbuild, read from its `.cmd`
/// file: `savedcmd_<obj> := gcc ... -c -o <obj> <src>`.
pub fn recorded_command(kdir: &Path, obj: &str) -> Option<String> {
    let p = Path::new(obj);
    let dir = p.parent()?;
    let base = p.file_name()?.to_string_lossy().to_string();
    let cmd = kdir.join(dir).join(format!(".{base}.cmd"));
    let text = fs::read_to_string(cmd).ok()?;
    for line in text.lines() {
        for key in ["savedcmd_", "cmd_"] {
            if line.trim_start().starts_with(key) {
                if let Some((_, rhs)) = line.split_once(":=") {
                    let t = rhs.trim();
                    if t.starts_with("gcc ") {
                        return Some(t.to_string());
                    }
                }
            }
        }
    }
    None
}

/// The gcc invocation alone. A `.cmd` line can chain further steps after the
/// source file (objtool, sign-file), and running those against a scratch
/// object would touch the real build.
pub fn gcc_invocation(cmd: &str) -> Option<String> {
    let end = cmd.find(" ; ").or_else(|| cmd.find(" && ")).unwrap_or(cmd.len());
    let head = &cmd[..end];
    if !head.starts_with("gcc ") || !head.contains(" -c ") {
        return None;
    }
    Some(head.trim().to_string())
}

/// Rewrite a compile command to write somewhere else, and PROVE it.
///
/// The proof is the reason this is a function. One kernel `.cmd` records its
/// output as `arch/arm64/kvm/../../../virt/kvm/kvm_main.o`, and a naive
/// "replace the object path" substitution missed it and overwrote the real
/// build object. So: the `-o` token is taken from the command itself, and the
/// result is REJECTED if the original output path still appears anywhere in
/// it.
///
/// The dependency-file option is dropped too: `-Wp,-MMD,<path>` would rewrite
/// the build's own `.d` file as a side effect of a test.
pub fn rewrite_output(cmd: &str, new_out: &str) -> Result<String, String> {
    let marker = " -c -o ";
    let at = cmd
        .find(marker)
        .ok_or_else(|| format!("no ' -c -o ' in the recorded command: {cmd}"))?;
    let rest = &cmd[at + marker.len()..];
    let end = rest.find(' ').ok_or("the -o token has no argument")?;
    let old_out = &rest[..end];
    if old_out.is_empty() {
        return Err("the -o argument is empty".to_string());
    }
    let rewritten = format!(
        "{}{}{}{}",
        &cmd[..at],
        " -c -B /tmp/nativecc1/ -o ",
        new_out,
        &rest[end..]
    );
    // Strip the dependency-file option, wherever it sits.
    let rewritten: String = rewritten
        .split_whitespace()
        .filter(|t| !t.starts_with("-Wp,-MMD,"))
        .collect::<Vec<_>>()
        .join(" ");
    // The substitution has to be complete. If the old path survives anywhere,
    // the command can still write the real object.
    if rewritten.split_whitespace().any(|t| t == old_out) {
        return Err(format!(
            "output path substitution failed: {old_out} still appears in the rewritten \
             command, which would overwrite a real build object"
        ));
    }
    Ok(rewritten)
}

/// Objects to test: the preferred list, filtered to what exists, topped up
/// with the largest `-nostdinc` C objects, at most one per top-level directory.
pub fn pick_objects(kdir: &Path, want: usize) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for p in PREFERRED {
        if kdir.join(p).is_file() && recorded_command(kdir, p).is_some() {
            out.push((*p).to_string());
        }
        if out.len() >= want {
            return out;
        }
    }
    let mut cands: Vec<(u64, String)> = Vec::new();
    collect_objects(kdir, kdir, &mut cands, 0);
    cands.sort_unstable_by_key(|(size, _)| std::cmp::Reverse(*size));
    let mut seen_top: Vec<String> = Vec::new();
    for (_, rel) in cands {
        if out.len() >= want {
            break;
        }
        if out.contains(&rel) {
            continue;
        }
        let top = rel.split('/').next().unwrap_or("").to_string();
        if seen_top.contains(&top) {
            continue;
        }
        let Some(cmd) = recorded_command(kdir, &rel) else { continue };
        if !cmd.contains("-nostdinc") || !cmd.contains(".c") {
            continue;
        }
        seen_top.push(top);
        out.push(rel);
    }
    out
}

fn collect_objects(root: &Path, dir: &Path, out: &mut Vec<(u64, String)>, depth: usize) {
    if depth > 6 || out.len() > 4000 {
        return;
    }
    let Ok(rd) = fs::read_dir(dir) else { return };
    for e in rd.flatten() {
        let p = e.path();
        let name = e.file_name().to_string_lossy().to_string();
        if p.is_dir() {
            // scripts/ and tools/ are HOST programs: they are not compiled for
            // the target at all, so they prove nothing about the cross cc1.
            if matches!(name.as_str(), "scripts" | "tools" | "Documentation" | ".git") {
                continue;
            }
            collect_objects(root, &p, out, depth + 1);
            continue;
        }
        if !name.ends_with(".o") || name.ends_with(".mod.o") || name.starts_with("built-in") {
            continue;
        }
        let Ok(md) = e.metadata() else { continue };
        if md.len() < 40_000 {
            continue;
        }
        let Ok(rel) = p.strip_prefix(root) else { continue };
        out.push((md.len(), rel.to_string_lossy().to_string()));
    }
}

/// The result of the gate, as evidence rather than a boolean.
#[derive(Debug, Clone)]
pub struct GateResult {
    pub identical: Vec<(String, u64)>,
    pub different: Vec<String>,
    pub failed: Vec<String>,
}

impl GateResult {
    /// The swap is allowed only on a clean sweep: no differences, no failures,
    /// and enough samples to mean something.
    pub fn passed(&self) -> bool {
        self.different.is_empty()
            && self.failed.is_empty()
            && self.identical.len() >= MIN_IDENTICAL
    }
    pub fn summary(&self) -> String {
        format!(
            "identical={} different={} failed={} (need >= {MIN_IDENTICAL} and zero of the others)",
            self.identical.len(),
            self.different.len(),
            self.failed.len()
        )
    }
}

/// Recompile real kernel objects with the native cc1 and compare byte for byte.
///
/// The reference is the object the EMULATED compiler already produced in this
/// very build - not a fresh emulated recompile - so the comparison is against
/// what actually went into the kernel.
pub fn gate(c: &mut Ctx, kdir_host: &Path, kdir_in_root: &str) -> Result<GateResult, String> {
    let br = c.spec.buildroot();
    let native = native_cc1(&c.spec.workdir)
        .ok_or("no native cross cc1 has been built; nothing to gate")?;

    fs::create_dir_all(br.join("usr/local/bin")).map_err(|e| format!("{e}"))?;
    fs::copy(&native, br.join("usr/local/bin/cc1-native-x86_64"))
        .map_err(|e| format!("installing the native cc1: {e}"))?;
    run("chmod", &["755", &br.join("usr/local/bin/cc1-native-x86_64").to_string_lossy()])?;
    // The driver searches -B before its own libexec, so this is how the native
    // cc1 gets selected without touching the installed compiler.
    let bdir = br.join("tmp/nativecc1");
    fs::create_dir_all(&bdir).map_err(|e| format!("{e}"))?;
    let _ = fs::remove_file(bdir.join("cc1"));
    std::os::unix::fs::symlink("/usr/local/bin/cc1-native-x86_64", bdir.join("cc1"))
        .map_err(|e| format!("linking the native cc1: {e}"))?;

    let objs = pick_objects(kdir_host, 10);
    if objs.len() < MIN_IDENTICAL {
        return Err(format!(
            "only {} built objects are available to test; the gate needs at least \
             {MIN_IDENTICAL} and will not certify the compiler on fewer",
            objs.len()
        ));
    }
    c.say(&format!("  byte-identity gate over {} translation units", objs.len()));

    let mut r = GateResult { identical: vec![], different: vec![], failed: vec![] };
    for obj in objs {
        let Some(full) = recorded_command(kdir_host, &obj) else {
            r.failed.push(format!("{obj}: no recorded command"));
            continue;
        };
        let Some(gcc) = gcc_invocation(&full) else {
            r.failed.push(format!("{obj}: the recorded command is not a plain gcc compile"));
            continue;
        };
        let nat = "/tmp/eq-nat.o";
        let cmd = match rewrite_output(&gcc, nat) {
            Ok(x) => x,
            Err(e) => {
                r.failed.push(format!("{obj}: {e}"));
                continue;
            }
        };
        let _ = fs::remove_file(br.join("tmp/eq-nat.o"));
        // argv, not a shell string: the command is data from the build tree.
        let argv: Vec<String> = cmd.split_whitespace().map(str::to_string).collect();
        let mut full_argv: Vec<&str> = vec!["/usr/bin/env", "-C", kdir_in_root];
        full_argv.extend(argv.iter().map(|s| s.as_str()));
        if chroot_capture(&br, &full_argv).is_err() {
            r.failed.push(format!("{obj}: the native compile failed"));
            continue;
        }
        let reference = kdir_host.join(&obj);
        let produced = br.join("tmp/eq-nat.o");
        if !produced.is_file() {
            r.failed.push(format!("{obj}: the native compile produced no object"));
            continue;
        }
        let (a, b) = (fs::read(&reference), fs::read(&produced));
        match (a, b) {
            (Ok(a), Ok(b)) if a == b => {
                c.say(&format!("    IDENTICAL {obj} ({} bytes)", a.len()));
                r.identical.push((obj, a.len() as u64));
            }
            (Ok(a), Ok(b)) => {
                c.say(&format!("    DIFFERENT {obj} ({} vs {} bytes)", a.len(), b.len()));
                r.different.push(obj);
            }
            _ => r.failed.push(format!("{obj}: could not read both objects")),
        }
    }
    c.say(&format!("  gate: {}", r.summary()));
    Ok(r)
}

/// The wrapper that routes only `-nostdinc` compiles to the native cc1.
///
/// A script rather than a symlink because the decision is per invocation:
/// perf, bpftool and the host tools in the same build must keep using the
/// media's own compiler, and they are distinguished by exactly this flag.
pub fn wrapper_script(dir: &str) -> String {
    format!(
        "#!/bin/sh\n\
         # Installed by sharukhan remaster after the byte-identity gate passed.\n\
         # Kernel and out-of-tree module compiles (-nostdinc) go to the native\n\
         # cross cc1; everything else stays on Photon's emulated one.\n\
         for a in \"$@\"; do\n\
         \x20 if [ \"$a\" = \"-nostdinc\" ]; then exec {dir}/cc1.native \"$@\"; fi\n\
         done\n\
         exec {dir}/cc1.photon \"$@\"\n"
    )
}

/// Install the wrapper. Only ever called after `GateResult::passed()`.
pub fn swap(c: &mut Ctx, r: &GateResult) -> Result<(), String> {
    if !r.passed() {
        return Err(format!(
            "refusing to swap in the native compiler: {}. The emulated compiler is slower \
             but is the one the media was built with.",
            r.summary()
        ));
    }
    let br = c.spec.buildroot();
    let dir = cc1_dir(&br)?;
    let dirs = dir.to_string_lossy().to_string();
    let in_root = dirs
        .strip_prefix(&br.to_string_lossy().to_string())
        .unwrap_or(&dirs)
        .to_string();
    if !dir.join("cc1.photon").exists() {
        fs::rename(dir.join("cc1"), dir.join("cc1.photon"))
            .map_err(|e| format!("setting the original cc1 aside: {e}"))?;
    }
    let native = native_cc1(&c.spec.workdir).ok_or("the native cc1 disappeared")?;
    fs::copy(&native, dir.join("cc1.native")).map_err(|e| format!("{e}"))?;
    fs::write(dir.join("cc1"), wrapper_script(&in_root)).map_err(|e| format!("{e}"))?;
    run("chmod", &["755", &dir.join("cc1").to_string_lossy(), &dir.join("cc1.native").to_string_lossy()])?;
    c.say(&format!(
        "  native cc1 wrapper installed in {} ({} identical TUs)",
        dir.display(),
        r.identical.len()
    ));
    Ok(())
}

/// Put the media's own compiler back. Always safe to call.
pub fn unswap(c: &mut Ctx) -> Result<(), String> {
    let br = c.spec.buildroot();
    let Ok(dir) = cc1_dir(&br) else { return Ok(()) };
    if dir.join("cc1.photon").exists() {
        let _ = fs::remove_file(dir.join("cc1"));
        fs::rename(dir.join("cc1.photon"), dir.join("cc1"))
            .map_err(|e| format!("restoring the original cc1: {e}"))?;
        let _ = fs::remove_file(dir.join("cc1.native"));
        c.say("  restored the media's own cc1");
    }
    Ok(())
}

/// Whether a native cc1 is available at all, for reporting before the build.
pub fn available(workdir: &Path) -> bool {
    native_cc1(workdir).map(|p| ok("file", &[&p.to_string_lossy()])).unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    const KVM: &str = "gcc -Wp,-MMD,arch/arm64/kvm/.kvm_main.o.d -nostdinc -I./arch/arm64/include \
                       -c -o arch/arm64/kvm/../../../virt/kvm/kvm_main.o ../../../virt/kvm/kvm_main.c";

    /// The substitution must take the `-o` token FROM THE COMMAND. This exact
    /// command - a relative path that climbs out of its own directory - is the
    /// one that defeated a naive replacement and overwrote a real build object.
    #[test]
    fn the_output_rewrite_takes_the_actual_o_token_and_proves_it_is_gone() {
        let out = rewrite_output(KVM, "/tmp/eq-nat.o").unwrap();
        assert!(out.contains("-o /tmp/eq-nat.o"), "{out}");
        assert!(
            !out.contains("arch/arm64/kvm/../../../virt/kvm/kvm_main.o"),
            "the real object path must not survive: {out}"
        );
        // the source file is untouched - only the OUTPUT moved
        assert!(out.contains("../../../virt/kvm/kvm_main.c"), "{out}");
        // and the native cc1 is selected by -B
        assert!(out.contains("-B /tmp/nativecc1/"), "{out}");
    }

    /// Rewriting must never leave the build's own dependency file as a target,
    /// or a test run silently rewrites the build's `.d` files.
    #[test]
    fn the_dependency_file_option_is_dropped_from_a_test_compile() {
        let out = rewrite_output(KVM, "/tmp/eq-nat.o").unwrap();
        assert!(!out.contains("-Wp,-MMD"), "{out}");
    }

    #[test]
    fn a_command_without_an_output_token_is_refused_rather_than_guessed() {
        let e = rewrite_output("gcc -nostdinc foo.c", "/tmp/x.o").unwrap_err();
        assert!(e.contains("-c -o"), "{e}");
    }

    /// A `.cmd` line can chain further steps after the source file. Running
    /// those against a scratch object would touch the real build.
    #[test]
    fn only_the_gcc_invocation_is_taken_from_a_chained_command_line() {
        let chained = format!("{KVM} ; ./tools/objtool/objtool orc generate kvm_main.o");
        let got = gcc_invocation(&chained).unwrap();
        assert!(!got.contains("objtool"), "{got}");
        assert!(got.ends_with("kvm_main.c"), "{got}");
        // a line that is not a compile at all yields nothing
        assert!(gcc_invocation("ld -r -o built-in.a foo.o").is_none());
    }

    /// The gate is a gate. Anything short of a clean sweep must refuse, and
    /// the negative controls are the whole reason it is trustworthy.
    #[test]
    fn the_gate_refuses_the_swap_on_any_difference_or_too_small_a_sample() {
        let ident = |n: usize| -> Vec<(String, u64)> {
            (0..n).map(|i| (format!("o{i}.o"), 100_000)).collect()
        };
        let pass = GateResult { identical: ident(10), different: vec![], failed: vec![] };
        assert!(pass.passed());

        // one differing object refuses the whole swap
        let diff = GateResult {
            identical: ident(9),
            different: vec!["mm/page_alloc.o".into()],
            failed: vec![],
        };
        assert!(!diff.passed(), "a single difference must refuse the swap");

        // a compile that did not run is not evidence of agreement
        let failed = GateResult { identical: ident(9), different: vec![], failed: vec!["x".into()] };
        assert!(!failed.passed());

        // too few samples, even all identical, is not evidence
        let thin = GateResult { identical: ident(MIN_IDENTICAL - 1), different: vec![], failed: vec![] };
        assert!(!thin.passed());
        assert!(thin.summary().contains("identical=4"), "{}", thin.summary());
    }

    /// Only `-nostdinc` compiles may reach the native compiler. perf and
    /// bpftool are built in the same rpmbuild and must keep using the media's
    /// own compiler.
    #[test]
    fn the_wrapper_routes_only_nostdinc_compiles_to_the_native_compiler() {
        let s = wrapper_script("/usr/libexec/gcc/aarch64-unknown-linux-gnu/12.5.0");
        assert!(s.starts_with("#!/bin/sh"), "{s}");
        assert!(s.contains("\"$a\" = \"-nostdinc\""), "{s}");
        // the fallback is the LAST line, so anything that is not a kernel
        // compile ends up on the emulated compiler
        let last = s.lines().last().unwrap();
        assert!(last.contains("cc1.photon"), "{last}");
        assert!(s.contains("cc1.native"), "{s}");
        // the version-bearing directory is substituted, never hardcoded
        assert!(s.contains("12.5.0"), "{s}");
    }

    /// Host programs under scripts/ and tools/ are not compiled for the target
    /// at all, so they prove nothing about a cross compiler.
    #[test]
    fn host_tool_objects_are_never_chosen_as_evidence() {
        let d = std::env::temp_dir().join(format!("shk-cc1pick-{}", std::process::id()));
        for sub in ["scripts", "tools/perf", "kernel/sched"] {
            fs::create_dir_all(d.join(sub)).unwrap();
        }
        let big = vec![0u8; 80_000];
        for f in ["scripts/big.o", "tools/perf/big.o", "kernel/sched/core.o"] {
            fs::write(d.join(f), &big).unwrap();
        }
        // only the kernel object gets a plausible .cmd
        fs::write(
            d.join("kernel/sched/.core.o.cmd"),
            "savedcmd_kernel/sched/core.o := gcc -nostdinc -c -o kernel/sched/core.o core.c\n",
        )
        .unwrap();
        for f in ["scripts/.big.o.cmd", "tools/perf/.big.o.cmd"] {
            fs::write(d.join(f), "savedcmd_x := gcc -c -o big.o big.c\n").unwrap();
        }
        let picked = pick_objects(&d, 10);
        assert!(picked.contains(&"kernel/sched/core.o".to_string()), "{picked:?}");
        assert!(
            !picked.iter().any(|p| p.starts_with("scripts/") || p.starts_with("tools/")),
            "host objects must never be evidence: {picked:?}"
        );
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn the_recorded_command_is_read_out_of_the_kbuild_cmd_file() {
        let d = std::env::temp_dir().join(format!("shk-cc1cmd-{}", std::process::id()));
        fs::create_dir_all(d.join("mm")).unwrap();
        fs::write(
            d.join("mm/.page_alloc.o.cmd"),
            "savedcmd_mm/page_alloc.o := gcc -nostdinc -c -o mm/page_alloc.o mm/page_alloc.c\n\
             source_mm/page_alloc.o := mm/page_alloc.c\n",
        )
        .unwrap();
        let got = recorded_command(&d, "mm/page_alloc.o").unwrap();
        assert!(got.starts_with("gcc "), "{got}");
        assert!(got.contains("page_alloc.c"), "{got}");
        assert!(recorded_command(&d, "mm/nonexistent.o").is_none());
        let _ = fs::remove_dir_all(&d);
    }
}
