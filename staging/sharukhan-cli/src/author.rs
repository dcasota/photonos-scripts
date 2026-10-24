//! Who the harness writes as: the `%changelog` entries a sync renumbers, the
//! committer of the commits it replays, the entries the one-entry rule counts
//! as the PR's own.
//!
//! MC_AUTHOR (`Name <email>`), else git's `user.name`/`user.email` of the
//! repository at hand. Neither set is an error: a changelog entry under a
//! guessed name is a false statement, and own entries would no longer be
//! recognised as such.

use std::path::Path;
use std::process::Command;

#[derive(Debug, Clone, PartialEq)]
pub struct Author {
    pub name: String,
    pub email: String,
}

impl Author {
    /// `Name <email>`, as a `%changelog` header carries it.
    pub fn line(&self) -> String {
        format!("{} <{}>", self.name, self.email)
    }
}

pub fn parse(s: &str) -> Result<Author, String> {
    let s = s.trim();
    let (name, rest) = s.split_once('<').ok_or_else(|| format!("'{s}' is not 'Name <email>'"))?;
    let email = rest.strip_suffix('>').ok_or_else(|| format!("'{s}' is not 'Name <email>'"))?.trim();
    let name = name.trim();
    if name.is_empty() || name.contains(['<', '>']) {
        return Err(format!("'{s}': the name is empty or holds '<'/'>'"));
    }
    let (local, domain) = email.split_once('@').ok_or_else(|| format!("'{email}' is not an email address"))?;
    if local.is_empty() || domain.is_empty() || email.contains(char::is_whitespace) || email.matches('@').count() != 1 {
        return Err(format!("'{email}' is not an email address"));
    }
    Ok(Author { name: name.to_string(), email: email.to_string() })
}

/// MC_AUTHOR, else the git identity configured for `repo` (or globally).
pub fn resolve(repo: Option<&Path>) -> Result<Author, String> {
    if let Some(v) = std::env::var("MC_AUTHOR").ok().filter(|v| !v.trim().is_empty()) {
        return parse(&v).map_err(|e| format!("MC_AUTHOR: {e}"));
    }
    let get = |key: &str| -> Option<String> {
        let mut c = Command::new("git");
        if let Some(r) = repo {
            c.arg("-C").arg(r);
        }
        let o = c.args(["config", "--get", key]).output().ok()?;
        o.status.success().then(|| String::from_utf8_lossy(&o.stdout).trim().to_string()).filter(|v| !v.is_empty())
    };
    match (get("user.name"), get("user.email")) {
        (Some(n), Some(e)) => parse(&format!("{n} <{e}>")).map_err(|x| format!("git user.name/user.email: {x}")),
        _ => Err("no author: set MC_AUTHOR='Name <email>' or git's user.name and user.email".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_author_parses_and_prints_as_a_changelog_header_does() {
        let a = parse("  Ada Lovelace <ada@example.org> ").unwrap();
        assert_eq!(a.name, "Ada Lovelace");
        assert_eq!(a.line(), "Ada Lovelace <ada@example.org>");
    }

    #[test]
    fn malformed_authors_are_refused() {
        for bad in ["Ada", "<ada@example.org>", "Ada <ada>", "Ada <a@b@c>", "Ada <a b@c>", "Ada <ada@example.org", "A<b <a@b>"] {
            assert!(parse(bad).is_err(), "{bad}");
        }
    }
}
