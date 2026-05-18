/* check_urlhealth.c — CheckURLHealth orchestrator scaffold (Phase 6a).
 *
 * Mirrors photonos-package-report.ps1 L 1574-4934 in *surface* — the
 * 12-column row layout from PS L 4933 is locked here. Body wires:
 *
 *   - Phase 3a Source0LookupData lookup
 *   - Phase 3b per-spec hook dispatch
 *   - Phase 4 substitution
 *   - Phase 5 urlhealth probe
 *
 * Columns 5-7, 10 are emitted as "" until Phase 6b-6d land. Columns
 * 11-12 (Warning, ArchivationDate) are populated from the Source0Lookup
 * row when one exists (PS L 2145-2153). Column 9 (SHAValue) is stubbed
 * until Phase 6d.
 */
/* _GNU_SOURCE for asprintf is provided via CMake; do not redefine. */
#include "pr_check_urlhealth.h"
#include "pr_clone.h"
#include "pr_git_tags.h"
#include "pr_hook.h"
#include "pr_latest.h"
#include "pr_state.h"
#include "pr_sha.h"
#include "pr_spec_warnings.h"
#include "pr_strutil.h"
#include "pr_substitute.h"
#include "pr_url_util.h"
#include "pr_urlhealth.h"
#include "pr_version.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Look up the Source0Lookup row whose specfile matches task->Spec.
 * Returns NULL if the table is unset or no row matches. */
static const pr_source0_lookup_t *
lookup_row(const pr_source0_lookup_table_t *t, const char *spec)
{
    if (t == NULL || spec == NULL) return NULL;
    for (size_t i = 0; i < t->count; i++) {
        if (strcmp(t->rows[i].specfile, spec) == 0) {
            return &t->rows[i];
        }
    }
    return NULL;
}

/* xstrdup that returns "" on NULL input rather than NULL. */
static char *dup_or_empty(const char *s)
{
    if (s == NULL) s = "";
    size_t n = strlen(s);
    char *p = (char *)malloc(n + 1);
    if (p) memcpy(p, s, n + 1);
    return p;
}

/* PS L 2507-2516: augment the per-name strip list with common
 * Photon-style patterns: `<Name>.`, `<Name>-`, `<Name>_`, `<Name>`,
 * `ver`, `release_`, `release/`, `release-`, `release`, `-final`.
 *
 * Applied after Source0Lookup.replaceStrings (`apply_replace_strings`)
 * and before pr_get_latest_name. Mirrors PS's foreach loop that
 * re-runs each token through every tag name via -replace regex-escape.
 *
 * Helps for tags like `expat-2.7.0` → `2.7.0`, `release-1.5` → `1.5`. */
static void apply_name_replace_augmentations(char **names, size_t n,
                                             const char *task_name)
{
    if (names == NULL) return;
    if (task_name == NULL) task_name = "";

    /* Build the Name-derived tokens dynamically. */
    char *name_dot = NULL, *name_dash = NULL, *name_under = NULL;
    if (task_name[0]) {
        if (asprintf(&name_dot,   "%s.", task_name) < 0) name_dot = NULL;
        if (asprintf(&name_dash,  "%s-", task_name) < 0) name_dash = NULL;
        if (asprintf(&name_under, "%s_", task_name) < 0) name_under = NULL;
    }

    const char *tokens[] = {
        name_dot, name_dash, name_under, task_name,
        "ver", "release_", "release/", "release-", "release", "-final",
        NULL,
    };

    for (int t = 0; tokens[t]; t++) {
        const char *tok = tokens[t];
        if (tok == NULL || *tok == '\0') continue;
        for (size_t i = 0; i < n; i++) {
            if (names[i] == NULL) continue;
            names[i] = istr_replace_all(names[i], tok, "");
        }
    }

    free(name_dot);
    free(name_dash);
    free(name_under);
}

