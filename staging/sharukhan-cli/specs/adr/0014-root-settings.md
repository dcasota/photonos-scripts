# ADR-0014 — Two root settings carry the host layout

Status: accepted, implemented
Date: 2026-11-20
Issue: #343 (U6)
Docs: [docs/configuration.md](../../docs/configuration.md#paths-the-vm-and-the-network)

## Context

Every path already had its own environment override, but each default still
named the lab host's layout in code: `/root/photon-mc/...` for the results, the
logs, the work tree, the memory database and the gate, and `/mnt/c/photon-mc/...`
for the VMs and the ISO cache.

Some defaults had no override at all:
- the builder's shared root and context directory, which had overrides but were
  derived from a separate constant;
- the default notification file;
- the PowerShell `doctor` uses.

A second host, such as an appliance builder zone with its data on its own disk,
had to set about a dozen variables and could still miss one. The miss would show
up as a write into `/root/photon-mc` on a host where that path means nothing.

## Options considered

1. **Leave the per-path overrides as they are and document a full settings
   file for other hosts.** No code change, but every new host repeats the
   same dozen lines, and a path added later is missed silently.
2. **One root setting for everything.** `MC_ROOT` would be the only knob, and
   `/mnt/c/...` would be derived from it. This fails on this host: VMware can
   only see Windows-visible paths (see `Config::vm_root`), so the VM and ISO
   roots cannot sit below a WSL path.
3. **Two root settings.** `MC_ROOT` is the work root and `MC_WIN_ROOT` the
   Windows-visible root. Every host-local default is derived from one of them,
   per-path settings keep winning, and the defaults are byte-identical when
   neither is set. A host tool path that is not a lab path (PowerShell) gets a
   plain setting of its own, `MC_POWERSHELL`.

## Decision

Option 3.
- Both roots are path settings, checked by `safepath` like every other one. A
  malformed root stops sharukhan with exit 78.
- `config::root_from_env` is the one place outside `Config` that reads
  `MC_ROOT`. The builder, the watcher's default channel and the service files
  derive their defaults through it. The service files derive from the settings
  being installed, not from the invoking process.
- `sharukhan settings` and the service settings file carry both roots.

## Consequences

- Moving sharukhan to another host takes two settings. Existing installs see
  no change, and a test pins today's defaults.
- Names that are not paths stay as they are: the `photon-mc-gate-shared` unit,
  the SSH key name, and lab notes cited in oracle messages.
