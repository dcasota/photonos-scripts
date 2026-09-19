//! The permutation matrix.
//!
//! permutations.tsv is whitespace-aligned, not tab-separated, despite the name.
//! Splitting on '\t' silently yields zero rows, so split on whitespace.

use crate::net::NetSpec;
use std::fs;
use std::path::Path;
use std::str::FromStr;

#[derive(Debug, Clone)]
pub struct Permutation {
    pub id: String,
    pub iso_type: String,
    pub poi: String,
    pub stig: String,
    pub fs: String,
    pub mode: String,
    pub variant: String,
    pub doc: String,
    /// What mission control expects WITH all the PRs applied. `doc` vs
    /// `expect` is the whole point of the matrix: where they differ, the PRs
    /// are doing work, and a run that reproduces `doc` instead of `expect` is
    /// a PR regression.
    pub expect: String,
    /// Build-time axis, like iso_type and poi: which FIPS crypto canister the ISO
    /// carries. Rows written before this column existed default to "prebuilt",
    /// which is the x86_64 default (fips=1, canister_usage=1).
    pub canister: String,
    /// INSTALL-TIME axis: IP family, address assignment and VLAN tagging, all
    /// in one column. Rows written before this column existed default to
    /// `net::DEFAULT`, which is exactly what they already did - the column
    /// documents the status quo rather than changing it.
    ///
    /// Parsed here rather than carried as a string, so a typo fails `load`
    /// in milliseconds. It has to: POI validates only the TOP-LEVEL keys of a
    /// kickstart, so a misspelt key inside `network` is silently ignored and
    /// produces a guest with no address and no error anywhere.
    pub net: NetSpec,
}

impl Permutation {
    /// True when this row needs a human at the installer console.
    pub fn needs_operator(&self) -> bool {
        self.mode == "ui"
    }
    /// Build-time axes decide which ISO serves the row. The canister is one of
    /// them, so two rows differing only by canister need two different ISOs.
    ///
    /// `net` is DELIBERATELY EXCLUDED, and that exclusion is the whole economy
    /// of the network axis. The network config reaches the guest as
    /// `guestinfo.kickstart.data` in the VMX and is consumed by a
    /// `_setup_network()` call against an already-installed root; it never
    /// touches the media, the package set or the installer. So five network
    /// rows cost five installs and ZERO ISO builds, where a build-time axis
    /// would have cost five multi-hour builds. Adding `net` here would silently
    /// fan the ISO cache out fivefold for no difference in the artefact.
    ///
    /// `poi` is excluded from the network axis for a related reason, recorded
    /// here because it is the kind of thing that gets re-litigated:
    /// `git diff v2.8 master -- photon_installer/networkmanager.py` is EMPTY.
    /// The network code is byte-identical across the poi axis, so crossing the
    /// two would re-test the same file at the price of a second ISO.
    pub fn iso_key(&self) -> String {
        format!("{}/{}/{}", self.iso_type, self.poi, self.canister)
    }

    /// The canister column carries the canister mode and any BUILD VARIANTS
    /// joined with `+`: `prebuilt+hyperv`, `fips0-aarch64+hyperv`.
    ///
    /// A `+`-joined list rather than a new column, so the TSV keeps its shape
    /// and every row written before variants existed still parses. `iso_key`
    /// deliberately keeps the WHOLE string, so a `+hyperv` row caches as a
    /// separate ISO - it is a different artefact, and reusing the plain one
    /// would report a verdict about media that was never built.
    pub fn build_variants(&self) -> Vec<&str> {
        self.canister
            .split('+')
            .skip(1)
            .filter(|s| !s.is_empty())
            .collect()
    }

    /// The canister part alone, which is what `CanisterMode::parse` accepts.
    pub fn canister_mode(&self) -> &str {
        // `fips0-aarch64` names an ARCH as well as a mode; the arch half is
        // consumed by `arch()` and the remainder is a plain prebuilt build.
        let head = self.canister.split('+').next().unwrap_or("prebuilt");
        match head {
            "fips0-aarch64" => "prebuilt",
            other => other,
        }
    }

    /// The architecture this row's ISO is for.
    pub fn arch(&self) -> &str {
        if self
            .canister
            .split('+')
            .next()
            .unwrap_or("")
            .contains("aarch64")
        {
            "aarch64"
        } else {
            "x86_64"
        }
    }

