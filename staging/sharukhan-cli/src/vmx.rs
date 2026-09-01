//! Rendering photon-matrix.vmx.template.
//!
//! The template stays a template, embedded verbatim. It is ~60% comments and
//! every one of them is a scar - the CDROM on SATA, the absent pciSlotNumber
//! pins, bios.bootOrder being ignored on EFI. As `writeln!` calls those
//! comments drift away from the lines they explain, and the file stops being
//! diffable against a .vmx VMware actually wrote, which is how the layout was
//! established in the first place.
//!
//! It is included from the mission-control config directory rather than copied
//! into this crate: permutations.tsv is read from there at runtime already,
//! and two copies of a file whose comments carry the knowledge is exactly the
//! drift this module exists to prevent.

use crate::b64;
use crate::config::Config;
use crate::matrix::Permutation;
use std::borrow::Cow;

pub const EMBEDDED: &str = include_str!("../../mission-control/config/photon-matrix.vmx.template");

/// The template actually in use. MC_VMX_TEMPLATE loads one from disk so a VMX
/// experiment does not need a rebuild; without it the embedded copy is used,
/// which is the one the placeholder test checks.
pub fn template() -> Result<Cow<'static, str>, String> {
    match std::env::var("MC_VMX_TEMPLATE") {
        Ok(p) if !p.is_empty() => std::fs::read_to_string(&p)
            .map(Cow::Owned)
            .map_err(|e| format!("MC_VMX_TEMPLATE={p}: {e}")),
        _ => Ok(Cow::Borrowed(EMBEDDED)),
    }
}

/// The kickstart, if this permutation has one.
///
/// Presence is a type, not string surgery. POI's isoInstaller reads
/// `guestinfo.kickstart.data` (base64) via vmtoolsd, which is present in the
/// installer initrd as /usr/bin/vmtoolsd - that is why an autonomous
/// permutation needs no ISO remaster and no typing at the boot menu.
/// Its ABSENCE is equally load-bearing: with no kickstart the installer falls
/// through to the curses configurator, which is the only place the STIG menu
/// exists. mode=ui is that absence, so it is a variant here rather than an
/// else-branch that happens to emit a comment.
pub struct Kickstart {
    pub json: String,
}

pub struct VmSpec {
    pub name: String,
    pub vcpus: u32,
    pub mem_mb: u32,
    pub mac: String,
    pub uuid_bios: String,
    /// Windows form. VMware cannot open a WSL path - see [`crate::winpath`].
    pub iso_win: String,
    pub serial_win: String,
    pub nic_dev: String,
    pub secure_boot: bool,
    pub kickstart: Option<Kickstart>,
}

impl VmSpec {
    /// The spec for one matrix row. Everything the row does not carry comes
    /// from the typed config, so a per-run override still reaches the VMX.
    pub fn for_permutation(
        cfg: &Config,
        p: &Permutation,
        mac: String,
        uuid_bios: String,
        iso_win: String,
        serial_win: String,
        kickstart: Option<Kickstart>,
    ) -> Self {
        VmSpec {
            name: cfg.vm_name(&p.id),
            vcpus: cfg.guest_vcpus,
            mem_mb: cfg.guest_mem_mb,
            mac,
            uuid_bios,
            iso_win,
            serial_win,
            nic_dev: cfg.nic_dev.clone(),
            // Secure boot is off across the matrix: no row varies it, and
            // turning it on would test the signing chain rather than the PRs.
            secure_boot: false,
            kickstart,
        }
    }

    /// The guestinfo line, or the comment that explains why there is none.
    fn guestinfo(&self) -> String {
        match &self.kickstart {
            Some(ks) => format!(
                "guestinfo.kickstart.data = \"{}\"",
                b64::encode(ks.json.as_bytes())
            ),
            None => {
                "# no kickstart: interactive install, the operator drives the curses configurator"
                    .to_string()
            }
        }
    }

    /// Every placeholder this renderer knows how to fill. The test below
    /// asserts this set is exactly the set the template asks for.
    fn substitutions(&self) -> Vec<(&'static str, String)> {
        vec![
            ("VM_NAME", self.name.clone()),
            ("GUEST_VCPUS", self.vcpus.to_string()),
            ("GUEST_MEM_MB", self.mem_mb.to_string()),
            ("GUEST_MAC", self.mac.clone()),
            ("UUID_BIOS", self.uuid_bios.clone()),
            ("ISO_PATH_WIN", self.iso_win.clone()),
            ("SERIAL_LOG_WIN", self.serial_win.clone()),
            ("NIC_DEV", self.nic_dev.clone()),
            (
                "SECUREBOOT",
                if self.secure_boot { "TRUE" } else { "FALSE" }.to_string(),
            ),
            ("GUESTINFO_KICKSTART", self.guestinfo()),
        ]
    }
}

/// Render `spec` into a complete VMX.
///
/// An unsubstituted `@@PLACEHOLDER@@` reaching a VMX is a VM that powers on
/// with a nonsense value and fails hours later, so it is refused here. For the
/// embedded template the test below turns the same mistake into a test
/// failure, which is earlier still; this check exists for MC_VMX_TEMPLATE.
pub fn render(spec: &VmSpec) -> Result<String, String> {
    render_with(&template()?, spec)
}

pub fn render_with(tpl: &str, spec: &VmSpec) -> Result<String, String> {
    let mut s = tpl.to_string();
    for (k, v) in spec.substitutions() {
        s = s.replace(&format!("@@{k}@@"), &v);
    }
    let left = placeholders(&s);
    if !left.is_empty() {
        return Err(format!(
            "unsubstituted placeholders survived: {}",
            left.join(", ")
        ));
    }
    Ok(s)
}

