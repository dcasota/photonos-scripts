//! The installer that COMPOSES the ISO, built from the variant under test.
//!
//! Photon's `make image` does not assemble media with the photon-os-installer
//! RPM the build just produced. `support/poi/poi.py` runs a docker image
//! (`photon-build-param.poi-image`, default `photon/installer`), and the POI
//! inside THAT image decides which packages go on the media. The RPM under
//! test only ends up inside the ISO's initrd.
//!
//! On this host `photon/installer:latest` carried photon-os-installer 2.4 on a
//! Python 3.14 base. Its STIG package set still names `ntp`, which Photon 5.0
//! does not build for a minimal ISO, and on 2026-09-29 both minimal gate groups
//! burnt all ten attempts on `Error(1011) : No matching packages` for 'ntp'.
//! Earlier minimal runs had passed only because a shared stage still held an
//! `ntp` RPM left by a full build: the variant's own installer - whose 0006
//! patch drops `ntp` from that set - never composed a single ISO.
//!
//! Building the image from upstream's Dockerfile does not fix it either. That
//! Dockerfile runs `tdnf update` against the live repos, and on the same day
//! photon-updates carried librepo-1.14.5-7 requiring `libxml2.so.2` next to a
//! libxml2-2.15.4 that no longer provides it, so no image could be built at
//! all. A gate cannot hinge on the live repo being consistent at that minute.
//!
//! So the base image supplies the tooling (pinned by its image ID, and
//! recorded), and its installer is replaced by the variant's:
//!
//! 1. the variant's own spec directory (pristine `HEAD` + the variant patch),
//! 2. every archive its `config.yaml` declares, each sha512-verified,
//! 3. the spec's own `%prep`, run by `rpmbuild -bp` - its patches, its order,
//! 4. the same two steps `%py3_build` and `%py3_install` run, inside the base
//!    image's own Python,
//! 5. then proven: every file of each Python package in the image must be
//!    byte-identical to the prepped tree, with nothing extra left behind by
//!    the installer it replaced, and every console script must resolve.
//!
//! The tag is a content hash over the base image ID and every file of the
//! prepped tree, so an unchanged variant reuses its image and any change -
//! one patch line, a new base - builds a new one. The shared
//! `photon/installer:latest` is never retagged: other sessions build with it.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// Photon's own default (`support/poi/poi.py`: `POI_IMAGE = "photon/installer"`).
/// `MC_POI_BASE_IMAGE` names another base.
pub const DEFAULT_BASE: &str = "photon/installer:latest";

/// The installer spec's directory, relative to a release tree.
const SPEC_DIR: &str = "SPECS/photon-os-installer";

#[derive(Debug, Clone)]
pub struct Composer {
    /// The image to put into `photon-build-param.poi-image`.
    pub tag: String,
    /// The spec's Version (what the variant claims to ship).
    pub version: String,
    /// The base image this one was layered on, by ID.
    pub base_id: String,
    /// Package files proven identical to the prepped tree.
    pub files: usize,
}

pub fn base_ref() -> String {
    std::env::var("MC_POI_BASE_IMAGE")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| DEFAULT_BASE.to_string())
}

fn run(dir: &Path, prog: &str, args: &[&str]) -> Result<String, String> {
    let out = Command::new(prog)
        .args(args)
        .current_dir(dir)
        .output()
        .map_err(|e| format!("running {prog}: {e}"))?;
    if out.status.success() {
        Ok(String::from_utf8_lossy(&out.stdout).to_string())
    } else {
        let err = String::from_utf8_lossy(&out.stderr);
        let tail: Vec<&str> = err.trim().lines().rev().take(12).collect();
        Err(format!(
            "{prog} {} failed: {}",
            args.join(" "),
            tail.into_iter().rev().collect::<Vec<_>>().join("\n")
        ))
    }
}

