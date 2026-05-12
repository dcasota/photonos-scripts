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

The PS script (and the C port, once Phase 3b lands) supports per-spec
override blocks. These are gated by `if ($currentTask.spec -ilike 'X.spec')`
in PS and become `hook_X_spec()` functions in C.

### Example (already in PS, awaiting C port in Phase 3b)

```powershell
# photonos-package-report.ps1 L 4727-4733
if ($currentTask.spec -ilike 'inih.spec') {
    $UpdateDownloadName = $UpdateDownloadName -ireplace "^r","libinih-"
}
if ($currentTask.spec -ilike 'open-vm-tools.spec') {
    $UpdateDownloadName = [System.String]::Concat("open-vm-tools-",$UpdateDownloadName)
}
if ($currentTask.spec -ilike 'samba-client.spec') {
    $UpdateDownloadName = $UpdateDownloadName -ireplace "samba-samba-","samba-"
}
```

### Procedure (PS-side; canonical until Phase 3b lands)

1. Open `../photonos-package-report.ps1`.
2. Find the exception cluster matching your case (URL prefix, tag prefix,
   filename rewrite). Common clusters live around PS L 2140-2200
   (Source0 substitution) and L 4720-4760 (UpdateDownloadName).
3. Append a new `if ($currentTask.spec -ilike 'your-spec.spec') { ... }`
   in **alphabetical order** within the cluster.
4. Commit. The C `spec-hook-extractor` agent will pick up the new block
   on its next run, emit a skeleton `src/check_urlhealth/hooks/your_spec.c`
   with the PS body embedded as a comment, and add the dispatch entry.
5. Hand-port the body to C, run `ctest`, open a PR.

### Where the hook ends up in C (post Phase 3b)

```
src/check_urlhealth/hooks/inih.c              # generated skeleton, then hand-edited
src/check_urlhealth/pr_spec_dispatch.h        # auto-generated dispatch table
```

Hook signature is fixed:

```c
int hook_inih_spec(pr_task_t *task, pr_state_t *state);
```

---

## 3. Excluding a package entirely (`UpstreamsExclusionList`)

If a package is breaking the upstream clone phase (firmware blobs,
chromium, etc.) you can short-circuit it with the existing
`-UpstreamsExclusionList` argument. Mirrored 1:1 in the C port.

```sh
./build/photonos-package-report \
    -workingDir   /var/photonos \
    -UpstreamsExclusionList 'firmware,chromium,my-broken-pkg'
```

Comma-separated, case-sensitive, no spaces. Matched against `Name` (the
directory leaf under `SPECS/`).

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

1. `F5` → pick **Debug test_phase2** (or `_phase1`, `_phase3`).
2. The launch config runs the test binary with the fixture-dir argument
   the harness uses.

### Why gdb and not lldb

Photon ships gdb in the default toolchain. lldb works fine if installed
but the shipped `launch.json` uses gdb to keep the runbook reproducible.

---

## 5. Running sequentially vs in parallel

The parallel worker pool is a **Phase 7** feature (pthread mirror of
`ForEach-Object -Parallel -ThrottleLimit 20` from PS L 5061 / L 5214).
Until Phase 7 lands, the C port is sequential by construction.

### Once Phase 7 lands (planned flag)

```sh
# Default: ThrottleLimit auto-detected, capped at 20 (matches PS L 5210-5214).
./build/photonos-package-report -workingDir /var/photonos

# Force sequential — useful for gdb, valgrind, or determinism while diffing .prn.
./build/photonos-package-report -workingDir /var/photonos -ThrottleLimit 1

# Bound the pool explicitly.
./build/photonos-package-report -workingDir /var/photonos -ThrottleLimit 4
```

### Why you might want sequential

* **Debugging.** gdb in one thread is dramatically easier than 20.
* **Parity diffing.** Two parallel runs of the PS script can yield
  identical `.prn` output but different stderr-warning order. Phase 8's
  parity gate runs **both PS and C with `-ThrottleLimit 1`** while it
  computes the bit-identical `.prn` diff. Reproduce locally the same way.
* **Rate-limited remotes.** GitHub API can 429 you out from a 20-wide
  fanout; drop to 4 or below to stay under the unauthenticated cap.

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
