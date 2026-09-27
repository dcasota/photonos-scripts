//! The base wrapper: its declared identity and its slots.
//!
//! The base declares what it is and where it is kernel-specific, so derivation
//! needs no knowledge of the base's text:
//!
//! ```text
//! # @sharukhan-wrapper kernel=7.2.7 userland=5.0 native-series=6.12
//! # @sharukhan-slot kernel-pin begin
//! pin_727() { ... }
//! # @sharukhan-slot kernel-pin end
//! ```
//!
//! Everything between a slot's markers is re-rendered for the target kernel;
//! everything outside is carried over with the base's identity renamed. The
//! markers are comments - inert when the base runs as a wrapper itself - and
//! may be indented where the slot sits inside embedded Python. Parsing is
//! strict: an unknown or misspelt marker, a missing, repeated, unpaired or
//! nested slot, or an unknown declaration key is an error that names it, never
//! a slot silently left alone.

use std::collections::BTreeMap;

use super::error::{Result, WrapperError};
use super::identity::{KernelRelease, Userland};

pub const DECL: &str = "# @sharukhan-wrapper ";
pub const SLOT: &str = "# @sharukhan-slot ";
const MARK: &str = "@sharukhan-";

/// Every slot a base must declare, in the order they appear in it.
pub const SLOTS: [&str; 9] = [
    "header",
    "banner",
    "kernel-pin",
    "kernel-sandbox-names",
    "kernel-pin-calls",
    "kernel-patches",
    "kernel-source",
    "version-assert",
    "prebuild",
];

#[derive(Debug, Clone, PartialEq)]
pub enum Segment {
    Text(String),
    Slot { name: String, content: String },
}

#[derive(Debug, Clone)]
pub struct Base {
    pub kernel: KernelRelease,
    pub userland: Userland,
    /// Photon's own kernel series for this userland (the specs' origin).
    pub native_series: String,
    pub segments: Vec<Segment>,
}

/// `s` occurs as a whole identity: not as the prefix or suffix of a longer
/// release, tag or marker (`7.2` inside `7.2.7`, `runph72` inside `runph727`).
fn mentions_whole(text: &str, s: &str) -> bool {
    let b = text.as_bytes();
    let extends = |c: u8| c.is_ascii_alphanumeric();
    let joins = |i: usize| {
        // '-' or '.' directly followed by a digit continues a version.
        i + 1 < b.len() && (b[i] == b'-' || b[i] == b'.') && b[i + 1].is_ascii_digit()
    };
    text.match_indices(s).any(|(at, _)| {
        let end = at + s.len();
        let before_ok = at == 0 || {
            let c = b[at - 1];
            !(c.is_ascii_digit() || (c == b'.' && at >= 2 && b[at - 2].is_ascii_digit()))
        };
        let after_ok = end == b.len() || !(extends(b[end]) || joins(end));
        before_ok && after_ok
    })
}

