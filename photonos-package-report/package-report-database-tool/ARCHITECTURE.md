# Architecture -- photon-report-db

## 1. System context

```
 Weekly cron / manual trigger
              |
              v
+---------------------------+       +---------------------+
| package-report.yml        |       | database-report.yml |
| (self-hosted runner)      |       | (self-hosted runner) |
|                           |       |                     |
| photonos-package-report   |       | photon-report-db    |
| .ps1                      |       | (this tool)         |
+---------------------------+       +---------------------+
       |                                  |          |
       v                                  v          v
  scans/*.prn  -----(import)----->  photon-scans.db  report.docx
```

The PowerShell script (`photonos-package-report.ps1`) clones every Photon OS
branch from `vmware/photon`, walks all `.spec` files, performs live URL
health checks, and writes per-branch `.prn` CSV files to `scans/`.

This C tool reads those `.prn` files, loads them into SQLite, and produces a
`.docx` trend report. The two tools run independently -- the C tool never
touches the network or the Photon git repos.

## 2. Component diagram

```
main.c
  |
  +-- db.c -------> SQLite3 (libsqlite3)
  |     |
  |     +-- csv_parser.c       parse .prn files
  |     |     +-- security.c   UTF-16LE->UTF-8, field validation
  |     |
  |     +-- (inline SHA-256)   file integrity hashing
  |
  +-- docx_writer.c --> .docx ZIP file
        |
        +-- chart_xml.c        OOXML DrawingML XML
        +-- security.c         XML escaping
        +-- zlib (deflate)     ZIP compression
```

### Module responsibilities

| Module | LOC | Responsibility |
|--------|-----|----------------|
| `main.c` | 143 | CLI argument parsing, orchestration |
| `security.c` | 138 | `realpath()` validation, filename checks, `secure_xml_escape()`, `secure_strncpy()` |
| `csv_parser.c` | 306 | Encoding detection (UTF-16LE BOM), schema detection (5/12 col), CSV field parsing with quote handling |
| `db.c` | 600 | Schema DDL, dedup (`scan_files.filename UNIQUE`), transactional insert, 4 report queries (timeline, top-changed, least-changed, categories) |
| `chart_xml.c` | 230 | OOXML `<c:lineChart>` and `<c:pieChart>` DrawingML generation with dynamic series |
| `docx_writer.c` | 436 | Minimal ZIP writer (local headers + central directory via raw zlib deflate), OOXML content types, relationships, `<w:document>` with tables and inline chart references |

## 3. Data model

### 3.1 Input: `.prn` files

Two schemas exist in the scan archive:

**5-column (2023)**

```
Spec, Source0 original, Recent Source0 modified, UrlHealth, UpdateAvailable
```

Encoding: UTF-16LE with BOM (FF FE).

**12-column (2025+)**

```
Spec, Source0 original, Modified Source0 for url health check, UrlHealth,
UpdateAvailable, UpdateURL, HealthUpdateURL, Name, SHAName,
UpdateDownloadName, warning, ArchivationDate
```

Encoding: UTF-8 (no BOM or UTF-8 BOM EF BB BF).

Detection: check first two bytes for `FF FE`; count commas in header row
(>=10 = 12-col).

### 3.2 SQLite schema

```sql
scan_files                          packages
+-----------+-------------------+   +--------------------+-------------------+
| id        | INTEGER PK        |   | id                 | INTEGER PK        |
| filename  | TEXT UNIQUE (dedup)|   | scan_file_id       | FK -> scan_files  |
| branch    | TEXT               |<--| spec               | TEXT              |
| scan_dt   | TEXT (YYYYMMDDHHmm)|   | source0_original   | TEXT              |
| file_sha  | TEXT (SHA-256)     |   | modified_source0   | TEXT              |
| schema_v  | INTEGER (5 or 12) |   | url_health         | TEXT              |
| imported  | TEXT (datetime)    |   | update_available   | TEXT              |
+-----------+-------------------+   | update_url         | TEXT              |
                                    | health_update_url  | TEXT              |
                                    | name               | TEXT              |
                                    | sha_name           | TEXT              |
                                    | update_download_name| TEXT             |
                                    | warning            | TEXT              |
                                    | archivation_date   | TEXT              |
                                    +--------------------+-------------------+
```

Indexes: `idx_packages_scan(scan_file_id)`, `idx_packages_name(name)`,
`idx_scan_files_branch(branch)`.

