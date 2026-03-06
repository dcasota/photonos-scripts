# Task 007: Validate Against Commit 6b7bc7c Reference Case

**Dependencies**: Tasks 004, 005
**Complexity**: Medium
**Status**: Complete

---

## Description

Run the full detection pipeline against the local build tree at the state after commit 6b7bc7c with snapshot 91 configured. Verify all expected findings are produced.

## Expected Findings

### C1 CRITICAL (3)

1. `libcap` split: libcap-doc, libcap-libs, libcap-minimal -- consumers: libcap, rpm
2. `gawk` split: gawk-all-langpacks, gawk-bin, gawk-devel, gawk-extras -- consumer: gawk
3. `strace` split: strace-bin -- consumer: strace

### C2 HIGH (4)

1. `rpm` -> `libcap-libs` (from libcap >= 92)
2. `pgbackrest` -> `postgresql18-devel` (from postgresql18 >= 92)
3. `python3-psycopg2` -> `postgresql18-devel`
4. `apr-util` -> `postgresql18-devel`

### C3 CRITICAL (86)

Distributed across 6 root-cause packages. Key validations:
- systemd flagged for Linux-PAM, dbus, libcap
- openssh flagged for Linux-PAM
- sudo flagged for Linux-PAM
- samba-client flagged for dbus

### C4 WARNING (2)

5.0+6.0 Intel driver divergence at thresholds 91 and 92.

### C5 WARNING (2)

linux and linux-esx FIPS canister deps in 6.0.

## Validation

```bash
python3 photon-gating-agent.py --base-dir /root --branches 4.0,5.0,6.0 --check-urls
# Expected: exit code 1, 97 findings, 89 CRITICAL
```

## Result

Scan completed 2026-03-06T20:48:03Z: **97 findings (89 CRITICAL, 4 HIGH, 4 WARNING)**. All expected findings confirmed.
