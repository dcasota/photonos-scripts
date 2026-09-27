# Task 001 — `sharukhan wrapper`: generic kernel wrapper derivation

Feature: [FRD-001](../features/kernel-wrapper.md) · Decisions: ADR-0002 .. ADR-0007
Status: done (2026-09-27)

| # | Step | Acceptance | Status |
|---|---|---|---|
| 1 | Release grammar and computed identity (`identity.rs`) | KW-2..KW-4 tests | done |
| 2 | Context validators, changelog dates with checked weekday (`escape.rs`) | KW-8, KW-21 tests | done |
| 3 | Strict profile schema (`profile.rs`), 7.3-rc4 profile | KW-17, KW-24 tests | done |
| 4 | Base declaration and slots (`base.rs`); mark up `staging/runPh7-2-7.sh`, fix its stale header, make its clean-up version-neutral | KW-5..KW-7, KW-33 fixtures | done |
| 5 | Slot renderers (`render.rs`) | golden | done |
| 6 | Derivation pipeline with collision, leak, rename-count and leftover checks, atomic write, `--check` (`derive.rs`) | KW-9..KW-15, KW-18, KW-22 controls | done |
| 7 | Output validation on stdin: `sh -n`, Python heredocs (`validate.rs`) | KW-13 tests | done |
| 8 | kernel.org: releases.json, selectors, trust file, private keyring, `.tar.sign` and signed-tag verification, tar walk (`kernelorg.rs`, `sha512.rs`) | KW-25..KW-27, KW-29, KW-31 tests with a throwaway signing key; live runs | done |
| 9 | Branch manifest and patch-file check (`branch.rs`) | KW-28 tests with a fixture clone; live run | done |
| 10 | CLI (`cli.rs`), dispatch and help in `main.rs` | KW-16, KW-30 tests; live runs | done |
| 11 | Golden: committed base + profile derive `staging/runPh7-3-RC4.sh` byte for byte | `cli::tests::golden_*` | done |
| 12 | Retire `tools/make-73rc4.py` | ADR-0007 | done |
| 13 | Gates: tests, clippy and fmt clean for the new files, coverage ≥ 80 % | 88 % of lines over `src/wrapper/` + `src/sha512.rs` (cargo-llvm-cov, rustup 1.97 toolchain; the system rustc has no profiler runtime) | done |

Live runs, 2026-09-27: see FRD-001 §5. Found while testing and fixed: concurrent derivations shared
one scratch path in `/tmp` (one run deleted the other's copy before `sh -n` read it); validation
now feeds the script to `sh -n` and `python3` on stdin and writes nothing.
