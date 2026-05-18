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
                        char *latest = pr_get_latest_name(names, n);
                        if (latest && latest[0]) {
                            /* Phase 6e: construct UpdateURL by re-running
                             * the Source0 substitution with version=NameLatest
                             * against the RAW Source0Lookup template (PS L
                             * 4659-4710 normal-path logic, simplified). */
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

                            /* HealthUpdateURL (col 7): urlhealth probe of
                             * the rewritten UpdateURL. Same network gate. */
                            if (state.UpdateURL && state.UpdateURL[0]) {
                                int h = urlhealth(state.UpdateURL);
                                char buf[16];
                                snprintf(buf, sizeof buf, "%d", h);
                                free(state.HealthUpdateURL);
                                state.HealthUpdateURL = strdup(buf);
                            }

                            /* UpdateDownloadName (col 10): PS L 4755-4793
                             * — basename of UpdateURL (with SourceForge
                             * /download → penultimate segment handled
                             * inside pr_basename_from_url), then PS
                             * post-processing (v-strip + name-prefix
                             * for numeric-only basenames). */
                            char *dl_name = pr_basename_from_url(state.UpdateURL);
                            if (dl_name) {
                                dl_name = download_name_post(dl_name,
                                              task->Name ? task->Name : "");
                                free(state.UpdateDownloadName);
                                state.UpdateDownloadName = dl_name;
                            } else {
                                /* Fallback: keep the raw NameLatest if
                                 * we couldn't derive a basename. */
                                free(state.UpdateDownloadName);
                                state.UpdateDownloadName = dup_or_empty(latest);
                            }

                            /* UpdateAvailable (col 5) per PS L 2538-2553:
                             *
                             *   $result = Compare-VersionStrings $Namelatest $version
                             *   if ($result -gt 0) $UpdateAvailable = $NameLatest
                             *   elseif ($result -lt 0) $UpdateAvailable = "Warning: ..."
                             *   else                   $UpdateAvailable = "(same version)"
                             *
                             * The compare in PS uses `$version` (the cut form from
                             * L 2114), NOT $currentTask.version (the uncut "X-Y"
                             * form). Mirror that here — pass state.version, not
                             * task->Version, otherwise tomcat9-style packages
                             * with Release suffix never match "same". */
                            int rc = pr_version_compare(latest,
                                                        state.version ? state.version : "");
                            free(state.UpdateAvailable);
                            if (rc == 1) {
                                state.UpdateAvailable = dup_or_empty(latest);
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
                                /* rc == -2 (parse error): PS Write-Host the
                                 * "comparison failed" diagnostic and leaves
                                 * $UpdateAvailable as its prior empty default. */
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