PRAGMAs: `journal_mode=WAL`, `foreign_keys=ON`, `synchronous=NORMAL`.

## 4. Report queries

### Q1 -- Timeline

```sql
SELECT sf.branch, sf.scan_datetime, COUNT(*)
FROM packages p JOIN scan_files sf ON p.scan_file_id = sf.id
WHERE p.url_health = '200'
  AND p.update_available NOT IN ('', '(same version)', 'pinned')
  AND p.update_download_name LIKE '%-%.tar%'
GROUP BY sf.branch, sf.scan_datetime
ORDER BY sf.branch, sf.scan_datetime
```

Rendered as a `<c:lineChart>` with one `<c:ser>` per branch, dashed stroke.

### Q2 -- Top 10 most-changed (branch 5.0)

Uses a window function (`LAG`) to detect when `update_available` changes
between consecutive scans for the same package, grouped by year.

### Q3 -- Least-changed (all branches)

Same `LAG` technique, but across all branches, with `WHERE` filters
excluding VMware-internal URLs, warning text, and non-empty
`archivation_date`.

### Q4 -- Source categories

```sql
CASE
  WHEN url LIKE '%github.com%' THEN 'github.com'
  WHEN url LIKE '%kernel.org%' THEN 'kernel.org'
  ...
  ELSE 'Other'
END
```

Uses the latest scan per branch (`MAX(scan_datetime) GROUP BY branch`),
then counts distinct package names per category.

Rendered as a `<c:pieChart>` with labels showing `category (count, pct%)`.

## 5. .docx generation

The `.docx` file is an OOXML ZIP archive:

```
[Content_Types].xml          MIME type registry
_rels/.rels                  Root relationships (-> word/document.xml)
word/document.xml            Body: headings, tables, inline chart refs
word/styles.xml              Heading1, Heading2, TableGrid definitions
word/_rels/document.xml.rels Chart relationship IDs (rId2, rId3)
word/charts/chart1.xml       Timeline line chart (DrawingML)
word/charts/chart2.xml       Pie chart (DrawingML)
```

ZIP creation uses raw `zlib` deflate (no minizip dependency). Each file is
deflated independently and written with a local file header; a central
directory and EOCD record are appended on close. This minimal writer is
~130 lines and handles only the creation path -- the tool never reads or
extracts ZIP archives.

## 6. Security architecture

See `specs/adr/0004-security-hardening.md` for the full threat model.

```
                     +-- realpath() + prefix check ----+
                     |                                  |
  .prn files ---+--> csv_parser ---> db (bind params) --+--> report queries
                |                                       |
                +-- SHA-256 integrity --+               |
                +-- size limits --------+               |
                                                        |
                                        docx_writer <---+
                                            |
                                    secure_xml_escape()
                                            |
                                        .docx ZIP
```

Key invariants:

- No SQL string concatenation anywhere. Every query uses `sqlite3_prepare_v2`
  + `sqlite3_bind_*`.
- No `sprintf`, `gets`, `strcpy`, `strcat`. Only `snprintf` and
  `secure_strncpy`.
- Every `malloc`/`realloc` result is checked for `NULL`.
- Compiler flags: `-fstack-protector-strong -D_FORTIFY_SOURCE=2 -pie -fPIE
  -Wl,-z,relro,-z,now`.

## 7. Build system

Two parallel build systems:

| System | Entry point | Usage |
|--------|-------------|-------|
| GNU Make | `Makefile` | `make && make test` |
| CMake | `CMakeLists.txt` | `mkdir build && cd build && cmake .. && make && ctest` |

Both produce the same binary `photon-report-db` with identical flags.

## 8. Factory AI integration

The `.factory/` directory provides three custom droids for ongoing
development:

| Droid | Purpose | Tools |
|-------|---------|-------|
| `c-implementer` | Implement C code per task specs | Read, Edit, Create, Execute, Grep, Glob |
| `security-auditor` | Review code for OWASP/MITRE compliance | Read, Grep, Glob, WebSearch |
| `test-runner` | Build + test + valgrind cycle | Read, Execute |

A `PostToolUse` hook (`validate_c_build.py`) runs `gcc -fsyntax-only` after
every `.c`/`.h` edit to catch compilation errors immediately.

## 9. CI pipeline

The `database-report.yml` workflow runs on a self-hosted runner:

```
checkout --> install deps --> make --> make test --> import scans --> report --> upload artefacts --> commit
```

Trigger: `workflow_dispatch` (manual) or `schedule` (weekly Monday 03:00
UTC).
