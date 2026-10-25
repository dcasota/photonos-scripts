//! `sharukhan mcp --run <id> --pr <n> [--profile escalation|readonly]`: the
//! stdio MCP server an escalation's Claude works through.
//!
//! It is bound at start to one sync run and one PR, and it is the only thing
//! the model can act with: the escalation runs `claude --tools ""`, so no
//! built-in tool (shell, files, web) exists, only these. What they can reach:
//!
//! * read: the subject (run, PR, stage, refusal), the PR's own change, what
//!   upstream changed in a path, files at four named revisions (never an
//!   arbitrary rev), a stage's log, the project's rules and findings;
//! * write, escalation profile only: `propose_patch` commits a diff to
//!   `refs/heads/sync/<run>/proposal/<branch>` and nowhere else;
//!   `propose_description` writes a description beside the run; `verify` runs
//!   sharukhan's own checks on the proposal. Nothing pushes: the server holds
//!   no credential, and a proposal becomes a candidate only through
//!   `sharukhan sync decide`.
//!
//! Every output is redacted (keys, tokens, password lines) and capped, with
//! pagination, well under the client's warning size. The memory database is
//! opened read-only. Upstream content (commit messages, logs, PR text) reaches
//! the model as data inside tool results, never as instructions of this server.


use serde_json::{json, Value};
use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};
use std::process::Command;

pub const PROTOCOL: &str = "2025-06-18";
const SUPPORTED: &[&str] = &["2025-06-18", "2025-03-26", "2024-11-05"];
/// Lines and characters per tool result; the client warns at 10k tokens.
const MAX_LINES: usize = 300;
const MAX_CHARS: usize = 12_000;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Profile {
    Escalation,
    Readonly,
}

/// What the server is bound to, read once at start.
#[derive(Debug, Clone)]
pub struct Subject {
    pub run: i64,
    pub pr: i64,
    pub branch: String,
    pub root: String,
    pub parent: Option<String>,
    pub state: String,
    pub detail: String,
    pub stage: String,
    pub stage_detail: String,
    pub repo: PathBuf,
    pub results: PathBuf,
    pub old_base: String,
    pub new_base: String,
    pub old_head: String,
    pub candidate: Option<String>,
}

impl Subject {
    pub fn proposal_ref(&self) -> String {
        format!("refs/heads/sync/{}/proposal/{}", self.run, self.branch)
    }
    /// Where a proposal starts: the run's candidate, else the PR's new
    /// position (its parent's candidate, or the new root base).
    pub fn start(&self) -> String {
        if let Some(c) = &self.candidate {
            return c.clone();
        }
        match &self.parent {
            Some(p) => format!("refs/heads/sync/{}/{p}", self.run),
            None => self.new_base.clone(),
        }
    }
}

pub fn load(db: &Path, results: &Path, run: i64, pr: i64) -> Result<Subject, String> {
    let c = crate::job::open_ro(db)?;
    let sql = |e: rusqlite::Error| format!("{}: {e}", db.display());
    let (repo, bases): (String, String) =
        c.query_row("SELECT repo, bases FROM sync_run WHERE id = ?1", [run], |r| Ok((r.get(0)?, r.get(1)?))).map_err(|_| format!("no sync run {run}"))?;
    let (branch, root, parent, gh_head, new_head, state, detail): (String, String, Option<String>, String, Option<String>, String, Option<String>) = c
        .query_row(
            "SELECT branch, root, parent, gh_head, new_head, state, detail FROM sync_pr WHERE run_id = ?1 AND number = ?2",
            rusqlite::params![run, pr],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?, r.get(6)?)),
        )
        .map_err(|_| format!("PR #{pr} is not part of run {run}"))?;
    let (stage, stage_detail): (String, String) = c
        .query_row(
            "SELECT name, coalesce(detail,'') FROM sync_stage WHERE run_id = ?1 AND state = 'failed' ORDER BY rowid DESC LIMIT 1",
            [run],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap_or_default();
    let _ = sql;
    let parsed = crate::syncrun::parse_bases(&bases)?;
    let (old_base, _) = parsed.get(&root).cloned().ok_or_else(|| format!("root {root} is not a base of run {run}"))?;
    Ok(Subject {
        run,
        pr,
        branch,
        new_base: format!("refs/sync/base/{root}"),
        root,
        parent,
        state,
        detail: detail.unwrap_or_default(),
        stage,
        stage_detail,
        repo: PathBuf::from(repo),
        results: results.to_path_buf(),
        old_base,
        old_head: gh_head,
        candidate: new_head,
    })
}

