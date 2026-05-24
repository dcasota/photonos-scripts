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
#include "pr_atom_feed.h"
#include "pr_clone.h"
#include "pr_git_tags.h"
#include "pr_github_tags.h"
#include "pr_hook.h"
#include "pr_latest.h"
#include "pr_netcat.h"
#include "pr_per_spec.h"
#include "pr_rubygems.h"
#include "pr_state.h"
#include "pr_sha.h"
#include "pr_scraper.h"
#include "pr_gnome_cache.h"
#include "pr_pypi.h"
#include "pr_sourceforge.h"
#include "pr_spec_warnings.h"
#include "pr_stable_source.h"
#include "pr_strutil.h"
#include "pr_substitute.h"
#include "pr_url_util.h"
#include "pr_urlhealth.h"
#include "pr_version.h"

#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>
#include <pthread.h>
#include <strings.h>
#include <fnmatch.h>

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

/* PS L 2395-2397: ftp.gnu.org is frequently down; rewrite to the FUNET
 * mirror (identical archive layout, very stable). PS applies this once
 * to $Source0 before update detection, so every URL later derived from
 * it (the probe Source0 AND the constructed UpdateURL) inherits the
 * mirror. istr_replace_all is a no-op when the needle is absent and
 * frees its input on rewrite, so reassignment is always safe. */
static char *funet_mirror(char *url)
{
    return istr_replace_all(url, "ftp.gnu.org",
                            "ftp.funet.fi/pub/gnu/ftp.gnu.org");
}

/* M46 / PS L 525: apparmor's launchpad URL embeds a release-series dir
 * (.../apparmor/<major.minor>/<version>/...). Its Source0 hardcodes the
 * OLD series (3.1), so re-substituting a newer version 404s; PS instead
 * uses the listing href, which carries the NEW series. Rewrite the
 * series segment to major.minor of `latest`. Robust to the literal
 * series value (replaces whatever segment follows "/apparmor/"). */
static char *apparmor_series_fixup(char *url, const char *latest)
{
    if (url == NULL || latest == NULL) return url;
    const char *d1 = strchr(latest, '.');
    if (!d1) return url;
    const char *d2 = strchr(d1 + 1, '.');
    size_t mmlen = d2 ? (size_t)(d2 - latest) : strlen(latest);  /* "4.1" */
    char *p = strstr(url, "/apparmor/");
    if (!p) return url;
    p += strlen("/apparmor/");
    char *slash = strchr(p, '/');
    if (!slash) return url;
    char *out = NULL;
    if (asprintf(&out, "%.*s%.*s%s",
                 (int)(p - url), url, (int)mmlen, latest, slash) < 0)
        return url;
    free(url);
    return out;
}

static int spec_eq(const char *spec, const char *name)
{
    return spec != NULL && strcasecmp(spec, name) == 0;
}

/* Tarball-cache path for col9 (ADR-0009 amendment 2026-05-21; M64 shared
 * cache). When PR_SHA_CACHE=1, returns a malloc'd cache path so PS and C
 * hash byte-identical tarballs (col9 stops drifting on regenerated github/
 * gitlab auto-archives).
 *
 * Path resolution:
 *   - PR_SHA_CACHE_BASE set  → <BASE>/photon-<branch>/SOURCES_NEW/<name>,
 *     where photon-<branch> is the leaf of clone_root minus "/clones".
 *     This points C at the PS run's *own* SOURCES_NEW (a persistent dir on
 *     the shared self-hosted runner, written by the PS job that produced
 *     the snapshot). C reuses PS's bytes when the file already exists →
 *     identical SHA. Clones stay in C's own cache (no full-vs-partial
 *     clone conflict). This is the TODO-1 shared cache.
 *   - otherwise              → legacy <upstreams>/<branch>/SOURCES_NEW/<name>
 *     derived from clone_root (C-local cache; stable across C runs only).
 * Returns NULL (→ legacy /tmp download) when caching is off or inputs missing. */
static char *col9_cache_path(const char *clone_root, const char *download_name)
{
    if (getenv("PR_SHA_CACHE") == NULL) return NULL;
    if (clone_root == NULL || clone_root[0] == '\0') return NULL;
    if (download_name == NULL || download_name[0] == '\0') return NULL;
    const char *suffix = "/clones";
    size_t cl = strlen(clone_root), sl = strlen(suffix);
    if (cl < sl || strcmp(clone_root + cl - sl, suffix) != 0) return NULL;
    char *cache = NULL;
    const char *base = getenv("PR_SHA_CACHE_BASE");
    if (base && base[0]) {
        /* leaf of ".../photon-<branch>" (clone_root with "/clones" removed) */
        const char *parent_end = clone_root + (cl - sl);
        const char *leaf = parent_end;
        while (leaf > clone_root && *(leaf - 1) != '/') leaf--;
        if (asprintf(&cache, "%s/%.*s/SOURCES_NEW/%s",
                     base, (int)(parent_end - leaf), leaf, download_name) < 0)
            cache = NULL;
    } else if (asprintf(&cache, "%.*s/SOURCES_NEW/%s",
                        (int)(cl - sl), clone_root, download_name) < 0) {
        cache = NULL;
    }
    return cache;
}

/* M35/M40: sourceforge specs whose PS quirks are NOT yet ported. libusb
 * needs a two-stage fetch (PS L 3503-3522) — still deferred. unzip/zip
 * are handled via munge_sf_version (M40). */
static int sourceforge_deferred(const char *spec)
{
    /* M40 deferred libusb (its files page needs a two-stage series→release
     * scrape); M63 implements that, so nothing is deferred now. Kept as the
     * hook for any future SourceForge spec that needs deferral. */
    (void)spec;
    return 0;
}

/* M40 / PS L 3487,3493: the infozip unzip/zip SourceForge listings name
 * their version directories without a dot (unzip60, zip30). PS munges
 * the spec version to the same dot-less form before comparing, so it
 * reads "(same version)" instead of "60 > 6.0 = update". */
static const char *munge_sf_version(const char *spec, const char *version)
{
    if (version == NULL) return version;
    if (spec_eq(spec, "unzip.spec") && strcmp(version, "6.0") == 0) return "60";
    if (spec_eq(spec, "zip.spec")   && strcmp(version, "3.0") == 0) return "30";
    return version;
}

/* M35 / PS L 3525-3529: tboot's sourceforge listing carries old
 * year-stamped directories (2007-2011); drop them before version sort. */
static void drop_year_names(char **names, size_t n)
{
    static const char *const years[] = {
        "2007", "2008", "2009", "2010", "2011", NULL,
    };
    for (size_t i = 0; i < n; i++) {
        if (names[i] == NULL) continue;
        for (int y = 0; years[y]; y++) {
            if (strstr(names[i], years[y]) != NULL) {
                free(names[i]); names[i] = NULL; break;
            }
        }
    }
}

/* M39 / PS L 3691-3695: the samba-family atom feeds return tags named
 * "<lib>-<ver>" (ldb-2.9.2, talloc-2.4.2, ...); strip the per-spec
 * prefix token so the version pipeline isolates the number. */
static void apply_samba_tokens(const char *spec, char **names, size_t n)
{
    const char *tok = NULL;
    if      (spec_eq(spec, "libldb.spec"))       tok = "ldb-";
    else if (spec_eq(spec, "libtalloc.spec"))    tok = "talloc-";
    else if (spec_eq(spec, "libtdb.spec"))       tok = "tdb-";
    else if (spec_eq(spec, "libtevent.spec"))    tok = "tevent-";
    else if (spec_eq(spec, "samba-client.spec")) tok = "samba-";
    if (tok == NULL) return;
    for (size_t i = 0; i < n; i++) {
        if (names[i] == NULL) continue;
        names[i] = istr_replace_all(names[i], tok, "");
    }
}

/* M47 / PS L 4210-4219: the linux kernel family pins to a per-branch
 * stable series (PS hardcodes the series string by output branch). The
 * v6.x listing carries the latest mainline (6.19.x); without this filter
 * C reports that instead of the tracked 6.1 LTS the spec actually
 * updates within. Returns the series substring ("6.1.", "4.19.", ...)
 * for the branch encoded in clone_root (.../photon-<branch>/clones), or
 * NULL for non-family specs / unknown branch. */
static const char *linux_kernel_series(const char *spec, const char *clone_root)
{
    static const char *const fam[] = {
        "linux.spec", "linux-aws.spec", "linux-esx.spec", "linux-rt.spec",
        "linux-secure.spec", "linux-api-headers.spec", NULL,
    };
    int is_fam = 0;
    for (int i = 0; fam[i]; i++) if (spec_eq(spec, fam[i])) { is_fam = 1; break; }
    if (!is_fam || clone_root == NULL) return NULL;
    const char *p = strstr(clone_root, "photon-");
    if (p == NULL) return NULL;
    p += 7;  /* past "photon-" */
    if (strncmp(p, "3.0", 3) == 0)    return "4.19.";
    if (strncmp(p, "4.0", 3) == 0)    return "5.10.";
    if (strncmp(p, "common", 6) == 0) return "6.12.";
    return "6.1.";  /* 5.0 / 6.0 / master / dev */
}

/* M42 / PS L 3335-3350: generic-scrape specs whose upstream tarball
 * basename drops the spec-name suffix (freetype2 ships "freetype-X",
 * grub2 ships "grub-X", ...), so the generic Name-token strip
 * ("freetype2-") misses and the no-alpha filter drops every candidate.
 * Strip the per-spec prefix token so the version is isolated. The two-
 * stage mozilla/python tokens (NameLatest-dependent) are NOT here. */
