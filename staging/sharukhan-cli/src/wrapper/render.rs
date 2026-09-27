//! Slot renderers: the kernel-specific parts of a derived wrapper, built from
//! the target's computed identity and the validated profile.
//!
//! Every value interpolated here was held to a grammar by `identity` (kernel
//! names: digits, dots, `-rc`, `[A-Za-z0-9-]`) or by `profile` via `escape`
//! (free text: no character its context would misread), and regex literals go
//! through `escape::re_escape`. There are no template tokens to forget.
//!
//! The emitted Python edits Photon's kernel specs at build time; its shape is
//! the contract with the base's `disable_unrebased_ranges`, which leaves
//! `Patch0`/`Patch1` and the single live line `%autopatch -p1 -m0 -M1`.
//! `derive` verifies the base still re-enables exactly that line before any of
//! this is used.

use super::base::Base;
use super::escape::re_escape;
use super::identity::{KernelRelease, Kind};
use super::profile::{KernelPatch, Mode, Profile};

/// The one `%autopatch` line the base leaves live; enablers anchor after it.
pub const LIVE_AUTOPATCH: &str = "%autopatch -p1 -m0 -M1";

/// Everything a renderer needs.
pub struct Ctx<'a> {
    pub target: &'a KernelRelease,
    pub base: &'a Base,
    pub profile: &'a Profile,
}

impl Ctx<'_> {
    fn tag(&self) -> String {
        self.target.tag()
    }
    fn token(&self) -> String {
        self.target.token()
    }
    fn kver(&self) -> String {
        self.target.rpm_version()
    }
    fn krel(&self) -> String {
        self.target.rpm_release(self.profile.rpm_release_iteration)
    }
}

fn lines(v: &[String]) -> String {
    let mut s = v.join("\n");
    s.push('\n');
    s
}

/// `# Photon OS 5.0 userland + experimental Linux 7.3-rc4 (mainline RC)`
pub fn header(c: &Ctx) -> String {
    lines(&[
        format!(
            "# Photon OS {} userland + experimental Linux {}{}",
            c.base.userland.full(),
            c.target.ksrc(),
            c.target.kind_suffix()
        ),
        format!("# wrapper v{}", c.profile.wrapper_version),
    ])
}

pub fn banner(c: &Ctx) -> String {
    lines(&[format!(
        "echo \"[{}] wrapper v{} (Linux {}, {})\"",
        c.tag(),
        c.profile.wrapper_version,
        c.target.ksrc(),
        c.profile.summary
    )])
}

/// The explanatory comment above the pin function, per release kind.
fn pin_comment(c: &Ctx) -> Vec<String> {
    let t = c.target;
    let (k, kv) = (t.ksrc(), c.kver());
    match t.kind {
        Kind::MainlineRc { rc } => vec![
            format!("# Pin linux.spec / linux-esx.spec to the {k} mainline tarball."),
            format!(
                "# RPM versions cannot contain \"-\": Version {kv}, Release 0.rc{rc}.N, and the"
            ),
            format!("# tarball directory (linux-{k}) lives in %define kernel_src. %prep blanks"),
            format!(
                "# EXTRAVERSION (-rc{rc}) so the kernel names itself {kv} + CONFIG_LOCALVERSION"
            ),
            "# (-%{release}), which equals uname_r = %{version}-%{release}. Idempotent.".into(),
        ],
        Kind::MainlineFinal => vec![
            format!("# Pin linux.spec / linux-esx.spec to the {k} mainline tarball."),
            format!("# The tarball directory (linux-{k}) differs from Version {kv}, so it lives"),
            format!("# in %define kernel_src. The kernel names itself {kv} + CONFIG_LOCALVERSION"),
            "# (-%{release}), which equals uname_r = %{version}-%{release}. Idempotent.".into(),
        ],
        Kind::Stable => vec![
            format!("# Pin linux.spec / linux-esx.spec to the {k} stable tarball."),
            "# Version equals the tarball directory, so %setup keeps linux-%{version}. The".into(),
            format!("# kernel names itself {kv} + CONFIG_LOCALVERSION (-%{{release}}), which"),
            "# equals uname_r = %{version}-%{release}. Idempotent.".into(),
        ],
    }
}