// --- output hygiene -----------------------------------------------------------

/// Keys, tokens and password lines out of anything the model reads.
pub fn redact(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for line in text.split_inclusive('\n') {
        if line.to_lowercase().contains("password") {
            out.push_str("[line redacted: it names a password]\n");
            continue;
        }
        out.push_str(&redact_tokens(line));
    }
    out
}

fn redact_tokens(line: &str) -> String {
    const PREFIXES: &[(&str, usize)] = &[("sk-ant-", 10), ("github_pat_", 20), ("ghp_", 20), ("gho_", 20), ("ghu_", 20), ("ghs_", 20), ("ghr_", 20)];
    let tok = |c: char| c.is_ascii_alphanumeric() || c == '_' || c == '-';
    let mut out = String::new();
    let mut rest = line;
    loop {
        // the earliest credential in what is left, whichever its prefix
        let hit = PREFIXES
            .iter()
            .flat_map(|(p, min)| rest.match_indices(p).map(move |(i, _)| (i, *p, *min)))
            .filter(|(i, p, min)| {
                let before_ok = rest[..*i].chars().next_back().map_or(true, |c| !tok(c));
                before_ok && rest[i + p.len()..].chars().take_while(|c| tok(*c)).count() >= *min
            })
            .min_by_key(|(i, _, _)| *i);
        let Some((i, p, _)) = hit else {
            out.push_str(rest);
            return out;
        };
        let tail = &rest[i + p.len()..];
        let n: usize = tail.chars().take_while(|c| tok(*c)).map(char::len_utf8).sum();
        out.push_str(&rest[..i]);
        out.push_str("[redacted credential]");
        rest = &tail[n..];
    }
}

/// A page of `text`: lines `offset..offset+limit`, capped, with where to go on.
pub fn page(text: &str, offset: usize, limit: usize) -> String {
    let lines: Vec<&str> = text.lines().collect();
    let total = lines.len();
    let limit = limit.clamp(1, MAX_LINES);
    let start = offset.min(total);
    let mut out = String::new();
    let mut end = start;
    for l in &lines[start..(start + limit).min(total)] {
        if out.len() + l.len() + 1 > MAX_CHARS {
            break;
        }
        out.push_str(l);
        out.push('\n');
        end += 1;
    }
    let out = redact(&out);
    if end < total {
        format!("{out}[lines {}-{} of {total}; continue with offset {end}]", start + 1, end)
    } else if total == 0 {
        "[empty]".into()
    } else {
        format!("{out}[lines {}-{end} of {total}; end]", start + 1)
    }
}

// --- git, bounded to the subject ---------------------------------------------

fn git(repo: &Path, args: &[&str]) -> Result<String, String> {
    let o = Command::new("git").arg("-C").arg(repo).args(args).env_remove("GIT_DIR").output().map_err(|e| format!("git: {e}"))?;
    if !o.status.success() {
        return Err(format!("git {}: {}", args.first().unwrap_or(&""), String::from_utf8_lossy(&o.stderr).trim()));
    }
    Ok(String::from_utf8_lossy(&o.stdout).to_string())
}

/// A repository-relative path, nothing that leaves the tree or names a rev.
pub fn safe_path(p: &str) -> Result<&str, String> {
    let ok = !p.is_empty()
        && !p.starts_with('/')
        && !p.starts_with('-')
        && !p.contains(':')
        && !p.contains('\0')
        && p.split('/').all(|c| !c.is_empty() && c != ".." && c != ".");
    if ok {
        Ok(p)
    } else {
        Err(format!("'{p}' is not a repository-relative path"))
    }
}

fn rev_of(s: &Subject, kind: &str) -> Result<String, String> {
    match kind {
        "old_base" => Ok(s.old_base.clone()),
        "new_base" => Ok(s.new_base.clone()),
        "pr_head" => Ok(s.old_head.clone()),
        "candidate" => s.candidate.clone().ok_or_else(|| "this PR has no candidate in the run".into()),
        "proposal" => git(&s.repo, &["rev-parse", "--verify", "-q", &s.proposal_ref()]).map(|x| x.trim().to_string()).map_err(|_| "no proposal yet".into()),
        other => Err(format!("revision '{other}': one of old_base, new_base, pr_head, candidate, proposal")),
    }
}

