//! Kconfig as data: the Hyper-V fragment, a tristate parser, the dependency
//! closure a fragment implies, and the IKCONFIG blob inside a built kernel.
//!
//! The reason this is a module rather than three greps is that a tristate
//! symbol cannot be `y` unless every symbol it depends on is `y`. Writing
//! `CONFIG_HYPERV_UTILS=y` into a config where `CONFIG_CONNECTOR=m` does not
//! fail - `olddefconfig` silently demotes it back to `m`, and the only visible
//! consequence is a kernel that cannot find VMBus devices in the installer.
//! So the fragment carries the symbols that were ASKED FOR, and the enabling
//! symbols are computed from the config at hand and REPORTED.
//!
//! Which symbols cap which is read from the kernel's own Kconfig - encoded
//! here as edges, because parsing the whole Kconfig language to learn three
//! edges would be a worse bargain than stating them and then PROVING the
//! result. The proof is `assert_all_y` after `olddefconfig`: if an edge here
//! is wrong or the kernel moved, the target comes back below `y` and the build
//! stops naming the symbol. That assertion is not optional anywhere in this
//! crate, which is what keeps the table honest.

use std::collections::BTreeMap;

/// The seven symbols the parameter exists to turn on, compiled in.
///
/// `include_str!` rather than a literal so the file is readable as a Kconfig
/// fragment and can be diffed against one; there is no file to go missing.
pub const HYPERV_FRAGMENT: &str = include_str!("embedded/hyperv.fragment");

/// A tristate value. Ordered, because "at least m" and "below y" are the two
/// questions asked of it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Tristate {
    N,
    M,
    Y,
}

impl Tristate {
    pub fn as_str(self) -> &'static str {
        match self {
            Tristate::N => "n",
            Tristate::M => "m",
            Tristate::Y => "y",
        }
    }
}

/// One symbol's value in a `.config`.
///
/// `Unset` is NOT `No`, and the distinction is load-bearing: `# CONFIG_X is
/// not set` means the symbol was considered and left off, while an absent line
/// means it was never visible at all (its dependencies are unmet). Collapsing
/// them loses the difference between "turn it on" and "you cannot turn it on
/// from here", which is exactly what the closure has to tell apart.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Value {
    /// `# CONFIG_X is not set`
    Unset,
    Tri(Tristate),
    /// A string or integer value, kept verbatim: `CONFIG_LOCALVERSION="-3.ph5"`.
    Other(String),
}

impl Value {
    pub fn tristate(&self) -> Option<Tristate> {
        match self {
            Value::Tri(t) => Some(*t),
            Value::Unset => Some(Tristate::N),
            Value::Other(_) => None,
        }
    }
    pub fn render(&self, sym: &str) -> String {
        match self {
            Value::Unset => format!("# CONFIG_{sym} is not set"),
            Value::Tri(t) => format!("CONFIG_{sym}={}", t.as_str()),
            Value::Other(s) => format!("CONFIG_{sym}={s}"),
        }
    }
}

/// A parsed `.config`, keyed by symbol name WITHOUT the `CONFIG_` prefix.
///
/// Stripping the prefix at the boundary means no caller has to remember which
/// convention a given function speaks, which is a real source of silently
/// empty lookups.
#[derive(Debug, Clone, Default)]
pub struct Kconfig {
    map: BTreeMap<String, Value>,
}

impl Kconfig {
    pub fn parse(text: &str) -> Kconfig {
        let mut map = BTreeMap::new();
        for line in text.lines() {
            let t = line.trim();
            if t.is_empty() {
                continue;
            }
            // `# CONFIG_X is not set` is a VALUE, not a comment, and it is the
            // only comment form that carries one.
            if let Some(rest) = t.strip_prefix("# CONFIG_") {
                if let Some(sym) = rest.strip_suffix(" is not set") {
                    map.insert(sym.to_string(), Value::Unset);
                }
                continue;
            }
            if t.starts_with('#') {
                continue;
            }
            let Some(rest) = t.strip_prefix("CONFIG_") else {
                continue;
            };
            let Some((sym, val)) = rest.split_once('=') else {
                continue;
            };
            let v = match val {
                "y" => Value::Tri(Tristate::Y),
                "m" => Value::Tri(Tristate::M),
                "n" => Value::Tri(Tristate::N),
                other => Value::Other(other.to_string()),
            };
            map.insert(sym.to_string(), v);
        }
        Kconfig { map }
    }

    /// `None` means the symbol has no line at all - not that it is off.
    pub fn get(&self, sym: &str) -> Option<&Value> {
        self.map.get(sym.trim_start_matches("CONFIG_"))
    }

    /// The tristate value, treating an absent line as `n`: an invisible symbol
    /// is off in the built kernel, whatever the reason.
    pub fn tri(&self, sym: &str) -> Tristate {
        self.get(sym)
            .and_then(|v| v.tristate())
            .unwrap_or(Tristate::N)
    }

    pub fn is_y(&self, sym: &str) -> bool {
        self.tri(sym) == Tristate::Y
    }

    pub fn len(&self) -> usize {
        self.map.len()
    }

    pub fn is_empty(&self) -> bool {
        self.map.is_empty()
    }

    /// How the symbol reads in the file, for an error message that an operator
    /// can act on. "MISSING" rather than a guess when there is no line.
    pub fn describe(&self, sym: &str) -> String {
        let s = sym.trim_start_matches("CONFIG_");
        match self.get(s) {
            Some(v) => v.render(s),
            None => format!("CONFIG_{s} MISSING"),
        }
    }
}

