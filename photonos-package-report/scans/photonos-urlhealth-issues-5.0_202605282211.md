# Photon OS URL Health Issues - branch 5.0

**Source file:** photonos-urlhealth-5.0_202605282211.prn

**Total packages analyzed:** 2

**Total packages with issues:** 1

**Vendor-pinned subrelease (frozen for a Photon sub-release) — informational, not an issue:** 1

## Summary

| # | Issue Category | Count | Severity |
|---|---|---|---|
| 7 | Update version detected but UpdateURL/HealthUpdateURL blank (packaging format changed) | 1 | Medium |

---

## 7. Update Version Detected but Update URL Not Constructed (Packaging Format Changed)

| # | Spec | Name | Update Available | Warning | Fix Suggestion |
|---|---|---|---|---|---|
| 1 | fontconfig.spec | fontconfig | 2.18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |

---

