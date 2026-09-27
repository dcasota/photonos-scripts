//! Validation and context escaping for every value that reaches the emitted
//! script.
//!
//! The emitted wrapper is shell that embeds Python that edits RPM specs, so a
//! value can land in a shell comment, a shell double-quoted string, a Python
//! string, a Python f-string, a Python raw regex or an RPM changelog. Rather
//! than escape for all of them and hope, each value is first held to a grammar
//! narrow enough that the context cannot misread it, and escaped only where
//! the grammar still admits a metacharacter (`.` and `+` in a regex).

use super::error::{profile, Result};

/// Printable ASCII, no control characters, no newline. The emitted script runs
/// under LC_ALL=C, so nothing else is guaranteed to survive.
fn printable(field: &str, s: &str) -> Result<()> {
    if s.is_empty() {
        return Err(profile(field, "is empty"));
    }
    if let Some(c) = s.chars().find(|c| !(' '..='~').contains(c)) {
        return Err(profile(
            field,
            format!("contains {c:?}; only printable ASCII is allowed"),
        ));
    }
    Ok(())
}

/// Free text for a shell `#` comment line.
pub fn comment_line(field: &str, s: &str) -> Result<()> {
    printable(field, s)?;
    if s.ends_with(' ') {
        return Err(profile(field, "ends with a space"));
    }
    Ok(())
}

/// Text inside a Python f-string that the emitted code prints: no quote,
/// backslash or brace, which would end the string or open a replacement field.
pub fn fstring_text(field: &str, s: &str) -> Result<()> {
    printable(field, s)?;
    if let Some(c) = s.chars().find(|c| matches!(c, '"' | '\\' | '{' | '}')) {
        return Err(profile(
            field,
            format!("contains {c:?}, which a Python f-string would misread"),
        ));
    }
    Ok(())
}

/// Text inside a plain Python double-quoted string.
pub fn py_text(field: &str, s: &str) -> Result<()> {
    printable(field, s)?;
    if let Some(c) = s.chars().find(|c| matches!(c, '"' | '\\')) {
        return Err(profile(
            field,
            format!("contains {c:?}, which would end or escape the Python string"),
        ));
    }
    Ok(())
}

/// Text inside a shell double-quoted string: no quote, backslash, `$` or
/// backtick, so nothing is expanded or ends the string.
pub fn sh_dq_text(field: &str, s: &str) -> Result<()> {
    printable(field, s)?;
    if let Some(c) = s.chars().find(|c| matches!(c, '"' | '\\' | '$' | '`')) {
        return Err(profile(
            field,
            format!("contains {c:?}, which a shell double-quoted string would expand or end"),
        ));
    }
    Ok(())
}

/// A patch file name as the spec's `PatchN:` line names it.
pub fn patch_file(field: &str, s: &str) -> Result<()> {
    if s.len() > 200 {
        return Err(profile(field, "is longer than 200 characters"));
    }
    if !s.ends_with(".patch") {
        return Err(profile(field, "does not end in .patch"));
    }
    if s.starts_with('.') || s.starts_with('-') {
        return Err(profile(field, "starts with '.' or '-'"));
    }
    if let Some(c) = s
        .chars()
        .find(|c| !(c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '+' | '-')))
    {
        return Err(profile(
            field,
            format!("contains {c:?}; allowed are letters, digits and . _ + -"),
        ));
    }
    Ok(())
}

/// A Photon package name.
pub fn package_name(field: &str, s: &str) -> Result<()> {
    let first_ok = s
        .chars()
        .next()
        .map(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
        .unwrap_or(false);
    if !first_ok
        || !s.chars().all(|c| {
            c.is_ascii_lowercase() || c.is_ascii_digit() || matches!(c, '.' | '_' | '+' | '-')
        })
    {
        return Err(profile(
            field,
            format!("'{s}' is not a package name (lower-case letters, digits, . _ + -)"),
        ));
    }
    Ok(())
}

/// A kernel command-line parameter as the spec's cmdline carries it.
pub fn kernel_param(field: &str, s: &str) -> Result<()> {
    if s.is_empty()
        || !s
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '=' | '-'))
    {
        return Err(profile(
            field,
            format!("'{s}' is not a kernel parameter (letters, digits, _ . = -)"),
        ));
    }
    Ok(())
}