/// The symbols a fragment asks for, in file order.
///
/// Parsed from the fragment text rather than duplicated as a constant, so the
/// file and the code cannot disagree about what is being requested.
pub fn fragment_symbols(fragment: &str) -> Vec<(String, Tristate)> {
    let mut out = Vec::new();
    for line in fragment.lines() {
        let t = line.trim();
        if t.is_empty() || t.starts_with('#') {
            continue;
        }
        let Some(rest) = t.strip_prefix("CONFIG_") else {
            continue;
        };
        let Some((sym, val)) = rest.split_once('=') else {
            continue;
        };
        let tri = match val {
            "y" => Tristate::Y,
            "m" => Tristate::M,
            "n" => Tristate::N,
            _ => continue,
        };
        out.push((sym.to_string(), tri));
    }
    out
}

/// How a dependency constrains its dependent.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Rule {
    /// `depends on X` where X is a tristate or bool: the dependent can only be
    /// `y` when X is `y`.
    MustBeY,
    /// The `(m || X != m)` idiom: the dependent may always be `m`, but can only
    /// be `y` when X is not `m`. HYPERV_STORAGE depends on SCSI_FC_ATTRS this
    /// way, which is why a stock config caps it at `m` with no error anywhere.
    MustNotBeM,
}

/// One `depends on` edge that can hold a fragment symbol below `y`.
#[derive(Debug, Clone, Copy)]
pub struct Edge {
    pub dependent: &'static str,
    pub dependency: &'static str,
    pub rule: Rule,
}

/// The edges that matter for the Hyper-V fragment, from the kernel's Kconfig.
///
/// Only symbols that can REALISTICALLY be below `y` in a Photon config are
/// listed; a bool that is `y` everywhere (SYSFS, PCI_MSI) would add noise
/// without adding a decision. Anything missed here is caught by
/// `assert_all_y`, not shipped.
///
/// Read from 6.12 (drivers/hv/Kconfig, net/vmw_vsock/Kconfig,
/// drivers/scsi/Kconfig, drivers/pci/Kconfig). Note that PCI_MSI_IRQ_DOMAIN,
/// which 6.1 listed under PCI_HYPERV, no longer exists in 6.12 - which is why
/// this table is per-edge and re-checked rather than copied from the 6.1 note.
pub const HYPERV_EDGES: &[Edge] = &[
    Edge {
        dependent: "HYPERV",
        dependency: "ACPI",
        rule: Rule::MustBeY,
    },
    Edge {
        dependent: "HYPERV_UTILS",
        dependency: "CONNECTOR",
        rule: Rule::MustBeY,
    },
    Edge {
        dependent: "HYPERV_UTILS",
        dependency: "NLS",
        rule: Rule::MustBeY,
    },
    Edge {
        dependent: "HYPERV_UTILS",
        dependency: "PTP_1588_CLOCK_OPTIONAL",
        rule: Rule::MustBeY,
    },
    Edge {
        dependent: "HYPERV_STORAGE",
        dependency: "SCSI",
        rule: Rule::MustBeY,
    },
    Edge {
        dependent: "HYPERV_STORAGE",
        dependency: "SCSI_FC_ATTRS",
        rule: Rule::MustNotBeM,
    },
    Edge {
        dependent: "HYPERV_VSOCKETS",
        dependency: "VSOCKETS",
        rule: Rule::MustBeY,
    },
];

/// A symbol the closure had to raise, and why. Printed, recorded and asserted -
/// a config change nobody can enumerate afterwards is not reviewable.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Forced {
    pub symbol: String,
    pub from: Value,
    pub to: Tristate,
    /// The fragment symbol that would otherwise be capped.
    pub because: String,
}

impl Forced {
    pub fn line(&self) -> String {
        format!(
            "CONFIG_{}: {} -> {} (else CONFIG_{} cannot be y)",
            self.symbol,
            match &self.from {
                Value::Unset => "not set".to_string(),
                Value::Tri(t) => t.as_str().to_string(),
                Value::Other(s) => s.clone(),
            },
            self.to.as_str(),
            self.because
        )
    }
}