fn fresh_dir(p: &Path) -> Result<(), String> {
    if p.exists() {
        fs::remove_dir_all(p).map_err(|e| format!("{}: {e}", p.display()))?;
    }
    fs::create_dir_all(p).map_err(|e| format!("{}: {e}", p.display()))
}

/// The variant's installer spec directory: the release tree's committed
/// (`HEAD`) directory with the variant patch applied - exactly what the build
/// will see once runPh5 applies the same patch to a pristine SPECS tree.
///
/// From `HEAD`, not the working tree: the working tree is whatever the last
/// build left behind, which is the very thing the SPECS reset exists to undo.
pub fn variant_spec_dir(release_tree: &Path, patch: &Path, work: &Path) -> Result<PathBuf, String> {
    let root = work.join("variant-spec");
    fresh_dir(&root)?;
    let archive = Command::new("git")
        .args(["archive", "--format=tar", "HEAD", SPEC_DIR])
        .current_dir(release_tree)
        .stdout(Stdio::piped())
        .spawn()
        .map_err(|e| format!("git archive: {e}"))?;
    let tar = Command::new("tar")
        .args(["-x", "-C"])
        .arg(&root)
        .stdin(archive.stdout.ok_or("git archive: no stdout")?)
        .status()
        .map_err(|e| format!("tar: {e}"))?;
    if !tar.success() {
        return Err(format!(
            "could not extract {SPEC_DIR} from {} at HEAD",
            release_tree.display()
        ));
    }
    // Outside any repository on purpose: inside one, `git apply` resolves
    // paths against that repository's root and ignores everything else.
    let parent = root.parent().unwrap_or(&root).to_string_lossy().to_string();
    let include = format!("--include={SPEC_DIR}/*");
    let out = Command::new("git")
        .args(["apply", "--whitespace=nowarn", &include])
        .arg(patch)
        .current_dir(&root)
        .env("GIT_CEILING_DIRECTORIES", &parent)
        .output()
        .map_err(|e| format!("git apply: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "{} does not apply to {SPEC_DIR}: {}",
            patch.display(),
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    Ok(root.join(SPEC_DIR))
}

/// The one `.spec` in the installer's spec directory. Two would make "the
/// installer" ambiguous, so that is refused rather than picked from.
fn the_spec(spec_dir: &Path) -> Result<PathBuf, String> {
    let mut specs: Vec<PathBuf> = fs::read_dir(spec_dir)
        .map_err(|e| format!("{}: {e}", spec_dir.display()))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().map(|x| x == "spec").unwrap_or(false))
        .collect();
    match specs.len() {
        1 => Ok(specs.remove(0)),
        0 => Err(format!("no .spec in {}", spec_dir.display())),
        n => Err(format!("{n} specs in {}: which one is the installer?", spec_dir.display())),
    }
}

/// Copy `archive` into `dest`, from the first place that holds it with the
/// declared sha512, fetching it into `cache` if none does. Never trusted by
/// name: an archive with no declared checksum is refused.
fn obtain(
    archive: &str,
    url: &str,
    sha: &str,
    places: &[PathBuf],
    cache: &Path,
    dest: &Path,
    log: &mut dyn FnMut(&str),
) -> Result<(), String> {
    if !crate::sha512::is_hex_digest(sha) {
        return Err(format!(
            "{archive} declares no sha512 in config.yaml: refusing to build an installer from an unverified archive"
        ));
    }
    let target = dest.join(archive);
    for d in places.iter().map(PathBuf::as_path).chain(std::iter::once(cache)) {
        let p = d.join(archive);
        if p.is_file() && crate::sha512::file(&p).ok().as_deref() == Some(sha) {
            fs::copy(&p, &target).map_err(|e| format!("{}: {e}", p.display()))?;
            return Ok(());
        }
    }
    fs::create_dir_all(cache).map_err(|e| format!("{}: {e}", cache.display()))?;
    let mirror = format!("{}/{archive}", crate::buildexec::SOURCES_MIRROR);
    for src in [url, mirror.as_str()] {
        if src.is_empty() {
            continue;
        }
        let tmp = cache.join(format!("{archive}.tmp"));
        let _ = fs::remove_file(&tmp);
        let got = Command::new("wget")
            .args(["-q", src, "-O"])
            .arg(&tmp)
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if got && crate::sha512::file(&tmp).ok().as_deref() == Some(sha) {
            let keep = cache.join(archive);
            fs::rename(&tmp, &keep).map_err(|e| format!("{}: {e}", keep.display()))?;
            fs::copy(&keep, &target).map_err(|e| format!("{}: {e}", keep.display()))?;
            log(&format!("fetched {archive} from {src} (sha512 verified)"));
            return Ok(());
        }
        let _ = fs::remove_file(&tmp);
    }
    Err(format!("{archive}: not found with sha512 {}... anywhere, and not fetchable", &sha[..16]))
}

/// Every regular file under `dir`, as (relative path, sha256), sorted, with
/// byte-compiled caches left out: they are generated, not shipped source.
fn manifest(dir: &Path) -> Result<Vec<(String, String)>, String> {
    fn walk(root: &Path, d: &Path, out: &mut Vec<(String, String)>) -> Result<(), String> {
        for e in fs::read_dir(d).map_err(|e| format!("{}: {e}", d.display()))? {
            let e = e.map_err(|e| e.to_string())?;
            let p = e.path();
            let ft = e.file_type().map_err(|e| e.to_string())?;
            if ft.is_symlink() {
                return Err(format!("{}: symlink in the installer tree", p.display()));
            }
            if ft.is_dir() {
                if e.file_name() == "__pycache__" {
                    continue;
                }
                walk(root, &p, out)?;
            } else if ft.is_file() {
                let rel = p.strip_prefix(root).unwrap().to_string_lossy().to_string();
                out.push((rel, crate::sha256::file(&p)?));
            }
        }
        Ok(())
    }
    let mut out = Vec::new();
    walk(dir, dir, &mut out)?;
    out.sort();
    Ok(out)
}

/// The prepped source tree: the one directory under `build` holding a
/// `setup.py`. %autosetup's layout differs between rpm versions (4.20 adds a
/// `<name>-<version>-build/` level), so it is found, not assumed.
fn prepped_tree(build: &Path) -> Result<PathBuf, String> {
    let mut hits = Vec::new();
    let mut stack = vec![(build.to_path_buf(), 0u8)];
    while let Some((d, depth)) = stack.pop() {
        if d.join("setup.py").is_file() {
            hits.push(d);
            continue;
        }
        if depth >= 3 {
            continue;
        }
        for e in fs::read_dir(&d).map_err(|e| format!("{}: {e}", d.display()))?.flatten() {
            if e.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                stack.push((e.path(), depth + 1));
            }
        }
    }
    match hits.len() {
        1 => Ok(hits.remove(0)),
        0 => Err(format!("%prep left no setup.py under {}", build.display())),
        _ => Err(format!("%prep left {} setup.py trees under {}", hits.len(), build.display())),
    }
}