/// The PR's own change, from where it branched to its head before the sync.
fn own_change(s: &Subject) -> Result<String, String> {
    let fork_point = git(&s.repo, &["merge-base", &s.old_base, &s.old_head])?;
    let base = match &s.parent {
        // a stacked PR's own commits start at its parent's old head
        Some(p) => git(&s.repo, &["merge-base", &format!("refs/heads/{p}"), &s.old_head]).unwrap_or(fork_point),
        None => fork_point,
    };
    git(&s.repo, &["diff", base.trim(), &s.old_head])
}

/// Commit `diff` on top of the proposal (or its start) with plumbing only:
/// a private index, the ref moved with its old value checked.
pub fn propose_patch(s: &Subject, diff: &str, message: &str, author: &crate::author::Author) -> Result<String, String> {
    if diff.len() > 2_000_000 {
        return Err("the diff exceeds 2 MB".into());
    }
    let msg = message.trim();
    if msg.is_empty() || msg.len() > 4000 {
        return Err("a commit message of 1-4000 characters is required".into());
    }
    let tip = rev_of(s, "proposal").ok();
    let parent = match &tip {
        Some(t) => t.clone(),
        None => git(&s.repo, &["rev-parse", "--verify", &format!("{}^{{commit}}", s.start())])?.trim().to_string(),
    };
    static SEQ: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let n = SEQ.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let dir = std::env::temp_dir().join(format!("shk-mcp-{}-{n}", std::process::id()));
    std::fs::create_dir_all(&dir).map_err(|e| format!("{e}"))?;
    let index = dir.join("index");
    let patch = dir.join("p.diff");
    std::fs::write(&patch, diff).map_err(|e| format!("{e}"))?;
    let run = |args: &[&str]| -> Result<String, String> {
        let o = Command::new("git")
            .arg("-C")
            .arg(&s.repo)
            .env("GIT_INDEX_FILE", &index)
            .env("GIT_AUTHOR_NAME", &author.name)
            .env("GIT_AUTHOR_EMAIL", &author.email)
            .env("GIT_COMMITTER_NAME", &author.name)
            .env("GIT_COMMITTER_EMAIL", &author.email)
            .args(args)
            .output()
            .map_err(|e| format!("git: {e}"))?;
        if !o.status.success() {
            return Err(String::from_utf8_lossy(&o.stderr).trim().to_string());
        }
        Ok(String::from_utf8_lossy(&o.stdout).trim().to_string())
    };
    let r = (|| {
        run(&["read-tree", &parent])?;
        run(&["apply", "--cached", "--recount", "--whitespace=nowarn", &patch.to_string_lossy()]).map_err(|e| format!("the diff does not apply to the proposal: {e}"))?;
        let tree = run(&["write-tree"])?;
        let old_tree = run(&["rev-parse", &format!("{parent}^{{tree}}")])?;
        if tree == old_tree {
            return Err("the diff changes nothing".into());
        }
        let commit = run(&["commit-tree", &tree, "-p", &parent, "-m", msg])?;
        let old = tip.clone().unwrap_or_else(|| "0".repeat(40));
        run(&["update-ref", &s.proposal_ref(), &commit, &old])?;
        let stat = run(&["diff", "--stat", &parent, &commit])?;
        Ok(format!("proposal {} on {}:\n{stat}", &commit[..12], s.proposal_ref()))
    })();
    let _ = std::fs::remove_dir_all(&dir);
    r
}

// --- the tools -----------------------------------------------------------------