/// Every enabling symbol that must be raised for `fragment` to survive
/// `olddefconfig` against `cfg`, computed from the config at hand.
///
/// Iterative, because raising a symbol can expose the next edge: the loop is
/// bounded by the edge count, so a cycle cannot hang a build.
///
/// A dependency that CANNOT be raised - no line at all, meaning its own
/// dependencies are unmet - is an error carrying the Kconfig evidence, not a
/// silent omission that surfaces as a demoted symbol hours later.
pub fn dependency_closure(
    cfg: &Kconfig,
    fragment: &str,
    edges: &[Edge],
) -> Result<Vec<Forced>, String> {
    let wanted: BTreeMap<String, Tristate> = fragment_symbols(fragment).into_iter().collect();
    let mut forced: Vec<Forced> = Vec::new();
    let mut raised: BTreeMap<String, Tristate> = BTreeMap::new();

    // Bounded by the number of edges: each pass can only add an edge that was
    // not satisfied before, so at most one pass per edge plus one to settle.
    for _ in 0..=edges.len() {
        let mut added = false;
        for e in edges {
            // Only edges under a symbol this fragment actually asks to be `y`.
            if wanted.get(e.dependent) != Some(&Tristate::Y) {
                continue;
            }
            let current = raised
                .get(e.dependency)
                .copied()
                .unwrap_or_else(|| cfg.tri(e.dependency));
            let satisfied = match e.rule {
                Rule::MustBeY => current == Tristate::Y,
                Rule::MustNotBeM => current != Tristate::M,
            };
            if satisfied {
                continue;
            }
            // A symbol with no line at all is not raisable from a fragment:
            // olddefconfig would drop the line again because the symbol is not
            // visible. Say which symbol and what was expected.
            if cfg.get(e.dependency).is_none() {
                return Err(format!(
                    "CONFIG_{} must be {} for CONFIG_{} to be y, but it has no line in this \
                     config at all - its own dependencies are unmet, so the fragment cannot \
                     raise it. Kconfig evidence: CONFIG_{} is {}",
                    e.dependency,
                    match e.rule {
                        Rule::MustBeY => "y",
                        Rule::MustNotBeM => "y or n (not m)",
                    },
                    e.dependent,
                    e.dependency,
                    cfg.describe(e.dependency)
                ));
            }
            forced.push(Forced {
                symbol: e.dependency.to_string(),
                from: cfg.get(e.dependency).cloned().unwrap_or(Value::Unset),
                to: Tristate::Y,
                because: e.dependent.to_string(),
            });
            raised.insert(e.dependency.to_string(), Tristate::Y);
            added = true;
        }
        if !added {
            return Ok(forced);
        }
    }
    Err(format!(
        "the dependency closure did not settle in {} passes; the edge table has a cycle",
        edges.len() + 1
    ))
}

/// The fragment plus its computed closure, as a Kconfig fragment ready to be
/// fed to `scripts/config`. Dependencies first: a reader should see WHY the
/// enabling symbols are there before the symbols that need them.
pub fn merged_fragment(fragment: &str, forced: &[Forced]) -> String {
    let mut out = String::new();
    if !forced.is_empty() {
        out.push_str("# Computed dependency closure for this config:\n");
        for f in forced {
            out.push_str(&format!("# {}\n", f.line()));
        }
        for f in forced {
            out.push_str(&format!("CONFIG_{}={}\n", f.symbol, f.to.as_str()));
        }
        out.push('\n');
    }
    for line in fragment.lines() {
        out.push_str(line);
        out.push('\n');
    }
    out
}

/// Every symbol a finished config must carry as `=y`: the fragment's own plus
/// the closure's. This is the list the verify step reads back off the ISO.
pub fn expected_y(fragment: &str, forced: &[Forced]) -> Vec<String> {
    let mut v: Vec<String> = fragment_symbols(fragment)
        .into_iter()
        .filter(|(_, t)| *t == Tristate::Y)
        .map(|(s, _)| s)
        .collect();
    for f in forced {
        if !v.contains(&f.symbol) {
            v.push(f.symbol.clone());
        }
    }
    v
}

/// Set every named symbol to `=y` in a config file's TEXT, in place.
///
/// Used by the build cascade, where there is no prepared kernel tree to run
/// `olddefconfig` in. A line that exists is rewritten where it stands - both
/// the `CONFIG_X=m` and the `# CONFIG_X is not set` forms - so the file keeps
/// its Kconfig ordering and stays reviewable as a diff. A symbol with no line
/// at all is appended, which is the only case that can move.
///
/// This is a TEXTUAL merge and does not pretend to be `olddefconfig`. Photon's
/// own `check_for_config_applicability.inc` runs `olddefconfig` during `%prep`
/// and fails the build if the result is not a fixed point, so a merge that
/// produced an inconsistent config is caught there rather than shipped. The
/// remaster path does the `olddefconfig` round trip itself, up front.
pub fn apply_to_config(text: &str, syms: &[String]) -> String {
    let mut out = String::with_capacity(text.len() + syms.len() * 24);
    let mut placed: Vec<&str> = Vec::new();
    for line in text.lines() {
        let t = line.trim();
        let name = if let Some(rest) = t.strip_prefix("# CONFIG_") {
            rest.strip_suffix(" is not set")
        } else {
            t.strip_prefix("CONFIG_")
                .and_then(|r| r.split_once('=').map(|(s, _)| s))
        };
        match name.and_then(|n| syms.iter().find(|s| s.as_str() == n)) {
            Some(s) => {
                out.push_str(&format!("CONFIG_{s}=y\n"));
                placed.push(s.as_str());
            }
            None => {
                out.push_str(line);
                out.push('\n');
            }
        }
    }
    let missing: Vec<&String> = syms
        .iter()
        .filter(|s| !placed.contains(&s.as_str()))
        .collect();
    if !missing.is_empty() {
        out.push_str("\n# Added by sharukhan --hyperv (no line existed for these):\n");
        for s in missing {
            out.push_str(&format!("CONFIG_{s}=y\n"));
        }
    }
    out
}

/// Assert every named symbol is `=y` in `cfg`, naming each one that is not and
/// how it actually reads.
///
/// This is the check that keeps `HYPERV_EDGES` honest. It runs after
/// `olddefconfig`, which is the only authority on what a config really means.
pub fn assert_all_y(cfg: &Kconfig, syms: &[String]) -> Result<(), String> {
    let bad: Vec<String> = syms
        .iter()
        .filter(|s| !cfg.is_y(s))
        .map(|s| cfg.describe(s))
        .collect();
    if bad.is_empty() {
        return Ok(());
    }
    Err(format!(
        "{} of {} symbols did not survive olddefconfig as =y: {}. A tristate cannot be y \
         unless every symbol it depends on is y, so this names a dependency the closure \
         did not raise.",
        bad.len(),
        syms.len(),
        bad.join(", ")
    ))
}

