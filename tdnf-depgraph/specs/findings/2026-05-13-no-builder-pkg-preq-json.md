# Finding 2026-05-13d: `vmware/photon` has no `data/builder-pkg-preq.json`

**Status**: Addressed — PRD v1.3 amends G3 success metric; task 016 lands a synthesized preq fixture.
**Discovered while implementing**: [task 016 (regression fixture)](../tasks/016-task-regression-fixture.md), 2026-05-13.
**Affects**: [prd.md §4 G3](../prd.md), [prd.md §6 AC-1](../prd.md), [adr/0005-bootstrap-resolved-classification.md](../adr/0005-bootstrap-resolved-classification.md), [tasks/016-task-regression-fixture.md](../tasks/016-task-regression-fixture.md), [tools/depgraph_cycles.py](../../tools/depgraph_cycles.py) `--preq` CLI.

## Summary

The PRD references `data/builder-pkg-preq.json` in `vmware/photon` as the canonical pre-stage package list against which the engine classifies each SCC's `bootstrap_resolved` boolean. The PRD's motivating commit comment also asserted that the libselinux fix added entries to that file.

**Empirical state on 2026-05-13:**

```
$ gh api 'repos/vmware/photon/git/trees/master?recursive=1' \
    | jq -r '.tree[] | select(.path | test("preq|builder-pkg|pre[-_]stage|bootstrap"; "i")) | .path'
$ gh api repos/vmware/photon/contents/data?ref=master --jq '.[].name'
{"message":"Not Found", ...}
```

No file under `data/` exists, and no file anywhere in the tree contains `preq`, `builder-pkg`, `pre-stage`, or `bootstrap` in its name. The recursive git tree search returns zero matches. The PRD's reference was fictional.

## Where the actual pre-stage list lives

The canonical pre-stage package definition lives in `support/package-builder/constants.py` as three Python class attributes on `class constants`:

- `listCoreToolChainPackages` — 17 names (bootstrap floor)
- `listToolChainPackages` — ~60 names (build toolchain)
- `listToolChainRPMsToInstall` — ~120 names (toolchain RPMs incl. subpackages)

Source pin (vmware/photon@master tip on 2026-05-11):

> https://github.com/vmware/photon/blob/0b37ad6f1c30/support/package-builder/constants.py

The lists are Python-resident — there is no JSON sidecar that could be globbed from disk by an external tool.

## Implication for the engine

[`tools/depgraph_cycles.py`](../../tools/depgraph_cycles.py) `load_preq()` walks any JSON file and collects every string leaf into the pre-stage set. It does not care about file location, schema, or whether the source is upstream. The function gracefully handles a missing file (returns `set()`; every SCC then classifies `bootstrap_resolved: false`, per ADR-0005 conservative default).

So the engine itself is unaffected by upstream's missing file. What changes is the **provenance** of any pre-stage set the workflow or tests load — it is necessarily synthesized, not pulled from upstream as the PRD originally implied.

## Gap with the PRD's G3 success metric

PRD G3 v1.1 claimed: *"On the 2026-05-11 master scan with the branch's real `data/builder-pkg-preq.json` loaded, the 37-node toolchain SCC reports `bootstrap_resolved: true` and is excluded from the `unresolved` summary counter."*

This is unsatisfiable for two compounding reasons:

1. The file does not exist (this finding).
2. Even if we use `support/package-builder/constants.py`'s `listToolChainRPMsToInstall` (the most-expansive upstream list), it does not cover every member of the 37-node SCC discovered by the engine. Specifically, `listToolChainRPMsToInstall` omits: `autogen`, `cmake`, `curl`/`curl-devel`/`curl-libs`, `dejagnu`, `e2fsprogs`/`e2fsprogs-devel`, `expect`/`expect-devel`, `guile`/`guile-devel`, `krb5`/`krb5-devel`, `libarchive`/`libarchive-devel`, `libffi-devel`, `libssh2`/`libssh2-devel`, `python3`/`python3-libs`, `tcl`/`tcl-devel` — 24 of the 37 names. The engine's classification rule requires every SCC member to be in the pre-stage set (ADR-0005), so even with upstream's real list loaded the SCC would still report `bootstrap_resolved: false`.

The 37-node SCC reflects the actual binary edge graph the engine derives from spec dependencies; it is broader than upstream's stated toolchain because runtime `Requires` edges drag in additional packages (curl, krb5, python3 — i.e. tools the toolchain consumes at build time and that are themselves part of the build graph).

## Resolution

Phase-1d PR (this task 016 PR) lands:

1. **A synthesized preq fixture** at `tdnf-depgraph/tests/fixtures/builder-pkg-preq.synthetic.20260511.json`. The file is structured as a dict containing the three upstream lists (verbatim from `constants.py` at commit `0b37ad6f1c30`) plus an explicit `_augmentation_for_37_node_scc` key listing the 24 additional names needed to cover the SCC. The `_README` key inside the JSON explains provenance and pins the source commit. The engine walks all string leaves identically — the partitioning is documentary.

2. **PRD G3 amended to v1.3** — the success metric now reads:

   > *"On the 2026-05-11 master fixture, when fed the synthesized pre-stage list at `tdnf-depgraph/tests/fixtures/builder-pkg-preq.synthetic.20260511.json` (derived from upstream `support/package-builder/constants.py` augmented to cover the engine's 37-node toolchain SCC; see [findings/2026-05-13-no-builder-pkg-preq-json.md](findings/2026-05-13-no-builder-pkg-preq-json.md)), the 37-node toolchain SCC reports `bootstrap_resolved: true` and is excluded from the `unresolved` summary counter. The `python3-attrs ↔ python3-pytest` cycle remains `bootstrap_resolved: false`."*

3. **ADR-0005 amended** — the "what counts as pre-stage" section now points at `support/package-builder/constants.py` for upstream's authoritative list and explicitly acknowledges the SCC-membership-vs-upstream-list discrepancy.

4. **New PRD Open Question Q5**: should the engine's classification rule be relaxed (e.g. "≥80% of SCC members in pre-stage set" rather than "100%")? A relaxed rule would make `bootstrap_resolved: true` achievable against upstream's actual list, but introduces a tunable threshold; conservative default per ADR-0005 is to keep the strict rule and use synthesized fixtures for testing. Recommendation: leave strict rule in place; revisit if real upstream cooperation produces a comprehensive list.

5. **Workflow unchanged** — `depgraph-scan.yml` already handles the missing preq via a single `::warning::` annotation per (branch, flavor), per task 014. Every SCC stays `bootstrap_resolved: false` until upstream cooperation or a deliberate operator-supplied fixture exists. This is the intended steady state.

## Re-verification

```
$ python3 -m unittest discover -s tdnf-depgraph/tests -v
...
test_python3_attrs_pytest_buildrequires_cycle (TestRegression20260511) ... ok
test_toolchain_scc_bootstrap_resolved_with_preq (TestRegression20260511) ... ok
test_twelve_sccs_one_of_size_37 (TestRegression20260511) ... ok
...
Ran 15 tests in 0.085s
OK
```

All three regression tests pass: AC-1 anchor (BR cycle), structural anchor (12 SCCs / one of size 37 with required toolchain members), and G3 anchor (synthesized preq → SCC flips, py-attrs/pytest stays).