pub fn tools(profile: Profile) -> Value {
    let page_props = json!({"offset": {"type": "integer", "minimum": 0, "description": "first line, 0-based"}, "limit": {"type": "integer", "minimum": 1, "maximum": MAX_LINES}});
    let with = |extra: Value| {
        let mut m = page_props.as_object().cloned().unwrap_or_default();
        if let Value::Object(e) = extra {
            m.extend(e);
        }
        Value::Object(m)
    };
    let mut t = vec![
        json!({"name": "subject", "description": "What this escalation is about: the sync run, the PR, the stage that stopped, its refusal, the revisions and where proposals go.", "inputSchema": {"type": "object", "properties": {}, "additionalProperties": false}}),
        json!({"name": "pr_diff", "description": "The PR's own change (its commits before the sync), as a unified diff, paginated.", "inputSchema": {"type": "object", "properties": page_props, "additionalProperties": false}}),
        json!({"name": "upstream_diff", "description": "What upstream changed in one path between the old and the new base, paginated.", "inputSchema": {"type": "object", "properties": with(json!({"path": {"type": "string"}})), "required": ["path"], "additionalProperties": false}}),
        json!({"name": "file_at", "description": "A file at one of the named revisions: old_base, new_base, pr_head, candidate, proposal; paginated.", "inputSchema": {"type": "object", "properties": with(json!({"rev": {"type": "string", "enum": ["old_base", "new_base", "pr_head", "candidate", "proposal"]}, "path": {"type": "string"}})), "required": ["rev", "path"], "additionalProperties": false}}),
        json!({"name": "list_files", "description": "Paths under a directory at a named revision.", "inputSchema": {"type": "object", "properties": with(json!({"rev": {"type": "string", "enum": ["old_base", "new_base", "pr_head", "candidate", "proposal"]}, "dir": {"type": "string"}})), "required": ["rev", "dir"], "additionalProperties": false}}),
        json!({"name": "log_excerpt", "description": "Lines of a stage log of this run (ANALYZE, REBASE, VERIFY, PREPARE, FASTLOOP, GATE, PUBLISH), optionally only those containing a text.", "inputSchema": {"type": "object", "properties": with(json!({"stage": {"type": "string", "enum": crate::syncrun::STAGES}, "contains": {"type": "string"}})), "required": ["stage"], "additionalProperties": false}}),
        json!({"name": "rules", "description": "The project's rules (changelog, commits, PR text, quality), optionally filtered by scope.", "inputSchema": {"type": "object", "properties": with(json!({"scope": {"type": "string"}})), "additionalProperties": false}}),
        json!({"name": "findings", "description": "Recorded findings whose title or evidence contains a text.", "inputSchema": {"type": "object", "properties": with(json!({"contains": {"type": "string"}})), "required": ["contains"], "additionalProperties": false}}),
    ];
    if profile == Profile::Escalation {
        t.push(json!({"name": "propose_patch", "description": "Commit a unified diff (git apply format, repository-relative paths) on top of the current proposal, or of the PR's new position for the first one. Writes only the proposal ref; nothing is pushed.", "inputSchema": {"type": "object", "properties": {"diff": {"type": "string"}, "message": {"type": "string", "description": "commit message"}}, "required": ["diff", "message"], "additionalProperties": false}}));
        t.push(json!({"name": "verify", "description": "Run sharukhan's checks (rpmspec, check_spec, the one-changelog-entry rule) on the proposal against the new base. Takes minutes.", "inputSchema": {"type": "object", "properties": {}, "additionalProperties": false}}));
        t.push(json!({"name": "propose_description", "description": "Propose the PR description for the proposal (Problem, Change, Testing, Dependencies if stacked, the Generated-with footer). It is linted; nothing is published.", "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"], "additionalProperties": false}}));
    }
    json!(t)
}

fn arg_usize(a: &Value, k: &str, d: usize) -> usize {
    a.get(k).and_then(Value::as_u64).map(|v| v as usize).unwrap_or(d)
}

fn arg_str<'a>(a: &'a Value, k: &str) -> Result<&'a str, String> {
    a.get(k).and_then(Value::as_str).ok_or_else(|| format!("'{k}' is required"))
}

pub struct Server {
    pub subject: Subject,
    pub profile: Profile,
    pub db: PathBuf,
    pub common: PathBuf,
}

