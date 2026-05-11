# Photon OS URL Health Issues - branch common

**Source file:** photonos-urlhealth-common_202605112124.prn

**Total packages analyzed:** 6

**Total packages with issues:** 4

## Summary

| # | Issue Category | Count | Severity |
|---|---|---|---|
| 2 | URL substitution unfinished | 1 | High |
| 5 | Version comparison anomaly (UpdateAvailable contains Warning) | 2 | Medium |
| 7 | Update version detected but UpdateURL/HealthUpdateURL blank (packaging format changed) | 2 | Medium |

---

## 2. URL Substitution Unfinished

| # | Spec | Name | Source0 Original | Modified Source0 | Fix Suggestion |
|---|---|---|---|---|---|
| 1 | stalld.spec | stalld | `https://gitlab.com/rt-linux-tools/stalld/-/archive/v%{version}/%{name}-v%{versio` | `` | Fix the Source0 URL pattern. The version/name substitution is incomplete -- check for nested or malformed macros. |

---

## 5. Version Comparison Anomaly

| # | Spec | Name | Version Warning | Fix Suggestion |
|---|---|---|---|---|
| 1 | linux.spec | v6.1 | Warning: linux.spec Source0 version 6.1.83-acvp} is higher than detected latest version 6.12.87 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 2 | linux.spec | v6.12 | Warning: linux.spec Source0 version 6.12.69-acvp} is higher than detected latest version 6.12.87 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |

---

## 7. Update Version Detected but Update URL Not Constructed (Packaging Format Changed)

| # | Spec | Name | Update Available | Warning | Fix Suggestion |
|---|---|---|---|---|---|
| 1 | linux-esx.spec | v6.1 | 6.12.87 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 2 | linux-rt.spec | v6.1 | 6.12.87 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |

---