static void apply_generic_scrape_tokens(const char *spec, char **names, size_t n)
{
    const char *tok = NULL;
    if      (spec_eq(spec, "compat-gdbm.spec"))       tok = "gdbm-";
    else if (spec_eq(spec, "grub2.spec"))             tok = "grub-";
    else if (spec_eq(spec, "freetype2.spec"))         tok = "freetype-";
    else if (spec_eq(spec, "proto.spec"))             tok = "xproto-";
    else if (spec_eq(spec, "xorg-applications.spec")) tok = "bdftopcf-";
    else if (spec_eq(spec, "xorg-fonts.spec"))        tok = "encodings-";
    /* M45 / PS L 4404: lsscsi's listing has a bogus dot-less "lsscsi-030"
     * entry that parses as 30 (> the real 0.32) and wins the sort. PS
     * strips it; here (post Name-strip) the entry is "030", so stripping
     * "030" drops it and leaves the real 0.3x versions. */
    else if (spec_eq(spec, "lsscsi.spec"))            tok = "030";
    /* M47b / PS L 4031 ($replace += "linux-"): kernel-family specs in
     * their OWN dir (Name != "linux") don't get "linux-" stripped by the
     * Name-token step, so "linux-6.1.173" keeps the prefix and the
     * no-alpha filter drops it. (linux/linux-esx/linux-rt share
     * SPECS/linux/ -> Name="linux" -> already stripped.) */
    else if (spec_eq(spec, "linux-api-headers.spec")) tok = "linux-";
    else if (spec_eq(spec, "linux-secure.spec"))      tok = "linux-";
    else if (spec_eq(spec, "linux-aws.spec"))         tok = "linux-";
    /* M50 / PS L 4405: ltrace tarball is "ltrace_<ver>.orig.tar.bz2";
     * after the Name-strip the candidate is "<ver>.orig" and the no-alpha
     * filter would drop it on "orig". Strip ".orig". */
    else if (spec_eq(spec, "ltrace.spec"))            tok = ".orig";
    if (tok == NULL) return;
    for (size_t i = 0; i < n; i++) {
        if (names[i] == NULL) continue;
        names[i] = istr_replace_all(names[i], tok, "");
    }
}

/* M43 / PS L 3206-3272: clean mozilla releases-index dir names. The
 * scrape returns hrefs like "v4.39/", "NSS_3_124_RTM/", "151.0.1/".
 * Strip the trailing slash; for nss strip the NSS_ prefix + _RTM suffix
 * (apply_clean_version_names' _->. then yields "3.124"). The leading-v
 * strip (nspr) is handled by apply_clean_version_names. */
static void apply_mozilla_transform(const char *spec, char **names, size_t n)
{
    int is_nss = spec_eq(spec, "nss.spec");
    for (size_t i = 0; i < n; i++) {
        if (names[i] == NULL) continue;
        /* pr_scrape_listing returns full-path hrefs like
         * "/pub/nspr/releases/v4.39/" — strip trailing slash(es) then
         * reduce to the last path segment so the pipeline sees "v4.39". */
        size_t l = strlen(names[i]);
        while (l > 0 && names[i][l - 1] == '/') names[i][--l] = '\0';
        char *slash = strrchr(names[i], '/');
        if (slash) memmove(names[i], slash + 1, strlen(slash + 1) + 1);
        if (is_nss) {
            names[i] = istr_replace_all(names[i], "NSS_", "");
            names[i] = istr_replace_all(names[i], "_RTM", "");
        }
    }
}

/* M54 / PS L 4331-4341: the generic HTML scraper keeps each `<a href>`
 * verbatim. PowerShell Core's `.Links.href` is likewise the raw attribute,
 * but PS's downstream version extraction is regex-based and tolerates a
 * path prefix, so PS detects the version inside e.g. "download/curl-8.20.0
 * .tar.xz". C's name pipeline strips the Name then drops anything with
 * residual alpha (M21), so a root-relative or absolute href
 * ("download/curl-8.20.0.tar.xz", "https://host/x/curl-8.20.0.tar.xz")
 * leaves a "download/"/"host/x/" prefix that gets dropped → empty col5.
 * Reduce every href to its last path segment (matching the nspr/ao paths)
 * so the pipeline always sees a basename. No-op on bare basenames, so it
 * only fixes the relative/absolute-href listings (e.g. curl.se, which now
 * 301s from curl.haxx.se and serves root-relative hrefs). */
static void apply_href_basename(char **names, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        if (names[i] == NULL) continue;
        size_t l = strlen(names[i]);
        while (l > 0 && names[i][l - 1] == '/') names[i][--l] = '\0';
        char *slash = strrchr(names[i], '/');
        if (slash) memmove(names[i], slash + 1, strlen(slash + 1) + 1);
    }
}

/* M55 / PS L 4406-4413: tzdata listing filter. After basename + ext-strip
 * the data.iana.org listing yields "tzdata2026b", "tzcode2026b",
 * "tzdb-2026b", "tzdata2026b.asc", … . PS keeps only the tzdata files and
 * drops signatures / .tar.Z, and adds "beta" to the strip set. Run before
 * the Name-strip. */
static void apply_tzdata_filter(char **names, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        if (names[i] == NULL) continue;
        if (strstr(names[i], "tzdata") == NULL
            || strcasestr(names[i], ".tar.z") != NULL
            || strstr(names[i], ".asc")  != NULL
            || strstr(names[i], ".sign") != NULL) {
            free(names[i]); names[i] = NULL;
        } else {
            names[i] = str_replace_all(names[i], "beta", "");
        }
    }
}

/* M55 / PS L 4449-4460: tzdata's NameLatest is the maximum by (year, letter)
 * — year = the digit run (2-digit normalised to 19xx), letter = a trailing
 * [a-z]. So "2026b" > "2026a" > "2025z". The generic Get-LatestName /
 * version-compare can't order the YYYY<letter> scheme, hence this dedicated
 * sort (PS special-cases tzdata exactly here). Returns a malloc'd copy to
 * match pr_get_latest_name's contract. */
static char *tzdata_latest(char **names, size_t n)
{
    const char *best = NULL;
    long best_year = -1;
    char best_letter = 0;
    for (size_t i = 0; i < n; i++) {
        if (names[i] == NULL || names[i][0] == '\0') continue;
        char yb[32]; size_t y = 0;
        for (const char *p = names[i]; *p && y < sizeof yb - 1; p++)
            if (*p >= '0' && *p <= '9') yb[y++] = *p;
        yb[y] = '\0';
        if (y == 0) continue;
        long year = atol(yb);
        if (y == 2) year = 1900 + year;   /* PS: 2-digit → 19xx */
        size_t L = strlen(names[i]);
        char last = names[i][L - 1];
        char letter = (last >= 'a' && last <= 'z') ? last : 0;
        if (year > best_year || (year == best_year && letter > best_letter)) {
            best_year = year; best_letter = letter; best = names[i];
        }
    }
    return dup_or_empty(best);   /* "" when no candidate → caller treats as none */
}

/* M63 / PS L 3513-3527: libusb sourceforge stage-1 series pick. The
 * project files page lists series dirs ("libusb-1.0", "libusb-compat-0.1"),
 * not releases. Strip the "libusb-compat-"/"libusb-" prefix, keep names that
 * have a digit and no alphabetic remainder, and return the highest by
 * version compare (e.g. "1.0"). Caller frees. NULL if none qualify. */
static char *libusb_latest_series(char **names, size_t n)
{
    char *best = NULL;
    for (size_t i = 0; i < n; i++) {
        if (names[i] == NULL) continue;
        const char *p = names[i];
        if (strncmp(p, "libusb-compat-", 14) == 0) p += 14;
        else if (strncmp(p, "libusb-", 7) == 0)    p += 7;
        if (*p == '\0') continue;
        int has_digit = 0, has_alpha = 0;
        for (const char *q = p; *q; q++) {
            if (*q >= '0' && *q <= '9') has_digit = 1;
            else if ((*q >= 'a' && *q <= 'z') || (*q >= 'A' && *q <= 'Z')) has_alpha = 1;
        }
        if (!has_digit || has_alpha) continue;
        if (best == NULL || pr_version_compare(p, best) == 1) {
            free(best);
            best = strdup(p);
        }
    }
    return best;
}

/* M37: a spec's Source0 points at a CPAN author directory. PS L 3933
 * gates the CPAN branch on the host alone, independent of Source0
 * health. The three forms PS recognises (L 3933). */
static int cpan_eligible_source0(const char *source0)
{
    return source0 != NULL
        && (strstr(source0, "cpan.metacpan.org/authors")     != NULL
            || strstr(source0, "search.cpan.org/CPAN/authors") != NULL
            || strstr(source0, "cpan.org/authors")           != NULL);
}

/* M37 / PS L 3955-3958: CPAN author-dir listings hold tarballs named
 * "<Module>-<ver>.tar.gz" with NO "perl-" prefix, so the generic
 * Name-token strip (which uses the full "perl-<Module>") never fires.
 * Add the prefix-stripped strip tokens "<Module>-" then "<Module>-perl-"
 * (PS array order). No-op for non perl-* specs. */
static void apply_cpan_perl_tokens(char **names, size_t n, const char *task_name)
{
    if (names == NULL || task_name == NULL) return;
    if (strncasecmp(task_name, "perl-", 5) != 0) return;
    const char *bare = task_name + 5;
    if (bare[0] == '\0') return;
    char *tok_dash = NULL, *tok_perl = NULL;
    if (asprintf(&tok_dash, "%s-",      bare) < 0) tok_dash = NULL;
    if (asprintf(&tok_perl, "%s-perl-", bare) < 0) tok_perl = NULL;
    for (size_t i = 0; i < n; i++) {
        if (names[i] == NULL) continue;
        if (tok_dash) names[i] = istr_replace_all(names[i], tok_dash, "");
        if (tok_perl) names[i] = istr_replace_all(names[i], tok_perl, "");
    }
    free(tok_dash);
    free(tok_perl);
}

