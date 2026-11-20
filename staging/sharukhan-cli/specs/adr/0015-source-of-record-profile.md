# ADR-0015 — A source-of-record profile

Status: accepted, implemented
Date: 2026-11-20
Issue: #342 (U4)
Docs: [docs/configuration.md](../../docs/configuration.md#the-source-of-record-profile)

## Context

A consumer plans to run sharukhan as the source of record for Photon OS RPMs
and ISOs: the SpagatLibrarian appliance's builder zone, ADR-0090 there. A record
must be reproducible and auditable from what it names: the sharukhan binary,
the commits, the images and the mirror snapshot. Today a run can depend on
inputs no record shows:
- a data file or template that replaces the built-in copy (`SHARUKHAN_MATRIX`,
  `MC_VMX_TEMPLATE`, ...);
- a model's answer (the escalation, ADR-0010);
- an image named by a tag that can move (`photon/installer:latest`);
- a download from a declared upstream URL, GitHub or the Broadcom mirror.

## Options considered

1. **A documented checklist for record hosts.** Nothing stops a run that
   misses one item, and the miss leaves no trace.
2. **Remove the overrides, the escalation and the network paths.** It breaks
   the lab use those features exist for.
3. **A profile, `--sor` or `SHARUKHAN_PROFILE=sor`, that refuses each such
   input before anything acts.** Each refusal names the setting, the measured
   value and what was expected. `doctor` lists the findings. Without the
   profile nothing changes.

## Decision

Option 3 (`src/sor.rs`). Under the profile, sharukhan refuses:
- **override:** any setting that replaces a built-in data file, template or
  profile directory;
- **escalation:** an explicit `MC_ESCALATE` other than `off`. The escalation is
  off under the profile in any case, and `escalate()` refuses;
- **image:** `MC_POI_BASE_IMAGE`, including its tag default, and
  `--builder-image` unless named by ID (`sha256:<64 hex>` or
  `<name>@sha256:<64 hex>`). The builder's own base is already accepted only
  by its pinned ID;
- **network:**
  - `MC_PHOTON_REMOTE` and the new `MC_SOURCES_MIRROR` unless they are
    `file://`;
  - the commands that reach a remote by design (`sync`, `watch`, `events`,
    `escalate`, `mcp`, `wrapper`, `systemd`, `pr-eligibility`).

  An archive is fetched from the mirror only, never from its declared upstream
  URL. A `file://` mirror is copied directly, since wget cannot read file URLs.

A refusal stops sharukhan with exit 78. `doctor`, `help` and `settings` report
instead of stopping. `sharukhan --sor <command>` re-executes the command with the
setting, so every child sharukhan starts runs under the profile too.

## Consequences

- A record host is configured by its settings alone, and a deviation is
  refused before it can reach a record.
- The network rules cover the URLs sharukhan owns. Isolating the host's network
  (no egress apart from the mirror) is the record host's job; the profile makes
  sure sharukhan does not need more.
- The per-run record of these inputs follows with U1 (#344), and the
  attestation with U2 (#346).
