/* pr_prn.h — .prn report row schema + writer.
 *
 * The .prn file is a comma-separated text file with one header line
 * (lifted verbatim from PS L 5068) followed by N row strings:
 *
 *   Spec,Source0 original,Modified Source0 for url health check,
 *   UrlHealth,UpdateAvailable,UpdateURL,HealthUpdateURL,Name,SHAName,
 *   UpdateDownloadName,warning,ArchivationDate
 *
 * Each row mirrors PS L 4933:
 *
 *   $spec, $source0, $Source0, $urlhealth, $UpdateAvailable, $UpdateURL,
 *   $HealthUpdateURL, $Name, $SHAValue, $UpdateDownloadName, $Warning,
 *   $ArchivationDate
 *
 * Rows are validated against PS L 5070 regex
 *   ^(.*?)([a-zA-Z0-9][a-zA-Z0-9._-]*\.spec.*)$
 * and the regex-stripped, sorted-ascending output is what reaches the
 * .prn file. flock(LOCK_EX) guards each append so parallel runspaces
 * (Phase 7) don't interleave (ADR-0010).
 */
#ifndef PR_PRN_H
#define PR_PRN_H

#include <stddef.h>

/* Exact header bytes, NO trailing newline. The writer appends "\n". */
extern const char PR_PRN_HEADER[];

/* Open `path` for writing (truncate). Writes the header line. Returns
 * a heap-allocated context that subsequent append calls use. NULL on
 * failure. Caller must pr_prn_close(). */
typedef struct pr_prn pr_prn_t;

pr_prn_t *pr_prn_open(const char *path);

/* Append a batch of row strings. Each row is:
 *   - validated against the PS regex (rows without a `<spec>.spec`
 *     anywhere are dropped — matches PS filter at L 5070)
 *   - locale-C-sorted ascending
 *   - appended under flock(LOCK_EX).
 *
 * Returns 0 on success, -1 on I/O error. */
int pr_prn_append_rows(pr_prn_t *ctx, char **rows, size_t n_rows);

/* Flush + close + free. */
int pr_prn_close(pr_prn_t *ctx);

/* Apply PS L 5070 stripping to a row in place. Returns the offset of
 * the kept substring in `row`, or -1 if the row doesn't match. */
const char *pr_prn_strip(const char *row);

#endif /* PR_PRN_H */