pub fn kernel_pin(c: &Ctx) -> String {
    let t = c.target;
    let (tag, k, kv, kr) = (c.tag(), t.ksrc(), c.kver(), c.krel());
    let native = &c.base.native_series;
    let mut v = pin_comment(c);
    v.extend([
        format!("{}() {{", t.pin_fn()),
        "  spec=\"$1\"".into(),
        "  [ -f \"$spec\" ] || return 1".into(),
        "  python3 - \"$spec\" << 'PY'".into(),
        "import re, sys".into(),
        "from pathlib import Path".into(),
        "p = Path(sys.argv[1])".into(),
        "t = p.read_text()".into(),
        "orig = t".into(),
        format!("KSRC, KVER, KREL = \"{k}\", \"{kv}\", \"{kr}\""),
        format!(
            "hdr = (\"# {} ({} userland)\\n\"",
            t.branch(),
            format_args!("Photon {}", c.base.userland.major)
        ),
        format!(
            "       \"# Upstream Linux {k} ({}), FIPS/canister OFF.\\n\"",
            t.kind_long()
        ),
        format!(
            "       \"# Only Patch0+Patch1 apply; {native}-era Photon patch ranges are skipped.\\n\")"
        ),
        "t = re.sub(r\"(?s)\\A# experimental/linux-[^\\n]*\\n(?:#[^\\n]*\\n){0,2}\", \"\", t)".into(),
        "t = hdr + t".into(),
        "t = t.replace(\"%global fips 1\", \"%global fips 0\", 1) if \"%global fips 1\" in t.split(\"%ifarch aarch64\")[0] else t".into(),
        "t = re.sub(r\"(?m)^Version:(\\s*)\\S+\", r\"Version:\\g<1>\" + KVER, t, count=1)".into(),
        "t = re.sub(r\"(?m)^Release:(\\s*)[^%\\s]+\", r\"Release:\\g<1>\" + KREL, t, count=1)".into(),
    ]);
    if t.needs_kernel_src() {
        v.extend([
            "if re.search(r\"(?m)^%define kernel_src \", t):".into(),
            "    t = re.sub(r\"(?m)^%define kernel_src .*$\", \"%define kernel_src \" + KSRC, t)".into(),
            "else:".into(),
            "    t = re.sub(r\"(?m)^(Version:.*\\n)\", r\"\\g<1>%define kernel_src \" + KSRC + \"\\n\", t, count=1)".into(),
        ]);
    }
    v.push(format!(
        "t = re.sub(r\"(?m)^Source0:(\\s*)\\S+\", r\"Source0:\\g<1>{}\", t, count=1)",
        t.source0()
    ));
    if t.needs_kernel_src() {
        v.push("t = t.replace(\"-n linux-%{version}\", \"-n linux-%{kernel_src}\")".into());
    }
    for d in &c.profile.drop_kernel_params {
        v.extend(d.reason.iter().map(|l| format!("# {l}")));
        v.push(format!(
            "t = re.sub(r\" {}(?=[ \\n])\", \"\", t)",
            re_escape(&d.param)
        ));
    }
    if let Some(extra) = t.extraversion() {
        v.extend([
            format!("mark = \"# {k}: blank EXTRAVERSION so uname -r equals uname_r\\n\""),
            "if mark not in t:".into(),
            format!(
                "    t, n = re.subn(r\"(?m)^(%setup -q -n linux-%\\{{{}\\}}\\n)\",",
                t.setup_macro()
            ),
            "                   r\"\\g<1>\" + mark + \"sed -i 's/^EXTRAVERSION = .*/EXTRAVERSION =/' Makefile\\n\", t, count=1)".into(),
            "    if n != 1:".into(),
            format!("        sys.exit(f\"[{tag}] ERROR: {{p}}: main %setup line not found\")"),
        ]);
        debug_assert!(extra.starts_with("-rc"));
    }
    v.extend([
        format!(
            "entry = \"* {} {} {kv}-{kr}\\n\"",
            c.profile.changelog.date, c.profile.changelog.author
        ),
        "if entry not in t and \"\\n%changelog\\n\" in t:".into(),
        "    t = t.replace(\"\\n%changelog\\n\", \"\\n%changelog\\n\" + entry +".into(),
        format!(
            "        \"- Experimental: Linux {k} {} from {}.\\n\"",
            t.kind_long(),
            t.source_host()
        ),
        format!(
            "        \"- FIPS canister off; Photon {} userland and {} dist tag unchanged.\\n\", 1)",
            c.base.userland.full(),
            c.base.userland.dist()
        ),
        "if t != orig:".into(),
        "    p.write_text(t)".into(),
        format!(
            "    print(f\"[{tag}] {{p}}: pinned to Linux {{KSRC}} (Version {{KVER}}, Release {{KREL}})\")"
        ),
        "else:".into(),
        format!("    print(f\"[{tag}] {{p}}: already pinned to Linux {{KSRC}}\")"),
        "PY".into(),
        "}".into(),
    ]);
    lines(&v)
}

pub fn kernel_pin_calls(c: &Ctx) -> String {
    let f = c.target.pin_fn();
    lines(&[
        format!("{f} SPECS/linux/linux.spec || exit 1"),
        format!("{f} SPECS/linux/linux-esx.spec || exit 1"),
    ])
}

