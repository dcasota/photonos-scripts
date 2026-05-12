# Task 016: Regression Fixture for the 2026-05-11 Snapshot

**Complexity**: Low
**Dependencies**: [012](012-task-cycle-engine.md)
**Status**: Pending
**Requirement**: PRD AC-1
**ADR**: N/A (testing infrastructure)

---

## Description

Check in the pre-fix `vmware/photon` master dependency-graph JSON from 2026-05-11 (workflow run [`25661049895`](https://github.com/dcasota/photonos-scripts/actions/runs/25661049895)) as a permanent regression fixture. Add a unit test that runs the cycle engine on this fixture and asserts the presence of the libselinux ↔ python3 cycle.

This task answers PRD §8 Open Question Q1 affirmatively: check in the fixture.

## Scope

- New file: `tdnf-depgraph/tests/fixtures/dependency-graph-master-20260511_091039.v1.json`. The byte-identical content downloaded from the run's `dependency-graphs` artifact.
- New file: `tdnf-depgraph/tests/fixtures/builder-pkg-preq.20260511.json`. The `data/builder-pkg-preq.json` content from `vmware/photon@<commit-of-2026-05-11>` *before* the libselinux/libsepol amendment. This is what makes AC-1 produce `bootstrap_resolved: false` — without it, the post-fix amendment masks the cycle.
- New test case in `tdnf-depgraph/tests/test_depgraph_cycles.py`:
  ```python
  def test_libselinux_python3_cycle_2026_05_11(self):
      out = run_cycles_pass(
          input="tests/fixtures/dependency-graph-master-20260511_091039.v1.json",
          preq="tests/fixtures/builder-pkg-preq.20260511.json",
      )
      cycles = out["cycles"]
      assert any(
          c["category"] == "buildrequires"
          and not c["bootstrap_resolved"]
          and "libselinux" in c["path_names"]
          and any(n.startswith("python3") for n in c["path_names"])
          for c in cycles
      )
  ```

## Implementation Notes

- The fixture file is ~660 KB; well within reasonable repository size limits.
- The pre-fix `builder-pkg-preq.json` must be sourced from the commit on `vmware/photon` master that was current on 2026-05-11 (not today's tip). A short header comment in the fixture identifies the source commit.
- Both fixtures live under `tests/fixtures/` to keep them out of any `scans/`-targeted glob in downstream workflows.
- The unit test must not depend on network access or on `vmware/photon` cloning — it reads only the checked-in fixtures.

## Acceptance Criteria

- [ ] **AC-1.** Running `python3 -m unittest tdnf-depgraph.tests.test_depgraph_cycles.TestRegression.test_libselinux_python3_cycle_2026_05_11` passes.
- [ ] The fixture file is byte-identical to the artifact downloaded from run 25661049895. SHA-256 recorded in a comment at the top of the test.
- [ ] The pre-fix `builder-pkg-preq.json` is documented in the file header with its source commit SHA.
- [ ] The test asserts both presence of `libselinux` and presence of at least one `python3*` node in the same cycle's `path_names`.

## Testing Requirements

- [ ] CI runs the regression test on every PR touching `tdnf-depgraph/tools/depgraph_cycles.py` or `tdnf-depgraph/tests/`.

## Out of Scope

- Regression fixtures for branches other than master.
- Periodic refresh of the fixture (it is anchored to a specific historic state — the libselinux ↔ python3 incident — by design).