impl Server {
    pub fn call(&self, name: &str, a: &Value) -> Result<String, String> {
        let s = &self.subject;
        let (off, lim) = (arg_usize(a, "offset", 0), arg_usize(a, "limit", MAX_LINES));
        match name {
            "subject" => Ok(redact(&format!(
                "sync run {run}, PR #{pr} ({branch}), state {state}: {detail}\nstopped at {stage}: {sd}\nroot {root}{parent}\nrevisions: old_base {ob}, new_base {nb}, pr_head {oh}, candidate {cand}\nproposals go to {pref}, starting from {start}\n",
                run = s.run,
                pr = s.pr,
                branch = s.branch,
                state = s.state,
                detail = s.detail,
                stage = if s.stage.is_empty() { "-" } else { &s.stage },
                sd = s.stage_detail,
                root = s.root,
                parent = s.parent.as_ref().map(|p| format!(", stacked on {p}")).unwrap_or_default(),
                ob = &s.old_base[..s.old_base.len().min(12)],
                nb = s.new_base,
                oh = &s.old_head[..s.old_head.len().min(12)],
                cand = s.candidate.as_deref().map(|c| &c[..c.len().min(12)]).unwrap_or("none"),
                pref = s.proposal_ref(),
                start = s.start(),
            ))),
            "pr_diff" => Ok(page(&own_change(s)?, off, lim)),
            "upstream_diff" => {
                let p = safe_path(arg_str(a, "path")?)?;
                Ok(page(&git(&s.repo, &["diff", "-M", &s.old_base, &s.new_base, "--", p])?, off, lim))
            }
            "file_at" => {
                let rev = rev_of(s, arg_str(a, "rev")?)?;
                let p = safe_path(arg_str(a, "path")?)?;
                Ok(page(&git(&s.repo, &["show", &format!("{rev}:{p}")])?, off, lim))
            }
            "list_files" => {
                let rev = rev_of(s, arg_str(a, "rev")?)?;
                let d = safe_path(arg_str(a, "dir")?.trim_end_matches('/'))?;
                Ok(page(&git(&s.repo, &["ls-tree", "-r", "--name-only", &rev, "--", &format!("{d}/")])?, off, lim))
            }
            "log_excerpt" => {
                let stage = arg_str(a, "stage")?;
                if !crate::syncrun::STAGES.contains(&stage) {
                    return Err(format!("unknown stage {stage}"));
                }
                let p = s.results.join("sync").join(s.run.to_string()).join(format!("{stage}.log"));
                let text = std::fs::read_to_string(&p).map_err(|_| format!("no {stage}.log in run {}", s.run))?;
                let text = match a.get("contains").and_then(Value::as_str) {
                    Some(c) => text.lines().filter(|l| l.contains(c)).collect::<Vec<_>>().join("\n"),
                    None => text,
                };
                Ok(page(&text, off, lim))
            }
            "rules" => {
                let c = crate::job::open_ro(&self.db)?;
                let scope = a.get("scope").and_then(Value::as_str).unwrap_or("%");
                let mut st = c
                    .prepare("SELECT slug, scope, rule, coalesce(how_to_apply,'') FROM rule WHERE superseded_by IS NULL AND scope LIKE ?1 ORDER BY scope, slug")
                    .map_err(|e| format!("{e}"))?;
                let rows: Vec<String> = st
                    .query_map([scope], |r| Ok(format!("[{}] {}: {}\n  how: {}", r.get::<_, String>(1)?, r.get::<_, String>(0)?, r.get::<_, String>(2)?, r.get::<_, String>(3)?)))
                    .map_err(|e| format!("{e}"))?
                    .flatten()
                    .collect();
                Ok(page(&rows.join("\n"), off, lim))
            }
            "findings" => {
                let c = crate::job::open_ro(&self.db)?;
                let q = format!("%{}%", arg_str(a, "contains")?);
                let mut st = c
                    .prepare("SELECT slug, severity, title, evidence, coalesce(mitigation,'') FROM finding WHERE superseded_by IS NULL AND (title LIKE ?1 OR evidence LIKE ?1) ORDER BY id DESC LIMIT 40")
                    .map_err(|e| format!("{e}"))?;
                let rows: Vec<String> = st
                    .query_map([q], |r| {
                        Ok(format!("{} [{}] {}\n  observed: {}\n  mitigation: {}", r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?, r.get::<_, String>(3)?, r.get::<_, String>(4)?))
                    })
                    .map_err(|e| format!("{e}"))?
                    .flatten()
                    .collect();
                Ok(page(&rows.join("\n"), off, lim))
            }
            "propose_patch" | "verify" | "propose_description" if self.profile != Profile::Escalation => Err(format!("{name} is not available in the read-only profile")),
            "propose_patch" => {
                let author = crate::author::resolve(Some(&s.repo))?;
                propose_patch(s, arg_str(a, "diff")?, arg_str(a, "message")?, &author).map(|x| redact(&x))
            }
            "verify" => {
                let head = rev_of(s, "proposal")?;
                let author = crate::author::resolve(Some(&s.repo))?.line();
                let work = crate::builder::shared_root().join(format!("work/mcp-verify-{}-{}", s.run, s.pr));
                let mut log = Vec::new();
                let checks = crate::sync::verify(&s.repo, &s.new_base, &head, &self.common, &work, &author, &mut |l| log.push(l.to_string()))?;
                let _ = std::fs::remove_dir_all(&work);
                let bad: Vec<String> = checks.iter().filter(|c| !c.ok).map(|c| format!("FAIL {} sr{} {}: {}", c.spec, c.subrelease, c.what, c.detail)).collect();
                Ok(page(&format!("{} check(s), {} failed\n{}", checks.len(), bad.len(), bad.join("\n")), 0, MAX_LINES))
            }
            "propose_description" => {
                let text = arg_str(a, "text")?;
                let head = rev_of(s, "proposal").or_else(|_| rev_of(s, "candidate"))?;
                let problems = description_problems(s, &head, text)?;
                let dir = s.results.join("sync").join(s.run.to_string()).join("PUBLISH");
                std::fs::create_dir_all(&dir).map_err(|e| format!("{e}"))?;
                std::fs::write(dir.join(format!("{}.proposed", s.pr)), text).map_err(|e| format!("{e}"))?;
                std::fs::write(dir.join(format!("{}.proposed.head", s.pr)), format!("{head}\n")).map_err(|e| format!("{e}"))?;
                Ok(if problems.is_empty() { "recorded; the lint passes".into() } else { format!("recorded; the lint finds: {}", problems.join("; ")) })
            }
            other => Err(format!("no tool {other}")),
        }
    }
}

