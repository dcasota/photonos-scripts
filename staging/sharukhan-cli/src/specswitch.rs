//! Build switches of a spec: macros that are off by default and turn on a
//! variant (`STIG_HARDEN`, `with_x`), tested in a spec's conditionals.
//!
//! Two kinds:
//! - overridable: `%{!?NAME: %global NAME 0}` - `rpmbuild -D 'NAME 1'` turns it on;
//! - fixed: a plain `%define NAME 0` / `%global NAME 0` line. A definition in
//!   the spec body is made after the command line's, so it wins over `-D`
//!   and the variant can only be built by editing the spec. That is how a
//!   variant goes stale unnoticed: no build, no CI and no `-D` ever applies
//!   its patches. To test one, `set` rewrites that line in a scratch copy of
//!   the spec - never in the tree.
//!
//! A fixed definition counts as a switch only when a conditional tests it
//! (`%if 0%{?NAME}`, `%if %{NAME}`, `%elif ...`), so a plain `%global foo 0`
//! that is a value, not a switch, is left alone.

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Kind {
    Overridable,
    /// the 0-based line index of the one plain definition
    Fixed(usize),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Switch {
    pub name: String,
    pub kind: Kind,
}

impl Switch {
    pub fn describe(&self) -> &'static str {
        match self.kind {
            Kind::Overridable => "overridable",
            Kind::Fixed(_) => "fixed in the spec (plain %define)",
        }
    }
}

fn is_macro_name(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_') && !s.as_bytes()[0].is_ascii_digit()
}

/// `%{!?NAME: %global NAME 0}` -> NAME
fn overridable(line: &str) -> Option<String> {
    let rest = line.trim().strip_prefix("%{!?")?;
    let (name, body) = rest.split_once(':')?;
    let body = body.trim().strip_suffix('}')?.trim();
    let mut w = body.split_whitespace();
    let (kw, n, val) = (w.next()?, w.next()?, w.next()?);
    ((kw == "%global" || kw == "%define") && n == name && val == "0" && w.next().is_none() && is_macro_name(n)).then(|| n.to_string())
}

/// `%define NAME 0` -> NAME
fn plain(line: &str) -> Option<String> {
    let t = line.trim();
    let mut w = t.split_whitespace();
    let (kw, n, val) = (w.next()?, w.next()?, w.next()?);
    ((kw == "%global" || kw == "%define") && val == "0" && w.next().is_none() && is_macro_name(n)).then(|| n.to_string())
}

/// Does a conditional of the spec test NAME?
fn tested(spec: &str, name: &str) -> bool {
    let forms = [format!("%{{?{name}}}"), format!("%{{{name}}}"), format!("%{{?{name}:")];
    spec.lines().map(str::trim_start).filter(|l| l.starts_with("%if") || l.starts_with("%elif")).any(|l| forms.iter().any(|f| l.contains(f.as_str())))
}

/// Every switch of the spec, in the order they are defined. A name defined
/// plainly more than once is no switch one edit could turn on, and is left out.
pub fn switches(spec: &str) -> Vec<Switch> {
    let mut v: Vec<Switch> = Vec::new();
    let mut plain_lines: Vec<(String, usize)> = Vec::new();
    for (i, l) in spec.lines().enumerate() {
        if let Some(n) = overridable(l) {
            if !v.iter().any(|s| s.name == n) {
                v.push(Switch { name: n, kind: Kind::Overridable });
            }
        } else if let Some(n) = plain(l) {
            plain_lines.push((n, i));
        }
    }
    for (n, i) in &plain_lines {
        let once = plain_lines.iter().filter(|(m, _)| m == n).count() == 1;
        if once && !v.iter().any(|s| &s.name == n) && tested(spec, n) {
            v.push(Switch { name: n.clone(), kind: Kind::Fixed(*i) });
        }
    }
    v.sort_by_key(|s| match s.kind {
        Kind::Fixed(i) => i,
        Kind::Overridable => spec.lines().position(|l| overridable(l).as_deref() == Some(s.name.as_str())).unwrap_or(0),
    });
    v
}

/// The spec with a fixed switch's definition set to `value` (a scratch copy's
/// text); an overridable switch needs no edit and gets none. Refused when the
/// line is no longer the definition `switches` found.
pub fn set(spec: &str, sw: &Switch, value: &str) -> Result<String, String> {
    let Kind::Fixed(i) = sw.kind else { return Ok(spec.to_string()) };
    if !is_macro_name(&sw.name) || value.is_empty() || value.contains(char::is_whitespace) {
        return Err(format!("{}: refusing to set it to {value:?}", sw.name));
    }
    let mut out = String::with_capacity(spec.len() + 2);
    let mut done = false;
    for (n, l) in spec.split_inclusive('\n').enumerate() {
        if n == i {
            if plain(l).as_deref() != Some(sw.name.as_str()) {
                return Err(format!("line {} is not the definition of {}", i + 1, sw.name));
            }
            let kw = l.trim().split_whitespace().next().unwrap_or("%define");
            let indent: String = l.chars().take_while(|c| c.is_whitespace() && *c != '\n').collect();
            let nl = if l.ends_with('\n') { "\n" } else { "" };
            out.push_str(&format!("{indent}{kw} {} {value}{nl}", sw.name));
            done = true;
        } else {
            out.push_str(l);
        }
    }
    if !done {
        return Err(format!("{}: the spec has no line {}", sw.name, i + 1));
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SPEC: &str = "%define STIG_HARDEN 0\n%{!?with_x: %global with_x 0}\n%{!?on: %global on 1}\n%global plainvalue 0\n%global twice 0\n%global twice 0\nName: s\n%if 0%{?STIG_HARDEN}\nPatch5: a.patch\n%endif\n%if %{twice}\n%endif\n%if 0%{?with_x}\n%endif\n";

    #[test]
    fn both_kinds_are_found_and_values_are_not_switches() {
        let s = switches(SPEC);
        assert_eq!(s, vec![Switch { name: "STIG_HARDEN".into(), kind: Kind::Fixed(0) }, Switch { name: "with_x".into(), kind: Kind::Overridable }]);
        // `plainvalue` is never tested, `twice` is defined twice, `on` is on by default
    }

    #[test]
    fn a_fixed_switch_is_set_in_the_copy_and_nowhere_else() {
        let s = switches(SPEC);
        let on = set(SPEC, &s[0], "1").unwrap();
        assert!(on.starts_with("%define STIG_HARDEN 1\n"));
        assert_eq!(on.lines().count(), SPEC.lines().count());
        assert_eq!(on.replacen("%define STIG_HARDEN 1", "%define STIG_HARDEN 0", 1), SPEC);
        // an overridable one is left to -D
        assert_eq!(set(SPEC, &s[1], "1").unwrap(), SPEC);
        // the line moved: refused, not guessed
        let moved = format!("# x\n{SPEC}");
        assert!(set(&moved, &s[0], "1").is_err());
        assert!(set(SPEC, &s[0], "1 2").is_err());
    }

    #[test]
    fn elif_and_value_forms_count_as_tests() {
        assert_eq!(switches("%global a 0\n%if 1\n%elif %{a}\n%endif\n").len(), 1);
        assert_eq!(switches("%global a 0\n%if 0%{?a:1}\n%endif\n").len(), 1);
        assert!(switches("%global a 0\nRequires: %{a}\n").is_empty());
        assert!(switches("%global 9a 0\n%if %{9a}\n%endif\n").is_empty());
    }
}