/* PS L 2151 + L 2516-2517: apply Source0Lookup's `replaceStrings`
 * column to each tag name in-place. Splits comma-separated tokens,
 * strips ASCII whitespace, and replaces all occurrences of each token
 * with the empty string in each name.
 *
 * Used to normalise tag names before version comparison, e.g.
 * `llvmorg-22.1.5` → `22.1.5` when replaceStrings contains "llvmorg-".
 *
 * PS's `-replace [regex]::Escape($item), ""` semantically equals a
 * literal-substring strip — no regex metachars survive the Escape().
 *
 * The `names[]` array is owned by the caller (pr_clone_list_tags);
 * we may free + replace individual entries. */
static void apply_replace_strings(char **names, size_t n,
                                  const char *replace_strings)
{
    if (names == NULL || replace_strings == NULL || *replace_strings == '\0') return;

    /* Walk comma-separated tokens. */
    const char *p = replace_strings;
    while (*p) {
        const char *comma = strchr(p, ',');
        const char *end = comma ? comma : p + strlen(p);
        const char *tok_start = p;
        const char *tok_end = end;
        /* Trim ASCII whitespace. */
        while (tok_start < tok_end && (*tok_start == ' ' || *tok_start == '\t')) tok_start++;
        while (tok_end > tok_start && (*(tok_end - 1) == ' ' || *(tok_end - 1) == '\t')) tok_end--;

        size_t tok_len = (size_t)(tok_end - tok_start);
        if (tok_len > 0) {
            char *tok = (char *)malloc(tok_len + 1);
            if (tok) {
                memcpy(tok, tok_start, tok_len);
                tok[tok_len] = '\0';
                /* Strip all occurrences of `tok` from each name. */
                for (size_t i = 0; i < n; i++) {
                    if (names[i] == NULL) continue;
                    names[i] = istr_replace_all(names[i], tok, "");
                }
                free(tok);
            }
        }

        if (!comma) break;
        p = comma + 1;
    }
}

/* PS L 4770: if download name starts with case-insensitive 'v' AND
 * the second char is not '-', strip the leading 'v'.
 * PS L 4782-4783: strip the well-known archive extensions; if the
 * remainder has NO alpha character, prepend "<task.Name>-".
 *
 * Mutates the passed string in place where possible; otherwise returns
 * a newly-allocated replacement. Caller owns the result. */
static char *download_name_post(char *raw, const char *task_name)
{
    if (raw == NULL) return NULL;

    /* L 4770: optional 'v' strip. */
    if ((raw[0] == 'v' || raw[0] == 'V') && raw[1] && raw[1] != '-') {
        memmove(raw, raw + 1, strlen(raw));
    }

    /* L 4782-4783: compute tmpName = basename minus extension. */
    if (task_name && task_name[0]) {
        static const char *exts[] = {
            ".tar.gz", ".tar.xz", ".tar.lz", ".tar.bz2",
            ".tgz",    ".zip",    ".gem",
            NULL,
        };
        size_t rl = strlen(raw);
        size_t tmp_len = rl;
        for (int i = 0; exts[i]; i++) {
            size_t el = strlen(exts[i]);
            if (rl >= el && strncasecmp(raw + rl - el, exts[i], el) == 0) {
                tmp_len = rl - el;
                break;
            }
        }
        /* Does the un-extensioned remainder contain any alpha char? */
        int has_alpha = 0;
        for (size_t i = 0; i < tmp_len; i++) {
            unsigned char c = (unsigned char)raw[i];
            if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) {
                has_alpha = 1; break;
            }
        }
        if (!has_alpha) {
            /* Prepend "<task_name>-". */
            size_t nl = strlen(task_name);
            char *out = (char *)malloc(nl + 1 + rl + 1);
            if (out) {
                memcpy(out, task_name, nl);
                out[nl] = '-';
                memcpy(out + nl + 1, raw, rl + 1);
                free(raw);
                return out;
            }
        }
    }
    return raw;
}