pub fn kernel_sandbox_names(c: &Ctx) -> String {
    let kv = c.kver();
    lines(&[
        "    find \"$stage\" -maxdepth 4 -type d \\( \\".into(),
        format!("        -name 'linux-{kv}*' -o -name 'linux-esx-{kv}*' -o \\"),
        format!("        -name 'build-linux-{kv}*' -o -name 'build-linux-esx-{kv}*' \\"),
        "      \\) -print -exec rm -rf {} + 2>/dev/null || true".into(),
    ])
}

pub fn kernel_source(c: &Ctx) -> String {
    let t = c.target;
    let var = t.sha_var();
    lines(&[
        format!("{var}=\"{}\"", c.profile.source.sha512),
        "if command -v fetch_or_validate_source >/dev/null 2>&1; then".into(),
        "  fetch_or_validate_source \\".into(),
        format!("    \"{}\" \\", t.tarball()),
        format!("    \"{}\" \\", t.source_url()),
        format!("    \"${var}\" || true"),
        "fi".into(),
    ])
}

pub fn version_assert(c: &Ctx) -> String {
    let t = c.target;
    let kv = c.kver();
    let also = if t.needs_kernel_src() {
        format!(" ({})", t.ksrc())
    } else {
        String::new()
    };
    lines(&[
        format!("  if [ \"${{PIN_REQUIRE_KVER:-1}}\" = 1 ] && [ \"$kver\" != \"{kv}\" ]; then"),
        format!(
            "    echo \"[{}] ERROR: linux.spec Version is '$kver', expected {kv}{also}\" 1>&2",
            c.tag()
        ),
    ])
}

fn autopatch(n: u32) -> String {
    format!("%autopatch -p1 -m{n} -M{n}")
}

/// One kernel patch enabler: comment, shell function, calls.
fn kernel_patch(c: &Ctx, k: &KernelPatch) -> Vec<String> {
    let (tag, n) = (c.tag(), k.patch);
    let func = format!("enable_{}_{}", k.name, c.token());
    let mut v: Vec<String> = k.comment.iter().map(|l| format!("# {l}")).collect();
    v.extend([
        format!("{func}() {{"),
        "  spec=\"$1\"".into(),
        "  [ -f \"$spec\" ] || return 0".into(),
        "  python3 - \"$spec\" << 'PY'".into(),
        "import re, sys".into(),
        "from pathlib import Path".into(),
        "p = Path(sys.argv[1])".into(),
        "t = p.read_text()".into(),
        "orig = t".into(),
    ]);
    let patch_line = format!("Patch{n}: {}", k.file);
    match k.mode {
        Mode::Replace => {
            let replaces = k.replaces.as_deref().unwrap_or_default();
            v.extend([
                format!(
                    "t = re.sub(r\"(?m)^Patch{n}:(\\s*){}$\",",
                    re_escape(replaces)
                ),
                format!("           r\"Patch{n}:\\g<1>{}\", t)", k.file),
                format!(
                    "if not re.search(r\"(?m)^Patch{n}:\\s*{}$\", t):",
                    re_escape(&k.file)
                ),
                format!(
                    "    sys.exit(f\"[{tag}] ERROR: {{p}}: Patch{n} is not the {} {} patch\")",
                    c.target.ksrc(),
                    k.label
                ),
            ]);
        }
        Mode::Readd => {
            let var = format!("new{n}");
            v.extend([
                format!("{var} = \"{patch_line}\""),
                format!("t = re.sub(r\"(?m)^Patch{n}:.*$\\n\", \"\", t)"),
                format!(
                    "t, n = re.subn(r\"(?m)^(Patch1:.*\\n)\", r\"\\g<1>\" + {var} + \"\\n\", t, count=1)"
                ),
                "if n != 1:".into(),
                format!("    sys.exit(f\"[{tag}] ERROR: {{p}}: no Patch1 line to anchor Patch{n}\")"),
            ]);
        }
        Mode::Add => {
            v.extend([
                format!("line = \"{patch_line}\""),
                "if line not in t:".into(),
                "    t, n = re.subn(r\"(?m)^(Patch1:.*\\n)\", r\"\\g<1>\" + line + \"\\n\", t, count=1)".into(),
                "    if n != 1:".into(),
                format!(
                    "        sys.exit(f\"[{tag}] ERROR: {{p}}: no Patch1 line to anchor Patch{n}\")"
                ),
            ]);
        }
    }
    let first = autopatch(k.autopatch[0]);
    let inserts: String = k
        .autopatch
        .iter()
        .map(|r| format!("{}\\n", autopatch(*r)))
        .collect();
    v.push(format!("if \"\\n{first}\\n\" not in t:"));
    let anchor = format!("r\"(?m)^({LIVE_AUTOPATCH}\\n)\"");
    if k.autopatch.len() > 1 {
        v.push(format!("    t, n = re.subn({anchor},"));
        v.push(format!(
            "                   r\"\\g<1>{inserts}\", t, count=1)"
        ));
    } else {
        v.push(format!(
            "    t, n = re.subn({anchor}, r\"\\g<1>{inserts}\", t, count=1)"
        ));
    }
    v.extend([
        "    if n != 1:".into(),
        format!("        sys.exit(f\"[{tag}] ERROR: {{p}}: no live {LIVE_AUTOPATCH} line\")"),
        "if t != orig:".into(),
        "    p.write_text(t)".into(),
        format!("    print(f\"[{tag}] {{p}}: {}\")", k.applied),
        "else:".into(),
        format!("    print(f\"[{tag}] {{p}}: {}\")", k.already),
        "PY".into(),
        "}".into(),
    ]);
    for f in &k.flavours {
        v.push(format!("{func} {} || exit 1", f.spec()));
    }
    v
}

