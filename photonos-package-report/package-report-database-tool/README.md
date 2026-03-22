# photon-report-db

C command-line tool that imports Photon OS URL-health scan files (`.prn`)
into a local SQLite database and generates a Word `.docx` trend-analysis
report with embedded OOXML charts.

## What it does

| Step | Description |
|------|-------------|
| **Import** | Reads every `photonos-urlhealth-<branch>_<datetime>.prn` from a directory, auto-detects encoding (UTF-16LE / UTF-8) and column schema (5-col 2023 format / 12-col 2026+ format), deduplicates on filename, computes SHA-256, and inserts all rows into SQLite inside a single transaction per file. |
| **Report** | Queries the database and writes a `.docx` containing four sections (see below). |

### Report sections

1. **Timeline line chart** -- packages matching `UrlHealth=200`,
   `UpdateAvailable` is a version string, and `UpdateDownloadName` matches
   `name-version.tar.*`, plotted per branch over time (dotted series for
   3.0, 4.0, 5.0, 6.0, common, master, dev).
2. **Top 10 most-changed packages** across **all branches** (2023--current)
   with per-year breakdown (2023 / 2024 / 2025 / 2026) and branch list.
3. **Least-changed packages** present in all 7 branches (3.0, 4.0, 5.0,
   6.0, common, dev, master) from 2023--current, excluding VMware-internal
   (`vmware.com`, `broadcom.com` in Source0 or warning) and archived
   packages (non-empty `ArchivationDate`).
4. **Source category drift** -- pie chart categorising packages by source
   domain (categories >= 3% shown individually, rest merged into Other),
   plus a 3D stacked bar chart showing how each category's percentage
   drifts over time per branch and scan run.

## Prerequisites

| Dependency | Minimum | Notes |
|------------|---------|-------|
| GCC | 10+ | C99 with POSIX extensions |
| SQLite 3 | 3.35+ | `libsqlite3` headers and library |
| zlib | 1.2+ | `zlib.h` and `-lz` |
| GNU Make | 4.0+ | or CMake 3.10+ |

On Photon OS both libraries are pre-installed.  On Debian/Ubuntu:

```bash
sudo apt-get install gcc make libsqlite3-dev zlib1g-dev
```

## Build

```bash
cd photonos-package-report/package-report-database-tool
make            # produces ./photon-report-db
make test       # compiles and runs all unit tests
make clean      # removes build artefacts
```

Or with CMake:

```bash
mkdir build && cd build
cmake ..
make
ctest
```

## Usage

```
./photon-report-db --db <path.db> [--import <scans-dir>] [--report <output.docx>]
```

| Flag | Required | Description |
|------|----------|-------------|
| `--db <path>` | yes | SQLite database file (created if absent) |
| `--import <dir>` | at least one | Directory containing `photonos-urlhealth-*.prn` files |
| `--report <path>` | at least one | Output `.docx` report path |
| `--help` | -- | Show usage |

At least one of `--import` or `--report` must be provided.

### Examples

Import all scans and generate the report in one pass:

```bash
./photon-report-db \
    --db photon-scans.db \
    --import ../scans/ \
    --report photon-report.docx
```

Import only (accumulate data across multiple runs):

```bash
./photon-report-db --db photon-scans.db --import ../scans/
```

Generate a report from an existing database:

```bash
./photon-report-db --db photon-scans.db --report photon-report.docx
```

## Report example

Generated from 170 scan files (branches 3.0, 4.0, 5.0, 6.0, common, dev,
master) spanning 2023-02 to 2026-03, producing a 144,292-row database
(42 MB) and a ~1 MB `.docx` (8 OOXML parts including 3 charts).

### Database statistics

```
Scan files: 170
Packages:   144292

  3.0:    41 scans
  4.0:    33 scans
  5.0:    35 scans
  6.0:    20 scans
  common: 20 scans
  dev:    10 scans
  master: 11 scans
```

### Section 1 -- Timeline chart

OOXML line chart with 64 data points across 7 branch series.
Each point counts packages with `UrlHealth = 200`, a versioned
`UpdateAvailable`, and `UpdateDownloadName` matching `name-version.tar.*`.

