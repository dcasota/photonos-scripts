/* source0_lookup.c — Source0Lookup port.
 * Mirrors photonos-package-report.ps1 L 508-1369.
 *
 * The PS function is a here-string + `convertfrom-csv`. Here:
 *   - the here-string is `pr_source0_lookup_csv` from the generated
 *     header `source0_lookup_data.h` (built by tools/extract-source0-lookup.sh
 *     + tools/csv-to-c-string.sh at configure time);
 *   - `convertfrom-csv` is implemented by parse_csv() below.
 *
 * CSV semantics target the RFC 4180 subset that PowerShell `ConvertFrom-Csv`
 * accepts, which covers everything in the embedded data:
 *   - field separator ','
 *   - records separated by '\n' (the generator emits \n, never \r\n)
 *   - field optionally enclosed by '"'; embedded '"' represented as ""
 *   - empty fields allowed
 *   - rows may have fewer fields than the header — missing trailing
 *     fields land as "" (matching ConvertFrom-Csv default)
 */
#include "source0_lookup.h"

/* The generated header is placed under the binary tree by CMake. */
#include "source0_lookup_data.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define N_COLUMNS 9

const char *pr_source0_lookup_csv_bytes(void)
{
    return pr_source0_lookup_csv;
}

/* Grow-able string buffer for a single field. */
typedef struct {
    char  *buf;
    size_t len;
    size_t cap;
} fieldbuf_t;

static void fb_init(fieldbuf_t *fb) { fb->buf = NULL; fb->len = 0; fb->cap = 0; }

static int fb_put(fieldbuf_t *fb, char c)
{
    if (fb->len + 1 >= fb->cap) {
        size_t nc = fb->cap == 0 ? 32 : fb->cap * 2;
        char *p = (char *)realloc(fb->buf, nc);
        if (!p) return -1;
        fb->buf = p;
        fb->cap = nc;
    }
    fb->buf[fb->len++] = c;
    return 0;
}

/* Detach the current buffer as a NUL-terminated heap string and reset
 * the fieldbuf for the next field. */
static char *fb_finish(fieldbuf_t *fb)
{
    char *out;
    if (fb->buf == NULL) {
        out = (char *)malloc(1);
        if (!out) return NULL;
        out[0] = '\0';
    } else {
        if (fb_put(fb, '\0') != 0) return NULL;
        out = fb->buf;
    }
    fb->buf = NULL;
    fb->len = 0;
    fb->cap = 0;
    return out;
}

/* Assign field index `idx` of `row` to `value`. */
static void assign_field(pr_source0_lookup_t *row, int idx, char *value)
{
    switch (idx) {
    case 0: row->specfile        = value; break;
    case 1: row->Source0Lookup   = value; break;
    case 2: row->gitSource       = value; break;
    case 3: row->gitBranch       = value; break;
    case 4: row->customRegex     = value; break;
    case 5: row->replaceStrings  = value; break;
    case 6: row->ignoreStrings   = value; break;
    case 7: row->Warning         = value; break;
    case 8: row->ArchivationDate = value; break;
    default: free(value); break;
    }
}

/* malloc("") helper. */
static char *new_empty(void)
{
    char *s = (char *)malloc(1);
    if (s) s[0] = '\0';
    return s;
}

/* Fill any unset fields of `row` with "" (non-NULL). */
static int pad_row(pr_source0_lookup_t *row, int filled)
{
    for (int i = filled; i < N_COLUMNS; i++) {
        char *e = new_empty();
        if (!e) return -1;
        assign_field(row, i, e);
    }
    return 0;
}

/* Append `row` to the table. */
static int table_push(pr_source0_lookup_table_t *t, pr_source0_lookup_t *row,
                       size_t *cap)
{
    if (t->count == *cap) {
        size_t nc = *cap == 0 ? 256 : *cap * 2;
        pr_source0_lookup_t *p = (pr_source0_lookup_t *)realloc(t->rows, nc * sizeof *p);
        if (!p) return -1;
        t->rows = p;
        *cap    = nc;
    }
    t->rows[t->count++] = *row;
    memset(row, 0, sizeof *row);
    return 0;
}