impl Base {
    pub fn parse(text: &str) -> Result<Base> {
        if !text.ends_with('\n') {
            return Err(WrapperError::Base {
                why: "does not end with a newline".into(),
            });
        }
        let mut decl: Option<BTreeMap<String, String>> = None;
        let mut segments: Vec<Segment> = Vec::new();
        let mut text_buf = String::new();
        let mut open: Option<(String, String)> = None; // (name, content)
        let mut seen: BTreeMap<String, usize> = BTreeMap::new();

        for (idx, line) in text.split_inclusive('\n').enumerate() {
            let lineno = idx + 1;
            let body = line.trim_end_matches('\n');
            let trimmed = body.trim_start();
            if let Some(rest) = trimmed.strip_prefix(DECL.trim_start()) {
                if decl.is_some() {
                    return Err(WrapperError::Declaration {
                        why: format!("declared a second time at line {lineno}"),
                    });
                }
                if trimmed != body {
                    return Err(WrapperError::Declaration {
                        why: format!("line {lineno} is indented; it must start the line"),
                    });
                }
                decl = Some(parse_decl(rest, lineno)?);
                continue;
            }
            if let Some(rest) = trimmed.strip_prefix(SLOT.trim_start()) {
                let parts: Vec<&str> = rest.split(' ').collect();
                let [name, edge] = parts.as_slice() else {
                    return Err(slot_err(
                        rest,
                        format!("line {lineno}: expected '# @sharukhan-slot <name> begin|end'"),
                    ));
                };
                if !SLOTS.contains(name) {
                    return Err(slot_err(
                        name,
                        format!(
                            "line {lineno}: unknown slot; known slots are {}",
                            SLOTS.join(", ")
                        ),
                    ));
                }
                match (*edge, &mut open) {
                    ("begin", None) => {
                        *seen.entry(name.to_string()).or_insert(0) += 1;
                        segments.push(Segment::Text(std::mem::take(&mut text_buf)));
                        open = Some((name.to_string(), String::new()));
                    }
                    ("begin", Some((outer, _))) => {
                        return Err(slot_err(
                            name,
                            format!(
                                "line {lineno}: begins inside slot '{outer}'; slots do not nest"
                            ),
                        ))
                    }
                    ("end", Some((cur, content))) if cur == name => {
                        segments.push(Segment::Slot {
                            name: cur.clone(),
                            content: std::mem::take(content),
                        });
                        open = None;
                    }
                    ("end", Some((cur, _))) => {
                        return Err(slot_err(
                            name,
                            format!("line {lineno}: ends while slot '{cur}' is open"),
                        ))
                    }
                    ("end", None) => {
                        return Err(slot_err(
                            name,
                            format!("line {lineno}: ends a slot that was never begun"),
                        ))
                    }
                    (other, _) => {
                        return Err(slot_err(
                            name,
                            format!("line {lineno}: '{other}' is neither begin nor end"),
                        ))
                    }
                }
                continue;
            }
            if body.contains(MARK) {
                return Err(WrapperError::Base {
                    why: format!(
                        "line {lineno} mentions '{MARK}' but is not a well-formed marker: {body}"
                    ),
                });
            }
            match &mut open {
                Some((_, content)) => content.push_str(line),
                None => text_buf.push_str(line),
            }
        }
        if let Some((name, _)) = open {
            return Err(slot_err(&name, "is begun but never ended".to_string()));
        }
        segments.push(Segment::Text(text_buf));
        for name in SLOTS {
            let n = seen.get(name).copied().unwrap_or(0);
            if n != 1 {
                return Err(WrapperError::Slot {
                    name: name.to_string(),
                    expected: 1,
                    found: n,
                    why: if n == 0 {
                        "the base does not declare it".into()
                    } else {
                        "declared more than once".into()
                    },
                });
            }
        }
        let decl = decl.ok_or_else(|| WrapperError::Declaration {
            why: "missing; the base must declare its kernel".into(),
        })?;
        let kernel = KernelRelease::parse(decl.get("kernel").map(String::as_str).unwrap_or(""))
            .map_err(|e| WrapperError::Declaration {
                why: format!("kernel: {e}"),
            })?;
        let userland = Userland::parse(decl.get("userland").map(String::as_str).unwrap_or(""))?;
        let native_series = decl.get("native-series").cloned().unwrap_or_default();
        let ns_ok = native_series.split_once('.').is_some_and(|(a, b)| {
            !a.is_empty()
                && !b.is_empty()
                && a.bytes().all(|c| c.is_ascii_digit())
                && b.bytes().all(|c| c.is_ascii_digit())
        });
        if !ns_ok {
            return Err(WrapperError::Declaration {
                why: format!("native-series '{native_series}' is not MAJOR.MINOR"),
            });
        }
        let base = Base {
            kernel,
            userland,
            native_series,
            segments,
        };
        base.check_consistency()?;
        Ok(base)
    }

    pub fn slot(&self, name: &str) -> Option<&str> {
        self.segments.iter().find_map(|s| match s {
            Segment::Slot { name: n, content } if n == name => Some(content.as_str()),
            _ => None,
        })
    }

    /// All base text, slots included, without markers or declaration.
    pub fn full_text(&self) -> String {
        self.segments
            .iter()
            .map(|s| match s {
                Segment::Text(t) => t.as_str(),
                Segment::Slot { content, .. } => content.as_str(),
            })
            .collect()
    }

