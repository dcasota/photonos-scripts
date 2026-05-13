# Finding 2026-05-13b: `find -regex/-printf` not portable on self-hosted runner

**Status**: Addressed — fix landed on `sdd/depgraph-phase-6-task013-fix-flavor-discovery`.
**Discovered while verifying**: [task 013 (workflow flavor matrix)](../tasks/013-task-workflow-flavor-matrix.md), AC-3 verification on workflow run `25772831806` (2026-05-13).
**Affects**: [tasks/013-task-workflow-flavor-matrix.md](../tasks/013-task-workflow-flavor-matrix.md), [features/subrelease-flavors.md](../features/subrelease-flavors.md) §2.1.

## Summary

The first cut of task 013 used GNU-style `find -regex … -printf '%f\n'` to enumerate `SPECS/[0-9]+/` overlay directories. On the self-hosted runner this produced

```
find: bad arg '.*/SPECS/[0-9]+'
```

so the `mapfile` body returned zero rows and `FLAVORS` stayed at its base-only initialisation `("")`. The job completed with conclusion `success` (the failing command's exit status was swallowed inside the `< <( … )` process substitution), but emitted only **one** artifact (`dependency-graph-5.0-<datetime>.json`) instead of the four required by PRD AC-3.

## Root cause

`/usr/bin/find` and `/bin/find` on the runner are symlinks into `toybox` (and `bfs` as the secondary). Neither implementation accepts the GNU-`find` extensions `-regex` and `-printf` in combination — `-regex` is parsed as an unknown flag and rejected with `bad arg`. The published recipe in FRD-subrelease-flavors §2.1 v1 assumed GNU `find`, which is not part of the runner image.

## Symptom on the failing run

From the `Clone vmware/photon branches and generate dependency graphs` step of run `25772831806`:

```
find: bad arg '.*/SPECS/[0-9]+'
  Flavors: []  (1 total)
  - Flavor -: 1622 specs -> dependency-graph-5.0-20260513_024825.json
```

Process substitution's failure does not abort `set -e`, so the job kept running and committed the single base artifact to `tdnf-depgraph/scans/`.

## Resolution

Replace the GNU-specific call with a portable pure-bash glob:

```bash
FLAVORS=("")
mapfile -t _NUMERIC < <(
  shopt -s nullglob
  for _entry in "${CLONE_DIR}/SPECS"/*/; do
    _name="${_entry%/}"; _name="${_name##*/}"
    [[ "$_name" =~ ^[0-9]+$ ]] && printf '%s\n' "$_name"
  done | sort
)
FLAVORS+=("${_NUMERIC[@]}")
unset _NUMERIC
```

Properties:

1. Only relies on `bash` (already required by every other step in the workflow) and POSIX `sort`.
2. `shopt -s nullglob` keeps the loop body silent when no entry matches `*/`.
3. The `[[ … =~ ^[0-9]+$ ]]` test excludes non-numeric subdirs (`kernel/`, `glibc/`, `01-special/`).
4. Output is sorted ascending, preserving the deterministic ordering contract from [FRD-cycle-detection §2.5](../features/cycle-detection.md).

## Test evidence

Local smoke test with a synthetic `SPECS/{90,91,92,abc,kernel,01-special,README}` tree:

```
Flavors discovered: [ 90 91 92]  (4 total)
PASS
```

Local smoke test with a base-only tree (no numeric subdirs, mimics `master`/`common`/`3.0`/`4.0`/`6.0`):

```
Count: 1
Contents: []        # element 0 = empty string (base)
PASS: base-only branch preserved
```

## Specs updated alongside this finding

- `tdnf-depgraph/specs/tasks/013-task-workflow-flavor-matrix.md` — Status note + scope recipe replaced.
- `tdnf-depgraph/specs/features/subrelease-flavors.md` — §2.1 recipe replaced + portability rationale added.
- `.github/workflows/depgraph-scan.yml` — discovery snippet at lines 185-196 replaced.

## Follow-up

AC-3 must be re-verified after this fix lands. The verification command is unchanged:

```
gh workflow run depgraph-scan.yml --repo dcasota/photonos-scripts --field branches=5.0
```

Expected artifacts on the run: four files matching `dependency-graph-5.0[-90|-91|-92|]-<datetime>.json`.
