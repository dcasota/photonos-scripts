//! Reading a VMware serial log.
//!
//! A serial log contains NUL bytes and SGR colour sequences, and both defeat
//! the obvious tools. On this host /usr/bin/grep in a non-interactive shell is
//! toybox (interactively it is ugrep), and toybox grep has no `-a`: on a
//! NUL-bearing file it reports ZERO matches rather than erroring. A count that
//! silently reads zero is the worst possible failure for an oracle - every
//! "no errors found" assertion passes vacuously.
//!
//! So: strip the NULs first, then match. vm-lab had the SGR strip right on one
//! line and wrong on another (`s/...*g//g` instead of `*m//g`); keeping it in
//! one function is what stops it drifting again.

use std::path::Path;

/// NULs removed, SGR sequences removed, lossy UTF-8. Never fails: an
/// unreadable log is an empty string, and the caller's own "serial log
/// missing" check is what reports it.
pub fn read_clean(path: &Path) -> String {
    match std::fs::read(path) {
        Ok(bytes) => clean(&bytes),
        Err(_) => String::new(),
    }
}

pub fn clean(bytes: &[u8]) -> String {
    let no_nul: Vec<u8> = bytes.iter().copied().filter(|b| *b != 0).collect();
    strip_sgr(&String::from_utf8_lossy(&no_nul))
}

/// Remove `ESC [ <params> m` only. Other CSI sequences are left alone: they
/// are rare in an installer log and a greedier pattern eats real text.
fn strip_sgr(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let b: Vec<char> = s.chars().collect();
    let mut i = 0;
    while i < b.len() {
        if b[i] == '\u{1b}' && i + 1 < b.len() && b[i + 1] == '[' {
            let mut j = i + 2;
            while j < b.len() && (b[j].is_ascii_digit() || b[j] == ';') {
                j += 1;
            }
            if j < b.len() && b[j] == 'm' {
                i = j + 1;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    out
}

/// Lines containing `needle`. The bash form was
/// `n=$(grep -c ...) || n=0`, never `$(grep -c ... || echo 0)` - the second
/// swallows an error into a plausible zero.
pub fn count(text: &str, needle: &str) -> usize {
    text.lines().filter(|l| l.contains(needle)).count()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nul_bytes_do_not_hide_matches() {
        let raw = b"boot\0ing root=PARTUUID=abc\0\nother line\n";
        let text = clean(raw);
        assert_eq!(count(&text, "root=PARTUUID="), 1);
        assert!(!text.contains('\0'));
    }

    #[test]
    fn sgr_sequences_are_stripped_but_text_survives() {
        let raw = "\u{1b}[0;32mError(1011)\u{1b}[0m no matching packages\n".as_bytes();
        let text = clean(raw);
        assert_eq!(text, "Error(1011) no matching packages\n");
        assert_eq!(count(&text, "Error(1011)"), 1);
    }

    #[test]
    fn a_non_sgr_escape_is_left_alone() {
        let text = clean("\u{1b}[2Jcleared\n".as_bytes());
        assert!(text.contains("cleared"));
    }

    #[test]
    fn counting_is_by_line_not_by_occurrence() {
        let text = "a x a\nb\na\n";
        assert_eq!(count(text, "a"), 2);
    }

    #[test]
    fn a_missing_log_reads_empty_rather_than_panicking() {
        assert_eq!(read_clean(Path::new("/no/such/serial0.log")), "");
    }
}