/* PS L 2111-2119: "cut last index in $currentTask.version and save value
 * in $version". Mirror byte-for-byte.
 *
 *   $versionArray = ($currentTask.version).split("-")
 *   if ($versionArray.length -gt 0) {
 *       $version = $versionArray[0]
 *       for ($i=1; $i -lt ($versionArray.length-1); $i++) {
 *           $version = concat($version, "-", $versionArray[$i])
 *       }
 *       if ($versionArray[length-1] -ilike '*.*') {
 *           if (last("." split of last element) -ne "") {
 *               $version = concat($version, "-", that-last-dot-split-element)
 *           }
 *       }
 *   }
 *
 * Equivalent in C: take task_version[0..last_dash) as the prefix; if the
 * last "-"-separated element contains a '.', append "-" + the part after
 * its last '.'. The "loop concat" is implicit because strrchr finds the
 * LAST dash, so the prefix already includes intermediate dashes. */
static char *version_cut(const char *task_version)
{
    if (task_version == NULL || *task_version == '\0') return dup_or_empty("");

    const char *last_dash = strrchr(task_version, '-');
    size_t prefix_len = last_dash ? (size_t)(last_dash - task_version)
                                  : strlen(task_version);

    /* "Last element" is everything after the last '-', or the whole
     * string if there is none (mirroring PS when versionArray.length=1). */
    const char *last_part = last_dash ? last_dash + 1 : task_version;
    const char *last_dot_in_part = strrchr(last_part, '.');

    if (last_dot_in_part && *(last_dot_in_part + 1)) {
        const char *suffix = last_dot_in_part + 1;
        size_t suffix_len = strlen(suffix);
        char *out = (char *)malloc(prefix_len + 1 + suffix_len + 1);
        if (!out) return dup_or_empty("");
        memcpy(out, task_version, prefix_len);
        out[prefix_len] = '-';
        memcpy(out + prefix_len + 1, suffix, suffix_len);
        out[prefix_len + 1 + suffix_len] = '\0';
        return out;
    }

    char *out = (char *)malloc(prefix_len + 1);
    if (!out) return dup_or_empty("");
    memcpy(out, task_version, prefix_len);
    out[prefix_len] = '\0';
    return out;
}