```
Qualifying packages per branch over time (sampled)

 1100 |                                                      *  *
 1000 |                              *     *  *        *  *
  900 |            *        *     *           *  *  *
  800 |         *     *  *        *
  700 |
  600 |
  500 |
  400 |         *
  300 |
  200 |   *  *  *
  100 |   *
    0 +---*-----*-------*--------*--------*--------*--------*----->
      2023-02  2023-11  2024-03  2024-09  2025-02  2026-02  2026-03

  --- 3.0 (41 scans, 146..893)      --- 4.0 (33 scans, 187..1011)
  --- 5.0 (35 scans, 191..1067)     --- 6.0 (20 scans, 345..1067)
  --- common (20 scans, 0..6)       --- dev (10 scans, 349..1053)
  --- master (11 scans, 349..1053)
```

### Section 2 -- Top 10 most-changed packages (all branches)

| Package | 2023 | 2024 | 2025 | 2026 | Total | Branches |
|---------|-----:|-----:|-----:|-----:|------:|----------|
| linux | 3 | 16 | 6 | 96 | **121** | 3.0,4.0,5.0,6.0,common,dev,master |
| vim | 3 | 23 | 11 | 72 | **109** | 3.0,4.0,5.0,6.0,dev,master |
| openjdk | 0 | 0 | 0 | 95 | **95** | 4.0,5.0,6.0,dev,master |
| python-botocore | 3 | 17 | 13 | 61 | **94** | 3.0,4.0,5.0,6.0,dev,master |
| python-boto3 | 3 | 17 | 13 | 60 | **93** | 3.0,4.0,5.0,6.0,dev,master |
| aws-sdk-cpp | 3 | 16 | 12 | 60 | **91** | 3.0,4.0,5.0,6.0,dev,master |
| nodejs | 3 | 15 | 7 | 64 | **89** | 3.0,4.0,5.0,6.0,dev,master |
| docker | 0 | 18 | 7 | 51 | **76** | 3.0,4.0,5.0,6.0,dev,master |
| rubygem-aws-partitions | 3 | 17 | 11 | 43 | **74** | 3.0,4.0,5.0,6.0,dev,master |
| ansible-community-general | 3 | 17 | 10 | 43 | **73** | 3.0,4.0,5.0,6.0,dev,master |

### Section 3 -- Least-changed packages

Packages present in **all 7 branches** (3.0, 4.0, 5.0, 6.0, common, dev,
master) that changed `UpdateAvailable` the fewest times across all scans.
Excludes VMware-internal and archived packages.

Only 4 packages exist across all 7 branches:

| Package | Branches | Total Changes |
|---------|----------|-----:|
| linux-rt | 3.0,4.0,5.0,6.0,common,dev,master | 29 |
| linux-esx | 3.0,4.0,5.0,6.0,common,dev,master | 36 |
| stalld | 3.0,4.0,5.0,6.0,common,dev,master | 36 |
| linux | 3.0,4.0,5.0,6.0,common,dev,master | 121 |

Note: No package has zero changes across all branches. Most packages only
appear in a subset of branches, which is why the earlier list (before
requiring all 7) was longer.

### Section 4 -- Source category drift

Categories below 3.0% are merged into "Other". "(scan issues)" denotes
entries with bare filenames or unresolved RPM `%{name}` macro templates.

**Pie chart (latest scan per branch):**

| Category | Count | % |
|----------|------:|----:|
| Other | 485 | 30.8 |
| github.com | 426 | 27.0 |
| (scan issues) | 201 | 12.8 |
| pypi | 161 | 10.2 |
| rubygems.org | 126 | 8.0 |
| gnu.org | 64 | 4.1 |
| sourceforge.net | 63 | 4.0 |
| cpan.org | 49 | 3.1 |

**3D bar chart** shows how each category's percentage drifts over time
(x-axis: scan runs grouped by branch, z-axis: percentage). Generated from
1,300 data points across 9 merged categories and 7 branches. The chart
reveals that `github.com`'s share grew from ~18% (2023) to ~27% (2026)
across most branches, while `(scan issues)` decreased as spec files gained
proper Source0 URLs.

### .docx structure

