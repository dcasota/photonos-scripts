# Task 008: Architecture Decision Records

**Dependencies**: Task 007
**Complexity**: Low
**Status**: Complete

---

## Description

Document the three key decisions as ADRs following the format from SDD-book-tracking-app.

## ADRs Created

1. **ADR-0001**: Snapshot bypass via photon-mainline
   - Documents the initial fix and its limitations
   - References: `common/build.py` line 1518

2. **ADR-0002**: tdnf upgrade conflict when snapshot is bypassed
   - Documents the C3+ root cause discovery
   - Blast radius: 86 packages, 6 root-cause gated packages
   - References: `PackageUtils.py`, `TDNFSandbox.py`

3. **ADR-0003**: Detection agent architecture
   - Documents why single-script Python, why no LLM, why deterministic
   - Maps agent roles to functions

## Acceptance Criteria

- [ ] Each ADR follows Context / Decision Drivers / Options / Outcome / Consequences structure
- [ ] ADR-0001 cross-references ADR-0002 (caveats)
- [ ] ADR-0002 includes blast-radius table with consumer counts
- [ ] ADR-0003 maps all 6 agents to code functions