char *check_urlhealth(pr_task_t                       *task,
                      const pr_source0_lookup_table_t *lookup_table,
                      const char                      *clone_root,
                      const char                      *exclusion_list)
{
    if (task == NULL || task->Spec == NULL) return NULL;

    /* PS L 2104-2106: vendor-pinned subrelease short-circuit. When the
     * SPECS/<digits>/<spec>/<spec>.spec path produced a non-empty
     * SubRelease in parse_directory, PS bypasses the full pipeline and
     * emits a fixed-shape "pinned" row:
     *
     *     <Spec>,<Source0 original>,,pinned,,,,<Name>,,,vendor-pinned (subrelease N),
     *
     *   col 3 (Source0 modified) — empty
     *   col 4 UrlHealth          — literal "pinned" (sentinel)
     *   cols 5,6,7               — empty
     *   col 8 Name               — task.Name
     *   cols 9,10                — empty
     *   col 11 warning           — "vendor-pinned (subrelease <N>)"
     *   col 12 ArchivationDate   — empty
     *
     * ADR-0012 Option A: keep PS's sentinel encoding (no schema change).
     */
    if (task->SubRelease && task->SubRelease[0] != '\0') {
        char *out = NULL;
        if (asprintf(&out,
                     "%s,%s,,pinned,,,,%s,,,vendor-pinned (subrelease %s),",
                     task->Spec,
                     task->Source0 ? task->Source0 : "",
                     task->Name    ? task->Name    : "",
                     task->SubRelease) < 0) {
            return NULL;
        }
        (void)lookup_table; (void)clone_root; (void)exclusion_list;
        return out;
    }

    pr_state_t state;
    pr_state_init(&state);

    /* PS L 2140-2153: Source0Lookup CSV lookup. */
    const pr_source0_lookup_t *row = lookup_row(lookup_table, task->Spec);
    if (row && row->Source0Lookup && row->Source0Lookup[0] != '\0') {
        free(state.Source0);
        state.Source0 = dup_or_empty(row->Source0Lookup);
    } else {
        free(state.Source0);
        state.Source0 = dup_or_empty(task->Source0);
    }
    /* PS L 2151-2152: pick up Warning + ArchivationDate from the
     * lookup row when present. (Strings "" otherwise.) */
    if (row) {
        free(state.Warning);
        state.Warning = dup_or_empty(row->Warning);
        free(state.ArchivationDate);
        state.ArchivationDate = dup_or_empty(row->ArchivationDate);
    }

    /* PS L 2111-2119: cut the trailing "-release" off task->Version
     * (with dot-suffix preservation for Photon-style dist tags like
     * "ph5"). See version_cut() above. */
    free(state.version);
    state.version = version_cut(task->Version);

    /* Phase 3b per-spec exception hook. */
    pr_hooks_run(task, &state);

    /* Phase 4 substitution (PS L 2172-2199). */
    pr_source0_substitute(task, &state.Source0, state.version);

    /* PS L 2343-2346: ftp.gnu.org is frequently down. Rewrite to the
     * FUNET mirror which holds an identical archive layout. Applies
     * post-substitution, pre-urlhealth. The rewrite is case-insensitive
     * (`-replace` in PS without `c` flag); `istr_replace_all` matches. */
    if (state.Source0 && strstr(state.Source0, "ftp.gnu.org") != NULL) {
        state.Source0 = istr_replace_all(state.Source0,
                                         "ftp.gnu.org",
                                         "ftp.funet.fi/pub/gnu/ftp.gnu.org");
    }

    /* Phase 5 urlhealth probe. Skipped offline so ctest stays hermetic. */
    int health = 0;
    const char *netenv = getenv("PR_TEST_NETWORK");
    int allow_network = (netenv && strcmp(netenv, "1") == 0);
    if (allow_network) {
        health = urlhealth(state.Source0);
    }

    /* Phase 6d: when the Source0Lookup row has a gitSource AND a
     * clone_root is configured AND the network is allowed, run the
     * clone+fetch+tag chain to populate UpdateDownloadName (col 10)
     * and UpdateAvailable (col 5). */
    if (allow_network && clone_root && clone_root[0] != '\0'
        && row && row->gitSource && row->gitSource[0] != '\0') {

        char *repo_name = pr_extract_repo_name(row->gitSource);
        if (repo_name) {
            /* Mirror PS L 2376-2392 (and L 3665-3679, 4020-4034):
             * skip clone creation when -UpstreamsExclusionList matches
             * $repoName, case-insensitive substring. The downstream
             * "no .git → fall through" path here is equivalent to PS's
             * silent skip of the `git tag -l` block when $SourceClonePath
             * was never created. */
            int skip_clone = pr_should_skip_clone(repo_name, exclusion_list);
            if (skip_clone) {
                fprintf(stderr,
                        "Skipping upstream clone for %s: exclusion-list "
                        "matches repo '%s'\n",
                        task->Spec, repo_name);
            }
            if (!skip_clone && pr_clone_ensure(clone_root,
                                row->gitSource,
                                row->gitBranch,
                                repo_name) == 0) {
                /* List tags. */
                char *clone_path = NULL;
                if (asprintf(&clone_path, "%s/%s", clone_root, repo_name) > 0) {
                    char  **names = NULL;
                    size_t  n     = 0;
                    if (pr_clone_list_tags(clone_path, row->customRegex,
                                           &names, &n) == 0 && n > 0) {
                        /* Apply replaceStrings from Source0Lookup row
                         * (PS L 2151). For clang/llvm specs this
                         * strips the `llvmorg-` prefix off tag names
                         * so version compare sees "22.1.5" not
                         * "llvmorg-22.1.5". */
                        apply_replace_strings(names, n, row->replaceStrings);
                        /* M19 (PS L 2507-2516): augment with Name-based
                         * tokens + common release/ver/-final patterns. */
                        apply_name_replace_augmentations(names, n,
                                                         task->Name ? task->Name : "");
                        char *latest = pr_get_latest_name(names, n);
                        if (latest && latest[0]) {
                            /* PS L 2538-2553: compare first; only the
                             * rc == 1 (newer) branch goes on to build
                             * UpdateURL / probe / download-name / SHA.
                             * rc == 0 ("(same version)") and rc == -1
                             * (warning) leave UpdateURL / HealthUpdateURL
                             * / SHAName / UpdateDownloadName all empty —
                             * see apr-util.spec sample: PS emits only
                             * UpdateAvailable=(same version), nothing else.
                             *
                             * Compare against state.version (cut form
                             * from M08), NOT task->Version. */
                            int rc = pr_version_compare(latest,
                                                        state.version ? state.version : "");
                            free(state.UpdateAvailable);
                            if (rc == 1) {
                                state.UpdateAvailable = dup_or_empty(latest);

                                /* Phase 6e: construct UpdateURL via
                                 * re-substitution with version=NameLatest. */
                                const char *template = (row->Source0Lookup
                                                        && row->Source0Lookup[0])
                                                       ? row->Source0Lookup
                                                       : (task->Source0 ? task->Source0 : "");
                                char *update_url = dup_or_empty(template);
                                if (update_url) {
                                    pr_source0_substitute(task, &update_url, latest);
                                    free(state.UpdateURL);
                                    state.UpdateURL = update_url;
                                }

                                /* HealthUpdateURL (col 7). */
                                int h = 0;
                                if (state.UpdateURL && state.UpdateURL[0]) {
                                    h = urlhealth(state.UpdateURL);
                                    char buf[16];
                                    snprintf(buf, sizeof buf, "%d", h);
                                    free(state.HealthUpdateURL);
                                    state.HealthUpdateURL = strdup(buf);
                                }

                                /* M18 (PS L 4727-4733): HEAD-fail
                                 * detection. PS retries up to 3 URL
                                 * constructions; on the final failure
                                 * it emits the "Manufacturer may
                                 * changed version packaging format"
                                 * warning AND clears UpdateURL +
                                 * HealthUpdateURL. C does the simple
                                 * single-attempt variant — emit the
                                 * warning + clear after one failed
                                 * HEAD. Multi-fallback URL
                                 * construction is a separate task. */
                                if (h != 0 && h != 200) {
                                    free(state.Warning);
                                    state.Warning = dup_or_empty(
                                        "Warning: Manufacturer may changed version packaging format.");
                                    free(state.UpdateURL);
                                    state.UpdateURL = dup_or_empty("");
                                    free(state.HealthUpdateURL);
                                    state.HealthUpdateURL = dup_or_empty("");
                                }

                                /* UpdateDownloadName (col 10) — PS L 4755-4793.
                                 * Skip when M18 cleared UpdateURL. */
                                if (state.UpdateURL && state.UpdateURL[0]) {
                                    char *dl_name = pr_basename_from_url(state.UpdateURL);
                                    if (dl_name) {
                                        dl_name = download_name_post(dl_name,
                                                      task->Name ? task->Name : "");
                                        free(state.UpdateDownloadName);
                                        state.UpdateDownloadName = dl_name;
                                    } else {
                                        free(state.UpdateDownloadName);
                                        state.UpdateDownloadName = dup_or_empty(latest);
                                    }
                                }
                            } else if (rc == 0) {
                                state.UpdateAvailable = dup_or_empty("(same version)");
                            } else if (rc == -1) {
                                /* PS warning text — note the lone-space before
                                 * the trailing period; must match byte-for-byte. */
                                char *warn = NULL;
                                if (asprintf(&warn,
                                             "Warning: %s Source0 version %s is higher than detected latest version %s .",
                                             task->Spec ? task->Spec : "",
                                             state.version ? state.version : "",
                                             latest) < 0) {
                                    warn = NULL;
                                }
                                state.UpdateAvailable = warn ? warn : dup_or_empty("");
                            } else {
                                /* rc == -2 (parse error). PS leaves
                                 * UpdateAvailable empty; mirror. */
                                state.UpdateAvailable = dup_or_empty("");
                            }

                            /* Phase 6f col 9 SHAValue (PS L 4912-4921):
                             * download UpdateURL, hash with the algorithm
                             * the spec file currently uses. Default
                             * SHA512 when no sha define is present.
                             * Hidden behind PR_TEST_NETWORK gate. */
                            if (state.UpdateURL && state.UpdateURL[0]) {
                                pr_sha_alg_t alg = PR_SHA512;
                                /* Inspect task->content for sha1/256/512
                                 * defines. PS L 4917-4919 form. */
                                for (size_t li = 0; li < task->content_lines; li++) {
                                    const char *line = task->content[li];
                                    if (line == NULL) continue;
                                    if (strstr(line, "%define sha1")   != NULL) { alg = PR_SHA1;   break; }
                                    if (strstr(line, "%define sha256") != NULL) { alg = PR_SHA256; break; }
                                    if (strstr(line, "%define sha512") != NULL) { alg = PR_SHA512; break; }
                                }
                                char *hex = pr_sha_of_url(alg, state.UpdateURL);
                                if (hex) {
                                    free(state.SHAValue);
                                    state.SHAValue = hex;
                                }
                            }
                        }
                        free(latest);
                    }
                    pr_git_tags_free(names, n);
                    free(clone_path);
                }
            }
            free(repo_name);
        }
    }

    /* PS L 4442-4520: per-spec warning table. Overrides any warning
     * set earlier from Source0Lookup row->Warning. PS "last match wins"
     * across the 6 chains. */
    {
        const char *w = pr_spec_warning(task->Spec, state.UpdateAvailable);
        if (w) {
            free(state.Warning);
            state.Warning = dup_or_empty(w);
        }
    }

    /* PS L 4527: if no update was detected AND the original urlhealth
     * probe didn't succeed, blank out Source0. Signals "we tried but
     * couldn't verify upstream — don't expose a dead URL in the report".
     *
     *   if (($UpdateAvailable -eq "") -and ($urlhealth -ne "200")) {$Source0=""}
     */
    if ((state.UpdateAvailable == NULL || state.UpdateAvailable[0] == '\0')
        && health != 200) {
        free(state.Source0);
        state.Source0 = dup_or_empty("");
    }

    /* PS L 4933: assemble the 12-column row.
     *
     *   $currentTask.spec , $currentTask.source0 , $Source0 ,
     *   $urlhealth , $UpdateAvailable , $UpdateURL , $HealthUpdateURL ,
     *   $currentTask.Name , $SHAValue , $UpdateDownloadName , $Warning ,
     *   $ArchivationDate
     */
    char *out = NULL;
    if (asprintf(&out,
                 "%s,%s,%s,%d,%s,%s,%s,%s,%s,%s,%s,%s",
                 task->Spec,                                      /*  1 Spec */
                 task->Source0 ? task->Source0 : "",              /*  2 Source0 original */
                 state.Source0,                                   /*  3 Source0 (rewritten) */
                 health,                                          /*  4 UrlHealth (0 offline) */
                 state.UpdateAvailable,                           /*  5 — Phase 6b */
                 state.UpdateURL,                                 /*  6 — Phase 6c */
                 state.HealthUpdateURL,                           /*  7 — Phase 6c */
                 task->Name,                                      /*  8 Name */
                 state.SHAValue,                                  /*  9 — Phase 6d */
                 state.UpdateDownloadName,                        /* 10 — Phase 6c */
                 state.Warning,                                   /* 11 from lookup row */
                 state.ArchivationDate                            /* 12 from lookup row */
                 ) < 0) {
        out = NULL;
    }

    pr_state_free(&state);
    return out;
}