// ---------------------------------------------------------------------------
// IKCONFIG: the config the kernel was actually built with, read from the image
// ---------------------------------------------------------------------------

const IKCFG_ST: &[u8] = b"IKCFG_ST";
const IKCFG_ED: &[u8] = b"IKCFG_ED";

fn find(hay: &[u8], needle: &[u8], from: usize) -> Option<usize> {
    if needle.is_empty() || hay.len() < needle.len() {
        return None;
    }
    (from..=hay.len() - needle.len()).find(|&i| &hay[i..i + needle.len()] == needle)
}

/// The `.config` embedded in a kernel image by `CONFIG_IKCONFIG`.
///
/// A Rust port of `scripts/extract-ikconfig` for the case that matters here:
/// arm64 `Image` is uncompressed, so the blob is directly in the file between
/// the `IKCFG_ST` and `IKCFG_ED` markers, gzip-compressed.
///
/// A kernel WITHOUT ikconfig is an error, never an empty config. An empty
/// config would make every symbol assertion vacuously fail - or, worse, make a
/// "no symbols missing" answer possible from a file that was never read.
pub fn extract_ikconfig(image: &[u8]) -> Result<String, String> {
    let st = find(image, IKCFG_ST, 0).ok_or_else(|| {
        format!(
            "no IKCFG_ST marker in this {}-byte image: it was built without CONFIG_IKCONFIG, \
             or it is compressed (x86 bzImage) rather than a flat arm64 Image",
            image.len()
        )
    })?;
    let blob_start = st + IKCFG_ST.len();
    let ed = find(image, IKCFG_ED, blob_start)
        .ok_or("IKCFG_ST found but no IKCFG_ED after it: the image is truncated")?;
    let blob = &image[blob_start..ed];
    if blob.len() < 2 || blob[0] != 0x1f || blob[1] != 0x8b {
        return Err(format!(
            "the {} bytes between IKCFG_ST and IKCFG_ED are not gzip (magic {:02x}{:02x})",
            blob.len(),
            blob.first().copied().unwrap_or(0),
            blob.get(1).copied().unwrap_or(0)
        ));
    }
    let raw = gunzip(blob)?;
    String::from_utf8(raw).map_err(|e| format!("the ikconfig blob is not UTF-8: {e}"))
}

/// gzip, then DEFLATE. Hand-rolled for the same reason `sha256` is: one fewer
/// external tool that behaves differently when /usr/bin is not coreutils, and
/// a decoder that can be tested without a compressor to hand.
pub fn gunzip(data: &[u8]) -> Result<Vec<u8>, String> {
    if data.len() < 18 {
        return Err(format!("{} bytes is too short to be gzip", data.len()));
    }
    if data[0] != 0x1f || data[1] != 0x8b {
        return Err("not gzip: bad magic".to_string());
    }
    if data[2] != 8 {
        return Err(format!("gzip method {} is not deflate", data[2]));
    }
    let flg = data[3];
    let mut p = 10usize;
    let need = |p: usize, n: usize| -> Result<(), String> {
        if p + n > data.len() {
            Err("gzip header runs past the end of the blob".to_string())
        } else {
            Ok(())
        }
    };
    if flg & 0x04 != 0 {
        need(p, 2)?;
        let xlen = u16::from_le_bytes([data[p], data[p + 1]]) as usize;
        p += 2 + xlen;
    }
    for bit in [0x08u8, 0x10u8] {
        if flg & bit != 0 {
            while p < data.len() && data[p] != 0 {
                p += 1;
            }
            p += 1;
        }
    }
    if flg & 0x02 != 0 {
        p += 2;
    }
    if p >= data.len() {
        return Err("gzip header consumed the whole blob".to_string());
    }
    inflate(&data[p..])
}

struct Bits<'a> {
    data: &'a [u8],
    pos: usize,
    bit: u32,
    acc: u32,
}

impl<'a> Bits<'a> {
    fn new(data: &'a [u8]) -> Self {
        Bits {
            data,
            pos: 0,
            bit: 0,
            acc: 0,
        }
    }
    fn get(&mut self, n: u32) -> Result<u32, String> {
        while self.bit < n {
            if self.pos >= self.data.len() {
                return Err("deflate stream ended mid-symbol".to_string());
            }
            self.acc |= (self.data[self.pos] as u32) << self.bit;
            self.pos += 1;
            self.bit += 8;
        }
        let v = self.acc & ((1u32 << n) - 1);
        self.acc >>= n;
        self.bit -= n;
        Ok(v)
    }
}

/// Canonical Huffman, in the shape `puff` uses: counts per length plus symbols
/// in canonical order. Decoding walks one bit at a time, which is slow and
/// obviously correct - the blobs here are a few hundred kilobytes.
struct Huff {
    count: [u16; 16],
    symbol: Vec<u16>,
}

