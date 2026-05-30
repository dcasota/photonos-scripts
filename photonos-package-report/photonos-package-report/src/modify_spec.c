/* modify_spec.c — port of ModifySpecFile (PS L 1394-1480).
 *
 * Walks the original spec file's content line-by-line and emits a new
 * file with these substitutions (PS line-by-line mapping in comments):
 *
 *   L 1430  $line -ilike '*Version:*'   → "Version:        <Update>"
 *                                          (openjdk8: "1.8.0.<Update>")
 *   L 1434  $line -ilike '*Release:*'   → "Release:        1%{?dist}"
 *   L 1436  $line -ilike '*Source0:*'   → echo line, then $SHALine, skip
 *                                          the very next input line
 *                                          ($skip=$true)
 *   L 1442  $line -ilike '%changelog*'  → echo line, then changelog entry
 *                                          + "automatic version bump"
 *                                          comment
 *   L 1450  $line -ilike '%define subversion*' → "%define subversion <Update>"
 *   L 1453  $line -ilike '%global commit_id*'  → "%global commit_id <CommitId>"
 *                                          (only fires when CommitId given;
 *                                           netcat.spec call site)
 *   default                              → emit line verbatim
 *
 * Output path: <upstreams_dir>/<photon_dir>/<out_subdir>/<Name>/
 *              <spec-basename>-<Update>.spec
 * (.asc suffix stripped from $Update before composing the filename, per
 * PS L 1472.)
 *
 * The function uses task->content (the lines ParseDirectory already read
 * out of the source spec file). PS re-reads $SpecFile here, but the
 * content is identical to what we already hold; reusing avoids a second
 * disk read and a path-existence race.
 */
#include "pr_modify_spec.h"

#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>

/* PS `-ilike '*X*'` — case-insensitive substring match. */
static int ilike_contains(const char *line, const char *needle)
{
    if (line == NULL || needle == NULL) return 0;
    return strcasestr(line, needle) != NULL;
}

/* PS `-ilike 'X*'` — case-insensitive prefix match. */
static int ilike_prefix(const char *line, const char *prefix)
{
    if (line == NULL || prefix == NULL) return 0;
    return strncasecmp(line, prefix, strlen(prefix)) == 0;
}

/* mkdir -p equivalent. Returns 0 on success or if path already exists. */
static int mkdir_p(const char *path)
{
    if (path == NULL || path[0] == '\0') return -1;
    char *copy = strdup(path);
    if (copy == NULL) return -1;
    int rc = 0;
    for (char *p = copy + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(copy, 0755) != 0 && errno != EEXIST) { rc = -1; break; }
            *p = '/';
        }
    }
    if (rc == 0 && mkdir(copy, 0755) != 0 && errno != EEXIST) rc = -1;
    free(copy);
    return rc;
}

/* PS L 1424: $DateEntry = (en-US "%a") + " " + en-US "MMM" + " " +
 * en-US "%d %Y". e.g. "Sat May 30 2026". setlocale here is safe because
 * the worker pool runs each spec in its own thread but locale changes
 * are process-global — so we use strftime with the C locale and the
 * en-US-equivalent format string; the C locale's %a / %b are byte-
 * identical to en-US's for English-named days/months (Sun..Sat,
 * Jan..Dec). */
static void format_date_entry(char *buf, size_t cap)
{
    time_t now = time(NULL);
    struct tm tm;
    localtime_r(&now, &tm);
    /* "%a %b %d %Y" — matches PS "%a" + " " + "MMM" + " " + "%d %Y". */
    strftime(buf, cap, "%a %b %d %Y", &tm);
}

/* PS L 1431-1432: $line -replace 'Version:.+$', '<replacement>'. The
 * regex tail is anything-after-"Version:" — we just find the colon and
 * truncate to the replacement string. */
static char *replace_after_colon(const char *key, const char *replacement)
{
    char *out = NULL;
    if (asprintf(&out, "%s        %s", key, replacement) < 0) return NULL;
    return out;
}