/// Top-level Python packages of the tree (directories with `__init__.py`):
/// what `%py3_install` puts into site-packages and what must match.
fn packages(tree: &Path) -> Result<Vec<String>, String> {
    let mut out: Vec<String> = fs::read_dir(tree)
        .map_err(|e| format!("{}: {e}", tree.display()))?
        .flatten()
        .filter(|e| e.path().join("__init__.py").is_file())
        .map(|e| e.file_name().to_string_lossy().to_string())
        .filter(|n| n != "tests")
        .collect();
    out.sort();
    if out.is_empty() {
        return Err(format!("no Python package in {}", tree.display()));
    }
    Ok(out)
}

/// `name = module:func` entries of setup.py's console_scripts.
pub(crate) fn console_scripts(setup_py: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let mut inside = false;
    for line in setup_py.lines() {
        if line.contains("console_scripts") {
            inside = true;
            continue;
        }
        if !inside {
            continue;
        }
        let t = line.trim();
        if t.starts_with(']') {
            break;
        }
        let t = t.trim_end_matches(',').trim_matches(|c| c == '\'' || c == '"');
        if let Some((name, target)) = t.split_once('=') {
            let module = target.trim().split(':').next().unwrap_or("").trim();
            if !name.trim().is_empty() && !module.is_empty() {
                out.push((name.trim().to_string(), module.to_string()));
            }
        }
    }
    out
}

