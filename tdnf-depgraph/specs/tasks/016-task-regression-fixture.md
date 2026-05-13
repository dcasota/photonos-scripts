# Task 016: Regression Fixture for the 2026-05-11 Snapshot

**Complexity**: Low
**Dependencies**: [012](012-task-cycle-engine.md)
**Status**: Complete
**Requirement**: PRD AC-1 (amended 2026-05-13, v1.1) + G3 (amended 2026-05-13, v1.3)
**ADR**: N/A (testing infrastructure)

> **Amended 2026-05-13** per [`../findings/2026-05-13-libselinux-python3-not-a-graph-cycle.md`](../findings/2026-05-13-libselinux-python3-not-a-graph-cycle.md). The original acceptance test anchored on a `libselinux ↔ python3` cycle that does not exist as a graph-level SCC in the fixture. Replaced with a `python3-attrs ↔ python3-pytest` anchor (the lone buildrequires cycle on the master fixture) plus a structural assertion on the 37-node toolchain SCC.
>
> **Amended again 2026-05-13** per [`../findings/2026-05-13-no-builder-pkg-preq-json.md`](../findings/2026-05-13-no-builder-pkg-preq-json.md). The G3 test was originally specified to load the branch's real `data/builder-pkg-preq.json` — that file does not exist in `vmware/photon`. The fixture is now synthesized from `support/package-builder/constants.py` (the actual upstream toolchain definition) augmented with the 24 SCC members upstream's list omits. Documented in the fixture file's `_README` key.

---

## Description