    pub fn wants_hyperv(&self) -> bool {
        self.build_variants().contains(&"hyperv")
    }
    /// The row cannot run on this host.
    ///
    /// Two independent reasons, both environmental rather than defects: the
    /// canister axis can name aarch64-only configurations, and the network axis
    /// can name combinations this host provides no server for. Either way the
    /// row is recorded and skipped rather than run and failed - a row that
    /// fails for the harness's own reason teaches nothing.
    pub fn is_unrunnable_here(&self) -> bool {
        self.unrunnable_reason().is_some()
    }

    /// Whether this host can build an aarch64 image at all: a registered
    /// qemu-aarch64 binfmt handler. Without one, an aarch64 row needs aarch64
    /// hardware; with one, it is merely slow.
    pub fn arm64_builder_available() -> bool {
        std::fs::read_to_string("/proc/sys/fs/binfmt_misc/qemu-aarch64")
            .map(|s| s.contains("enabled"))
            .unwrap_or(false)
    }

    /// Why, in words. `plan` prints it: a year from now the reason is the only
    /// part that is hard to reconstruct.
    pub fn unrunnable_reason(&self) -> Option<String> {
        self.unrunnable_reason_with(Permutation::arm64_builder_available())
    }

    /// The same decision with the emulation probe INJECTED, so the aarch64
    /// branch can be tested on either kind of host.
    ///
    /// An aarch64 row no longer needs aarch64 hardware unconditionally: with a
    /// registered qemu-aarch64 binfmt handler and an arm64 builder image the
    /// row is buildable here, just slowly. Reporting it as impossible when it
    /// is merely slow silently drops a row from the matrix.
    pub fn unrunnable_reason_with(&self, arm64_builder: bool) -> Option<String> {
        if self.arch() == "aarch64" && std::env::consts::ARCH != "aarch64" && !arm64_builder {
            return Some(format!(
                "canister={} needs aarch64 hardware or a registered qemu-aarch64 binfmt \
                 handler plus an arm64 builder image; this host is {} and has neither",
                self.canister,
                std::env::consts::ARCH
            ));
        }
        self.net
            .unrunnable_reason()
            .map(|r| format!("net={}: {r}", self.net))
    }
}

pub fn load(path: &Path) -> Result<Vec<Permutation>, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut out = Vec::new();
    for line in text.lines() {
        let t = line.trim();
        if t.is_empty() || t.starts_with('#') {
            continue;
        }
        let f: Vec<&str> = t.split_whitespace().collect();
        if f.len() < 8 {
            continue;
        }
        out.push(Permutation {
            id: f[0].into(),
            iso_type: f[1].into(),
            poi: f[2].into(),
            stig: f[3].into(),
            fs: f[4].into(),
            mode: f[5].into(),
            variant: f[6].into(),
            doc: f[7].into(),
            expect: f.get(8).copied().unwrap_or("-").into(),
            canister: f.get(9).copied().unwrap_or("prebuilt").into(),
            // An unknown token fails the whole load, naming the row. Silently
            // defaulting would run the row as plain DHCP and report a pass for
            // an axis that was never exercised.
            net: NetSpec::from_str(f.get(10).copied().unwrap_or(crate::net::DEFAULT))
                .map_err(|e| format!("{}: row '{}': {e}", path.display(), f[0]))?,
        });
    }
    if out.is_empty() {
        return Err(format!("no permutations parsed from {}", path.display()));
    }
    Ok(out)
}

