# Keeping the fork's PRs current

[← sharukhan overview](../../README.md)

**Who this is for:** The maintainer of the fork's PRs: how a sync keeps them current, what needs a decision, and the upstream stage.

## Keeping the fork's PRs current: `sharukhan sync`

When the fork's release branch (`MC_RELEASE`, default `5.0`) or its `common`
branch moves, every open PR of the fork (`MC_FORK`, default `dcasota/photon`)
has to be rebased, checked, built, gated and published again. `sharukhan sync`
does that as a resumable state machine recorded in `memory.db`.

### The stages

```
ANALYZE -> REBASE -> VERIFY -> PREPARE -> FASTLOOP -> GATE -> PUBLISH -> STAGEVM -> UPSTREAM -> DONE
```

| Stage | What it does |
|---|---|
| `ANALYZE` | lists the fork's open PRs, checks each local head equals GitHub's, and decides per PR: keep, or rebase (a PR stacked on a rebased one is rebased too) |
| `REBASE` | moves each PR onto its new base, parents first; a refused rebase stops the run as `needs-decision` |
| `VERIFY` | `rpmspec -P` per subrelease and arch, `check_spec`, and the one-changelog-entry rule against the new base |
| `PREPARE` | points the gate repository at the candidates, resets the build trees and regenerates the variant patches |
| `FASTLOOP` | builds the minimal ISO of the default variant and installs `MC_FASTLOOP_ROWS` (default `k03 c03`) |
| `GATE` | `sharukhan run --all --allow-build`: every ISO, every unattended row |
| `PUBLISH` | pushes with `--force-with-lease`, carries each description, checks GitHub shows both |
| `STAGEVM` | for PRs held for the upstream stage: the staged code is the gated code, then `MC_STAGED_ROWS` (default `k11`) is installed from it |
| `UPSTREAM` | waits for `sync approve-upstream`, then moves the shared branches and updates both descriptions in place |
| `DONE` | records the synced bases |

Rules that hold throughout:

* One run at a time.
* Before every stage the inputs are checked again: if a base head or a PR head
  moved, the run stops as `superseded`.
* A stage left `running` by a process that is gone is `interrupted` and runs
  again on resume; every stage is idempotent.
* `abort` takes effect between stages, never inside PUBLISH.
* Nothing reaches GitHub before PUBLISH. Candidates live in the gate
  repository as `sync/<run>/<branch>`.

### Starting, following and resuming a run

```bash
sharukhan sync start                    # a run against the fork's current bases
sharukhan sync start --until GATE       # stop before GATE (paused)
sharukhan sync start --rebase-all      # move every PR to the new base, not only those that must
sharukhan sync status                   # the last five runs and their stages
sharukhan sync resume 7                 # continue run 7 from where it stopped
sharukhan sync abort 7                  # between stages; restores the gate refs
```

`start` also takes `--fork <owner/repo>`, `--repo <gate repository>` and
`--against <repository>` (new bases from another repository, for a preview).
Without `--rebase-all`, ANALYZE rebases a PR only when it no longer merges or
upstream touched its files; the others keep their old base on GitHub. Any other
argument, `--help` included, is refused before a run starts.
Stage logs go to `$MC_RESULTS_DIR/sync/<run>/`.

`MC_PUBLISH_DCASOTA` decides PUBLISH:

| Value | PUBLISH |
|---|---|
| `auto` (default) | pushes when every description passes the lint |
| `approve` | always waits for `sharukhan sync approve <run>` |
| `preview` | the run ends before PREPARE: candidates only, nothing built or published |

### When a PR needs a decision

A refused rebase or failed checks stop the run as `needs-decision`. The
escalation (below) may propose a fix; either way the answer is recorded with
`decide`:

```bash
sharukhan sync decide 7 23 candidate refs/heads/resolve/23
sharukhan sync decide 7 92 candidate refs/heads/resolve/92 --base 5.0   # and move the PR's base
sharukhan sync resume 7
```

The candidate must sit on the new position of the base the PR will have.
Resuming keeps every PR already rebased or resolved.

### Descriptions

PUBLISH carries each PR's description to its new head (moved paths, Release
numbers) and lints it: Problem / Change / Testing sections, Dependencies when
stacked, no stale paths or versions. A change whose content changed needs a
description reviewed for it:

```bash
sharukhan sync lint                              # every open PR's description now
sharukhan sync lint 23 36                        # only these
sharukhan sync body --set 7 23 reviewed-23.md    # a reviewed description for run 7
sharukhan sync body --set 7 23 proposed          # the escalation's, once its proposal is decided
sharukhan sync body --set-upstream 7 36 up-36.md # the upstream PR's description
sharukhan sync body --restore 7 23               # put back the text from before run 7
```

The previous text of every edited description is kept as
`PUBLISH/<n>.orig` (and `<n>.upstream.orig`).

### Upstream PRs: shared branches, staged first

An upstream PR (`MC_UPSTREAM`, default `vmware/photon`) opened from a fork
branch shares that branch with the fork's own PR. GitHub cannot give a PR
another head, and the maintainers keep their conversation on the PR they have,
so sharukhan never closes, re-opens or comments on an upstream PR, and it
never opens one:

1. **PUBLISH** pushes such a branch, and every PR stacked on it, to
   `staging/<branch>` on the fork, a branch no PR uses.
2. **STAGEVM** checks `staging/<branch>` is the gated candidate and the
   upstream PR's head has not moved, then installs `MC_STAGED_ROWS` from it.
3. **UPSTREAM** prepares both descriptions and checks the head merges cleanly
   onto the upstream PR's base. The upstream description may not name the
   fork's owner, nor a PR number that is not an upstream PR of the fork and
   not already in its text. It waits for a person whatever
   `MC_PUBLISH_DCASOTA` says:

```bash
cat $MC_RESULTS_DIR/sync/7/UPSTREAM.table       # what will move, both descriptions' verdicts
sharukhan sync approve-upstream 7
```

After approval it moves the shared branch with a lease, checks both PRs show
the new head, edits both descriptions in place, checks GitHub's merge verdict
and deletes `staging/<branch>`. For these PRs the fork PR shows the new code
at the same moment as the upstream PR.

### The timer: `sync auto`

```bash
sharukhan sync auto                  # what the timer runs
sharukhan sync auto --quiet 3600     # quiet period override (default SHARUKHAN_SYNC_QUIET, else 7200 s)
```

It starts a run only when the watcher recorded a move of the fork's bases
that has been quiet long enough, no run is active and no gate or build job is
running. A run that waits for a decision is handed to the escalation queue on
every tick. Notifications go to `MC_NOTIFY`.

### Other sync commands

```bash
sharukhan sync reset-trees            # build trees back to the gate repository's branches, as PREPARE does
sharukhan sync baseline 5.0 <sha>     # record the synced base of a root
sharukhan sync analyze --repo <git dir> --fork <owner/repo> --base 5.0=<old>..<new>
sharukhan sync verify  --repo <git dir> --base <rev> --common <common tree> <ref>...
```

`reset-trees` refuses edits no variant patch or fixup explains, and refuses
while a run or job uses the trees: use it before a gate run by hand.

---

[← sharukhan overview](../../README.md)