/// Whether the installer shells out to `prog` (`["prog", ...]` in its code).
fn shells_out_to(tree: &Path, pkgs: &[String], prog: &str) -> bool {
    let needle = format!("[\"{prog}\"");
    let needle2 = format!("['{prog}'");
    pkgs.iter().any(|p| {
        manifest(&tree.join(p)).unwrap_or_default().iter().any(|(rel, _)| {
            rel.ends_with(".py")
                && fs::read_to_string(tree.join(p).join(rel))
                    .map(|t| t.contains(&needle) || t.contains(&needle2))
                    .unwrap_or(false)
        })
    })
}

fn image_id(r: &str) -> Option<String> {
    run(Path::new("/"), "docker", &["image", "inspect", "--format", "{{.Id}}", r])
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

fn in_image(image: &str, script: &str, args: &[&str]) -> Result<String, String> {
    let mut a = vec!["run", "--rm", "--network=none", "--entrypoint", "/bin/sh", image, "-c", script, "sh"];
    a.extend_from_slice(args);
    run(Path::new("/"), "docker", &a)
}

/// Build (or reuse) the composer for the installer spec in `spec_dir`.
pub fn ensure(
    spec_dir: &Path,
    source_dirs: &[PathBuf],
    work: &Path,
    base: &str,
    log: &mut dyn FnMut(&str),
) -> Result<Composer, String> {
    let base_id = image_id(base).ok_or_else(|| {
        format!("the composer base image {base} is not present; set MC_POI_BASE_IMAGE or load it first")
    })?;
    let spec = the_spec(spec_dir)?;
    let spec_s = spec.to_string_lossy().to_string();
    let sdir = format!("_sourcedir {}", spec_dir.display());
    let q = |fmt: &str| {
        run(Path::new("/"), "rpmspec", &["-q", "--srpm", "-D", &sdir, "-D", "dist .ph5", "--qf", fmt, &spec_s])
            .map(|s| s.trim().to_string())
    };
    let name = q("%{NAME}")?;
    let version = q("%{VERSION}")?;

    // --- sources: the spec directory plus every declared archive -----------
    let sources = work.join("sources");
    fresh_dir(&sources)?;
    for e in fs::read_dir(spec_dir).map_err(|e| format!("{}: {e}", spec_dir.display()))?.flatten() {
        if e.file_type().map(|t| t.is_file()).unwrap_or(false) {
            fs::copy(e.path(), sources.join(e.file_name())).map_err(|x| format!("{}: {x}", e.path().display()))?;
        }
    }
    let declared = crate::buildexec::declared_sources(&spec_dir.join("config.yaml"));
    if declared.is_empty() {
        return Err(format!("{}/config.yaml declares no source archive", spec_dir.display()));
    }
    for (archive, url, sha) in &declared {
        obtain(archive, url, sha, source_dirs, &work.join("cache"), &sources, log)?;
    }

    // --- %prep, the spec's own ----------------------------------------------
    let build = work.join("build");
    fresh_dir(&build)?;
    let top = work.join("top");
    fresh_dir(&top)?;
    run(
        Path::new("/"),
        "rpmbuild",
        &[
            "-bp",
            "--nodeps",
            "-D",
            &format!("_topdir {}", top.display()),
            "-D",
            &format!("_sourcedir {}", sources.display()),
            "-D",
            &format!("_builddir {}", build.display()),
            "-D",
            "dist .ph5",
            &spec_s,
        ],
    )
    .map_err(|e| format!("%prep of {}: {e}", spec.display()))?;
    let tree = prepped_tree(&build)?;
    let pkgs = packages(&tree)?;
    let setup = fs::read_to_string(tree.join("setup.py")).map_err(|e| format!("setup.py: {e}"))?;
    let scripts = console_scripts(&setup);

    // --- content address ----------------------------------------------------
    let mut h = format!("base {base_id}\n");
    for (rel, sum) in manifest(&tree)? {
        h.push_str(&format!("{sum}  {rel}\n"));
    }
    let digest = crate::sha256::bytes(h.as_bytes());
    let tag = format!("sharukhan/{name}:{version}-{}", &digest[..16]);

    // Tools the installer runs that ISO assembly dies without. Checked in the
    // BASE: this layer adds nothing but the installer, and so must not need
    // the network.
    if shells_out_to(&tree, &pkgs, "file")
        && in_image(&base_id, "command -v file", &[]).is_err()
    {
        return Err(format!(
            "{name} {version} runs `file` during initrd generation and the base {base} has none"
        ));
    }

    if image_id(&tag).is_some() {
        log(&format!("composer {tag} already built from this exact tree: reusing it"));
    } else {
        let ctx = work.join("ctx");
        fresh_dir(&ctx)?;
        run(Path::new("/"), "cp", &["-a", &tree.to_string_lossy(), &ctx.join("src").to_string_lossy()])?;
        // The spec's %build/%install are %py3_build/%py3_install; these are
        // their two commands, run by the base image's own interpreter so the
        // files land in ITS site-packages. The RPM of the installer being
        // replaced goes first: its file list would otherwise keep claiming
        // the old version in the image's rpmdb.
        let dockerfile = format!(
            "FROM {base_id}\n\
             COPY src /tmp/poi-src\n\
             RUN if rpm -q {name} >/dev/null 2>&1; then rpm -e --nodeps {name}; fi \\\n \
             && cd /tmp/poi-src \\\n \
             && python3 setup.py build --executable=\"/usr/bin/python3 -s\" \\\n \
             && python3 setup.py install -O1 --skip-build --root / \\\n \
             && cd / && rm -rf /tmp/poi-src\n\
             LABEL org.photon.sharukhan.base=\"{base_id}\" org.photon.sharukhan.installer=\"{name}-{version}\" org.photon.sharukhan.tree=\"{digest}\"\n"
        );
        fs::write(ctx.join("Dockerfile"), dockerfile).map_err(|e| format!("Dockerfile: {e}"))?;
        log(&format!("building composer {tag} on {base} ({})", &base_id[..19.min(base_id.len())]));
        let blog = work.join("docker-build.log");
        let f = fs::File::create(&blog).map_err(|e| format!("{}: {e}", blog.display()))?;
        let f2 = f.try_clone().map_err(|e| e.to_string())?;
        let st = Command::new("docker")
            .args(["build", "--network=none", "-t", &tag])
            .arg(&ctx)
            .env("DOCKER_BUILDKIT", "0")
            .stdout(Stdio::from(f))
            .stderr(Stdio::from(f2))
            .status()
            .map_err(|e| format!("docker build: {e}"))?;
        if !st.success() {
            return Err(format!("building {tag} failed, see {}", blog.display()));
        }
    }

    // --- proof ----------------------------------------------------------------
    let files = verify(&tag, &name, &tree, &pkgs, &scripts)?;
    log(&format!(
        "composer {tag}: {name} {version}, {files} file(s) in {} identical to the variant's %prep, {} console script(s) resolve",
        pkgs.join(", "),
        scripts.len()
    ));
    Ok(Composer { tag, version, base_id, files })
}

/// The image carries the tree, the whole tree, and nothing but the tree.
fn verify(
    tag: &str,
    name: &str,
    tree: &Path,
    pkgs: &[String],
    scripts: &[(String, String)],
) -> Result<usize, String> {
    // Where the image's Python imports each package from, then every file
    // there. `find -type f` with sha256sum, relative to the package's parent.
    let script = r#"set -e
for p in "$@"; do
  d=$(python3 -W ignore -c "import importlib.util,os,sys; s=importlib.util.find_spec(sys.argv[1]); print(os.path.dirname(s.origin))" "$p")
  echo "@pkg $p $d"
  ( cd "$(dirname "$d")" && find "$p" -type f ! -path '*/__pycache__/*' -exec sha256sum {} + )
done"#;
    let args: Vec<&str> = pkgs.iter().map(String::as_str).collect();
    let out = in_image(tag, script, &args)?;
    let mut image: Vec<(String, String)> = Vec::new();
    for line in out.lines() {
        if line.starts_with("@pkg ") {
            continue;
        }
        if let Some((sum, rel)) = line.split_once("  ") {
            image.push((rel.to_string(), sum.to_string()));
        }
    }
    image.sort();
    let mut want: Vec<(String, String)> = Vec::new();
    for p in pkgs {
        for (rel, sum) in manifest(&tree.join(p))? {
            want.push((format!("{p}/{rel}"), sum));
        }
    }
    want.sort();
    if image != want {
        let img: std::collections::BTreeMap<_, _> = image.iter().cloned().collect();
        let src: std::collections::BTreeMap<_, _> = want.iter().cloned().collect();
        let mut diffs = Vec::new();
        for (rel, s) in &src {
            match img.get(rel) {
                None => diffs.push(format!("missing {rel}")),
                Some(i) if i != s => diffs.push(format!("differs {rel}")),
                _ => {}
            }
        }
        for rel in img.keys().filter(|r| !src.contains_key(*r)) {
            diffs.push(format!("extra {rel}"));
        }
        diffs.truncate(12);
        return Err(format!(
            "{tag} does not carry the variant's installer: {}",
            diffs.join("; ")
        ));
    }
    // No rpmdb entry left claiming another version of the installer.
    if in_image(tag, "rpm -q \"$1\"", &[name]).is_ok() {
        return Err(format!("{tag}: the rpmdb still lists {name}, i.e. the replaced installer"));
    }
    for (script, module) in scripts {
        in_image(
            tag,
            "command -v \"$1\" >/dev/null && python3 -W ignore -c \"import $2\"",
            &[script, module],
        )
        .map_err(|e| format!("{tag}: console script {script} ({module}) does not resolve: {e}"))?;
    }
    Ok(want.len())
}

/// The composer for a variant patch against the configured build trees.
pub fn for_variant(
    cfg: &crate::config::Config,
    patch: &Path,
    log: &mut dyn FnMut(&str),
) -> Result<Composer, String> {
    let work = cfg.work.join("poi-image");
    let spec_dir = variant_spec_dir(&cfg.photon_tree, patch, &work)?;
    let sources = [
        cfg.photon_tree.join("stage/SOURCES"),
        cfg.build_root.join(&cfg.build_common).join("stage/SOURCES"),
    ];
    ensure(&spec_dir, &sources, &work, &base_ref(), log)
}

/// Point build.py at `tag`: `photon-build-param.poi-image` in the COMMON
/// tree's build-config.json, where build.py reads it - then read it back.
pub fn point_build_config(common_tree: &Path, tag: &str) -> Result<Option<String>, String> {
    let cfg_path = common_tree.join("build-config.json");
    let text = fs::read_to_string(&cfg_path).map_err(|e| format!("{}: {e}", cfg_path.display()))?;
    let mut v: serde_json::Value =
        serde_json::from_str(&text).map_err(|e| format!("{}: {e}", cfg_path.display()))?;
    let param = v
        .as_object_mut()
        .ok_or_else(|| format!("{} is not a JSON object", cfg_path.display()))?
        .entry("photon-build-param")
        .or_insert_with(|| serde_json::json!({}))
        .as_object_mut()
        .ok_or_else(|| format!("{}: photon-build-param is not an object", cfg_path.display()))?;
    let before = param.get("poi-image").and_then(|x| x.as_str()).map(str::to_string);
    param.insert("poi-image".into(), serde_json::Value::String(tag.into()));
    let new = serde_json::to_string_pretty(&v).map_err(|e| e.to_string())? + "\n";
    fs::write(&cfg_path, &new).map_err(|e| format!("{}: {e}", cfg_path.display()))?;
    let check: serde_json::Value = serde_json::from_str(
        &fs::read_to_string(&cfg_path).map_err(|e| format!("{}: {e}", cfg_path.display()))?,
    )
    .map_err(|e| format!("{}: {e}", cfg_path.display()))?;
    if check["photon-build-param"]["poi-image"].as_str() != Some(tag) {
        return Err(format!("{} does not name {tag} after the write", cfg_path.display()));
    }
    Ok(before)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn console_scripts_are_read_from_setup_py() {
        let s = "setup(\n    entry_points={\n        'console_scripts': [\n            'photon-installer = photon_installer.main:main',\n            'photon-iso-builder = photon_installer.isoBuilder:main'\n        ]\n    },\n)\n";
        assert_eq!(
            console_scripts(s),
            vec![
                ("photon-installer".to_string(), "photon_installer.main".to_string()),
                ("photon-iso-builder".to_string(), "photon_installer.isoBuilder".to_string()),
            ]
        );
    }

    #[test]
    fn the_prepped_tree_is_found_below_an_rpm_4_20_build_level() {
        let tmp = std::env::temp_dir().join(format!("shk-poi-tree-{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        let t = tmp.join("x-2.8-build/x-2.8");
        fs::create_dir_all(t.join("pkg")).unwrap();
        fs::write(t.join("setup.py"), "").unwrap();
        fs::write(t.join("pkg/__init__.py"), "").unwrap();
        fs::create_dir_all(t.join("tests")).unwrap();
        fs::write(t.join("tests/__init__.py"), "").unwrap();
        assert_eq!(prepped_tree(&tmp).unwrap(), t);
        assert_eq!(packages(&t).unwrap(), vec!["pkg".to_string()]);
        fs::create_dir_all(tmp.join("y/z")).unwrap();
        fs::write(tmp.join("y/z/setup.py"), "").unwrap();
        assert!(prepped_tree(&tmp).is_err(), "two trees must be refused, not picked from");
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn manifest_skips_bytecode_and_refuses_symlinks() {
        let tmp = std::env::temp_dir().join(format!("shk-poi-man-{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(tmp.join("__pycache__")).unwrap();
        fs::write(tmp.join("a.py"), "x").unwrap();
        fs::write(tmp.join("__pycache__/a.cpython-314.pyc"), "y").unwrap();
        let m = manifest(&tmp).unwrap();
        assert_eq!(m.len(), 1);
        assert_eq!(m[0].0, "a.py");
        std::os::unix::fs::symlink("a.py", tmp.join("b.py")).unwrap();
        assert!(manifest(&tmp).is_err());
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn build_config_is_pointed_and_read_back() {
        let tmp = std::env::temp_dir().join(format!("shk-poi-cfg-{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();
        fs::write(
            tmp.join("build-config.json"),
            "{\"photon-build-param\": {\"poi-image\": \"photon/installer:latest\", \"x\": 1}}",
        )
        .unwrap();
        let before = point_build_config(&tmp, "sharukhan/p:2.8-abc").unwrap();
        assert_eq!(before.as_deref(), Some("photon/installer:latest"));
        let v: serde_json::Value =
            serde_json::from_str(&fs::read_to_string(tmp.join("build-config.json")).unwrap()).unwrap();
        assert_eq!(v["photon-build-param"]["poi-image"], "sharukhan/p:2.8-abc");
        assert_eq!(v["photon-build-param"]["x"], 1);
        let _ = fs::remove_dir_all(&tmp);
    }
}
