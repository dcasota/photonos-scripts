# Provenance

`staging/vm-lab/` is a snapshot of `deploy/vm-lab/` from the SPAGAT-Librarian
appliance repository.

```
source repo   : dcasota/SpagatLibrarian-Appliance
source path   : deploy/vm-lab/
authored at   : b7ec6954e03ebe1c1b134bd5d8267c402848bdb0
snapshot date : 2026-08-31
```

**What that commit id means.** `deploy/vm-lab/` was authored alongside
`b7ec6954` but is not itself committed in the source repo yet, so
`photonos-scripts/staging/vm-lab/` is currently its published home. The id
identifies the appliance tree these scripts were written and tested against —
in particular the kickstart template and the `spagat-vm-orchestrator` CLI
surface they wrap — not a commit that contains this directory.

## The kickstart copy

`kickstart/photon-appliance.ks.template.json` is a **byte-exact** copy of
`src/tools/iso-build/iso-phase6-kickstart-template.cfg` in the source repo,
which is the file the ISO build actually consumes.

```
sha256 at snapshot time: ac5a3a5c3f87e392af927d070052f0edf86d178fb70a427e51fef4572c67f7e1
```

`kickstart/check-drift.sh` verifies this and states which mode it used:

- **Mode 1** — a SPAGAT checkout is reachable (`SPAGAT_REPO=/path/to/repo`, or
  this directory sitting inside that repo): it diffs against the live
  canonical file and catches drift in **either** direction.
- **Mode 2** — standalone, as here: it falls back to the hash above. That
  still detects an edited local copy, but **cannot** tell you whether the
  upstream template has moved on. The script says so rather than implying it
  proved more than it did.

If neither the canonical file nor `EXPECTED-SHA256` is available it exits
non-zero — "cannot check" must never read as "fine".

A convenience copy that can silently diverge from the real thing is worse than
no copy, because you would reason about a kickstart the build never uses.

## Refreshing the snapshot

```bash
SPAGAT=/path/to/SpagatLibrarian-Appliance
cp "$SPAGAT/src/tools/iso-build/iso-phase6-kickstart-template.cfg" \
   staging/vm-lab/kickstart/photon-appliance.ks.template.json
sha256sum staging/vm-lab/kickstart/photon-appliance.ks.template.json \
   | cut -d' ' -f1 > staging/vm-lab/kickstart/EXPECTED-SHA256
# then update the sha256 and the commit id above
```
