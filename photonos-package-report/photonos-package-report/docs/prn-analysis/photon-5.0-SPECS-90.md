# PRN incomplete-entry analysis — photon-5.0 SPECS/90

**Source PRN:** `photonos-urlhealth-5.0_202605171536.prn` (PS-side, 2026-05-17 15:36 UTC, run 25991871716).

**Scope:** rows from `<workingDir>/photon-5.0/SPECS/90/<pkg>/<pkg>.spec`.

## Snapshot-staleness caveat

The PS scan that produced the source PRN pinned `photon-5.0` at SHA `ac37e5567` (dated **2026-03-06**, commit `trace-cmd: retry build as an attempt to fix intermittent build failure`). The `SPECS/90/` subdirectory **did not exist** at that SHA — only `SPECS/91/` did. Therefore:

- **Rows in the PRN from SPECS/90:** **0**
- **SPECS/90 was created later** — in commit `09e9a0796` (2026-05-12, `gnutls: update to latest`) and expanded across May 12-14. Today (2026-05-17), `origin/vmware/photon/SPECS/90/` carries **53 packages**.

The two-month gap between the runner's pinned `photon-5.0` clone and the current upstream HEAD is a separate finding worth tracking — the PS workflow clones `vmware/photon` once and never `git fetch`es before subsequent scans, so today's snapshot describes the March state of photon-5.0, not the current state.

## What SPECS/90 contains on current origin/5.0 (53 packages)

Pulled via `gh api repos/vmware/photon/contents/SPECS/90?ref=5.0`:

```
GConf                    ImageMagick           Linux-PAM             ModemManager
ant-contrib              aufs-util             bash-completion       bluez-tools
bubblewrap               calico-bgp-daemon     cppunit               createrepo_c
dbus                     dotnet-runtime        dotnet-sdk            dracut
drpm                     eventlog              geoip-api-c           gpsd
hiredis                  inotify-tools         libcap                libdaemon
libdnet                  libmodulemd           libnetfilter_conntrack librepo
libsoup                  libteam               lttng-tools           lttng-ust
mdadm                    msr-tools             netkit-telnet         nicstat
ntp                      ntpsec                ostree                pam_tacplus
(+ 13 more)
```

This is the kernel-90 lineage's vendor-pinned variant tree — parallel to SPECS/91 (kernel-91 lineage). The split mirrors the kernel-CVE-gate skill's view of "5.0 SPECS/91, 5.0 SPECS/ ≥92" but the current canonical breakdown is actually three flavors: SPECS/90, SPECS/91, and main SPECS/ (the default).

## Expected behaviour once the snapshot is refreshed

Once the PS workflow's photon-5.0 clone catches up to current `origin/5.0`, the next parity snapshot will include 53 additional rows in `photonos-urlhealth-5.0.prn` — one per `SPECS/90/<pkg>/<pkg>.spec`. By analogy with SPECS/91, these rows are likely to be vendor-pinned:

| Expected column | Expected value |
|---|---|
| col 4 `UrlHealth` | literal `pinned` |
| col 5 `UpdateAvailable` | empty |
| col 11 `warning` | something like `vendor-pinned (subrelease 90)` |

This assumes the PS script has logic to detect the `SPECS/90/` prefix and short-circuit like it does for `SPECS/91/`. **Open question:** verify the PS pinned-emit logic at `photonos-package-report.ps1` recognises the `SPECS/90` path. If it doesn't, those 53 rows will appear as **normal** rows (full Source0Lookup pipeline) and inflate the incomplete count substantially — most of these packages have main-SPECS counterparts whose normal URL paths are unlikely to match the SPECS/90 frozen content.

## Action items (separate from this doc's scope)

1. **PS workflow staleness:** today the PS workflow scans a March 6 working tree. Either add `git fetch + checkout origin/5.0` to the clone step in `package-report.yml`, or document that this is intentional (long-stable target SHAs).
2. **Pinned-emit recognition:** verify PS handles `SPECS/90/` symmetric to `SPECS/91/`. If not, file as a separate bug.
3. **Refresh the snapshot manifest:** if (1) is intentional, the manifest's photon-5.0 SHA should be bumped explicitly to a recent commit so SPECS/90 rows are in scope for parity.

## Verification commands

```sh
# Snapshot SHA's SPECS contents (no SPECS/90):
git -C <photon-5.0-clone> ls-tree ac37e5567:SPECS | head | grep -E "tree.*\s9"
# Returns: only SPECS/91 (40000 tree …)

# Current origin/5.0 (has both SPECS/90 and SPECS/91):
git -C <photon-5.0-clone> ls-tree origin/5.0:SPECS | grep -E "tree.*\s9"
# Returns: SPECS/90 + SPECS/91

# When SPECS/90 was added:
git -C <photon-5.0-clone> log origin/5.0 --diff-filter=A --pretty="%h %ad %s" --date=short \
    -- 'SPECS/90/Linux-PAM/Linux-PAM.spec'
# Returns: dcf28fe61 2026-05-14 systemd: upgrade to v257.13 for subrelease 91
```
