# Task 007 — Swarm Validation

| Field | Value |
|-------|-------|
| **Status** | Pending |
| **Phase** | 3 — New Capabilities |
| **Dependencies** | 003, 004, 005 |
| **PRD Refs** | PRD §12 (Swarm Architecture), §13 (Quality Gates) |

## Description

Validate the 5-team Factory AI swarm integration end-to-end. Verify that
quality gates between teams function correctly and that the sequential
execution order (Maintenance → Sandbox → Blogger → Translator) is enforced,
while the Security team runs as a continuous parallel monitor.

## Acceptance Criteria

- [ ] End-to-end test harness exercises all 5 swarm teams
- [ ] Sequential order verified: Maintenance → Sandbox → Blogger → Translator
- [ ] Security team confirmed running in parallel throughout the pipeline
- [ ] Quality gate between Maintenance and Sandbox validates clean DB state
- [ ] Quality gate between Sandbox and Blogger validates summary completeness
- [ ] Quality gate between Blogger and Translator validates Hugo frontmatter
- [ ] Failure in any gate halts downstream teams and reports clearly
- [ ] Test report generated with pass/fail per team and per gate

## Implementation Notes

- Use subprocess or API calls to trigger each team depending on swarm runner.
- Quality gates can be simple assertion functions checking DB/file state.
- Security team monitoring can be validated by checking its log output timestamps.
- Consider a `conftest.py` fixture that sets up a temporary DB for isolation.
- The test harness should support `--dry-run` for CI environments without API keys.