    /// Only the text outside slots: what derivation carries over renamed.
    pub fn carried_text(&self) -> String {
        self.segments
            .iter()
            .filter_map(|s| match s {
                Segment::Text(t) => Some(t.as_str()),
                Segment::Slot { .. } => None,
            })
            .collect()
    }

    /// The wrapper version the banner announces (`wrapper vN`).
    pub fn wrapper_version(&self) -> Result<u32> {
        let banner = self.slot("banner").unwrap_or("");
        let v = wrapper_versions(banner);
        match v.as_slice() {
            [n] => Ok(*n),
            _ => Err(WrapperError::Base {
                why: format!(
                    "the banner slot must announce exactly one 'wrapper vN'; found {}",
                    v.len()
                ),
            }),
        }
    }

    /// The base must agree with itself before anything is derived from it.
    fn check_consistency(&self) -> Result<()> {
        let banner_v = self.wrapper_version()?;
        let header_v = wrapper_versions(self.slot("header").unwrap_or(""));
        if header_v != [banner_v] {
            return Err(WrapperError::Base {
                why: format!(
                    "the header slot announces {header_v:?} but the banner announces wrapper v{banner_v}; \
                     a base whose two version lines disagree cannot be reviewed against"
                ),
            });
        }
        let full = self.full_text();
        let k = &self.kernel;
        for (what, s) in [
            ("its tag", k.tag()),
            ("its ISO marker", k.marker()),
            ("its kernel release", k.ksrc()),
        ] {
            if !mentions_whole(&full, &s) {
                return Err(WrapperError::Base {
                    why: format!(
                        "declares kernel={} but never mentions {what} '{s}'; the declaration is wrong",
                        k.ksrc()
                    ),
                });
            }
        }
        Ok(())
    }
}

fn slot_err(name: &str, why: String) -> WrapperError {
    WrapperError::Slot {
        name: name.to_string(),
        expected: 1,
        found: 0,
        why,
    }
}

fn parse_decl(rest: &str, lineno: usize) -> Result<BTreeMap<String, String>> {
    let mut m = BTreeMap::new();
    for kv in rest.split(' ') {
        let (k, v) = kv
            .split_once('=')
            .ok_or_else(|| WrapperError::Declaration {
                why: format!("line {lineno}: '{kv}' is not key=value"),
            })?;
        if !matches!(k, "kernel" | "userland" | "native-series") {
            return Err(WrapperError::Declaration {
                why: format!("line {lineno}: unknown key '{k}'"),
            });
        }
        if m.insert(k.to_string(), v.to_string()).is_some() {
            return Err(WrapperError::Declaration {
                why: format!("line {lineno}: '{k}' given twice"),
            });
        }
    }
    Ok(m)
}

/// Every `wrapper vN` in a text.
fn wrapper_versions(text: &str) -> Vec<u32> {
    let mut out = Vec::new();
    let mut rest = text;
    while let Some(i) = rest.find("wrapper v") {
        let after = &rest[i + "wrapper v".len()..];
        let digits: String = after.chars().take_while(|c| c.is_ascii_digit()).collect();
        if let Ok(n) = digits.parse() {
            out.push(n);
        }
        rest = after;
    }
    out
}

#[cfg(test)]
pub mod tests {
    use super::*;

    /// A minimal well-formed base for unit tests.
    pub fn sample() -> String {
        let mut s = String::from(
            "#!/bin/sh\n# @sharukhan-wrapper kernel=7.2.7 userland=5.0 native-series=6.12\n",
        );
        for name in SLOTS {
            s.push_str(&format!("# @sharukhan-slot {name} begin\n"));
            match name {
                "header" => s.push_str(
                    "# Photon OS 5.0 userland + experimental Linux 7.2.7\n# wrapper v13\n",
                ),
                "banner" => s.push_str("echo \"[runPh7-2-7] wrapper v13 + things\"\n"),
                _ => s.push_str(&format!("# {name} for 7.2.7\n")),
            }
            s.push_str(&format!("# @sharukhan-slot {name} end\n"));
            s.push_str("echo \"[runPh7-2-7] between .runph727-iso-marker\"\n");
        }
        s
    }