/* Strip a trailing ".asc" suffix from `s` (case-insensitive). PS L 1473
 * does this before composing the output filename, because some sources
 * deliver an .asc-suffixed update name (signature files) the spec writer
 * shouldn't carry into the new spec filename. */
static char *strip_asc_suffix_dup(const char *s)
{
    if (s == NULL) return strdup("");
    size_t sl = strlen(s);
    if (sl >= 4 && strcasecmp(s + sl - 4, ".asc") == 0) {
        char *out = malloc(sl - 4 + 1);
        if (out == NULL) return NULL;
        memcpy(out, s, sl - 4);
        out[sl - 4] = '\0';
        return out;
    }
    return strdup(s);
}

int pr_modify_spec_file(const pr_task_t *task,
                        const char      *working_dir,
                        const char      *upstreams_dir,
                        const char      *photon_dir,
                        const char      *update_avail,
                        const char      *sha_line,
                        int              openjdk8,
                        const char      *commit_id,
                        const char      *out_subdir)
{
    if (task == NULL || task->Spec == NULL || task->Name == NULL) return -1;
    if (update_avail == NULL || update_avail[0] == '\0') return -1;
    if (working_dir == NULL || working_dir[0] == '\0') return -1;
    if (upstreams_dir == NULL || upstreams_dir[0] == '\0') return -1;
    if (photon_dir == NULL || photon_dir[0] == '\0') return -1;
    if (out_subdir == NULL || out_subdir[0] == '\0') out_subdir = "SPECS_NEW_C";

    /* PS L 1419: $SpecFile = Join(WorkingDir, photonDir, "SPECS", Name,
     *                              SpecFileName). PS uses this only for
     * the file-exists check; we already hold the content, but we keep
     * the test so a missing spec produces the same "skipping" warning. */
    char src_path[1024];
    if (snprintf(src_path, sizeof src_path, "%s/%s/SPECS/%s/%s",
                 working_dir, photon_dir, task->Name, task->Spec) < 0) return -1;
    struct stat st;
    if (stat(src_path, &st) != 0) {
        fprintf(stderr, "::warning::modify_spec: source spec file not found, "
                "skipping: %s\n", src_path);
        return -1;
    }
    if (task->content == NULL || task->content_lines == 0) return -1;

    /* PS L 1425: $line1 = "* <DateEntry> <First> <Last> <<email>> <Update>-1".
     *
     * M125: changelog author + email are pulled from env vars
     * PR_FIRST_NAME / PR_LAST_NAME / PR_EMAIL_ADDRESS (set by the
     * workflow input or the operator's shell). Defaults preserve the
     * legacy hardcoded "First Last <firstname.lastname@broadcom.com>"
     * string when env is unset — byte-identical to the pre-M125 line. */
    const char *first_name = getenv("PR_FIRST_NAME");
    const char *last_name  = getenv("PR_LAST_NAME");
    const char *email_addr = getenv("PR_EMAIL_ADDRESS");
    if (first_name == NULL || first_name[0] == '\0') first_name = "First";
    if (last_name  == NULL || last_name[0]  == '\0') last_name  = "Last";
    if (email_addr == NULL || email_addr[0] == '\0') email_addr = "firstname.lastname@broadcom.com";

    char date_entry[64];
    format_date_entry(date_entry, sizeof date_entry);
    char *line1 = NULL;
    if (asprintf(&line1, "* %s %s %s <%s> %s-1",
                 date_entry, first_name, last_name, email_addr, update_avail) < 0) return -1;

    /* Build the Version: replacement string. PS L 1432 splits on
     * openjdk8: openjdk8 → "1.8.0.<Update>"; default → "<Update>". */
    char version_value[256];
    if (openjdk8) {
        snprintf(version_value, sizeof version_value, "1.8.0.%s", update_avail);
    } else {
        snprintf(version_value, sizeof version_value, "%s", update_avail);
    }

    /* Build the output buffer. Allocate a generous initial capacity. */
    size_t out_cap   = 16 * 1024;
    size_t out_used  = 0;
    char  *out_buf   = malloc(out_cap);
    if (out_buf == NULL) { free(line1); return -2; }

#define EMIT(STR) do {                                                   \
        size_t sl = strlen(STR);                                         \
        while (out_used + sl + 2 > out_cap) {                            \
            size_t ncap = out_cap * 2;                                   \
            char *np = realloc(out_buf, ncap);                           \
            if (np == NULL) { free(out_buf); free(line1); return -2; }   \
            out_buf = np; out_cap = ncap;                                \
        }                                                                \
        memcpy(out_buf + out_used, (STR), sl);                           \
        out_used += sl;                                                  \
        out_buf[out_used++] = '\n';                                      \
    } while (0)

    int skip_next = 0;          /* PS $skip — skip one line after Source0: */

    for (size_t i = 0; i < task->content_lines; i++) {
        const char *line = task->content[i] ? task->content[i] : "";
        if (skip_next) { skip_next = 0; continue; }

        if (ilike_contains(line, "Version:")) {
            char *v = replace_after_colon("Version:", version_value);
            if (v) { EMIT(v); free(v); } else { EMIT(line); }
        } else if (ilike_contains(line, "Release:")) {
            char *r = replace_after_colon("Release:", "1%{?dist}");
            if (r) { EMIT(r); free(r); } else { EMIT(line); }
        } else if (ilike_contains(line, "Source0:")) {
            EMIT(line);
            if (sha_line && sha_line[0]) EMIT(sha_line);
            skip_next = 1;
        } else if (ilike_prefix(line, "%changelog")) {
            EMIT(line);
            EMIT(line1);
            EMIT("- automatic version bump for testing purposes DO NOT USE");
        } else if (ilike_prefix(line, "%define subversion")) {
            char *s = NULL;
            if (asprintf(&s, "%%define subversion %s", update_avail) >= 0 && s) {
                EMIT(s); free(s);
            } else {
                EMIT(line);
            }
        } else if (ilike_prefix(line, "%global commit_id") &&
                   commit_id && commit_id[0]) {
            char *g = NULL;
            if (asprintf(&g, "%%global commit_id %s", commit_id) >= 0 && g) {
                EMIT(g); free(g);
            } else {
                EMIT(line);
            }
        } else {
            EMIT(line);
        }
    }