/// The lint of a description for `head`, the proposal of `s`. The change
/// differs by construction, so only the facts are checked.
pub fn description_problems(s: &Subject, head: &str, text: &str) -> Result<Vec<String>, String> {
    let facts = crate::prbody::gather(&s.repo, &s.old_base, &s.new_base, &s.old_head, head, None, None)?;
    let facts = crate::prbody::Facts { change_differs: Vec::new(), ..facts };
    let mut problems = crate::prbody::lint(text, &facts);
    if s.parent.is_some() && !text.contains("## Dependencies") {
        problems.push("a stacked PR needs a Dependencies section".into());
    }
    Ok(problems)
}

/// The description an escalation proposed for `head`, as sharukhan judges it.
pub fn proposed_description(s: &Subject, head: &str) -> Result<String, String> {
    let dir = s.results.join("sync").join(s.run.to_string()).join("PUBLISH");
    let Ok(text) = std::fs::read_to_string(dir.join(format!("{}.proposed", s.pr))) else { return Ok("no description proposed".into()) };
    let for_head = std::fs::read_to_string(dir.join(format!("{}.proposed.head", s.pr))).unwrap_or_default();
    if for_head.trim() != head {
        return Ok("the proposed description was written for an earlier proposal".into());
    }
    let p = description_problems(s, head, &text)?;
    Ok(if p.is_empty() {
        format!("its description passes the lint; `sharukhan sync body --set {} {} proposed` takes it after the decision", s.run, s.pr)
    } else {
        format!("its description fails the lint: {}", p.join("; "))
    })
}

/// One JSON-RPC message in, at most one out.
pub fn handle(server: &Server, msg: &Value) -> Option<Value> {
    let id = msg.get("id").cloned();
    let method = msg.get("method").and_then(Value::as_str).unwrap_or("");
    let reply = |result: Value| Some(json!({"jsonrpc": "2.0", "id": id.clone()?, "result": result}));
    let error = |code: i64, m: String| Some(json!({"jsonrpc": "2.0", "id": id.clone()?, "error": {"code": code, "message": m}}));
    match method {
        "initialize" => {
            let asked = msg.pointer("/params/protocolVersion").and_then(Value::as_str).unwrap_or(PROTOCOL);
            let v = if SUPPORTED.contains(&asked) { asked } else { PROTOCOL };
            reply(json!({"protocolVersion": v, "capabilities": {"tools": {"listChanged": false}}, "serverInfo": {"name": "sharukhan", "version": env!("CARGO_PKG_VERSION")}}))
        }
        "ping" => reply(json!({})),
        "tools/list" => reply(json!({"tools": tools(server.profile)})),
        "tools/call" => {
            let name = msg.pointer("/params/name").and_then(Value::as_str).unwrap_or("");
            let args = msg.pointer("/params/arguments").cloned().unwrap_or(json!({}));
            match server.call(name, &args) {
                Ok(text) => reply(json!({"content": [{"type": "text", "text": text}], "isError": false})),
                Err(e) => reply(json!({"content": [{"type": "text", "text": redact(&e)}], "isError": true})),
            }
        }
        m if m.starts_with("notifications/") => None,
        _ => error(-32601, format!("method not found: {method}")),
    }
}

