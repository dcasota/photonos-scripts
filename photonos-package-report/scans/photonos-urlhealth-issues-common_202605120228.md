# Photon OS URL Health Issues - branch common

**Source file:** photonos-urlhealth-common_202605120228.prn

**Total packages analyzed:** 6

**Total packages with issues:** 1

## Summary

| # | Issue Category | Count | Severity |
|---|---|---|---|
| 5 | Version comparison anomaly (UpdateAvailable contains Warning) | 2 | Medium |

---

## 5. Version Comparison Anomaly

| # | Spec | Name | Version Warning | Fix Suggestion |
|---|---|---|---|---|
| 1 | linux.spec | v6.1 | Warning: linux.spec Source0 version 6.1.83-acvp} is higher than detected latest version 6.12.87 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 2 | linux.spec | v6.12 | Warning: linux.spec Source0 version 6.12.69-acvp} is higher than detected latest version 6.12.87 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |

---