/// Filter by a comma-separated id list. Unknown ids are an error rather than a
/// silent no-op: asking for a row that does not exist should never look like a
/// clean run.
pub fn select(all: &[Permutation], only: Option<&str>) -> Result<Vec<Permutation>, String> {
    let Some(spec) = only else {
        return Ok(all.to_vec());
    };
    let want: Vec<&str> = spec
        .split(',')
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .collect();
    let mut out = Vec::new();
    let mut missing = Vec::new();
    for id in &want {
        match all.iter().find(|p| p.id == *id) {
            Some(p) => out.push(p.clone()),
            None => missing.push(id.to_string()),
        }
    }
    if !missing.is_empty() {
        return Err(format!("unknown permutation id(s): {}", missing.join(", ")));
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row_with(canister: &str, net: &str) -> Permutation {
        Permutation {
            id: "x".into(),
            iso_type: "full".into(),
            poi: "2.8".into(),
            stig: "no".into(),
            fs: "ext4".into(),
            mode: "ks".into(),
            variant: "none".into(),
            doc: "untested".into(),
            expect: "pass".into(),
            canister: canister.into(),
            net: NetSpec::from_str(net).unwrap(),
        }
    }

    /// The file is whitespace-aligned despite the .tsv name. Splitting on '\t'
    /// yields zero rows and `load` would then have to invent an error, so the
    /// separator is the property to pin.
    #[test]
    fn a_whitespace_aligned_row_parses_including_the_canister_column() {
        let d = std::env::temp_dir().join(format!("sk-matrix-{}", std::process::id()));
        std::fs::create_dir_all(&d).unwrap();
        let f = d.join("permutations.tsv");
        std::fs::write(
            &f,
            "# comment\n\
             k09      full      2.8     no    ext4   ks    none        untested   pass   prebuilt\n\
             c01      full      2.8     no    ext4   ks    none        untested   pass    equivalent\n\
             n04      minimal   2.8     no    ext4   ks    none        untested   pass    prebuilt    v4-static-vlan100\n",
        )
        .unwrap();
        let rows = load(&f).unwrap();
        std::fs::remove_dir_all(&d).ok();

        assert_eq!(rows.len(), 3);
        assert_eq!(rows[1].id, "c01");
        assert_eq!(rows[1].canister, "equivalent");
        // A row with no net column parses, and lands on the token every
        // pre-existing row has always used.
        assert!(rows[1].net.is_default(), "{}", rows[1].net);
        assert_eq!(rows[2].net.vlan, Some(100));
        assert_eq!(rows[2].net.schema(), crate::net::Schema::V2);
    }

    /// The parser is the only place a typo in this axis can be caught: POI
    /// validates only the top-level keys of a kickstart, so a misspelt key
    /// inside `network` is silently ignored and yields a guest with no address
    /// and no error. A bad token must therefore fail the LOAD, naming the row,
    /// rather than quietly running as plain DHCP and reporting a pass for an
    /// axis nothing exercised.
    #[test]
    fn a_bad_net_token_fails_the_load_and_names_the_row() {
        let d = std::env::temp_dir().join(format!("sk-matrix-net-{}", std::process::id()));
        std::fs::create_dir_all(&d).unwrap();
        let f = d.join("permutations.tsv");
        std::fs::write(
            &f,
            "n99      minimal   2.8     no    ext4   ks    none        untested   pass    prebuilt    v4-dhpc-untag\n",
        )
        .unwrap();
        let e = load(&f).unwrap_err();
        std::fs::remove_dir_all(&d).ok();
        assert!(e.contains("n99"), "{e}");
        assert!(e.contains("v4-dhpc-untag"), "{e}");
    }

    /// Five network rows must cost five installs and no ISO builds. If `net`
    /// ever reached iso_key, the cache would fan out fivefold and each row
    /// would demand a multi-hour build for media identical to k01's.
    #[test]
    fn the_network_axis_never_reaches_the_iso_cache() {
        let base = row_with("prebuilt", "v4-dhcp-untag");
        for token in [
            "v4-static-untag",
            "dual-static-untag",
            "v6-static-untag",
            "v4-static-vlan100",
            "v4-dhcp-vlan100",
        ] {
            assert_eq!(
                row_with("prebuilt", token).iso_key(),
                base.iso_key(),
                "net={token} must not create a new ISO"
            );
        }
    }

    /// A DHCPv6 row has no server to lease from on this host - VMnetDHCP.exe is
    /// IPv4-only - so it is recorded as unrunnable rather than run and failed,
    /// on the c02 precedent. The REASON is what plan prints.
    #[test]
    fn an_environmentally_impossible_net_row_is_unrunnable_with_a_reason() {
        let r = row_with("prebuilt", "v6-dhcp-untag");
        assert!(r.is_unrunnable_here());
        let why = r.unrunnable_reason().unwrap();
        assert!(why.contains("DHCPv6"), "{why}");
        assert!(!row_with("prebuilt", "v6-static-untag").is_unrunnable_here());
    }

    /// c01 and k09 differ in exactly one axis, and that axis is build-time. If
    /// the canister ever dropped out of iso_key the equivalent row would reuse
    /// the cached prebuilt ISO and report a verdict about the wrong artefact -
    /// which is the same class of silent no-op canister=build turned out to be.
    #[test]
    fn the_equivalent_row_cannot_reuse_the_prebuilt_iso() {
        let row = |canister: &str| row_with(canister, crate::net::DEFAULT);
        assert_ne!(row("prebuilt").iso_key(), row("equivalent").iso_key());
        assert_eq!(row("equivalent").iso_key(), "full/2.8/equivalent");
        // and an equivalent row is autonomous: mode=ks needs no operator.
        assert!(!row("equivalent").needs_operator());
        // fips0-aarch64 is the only value that gates on the host arch.
        assert!(!row("equivalent").is_unrunnable_here());
        assert_eq!(
            row("fips0-aarch64").unrunnable_reason_with(false).is_some(),
            std::env::consts::ARCH != "aarch64"
        );
    }

    /// The canister column carries the mode and any build variants joined with
    /// `+`, so the TSV keeps its shape and every pre-existing row still parses.
    /// `fips0-aarch64` was previously unparseable as a canister mode at all.
    #[test]
    fn a_plus_joined_canister_column_splits_into_canister_and_variants() {
        let hv = row_with("prebuilt+hyperv", crate::net::DEFAULT);
        assert_eq!(hv.canister_mode(), "prebuilt");
        assert_eq!(hv.build_variants(), vec!["hyperv"]);
        assert!(hv.wants_hyperv());

        let plain = row_with("prebuilt", crate::net::DEFAULT);
        assert!(
            plain.build_variants().is_empty(),
            "a bare column has no variants"
        );
        assert!(!plain.wants_hyperv());
        assert_eq!(plain.arch(), "x86_64");

        // fips0-aarch64 names an ARCH as well as a mode; the remainder is a
        // plain prebuilt build, which is what makes it parseable at last.
        let a = row_with("fips0-aarch64+hyperv", crate::net::DEFAULT);
        assert_eq!(a.canister_mode(), "prebuilt");
        assert_eq!(a.arch(), "aarch64");
        assert!(a.wants_hyperv());

        // Whatever comes out of canister_mode must be something the build
        // layer actually accepts, or the split is decorative.
        for r in [&hv, &plain, &a] {
            assert!(
                crate::buildmode::CanisterMode::parse(r.canister_mode()).is_ok(),
                "canister_mode() gave {:?}, which CanisterMode::parse rejects",
                r.canister_mode()
            );
        }
    }

    /// A `+hyperv` ISO is a DIFFERENT artefact. If it shared an iso_key with
    /// the plain row it would reuse the cached non-Hyper-V media and report a
    /// verdict about an ISO that was never built.
    #[test]
    fn iso_key_distinguishes_hyperv_isos() {
        let plain = row_with("prebuilt", crate::net::DEFAULT);
        let hv = row_with("prebuilt+hyperv", crate::net::DEFAULT);
        assert_ne!(plain.iso_key(), hv.iso_key());
        assert_eq!(hv.iso_key(), "full/2.8/prebuilt+hyperv");
        assert_eq!(plain.iso_key(), "full/2.8/prebuilt");
    }

    /// An aarch64 row is buildable on an x86_64 host that has qemu-aarch64
    /// binfmt registered - slowly, but buildable. Calling it impossible drops
    /// the row from the matrix for a reason that no longer holds.
    #[test]
    fn fips0_aarch64_is_runnable_on_x86_64_when_an_arm64_builder_is_registered() {
        let r = row_with("fips0-aarch64+hyperv", crate::net::DEFAULT);
        assert!(
            r.unrunnable_reason_with(true).is_none(),
            "with an arm64 builder the row is merely slow, not impossible"
        );
        let why = r.unrunnable_reason_with(false).unwrap_or_default();
        if std::env::consts::ARCH != "aarch64" {
            assert!(
                why.contains("binfmt"),
                "the reason must say what is missing: {why}"
            );
            assert!(why.contains("aarch64 hardware"), "{why}");
        }
    }
}
