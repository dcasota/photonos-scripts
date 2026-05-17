# Maintainer runbook — photonos-package-report (C port)

This document is the operability companion to the PRD. It targets the
person who actually runs, debugs, and curates the tool day-to-day: adding
a `Source0LookupData` row when upstream URLs change, pinning a stubborn
package, debugging a parity failure in VS Code, or rerunning a single
branch without the parallel worker pool getting in the way.

The runbook tracks the live C codebase. When a phase lands a feature
that changes a procedure here, update the corresponding section in the
same PR — sections that are still under construction call out the phase
where they unlock.

---

## 1. Adding a `Source0LookupData` row

The 855-row CSV is embedded in the **upstream PowerShell script** at
`../photonos-package-report.ps1` between the `$Source0LookupData=@'` and
`'@` markers (currently L 509-1366). The C port reads it at build time
via `tools/extract-source0-lookup.sh`.

### Procedure

1. Open `../photonos-package-report.ps1`.
2. Locate the `=@'` opening marker (search for `Source0LookupData=@`).
3. Insert your new row **in alphabetical order by `specfile`** — the
   build does not enforce this, but `Source0Lookup` consumers downstream
   (and humans diffing PRs) expect it.
4. CSV columns (in order):

   | # | Column            | Required | Notes                                            |
   |---|-------------------|----------|--------------------------------------------------|
   | 1 | `specfile`        | yes      | basename, e.g. `abseil-cpp.spec`                 |
   | 2 | `Source0Lookup`   | yes      | replacement URL, may use `%{version}` etc.       |
   | 3 | `gitSource`       | no       | upstream `git clone` URL                         |
   | 4 | `gitBranch`       | no       | non-default branch (e.g. `trunk` for httpd.spec) |
   | 5 | `customRegex`     | no       | extra regex applied during version extraction    |
   | 6 | `replaceStrings`  | no       | comma list of substrings to strip from tag names |
   | 7 | `ignoreStrings`   | no       | comma list of tag patterns to skip               |
   | 8 | `Warning`         | no       | maintainer-visible note shown in the report      |
   | 9 | `ArchivationDate` | no       | mark a package archived; freezes lookups         |

5. Quoting: if a cell contains a comma or a double quote, wrap the cell
   in double quotes and double any embedded quotes (RFC 4180 subset).
   Example with embedded commas:

   ```csv
   apache-maven.spec,https://.../maven-%{version}.tar.gz,https://github.com/apache/maven.git,,apache-maven,"workspace-v0,maven-"
   ```

6. Rebuild. The CMake `add_custom_command` re-extracts the CSV and
   regenerates `build/generated/source0_lookup_data.h`:

   ```sh
   cmake --build build
   ```

7. Confirm the new row landed:

   ```sh
   ./build/tests/unit/test_phase3 --emit-csv | grep '^my-new-package\.spec,'
   ```

### Sanity checks the test suite already runs for you

* `test_phase3` re-validates the row count (currently 855) and the
  first/last row markers, so an accidental delete is caught.
* The emit→reparse roundtrip would catch quoting errors.

### Pitfalls

* **Do not** edit the C side header (`build/generated/source0_lookup_data.h`)
  — it is regenerated on every build and your changes will be lost.