void pr_source0_lookup_free(pr_source0_lookup_table_t *t)
{
    if (t == NULL) return;
    for (size_t i = 0; i < t->count; i++) {
        free(t->rows[i].specfile);
        free(t->rows[i].Source0Lookup);
        free(t->rows[i].gitSource);
        free(t->rows[i].gitBranch);
        free(t->rows[i].customRegex);
        free(t->rows[i].replaceStrings);
        free(t->rows[i].ignoreStrings);
        free(t->rows[i].Warning);
        free(t->rows[i].ArchivationDate);
    }
    free(t->rows);
    t->rows = NULL;
    t->count = 0;
}

int source0_lookup(pr_source0_lookup_table_t *out)
{
    if (out == NULL) return -1;
    out->rows  = NULL;
    out->count = 0;
    size_t cap = 0;

    const char *src = pr_source0_lookup_csv;

    /* Skip the header line (PS ConvertFrom-Csv uses row 1 as the
     * property-name template, which we have baked into the struct). */
    while (*src && *src != '\n') src++;
    if (*src == '\n') src++;

    pr_source0_lookup_t row;
    memset(&row, 0, sizeof row);
    int field_idx = 0;
    int in_quotes = 0;
    fieldbuf_t fb;
    fb_init(&fb);

    while (*src) {
        char c = *src++;

        if (in_quotes) {
            if (c == '"') {
                if (*src == '"') {           /* RFC 4180 escaped quote */
                    fb_put(&fb, '"');
                    src++;
                } else {
                    in_quotes = 0;            /* end quoted field */
                }
            } else {
                fb_put(&fb, c);
            }
            continue;
        }

        /* Outside quotes. */
        if (c == '"' && fb.len == 0) {        /* opening quote */
            in_quotes = 1;
            continue;
        }
        if (c == ',') {
            char *v = fb_finish(&fb);
            if (!v) goto fail;
            if (field_idx < N_COLUMNS) {
                assign_field(&row, field_idx, v);
            } else {
                free(v);                       /* PS ConvertFrom-Csv silently
                                                * drops extra columns */
            }
            field_idx++;
            continue;
        }
        if (c == '\n') {
            char *v = fb_finish(&fb);
            if (!v) goto fail;
            if (field_idx < N_COLUMNS) {
                assign_field(&row, field_idx, v);
            } else {
                free(v);
            }
            field_idx++;
            if (pad_row(&row, field_idx) != 0) goto fail;
            if (table_push(out, &row, &cap) != 0) goto fail;
            field_idx = 0;
            continue;
        }
        if (c == '\r') {
            /* Tolerate CRLF even though generator emits LF. */
            continue;
        }
        fb_put(&fb, c);
    }

    /* Handle a file with no trailing newline. */
    if (fb.len > 0 || field_idx > 0 || in_quotes) {
        char *v = fb_finish(&fb);
        if (!v) goto fail;
        if (field_idx < N_COLUMNS) assign_field(&row, field_idx, v);
        else free(v);
        field_idx++;
        if (pad_row(&row, field_idx) != 0) goto fail;
        if (table_push(out, &row, &cap) != 0) goto fail;
    }

    free(fb.buf);
    return 0;

fail:
    free(fb.buf);
    /* Free anything attached to the partially-built row. */
    free(row.specfile);
    free(row.Source0Lookup);
    free(row.gitSource);
    free(row.gitBranch);
    free(row.customRegex);
    free(row.replaceStrings);
    free(row.ignoreStrings);
    free(row.Warning);
    free(row.ArchivationDate);
    pr_source0_lookup_free(out);
    return -1;
}
