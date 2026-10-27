//! The documentation is checked like code: every relative link and anchor in
//! README.md, docs/ and archive/README.md must resolve, and every
//! `sharukhan <subcommand>` the docs name must be one the CLI has.

#[cfg(test)]
mod tests {
    use std::collections::{BTreeMap, BTreeSet};
    use std::fs;
    use std::path::PathBuf;

    fn root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
    }

    /// The documents a reader is pointed at.
    fn documents() -> Vec<PathBuf> {
        let r = root();
        let mut v = vec![r.join("README.md"), r.join("archive/README.md")];
        let mut stack = vec![r.join("docs")];
        while let Some(d) = stack.pop() {
            for e in fs::read_dir(&d).unwrap().flatten() {
                let p = e.path();
                if p.is_dir() {
                    stack.push(p);
                } else if p.extension().and_then(|x| x.to_str()) == Some("md") {
                    v.push(p);
                }
            }
        }
        v.sort();
        v
    }

    /// The lines outside fenced code blocks, and the code (inline spans and
    /// fenced blocks) separately.
    fn split(text: &str) -> (Vec<String>, Vec<String>) {
        let (mut prose, mut code) = (Vec::new(), Vec::new());
        let mut fence = false;
        for l in text.lines() {
            if l.trim_start().starts_with("```") {
                fence = !fence;
                continue;
            }
            if fence {
                code.push(l.to_string());
            } else {
                prose.push(l.to_string());
                let mut rest = l;
                while let Some(a) = rest.find('`') {
                    let Some(b) = rest[a + 1..].find('`') else { break };
                    code.push(rest[a + 1..a + 1 + b].to_string());
                    rest = &rest[a + 2 + b..];
                }
            }
        }
        (prose, code)
    }

    /// GitHub's heading anchor: lower case, punctuation dropped (letters,
    /// digits, `-`, `_` and spaces kept), spaces to `-`.
    fn slug(heading: &str) -> String {
        heading
            .trim()
            .to_lowercase()
            .chars()
            .filter(|c| c.is_alphanumeric() || *c == '-' || *c == '_' || *c == ' ')
            .map(|c| if c == ' ' { '-' } else { c })
            .collect()
    }

    /// Every anchor a document offers: its headings (repeats numbered as
    /// GitHub numbers them) and explicit `<a name=...>` / `id=` anchors.
    fn anchors(text: &str) -> BTreeSet<String> {
        let (prose, _) = split(text);
        let mut seen: BTreeMap<String, usize> = BTreeMap::new();
        let mut out = BTreeSet::new();
        for l in &prose {
            let t = l.trim_start();
            if t.starts_with('#') {
                let h = t.trim_start_matches('#');
                if h.starts_with(' ') {
                    let s = slug(h);
                    let n = seen.entry(s.clone()).or_insert(0);
                    out.insert(if *n == 0 { s.clone() } else { format!("{s}-{n}") });
                    *n += 1;
                }
            }
            for key in ["name=\"", "id=\""] {
                let mut rest = l.as_str();
                while let Some(i) = rest.find(key) {
                    let v = &rest[i + key.len()..];
                    if let Some(j) = v.find('"') {
                        out.insert(v[..j].to_string());
                    }
                    rest = &rest[i + key.len()..];
                }
            }
        }
        out
    }

    /// `[text](target)` link targets outside code.
    fn links(text: &str) -> Vec<String> {
        let (prose, _) = split(text);
        let mut v = Vec::new();
        for l in &prose {
            let mut rest = l.as_str();
            while let Some(i) = rest.find("](") {
                let t = &rest[i + 2..];
                let Some(j) = t.find(')') else { break };
                v.push(t[..j].to_string());
                rest = &t[j..];
            }
        }
        v
    }

    #[test]
    fn the_anchor_rule_is_githubs() {
        assert_eq!(slug("Kernel wrappers: `sharukhan wrapper`"), "kernel-wrappers-sharukhan-wrapper");
        assert_eq!(slug("Step 1: from scratch - a host"), "step-1-from-scratch---a-host");
        assert_eq!(slug("Real-world example: kernel 7.3, the latest"), "real-world-example-kernel-73-the-latest");
    }

    #[test]
    fn every_link_and_anchor_in_the_docs_resolves() {
        let mut broken = Vec::new();
        for doc in documents() {
            let text = fs::read_to_string(&doc).unwrap();
            let dir = doc.parent().unwrap();
            for t in links(&text) {
                if t.contains("://") || t.starts_with("mailto:") {
                    continue;
                }
                let (path, frag) = t.split_once('#').unwrap_or((t.as_str(), ""));
                let target: PathBuf = if path.is_empty() { doc.clone() } else { dir.join(path) };
                if !target.exists() {
                    broken.push(format!("{}: {t} (no such path)", doc.strip_prefix(root()).unwrap().display()));
                    continue;
                }
                if !frag.is_empty() {
                    let ok = target.extension().and_then(|x| x.to_str()) == Some("md")
                        && anchors(&fs::read_to_string(&target).unwrap()).contains(frag);
                    if !ok {
                        broken.push(format!("{}: {t} (no such anchor)", doc.strip_prefix(root()).unwrap().display()));
                    }
                }
            }
        }
        assert!(broken.is_empty(), "{} broken link(s):\n{}", broken.len(), broken.join("\n"));
    }

    /// The subcommands the CLI has: the usage text, plus the ones `main`
    /// dispatches before it parses (`events`, an alias of the watcher).
    fn subcommands() -> BTreeSet<String> {
        let mut s: BTreeSet<String> = crate::USAGE
            .lines()
            .filter(|l| l.starts_with("    ") && !l.starts_with("     "))
            .filter_map(|l| l.split_whitespace().next())
            .filter(|w| w.chars().all(|c| c.is_ascii_lowercase() || c == '-'))
            .map(str::to_string)
            .collect();
        let main = fs::read_to_string(root().join("src/main.rs")).unwrap();
        for l in main.lines().filter(|l| l.contains("argv.first()")) {
            let mut rest = l;
            while let Some(i) = rest.find("\"") {
                let v = &rest[i + 1..];
                let Some(j) = v.find('"') else { break };
                if !v[..j].is_empty() && v[..j].chars().all(|c| c.is_ascii_lowercase() || c == '-') {
                    s.insert(v[..j].to_string());
                }
                rest = &v[j + 1..];
            }
        }
        s
    }

    #[test]
    fn every_subcommand_the_docs_name_exists() {
        let known = subcommands();
        assert!(known.contains("sync") && known.contains("run") && known.len() > 30, "{known:?}");
        let mut unknown = Vec::new();
        for doc in documents() {
            let (_, code) = split(&fs::read_to_string(&doc).unwrap());
            for c in &code {
                // a shell comment names things, it does not run them
                let line = match c.trim_start() {
                    t if t.starts_with('#') => continue,
                    _ => c.split(" # ").next().unwrap_or(c),
                };
                // a command word, then its subcommand
                let mut prev = "";
                let mut binary_at_command = false;
                for (i, word) in line.split_whitespace().enumerate() {
                    if binary_at_command {
                        let sub: String = word.chars().take_while(|c| c.is_ascii_lowercase() || *c == '-').collect();
                        if sub.starts_with(|c: char| c.is_ascii_lowercase()) && !known.contains(&sub) {
                            unknown.push(format!("{}: sharukhan {sub}", doc.strip_prefix(root()).unwrap().display()));
                        }
                    }
                    let at_command = i == 0
                        || matches!(prev, "$" | ";" | "&&" | "||" | "|" | "nohup" | "--" | "exec" | "time" | "setsid" | "sudo")
                        || prev.ends_with(';');
                    let w = word.trim_start_matches("$(").trim_start_matches('(');
                    binary_at_command = (at_command || word.starts_with("$(")) && (w == "sharukhan" || w.ends_with("/sharukhan"));
                    prev = word;
                }
            }
        }
        unknown.sort();
        unknown.dedup();
        assert!(unknown.is_empty(), "{} unknown subcommand(s):\n{}", unknown.len(), unknown.join("\n"));
    }

    #[test]
    fn no_document_is_too_long_to_read() {
        let long: Vec<String> = documents()
            .iter()
            .filter_map(|d| {
                let n = fs::read_to_string(d).unwrap().lines().count();
                (n > 400).then(|| format!("{}: {n} lines", d.strip_prefix(root()).unwrap().display()))
            })
            .collect();
        assert!(long.is_empty(), "split these: {long:?}");
    }
}
