//! Embeds the kernel wrapper bases (src/embedded/kernel-base/*.sh), the
//! kernel profiles (profiles/kernel/*.json) and the systemd profiles
//! (profiles/systemd/*.json) into the binary, so a kernel
//! build needs no file beside it. The tables are generated from the
//! directories: a new profile or base is embedded by adding the file.

use std::fmt::Write as _;
use std::path::Path;

fn table(dir: &str, ext: &str, name: &str, out: &mut String) {
    println!("cargo:rerun-if-changed={dir}");
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let mut files: Vec<String> = std::fs::read_dir(root.join(dir))
        .unwrap_or_else(|e| panic!("{dir}: {e}"))
        .flatten()
        .filter_map(|e| e.file_name().to_str().map(str::to_string))
        .filter(|n| n.ends_with(ext))
        .collect();
    files.sort();
    writeln!(out, "pub const {name}: &[(&str, &str)] = &[").unwrap();
    for f in &files {
        let p = root.join(dir).join(f);
        println!("cargo:rerun-if-changed={}", p.display());
        writeln!(out, "    ({f:?}, include_str!({:?})),", p.display().to_string()).unwrap();
    }
    writeln!(out, "];").unwrap();
}

fn main() {
    let mut out = String::new();
    table("src/embedded/kernel-base", ".sh", "BASES", &mut out);
    table("profiles/kernel", ".json", "PROFILES", &mut out);
    table("profiles/systemd", ".json", "SYSTEMD_PROFILES", &mut out);
    let dest = Path::new(&std::env::var("OUT_DIR").unwrap()).join("embedded_kernel.rs");
    std::fs::write(dest, out).unwrap();
}
