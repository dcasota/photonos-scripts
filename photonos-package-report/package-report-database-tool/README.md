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
2. **Top 10 most-changed 5.0 packages** (2023--current) with per-year
   breakdown (2023 / 2024 / 2025 / 2026).
3. **Least-changed packages** across all branches (2023--current), excluding
   VMware-internal (`vmware.com`, `broadcom.com` in Source0 or warning) and
   archived packages (non-empty `ArchivationDate`).
4. **Pie chart** categorising packages by source domain (github.com,
   kernel.org, freedesktop.org, gnu.org, rubygems.org, sourceforge.net,
   \*cpan.org, paguire.io, Other) with count and percentage.

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
(42 MB) and a 59 KB `.docx`.

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

### Section 2 -- Top 10 most-changed 5.0 packages

| Package | 2023 | 2024 | 2025 | 2026 | Total |
|---------|-----:|-----:|-----:|-----:|------:|
| linux | 1 | 5 | 2 | 21 | **29** |
| vim | 1 | 7 | 3 | 13 | **24** |
| openjdk | 0 | 0 | 0 | 23 | **23** |
| python-botocore | 1 | 5 | 4 | 11 | **21** |
| runc | 1 | 5 | 1 | 13 | **20** |
| python-boto3 | 1 | 5 | 4 | 10 | **20** |
| chromium | 0 | 7 | 5 | 8 | **20** |
| aws-sdk-cpp | 1 | 5 | 3 | 10 | **19** |
| gawk | 1 | 1 | 2 | 14 | **18** |
| docker-compose | 1 | 5 | 2 | 10 | **18** |

### Section 3 -- Least-changed packages (sample)

Packages that never changed `UpdateAvailable` across any branch, excluding
VMware-internal and archived packages:

```
ant-contrib          (3.0, 4.0, 5.0)
apache-tomcat-9      (6.0, dev, master)
autoconf-2.13        (4.0, 5.0)
calico-cni           (3.0, 4.0, 5.0)
calico-felix         (3.0, 4.0, 5.0)
confd                (3.0, 4.0, 5.0)
eventlog             (3.0, 4.0, 5.0, 6.0)
fakeroot             (5.0, 6.0, dev, master)
filesystem           (3.0, 4.0, 5.0, 6.0, dev, master)
hyper-v              (3.0, 4.0, 5.0, 6.0, dev, master)
```

### Section 4 -- Source category pie chart

| Category | Count | % |
|----------|------:|----:|
| Other | 771 | 49.0 |
| github.com | 426 | 27.0 |
| rubygems.org | 126 | 8.0 |
| gnu.org | 64 | 4.1 |
| sourceforge.net | 63 | 4.0 |
| cpan.org | 49 | 3.1 |
| kernel.org | 47 | 3.0 |
| freedesktop.org | 29 | 1.8 |

### .docx structure

```
$ unzip -l photon-report.docx
  Length      Date    Time    Name
---------  ---------- -----   ----
      810  00-00-1980 00:00   [Content_Types].xml
      299  00-00-1980 00:00   _rels/.rels
    15282  00-00-1980 00:00   word/document.xml
     1022  00-00-1980 00:00   word/styles.xml
      550  00-00-1980 00:00   word/_rels/document.xml.rels
    39274  00-00-1980 00:00   word/charts/chart1.xml
     1618  00-00-1980 00:00   word/charts/chart2.xml
---------                     -------
    58855                     7 files
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
