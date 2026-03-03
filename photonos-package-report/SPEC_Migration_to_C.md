# Migration of photonos-package-report.ps1 to C - Token Estimation

**Created**: 2026-02-12
**Status**: Draft - Not Approved
**Author**: Droid/User collaboration

## Executive Summary

Migrating this 4,422-line PowerShell script to C would require approximately **2.5-4 million tokens** of AI-assisted development, translating to **50-100 hours of active session time** depending on model speed and iteration cycles.

## Token Consumption Estimation Model

**Assumptions:**
- Average tokens per response: ~2,000 tokens
- Average tokens per user prompt + context: ~1,500 tokens
- Tool calls overhead: ~500 tokens per operation
- Code generation: ~3 tokens per character of C code
- Iterative refinement: 2-3 cycles per component

## Phase-by-Phase Token Breakdown

### Phase 1: Architecture & Design
| Task | Tokens (Input) | Tokens (Output) | Sessions | Time |
|------|----------------|-----------------|----------|------|
| Analyze PS1 structure | 50,000 | 15,000 | 3 | 1.5h |
| Design C architecture | 10,000 | 25,000 | 2 | 1h |
| Define data structures | 8,000 | 20,000 | 2 | 1h |
| Plan library integration | 5,000 | 15,000 | 1 | 0.5h |
| **Subtotal** | **73,000** | **75,000** | **8** | **4h** |

### Phase 2: Core Utilities
| Component | Lines of C | Tokens (Input) | Tokens (Output) | Iterations | Time |
|-----------|------------|----------------|-----------------|------------|------|
| string_utils.c/.h | 600 | 30,000 | 45,000 | 3 | 2h |
| file_utils.c/.h | 400 | 20,000 | 30,000 | 2 | 1.5h |
| memory_pool.c/.h | 300 | 15,000 | 22,000 | 2 | 1h |
| config.c/.h | 200 | 10,000 | 15,000 | 2 | 0.75h |
| **Subtotal** | **1,500** | **75,000** | **112,000** | **9** | **5.25h** |

### Phase 3: Library Wrappers
| Component | Lines of C | Tokens (Input) | Tokens (Output) | Iterations | Time |
|-----------|------------|----------------|-----------------|------------|------|
| http_client.c/.h (curl) | 500 | 40,000 | 60,000 | 3 | 2.5h |
| json_utils.c/.h (cJSON) | 300 | 20,000 | 30,000 | 2 | 1.25h |
| regex_utils.c/.h (PCRE2) | 400 | 35,000 | 50,000 | 3 | 2h |
| hash_utils.c/.h (OpenSSL) | 200 | 15,000 | 20,000 | 2 | 1h |
| git_utils.c/.h | 500 | 35,000 | 50,000 | 3 | 2h |
| process_utils.c/.h | 300 | 20,000 | 30,000 | 2 | 1.25h |
| **Subtotal** | **2,200** | **165,000** | **240,000** | **15** | **10h** |

### Phase 4: Business Logic Migration
| Component | PS1 Lines | C Lines | Tokens (Input) | Tokens (Output) | Iterations | Time |
|-----------|-----------|---------|----------------|-----------------|------------|------|
| version_compare.c/.h | 200 | 500 | 50,000 | 75,000 | 4 | 3h |
| spec_parser.c/.h | 150 | 600 | 45,000 | 70,000 | 3 | 2.5h |
| source_lookup.c/.h | 580 | 800 | 60,000 | 90,000 | 3 | 3h |
| url_health.c/.h | 3,000 | 2,500 | 200,000 | 300,000 | 5 | 12h |
| report_generator.c/.h | 200 | 500 | 30,000 | 45,000 | 2 | 2h |
| **Subtotal** | **4,130** | **4,900** | **385,000** | **580,000** | **17** | **22.5h** |

### Phase 5: Parallel Processing
| Component | Lines of C | Tokens (Input) | Tokens (Output) | Iterations | Time |
|-----------|------------|----------------|-----------------|------------|------|
| thread_pool.c/.h | 400 | 40,000 | 60,000 | 3 | 2.5h |
| Synchronization logic | 200 | 25,000 | 35,000 | 2 | 1.5h |
| Integration testing | - | 30,000 | 20,000 | 3 | 1.5h |
| **Subtotal** | **600** | **95,000** | **115,000** | **8** | **5.5h** |

### Phase 6: Build System & Integration
| Task | Tokens (Input) | Tokens (Output) | Sessions | Time |
|------|----------------|-----------------|----------|------|
| CMakeLists.txt | 10,000 | 15,000 | 2 | 0.75h |
| main.c integration | 30,000 | 45,000 | 3 | 2h |
| Cross-platform #ifdefs | 25,000 | 35,000 | 2 | 1.5h |
| **Subtotal** | **65,000** | **95,000** | **7** | **4.25h** |

### Phase 7: Testing & Debugging
| Task | Tokens (Input) | Tokens (Output) | Sessions | Time |
|------|----------------|-----------------|----------|------|
| Unit tests | 50,000 | 80,000 | 5 | 3h |
| Integration tests | 40,000 | 60,000 | 4 | 2.5h |
| Bug fixes (est. 30 bugs) | 150,000 | 180,000 | 15 | 8h |
| Memory leak debugging | 40,000 | 50,000 | 4 | 2.5h |
| **Subtotal** | **280,000** | **370,000** | **28** | **16h** |