fn build_huff(lengths: &[u16]) -> Huff {
    let mut count = [0u16; 16];
    for &l in lengths {
        count[l as usize] += 1;
    }
    count[0] = 0;
    let mut offs = [0u16; 16];
    for i in 1..15 {
        offs[i + 1] = offs[i] + count[i];
    }
    let mut symbol = vec![0u16; lengths.len()];
    for (s, &l) in lengths.iter().enumerate() {
        if l != 0 {
            symbol[offs[l as usize] as usize] = s as u16;
            offs[l as usize] += 1;
        }
    }
    Huff { count, symbol }
}

fn decode(b: &mut Bits, h: &Huff) -> Result<u16, String> {
    let mut code = 0i32;
    let mut first = 0i32;
    let mut index = 0i32;
    for len in 1..16 {
        code |= b.get(1)? as i32;
        let count = h.count[len] as i32;
        if code - first < count {
            return Ok(h.symbol[(index + (code - first)) as usize]);
        }
        index += count;
        first = (first + count) << 1;
        code <<= 1;
    }
    Err("invalid Huffman code in the deflate stream".to_string())
}

const LBASE: [u16; 29] = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131,
    163, 195, 227, 258,
];
const LEXT: [u16; 29] = [
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
];
const DBASE: [u16; 30] = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537,
    2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
];
const DEXT: [u16; 30] = [
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13,
    13,
];