    #[test]
    fn a_well_formed_base_parses_into_text_and_slots() {
        let b = Base::parse(&sample()).unwrap();
        assert_eq!(b.kernel.ksrc(), "7.2.7");
        assert_eq!(b.userland.full(), "5.0");
        assert_eq!(b.native_series, "6.12");
        assert_eq!(b.wrapper_version().unwrap(), 13);
        assert_eq!(b.slot("kernel-pin"), Some("# kernel-pin for 7.2.7\n"));
        assert!(!b.full_text().contains("@sharukhan-"));
        assert!(!b.carried_text().contains("kernel-pin for"));
    }

    #[test]
    fn each_malformed_slot_is_named_with_expected_and_found() {
        for (edit, needle) in [
            (("# @sharukhan-slot banner begin\n", ""), "slot 'banner'"),
            (("# @sharukhan-slot banner end\n", ""), "slot 'banner'"),
            (
                ("# @sharukhan-slot banner end\n", "# @sharukhan-slot banner end\n# @sharukhan-slot banner begin\n# @sharukhan-slot banner end\n"),
                "expected 1, found 2",
            ),
            (("# @sharukhan-slot prebuild begin", "# @sharukhan-slot prebuilt begin"), "unknown slot"),
            (("# @sharukhan-slot header end\n", ""), "do not nest"),
            (("# @sharukhan-slot header begin", "# @sharukhan-slot header start"), "neither begin nor end"),
            (("# @sharukhan-slot header begin", "# @sharukhan-slot  header begin"), "expected '# @sharukhan-slot"),
            (("# @sharukhan-slot kernel-pin begin\n", "# @sharukhan-slotkernel-pin begin\n"), "not a well-formed marker"),
        ] {
            let s = sample().replacen(edit.0, edit.1, 1);
            assert_ne!(s, sample());
            let e = Base::parse(&s).unwrap_err().to_string();
            assert!(e.contains(needle), "{edit:?}: {e}");
        }
    }

    #[test]
    fn the_declaration_is_required_and_strict() {
        let decl = "# @sharukhan-wrapper kernel=7.2.7 userland=5.0 native-series=6.12\n";
        for (to, needle) in [
            ("", "missing"),
            (
                "# @sharukhan-wrapper kernel=7.2.7 userland=5.0 native-series=6.12 arch=x86\n",
                "unknown key 'arch'",
            ),
            (
                "# @sharukhan-wrapper kernel=7.2.7 kernel=7.2.8 userland=5.0 native-series=6.12\n",
                "given twice",
            ),
            (
                "# @sharukhan-wrapper kernel=7.2 userland=5.0 native-series=6.12\n",
                "never mentions",
            ),
            (
                "# @sharukhan-wrapper kernel=7.2.7 userland=5 native-series=6.12\n",
                "userland",
            ),
            (
                "# @sharukhan-wrapper kernel=7.2.7 userland=5.0 native-series=six\n",
                "native-series",
            ),
            (
                "  # @sharukhan-wrapper kernel=7.2.7 userland=5.0 native-series=6.12\n",
                "indented",
            ),
        ] {
            let s = sample().replacen(decl, to, 1);
            let e = Base::parse(&s).unwrap_err().to_string();
            assert!(e.contains(needle), "{to:?}: {e}");
        }
        let twice = sample().replacen(decl, &format!("{decl}{decl}"), 1);
        assert!(Base::parse(&twice)
            .unwrap_err()
            .to_string()
            .contains("second time"));
    }

    #[test]
    fn disagreeing_version_lines_are_refused() {
        let s = sample().replacen("# wrapper v13\n", "# wrapper v4\n", 1);
        let e = Base::parse(&s).unwrap_err().to_string();
        assert!(e.contains("[4]") && e.contains("v13"), "{e}");
    }

    #[test]
    fn indented_markers_are_accepted_for_slots_inside_embedded_code() {
        let s = sample().replacen(
            "# @sharukhan-slot prebuild begin\n",
            "        # @sharukhan-slot prebuild begin\n",
            1,
        );
        assert!(Base::parse(&s).is_ok());
    }

    #[test]
    fn a_missing_final_newline_is_refused() {
        let s = sample();
        assert!(Base::parse(s.trim_end()).is_err());
    }
}