Check in the 2026-05-11 `vmware/photon` master dependency-graph JSON (workflow run [`25661049895`](https://github.com/dcasota/photonos-scripts/actions/runs/25661049895)) as a permanent regression fixture. Add unit tests that run the cycle engine on this fixture and assert the cycles documented in PRD AC-1 v1.1.

This task answers PRD §8 Open Question Q1 affirmatively: check in the fixture.

## Scope

- New file: `tdnf-depgraph/tests/fixtures/dependency-graph-master-20260511_091039.v1.json`. The byte-identical content currently sitting at `tdnf-depgraph/scans/dependency-graph-master-20260511_091039.json` *as of the pre-task-012 master tree* — that is, the v1 JSON, before any cycle pass has run. (A copy is needed because the production `scans/` location is the workflow's write target; tests must not depend on the live commit-back state.)
- New file: `tdnf-depgraph/tests/fixtures/builder-pkg-preq.synthetic.20260511.json`. The synthesized pre-stage fixture. Derived from `vmware/photon@0b37ad6f1c30:support/package-builder/constants.py` (the three Python lists `listCoreToolChainPackages`, `listToolChainPackages`, `listToolChainRPMsToInstall`) augmented with the 24 names upstream's lists omit but are required to cover the engine's 37-node SCC. Provenance documented in the file's `_README` key. Used to verify the `bootstrap_resolved: true` flip on the 37-node toolchain SCC (G3 success metric). The original spec referenced `builder-pkg-preq.20260511.json`; see [findings/2026-05-13-no-builder-pkg-preq-json.md](../findings/2026-05-13-no-builder-pkg-preq-json.md) for why the file is synthesized and not a verbatim upstream copy.
- New test class in `tdnf-depgraph/tests/test_depgraph_cycles.py`:
  ```python
  class TestRegression20260511(unittest.TestCase):
      FIXTURE = "tests/fixtures/dependency-graph-master-20260511_091039.v1.json"
      PREQ    = "tests/fixtures/builder-pkg-preq.20260511.json"

      def test_python3_attrs_pytest_buildrequires_cycle(self):
          """AC-1 anchor: the lone buildrequires cycle on the master fixture."""
          out = run_pass(self.FIXTURE, preq=None)
          cycles = out["cycles"]
          self.assertTrue(any(
              c["category"] == "buildrequires"
              and c["length"] == 2
              and not c["bootstrap_resolved"]
              and c["path_names"] == [
                  "python3-attrs", "python3-pytest", "python3-attrs"
              ]
              for c in cycles
          ), f"expected python3-attrs <-> python3-pytest buildrequires cycle; "
             f"got cycles: {[c['path_names'] for c in cycles]}")

      def test_twelve_sccs_one_of_size_37(self):
          """AC-1 structural anchor: 12 SCCs, one toolchain SCC of size 37."""
          out = run_pass(self.FIXTURE, preq=None)
          self.assertEqual(len(out["sccs"]), 12)
          big = [s for s in out["sccs"] if s["size"] == 37]
          self.assertEqual(len(big), 1)
          names = set(big[0]["names"])
          for required in {"python3", "gcc", "bash", "cmake", "openssl"}:
              self.assertIn(required, names)

      def test_toolchain_scc_bootstrap_resolved_with_preq(self):
          """G3 success metric: with the real preq file, the 37-node toolchain
          SCC flips to bootstrap_resolved: true, while python3-attrs/pytest
          remains unresolved (those packages are not in builder-pkg-preq.json)."""
          out = run_pass(self.FIXTURE, preq=self.PREQ)
          toolchain = next(s for s in out["sccs"] if s["size"] == 37)
          self.assertTrue(toolchain["bootstrap_resolved"])
          attrs_pytest = next(
              c for c in out["cycles"]
              if c["path_names"] == [
                  "python3-attrs", "python3-pytest", "python3-attrs"
              ]
          )
          self.assertFalse(attrs_pytest["bootstrap_resolved"])
  ```

  `run_pass(fixture, preq=None)` is a thin wrapper around
  `depgraph_cycles.run(input_path, preq_path, flavor="", specsdir_meta="SPECS")`
  that resolves fixture paths relative to the test file.

## Implementation Notes

- The dependency-graph fixture file is ~660 KB; well within reasonable repository size limits.
- The pre-fix `builder-pkg-preq.json` must be sourced from the commit on `vmware/photon` master that was current on 2026-05-11 (not today's tip). A short header comment in the fixture file identifies the source commit SHA.
- Both fixtures live under `tests/fixtures/` to keep them out of any `scans/`-targeted glob in downstream workflows.
- The unit tests must not depend on network access or on `vmware/photon` cloning — they read only the checked-in fixtures.
- The fixture is **frozen in time**: it anchors the cycle engine's behaviour at the 2026-05-11 master state. It will not be refreshed when later master scans land. This is by design — the test guarantees the engine continues to find the same 12 SCCs on the same input forever.

## Acceptance Criteria

- [x] **AC-1 (v1.1).** All three tests in `TestRegression20260511` pass: `python3-attrs ↔ python3-pytest` buildrequires cycle is present and `bootstrap_resolved: false` without preq; `len(sccs) == 12` and one SCC has size 37 with the required toolchain members.
- [x] **G3 success metric (v1.3).** With the synthesized preq fixture, the 37-node toolchain SCC reports `bootstrap_resolved: true`; the python3-attrs/pytest cycle remains `bootstrap_resolved: false`.
- [x] The dependency-graph fixture file is byte-identical to the v1 content of `tdnf-depgraph/scans/dependency-graph-master-20260511_091039.json` at the master commit immediately preceding task 012. SHA-256 `290b60aec07a60acd6c58c5b595182a603863301ad72ae275f08baee1dafa479` recorded in the test class docstring.
- [x] The synthesized preq fixture is documented at the top of the file with its source commit SHA (`0b37ad6f1c30`) and the rationale for augmentation (per [findings/2026-05-13-no-builder-pkg-preq-json.md](../findings/2026-05-13-no-builder-pkg-preq-json.md)).

## Testing Requirements

- [ ] CI runs the regression tests on every PR touching `tdnf-depgraph/tools/depgraph_cycles.py` or `tdnf-depgraph/tests/`.

## Out of Scope

- Regression fixtures for branches other than master.
- Periodic refresh of the fixture (frozen by design).
- Surfacing the `libselinux ↔ python3` spec-source coupling as a graph cycle. Tracked separately by PRD §8 Q4 (whether the C extension should propagate source-level `BuildRequires` to subpackages).