/// Raw DEFLATE (RFC 1951): stored, fixed-Huffman and dynamic-Huffman blocks.
pub fn inflate(data: &[u8]) -> Result<Vec<u8>, String> {
    let mut b = Bits::new(data);
    let mut out: Vec<u8> = Vec::new();
    loop {
        let last = b.get(1)?;
        let kind = b.get(2)?;
        match kind {
            0 => {
                // Stored: discard the partial byte, then LEN/NLEN.
                b.acc = 0;
                b.bit = 0;
                if b.pos + 4 > data.len() {
                    return Err("stored block header runs past the end".to_string());
                }
                let len = u16::from_le_bytes([data[b.pos], data[b.pos + 1]]) as usize;
                let nlen = u16::from_le_bytes([data[b.pos + 2], data[b.pos + 3]]) as usize;
                if len != !nlen & 0xffff {
                    return Err("stored block LEN/NLEN mismatch".to_string());
                }
                b.pos += 4;
                if b.pos + len > data.len() {
                    return Err("stored block runs past the end".to_string());
                }
                out.extend_from_slice(&data[b.pos..b.pos + len]);
                b.pos += len;
            }
            1 | 2 => {
                let (lh, dh) = if kind == 1 {
                    let mut ll = [0u16; 288];
                    for (i, l) in ll.iter_mut().enumerate() {
                        *l = if i < 144 {
                            8
                        } else if i < 256 {
                            9
                        } else if i < 280 {
                            7
                        } else {
                            8
                        };
                    }
                    (build_huff(&ll), build_huff(&[5u16; 30]))
                } else {
                    let hlit = b.get(5)? as usize + 257;
                    let hdist = b.get(5)? as usize + 1;
                    let hclen = b.get(4)? as usize + 4;
                    const ORDER: [usize; 19] = [
                        16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
                    ];
                    let mut cl = [0u16; 19];
                    for &o in ORDER.iter().take(hclen) {
                        cl[o] = b.get(3)? as u16;
                    }
                    let clh = build_huff(&cl);
                    let mut lens = vec![0u16; hlit + hdist];
                    let mut i = 0;
                    while i < lens.len() {
                        let s = decode(&mut b, &clh)?;
                        match s {
                            0..=15 => {
                                lens[i] = s;
                                i += 1;
                            }
                            16 => {
                                if i == 0 {
                                    return Err("repeat code 16 with no previous length".into());
                                }
                                let prev = lens[i - 1];
                                let n = 3 + b.get(2)? as usize;
                                for _ in 0..n {
                                    if i >= lens.len() {
                                        return Err("code-length repeat overruns".into());
                                    }
                                    lens[i] = prev;
                                    i += 1;
                                }
                            }
                            17 | 18 => {
                                let n = if s == 17 {
                                    3 + b.get(3)? as usize
                                } else {
                                    11 + b.get(7)? as usize
                                };
                                for _ in 0..n {
                                    if i >= lens.len() {
                                        return Err("code-length repeat overruns".into());
                                    }
                                    lens[i] = 0;
                                    i += 1;
                                }
                            }
                            _ => return Err(format!("bad code-length symbol {s}")),
                        }
                    }
                    (build_huff(&lens[..hlit]), build_huff(&lens[hlit..]))
                };
                loop {
                    let s = decode(&mut b, &lh)?;
                    if s == 256 {
                        break;
                    }
                    if s < 256 {
                        out.push(s as u8);
                        continue;
                    }
                    let li = s as usize - 257;
                    if li >= LBASE.len() {
                        return Err(format!("length symbol {s} is out of range"));
                    }
                    let len = LBASE[li] as usize + b.get(LEXT[li] as u32)? as usize;
                    let ds = decode(&mut b, &dh)? as usize;
                    if ds >= DBASE.len() {
                        return Err(format!("distance symbol {ds} is out of range"));
                    }
                    let dist = DBASE[ds] as usize + b.get(DEXT[ds] as u32)? as usize;
                    if dist > out.len() {
                        return Err("distance points before the start of the output".to_string());
                    }
                    let start = out.len() - dist;
                    for k in 0..len {
                        let byte = out[start + k];
                        out.push(byte);
                    }
                }
            }
            _ => return Err("reserved deflate block type 3".to_string()),
        }
        if last == 1 {
            return Ok(out);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A trimmed config_aarch64: the lines the closure actually reads, in the
    /// values Photon 5.0 ships for the generic aarch64 flavour (6.12.109-3,
    /// read off the input ISO's /boot/config).
    const STOCK_AARCH64: &str = "\
CONFIG_ACPI=y
CONFIG_SCSI=y
CONFIG_NLS=y
CONFIG_PTP_1588_CLOCK=y
CONFIG_PTP_1588_CLOCK_OPTIONAL=y
CONFIG_VSOCKETS=m
CONFIG_CONNECTOR=m
CONFIG_SCSI_FC_ATTRS=m
# CONFIG_HYPERV is not set
CONFIG_LOCALVERSION=\"\"
";

    #[test]
    fn parsing_is_not_set_lines_yields_unset_not_n() {
        let c = Kconfig::parse(STOCK_AARCH64);
        // The line exists and says "considered, left off".
        assert_eq!(c.get("HYPERV"), Some(&Value::Unset));
        // Which is NOT the same as having no line at all.
        assert_eq!(c.get("HYPERV_STORAGE"), None);
        // Both read as `n` when asked for a tristate, and that is the only
        // place the two are allowed to look alike.
        assert_eq!(c.tri("HYPERV"), Tristate::N);
        assert_eq!(c.tri("HYPERV_STORAGE"), Tristate::N);
        // A CONFIG_ prefix on the lookup must not change the answer.
        assert_eq!(c.tri("CONFIG_VSOCKETS"), Tristate::M);
        // A string value is not a tristate and must not pretend to be one.
        assert_eq!(c.get("LOCALVERSION").unwrap().tristate(), None);
    }

    #[test]
    fn a_fragment_symbol_capped_by_a_module_dependency_is_reported_with_the_gating_symbol() {
        let cfg = Kconfig::parse(STOCK_AARCH64);
        let forced = dependency_closure(&cfg, HYPERV_FRAGMENT, HYPERV_EDGES).unwrap();
        let utils: Vec<&Forced> = forced
            .iter()
            .filter(|f| f.because == "HYPERV_UTILS")
            .collect();
        assert_eq!(
            utils.len(),
            1,
            "exactly CONNECTOR gates HYPERV_UTILS here: {forced:?}"
        );
        assert_eq!(utils[0].symbol, "CONNECTOR");
        assert_eq!(utils[0].from, Value::Tri(Tristate::M));
        // The message has to name both ends, or it cannot be acted on.
        let line = utils[0].line();
        assert!(line.contains("CONFIG_CONNECTOR"), "{line}");
        assert!(line.contains("HYPERV_UTILS"), "{line}");
        assert!(line.contains("m -> y"), "{line}");
        // NLS and PTP_1588_CLOCK_OPTIONAL are already y here, so they are not
        // forced - the closure reports what it CHANGED, not the whole table.
        assert!(!forced.iter().any(|f| f.symbol == "NLS"), "{forced:?}");
        assert!(
            !forced.iter().any(|f| f.symbol == "PTP_1588_CLOCK_OPTIONAL"),
            "{forced:?}"
        );
    }

    #[test]
    fn the_hyperv_fragment_on_a_stock_aarch64_config_forces_connector_vsockets_and_scsi_fc_attrs() {
        let cfg = Kconfig::parse(STOCK_AARCH64);
        let forced = dependency_closure(&cfg, HYPERV_FRAGMENT, HYPERV_EDGES).unwrap();
        let mut got: Vec<&str> = forced.iter().map(|f| f.symbol.as_str()).collect();
        got.sort_unstable();
        assert_eq!(got, ["CONNECTOR", "SCSI_FC_ATTRS", "VSOCKETS"]);
        // SCSI_FC_ATTRS is the `(m || X != m)` idiom, not a plain depends-on:
        // it is raised because it is m, and m specifically is what caps
        // HYPERV_STORAGE at m.
        let fc = forced.iter().find(|f| f.symbol == "SCSI_FC_ATTRS").unwrap();
        assert_eq!(fc.because, "HYPERV_STORAGE");

        // And the resulting =y list is exactly the seven asked for plus the
        // three raised: ten, which is what the ISO is later read back for.
        let want = expected_y(HYPERV_FRAGMENT, &forced);
        assert_eq!(want.len(), 10, "{want:?}");
        for s in [
            "HYPERV",
            "HYPERV_STORAGE",
            "HYPERV_NET",
            "HYPERV_UTILS",
            "HYPERV_BALLOON",
            "HYPERV_VSOCKETS",
            "PCI_HYPERV",
            "CONNECTOR",
            "VSOCKETS",
            "SCSI_FC_ATTRS",
        ] {
            assert!(want.iter().any(|w| w == s), "{s} missing from {want:?}");
        }
    }

    /// The negative control for the closure: on a config where the enabling
    /// symbols are ALREADY y there is nothing to force, and the closure must
    /// say so by returning nothing rather than re-stating the table.
    #[test]
    fn a_config_that_is_already_all_y_needs_no_closure() {
        let cfg = Kconfig::parse(
            "CONFIG_ACPI=y\nCONFIG_SCSI=y\nCONFIG_NLS=y\nCONFIG_PTP_1588_CLOCK_OPTIONAL=y\n\
             CONFIG_VSOCKETS=y\nCONFIG_CONNECTOR=y\nCONFIG_SCSI_FC_ATTRS=y\n",
        );
        let forced = dependency_closure(&cfg, HYPERV_FRAGMENT, HYPERV_EDGES).unwrap();
        assert!(forced.is_empty(), "nothing to raise, but got {forced:?}");
        // SCSI_FC_ATTRS=n also satisfies `(m || X != m)`, and getting that
        // backwards would force a symbol the kernel never needed.
        let cfg_n = Kconfig::parse(
            "CONFIG_ACPI=y\nCONFIG_SCSI=y\nCONFIG_NLS=y\nCONFIG_PTP_1588_CLOCK_OPTIONAL=y\n\
             CONFIG_VSOCKETS=y\nCONFIG_CONNECTOR=y\n# CONFIG_SCSI_FC_ATTRS is not set\n",
        );
        assert!(dependency_closure(&cfg_n, HYPERV_FRAGMENT, HYPERV_EDGES)
            .unwrap()
            .is_empty());
    }

    /// A dependency with no line at all cannot be raised by a fragment, and
    /// saying nothing would produce a kernel with HYPERV_UTILS silently at m.
    #[test]
    fn a_dependency_that_is_not_visible_at_all_is_an_error_naming_the_symbol() {
        let cfg = Kconfig::parse(
            "CONFIG_ACPI=y\nCONFIG_SCSI=y\nCONFIG_NLS=y\nCONFIG_PTP_1588_CLOCK_OPTIONAL=y\n\
             CONFIG_VSOCKETS=y\nCONFIG_SCSI_FC_ATTRS=y\n",
        );
        let e = dependency_closure(&cfg, HYPERV_FRAGMENT, HYPERV_EDGES).unwrap_err();
        assert!(e.contains("CONFIG_CONNECTOR"), "{e}");
        assert!(e.contains("HYPERV_UTILS"), "{e}");
        assert!(e.contains("no line"), "{e}");
    }

    #[test]
    fn assert_all_y_names_every_symbol_that_did_not_survive_and_how_it_reads() {
        let cfg = Kconfig::parse("CONFIG_HYPERV=y\nCONFIG_HYPERV_UTILS=m\n");
        let syms: Vec<String> = ["HYPERV", "HYPERV_UTILS", "PCI_HYPERV"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        let e = assert_all_y(&cfg, &syms).unwrap_err();
        assert!(e.contains("CONFIG_HYPERV_UTILS=m"), "{e}");
        assert!(e.contains("CONFIG_PCI_HYPERV MISSING"), "{e}");
        assert!(
            !e.contains("CONFIG_HYPERV=y"),
            "the one that passed must not be listed: {e}"
        );
        // Negative control: the same assertion has to be able to PASS, or it
        // proves nothing when it does.
        let good = Kconfig::parse("CONFIG_HYPERV=y\nCONFIG_HYPERV_UTILS=y\nCONFIG_PCI_HYPERV=y\n");
        assert!(assert_all_y(&good, &syms).is_ok());
    }

    #[test]
    fn the_merged_fragment_puts_the_closure_first_and_explains_it() {
        let cfg = Kconfig::parse(STOCK_AARCH64);
        let forced = dependency_closure(&cfg, HYPERV_FRAGMENT, HYPERV_EDGES).unwrap();
        let merged = merged_fragment(HYPERV_FRAGMENT, &forced);
        let conn = merged.find("CONFIG_CONNECTOR=y").unwrap();
        let utils = merged.find("CONFIG_HYPERV_UTILS=y").unwrap();
        assert!(
            conn < utils,
            "the enabling symbol must precede what needs it"
        );
        assert!(merged.contains("# CONFIG_CONNECTOR: m -> y"), "{merged}");
        // Re-parsing the merged fragment must yield every symbol as y.
        let syms: Vec<String> = fragment_symbols(&merged)
            .into_iter()
            .map(|(s, _)| s)
            .collect();
        assert_eq!(syms.len(), 10);
    }

    /// The textual merge rewrites lines WHERE THEY STAND, so the result reads
    /// as a small diff rather than a reordered file - and it must handle both
    /// spellings of "off".
    #[test]
    fn applying_the_fragment_rewrites_lines_in_place_and_appends_only_what_is_new() {
        let src = "CONFIG_A=y\nCONFIG_CONNECTOR=m\n# CONFIG_HYPERV is not set\nCONFIG_Z=y\n";
        let syms: Vec<String> = ["CONNECTOR", "HYPERV", "PCI_HYPERV"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        let out = apply_to_config(src, &syms);
        let lines: Vec<&str> = out.lines().collect();
        // rewritten in place: position 1 and 2, exactly where they were
        assert_eq!(lines[0], "CONFIG_A=y");
        assert_eq!(lines[1], "CONFIG_CONNECTOR=y");
        assert_eq!(lines[2], "CONFIG_HYPERV=y");
        assert_eq!(lines[3], "CONFIG_Z=y");
        // only the symbol with no line at all is appended, and it says so
        assert!(out.contains("# Added by sharukhan --hyperv"), "{out}");
        assert!(out.trim_end().ends_with("CONFIG_PCI_HYPERV=y"), "{out}");
        // and the result parses back as all-y
        let k = Kconfig::parse(&out);
        assert!(assert_all_y(&k, &syms).is_ok());
        // a symbol whose name merely PREFIXES another must not be touched
        let pre = apply_to_config("CONFIG_HYPERV_NET=m\n", &["HYPERV".to_string()]);
        assert!(pre.contains("CONFIG_HYPERV_NET=m"), "{pre}");
    }

    // ---- ikconfig ------------------------------------------------------

    /// A gzip member whose deflate payload is a single STORED block. Built by
    /// hand so the decoder is tested without a compressor in the loop.
    fn gzip_stored(payload: &[u8]) -> Vec<u8> {
        let mut v = vec![0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0x03];
        // BFINAL=1, BTYPE=00, then pad to a byte boundary.
        v.push(0x01);
        let len = payload.len() as u16;
        v.extend_from_slice(&len.to_le_bytes());
        v.extend_from_slice(&(!len).to_le_bytes());
        v.extend_from_slice(payload);
        v.extend_from_slice(&[0, 0, 0, 0]); // CRC32, not checked here
        v.extend_from_slice(&(payload.len() as u32).to_le_bytes());
        v
    }

    #[test]
    fn the_ikconfig_blob_is_found_in_an_uncompressed_arm64_image() {
        let config = "CONFIG_HYPERV=y\nCONFIG_PCI_HYPERV=y\n";
        let mut image: Vec<u8> = vec![0xa5; 4096]; // plausible Image padding
        image.extend_from_slice(IKCFG_ST);
        image.extend_from_slice(&gzip_stored(config.as_bytes()));
        image.extend_from_slice(IKCFG_ED);
        image.extend_from_slice(&[0x5a; 512]);

        let got = extract_ikconfig(&image).unwrap();
        assert_eq!(got, config);
        let k = Kconfig::parse(&got);
        assert!(k.is_y("HYPERV") && k.is_y("PCI_HYPERV"));
    }

    #[test]
    fn a_kernel_without_ikconfig_is_an_error_not_an_empty_config() {
        let image = vec![0u8; 8192];
        let e = extract_ikconfig(&image).unwrap_err();
        assert!(e.contains("IKCFG_ST"), "{e}");
        assert!(
            e.contains("8192"),
            "the message must say what was searched: {e}"
        );

        // A truncated image - marker present, terminator absent - is also an
        // error, not a silently short config.
        let mut trunc: Vec<u8> = Vec::new();
        trunc.extend_from_slice(IKCFG_ST);
        trunc.extend_from_slice(&gzip_stored(b"CONFIG_X=y\n"));
        let e2 = extract_ikconfig(&trunc).unwrap_err();
        assert!(e2.contains("IKCFG_ED"), "{e2}");
    }

    /// The decoder against a REAL kernel: a ~50 KB dynamic-Huffman blob inside
    /// a 33 MB arm64 Image, which is the case the remaster actually depends on.
    /// Skipped unless `MC_TEST_KERNEL_IMAGE` names one, so the default suite
    /// needs no ISO mounted.
    ///
    /// It doubles as the NEGATIVE CONTROL for the whole verify step: a stock
    /// Photon kernel must FAIL the Hyper-V assertion. If it passed, the check
    /// that certifies the finished ISO would be vacuous.
    #[test]
    fn a_real_arm64_kernel_image_yields_its_config_and_a_stock_one_fails_the_hyperv_assertion() {
        let Ok(p) = std::env::var("MC_TEST_KERNEL_IMAGE") else {
            return;
        };
        let Ok(img) = std::fs::read(&p) else { return };
        let text = extract_ikconfig(&img).expect("a kernel built with CONFIG_IKCONFIG=y");
        let k = Kconfig::parse(&text);
        assert!(k.len() > 5000, "only {} symbols read from {p}", k.len());
        assert!(
            k.is_y("IKCONFIG"),
            "a kernel carrying an ikconfig says so in it"
        );

        // The symbol exists as a line, so the reader is looking in the right
        // place - it is simply off on a stock kernel.
        assert!(
            k.get("HYPERV").is_some(),
            "CONFIG_HYPERV has no line at all"
        );

        let want = expected_y(HYPERV_FRAGMENT, &[]);
        let e = assert_all_y(&k, &want)
            .expect_err("a STOCK kernel must fail the Hyper-V assertion, or it proves nothing");
        assert!(e.contains("CONFIG_HYPERV"), "{e}");
    }

    /// The decoder has to handle the block types a real kernel's ikconfig
    /// uses. A dynamic-Huffman round trip is the one that matters; `gzip` is
    /// used only to PRODUCE the fixture, so a missing gzip skips rather than
    /// fails.
    #[test]
    fn inflate_reads_a_real_gzip_members_dynamic_huffman_blocks() {
        use std::io::Write;
        use std::process::{Command, Stdio};
        let mut body = String::new();
        for i in 0..2000 {
            body.push_str(&format!("CONFIG_SYMBOL_NUMBER_{i}=y\n"));
        }
        let Ok(mut ch) = Command::new("gzip")
            .arg("-9")
            .arg("-c")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
        else {
            return; // no gzip on this host: nothing to build the fixture from
        };
        ch.stdin.take().unwrap().write_all(body.as_bytes()).unwrap();
        let out = ch.wait_with_output().unwrap();
        assert!(out.status.success());
        // Highly repetitive input: gzip -9 emits dynamic Huffman with
        // back-references, which exercises every path but `stored`.
        assert!(
            out.stdout.len() < body.len() / 4,
            "the fixture must be compressed"
        );
        assert_eq!(
            String::from_utf8(gunzip(&out.stdout).unwrap()).unwrap(),
            body
        );
    }
}