pub fn serve(server: &Server) -> Result<(), String> {
    let stdin = std::io::stdin();
    let mut out = std::io::stdout().lock();
    for line in stdin.lock().lines() {
        let line = line.map_err(|e| format!("stdin: {e}"))?;
        if line.trim().is_empty() {
            continue;
        }
        let reply = match serde_json::from_str::<Value>(&line) {
            Ok(msg) => handle(server, &msg),
            Err(e) => Some(json!({"jsonrpc": "2.0", "id": null, "error": {"code": -32700, "message": format!("parse error: {e}")}})),
        };
        if let Some(r) = reply {
            writeln!(out, "{r}").map_err(|e| format!("stdout: {e}"))?;
            out.flush().map_err(|e| format!("stdout: {e}"))?;
        }
    }
    Ok(())
}

pub fn cli(cfg: &crate::config::Config, args: &[String]) -> Result<(), String> {
    let usage = "sharukhan mcp --run <id> --pr <n> [--profile escalation|readonly]";
    let flag = |n: &str| args.iter().position(|a| a == n).and_then(|i| args.get(i + 1)).cloned();
    let run: i64 = flag("--run").and_then(|v| v.parse().ok()).ok_or(usage)?;
    let pr: i64 = flag("--pr").and_then(|v| v.parse().ok()).ok_or(usage)?;
    let profile = match flag("--profile").as_deref() {
        None | Some("readonly") => Profile::Readonly,
        Some("escalation") => Profile::Escalation,
        Some(o) => return Err(format!("--profile {o}: escalation or readonly")),
    };
    let subject = load(&cfg.memory_db, &cfg.results_dir, run, pr)?;
    let server = Server { subject, profile, db: cfg.memory_db.clone(), common: crate::builder::shared_root().join("work/common-check") };
    serve(&server)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn credentials_and_password_lines_never_leave() {
        let t = "key sk-ant-api03-AbCdEfGhIjKlMnOp_q end\nGH ghp_0123456789abcdefghijABCD and github_pat_11ABCDEFG0123456789_xyz\nMC_GUEST_PASSWORD=x\nskip sk-ant-x\n";
        let r = redact(t);
        assert!(!r.contains("AbCdEf") && !r.contains("0123456789abcdef") && !r.contains("11ABCDEFG"), "{r}");
        assert!(r.contains("[line redacted: it names a password]"));
        assert!(r.contains("skip sk-ant-x"), "a short tail is not a key: {r}");
        assert_eq!(r.matches("[redacted credential]").count(), 3, "{r}");
    }

    #[test]
    fn pages_are_capped_and_say_where_to_continue() {
        let text: String = (0..1000).map(|i| format!("line {i}\n")).collect();
        let p = page(&text, 0, 10_000);
        assert!(p.ends_with("[lines 1-300 of 1000; continue with offset 300]"), "{}", &p[p.len() - 60..]);
        let last = page(&text, 990, 50);
        assert!(last.ends_with("[lines 991-1000 of 1000; end]"));
        let wide: String = (0..300).map(|_| "x".repeat(200) + "\n").collect();
        assert!(page(&wide, 0, 300).len() < MAX_CHARS + 100);
        assert_eq!(page("", 0, 10), "[empty]");
    }

    #[test]
    fn only_repository_relative_paths_are_accepted() {
        for ok in ["SPECS/92/linux/linux.spec", "support/x.py"] {
            assert!(safe_path(ok).is_ok(), "{ok}");
        }
        for bad in ["", "/etc/passwd", "../x", "SPECS/../../x", "HEAD:x", "-n", "a//b", "./a"] {
            assert!(safe_path(bad).is_err(), "{bad}");
        }
    }

    fn server(profile: Profile) -> Server {
        Server {
            subject: Subject {
                run: 9,
                pr: 23,
                branch: "fix/x".into(),
                root: "5.0".into(),
                parent: None,
                state: "refused".into(),
                detail: "conflict".into(),
                stage: "REBASE".into(),
                stage_detail: "1 refused".into(),
                repo: PathBuf::from("/nonexistent"),
                results: PathBuf::from("/nonexistent"),
                old_base: "a".repeat(40),
                new_base: "refs/sync/base/5.0".into(),
                old_head: "b".repeat(40),
                candidate: None,
            },
            profile,
            db: PathBuf::from("/nonexistent"),
            common: PathBuf::from("/nonexistent"),
        }
    }

    #[test]
    fn the_protocol_handshake_and_tool_listing_follow_mcp() {
        let s = server(Profile::Readonly);
        let init = handle(&s, &json!({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-03-26"}})).unwrap();
        assert_eq!(init["result"]["protocolVersion"], "2025-03-26");
        assert!(handle(&s, &json!({"jsonrpc": "2.0", "method": "notifications/initialized"})).is_none());
        let list = handle(&s, &json!({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})).unwrap();
        let names: Vec<&str> = list["result"]["tools"].as_array().unwrap().iter().map(|t| t["name"].as_str().unwrap()).collect();
        assert!(names.contains(&"subject") && !names.contains(&"propose_patch"), "{names:?}");
        let esc = server(Profile::Escalation);
        let list = handle(&esc, &json!({"jsonrpc": "2.0", "id": 3, "method": "tools/list"})).unwrap();
        assert!(list["result"]["tools"].as_array().unwrap().iter().any(|t| t["name"] == "propose_patch"));
        let unknown = handle(&s, &json!({"jsonrpc": "2.0", "id": 4, "method": "resources/list"})).unwrap();
        assert_eq!(unknown["error"]["code"], -32601);
    }

    #[test]
    fn a_readonly_server_refuses_writes_and_reports_tool_errors_as_results() {
        let s = server(Profile::Readonly);
        let r = handle(&s, &json!({"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {"name": "propose_patch", "arguments": {"diff": "x", "message": "m"}}})).unwrap();
        assert_eq!(r["result"]["isError"], true);
        assert!(r["result"]["content"][0]["text"].as_str().unwrap().contains("read-only"));
        let r = handle(&s, &json!({"jsonrpc": "2.0", "id": 6, "method": "tools/call", "params": {"name": "file_at", "arguments": {"rev": "HEAD", "path": "x"}}})).unwrap();
        assert!(r["result"]["content"][0]["text"].as_str().unwrap().contains("one of old_base"));
        let r = handle(&s, &json!({"jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": {"name": "subject", "arguments": {}}})).unwrap();
        assert!(r["result"]["content"][0]["text"].as_str().unwrap().contains("PR #23 (fix/x)"));
    }

    #[test]
    fn a_proposal_is_a_commit_on_its_own_ref_only() {
        let d = std::env::temp_dir().join(format!("shk-mcp-repo-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(d.join("SPECS/x")).unwrap();
        std::fs::write(d.join("SPECS/x/x.spec"), "Name: x\nRelease: 1\n").unwrap();
        let g = |a: &[&str]| {
            let o = Command::new("git").arg("-C").arg(&d).args(a).output().unwrap();
            assert!(o.status.success(), "{a:?}: {}", String::from_utf8_lossy(&o.stderr));
            String::from_utf8_lossy(&o.stdout).trim().to_string()
        };
        g(&["init", "-q"]);
        g(&["add", "-A"]);
        g(&["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base"]);
        let base = g(&["rev-parse", "HEAD"]);
        g(&["update-ref", "refs/sync/base/5.0", &base]);
        let mut s = server(Profile::Escalation).subject;
        s.repo = d.clone();
        let who = crate::author::parse("Ada <ada@example.org>").unwrap();
        let diff = "--- a/SPECS/x/x.spec\n+++ b/SPECS/x/x.spec\n@@ -1,2 +1,2 @@\n Name: x\n-Release: 1\n+Release: 2\n";
        let out = propose_patch(&s, diff, "x: bump", &who).unwrap();
        assert!(out.contains("refs/heads/sync/9/proposal/fix/x"), "{out}");
        assert_eq!(g(&["show", "refs/heads/sync/9/proposal/fix/x:SPECS/x/x.spec"]), "Name: x\nRelease: 2");
        assert_eq!(g(&["rev-parse", "refs/sync/base/5.0"]), base, "the base is untouched");
        assert_eq!(g(&["log", "-1", "--format=%an <%ae>", "refs/heads/sync/9/proposal/fix/x"]), "Ada <ada@example.org>");
        assert!(propose_patch(&s, diff, "again", &who).unwrap_err().contains("does not apply"));
        assert!(propose_patch(&s, "", "empty", &who).is_err());
        let _ = std::fs::remove_dir_all(&d);
    }
}
