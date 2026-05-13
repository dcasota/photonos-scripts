# Finding 2026-05-13: libselinux ↔ python3 is not a graph-level cycle

**Status**: Addressed — PRD v1.1 and task 016 amended on 2026-05-13. New open question Q4 opened in the PRD for the separate spec-source-coupling initiative.
**Discovered while implementing**: [task 012 (cycle engine)](../tasks/012-task-cycle-engine.md)
**Affects**: [prd.md §6 AC-1](../prd.md), [tasks/016-task-regression-fixture.md](../tasks/016-task-regression-fixture.md)

## Summary

The PRD (acceptance criterion AC-1) asserts that running the cycle engine on the 2026-05-11 master snapshot (`tdnf-depgraph/scans/dependency-graph-master-20260511_091039.json`) must produce a cycle whose `path_names` contains both `libselinux` and a `python3-*` node. **Empirically, no such cycle exists in that file.** The "loop" referenced in the motivating commit (`vmware/photon@8fb8549c`, *"breaks the dependency loop of libselinux ↔ python3"*) is real at the spec-source-coupling level, but is not captured as a strongly-connected component in the binary-package edge graph that the C extension exports.

## What the engine actually finds on this fixture

Twelve cycles across twelve SCCs. None contain `libselinux`, `libselinux-python3`, or `selinux-python`.

| # | Category | Length | Path |
|---|---|---|---|
| cyc-001 | requires | 3 | apparmor-abstractions → apparmor-parser → apparmor-profiles → apparmor-abstractions |
| cyc-002 | mixed | 8 | autogen → libffi → dejagnu → expect → tcl → cmake → ncurses → gcc → autogen *(toolchain cluster, SCC size 37)* |
| cyc-003 | mixed | 7 | debugedit → dwz → gdb → systemtap-sdt-devel → systemtap → rpm-devel → rpm → debugedit |
| cyc-004 | requires | 2 | fail2ban ↔ fail2ban-sendmail |
| cyc-005 | requires | 2 | libllvm ↔ llvm |
| cyc-006..009 | requires | 2 | postgresql{13,14,15,16} ↔ postgresql{13,14,15,16}-server |
| cyc-010 | buildrequires | 2 | python3-attrs ↔ python3-pytest |
| cyc-011 | requires | 2 | shadow ↔ shadow-tools |
| cyc-012 | requires | 2 | systemd ↔ systemd-pam |

All twelve are `bootstrap_resolved: false` when computed against an empty pre-stage set; many are expected to flip to `true` once measured against the branch's actual `data/builder-pkg-preq.json` (in particular SCC-002 — the 37-node toolchain cluster).

## Why libselinux is not in any SCC

The relevant edges in the fixture:

```
libselinux → buildrequires → util-linux-devel        (in SCC-002 toolchain cluster)
libselinux → buildrequires → python3-pip/setuptools/devel
libselinux → buildrequires → swig, pcre2-devel, libsepol-devel
libselinux → requires      → pcre2-libs

libselinux-python3 → requires → libselinux
libselinux-python3 → requires → python3

selinux-python → buildrequires → python3-pip/setuptools/devel, libselinux-devel, libsepol-devel
selinux-python → requires      → libselinux, libselinux-python3, libsemanage-python3, python3, ...
```

For a graph cycle through `libselinux`, we would need a path from one of `libselinux`'s outgoing destinations back to `libselinux` itself. Concretely: `libselinux → util-linux-devel → ...(within SCC-002)... → libselinux`. **No member of SCC-002 has an outgoing edge to `libselinux`** in this fixture. The SCC-002 cluster is closed under cycle-relevant edges to its 37 toolchain members; libselinux sits *outside* it as a downstream consumer.

The spec-level "loop" the Photon team identified — *"to build libselinux you need python3-devel; to ship the libselinux-python3 subpackage you need libselinux already built"* — is a coupling at the **source-package** level (the `libselinux.spec` source package both produces `libselinux` and `BuildRequires: python3-devel`). The C extension records `BuildRequires` against the source-package node only (e.g. on the `libselinux` node), not propagated to subpackages. So the "loop" surfaces as a *constraint on a single source* — not as a directed cycle in the binary graph.

## Implications

1. **PRD AC-1 is empirically incorrect** as written. It is not a defect of the engine.
2. **Task 016 (regression fixture)** as written cannot be satisfied; the unit test it specifies would fail on the real 2026-05-11 data.
3. **Task 012's "AC-1 hook" acceptance criterion** is similarly unmet. Every other criterion in task 012 (AC-2 determinism, AC-5 schema, empty/self-loop/mixed cases, sub-package resolution, iterative-Tarjan depth) passes.

## Resolution (2026-05-13)

PR `sdd/depgraph-phase-1b-amend-ac1` amended the PRD to v1.1 and rewrote task 016:

1. **PRD AC-1 rewritten** to anchor on `path_names == ["python3-attrs", "python3-pytest", "python3-attrs"]` (the lone buildrequires cycle, length 2, `bootstrap_resolved: false`) plus a structural assertion that the fixture produces exactly 12 SCCs, one of size 37 containing `python3`, `gcc`, `bash`, `cmake`, `openssl`.
2. **PRD G1 success metric rewritten** to match.
3. **PRD G3 success metric rewritten** to anchor on the 37-node toolchain SCC flipping to `bootstrap_resolved: true` once the branch's real `builder-pkg-preq.json` loads — replacing the (incorrect) claim about a libselinux ↔ python3 SCC.
4. **PRD G4 v1-key list corrected** to `metadata.{generator, timestamp, branch}` (the keys the C extension actually emits) rather than the aspirational `branch`/`specsdir`/`generated_at` of v1.0.
5. **Task 016 rewritten** with three concrete test cases: `python3-attrs ↔ python3-pytest` cycle presence, structural 12-SCCs / one-size-37 assertion, and the bootstrap-resolved flip on the toolchain SCC.
6. **New PRD Open Question Q4**: should the C `tdnf-depgraph` extension propagate source-level `BuildRequires` to subpackages, so that spec-source-couplings (like the original libselinux ↔ python3 incident) surface as graph cycles? Recommendation: separate initiative, its own PRD.

This finding remains in `specs/findings/` as the empirical record of why the v1.0 PRD's AC-1 could not be satisfied.

## Pointer

The engine implementation that produced these results is the one landing in this PR (task 012). All 12 unit tests pass; the engine is correct by graph-theoretic standards. The mismatch is in the spec's assumption about the data, not in the engine.
