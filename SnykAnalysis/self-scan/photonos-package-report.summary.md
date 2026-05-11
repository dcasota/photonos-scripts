# photonos-package-report self-scan summary

Scan date: 2026-05-11
Branch: snyk-self-scan-20260511

## Counts

| Phase     | Total | Warning | Note |
|-----------|-------|---------|------|
| Baseline  | 11    | 2       | 9    |
| Iter 1    | 10    | 2       | 8    |
| Accepted  | 10    | -       | -    |
| Open      | 0     | -       | -    |

## Per-finding outcomes

| Rule | Location | Outcome |
|------|----------|---------|
| cpp/AllocOfStrlen | docx_writer.c:68 | FALSE-POSITIVE (binary deflate size, not C-string allocation) |
| cpp/BufferOverflow | db.c:38 | FALSE-POSITIVE (msg sized new_len+8 >= len+9, input also bounded by MAX_FILE_SIZE) |
| cpp/DerefNull/test | test_csv_parser.c:104 | HARD-FIX (added null check on fopen before fclose) |
| cpp/ImproperNullTermination | csv_parser.c:86 | FALSE-POSITIVE (fgets output is NUL-terminated) |
| cpp/ImproperNullTermination | csv_parser.c:177 | FALSE-POSITIVE (fgets output is NUL-terminated) |
| cpp/ImproperNullTermination | docx_writer.c:428 | FALSE-POSITIVE (strbuf input is NUL-terminated) |
| cpp/ImproperNullTermination/test | test_csv_parser.c:121 | FALSE-POSITIVE (string literal) |
| cpp/InsecureStorage | db.c:88 | DESIGN-DECISION (tool is by definition a SQLite report db) |
| cpp/PT | main.c:85 | DESIGN-DECISION (CLI --import takes operator-supplied dir) |
| cpp/PT | main.c:150 | DESIGN-DECISION (CLI --report takes operator-supplied path) |
| cpp/WeakGuard/test | test_db.c:149 | FALSE-POSITIVE (assertion on test fixture row, not a guard) |

## Build verification

`make` rebuilds photon-report-db cleanly with `-Werror`.
