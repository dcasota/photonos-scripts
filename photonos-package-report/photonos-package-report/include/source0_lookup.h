/* source0_lookup.h — interface for the embedded $Source0LookupData CSV.
 *
 * Mirrors photonos-package-report.ps1 L 508-1369:
 *
 *     function Source0Lookup {
 *         $Source0LookupData=@'
 *         specfile,Source0Lookup,gitSource,gitBranch,customRegex,
 *         replaceStrings,ignoreStrings,Warning,ArchivationDate
 *         abseil-cpp.spec,https://...
 *         ...
 *         '@
 *         $Source0LookupData = $Source0LookupData | convertfrom-csv
 *         return( $Source0LookupData )
 *     }
 *
 * The CSV body itself is *not* part of this header — it lives in the
 * generated file `build/generated/source0_lookup_data.h`, produced from
 * the upstream PS script at CMake configure time by:
 *
 *     tools/extract-source0-lookup.sh ../photonos-package-report.ps1
 *       | tools/csv-to-c-string.sh
 *
 * Field order matches the PS CSV header exactly.
 */
#ifndef SOURCE0_LOOKUP_H
#define SOURCE0_LOOKUP_H

#include <stddef.h>

typedef struct {
    char *specfile;         /* col 1 */
    char *Source0Lookup;    /* col 2 */
    char *gitSource;        /* col 3 */
    char *gitBranch;        /* col 4 */
    char *customRegex;      /* col 5 */
    char *replaceStrings;   /* col 6 */
    char *ignoreStrings;    /* col 7 */
    char *Warning;          /* col 8 */
    char *ArchivationDate;  /* col 9 */
} pr_source0_lookup_t;

typedef struct {
    pr_source0_lookup_t *rows;
    size_t               count;
} pr_source0_lookup_table_t;

/* PS Source0Lookup function entry point.
 *
 * Parses the embedded CSV (header skipped) into a heap-allocated table.
 * Mirrors the `convertfrom-csv` behaviour: each row becomes one
 * pr_source0_lookup_t whose fields are NUL-terminated heap copies of the
 * CSV cells. Missing trailing columns are filled with "" (non-NULL).
 *
 * Returns 0 on success and writes the table into *out. Caller must
 * free with pr_source0_lookup_free().
 */
int source0_lookup(pr_source0_lookup_table_t *out);

/* Free all heap memory owned by a table returned by source0_lookup(). */
void pr_source0_lookup_free(pr_source0_lookup_table_t *t);

/* Returns the embedded CSV bytes (header + data) exactly as they appear
 * in the PS script. Used by the parity roundtrip test. */
const char *pr_source0_lookup_csv_bytes(void);

#endif /* SOURCE0_LOOKUP_H */
