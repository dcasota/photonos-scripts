//! Validation of an emitted wrapper by the tools that will run it.
//!
//! `sh -n` parses the shell; each embedded `<< 'PY'` heredoc is parsed by the
//! Python that will execute it. Both are external commands invoked with an
//! argument vector, fed through stdin or a private temporary file, and each
//! reports what it measured rather than a bare pass.

use std::io::Write;
use std::process::{Command, Stdio};

use super::error::{io, Result, WrapperError};

/// What validation measured, for the report.
#[derive(Debug, Clone, PartialEq)]
pub struct Measured {
    pub sh_n: String,
    pub python_heredocs: usize,
    pub lines: usize,
}

/// The bodies of every `<< 'PY'` heredoc, with the line each starts on.
pub fn python_heredocs(script: &str) -> Result<Vec<(usize, String)>> {
    let mut out = Vec::new();
    let mut cur: Option<(usize, String)> = None;
    for (i, line) in script.lines().enumerate() {
        let n = i + 1;
        match &mut cur {
            Some((_, body)) => {
                if line == "PY" {
                    if let Some(done) = cur.take() {
                        out.push(done);
                    }
                } else {
                    body.push_str(line);
                    body.push('\n');
                }
            }
            None => {
                if line.contains("<< 'PY'") {
                    cur = Some((n + 1, String::new()));
                }
            }
        }
    }
    if let Some((start, _)) = cur {
        return Err(WrapperError::Validation {
            step: "python heredocs".into(),
            measured: format!("the heredoc starting at line {start} has no closing 'PY' line"),
        });
    }
    Ok(out)
}

fn python_parses(body: &str, start: usize) -> Result<()> {
    let mut py = Command::new("python3");
    py.args(["-c", "import ast, sys\nast.parse(sys.stdin.read())"]);
    let out = piped(py, body, "python3")?;
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        let last = err.lines().last().unwrap_or("").to_string();
        return Err(WrapperError::Validation {
            step: format!("python heredoc at line {start}"),
            measured: format!("does not parse: {last}"),
        });
    }
    Ok(())
}

/// Feed `input` to `cmd` on stdin and collect its output.
fn piped(mut cmd: Command, input: &str, what: &str) -> Result<std::process::Output> {
    let mut child = cmd
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| io(format!("running {what}"), e))?;
    let mut stdin = child
        .stdin
        .take()
        .ok_or_else(|| io(what.to_string(), "no stdin"))?;
    // A writer thread: a child that fills its output pipe before reading all
    // of its input would otherwise deadlock against us.
    let data = input.as_bytes().to_vec();
    let writer = std::thread::spawn(move || stdin.write_all(&data));
    let out = child
        .wait_with_output()
        .map_err(|e| io(format!("waiting for {what}"), e))?;
    match writer.join() {
        Ok(Ok(())) => Ok(out),
        Ok(Err(e)) => Err(io(format!("feeding {what}"), e)),
        Err(_) => Err(io(format!("feeding {what}"), "writer thread panicked")),
    }
}

/// Run every validation on `script`. Nothing touches the filesystem: the
/// script reaches `sh -n` and `python3` on stdin.
pub fn validate(script: &str) -> Result<Measured> {
    if !script.ends_with('\n') {
        return Err(WrapperError::Validation {
            step: "final newline".into(),
            measured: "the script does not end with a newline".into(),
        });
    }
    if let Some((i, l)) = script
        .lines()
        .enumerate()
        .find(|(_, l)| l.contains("@sharukhan-"))
    {
        return Err(WrapperError::Validation {
            step: "markers removed".into(),
            measured: format!("line {} still carries a marker: {l}", i + 1),
        });
    }
    let mut sh = Command::new("sh");
    sh.arg("-n");
    let out = piped(sh, script, "sh -n")?;
    let sh_n = format!(
        "exit {}{}",
        out.status.code().unwrap_or(-1),
        if out.stderr.is_empty() {
            String::new()
        } else {
            format!(", {}", String::from_utf8_lossy(&out.stderr).trim())
        }
    );
    if !out.status.success() {
        return Err(WrapperError::Validation {
            step: "sh -n".into(),
            measured: sh_n,
        });
    }
    let docs = python_heredocs(script)?;
    for (start, body) in &docs {
        python_parses(body, *start)?;
    }
    Ok(Measured {
        sh_n,
        python_heredocs: docs.len(),
        lines: script.lines().count(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_valid_script_reports_what_was_measured() {
        let s = "#!/bin/sh\npython3 - << 'PY'\nprint('x')\nPY\necho ok\n";
        let m = validate(s).unwrap();
        assert_eq!(m.sh_n, "exit 0");
        assert_eq!(m.python_heredocs, 1);
        assert_eq!(m.lines, 5);
    }

    #[test]
    fn a_shell_syntax_error_is_caught_by_sh_n() {
        let e = validate("#!/bin/sh\nif true; then\necho x\n")
            .unwrap_err()
            .to_string();
        assert!(e.contains("'sh -n'") && e.contains("exit"), "{e}");
    }

    #[test]
    fn a_python_heredoc_that_does_not_parse_is_caught_with_its_line() {
        let s = "#!/bin/sh\necho a\npython3 - << 'PY'\nif True\n    pass\nPY\n";
        let e = validate(s).unwrap_err().to_string();
        assert!(e.contains("heredoc at line 4"), "{e}");
    }

    #[test]
    fn an_unclosed_heredoc_and_a_surviving_marker_are_refused() {
        assert!(python_heredocs("python3 - << 'PY'\nx = 1\n").is_err());
        let e = validate("# @sharukhan-slot x begin\n")
            .unwrap_err()
            .to_string();
        assert!(e.contains("marker"), "{e}");
        assert!(validate("echo x").is_err());
    }
}