/// Every `@@NAME@@` token in `text`, sorted and deduplicated.
pub fn placeholders(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    let b = text.as_bytes();
    let mut i = 0;
    while i + 4 <= b.len() {
        if b[i] == b'@' && b[i + 1] == b'@' {
            let start = i + 2;
            let mut j = start;
            while j < b.len() && (b[j].is_ascii_uppercase() || b[j] == b'_') {
                j += 1;
            }
            if j > start && j + 1 < b.len() && b[j] == b'@' && b[j + 1] == b'@' {
                out.push(text[start..j].to_string());
                i = j + 2;
                continue;
            }
        }
        i += 1;
    }
    out.sort();
    out.dedup();
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spec(ks: Option<Kickstart>) -> VmSpec {
        VmSpec {
            name: "mc-k01".into(),
            vcpus: 2,
            mem_mb: 4096,
            mac: "00:50:56:3a:00:11".into(),
            uuid_bios: "56 4d 6d 63 00 00 00 00-00 00 00 00 00 00 00 11".into(),
            iso_win: "C:\\photon-mc\\iso-cache\\minimal-poi2.8-prebuilt\\photon.iso".into(),
            serial_win: "C:\\photon-mc\\vm\\mc-k01\\serial0-mc-k01.log".into(),
            nic_dev: "e1000".into(),
            secure_boot: false,
            kickstart: ks,
        }
    }

    /// The check the bash made at VM-CREATE time, in a python heredoc: too
    /// late, because by then a run has already started. A placeholder the
    /// renderer does not supply, or a substitution the template no longer
    /// asks for, now fails `cargo test` instead.
    #[test]
    fn template_placeholders_exactly_match_the_renderer() {
        let want = placeholders(EMBEDDED);
        let mut have: Vec<String> = spec(None)
            .substitutions()
            .iter()
            .map(|(k, _)| k.to_string())
            .collect();
        have.sort();
        have.dedup();
        assert_eq!(
            want, have,
            "photon-matrix.vmx.template and VmSpec::substitutions have diverged"
        );
    }

    #[test]
    fn a_rendered_vmx_carries_no_placeholders() {
        let out = render_with(EMBEDDED, &spec(None)).unwrap();
        assert!(placeholders(&out).is_empty());
        assert!(out.contains("displayName = \"mc-k01\""));
        assert!(out.contains("ethernet0.address = \"00:50:56:3a:00:11\""));
        assert!(out.contains("uefi.secureBoot.enabled = \"FALSE\""));
    }

    #[test]
    fn a_missing_substitution_is_refused_not_shipped() {
        let tpl = "displayName = \"@@VM_NAME@@\"\nfoo = \"@@NOT_A_KEY@@\"\n";
        let e = render_with(tpl, &spec(None)).unwrap_err();
        assert!(e.contains("NOT_A_KEY"), "{e}");
    }

    #[test]
    fn kickstart_presence_selects_the_guestinfo_line() {
        let with = render_with(EMBEDDED, &spec(Some(Kickstart { json: "{\"a\":1}".into() }))).unwrap();
        assert!(with.contains("guestinfo.kickstart.data = \"eyJhIjoxfQ==\""));

        // The template's own comment names guestinfo.kickstart.data, so the
        // absence that matters is an ASSIGNMENT of it, not the string.
        let without = render_with(EMBEDDED, &spec(None)).unwrap();
        assert!(!without
            .lines()
            .any(|l| l.trim_start().starts_with("guestinfo.kickstart.data")));
        assert!(without.contains("# no kickstart: interactive install"));
    }

    /// Guards the lines whose absence cost hours. Each of these is explained
    /// in the template's own comments; this test is what stops a tidy-up from
    /// deleting the line and leaving the comment.
    #[test]
    fn the_template_still_carries_its_scars() {
        // On ide1:0 the installer boots but userspace cannot find /dev/sr0,
        // and the failure reads exactly like a corrupt ISO.
        assert!(EMBEDDED.contains("sata0:1.deviceType = \"cdrom-image\""));
        assert!(!EMBEDDED.contains("ide1:0.deviceType"));
        // VMware rewrote sata0 35->18 and ethernet0 160->17 on the one
        // power-on that succeeded; pinning a foreign slot layout makes
        // power-on fail with "Error: Unknown error" and no vmware.log at all.
        assert!(!EMBEDDED
            .lines()
            .any(|l| !l.trim_start().starts_with('#') && l.contains("pciSlotNumber")));
        // The serial log is the only unambiguous liveness instrument during an
        // unattended install.
        assert!(EMBEDDED.contains("serial0.fileType = \"file\""));
        // Without autoAnswer a modal blocks power-on forever, with no output.
        assert!(EMBEDDED.contains("msg.autoAnswer = \"TRUE\""));
        // bios.bootOrder is IGNORED on EFI; teardown moving the .nvram aside
        // is the only boot-source control there is.
        assert!(EMBEDDED.contains("firmware = \"efi\""));
        // The comment naming bios.bootOrder must stay; an ASSIGNMENT of it
        // must never appear, because it would read as a boot-source control
        // that does nothing.
        assert!(!EMBEDDED
            .lines()
            .any(|l| l.trim_start().starts_with("bios.bootOrder")));
        // The guest clock must not be host-slaved; time sync is under test.
        assert!(EMBEDDED.contains("tools.syncTime = \"FALSE\""));
    }
}