* The upstream PS script is the **single source of truth**. Bug fixes
  flow PS → spec → C, never the reverse (CLAUDE.md invariant #2).

---

## 2. Pinning a package to a specific version (per-spec exception)

The PS script and the C port both support per-spec override blocks.
In PS they are gated by `if ($currentTask.spec -ilike 'X.spec')`; in C
they live in their own translation unit under `src/hooks/<name>.c` and
are wired in by a generated dispatch table (`build/generated/pr_hook_dispatch.c`)
rebuilt on every CMake build.

PS remains the source-of-truth per CLAUDE.md invariant #2 — add the
exception there first, then mirror it to C.

### File-naming convention

| PS basename            | C hook file               | C symbol                        |
|------------------------|---------------------------|---------------------------------|
| `inih.spec`            | `src/hooks/inih.c`        | `hook_inih_spec`                |
| `open-vm-tools.spec`   | `src/hooks/open_vm_tools.c` | `hook_open_vm_tools_spec`     |
| `samba-client.spec`    | `src/hooks/samba_client.c`  | `hook_samba_client_spec`      |

Rules: strip `.spec` from the filename, map `-` → `_` in both the
filename and the symbol, prefix `hook_` and suffix `_spec` on the symbol.

### Example (currently ported: inih, open-vm-tools, samba-client)

```powershell
# photonos-package-report.ps1 L 4727-4733
if ($currentTask.spec -ilike 'inih.spec') {
    $UpdateDownloadName = $UpdateDownloadName -ireplace "^r","libinih-"
}
```

The matching C hook (`src/hooks/inih.c`) implements the same body
against `pr_task_t`/`pr_state_t`. The `pr_state_t` struct grew its
`UpdateDownloadName` field in Phase 4/6; hooks ported before that field
landed compile as no-ops with the PS body in a `/* TODO */` comment.

### Procedure

1. Open `../photonos-package-report.ps1`.
2. Find the exception cluster matching your case. Common clusters live
   around PS L 2140-2200 (Source0 substitution) and L 4720-4760
   (UpdateDownloadName).
3. Append a new `if ($currentTask.spec -ilike 'your-spec.spec') { ... }`
   in **alphabetical order** within the cluster.
4. Run the extractor and confirm your new block is detected:

   ```sh
   ./tools/extract-spec-hooks.sh ../photonos-package-report.ps1 \
     | grep '^your-spec\.spec'
   ```

   Output is TSV: `<spec-basename>\t<start-line>\t<end-line>`. One row per
   block (a spec may have several scattered blocks).

5. Create (or edit) the matching C file under `src/hooks/`. Signature is fixed:

   ```c
   #include "pr_hook.h"
   int hook_<name>_spec(pr_task_t *task, pr_state_t *state) {
       /* hand-port of PS body */
       return 0;  /* non-zero to abort the per-task workflow */
   }
   ```

   No registration needed — `tools/generate-hook-dispatch.sh` scans
   `src/hooks/*.c` on every build and emits the sorted dispatch array
   automatically.

6. Build + test:

   ```sh
   cmake --build build
   ctest --test-dir build -R test_phase3b --output-on-failure
   ```

   `test_phase3b` validates that `pr_hooks_find("your-spec.spec")` returns
   non-NULL and that `pr_hooks_run` invokes your hook on a task with the
   matching `Spec`.

7. Open a PR using the standard commit-message template.

### Drift between PS and C

```sh
./tools/spec-hooks-drift-check.sh .
```

The argument is the C project root (the script resolves
`<root>/../photonos-package-report.ps1` for the PS side). Output header:

```
spec-hooks-drift: PS=96  C=3  PS-only=93  C-only=0
```

`PS-only` is the long tail of unported specs; `C-only` is always an error
(an invented hook with no PS counterpart). Phase 7+ flips PS-only to a
hard error via the env var `PR_HOOKS_PS_ONLY_FATAL=1`.

---

## 3. Excluding a package entirely (`UpstreamsExclusionList`)

If a package's upstream clone is large enough to push the runner against
disk limits (firmware blobs, chromium, etc.), short-circuit it with
`-UpstreamsExclusionList`.

```sh
pwsh -File ./photonos-package-report.ps1 \
    -workingDir   /var/photonos \
    -UpstreamsExclusionList 'firmware,chromium,my-broken-pkg'
```

Comma-separated, **case-insensitive substring match**, no spaces around
the commas. The list is applied against **two** keys, each independently:

| # | Key                                       | What gets skipped                  | PS site             |
|---|-------------------------------------------|------------------------------------|---------------------|
| 1 | `repoName` (leaf of `*.git` URL)          | `git clone` into `clones/<repo>`   | L 2392 / 3679 / 4034 |
| 2 | leaf of `$UpdateDownloadFile` (tarball)   | tarball build/fetch into `SOURCES_NEW` | L 4790            |

When key 1 fires, `$repoName/.git` is never created → the downstream
`git tag -l` block falls through cleanly and version detection uses
the non-git heuristic path (Source0 parent + `customRegex`). When key 2
fires, the tarball block is bypassed; substitution + urlhealth still run.

Default (empty list): both keys are no-ops; behaviour matches pre-flag
runs byte-for-byte.

### Disk-space recovery on the runner

Activating the exclusion **does not delete existing clones** — it only
prevents future creation. After the flag is in your operator config,
free space manually:

```sh
# Example: actions-runner installation. ~122 GB recovered per branch.
for b in 3.0 4.0 5.0 6.0 common dev master; do
    rm -rf "/root/actions-runner/_work/photonos-scripts/photonos-scripts/reports/photon-upstreams/photon-$b/clones/firmware"
    rm -rf "/root/actions-runner/_work/photonos-scripts/photonos-scripts/reports/photon-upstreams/photon-$b/clones/chromium"
done
```

Without the flag, the very next run re-clones both (`firmware` ≈ 55 GB,
`chromium` ≈ 67 GB per branch — measured 2026-05-17). With the flag, the
slots stay empty.

### Parity-gate interaction

The C port currently honours `-UpstreamsExclusionList` only for the
tarball half (key 2). Until the C side also honours key 1, passing
`firmware,chromium` to the PS workflow without also passing it to the
C workflow will diverge on rows where git-tag detection ran on one
side and the non-git fallback ran on the other → **strict-fail** on
columns 5/6 of those spec rows.

Operational rule until the C-side migration lands:

* **Do not** set `-UpstreamsExclusionList` on the production PS
  workflow (`package-report.yml`) yet. The flag is safe in ad-hoc
  manual runs and in any C-side workflow that explicitly forwards
  the same value.
* The dual-key matching is already wired in `package-report.ps1` so
  the symmetric C-side change (Phase 9 follow-on or its own SDD spec
  under Phase M) is a straight port; no PS-side rework needed when
  the C side catches up.

---

## 4. Debugging in VS Code

The repo ships ready-to-use VS Code config under `.vscode/`:

| File                       | What it gives you                                     |
|----------------------------|-------------------------------------------------------|
| `.vscode/tasks.json`       | `Build (Debug)`, `Run tests`, `Regenerate Source0`   |
| `.vscode/launch.json`      | `Debug photonos-package-report`, `Debug test_phaseN` |
| `.vscode/c_cpp_properties.json` | IntelliSense paths (libpcre2 + generated header) |

### One-time setup

```sh
sudo tdnf install -y cmake gcc gdb libcurl-devel pcre2-devel pkg-config make
cmake -B build -S . -DCMAKE_BUILD_TYPE=Debug
cmake --build build
```

VS Code: install the **C/C++** and **CMake Tools** extensions.

### Debug the main executable

1. `F5` → pick **Debug photonos-package-report**.
2. Set a breakpoint in `src/main.c` or anywhere along the call path.
3. The configuration passes `-workingDir tests/fixtures` and
   `--dump-tasks photon-fixture` so you can step into `parse_directory()`
   on the fixture tree without touching real Photon checkouts. Change
   the `args` in `launch.json` to point at your real working tree.

### Debug a single test

1. `F5` → pick **Debug test_phaseN**. One launch config per merged phase:
   `1`, `2`, `3`, `3b`, `4`, `5`, `6`, `6b`, `6c`, `6d`, `6e`, `6f`, `7`.
2. `test_phase2` is the only one that takes a fixture-dir argument
   (`${workspaceFolder}/tests/fixtures`); the rest run with `"args": []`.

### Why gdb and not lldb

Photon ships gdb in the default toolchain. lldb works fine if installed
but the shipped `launch.json` uses gdb to keep the runbook reproducible.

---

## 5. Running sequentially vs in parallel

The parallel worker pool is a pthread mirror of
`ForEach-Object -Parallel -ThrottleLimit 20` (PS L 5061 / L 5214),
landed in Phase 7 (PR #66). The dispatch decision lives in
`src/main.c:443` — if `params->ThrottleLimit <= 1` the loop runs
sequentially, otherwise `pr_pool_create(N)` spawns N workers
(`src/pool.c`).

### Usage

```sh
# Default: ThrottleLimit = 20 (matches PS L 5214).
./build/photonos-package-report -workingDir /var/photonos

# Force sequential — useful for gdb, valgrind, or determinism while diffing .prn.
./build/photonos-package-report -workingDir /var/photonos -ThrottleLimit 1

# Bound the pool explicitly. Clamp is [1, 256]; values outside snap to bounds.
./build/photonos-package-report -workingDir /var/photonos -ThrottleLimit 4
```

### Why you might want sequential

* **Debugging.** gdb in one thread is dramatically easier than 20.
* **Parity diffing.** Two parallel runs of the PS script can yield
  identical `.prn` output but different stderr-warning order. Phase 8's
  parity gate (pending) is planned to run **both PS and C with
  `-ThrottleLimit 1`** while computing the bit-identical `.prn` diff.
  Reproduce locally the same way.
* **Rate-limited remotes.** GitHub API can 429 you out from a 20-wide
  fanout; drop to 4 or below to stay under the unauthenticated cap, or
  pass `-github_token <PAT>` to lift to the authenticated 5000/h cap.

### Per-repo fetch arbitration

Parallel workers can collide on the same `git fetch` directory when two
specs in the same run share an upstream repository. Phase 7 added
`flock(LOCK_EX)` around the clone/fetch critical section
(`src/pr_clone.c:150`), so concurrent fetches against the same repo
serialise themselves automatically — no extra config needed. The
unlock fires after the fetch completes (`src/pr_clone.c:179`).

If you see "Resource temporarily unavailable" or "Cannot fetch — another
process holds the lock" from inside a worker, lower `-ThrottleLimit` to
reduce contention or check `lsof | grep $repo/.git` for stuck holders.

---

## 6. Regenerating embedded data manually

The build does this automatically, but you may want to peek:

```sh
# Just the CSV body, one row per line.
./tools/extract-source0-lookup.sh ../photonos-package-report.ps1 | head

# The full generated header.
./tools/extract-source0-lookup.sh ../photonos-package-report.ps1 \
  | ./tools/csv-to-c-string.sh \
  | less
```

Both scripts depend on POSIX shell + awk only. No Python, no pwsh
(ADR-0005, ADR-0008). Output goes to stdout; the build redirects it
into `build/generated/source0_lookup_data.h`.

---

## 7. Common troubleshooting

| Symptom                                  | First thing to check                          |
|------------------------------------------|-----------------------------------------------|
| `parse_directory: SPECS path not a directory` | `<workingDir>/<branch>/SPECS` actually exists |
| Build fails: `pcre2.h: No such file`     | `tdnf install -y pcre2-devel` then re-cmake   |
| `test_phase3` row count drift            | Re-pull master; PS upstream gained/lost rows  |
| `--dump-tasks` emits 0 records           | Wrong `-workingDir`/branch combination        |
| `.prn` diff after parity run             | Run **both** PS and C with `-ThrottleLimit 1` |
| `convert_to_boolean` returns 1 for "no"  | PS accepts `$true`/`$false`/`true`/`false`/`0`/`1` only; "no" is not in the table — file an issue |

---

## 8. Where to file issues / PRs

* **Bugs / RFE:** https://github.com/dcasota/photonos-scripts/issues
* **PRs:** Branch from `master`, name `sdd/phase-<N>-<topic>`, open against `master`.
* **Commit-message template** (enforced by `tools/git-hooks/commit-msg` once that lands):
  ```
  phase-<N> task <NNN>: <imperative subject>

  FRD: FRD-<NNN>
  ADR: ADR-<NNNN>[, ADR-<NNNN>...]
  PS-source: photonos-package-report.ps1 L <start>-<end>
  Parity: <strict|semantic|n/a>
  ```

---

## 9. Reading the parity gate verdict

Phase 8 (PR-pending) ships a three-workflow parity harness around the
PS-side production workflow. The gate decides whether a PR is allowed
to merge based on how recent runs have diffed.

### Workflow shape

```
package-report.yml (PS)         package-report-C.yml (C)         parity-check.yml (gate)
─────────────────────           ────────────────────────         ──────────────────────
schedule / dispatch             workflow_run trigger             pull_request trigger
       │                              │                                 │
       ▼                              ▼                                 ▼
  produce .prn                   download parity-snapshot         read parity-journal.tsv
       │                         reconstruct working tree         apply 30/60/90 ladder
       ▼                         build C / run C                  set commit status
  upload parity-snapshot         parity-diff per branch
                                 append journal row + commit
```

### The 30/60/90-day ladder (ADR-0009)

| Days since clock start | Latest verdict → gate state |
|---|---|
| 0-30   | any → `pass` (soft window, informational) |
| 30-60  | green→`pass`, else `warn` |
| 60-90  | green→`pass`, soft→`warn`, strict→`fail` (PR blocked) |
| 90+    | any → `pass` (cutover-ready; Phase 9 retirement trigger) |

The clock starts with the first row in `tools/parity-journal.tsv`. The
gate workflow (`parity-check.yml`) runs on every PR; it reads the
journal as-checked-in and emits a `parity-gate` commit status.

### Journal schema

`tools/parity-journal.tsv` — one row per (PS run, C run, branch):

```
ts             ISO 8601 UTC
ps_run_id      GitHub run id of the PS workflow
c_run_id       GitHub run id of the C workflow run
branch         3.0 | 4.0 | 5.0 | 6.0 | common | dev | master
strict_rows    rows differing in non-volatile columns
soft_rows      rows differing only in cols 4 and/or 7
volatile_only  "true" iff soft_rows > 0 AND strict_rows == 0
verdict        green | soft | strict
```

Volatile columns are 4 (`UrlHealth`) and 7 (`HealthUpdateURL`) — both
HTTP status codes that legitimately shift day-to-day (ADR-0006). All
other columns are strict.

### Manual snapshot replay

You can re-run the C workflow against any past PS snapshot:

```sh
# 1. Find the PS run id you want to replay against.
gh run list --workflow="Photon OS Package Report" --limit 5

# 2. Trigger the C workflow with that id (no PS rerun).
gh workflow run "Photon OS Package Report (C-side parity)" \
   -f snapshot_run_id=<PS_RUN_ID>
```

For fully-offline replay:

```sh
gh run download <PS_RUN_ID> -n parity-snapshot-<PS_RUN_ID> -D /tmp/snap
cd /tmp/snap && tar -xzf parity-snapshot-*.tar.gz

# Reconstruct working tree from manifests.
.github/scripts/parity-reconstruct.sh /tmp/snap /tmp/wd /tmp/wd/photon-upstreams

# Build + run C with the same -ThrottleLimit 1 the workflow uses.
cmake --build build
./build/photonos-package-report \
   -workingDir /tmp/wd -upstreamsDir /tmp/wd/photon-upstreams \
   -scansDir /tmp/wd/scans -ThrottleLimit 1 \
   -GeneratePh6URLHealthReport true   # ...etc per branches in /tmp/snap/prn-snapshot/

# Diff a single branch.
./tools/parity-diff.sh \
   /tmp/snap/prn-snapshot/photonos-urlhealth-6.0_*.prn \
   /tmp/wd/scans/photonos-urlhealth-6.0_*.prn
```

### Common gate-verdict troubleshooting

| Verdict | Meaning | First thing to check |
|---|---|---|
| `green` | byte-identical PRN | nothing to do |
| `soft`  | only cols 4 / 7 differ | day-to-day HTTP flux; ignore unless persistent |
| `strict` | non-volatile column drift | run replay (above) locally and `diff` the .prn pair to find the offending spec |
| `no-data` | journal empty | first paired run hasn't happened yet; not an error |

### When the clock should be reset

Resetting means deleting `parity-journal.tsv` and re-committing. Do this
only when:

* The PS script itself has been intentionally changed and the previous
  parity baseline is no longer the canonical target.
* The C-side ADR-0006 column set has changed (new column added, etc.).

In both cases open a separate PR that resets the journal explicitly
with a justification linked to the ADR or PRD change.