/* PS L 2520-2525: post-strip name filter pipeline for non-amdvlk.
 *
 *   $Names = $Names -replace "v",""                       # all 'v' → ''
 *   $Names = where { $_ -match '\d' }                      # keep has-digit
 *   $Names = where {
 *       !(($_ -replace '[pP]\d+', '') -match '[a-zA-Z]')   # no alpha after stripping pN
 *   }
 *
 * Mutates names[] in place. Entries that don't survive are freed and
 * set to NULL (caller must skip NULL).
 *
 * The amdvlk.spec exception isn't ported here — that spec has its
 * own hook path. Callers can skip this function for amdvlk-style
 * cases if needed. */
static int has_any_digit(const char *s)
{
    if (s == NULL) return 0;
    for (const char *p = s; *p; p++) {
        if (*p >= '0' && *p <= '9') return 1;
    }
    return 0;
}

static int has_any_alpha_after_pN_strip(const char *s)
{
    if (s == NULL) return 0;
    /* Strip [pP]\d+ patterns: any 'p' or 'P' immediately followed by
     * one or more digits. Then check if remainder has alpha. */
    size_t n = strlen(s);
    char *tmp = (char *)malloc(n + 1);
    if (!tmp) return 0;
    size_t k = 0;
    for (size_t i = 0; i < n; ) {
        if ((s[i] == 'p' || s[i] == 'P') && i + 1 < n
            && s[i+1] >= '0' && s[i+1] <= '9') {
            /* Skip p/P + run of digits. */
            i++;
            while (i < n && s[i] >= '0' && s[i] <= '9') i++;
        } else {
            tmp[k++] = s[i];
            i++;
        }
    }
    tmp[k] = '\0';
    int has_alpha = 0;
    for (size_t i = 0; i < k; i++) {
        unsigned char c = (unsigned char)tmp[i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) {
            has_alpha = 1; break;
        }
    }
    free(tmp);
    return has_alpha;
}

static void apply_name_post_filters(char **names, size_t n)
{
    if (names == NULL) return;
    for (size_t i = 0; i < n; i++) {
        if (names[i] == NULL) continue;
        /* L 2522: replace all 'v' with '' (case-sensitive lowercase). */
        names[i] = istr_replace_all(names[i], "v", "");
        /* L 2523: keep only has-digit. */
        if (!has_any_digit(names[i])) {
            free(names[i]); names[i] = NULL; continue;
        }
        /* L 2524: keep only if no alpha after [pP]\d+ strip. */
        if (has_any_alpha_after_pN_strip(names[i])) {
            free(names[i]); names[i] = NULL; continue;
        }
    }
}

/* M22 — PS L 441-451 Clean-VersionNames.
 *
 *   $Names = ((($_ -ireplace '^rel/','') -ireplace '^v','') -ireplace '^r','') -replace '_','.'
 *   $preReleasePattern = 'candidate|-alpha|-beta|\.beta|rc\.[0-4]|rc[1-4]|-preview\.|-dev\.|-pre1|\.pre1'
 *   $Names = $Names | Where-Object { $_ -notmatch $preReleasePattern }
 *
 * The three -ireplace ops are anchored (`^`) so they fire at most once
 * each, in order. -notmatch is case-INsensitive (PCRE2_CASELESS).
 *
 * Pipeline placement: between apply_name_replace_augmentations (M19) and
 * apply_name_post_filters (M21). M22 sees the raw candidate set after
 * Source0Lookup.replaceStrings and the Name-token augmentations; it
 * normalises prefixes and removes pre-release tags before M21's
 * lowercase-v strip / has-digit / no-alpha-after-pN gauntlet runs.
 *
 * Mutates names[] in place. Dropped entries are freed and set to NULL. */
static pcre2_code     *RE_PRE_RELEASE;
static pthread_once_t  g_pre_release_once = PTHREAD_ONCE_INIT;

static void init_re_pre_release(void)
{
    int        err_code = 0;
    PCRE2_SIZE err_off  = 0;
    RE_PRE_RELEASE = pcre2_compile(
        (PCRE2_SPTR)"candidate|-alpha|-beta|\\.beta|rc\\.[0-4]|rc[1-4]|-preview\\.|-dev\\.|-pre1|\\.pre1",
        PCRE2_ZERO_TERMINATED, PCRE2_CASELESS, &err_code, &err_off, NULL);
    if (!RE_PRE_RELEASE) {
        PCRE2_UCHAR ebuf[256];
        pcre2_get_error_message(err_code, ebuf, sizeof ebuf);
        fprintf(stderr, "check_urlhealth.c: pre-release re_compile failed: %s\n", (char *)ebuf);
        abort();
    }
}

static int matches_pre_release(const char *s)
{
    if (s == NULL || *s == '\0') return 0;
    pthread_once(&g_pre_release_once, init_re_pre_release);
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(RE_PRE_RELEASE, NULL);
    int rc = pcre2_match(RE_PRE_RELEASE, (PCRE2_SPTR)s, PCRE2_ZERO_TERMINATED,
                          0, 0, md, NULL);
    pcre2_match_data_free(md);
    return rc >= 0;
}

static void strip_prefix_icase_inplace(char *s, const char *prefix)
{
    if (s == NULL || prefix == NULL || *prefix == '\0') return;
    size_t plen = strlen(prefix);
    if (strncasecmp(s, prefix, plen) == 0) {
        memmove(s, s + plen, strlen(s + plen) + 1);
    }
}

static void apply_clean_version_names(char **names, size_t n)
{
    if (names == NULL) return;
    for (size_t i = 0; i < n; i++) {
        if (names[i] == NULL) continue;
        /* L 445: anchored case-insensitive leading-prefix strips, in order. */
        strip_prefix_icase_inplace(names[i], "rel/");
        strip_prefix_icase_inplace(names[i], "v");
        strip_prefix_icase_inplace(names[i], "r");
        /* L 445: literal underscore → dot. PS's `-replace '_','.'` would
         * be regex-aware in principle, but the source token is a literal
         * underscore so str_replace_all (case-sensitive literal) matches. */
        names[i] = str_replace_all(names[i], "_", ".");
        if (names[i] == NULL || names[i][0] == '\0') {
            free(names[i]); names[i] = NULL; continue;
        }
        /* L 448-449: drop pre-release candidates. */
        if (matches_pre_release(names[i])) {
            free(names[i]); names[i] = NULL; continue;
        }
    }
}

/* M23 — PS L 4321-4341 scraper pre-filter pipeline.
 *
 * Applied to scraper hrefs BEFORE the standard
 * apply_name_replace_augmentations / apply_clean_version_names /
 * apply_name_post_filters chain. Without this pre-step, candidates
 * like `autogen-5.18.16.tar.xz` get dropped by M21's
 * no-alpha-after-[pP]N rule (tar/xz are alpha residue), so the
 * scraper-path UpdateAvailable / UpdateURL / SHAName /
 * UpdateDownloadName cells stay empty for the ~189-spec
 * `cols[5 6 7 9 10]` bucket per branch.
 *
 * Steps:
 *   1. (PS L 4333) drop hrefs that contain `</a` — leftover from
 *      raw-HTML href extraction.
 *   2. (PS L 4334) drop hrefs that contain `.tgz.asc` — signature
 *      files, not archives.
 *   3. (PS L 4325-4332) two-pass keep filter: if any candidate
 *      contains `.tar.`, keep only those; else keep only `.tgz`.
 *      Per-spec `dialog` / `byacc` exceptions are deferred to
 *      future per-spec hooks (PS L 4325 disjunction).
 *   4. (PS L 4335-4340) strip the well-known archive extensions
 *      from each surviving candidate, in PS order:
 *      `-src.tar.gz`, `.tar.gz`, `.tar.bz2`, `.tar.xz`, `.tar.lz`,
 *      `.tgz`.
 *
 * Mutates names[] in place. Dropped entries are freed and set to
 * NULL. Surviving entries are reallocated by str_replace_all. */