## Total Token Summary

| Phase | Input Tokens | Output Tokens | Total Tokens | Time |
|-------|--------------|---------------|--------------|------|
| 1. Architecture | 73,000 | 75,000 | 148,000 | 4h |
| 2. Core Utilities | 75,000 | 112,000 | 187,000 | 5.25h |
| 3. Library Wrappers | 165,000 | 240,000 | 405,000 | 10h |
| 4. Business Logic | 385,000 | 580,000 | 965,000 | 22.5h |
| 5. Parallel Processing | 95,000 | 115,000 | 210,000 | 5.5h |
| 6. Build & Integration | 65,000 | 95,000 | 160,000 | 4.25h |
| 7. Testing & Debugging | 280,000 | 370,000 | 650,000 | 16h |
| **TOTAL** | **1,138,000** | **1,587,000** | **2,725,000** | **67.5h** |

## Contingency & Overhead

| Factor | Multiplier | Adjusted Total |
|--------|------------|----------------|
| Base estimate | 1.0x | 2,725,000 tokens |
| Context window reloading | 1.2x | 3,270,000 tokens |
| Unexpected issues | 1.3x | 3,542,500 tokens |
| Cross-platform edge cases | 1.1x | 3,896,750 tokens |
| **Final Estimate** | **~1.4x** | **~3.8M tokens** |

## Time Breakdown by Model Speed

| Model/Rate | Tokens/min | Total Time |
|------------|------------|------------|
| Claude Opus (fast) | 1,500 | ~42 hours |
| Claude Sonnet | 2,000 | ~32 hours |
| With human review/iteration | - | ~70-90 hours |

## Cost Estimation (at typical API rates)

| Metric | Value |
|--------|-------|
| Input tokens | ~1.5M |
| Output tokens | ~2.3M |
| Estimated cost (Opus) | $45-75 |
| Estimated cost (Sonnet) | $15-25 |

## Deliverables

- **~10,000 lines of C code** across 16+ source files
- **CMake build system** for cross-platform compilation
- **Unit tests** for core components
- **Documentation** (README, API docs)

## Current Script Analysis

| Metric | Value |
|--------|-------|
| Lines of code | 4,422 |
| Functions | 12 |
| Regex operations | 239 |
| HTTP requests | 8+ distinct call patterns |
| File I/O operations | 15+ patterns |
| String manipulations | 500+ |
| External commands (git, tar) | 20+ |

## Required C Libraries

| Library | Purpose | License |
|---------|---------|---------|
| **libcurl** | HTTP/HTTPS requests | MIT |
| **PCRE2** | Regular expressions | BSD |
| **cJSON** or **json-c** | JSON parsing | MIT |
| **OpenSSL** | SHA256/512 hashing, TLS | Apache 2.0 |
| **pthreads** | Parallel processing | POSIX |
| **libgit2** | Git operations (alternative to shelling out) | GPL2 |
| **zlib** | Archive extraction | zlib |
| **libarchive** | tar/xz/bz2 handling | BSD |

## Estimated C Code Structure

```
photon-package-report/
+-- src/
¦   +-- main.c                    (~300 lines)
¦   +-- config.c/.h               (~200 lines) - CLI args, env vars
¦   +-- http_client.c/.h          (~500 lines) - curl wrapper
¦   +-- json_utils.c/.h           (~300 lines) - JSON parsing
¦   +-- regex_utils.c/.h          (~400 lines) - PCRE2 wrapper
¦   +-- string_utils.c/.h         (~600 lines) - string manipulation
¦   +-- file_utils.c/.h           (~400 lines) - file I/O
¦   +-- git_utils.c/.h            (~500 lines) - git operations
¦   +-- process_utils.c/.h        (~300 lines) - subprocess handling
¦   +-- thread_pool.c/.h          (~400 lines) - parallel processing
¦   +-- version_compare.c/.h      (~500 lines) - version parsing/comparison
¦   +-- url_health.c/.h           (~2000 lines) - CheckURLHealth logic
¦   +-- source_lookup.c/.h        (~800 lines) - Source0Lookup data
¦   +-- spec_parser.c/.h          (~600 lines) - spec file parsing
¦   +-- report_generator.c/.h     (~500 lines) - CSV output
¦   +-- hash_utils.c/.h           (~200 lines) - SHA256/512
¦   +-- memory_pool.c/.h          (~300 lines) - memory management
+-- include/
¦   +-- common.h                  (~100 lines)
+-- data/
¦   +-- source0_lookup.csv        (embedded or external)
+-- CMakeLists.txt                (~100 lines)
+-- Makefile                      (~50 lines)
+-- README.md
```

**Estimated total: 8,000-10,000 lines of C code** (plus ~5,000-15,000 lines for library wrappers and error handling)

## Recommendation

The token cost is manageable (~$50-75 with Opus), but the **~70 hours of active session time** and **coordination complexity** make this a significant project. Consider:

1. **Go or Rust** would require ~40% fewer tokens due to better abstractions
2. **Incremental approach**: Migrate only performance-critical sections to C
3. **Keep PowerShell**: Current solution works; optimize rather than rewrite

---

## Notes

- This specification is a draft and requires approval before implementation
- Token estimates are based on similar migration projects
- Actual token usage may vary based on complexity discovered during implementation
- Human review time is not included in token estimates