/// A short machine name: `[a-z][a-z0-9]*`, used in shell function names.
pub fn ident(field: &str, s: &str) -> Result<()> {
    let ok = s
        .chars()
        .next()
        .map(|c| c.is_ascii_lowercase())
        .unwrap_or(false)
        && s.chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
        && s.len() <= 32;
    if !ok {
        return Err(profile(
            field,
            format!("'{s}' is not a lower-case identifier of at most 32 characters"),
        ));
    }
    Ok(())
}

/// `Name <user@host>`, as an RPM changelog line carries it.
pub fn author(field: &str, s: &str) -> Result<()> {
    py_text(field, s)?;
    let bad = || profile(field, format!("'{s}' is not 'Name <user@example.org>'"));
    let (name, rest) = s.split_once(" <").ok_or_else(bad)?;
    let email = rest.strip_suffix('>').ok_or_else(bad)?;
    if name.trim().is_empty()
        || name != name.trim()
        || !name
            .chars()
            .all(|c| c.is_ascii_alphabetic() || matches!(c, ' ' | '.' | '\'' | '-'))
    {
        return Err(bad());
    }
    let (user, host) = email.split_once('@').ok_or_else(bad)?;
    let user_ok = !user.is_empty()
        && user
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '+' | '-'));
    let host_ok = host.contains('.')
        && !host.starts_with('.')
        && !host.ends_with('.')
        && host
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-'));
    if !user_ok || !host_ok {
        return Err(bad());
    }
    Ok(())
}

const WEEKDAYS: [&str; 7] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const MONTHS: [&str; 12] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

fn days_in_month(y: i64, m: u32) -> u32 {
    match m {
        2 if (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    }
}

/// Days since 1970-01-01 of a proleptic Gregorian date (Howard Hinnant).
pub fn days_from_civil(y: i64, m: u32, d: u32) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (m as i64 + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d as i64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

/// The proleptic Gregorian date of a day count since 1970-01-01 (Hinnant).
pub fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (yoe + era * 400 + i64::from(m <= 2), m, d)
}

/// The weekday of a date, as an RPM changelog abbreviates it.
pub fn weekday(y: i64, m: u32, d: u32) -> &'static str {
    // 1970-01-01 was a Thursday.
    let idx = (days_from_civil(y, m, d) + 3).rem_euclid(7) as usize;
    WEEKDAYS[idx]
}

/// Format a date as an RPM changelog date: `Sun Sep 27 2026`.
pub fn changelog_date_of(y: i64, m: u32, d: u32) -> String {
    format!(
        "{} {} {:02} {}",
        weekday(y, m, d),
        MONTHS[(m - 1) as usize],
        d,
        y
    )
}

/// An RPM changelog date, with the weekday CHECKED against the calendar: rpm
/// rejects a wrong weekday ("bogus date in %changelog"), and a hand-typed one
/// is exactly how that happens.
pub fn changelog_date(field: &str, s: &str) -> Result<()> {
    let bad = |why: String| profile(field, format!("'{s}': {why}"));
    let parts: Vec<&str> = s.split(' ').collect();
    let [wd, mon, day, year] = parts.as_slice() else {
        return Err(bad("expected 'Www Mmm DD YYYY'".into()));
    };
    let m = MONTHS
        .iter()
        .position(|x| x == mon)
        .ok_or_else(|| bad(format!("'{mon}' is not a month abbreviation")))? as u32
        + 1;
    if day.len() != 2 || !day.bytes().all(|b| b.is_ascii_digit()) {
        return Err(bad("the day must be two digits".into()));
    }
    if year.len() != 4 || !year.bytes().all(|b| b.is_ascii_digit()) {
        return Err(bad("the year must be four digits".into()));
    }
    let d: u32 = day.parse().map_err(|_| bad("bad day".into()))?;
    let y: i64 = year.parse().map_err(|_| bad("bad year".into()))?;
    if d == 0 || d > days_in_month(y, m) {
        return Err(bad(format!("{mon} {y} has no day {d}")));
    }
    let real = weekday(y, m, d);
    if *wd != real {
        return Err(bad(format!("that date is a {real}, not a {wd}")));
    }
    Ok(())
}