static void apply_scraper_pre_filters(char **names, size_t n, const char *spec)
{
    if (names == NULL || n == 0) return;

    /* Steps 1+2: drop </a and .tgz.asc noise. */
    for (size_t i = 0; i < n; i++) {
        if (names[i] == NULL) continue;
        if (strstr(names[i], "</a") != NULL
            || strstr(names[i], ".tgz.asc") != NULL) {
            free(names[i]); names[i] = NULL;
        }
    }

    /* Step 3: keep .tar. if present in any survivor; else keep .tgz.
     * M56 / PS L 4374: byacc and dialog ALWAYS keep .tgz, even when a
     * versionless `<name>.tar.gz` "latest" symlink is also listed —
     * otherwise that lone .tar.gz flips the marker and drops every
     * versioned byacc-X.tgz / dialog-X.tgz, reducing to empty. */
    int force_tgz = spec != NULL
                    && (spec_eq(spec, "byacc.spec") || spec_eq(spec, "dialog.spec"));
    int has_tar = 0;
    for (size_t i = 0; i < n; i++) {
        if (names[i] && strstr(names[i], ".tar.") != NULL) { has_tar = 1; break; }
    }
    const char *keep_marker = (has_tar && !force_tgz) ? ".tar." : ".tgz";
    for (size_t i = 0; i < n; i++) {
        if (names[i] == NULL) continue;
        if (strstr(names[i], keep_marker) == NULL) {
            free(names[i]); names[i] = NULL;
        }
    }

    /* Step 4: strip archive extensions, PS order. PS uses `-replace`
     * (case-sensitive literal — `[regex]::Escape` style on a static
     * suffix) so str_replace_all is the right helper. */
    static const char *strip_exts[] = {
        "-src.tar.gz", ".tar.gz", ".tar.bz2", ".tar.xz", ".tar.lz", ".tgz",
        NULL,
    };
    for (size_t i = 0; i < n; i++) {
        if (names[i] == NULL) continue;
        for (int e = 0; strip_exts[e]; e++) {
            names[i] = str_replace_all(names[i], strip_exts[e], "");
        }
        if (names[i] == NULL || names[i][0] == '\0') {
            free(names[i]); names[i] = NULL;
        }
    }
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

/* M26 — PS L 2152 + L 2505 (and scraper mirror at L 4376):
 * Source0Lookup `ignoreStrings` column. Comma-separated list of glob
 * patterns; PS `-like` semantics with `*` wildcard, case-INsensitive.
 * Drop any candidate name matching ANY pattern.
 *
 * Sample (checkpolicy.spec L 568):
 *   ignoreStrings = "2008*,2009*,2010*,...,2020*"
 * Used to filter out date-format tags from upstreams that mix
 * date-based and version-based tag conventions (e.g. SELinuxProject).
 *
 * Mutates names[] in place. Dropped entries are freed and set to NULL.
 * Reuses fnmatch(3) with FNM_CASEFOLD for the glob match. */
static void apply_ignore_strings(char **names, size_t n,
                                 const char *ignore_strings)
{
    if (names == NULL || ignore_strings == NULL || *ignore_strings == '\0') return;

    /* Walk comma-separated patterns. */
    const char *p = ignore_strings;
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
            char *pattern = (char *)malloc(tok_len + 1);
            if (pattern) {
                memcpy(pattern, tok_start, tok_len);
                pattern[tok_len] = '\0';
                for (size_t i = 0; i < n; i++) {
                    if (names[i] == NULL) continue;
                    if (fnmatch(pattern, names[i], FNM_CASEFOLD) == 0) {
                        free(names[i]); names[i] = NULL;
                    }
                }
                free(pattern);
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
 * PS L 4786-4791 (M24): if the name starts with `Release` or `Rel_`
 * (case-INsensitive), replace those prefix tokens with
 * `<task.Name>-` and turn remaining `_` into `.`. Targets specs that
 * tag releases like `release-0.18.tar.gz` (chrpath) or `Rel_2.0.tar.gz`.
 * PS L 4792-4793 (M24): if the name starts with `v-` (case-INsensitive),
 * replace that prefix with `<task.Name>-`. Targets amdvlk-style
 * `v-2024.Q3.1.tar.gz`.
 *
 * Mutates the passed string in place where possible; otherwise returns
 * a newly-allocated replacement. Caller owns the result. */
static int starts_with_icase(const char *s, const char *prefix)
{
    if (s == NULL || prefix == NULL) return 0;
    size_t pl = strlen(prefix);
    if (strlen(s) < pl) return 0;
    return strncasecmp(s, prefix, pl) == 0;
}

/* PS `-ireplace '<prefix>', '<replacement>'` for a leading prefix only —
 * anchored at offset 0 by virtue of the prefix being a literal substring
 * that we only ever match once. PS's -ireplace operator scans globally
 * but for the prefix-strip patterns below the prefix only appears once
 * per name; treating as anchored matches PS bytes. */
static char *replace_leading_icase(char *s, const char *prefix,
                                   const char *replacement)
{
    if (s == NULL || prefix == NULL || *prefix == '\0') return s;
    if (!starts_with_icase(s, prefix)) return s;
    size_t pl = strlen(prefix);
    size_t rl = strlen(replacement ? replacement : "");
    size_t sl = strlen(s);
    size_t tail = sl - pl;
    char *out = (char *)malloc(rl + tail + 1);
    if (!out) return s;
    if (rl) memcpy(out, replacement, rl);
    memcpy(out + rl, s + pl, tail + 1);
    free(s);
    return out;
}

static char *download_name_post(char *raw, const char *task_name,
                                const char *task_spec)
{
    if (raw == NULL) return NULL;


    /* L 4770: optional 'v' strip. */
    if ((raw[0] == 'v' || raw[0] == 'V') && raw[1] && raw[1] != '-') {
        memmove(raw, raw + 1, strlen(raw));
    }

    /* M25 — PS L 4772-4779: four per-spec overrides applied AFTER the
     * common L 4770 v-strip but BEFORE the L 4782-4793 generic post-
     * processing. PS handles them as a flat if-chain inside CheckURLHealth
     * (not via Phase-3b hooks), so the natural C placement is inline here.
     * Each rule is anchored to the leading prefix of the basename. */
    if (task_spec && task_spec[0]) {
        if (strcasecmp(task_spec, "inih.spec") == 0) {
            /* PS L 4772: $UpdateDownloadName -ireplace "^r","libinih-".
             * Strips ONE leading 'r' (case-insensitive) anchored by `^`. */
            raw = replace_leading_icase(raw, "r", "libinih-");
        } else if (strcasecmp(task_spec, "open-vm-tools.spec") == 0) {
            /* PS L 4773: prepend "open-vm-tools-". Unconditional. */
            const char *pfx = "open-vm-tools-";
            size_t pl = strlen(pfx);
            size_t rl = strlen(raw);
            char *out = (char *)malloc(pl + rl + 1);
            if (out) {
                memcpy(out, pfx, pl);
                memcpy(out + pl, raw, rl + 1);
                free(raw);
                raw = out;
            }
        } else if (strcasecmp(task_spec, "samba-client.spec") == 0) {
            /* PS L 4774: -ireplace "samba-samba-","samba-" — global,
             * not anchored. Collapses duplicated prefix. */
            raw = istr_replace_all(raw, "samba-samba-", "samba-");
        } else if (strcasecmp(task_spec, "httpd-mod_jk.spec") == 0) {
            /* PS L 4775-4779: three sequential -ireplace ops then prepend.
             * `JK_` and `_` are case-insensitive globals; the prepend is
             * unconditional. */
            raw = istr_replace_all(raw, "JK_", "");
            raw = istr_replace_all(raw, "_",   ".");
            const char *pfx = "tomcat-connectors-";
            size_t pl = strlen(pfx);
            size_t rl = strlen(raw);
            char *out = (char *)malloc(pl + rl + 1);
            if (out) {
                memcpy(out, pfx, pl);
                memcpy(out + pl, raw, rl + 1);
                free(raw);
                raw = out;
            }
        }
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
                raw = out;
            }
        }
    }

    /* M24 — PS L 4786-4791: Release/Rel_ prefix replacement. PS branches
     * on `StartsWith("Release", OrdinalIgnoreCase) || StartsWith("Rel_", ...)`
     * then runs four -ireplace ops in order: `Release_`, `Release-`, `Rel_`,
     * and final `_`→`.`. */
    if (task_name && task_name[0]
        && (starts_with_icase(raw, "Release") || starts_with_icase(raw, "Rel_"))) {
        size_t nl = strlen(task_name);
        char *name_dash = (char *)malloc(nl + 2);
        if (name_dash) {
            memcpy(name_dash, task_name, nl);
            name_dash[nl] = '-';
            name_dash[nl + 1] = '\0';
            raw = replace_leading_icase(raw, "Release_", name_dash);
            raw = replace_leading_icase(raw, "Release-", name_dash);
            raw = replace_leading_icase(raw, "Rel_",     name_dash);
            free(name_dash);
        }
        /* PS L 4790 `-ireplace "_","."` runs after the prefix swap.
         * istr_replace_all is case-insensitive but for `_` the case
         * distinction is moot. */
        raw = str_replace_all(raw, "_", ".");
    }

    /* M24 — PS L 4792-4793: `v-` prefix replacement. */
    if (task_name && task_name[0] && starts_with_icase(raw, "v-")) {
        size_t nl = strlen(task_name);
        char *name_dash = (char *)malloc(nl + 2);
        if (name_dash) {
            memcpy(name_dash, task_name, nl);
            name_dash[nl] = '-';
            name_dash[nl + 1] = '\0';
            raw = replace_leading_icase(raw, "v-", name_dash);
            free(name_dash);
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

    /* PS L 2395-2397: rewrite ftp.gnu.org → FUNET mirror, post-
     * substitution / pre-urlhealth. See funet_mirror(). */
    state.Source0 = funet_mirror(state.Source0);

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
                        /* M26 (PS L 2152 + 2505): drop candidates matching
                         * Source0Lookup.ignoreStrings glob list. */
                        apply_ignore_strings(names, n, row->ignoreStrings);
                        /* M27 (PS L 2839 switch): per-spec strip tokens for
                         * ~76 specs that need custom prefix/substring strips
                         * beyond the generic M19 augmentations. */
                        pr_apply_per_spec_strip_tokens(task->Spec, names, n);
                        /* M28 (PS L 2839 switch): per-spec drop-substring
                         * blacklists for specs whose tag stream includes
                         * unwanted branch/test/feature tags. */
                        pr_apply_per_spec_drop_substrings(task->Spec, names, n);
                        /* M29 (PS L 2849, 2929, 2965): per-spec global
                         * character replacement ("-" → "."). */
                        pr_apply_per_spec_global_replace(task->Spec, names, n);
                        /* M19 (PS L 2507-2516): augment with Name-based
                         * tokens + common release/ver/-final patterns. */
                        apply_name_replace_augmentations(names, n,
                                                         task->Name ? task->Name : "");
                        /* M22 (PS L 441-451 Clean-VersionNames): leading
                         * rel//v/r strips, _→. replace, drop pre-release
                         * candidates (alpha/beta/rc/preview/dev/pre). */
                        apply_clean_version_names(names, n);
                        /* M21 (PS L 2522-2524): post-strip filters —
                         * v-strip + has-digit + no-alpha-after-pN-strip.
                         * M48 / PS L 2569: SKIP for amdvlk — its tags are
                         * quarterly "YYYY.Q#.#" (the comparator handles
                         * them, Case 2b), but the no-alpha filter would
                         * drop them on the "Q", leaving older non-Q tags
                         * as the wrong latest. */
                        if (!spec_eq(task->Spec, "amdvlk.spec"))
                            apply_name_post_filters(names, n);
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
                                    update_url = funet_mirror(update_url);
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
                                                      task->Name ? task->Name : "",
                                                      task->Spec ? task->Spec : "");
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
                                /* ADR-0015 (Option A): for github auto-archive
                                 * URLs, probe the corresponding release-asset
                                 * URL. On match, hash against the stable
                                 * asset; otherwise fall back to UpdateURL.
                                 * col 6 (UpdateURL) stays user-facing. */
                                char *sha_url = pr_resolve_stable_source_url(
                                    task->Spec, latest, state.UpdateURL);
                                const char *hash_url = sha_url
                                    ? sha_url : state.UpdateURL;
                                char *cache_file = col9_cache_path(
                                    clone_root, state.UpdateDownloadName);
                                /* ADR-0014 (Option B): single GET, dual-hash
                                 * when PR_EMIT_MULTI_SHA is set. Otherwise
                                 * the single-algorithm pr_sha_of_url. */
                                if (getenv("PR_EMIT_MULTI_SHA") != NULL) {
                                    char *h256 = NULL, *h512 = NULL;
                                    if (pr_sha_of_url_multi_cached(hash_url, &h256, &h512, cache_file) == 0) {
                                        free(state.SHA256Name); state.SHA256Name = h256;
                                        free(state.SHA512Name); state.SHA512Name = h512;
                                        /* SHAValue (col 9) keeps the spec's
                                         * preferred algorithm for backward
                                         * compat. Pick from the multi result. */
                                        const char *primary =
                                            (alg == PR_SHA256) ? h256 :
                                            (alg == PR_SHA512) ? h512 : NULL;
                                        if (primary) {
                                            free(state.SHAValue);
                                            state.SHAValue = strdup(primary);
                                        } else {
                                            /* SHA1 still needs single hash. */
                                            char *h1 = pr_sha_of_url_cached(PR_SHA1, hash_url, cache_file);
                                            if (h1) {
                                                free(state.SHAValue);
                                                state.SHAValue = h1;
                                            }
                                        }
                                    }
                                } else {
                                    char *hex = pr_sha_of_url_cached(alg, hash_url, cache_file);
                                    if (hex) {
                                        free(state.SHAValue);
                                        state.SHAValue = hex;
                                    }
                                }
                                free(cache_file);
                                free(sha_url);
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

    /* M78: dual-source detection for python packages. A developer may publish
     * a release to github, to PyPI, or to both, so for a python-* spec with a
     * github gitSource that is NOT declared deprecated (no ArchivationDate)
     * consult BOTH sources and report the HIGHER version. The git-tag path
     * above already produced github's view in state.UpdateAvailable (a version
     * / "(same version)" / empty / a regression Warning); we reconstruct
     * github's latest from it, query PyPI (the JSON API backing
     * pypi.org/project/<pkg>/#files), and adopt PyPI only when it is strictly
     * newer than both the current version AND github's latest. This subsumes
     * the one-way fallback: github-tagless (pyjsparser) -> PyPI; github newer
     * -> github kept; PyPI newer than a stale github tag -> PyPI. The
     * pyjsparser-class "Cannot detect correlating tags" warning is gated on
     * UpdateAvailable being empty, so populating it here suppresses it at the
     * downstream pr_spec_warning() step. PS mirrors this block verbatim. */
    if (allow_network
        && row && row->gitSource && strstr(row->gitSource, "github.com") != NULL
        && (row->ArchivationDate == NULL || row->ArchivationDate[0] == '\0')
        && task->Spec && strncmp(task->Spec, "python-", 7) == 0) {

        const char *cur = state.version ? state.version : "";
        /* github's latest, reconstructed from the git-path result. */
        char *gh_latest = NULL;
        if (state.UpdateAvailable && state.UpdateAvailable[0]
            && strcmp(state.UpdateAvailable, "(same version)") != 0
            && strncmp(state.UpdateAvailable, "Warning:", 8) != 0) {
            gh_latest = strdup(state.UpdateAvailable);   /* github found a newer ver */
        } else if (state.UpdateAvailable
                   && strcmp(state.UpdateAvailable, "(same version)") == 0) {
            gh_latest = strdup(cur);                     /* github latest == current */
        }

        /* PyPI package name = spec minus "python-" prefix and ".spec" suffix.
         * Photon's naming convention matches the PyPI project name (PyPI lookup
         * is case-insensitive); the github repo leaf can differ, e.g.
         * python-filelock -> repo "py-filelock" but PyPI "filelock". */
        char *pkg = NULL;
        {
            const char *s = task->Spec + 7;            /* gate guarantees "python-" */
            size_t sl = strlen(s);
            if (sl > 5 && strcmp(s + sl - 5, ".spec") == 0) sl -= 5;
            pkg = (char *)malloc(sl + 1);
            if (pkg) { memcpy(pkg, s, sl); pkg[sl] = '\0'; }
        }
        char *surl = NULL, *sname = NULL;
        char *pp = pkg ? pr_pypi_latest_version(pkg, &surl, &sname) : NULL;

        if (pp && pp[0]) {
            int pp_gt_cur = (pr_version_compare(pp, cur) == 1);
            int pp_gt_gh  = (gh_latest == NULL)
                            || (pr_version_compare(pp, gh_latest) == 1);
            if (pp_gt_cur && pp_gt_gh) {
                /* PyPI is the newest of the three -> developer released to PyPI. */
                free(state.UpdateAvailable); state.UpdateAvailable = strdup(pp);
                if (surl && surl[0]) {
                    free(state.UpdateURL); state.UpdateURL = surl; surl = NULL;
                    int h = urlhealth(state.UpdateURL);
                    char b[16]; snprintf(b, sizeof b, "%d", h);
                    free(state.HealthUpdateURL); state.HealthUpdateURL = strdup(b);
                }
                if (sname && sname[0]) {
                    /* Raw PyPI sdist filename; PS uses $sdist.filename verbatim
                     * too, so col 10 stays byte-identical. */
                    free(state.UpdateDownloadName); state.UpdateDownloadName = sname; sname = NULL;
                }
            } else if (gh_latest != NULL
                       && pr_version_compare(pp, gh_latest) == 0
                       && pp_gt_cur
                       && (state.UpdateURL == NULL || state.UpdateURL[0] == '\0')) {
                /* github detected this SAME update version but could not build a
                 * working download URL (cat 7 "packaging format changed" — the
                 * git path cleared UpdateURL + set the warning above). PyPI has
                 * a valid sdist for the same version: complete the record from
                 * PyPI and clear the now-obsolete packaging-format warning.
                 * UpdateAvailable (== pp == github's version) is unchanged. */
                if (surl && surl[0]) {
                    free(state.UpdateURL); state.UpdateURL = surl; surl = NULL;
                    int h = urlhealth(state.UpdateURL);
                    char b[16]; snprintf(b, sizeof b, "%d", h);
                    free(state.HealthUpdateURL); state.HealthUpdateURL = strdup(b);
                }
                if (sname && sname[0]) {
                    free(state.UpdateDownloadName); state.UpdateDownloadName = sname; sname = NULL;
                }
                if (state.Warning && strstr(state.Warning, "packaging format") != NULL) {
                    free(state.Warning); state.Warning = dup_or_empty("");
                }
            } else if (gh_latest == NULL && pr_version_compare(pp, cur) == 0) {
                /* github found nothing and PyPI == current -> (same version). */
                free(state.UpdateAvailable); state.UpdateAvailable = dup_or_empty("(same version)");
            }
            /* else: github's version >= PyPI (and URL ok, or PyPI not newer)
             * -> keep the git-path result. */
        }
        free(gh_latest); free(pp); free(surl); free(sname); free(pkg);
    }

    /* M34 / FRD-020: rubygems.org JSON-API update detection.
     *
     * PS L 3402-3456: when Source0 points at rubygems.org, PS queries
     * the RubyGems versions API instead of HTML-scraping (which is
     * useless for rubygems.org/downloads/). The C scraper had no
     * rubygems handling, leaving ~64 rubygem-* specs per branch in the
     * cols[5 6 7 9 10] residual bucket. Mirror PS exactly: gem_name
     * from task (fallback: spec minus `rubygem-` prefix / `.spec`
     * suffix), GET the API, take the newest non-prerelease version,
     * build the .gem download URL, compare, emit. */
    if (allow_network
        && (state.UpdateAvailable == NULL || state.UpdateAvailable[0] == '\0')
        && state.Source0 && strstr(state.Source0, "rubygems.org") != NULL) {
        const char *gem = (task->gem_name && task->gem_name[0])
                          ? task->gem_name : NULL;
        char *gem_fallback = NULL;
        if (gem == NULL && task->Spec) {
            /* spec minus leading "rubygem-" and trailing ".spec". */
            const char *s = task->Spec;
            if (strncmp(s, "rubygem-", 8) == 0) s += 8;
            size_t sl = strlen(s);
            if (sl > 5 && strcmp(s + sl - 5, ".spec") == 0) sl -= 5;
            gem_fallback = (char *)malloc(sl + 1);
            if (gem_fallback) { memcpy(gem_fallback, s, sl); gem_fallback[sl] = '\0'; gem = gem_fallback; }
        }
        char *latest = gem ? pr_rubygems_latest_version(gem) : NULL;
        if (latest && latest[0]) {
            int rc = pr_version_compare(latest, state.version ? state.version : "");
            free(state.UpdateAvailable);
            if (rc == 1) {
                state.UpdateAvailable = dup_or_empty(latest);
                char *update_url = NULL;
                if (asprintf(&update_url,
                             "https://rubygems.org/downloads/%s-%s.gem",
                             gem, latest) >= 0) {
                    free(state.UpdateURL);
                    state.UpdateURL = update_url;
                    int h = urlhealth(state.UpdateURL);
                    char buf[16]; snprintf(buf, sizeof buf, "%d", h);
                    free(state.HealthUpdateURL); state.HealthUpdateURL = strdup(buf);
                    /* UpdateDownloadName = <gem>-<latest>.gem basename. */
                    char *dl = pr_basename_from_url(state.UpdateURL);
                    if (dl) {
                        dl = download_name_post(dl, task->Name ? task->Name : "",
                                                task->Spec ? task->Spec : "");
                        free(state.UpdateDownloadName); state.UpdateDownloadName = dl;
                    }
                    /* SHA (col 9): rubygems .gem files are immutable
                     * stored blobs — no auto-archive drift — so hash
                     * the download URL directly. */
                    if (state.UpdateURL[0]) {
                        pr_sha_alg_t alg = PR_SHA512;
                        for (size_t li = 0; li < task->content_lines; li++) {
                            const char *line = task->content[li];
                            if (line == NULL) continue;
                            if (strstr(line, "%define sha1")   != NULL) { alg = PR_SHA1;   break; }
                            if (strstr(line, "%define sha256") != NULL) { alg = PR_SHA256; break; }
                            if (strstr(line, "%define sha512") != NULL) { alg = PR_SHA512; break; }
                        }
                        char *cache_file = col9_cache_path(
                            clone_root, state.UpdateDownloadName);
                        char *hex = pr_sha_of_url_cached(alg, state.UpdateURL, cache_file);
                        if (hex) { free(state.SHAValue); state.SHAValue = hex; }
                        free(cache_file);
                    }
                }
            } else if (rc == 0) {
                state.UpdateAvailable = dup_or_empty("(same version)");
            } else if (rc == -1) {
                char *warn = NULL;
                if (asprintf(&warn,
                             "Warning: %s Source0 version %s is higher than detected latest version %s .",
                             task->Spec ? task->Spec : "",
                             state.version ? state.version : "", latest) < 0) warn = NULL;
                state.UpdateAvailable = warn ? warn : dup_or_empty("");
            } else {
                state.UpdateAvailable = dup_or_empty("");
            }
        }
        free(latest);
        free(gem_fallback);
    }

    /* M20 / FRD-018: non-git update detection via HTTP listing scrape.
     *
     * When the spec has NO gitSource (or the row didn't load), PS
     * (L 4258-4283) GETs the directory-listing parent of Source0,
     * extracts <a href> values, and runs them through the same
     * version-name filter pipeline as git tags.
     *
     * M33 / FRD-019: per-spec atom-feed override. PS L 3815-3866
     * dispatcher sets `$SourceTagURL` to an atom-feed URL for ~27
     * specs (dbus, fontconfig, gstreamer, libdrm, mesa, pixman, ...).
     * PS uses it as a FALLBACK when the github-tag-list path returned
     * no Names. C mirrors: if the spec has an atom override AND
     * UpdateAvailable is still empty after the git-tag path, dispatch
     * to the atom-feed parser. Otherwise fall through to the existing
     * HTML listing scraper (M20).
     *
     * Gate: allow_network=1, UpdateAvailable empty (git path didn't
     * fill it), AND either (a) no gitSource OR (b) the spec has an
     * atom override. The original urlhealth must be 200 — a dead
     * Source0 means the listing parent is probably dead too. */
    const char *atom_url = pr_per_spec_source_tag_url(task->Spec);
    /* M35: PS reaches the sourceforge branch (L 3460) on the Source0 host
     * alone, independent of Source0 health — the project "files" landing
     * page is a different URL than the (often non-200) download Source0.
     * Admit such specs to the detection block regardless of `health`. */
    int sf_eligible = state.Source0
                      && strstr(state.Source0, "sourceforge.net") != NULL
                      && !sourceforge_deferred(task->Spec);
    /* M37: CPAN author-dir specs are likewise admitted regardless of
     * Source0 health (PS L 3933). The fetch is the normal listing scrape
     * of dirname(Source0) — only the perl-* strip tokens differ. */
    int cpan_eligible = cpan_eligible_source0(state.Source0);
    /* M38: github special-case specs with NO gitSource scrape the HTML
     * tags page (PS L 2766/2817-2818), independent of Source0 health.
     * Specs WITH a gitSource are handled by the Phase-6d git path above
     * and must not be disturbed, so require gitSource to be absent. */
    int gh_eligible = state.Source0
                      && strstr(state.Source0, "github.com") != NULL
                      && (row == NULL || row->gitSource == NULL
                          || row->gitSource[0] == '\0')
                      && pr_github_is_html_tags_spec(task->Spec);
    /* M41: "all other types" specs (PS L 4260-4305) with a per-spec
     * project-download-page override. Admitted regardless of health (PS
     * lists them explicitly in the gate). Tarball <a href> links are
     * full URLs → path-split to basename after extraction. */
    const char *ao_url = pr_all_other_source_tag_url(task->Spec);
    int ao_eligible = (ao_url != NULL)
                      && (row == NULL || row->gitSource == NULL
                          || row->gitSource[0] == '\0');
    /* M43: mozilla family scrapes a releases INDEX regardless of health
     * (PS L 3206-3272). Dir-name versions, nss/nspr transforms. */
    const char *moz_url = pr_mozilla_releases_url(task->Spec);
    int moz_eligible = (moz_url != NULL)
                       && (row == NULL || row->gitSource == NULL
                           || row->gitSource[0] == '\0');
    /* M44 / PS L 4300-4367: json-c is hosted on an S3 bucket whose XML
     * listing exposes versions as <Key> elements (not <a href>). */
    int jsonc_eligible = spec_eq(task->Spec, "json-c.spec")
                         && (row == NULL || row->gitSource == NULL
                             || row->gitSource[0] == '\0');
    /* cat-6 cluster B: the classic gnome FTP layout
     * (gnome.org/.../sources/<module>/<M.N>/<module>-<ver>) defeats the
     * generic listing scraper — dirname(Source0) is one minor dir and the
     * version-bearing parent lists bare "M.N/" dirs, so enumeration returns
     * nothing (empty cols 5/6 = cat 6). Enumerate versions from the gnome
     * download server's cache.json instead. SCOPED to the two cat-6 gnome
     * specs (GConf, gnome-common) — other gnome /sources/ specs either carry a
     * gitlab.gnome.org gitSource (git path) or already detect via the generic
     * scraper (e.g. libsigc++), so a host-wide rule would risk changing a
     * working spec. Add specs here if they later regress to cat 6. */
    int gnome_eligible = (spec_eq(task->Spec, "GConf.spec")
                          || spec_eq(task->Spec, "gnome-common.spec"))
                         && (row == NULL || row->gitSource == NULL
                             || row->gitSource[0] == '\0');
    if (allow_network && (health == 200 || sf_eligible || cpan_eligible || gh_eligible || ao_eligible || moz_eligible || jsonc_eligible || gnome_eligible)
        && (state.UpdateAvailable == NULL || state.UpdateAvailable[0] == '\0')
        && (atom_url != NULL
            || row == NULL
            || row->gitSource == NULL
            || row->gitSource[0] == '\0')
        && state.Source0 && state.Source0[0]) {
        /* Compute dirname(Source0) — strip from the last '/'. */
        char *parent = dup_or_empty(state.Source0);
        char *last_slash = strrchr(parent, '/');
        if (last_slash && last_slash != parent) {
            /* Keep trailing slash for directory-listing semantics. */
            last_slash[1] = '\0';
        }
        char **names = NULL;
        size_t  n     = 0;
        /* M33 / FRD-019: when this spec has an atom-feed URL override,
         * dispatch to pr_scrape_atom_feed against the override URL.
         * Otherwise fall through to the HTML listing scraper.
         * The M23 pre-filter is skipped on the atom path — atom titles
         * are tag names, not file basenames. */
        int used_atom  = 0;
        int used_sf    = 0;
        int used_gh    = 0;
        int used_moz   = 0;
        int used_gnome = 0;
        int scrape_ok  = 0;
        if (jsonc_eligible) {
            /* M44: S3-bucket XML listing -> <Key> values. Drop the
             * -nodoc variant (PS L 4367) and strip the "releases/json-c-"
             * prefix (PS L 4366); the pipeline ext-strip then yields the
             * version. */
            scrape_ok = (pr_scrape_keys("https://s3.amazonaws.com/json-c_releases/", &names, &n) == 0);
            if (scrape_ok) {
                for (size_t i = 0; i < n; i++) {
                    if (names[i] == NULL) continue;
                    if (strstr(names[i], "-nodoc") != NULL) {
                        free(names[i]); names[i] = NULL; continue;
                    }
                    names[i] = istr_replace_all(names[i], "releases/json-c-", "");
                }
            }
            /* Do NOT skip M23 here: the names are "<ver>.tar.gz" — M23
             * keeps .tar. entries and strips the extension early, before
             * the no-alpha post-filter would otherwise drop them. */
        } else if (moz_eligible) {
            /* M43: scrape the mozilla releases index for dir-name
             * versions; transform (basename, strip trailing /, nss
             * NSS_/_RTM) then the standard pipeline finds the latest. */
            scrape_ok = (pr_scrape_listing(moz_url, &names, &n) == 0);
            if (scrape_ok) apply_mozilla_transform(task->Spec, names, n);
            used_moz = 1;
        } else if (ao_eligible) {
            /* M41: scrape the project download page; its <a href> tarball
             * links are full URLs, so reduce each to its basename
             * (PS L 4400 path-split) before the version pipeline. The
             * basenamed names then run the standard scraper pipeline
             * (M23 pre-filter + Name-strip + Clean-VersionNames + …). */
            scrape_ok = (pr_scrape_listing(ao_url, &names, &n) == 0);
            if (scrape_ok) {
                for (size_t i = 0; i < n; i++) {
                    if (names[i] == NULL) continue;
                    char *base = pr_basename_from_url(names[i]);
                    if (base) { free(names[i]); names[i] = base; }
                }
            }
        } else if (gh_eligible) {
            /* M38: github special-case HTML tags page. */
            char *gh_url = pr_github_tags_html_url(state.Source0);
            if (gh_url) {
                scrape_ok = (pr_github_scrape_tags_html(gh_url, &names, &n) == 0);
                used_gh = 1;
                free(gh_url);
            }
        } else if (sf_eligible) {
            /* M35: SourceForge — derive the project files URL and parse
             * the embedded net.sf.files JSON instead of HTML hrefs. */
            char *sf_url = pr_sourceforge_tag_url(task->Spec, state.Source0);
            if (sf_url) {
                scrape_ok = (pr_sourceforge_fetch_names(sf_url, &names, &n) == 0);
                /* M49: the derived URL is .../files/<project>, but some
                 * projects host releases directly under .../files/ (e.g.
                 * nicstat, tclap). If the <project> sub-dir 404s / yields
                 * nothing, retry the parent .../files/. Only fires when
                 * the primary fails, so working specs are untouched. */
                if (!scrape_ok || n == 0) {
                    char *slash = strrchr(sf_url, '/');
                    if (slash && slash != sf_url) {
                        slash[1] = '\0';  /* keep trailing slash */
                        scrape_ok = (pr_sourceforge_fetch_names(sf_url, &names, &n) == 0);
                    }
                }
                /* M63 / PS L 3513-3530: libusb two-stage. Stage-1 names are
                 * series dirs (libusb-1.0). Pick the latest series, then
                 * re-scrape files/libusb-<series> for the real release names
                 * — the generic pipeline below then yields e.g. 1.0.30. */
                if (scrape_ok && n > 0 && spec_eq(task->Spec, "libusb.spec")) {
                    char *series = libusb_latest_series(names, n);
                    if (series) {
                        char *s2_url = NULL;
                        if (asprintf(&s2_url,
                                "https://sourceforge.net/projects/libusb/files/libusb-%s",
                                series) >= 0 && s2_url) {
                            char **n2 = NULL; size_t c2 = 0;
                            if (pr_sourceforge_fetch_names(s2_url, &n2, &c2) == 0 && c2 > 0) {
                                pr_git_tags_free(names, n);  /* drop stage-1 */
                                names = n2; n = c2;
                            } else {
                                pr_git_tags_free(n2, c2);
                            }
                            free(s2_url);
                        }
                        free(series);
                    }
                }
                used_sf = 1;
                free(sf_url);
            }
        } else if (gnome_eligible) {
            /* cluster B: gnome cache.json. Module name = the gnome module,
             * i.e. task->Name (Source0 is .../sources/%{name}/...). The
             * returned strings are bare versions ("3.2.6"), so the standard
             * pipeline below (no Name-strip needed, but harmless) finds the
             * latest. Skip the M23 href pre-filter — these aren't basenames. */
            const char *module = (task->Name && task->Name[0]) ? task->Name : NULL;
            if (module) {
                scrape_ok = (pr_gnome_cache_versions(module, &names, &n) == 0);
                used_gnome = 1;
            }
        } else if (atom_url != NULL) {
            scrape_ok = (pr_scrape_atom_feed(atom_url, &names, &n) == 0);
            used_atom = 1;
        } else {
            scrape_ok = (pr_scrape_listing(parent, &names, &n) == 0);
            /* M54: reduce raw hrefs to their last path segment so
             * root-relative / absolute listing links (e.g. curl.se's
             * "download/curl-8.20.0.tar.xz") parse like bare basenames. */
            if (scrape_ok) apply_href_basename(names, n);
        }
        if (scrape_ok && n > 0) {
            if (!used_atom && !used_sf && !used_gh && !used_moz && !used_gnome) {
                /* M23 (PS L 4321-4341) — HTML href path only. */
                apply_scraper_pre_filters(names, n, task->Spec);
            }
            /* M35 / PS L 3525-3529: tboot year-stamped dir drops. */
            if (used_sf && spec_eq(task->Spec, "tboot.spec")) {
                drop_year_names(names, n);
            }
            /* M38 / PS L 2888 switch "python-networkx.spec": extra strip
             * tokens so "networkx-X" / "python-networkx-X" reduce to X. */
            if (used_gh && spec_eq(task->Spec, "python-networkx.spec")) {
                for (size_t i = 0; i < n; i++) {
                    if (names[i] == NULL) continue;
                    names[i] = istr_replace_all(names[i], "python-networkx-", "");
                    names[i] = istr_replace_all(names[i], "networkx-", "");
                }
            }
            /* M39 / PS L 3691-3695: samba-family per-library prefix token. */
            if (used_atom) {
                apply_samba_tokens(task->Spec, names, n);
            }
            /* M55 / PS L 4406-4413: tzdata listing filter (keep tzdata-*,
             * drop sigs/.tar.Z, strip "beta") — before the Name-strip. */
            if (spec_eq(task->Spec, "tzdata.spec")) {
                apply_tzdata_filter(names, n);
            }
            apply_replace_strings(names, n, row ? row->replaceStrings : NULL);
            /* M26 (PS L 2152 + L 4376): drop candidates matching
             * Source0Lookup.ignoreStrings glob list (only when a row
             * exists — scraper-only fallback specs have no row). */
            apply_ignore_strings(names, n, row ? row->ignoreStrings : NULL);
            /* M37 / PS L 3955-3958: CPAN prefix-stripped tokens, added
             * before the generic Name tokens (PS $replace array order). */
            if (cpan_eligible) {
                apply_cpan_perl_tokens(names, n, task->Name ? task->Name : "");
            }
            /* M42 / PS L 3335-3350: per-spec generic-scrape prefix tokens
             * (freetype-, grub-, xproto-, ...). No-op for other specs.
             * M51: applied BEFORE the Name tokens (matching PS $replace
             * array order, where these are added earlier) — critical for
             * proto, where Name="proto" would otherwise strip the "proto"
             * inside "xproto-7.0.31" → "x-7.0.31" (dropped on the "x")
             * before the "xproto-" token could fire. */
            apply_generic_scrape_tokens(task->Spec, names, n);
            apply_name_replace_augmentations(names, n,
                                             task->Name ? task->Name : "");
            /* M22 (PS L 441-451 Clean-VersionNames): leading rel//v/r
             * strips, _→. replace, drop pre-release candidates. */
            apply_clean_version_names(names, n);
            /* M21 (PS L 2522-2524): v-strip + has-digit + no-alpha-
             * after-[pP]\d+-strip. Drops scraper noise like
             * `LATEST-IS-X`, `?C=S;O=A`, `..`. M55 / PS L 4439: skipped for
             * tzdata — its versions end in a letter ("2026b"), which the
             * no-alpha filter would otherwise drop entirely. */
            if (!spec_eq(task->Spec, "tzdata.spec"))
                apply_name_post_filters(names, n);
            /* M47 / PS L 4210-4219: linux kernel family per-branch series
             * pin — keep only candidates in the tracked LTS series. */
            const char *kseries = linux_kernel_series(task->Spec, clone_root);
            if (kseries) {
                for (size_t ki = 0; ki < n; ki++) {
                    if (names[ki] && strstr(names[ki], kseries) == NULL) {
                        free(names[ki]); names[ki] = NULL;
                    }
                }
            }
            /* M55 / PS L 4445-4460: tzdata uses the bespoke year+letter sort
             * instead of the generic Get-LatestName. */
            char *latest = spec_eq(task->Spec, "tzdata.spec")
                           ? tzdata_latest(names, n)
                           : pr_get_latest_name(names, n);
            if (latest && latest[0]) {
                /* Strip common file extensions if present — listing
                 * hrefs are often like "GConf-3.2.6.tar.xz". */
                static const char *exts[] = {
                    ".tar.gz", ".tar.xz", ".tar.lz", ".tar.bz2",
                    ".tgz",    ".zip",    ".gem",
                    NULL,
                };
                size_t ll = strlen(latest);
                for (int e = 0; exts[e]; e++) {
                    size_t el = strlen(exts[e]);
                    if (ll >= el && strncasecmp(latest + ll - el, exts[e], el) == 0) {
                        latest[ll - el] = '\0';
                        break;
                    }
                }
                /* M40: unzip/zip dot-less version munge for the compare. */
                const char *cmp_ver = munge_sf_version(
                    task->Spec, state.version ? state.version : "");
                int rc = pr_version_compare(latest, cmp_ver);
                free(state.UpdateAvailable);
                if (rc == 1) {
                    state.UpdateAvailable = dup_or_empty(latest);
                    /* Build UpdateURL via re-substitution. */
                    const char *template = (row && row->Source0Lookup && row->Source0Lookup[0])
                                           ? row->Source0Lookup
                                           : (task->Source0 ? task->Source0 : "");
                    char *update_url = dup_or_empty(template);
                    if (update_url) {
                        pr_source0_substitute(task, &update_url, latest);
                        /* PS rewrites $Source0 (L2395) before deriving the
                         * UpdateURL, so the mirror propagates here too. */
                        update_url = funet_mirror(update_url);
                        /* M46: apparmor launchpad series-dir fixup. */
                        if (spec_eq(task->Spec, "apparmor.spec"))
                            update_url = apparmor_series_fixup(update_url, latest);
                        free(state.UpdateURL);
                        state.UpdateURL = update_url;
                    }
                    if (state.UpdateURL && state.UpdateURL[0]) {
                        int h = urlhealth(state.UpdateURL);
                        char buf[16];
                        snprintf(buf, sizeof buf, "%d", h);
                        free(state.HealthUpdateURL);
                        state.HealthUpdateURL = strdup(buf);
                        if (h != 0 && h != 200) {
                            free(state.Warning);
                            state.Warning = dup_or_empty(
                                "Warning: Manufacturer may changed version packaging format.");
                            free(state.UpdateURL);
                            state.UpdateURL = dup_or_empty("");
                            free(state.HealthUpdateURL);
                            state.HealthUpdateURL = dup_or_empty("");
                        } else {
                            char *dl_name = pr_basename_from_url(state.UpdateURL);
                            if (dl_name) {
                                dl_name = download_name_post(dl_name,
                                              task->Name ? task->Name : "",
                                              task->Spec ? task->Spec : "");
                                free(state.UpdateDownloadName);
                                state.UpdateDownloadName = dl_name;
                            }
                            /* SHA computation reusing the existing
                             * pattern: walk content for sha define. */
                            pr_sha_alg_t alg = PR_SHA512;
                            for (size_t li = 0; li < task->content_lines; li++) {
                                const char *line = task->content[li];
                                if (line == NULL) continue;
                                if (strstr(line, "%define sha1")   != NULL) { alg = PR_SHA1;   break; }
                                if (strstr(line, "%define sha256") != NULL) { alg = PR_SHA256; break; }
                                if (strstr(line, "%define sha512") != NULL) { alg = PR_SHA512; break; }
                            }
                            /* ADR-0015 (Option A): stable-source override. */
                            char *sha_url = pr_resolve_stable_source_url(
                                task->Spec, latest, state.UpdateURL);
                            const char *hash_url = sha_url ? sha_url
                                                            : state.UpdateURL;
                            char *cache_file = col9_cache_path(
                                clone_root, state.UpdateDownloadName);
                            /* ADR-0014 (Option B): multi-hash when env var set. */
                            if (getenv("PR_EMIT_MULTI_SHA") != NULL) {
                                char *h256 = NULL, *h512 = NULL;
                                if (pr_sha_of_url_multi_cached(hash_url, &h256, &h512, cache_file) == 0) {
                                    free(state.SHA256Name); state.SHA256Name = h256;
                                    free(state.SHA512Name); state.SHA512Name = h512;
                                    const char *primary =
                                        (alg == PR_SHA256) ? h256 :
                                        (alg == PR_SHA512) ? h512 : NULL;
                                    if (primary) {
                                        free(state.SHAValue);
                                        state.SHAValue = strdup(primary);
                                    } else {
                                        char *h1 = pr_sha_of_url_cached(PR_SHA1, hash_url, cache_file);
                                        if (h1) { free(state.SHAValue); state.SHAValue = h1; }
                                    }
                                }
                            } else {
                                char *hex = pr_sha_of_url_cached(alg, hash_url, cache_file);
                                if (hex) {
                                    free(state.SHAValue);
                                    state.SHAValue = hex;
                                }
                            }
                            free(cache_file);
                            free(sha_url);
                        }
                    }
                } else if (rc == 0) {
                    state.UpdateAvailable = dup_or_empty("(same version)");
                } else if (rc == -1) {
                    char *warn = NULL;
                    if (asprintf(&warn,
                                 "Warning: %s Source0 version %s is higher than detected latest version %s .",
                                 task->Spec ? task->Spec : "",
                                 cmp_ver,
                                 latest) < 0) warn = NULL;
                    state.UpdateAvailable = warn ? warn : dup_or_empty("");
                } else {
                    state.UpdateAvailable = dup_or_empty("");
                }
            }
            free(latest);
            pr_git_tags_free(names, n);
        }
        free(parent);
    }

    /* M62 / PS L 2540-2556 + L 4705-4711: netcat bespoke detection. The
     * vendored Source0 (packages.broadcom.com/.../nc-<commit_id>.tar.xz) has
     * no upstream release listing, so derive col5 from the CVS revision in
     * openbsd's netcat.c and the download-name commit_id from the GitHub
     * Commits API. col6/col7/col10 follow PS's self-built convention. */
    if (allow_network && spec_eq(task->Spec, "netcat.spec")) {
        char *nc_ver = NULL, *nc_cid = NULL;
        if (pr_netcat_detect(getenv("GITHUB_TOKEN"), &nc_ver, &nc_cid) == 0
            && nc_ver && nc_ver[0]) {
            free(state.UpdateAvailable);
            state.UpdateAvailable = nc_ver;   /* takes ownership */
            if (nc_cid && nc_cid[0]) {
                free(state.UpdateURL);
                state.UpdateURL = dup_or_empty(
                    "self-built from https://github.com/openbsd/src (usr.bin/nc)");
                free(state.HealthUpdateURL);
                state.HealthUpdateURL = dup_or_empty("200");
                free(state.UpdateDownloadName);
                if (asprintf(&state.UpdateDownloadName, "nc-%s.tar.xz", nc_cid) < 0)
                    state.UpdateDownloadName = dup_or_empty("");
            }
        } else {
            free(nc_ver);
        }
        free(nc_cid);
    }

    /* M57 / PS L 2264-2363: hardcoded UpdateURL/UpdateAvailable overrides.
     * The maintainer pins these because dynamic detection is impossible or
     * broken upstream (archived projects, broken download pages, pythonhosted
     * blob URLs, etc.). PS sets them early (L2264) so the later detection
     * leaves them untouched; we apply them after detection (overriding any
     * stray value) for the same net output. HealthUpdateURL is "200";
     * UpdateDownloadName derives from the URL via the standard L4810-4842
     * pipeline (download_name_post), so the leading-'v' strip etc. match PS.
     * col9 (SHAValue) is left empty here — it is soft in the parity verdict
     * and PS computes it from a network fetch we intentionally skip. */
    {
        static const struct { const char *spec, *url, *ver, *archdate; } k_hard[] = {
            {"cdrkit.spec",             "https://deb.debian.org/debian/pool/main/c/cdrkit/cdrkit_1.1.11.orig.tar.gz", "1.1.11", "2021-10-10"},
            {"iptraf.spec",             "https://distro.ibiblio.org/fatdog/source/800/iptraf-3.0.1.tar.gz",          "3.0.1",  ""},
            {"json-spirit.spec",        "https://api-main.codeproject.com/v1/article/JSON_Spirit/downloadAttachment?src=JSON_Spirit/json_spirit_v4.08.zip", "3.1.2", ""},
            {"libassuan.spec",          "https://www.gnupg.org/ftp/gcrypt/libassuan/libassuan-3.0.2.tar.bz2",        "3.0.2",  ""},
            {"libtiff.spec",            "https://download.osgeo.org/libtiff/tiff-4.7.1.tar.xz",                      "4.7.1",  ""},
            {"mpc.spec",                "https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz",                              "1.3.1",  ""},
            {"python-daemon.spec",      "https://files.pythonhosted.org/packages/3d/37/4f10e37bdabc058a32989da2daf29e57dc59dbc5395497f3d36d5f5e2694/python_daemon-3.1.2.tar.gz", "3.1.2", ""},
            {"python-enum.spec",        "https://files.pythonhosted.org/packages/02/a0/32e1d5a21b703f600183e205aafc6773577e16429af5ad3c3f9b956b07ca/enum-0.4.7.tar.gz", "0.4.7", ""},
            {"python-enum34.spec",      "https://files.pythonhosted.org/packages/11/c4/2da1f4952ba476677a42f25cd32ab8aaf0e1c0d0e00b89822b835c7e654c/enum34-1.1.10.tar.gz", "1.1.10", ""},
            {"python-Js2Py.spec",       "https://files.pythonhosted.org/packages/cb/a5/3d8b3e4511cc21479f78f359b1b21f1fb7c640988765ffd09e55c6605e3b/Js2Py-0.74.tar.gz", "0.74", ""},
            {"python-ruamel-yaml.spec", "https://files.pythonhosted.org/packages/c7/3b/ebda527b56beb90cb7652cb1c7e4f91f48649fbcd8d2eb2fb6e77cd3329b/ruamel_yaml-0.19.1.tar.gz", "0.19.1", ""},
            {"runit.spec",              "https://smarden.org/runit/runit-2.3.0.tar.gz",                              "2.3.0",  ""},
            {"sendmail.spec",           "https://ftp.sendmail.org/sendmail.8.18.2.tar.gz",                           "8.18.2", ""},
            {"vsftpd.spec",             "https://security.appspot.com/downloads/vsftpd-3.0.5.tar.gz",                "3.0.5",  ""},
        };
        for (size_t i = 0; i < sizeof k_hard / sizeof k_hard[0]; i++) {
            if (!spec_eq(task->Spec, k_hard[i].spec)) continue;
            free(state.UpdateAvailable); state.UpdateAvailable = dup_or_empty(k_hard[i].ver);
            free(state.UpdateURL);       state.UpdateURL       = dup_or_empty(k_hard[i].url);
            free(state.HealthUpdateURL); state.HealthUpdateURL = dup_or_empty("200");
            char *base = pr_basename_from_url(k_hard[i].url);   /* ($UpdateURL -split '/')[-1] */
            free(state.UpdateDownloadName);
            state.UpdateDownloadName = download_name_post(base, task->Name, task->Spec);
            if (state.UpdateDownloadName == NULL) state.UpdateDownloadName = dup_or_empty("");
            if (k_hard[i].archdate[0]) {
                free(state.ArchivationDate); state.ArchivationDate = dup_or_empty(k_hard[i].archdate);
            }
            break;
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

    /* PS L 4933: assemble the row.
     *
     *   $currentTask.spec , $currentTask.source0 , $Source0 ,
     *   $urlhealth , $UpdateAvailable , $UpdateURL , $HealthUpdateURL ,
     *   $currentTask.Name , $SHAValue , $UpdateDownloadName , $Warning ,
     *   $ArchivationDate
     *
     * ADR-0014 (Accepted Option B): when PR_EMIT_MULTI_SHA env var is
     * set, append cols 13 (SHA256Name) + 14 (SHA512Name). The cached
     * PS snapshot is 12-col; when the operator refreshes the PS
     * snapshot with the matching PS-side change, flip the env var to
     * activate 14-col emission. Default is 12-col so the parity-gate
     * stays consistent during rollout.
     */
    const int emit_multi_sha = getenv("PR_EMIT_MULTI_SHA") != NULL;
    char *out = NULL;
    int rc;
    if (emit_multi_sha) {
        rc = asprintf(&out,
                     "%s,%s,%s,%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s",
                     task->Spec,
                     task->Source0 ? task->Source0 : "",
                     state.Source0,
                     health,
                     state.UpdateAvailable,
                     state.UpdateURL,
                     state.HealthUpdateURL,
                     task->Name,
                     state.SHAValue,
                     state.UpdateDownloadName,
                     state.Warning,
                     state.ArchivationDate,
                     state.SHA256Name,                            /* 13 — ADR-0014 */
                     state.SHA512Name                             /* 14 — ADR-0014 */
                     );
    } else {
        rc = asprintf(&out,
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
                     );
    }
    if (rc < 0) out = NULL;

    pr_state_free(&state);
    return out;
}
