//! A child's stdout and stderr written to a log, every line prefixed with the
//! UTC time it arrived. A build log without times shows what happened but not
//! where the minutes went: the setup before build.py logs its first line was
//! visible only as a gap between two file timestamps.

use std::fs::File;
use std::io::{BufRead, BufReader, Read, Write};
use std::path::Path;
use std::process::{Command, ExitStatus, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

/// `HH:MM:SS.mmm` (UTC) of `t`.
pub fn hms(t: SystemTime) -> String {
    let d = t.duration_since(UNIX_EPOCH).unwrap_or_default();
    let s = d.as_secs() % 86_400;
    format!("{:02}:{:02}:{:02}.{:03}", s / 3600, s / 60 % 60, s % 60, d.subsec_millis())
}

/// Copy `from` line by line into `to`, each line prefixed by its arrival time.
/// Bytes are kept as they are; a last line without a newline gets one.
fn pump(from: impl Read, to: &Mutex<File>) -> std::io::Result<()> {
    let mut r = BufReader::new(from);
    let mut line = Vec::new();
    loop {
        line.clear();
        if r.read_until(b'\n', &mut line)? == 0 {
            return Ok(());
        }
        if line.last() != Some(&b'\n') {
            line.push(b'\n');
        }
        let mut out = format!("{} ", hms(SystemTime::now())).into_bytes();
        out.extend_from_slice(&line);
        let mut f = to.lock().map_err(|_| std::io::Error::other("log lock poisoned"))?;
        f.write_all(&out)?;
    }
}

/// Run `cmd` with stdin closed and both output streams appended to `log`,
/// timestamped. Returns the child's status once both streams are drained.
pub fn run_to_log(cmd: &mut Command, log: &Path) -> Result<ExitStatus, String> {
    let f = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(log)
        .map_err(|e| format!("{}: {e}", log.display()))?;
    let f = Arc::new(Mutex::new(f));
    let mut child = cmd
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("spawning {:?}: {e}", cmd.get_program()))?;
    let out = child.stdout.take().ok_or("child stdout missing")?;
    let err = child.stderr.take().ok_or("child stderr missing")?;
    let (fo, fe) = (Arc::clone(&f), Arc::clone(&f));
    let to = std::thread::spawn(move || pump(out, &fo));
    let te = std::thread::spawn(move || pump(err, &fe));
    let status = child.wait().map_err(|e| format!("waiting for {:?}: {e}", cmd.get_program()))?;
    for (name, t) in [("stdout", to), ("stderr", te)] {
        t.join()
            .map_err(|_| format!("{name} copier panicked"))?
            .map_err(|e| format!("writing {name} to {}: {e}", log.display()))?;
    }
    Ok(status)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hms_is_utc_time_of_day_with_millis() {
        let t = UNIX_EPOCH + std::time::Duration::from_millis(86_400_000 * 3 + 3_723_045);
        assert_eq!(hms(t), "01:02:03.045");
    }

    /// Every line of both streams arrives, stamped, including a last line
    /// without a newline and bytes that are not UTF-8; the status is the child's.
    #[test]
    fn both_streams_are_stamped_line_by_line() {
        let log = crate::safepath::test_base().join(format!("shk-tslog-{}.log", std::process::id()));
        let _ = std::fs::remove_file(&log);
        std::fs::write(&log, "earlier\n").unwrap();
        let st = run_to_log(
            Command::new("sh").args(["-c", "echo one; echo two >&2; printf 'x\\377y\\nlast'; exit 3"]),
            &log,
        )
        .unwrap();
        assert_eq!(st.code(), Some(3));
        let text = std::fs::read(&log).unwrap();
        let lines: Vec<&[u8]> = text.split(|b| *b == b'\n').filter(|l| !l.is_empty()).collect();
        assert_eq!(lines[0], b"earlier", "the log is appended to, not replaced");
        let body: Vec<Vec<u8>> = lines[1..].iter().map(|l| l[13..].to_vec()).collect();
        for l in &lines[1..] {
            let s = String::from_utf8_lossy(&l[..13]);
            assert!(s.len() == 13 && s.as_bytes()[2] == b':' && s.as_bytes()[8] == b'.' && s.ends_with(' '), "{s:?}");
        }
        let mut body = body;
        body.sort();
        let mut want: Vec<Vec<u8>> = vec![b"one".to_vec(), b"two".to_vec(), b"x\xffy".to_vec(), b"last".to_vec()];
        want.sort();
        assert_eq!(body, want);
        let _ = std::fs::remove_file(&log);
    }
}