fn installer_patches(c: &Ctx) -> Option<Vec<String>> {
    let ip = c.profile.installer_patches.as_ref()?;
    let tag = c.tag();
    let func = format!("pin_installer_{}", c.token());
    let mut v: Vec<String> = ip.comment.iter().map(|l| format!("# {l}")).collect();
    v.extend([
        format!("{func}() {{"),
        "  spec=\"SPECS/photon-os-installer/photon-os-installer.spec\"".into(),
        "  [ -f \"$spec\" ] || return 0".into(),
        "  python3 - \"$spec\" << 'PY'".into(),
        "import re, sys".into(),
        "from pathlib import Path".into(),
        "p = Path(sys.argv[1])".into(),
        "t = p.read_text()".into(),
        "fixes = [".into(),
    ]);
    for p in &ip.patches {
        v.push(format!("    (\"{}\", \"{}\",", p.file, p.date));
        let last = p.changelog.len() - 1;
        for (i, l) in p.changelog.iter().enumerate() {
            let close = if i == last { ")," } else { "" };
            v.push(format!("     \"{l}\\n\"{close}"));
        }
    }
    v.extend([
        "]".into(),
        "for fname, date, entry in fixes:".into(),
        "    if fname in t:".into(),
        format!("        print(f\"[{tag}] {{p}}: {{fname}} already applied\")"),
        "        continue".into(),
        "    nums = [int(n) for n in re.findall(r\"(?m)^Patch(\\d+):\", t)]".into(),
        "    if not nums:".into(),
        format!("        sys.exit(f\"[{tag}] ERROR: {{p}}: no Patch lines\")"),
        "    last = max(nums)".into(),
        "    t, n = re.subn(rf\"(?m)^(Patch{last}:.*\\n)\", rf\"\\g<1>Patch{last + 1}: {fname}\\n\", t, count=1)".into(),
        "    m = re.search(r\"(?m)^(Release:\\s*)(\\d+)(%\\{\\?dist\\})\", t)".into(),
        "    if n != 1 or not m:".into(),
        format!("        sys.exit(f\"[{tag}] ERROR: {{p}}: cannot add {{fname}}\")"),
        "    rel = int(m.group(2)) + 1".into(),
        "    t = t[:m.start()] + f\"{m.group(1)}{rel}{m.group(3)}\" + t[m.end():]".into(),
        "    ver = re.search(r\"(?m)^Version:\\s*(\\S+)\", t).group(1)".into(),
        format!(
            "    t = t.replace(\"%changelog\\n\", f\"%changelog\\n* {{date}} {} \"",
            c.profile.changelog.author
        ),
        "                  f\"{ver}-{rel}\\n\" + entry, 1)".into(),
        format!("    print(f\"[{tag}] {{p}}: Patch{{last + 1}} {{fname}}, release {{ver}}-{{rel}}\")"),
        "p.write_text(t)".into(),
        "PY".into(),
        "}".into(),
        format!("{func} || exit 1"),
    ]);
    Some(v)
}

/// Kernel patch enablers, then the installer appender, in profile order.
pub fn kernel_patches(c: &Ctx) -> String {
    let mut v: Vec<String> = Vec::new();
    for k in &c.profile.kernel_patches {
        v.extend(kernel_patch(c, k));
    }
    if let Some(ip) = installer_patches(c) {
        if !v.is_empty() {
            v.push(String::new());
        }
        v.extend(ip);
    }
    if v.is_empty() {
        String::new()
    } else {
        lines(&v)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn autopatch_lines_are_formed_from_the_number() {
        assert_eq!(autopatch(7300), "%autopatch -p1 -m7300 -M7300");
    }
}