```
$ unzip -l photon-report.docx
  Length      Date    Time    Name
---------  ---------- -----   ----
      936  00-00-1980 00:00   [Content_Types].xml
      299  00-00-1980 00:00   _rels/.rels
     8677  00-00-1980 00:00   word/document.xml
     1022  00-00-1980 00:00   word/styles.xml
      683  00-00-1980 00:00   word/_rels/document.xml.rels
    39274  00-00-1980 00:00   word/charts/chart1.xml   (timeline line chart)
     1616  00-00-1980 00:00   word/charts/chart2.xml   (category pie chart)
   967551  00-00-1980 00:00   word/charts/chart3.xml   (3D category drift)
---------                     -------
  1020058                     8 files
```

### Duplicate handling

Imports are idempotent. If a `.prn` filename already exists in the database
it is silently skipped, so re-running `--import` on the same directory is
safe and fast.

## Tests

```bash
make test
```

Runs two test suites:

| Suite | Tests | Covers |
|-------|-------|--------|
| `test_csv_parser` | 7 | UTF-16LE/UTF-8 conversion, 5/12-col parsing, empty files, XML escaping, filename validation |
| `test_db` | 5 | Schema creation, duplicate detection, package insert, report queries, `.docx` generation |

An integration test script is also provided:

```bash
bash test/run_tests.sh
```

This builds, runs unit tests, then imports the real `../scans/` directory
and verifies the generated `.docx` structure with `unzip -l`.

## Security

The tool is hardened against OWASP / MITRE ATT&CK vectors
(see `specs/adr/0004-security-hardening.md` for details):

- **SQL injection** -- all queries use `sqlite3_bind_*` parameterised statements
- **Path traversal** -- `realpath()` validation; `..` rejected in filenames
- **Buffer overflow** -- `snprintf` only; no `sprintf`/`gets`/`strcpy`
- **Resource exhaustion** -- max 50 MB per file, 10,000 files, 100,000 rows
- **XML injection** -- `secure_xml_escape()` on all user-derived text
- **Compiler hardening** -- `-Wall -Wextra -Werror -fstack-protector-strong
  -D_FORTIFY_SOURCE=2 -pie -fPIE -Wl,-z,relro,-z,now`

## CI / GitHub Actions

The workflow **Photon OS Database Report** (`database-report.yml`) runs on a
self-hosted runner and is triggered manually or on a weekly schedule (Monday
03:00 UTC). It:

1. Installs build dependencies (gcc, sqlite-devel, zlib-devel).
2. Compiles with full hardening flags and runs all unit tests.
3. Imports the latest `.prn` scans from `scans/`.
4. Generates the `.docx` report.
5. Uploads the `.docx` and `.db` as build artefacts (90-day retention).
6. Commits the `.db` and `.docx` back to the `scans/` directory.

## Project structure

```
package-report-database-tool/
├── src/                        C source and headers
│   ├── main.c                  CLI entry point
│   ├── security.c / .h        Input validation, path sanitisation, XML escaping
│   ├── csv_parser.c / .h      CSV/PRN parsing (UTF-16LE + UTF-8, 5/12-col)
│   ├── db.c / .h              SQLite schema, import, report queries
│   ├── chart_xml.c / .h       OOXML DrawingML chart XML generation
│   └── docx_writer.c / .h     .docx ZIP creation + OOXML document assembly
├── test/                       Unit and integration tests
├── specs/                      SDD artefacts (PRD, FRDs, ADRs, tasks)
├── .factory/                   Factory AI droids, hooks, commands
├── .github/                    Changelog and prompt templates
├── Makefile                    GNU Make build
├── CMakeLists.txt              CMake alternative build
├── ARCHITECTURE.md             Technical architecture overview
└── README.md                   This file
```

## Specs-Driven Development (SDD)

This tool was developed using the SDD methodology (inspired by
[SDD-book-tracking-app](https://github.com/sitoader/SDD-book-tracking-app)).
All design decisions are captured as versioned artefacts:

| Artefact | Path |
|----------|------|
| Product Requirements | `specs/prd.md` |
| Feature Requirements | `specs/features/*.md` |
| Architecture Decisions | `specs/adr/0001..0005` |
| Task Tracker | `specs/tasks/README.md` |

## License

Same as the parent repository.