#undef EMIT
    free(line1);

    /* PS L 1466: $SpecsNewDirectory = Join(UpstreamsDir, photonDir,
     *                                       <out_subdir>, Name). */
    char out_dir[1024];
    if (snprintf(out_dir, sizeof out_dir, "%s/%s/%s/%s",
                 upstreams_dir, photon_dir, out_subdir, task->Name) < 0) {
        free(out_buf); return -2;
    }
    if (mkdir_p(out_dir) != 0) {
        fprintf(stderr, "::warning::modify_spec: mkdir_p failed: %s (%s)\n",
                out_dir, strerror(errno));
        free(out_buf); return -2;
    }

    /* PS L 1471-1475: strip the .spec suffix from the basename, append
     * -<Update> (with .asc stripped), then append .spec. */
    char *base = strdup(task->Spec);
    if (base == NULL) { free(out_buf); return -2; }
    size_t bl = strlen(base);
    if (bl >= 5 && strcasecmp(base + bl - 5, ".spec") == 0) base[bl - 5] = '\0';

    char *upd_clean = strip_asc_suffix_dup(update_avail);
    if (upd_clean == NULL) { free(base); free(out_buf); return -2; }

    char out_path[2048];
    if (snprintf(out_path, sizeof out_path, "%s/%s-%s.spec",
                 out_dir, base, upd_clean) < 0) {
        free(base); free(upd_clean); free(out_buf); return -2;
    }
    free(base); free(upd_clean);

    FILE *fp = fopen(out_path, "w");
    if (fp == NULL) {
        fprintf(stderr, "::warning::modify_spec: fopen failed: %s (%s)\n",
                out_path, strerror(errno));
        free(out_buf); return -2;
    }
    if (out_used > 0 && fwrite(out_buf, 1, out_used, fp) != out_used) {
        fclose(fp); free(out_buf); return -2;
    }
    if (fclose(fp) != 0) { free(out_buf); return -2; }

    free(out_buf);
    return 0;
}
