# AGENTS.md — sharukhan

**Authored by hand for this subproject.** The SDD sources this project follows reference an `AGENTS.md` but generate it from an Azure-centric APM toolchain (`apm install && apm compile`) that has no bearing on a local Rust CLI, and neither source commits the file. Nothing here is inherited; it is written for Rust and for this tool's threat model.

## Roles

| Agent | Responsibility | Hard boundary |
|---|---|---|
| **PM** | PRD and FRDs — defines *what* | Never specifies crates, module layout, schemas, or flags' internal handling |
| **Dev Lead** | Feasibility review on the PRD PR | Simplicity first: rejects scope not explicitly requested |
| **Architect** | ADRs — one decision each, ≥3 options considered | Does not write implementation |
| **Developer** | Tasks and code | Consumes ADRs; hands unclear design decisions back to the Architect rather than deciding in code |

## Rust standards

- `cargo clippy -- -D warnings` and `cargo fmt --check` are gates, not suggestions.
- **No `unwrap()` or `expect()` outside `#[cfg(test)]`.** A CLI that panics on a missing binary or a malformed VMX gives the operator a backtrace instead of a diagnosis.
- Errors are typed at module boundaries and contextual at the binary boundary. A failure must say *which* input was bad and *what was expected*.
- Print measured values, never a bare OK/FAIL. "tool missing" and "tool present but not executable by this user" need different fixes and are indistinguishable in a boolean — this rule is inherited from the shell tooling `sharukhan` replaces and is not negotiable.
- Every check that can be vacuous carries a negative control.
- Unit tests live in `#[cfg(test)] mod tests`; integration tests in `tests/<module>.rs` mirroring `src/<module>.rs`.

## Security posture

`sharukhan` orchestrates VMs, runs installs, and stores results. It is a test harness, not a production service, but it handles credentials and executes external binaries, so:

- **No credential ever reaches a process argument.** Arguments are world-readable via `/proc`. Secrets travel by environment or file descriptor only.
- **No credential is ever written to the memory database or a log.** Fields that could carry one are redacted at the boundary, and the redaction is tested.
- **Every external command is invoked with an argument vector**, never a shell string. No interpolation of caller data into a shell.
- **Every SQL statement is parameterised.** No string-built SQL, ever.
- **Paths derived from configuration are validated** before use in destructive operations. A teardown that accepts an arbitrary path is a footgun.
- **Destructive operations stash, never delete**, by default, and target one named VM. Blanket operations across a hypervisor are forbidden — this host runs other people's VMs.
- Prerequisite checks report the *version and provenance* of each external binary, because a version-skewed dependency (openssh built against a different OpenSSL) presents exactly like an unreachable host.

Control mappings for these are recorded in `specs/adr/` and the PRD's non-functional requirements rather than duplicated here.
