# helper-scripts (archived)

[← sharukhan overview](../../README.md)

**Who this is for:** History only: the September 2026 run wrappers, kept for provenance; nothing uses them.

## `helper-scripts/` — the run wrappers

Five scripts that drive `sharukhan` through a specific multi-hour sequence.
They are **not** part of the harness: nothing in `src/` calls them, and every
one of them shells out to the built binary. They are kept because each records
*why* a particular run was shaped the way it was, and that reasoning is not
recoverable from the CLI.

| script | what it drives |
|---|---|
| `rebuild-both.sh` | Rebuilds **both** minimal ISOs (2.8 and latest) and runs every unattended row they serve. Both variants, because the isoBuilder change rides POI patch 0008, which is carried by the 2.8 *and* the latest installer branch — testing one would leave the other unproven with the same change in it. |
| `activate-coverage-plan.sh` | Pass 2 of the two-pass protocol: throw the local state away, take everything back from the fork, rebuild, run every unattended row. Waits for `rebuild-both.sh` and refuses if that run never reached `=== done ===`. |
| `pass2.sh` | Pass 2, second attempt. Its header is the most useful thing in this directory — it dissects how the first attempt reported *"pass 2 complete"* having run zero rows, from three compounding faults. |
| `full-rows.sh` | The full-ISO half of the matrix plus the canister row, after the variant patch moved under all of them. |
| `canister-equivalent.sh` | First real exercise of the equivalent-canister path, on minimal/2.8 rather than full — the mechanism is identical either way and a minimal ISO costs ~30 minutes against hours. Asserts four things rather than assuming them: phase A produced the canister, the purge kept it and removed the canister-*creating* kernel, phase B rebuilt **both** flavours against it, and the ISO carries a `linux-esx` built after the canister. |

### The two-pass protocol

`activate-coverage-plan.sh` and `pass2.sh` exist for a distinction worth
stating plainly:

```
pass 1   change it locally, test it locally, push it to the fork PR
pass 2   THROW THE LOCAL STATE AWAY, take everything back from the fork,
         rebuild, and run every unattended row
```

Pass 1 proves the change is right. Pass 2 proves *the change that is published*
is the one that was proven — a different claim, and the one that matters before
opening a PR against `vmware/photon`. A local working tree can make a test pass
for reasons the fork does not carry.

### They need `MC_GUEST_PASSWORD` in the environment

Each script opens with

```bash
: "${MC_GUEST_PASSWORD:?not set ...}"
```

and exits immediately if it is unset. It is the root password of every VM the
harness creates, so it has no default and is deliberately **not** stored in
this repository — these scripts previously carried it as a literal, which is
exactly what a public repository must not hold. Export it before running.

### Paths are absolute and host-specific

They hardcode `/root/photonos-scripts/...`, `/root/photon-mc/...` and
`/root/5.0`. They are a record of how this host was driven, not a portable
tool. Read them before running one anywhere else.

---

[← sharukhan overview](../../README.md)