/// Escape a literal for a Python regex. The file-name grammar leaves only `.`
/// and `+` as metacharacters, but every one is handled so a looser grammar
/// later cannot turn a literal into a pattern.
pub fn re_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 4);
    for c in s.chars() {
        if matches!(
            c,
            '.' | '^' | '$' | '*' | '+' | '?' | '(' | ')' | '[' | ']' | '{' | '}' | '|' | '\\'
        ) {
            out.push('\\');
        }
        out.push(c);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn weekdays_match_the_calendar() {
        assert_eq!(weekday(2026, 9, 23), "Wed");
        assert_eq!(weekday(2026, 9, 25), "Fri");
        assert_eq!(weekday(2026, 9, 27), "Sun");
        assert_eq!(weekday(1970, 1, 1), "Thu");
        assert_eq!(weekday(2000, 2, 29), "Tue");
        assert_eq!(changelog_date_of(2026, 9, 26), "Sat Sep 26 2026");
    }

    #[test]
    fn a_changelog_date_with_the_wrong_weekday_is_refused() {
        assert!(changelog_date("d", "Fri Sep 25 2026").is_ok());
        let e = changelog_date("d", "Tue Sep 23 2026")
            .unwrap_err()
            .to_string();
        assert!(e.contains("is a Wed, not a Tue"), "{e}");
        for bad in [
            "Fri Sep 31 2026",
            "Fri Sept 25 2026",
            "Fri Sep 5 2026",
            "Fri Sep 25 26",
            "Fri  Sep 25 2026",
            "Sun Feb 29 2026",
        ] {
            assert!(changelog_date("d", bad).is_err(), "{bad}");
        }
        assert!(changelog_date("d", "Sat Feb 29 2020").is_ok());
    }

    #[test]
    fn each_context_refuses_the_characters_it_would_misread() {
        assert!(fstring_text("f", "RAP/KCFI Patch61 (7.3-rc4 rebase) and Patch63 enabled").is_ok());
        for bad in ["a{b", "a}b", "a\"b", "a\\b", "tab\there", "", "é"] {
            assert!(fstring_text("f", bad).is_err(), "{bad:?}");
        }
        assert!(py_text("f", "- networkmanager: match by Type=ether/Kind=!*").is_ok());
        assert!(py_text("f", "a\"b").is_err());
        assert!(sh_dq_text("f", "RAP/KCFI on, rdrand-rng").is_ok());
        for bad in ["$HOME", "a`b`", "a\"b", "a\\b"] {
            assert!(sh_dq_text("f", bad).is_err(), "{bad}");
        }
        assert!(comment_line("c", "fine").is_ok());
        assert!(comment_line("c", "trailing ").is_err());
    }

    #[test]
    fn names_follow_their_grammars() {
        assert!(patch_file("p", "0001-gcc-rap-plugin-with-kcfi-7.3.patch").is_ok());
        for bad in [
            "x.diff",
            "../x.patch",
            "-x.patch",
            "a b.patch",
            "a\"b.patch",
            ".x.patch",
        ] {
            assert!(patch_file("p", bad).is_err(), "{bad}");
        }
        assert!(package_name("p", "openssl-fips-provider").is_ok());
        assert!(package_name("p", "Cloud-init").is_err());
        assert!(package_name("p", "").is_err());
        assert!(kernel_param("k", "noreplace-smp").is_ok());
        assert!(kernel_param("k", "a b").is_err());
        assert!(ident("i", "rdrand").is_ok());
        assert!(ident("i", "Rap").is_err());
        assert!(ident("i", "7rap").is_err());
        assert!(author("a", "Daniel Casota <dcasota@gmail.com>").is_ok());
        for bad in [
            "Daniel Casota",
            "Daniel <dcasota>",
            "<a@b.c>",
            "D <a@b.c> x",
            "D <a@.c>",
            "D\" <a@b.c>",
        ] {
            assert!(author("a", bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn regex_escaping_turns_every_metacharacter_into_a_literal() {
        assert_eq!(
            re_escape("0001-gcc-rap-plugin-with-kcfi-7.3.patch"),
            "0001-gcc-rap-plugin-with-kcfi-7\\.3\\.patch"
        );
        assert_eq!(re_escape("a+b(c)"), "a\\+b\\(c\\)");
    }

    #[test]
    fn civil_from_days_inverts_days_from_civil() {
        for (y, m, d) in [
            (1970, 1, 1),
            (2000, 2, 29),
            (2026, 9, 27),
            (1969, 12, 31),
            (2100, 3, 1),
        ] {
            assert_eq!(civil_from_days(days_from_civil(y, m, d)), (y, m, d));
        }
        assert_eq!(changelog_date_of(2026, 9, 27), "Sun Sep 27 2026");
    }
}
