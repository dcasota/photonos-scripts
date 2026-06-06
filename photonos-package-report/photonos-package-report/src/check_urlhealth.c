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
#include "pr_github_api.h"
#include "pr_hook.h"
#include "pr_jdk.h"
#include "pr_latest.h"
#include "pr_modify_spec.h"
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
/* M81: archive-extension fallback. Upstreams migrate archive formats over time
 * (notably ftp.x.org: .tar.bz2 -> .tar.xz/.tar.gz), so a version-substituted
 * UpdateURL that keeps the spec's stale extension 404s even though the release
 * exists under a different extension. When the built URL HEAD-fails, retry the
 * same URL with each alternate archive extension; on a 200 rewrite *url in
 * place and return 200. Additive — only invoked on an already-failing URL, so
 * it can only turn a cat-7 empty into a working download. PS mirrors this in
 * its URL-build retry (the extension-swap loop before the packaging warning). */
static int try_url_ext_fallback(char **url)
{
    static const char *const exts[] = {".tar.xz", ".tar.gz", ".tar.bz2", ".tgz", ".zip", NULL};
    if (url == NULL || *url == NULL) return 0;
    const char *cur = NULL;
    size_t ul = strlen(*url);
    for (int i = 0; exts[i]; i++) {
        size_t el = strlen(exts[i]);
        if (ul >= el && strcmp(*url + ul - el, exts[i]) == 0) { cur = exts[i]; break; }
    }
    if (cur == NULL) return 0;                 /* not a recognised archive URL */
    size_t base = ul - strlen(cur);
    for (int i = 0; exts[i]; i++) {
        if (strcmp(exts[i], cur) == 0) continue;
        char *cand = NULL;
        if (asprintf(&cand, "%.*s%s", (int)base, *url, exts[i]) < 0) continue;
        if (urlhealth(cand) == 200) { free(*url); *url = cand; return 200; }
        free(cand);
    }
    return 0;
}

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

/* PS L4868: major.minor of a version — Split('.')[0] + "." + [1]. PowerShell
 * concat of a $null [1] (no second dot-segment, e.g. "39") yields a trailing
 * dot: "39." Replicate that edge case exactly. */
static char *vmm(const char *v)
{
    if (v == NULL) return dup_or_empty("");
    const char *d1 = strchr(v, '.');
    if (d1 == NULL) {
        size_t l = strlen(v);
        char *o = (char *)malloc(l + 2);
        if (!o) return dup_or_empty("");
        memcpy(o, v, l); o[l] = '.'; o[l + 1] = '\0';
        return o;
    }
    const char *d2 = strchr(d1 + 1, '.');
    size_t end = d2 ? (size_t)(d2 - v) : strlen(v);
    char *o = (char *)malloc(end + 1);
    if (!o) return dup_or_empty("");
    memcpy(o, v, end); o[end] = '\0';
    return o;
}

/* PS `-ireplace <pat>,<repl>`: case-insensitive, global, REGEX replace. The
 * version strings PS passes as the pattern contain '.', which as a regex
 * matches ANY char — this is load-bearing: e.g. openldap's resolved tag holds
 * "OPENLDAP_REL_ENG_2_6_12", and the pattern "2.6.12" matches "2_6_12" because
 * '.' matches '_'. Literal replace would miss it. Replacement is literal
 * (version strings carry no '$' backrefs). Heap result; on compile failure or
 * no match returns a copy of `s`. (Does NOT free `s`.) */
static char *ireplace_re(const char *s, const char *pat, const char *repl)
{
    if (s == NULL) return NULL;
    if (pat == NULL || pat[0] == '\0') return strdup(s);
    int ec = 0; PCRE2_SIZE eo = 0;
    pcre2_code *re = pcre2_compile((PCRE2_SPTR)pat, PCRE2_ZERO_TERMINATED,
                                   PCRE2_CASELESS, &ec, &eo, NULL);
    if (re == NULL) return strdup(s);
    PCRE2_SIZE olen = strlen(s) * 2 + 64;
    PCRE2_UCHAR *out = (PCRE2_UCHAR *)malloc(olen);
    if (out == NULL) { pcre2_code_free(re); return strdup(s); }
    uint32_t opt = PCRE2_SUBSTITUTE_GLOBAL | PCRE2_SUBSTITUTE_LITERAL
                 | PCRE2_SUBSTITUTE_OVERFLOW_LENGTH;
    int rc = pcre2_substitute(re, (PCRE2_SPTR)s, PCRE2_ZERO_TERMINATED, 0, opt,
                              NULL, NULL, (PCRE2_SPTR)(repl ? repl : ""),
                              PCRE2_ZERO_TERMINATED, out, &olen);
    if (rc == PCRE2_ERROR_NOMEMORY) {
        PCRE2_UCHAR *bg = (PCRE2_UCHAR *)realloc(out, olen);
        if (bg != NULL) {
            out = bg;
            rc = pcre2_substitute(re, (PCRE2_SPTR)s, PCRE2_ZERO_TERMINATED, 0,
                                  PCRE2_SUBSTITUTE_GLOBAL | PCRE2_SUBSTITUTE_LITERAL,
                                  NULL, NULL, (PCRE2_SPTR)(repl ? repl : ""),
                                  PCRE2_ZERO_TERMINATED, out, &olen);
        }
    }
    pcre2_code_free(re);
    char *result = (rc < 0) ? strdup(s) : strdup((char *)out);
    free(out);
    return result;
}

/* M96/M97 allow-list for the github bare-tag Source0 normalization below.
 * Deliberately an explicit per-spec allow-list, NOT a global github rule: the
 * broad form was validated (isolation: C-master vs C-branch, same snapshot) to
 * regress redirect-resolving / detection-path-shifting repos by landing on a
 * PS-divergent variant — kubernetes-dashboard (kubernetes/ vs PS's
 * kubernetes-retired/) and falco (older 0.43.1). Only specs proven by that
 * same isolation to CHANGE *and* CONVERGE to PS are admitted here. */
static int gh_tag_normalize_allowed(const char *spec)
{
    static const char *const list[] = {
        "valkey.spec", "liblognorm.spec", "rpm-sequoia.spec", "tinydir.spec",
        "timescaledb14.spec", "timescaledb15.spec", "timescaledb16.spec",
        "timescaledb17.spec", "timescaledb18.spec", NULL,
    };
    for (int i = 0; list[i]; i++)
        if (spec_eq(spec, list[i])) return 1;
    return 0;
}

/* M120: per-spec allow-list for the github "no-/archive/" Source0
 * normalization (PS L2766-2790 else branch). PS rewrites <name>-<ver>
 * (anywhere in the URL) to /archive/refs/tags/v<ver>, then
 * /archive/refs/tags/<ver> as a fallback. Same conservative pattern as
 * M96/M97 + M114 — allow-listed to specs proven safe. cbindgen is the
 * first admit: its raw Source0 "%{name}-%{version}.tar.gz" gets
 * URL-prefixed by source0_substitute to
 * "https://github.com/mozilla/cbindgencbindgen-0.29.2.tar.gz" (no
 * slash because the spec's URL has no trailing slash), then PS's L2766
 * else branch ireplaces "cbindgen-0.29.2" with "/archive/refs/tags/
 * v0.29.2", producing the correct
 * "https://github.com/mozilla/cbindgen/archive/refs/tags/v0.29.2.tar.gz".
 * The slash reappears as a side effect of the rewrite. */
static int gh_no_archive_normalize_allowed(const char *spec)
{
    static const char *const list[] = {
        "cbindgen.spec", NULL,
    };
    for (int i = 0; list[i]; i++)
        if (spec_eq(spec, list[i])) return 1;
    return 0;
}

/* M114: per-spec allow-list for the github /archive/<name>- (NO /refs/tags/)
 * Source0 normalization. PS L2710-2720 unconditionally rewrites such URLs
 * to /archive/refs/tags/<ver> when the original 404s, then to
 * /archive/refs/tags/v<ver> as a fallback. C mirrors that behaviour but
 * gated to the proven-safe allow-list — the same conservative pattern as
 * gh_tag_normalize_allowed (the broad form there regressed kubernetes-
 * dashboard / falco). Specs admitted here must (1) lack a Source0Lookup
 * row with a gitSource so the clone path doesn't already cover them, and
 * (2) have a github archive Source0 of the /<name>-<ver>.tar.gz shape. */
static int gh_archive_no_refs_normalize_allowed(const char *spec)
{
    static const char *const list[] = {
        "logrotate.spec", NULL,
    };
    for (int i = 0; list[i]; i++)
        if (spec_eq(spec, list[i])) return 1;
    return 0;
}

/* PS L2630-2701: when a github /archive/refs/tags/ Source0 is NOT 200,
 * normalize it to the real tag form by trying variants against the CURRENT
 * version (PS source order): <name>-v<ver> -> v<ver>; <name>-<ver> -> v<ver>;
 * <name>-<ver> -> <ver> (bare); version _->. ; .->- ; .->_ ; <name-last-seg>-
 * <ver> -> v<ver>. Adopts the first that HEADs 200 so the M91 update cascade
 * then builds the real-tag latest URL. Returns the normalized URL (heap; a
 * copy of `save` if none work); *out_health = 200 iff a variant resolved.
 * Caller gates via gh_tag_normalize_allowed() (proven-safe allow-list). */
static char *gh_archive_tag_normalize(const char *save, const char *name,
                                      const char *version, int *out_health)
{
    const char *nm = name ? name : "";
    const char *ver = version ? version : "";
    char *best = strdup(save);
    int h = 0;
    char p[768], r[768];

#define GH_TRY(PAT, REP) do {                                     \
        char *cand = ireplace_re(save, (PAT), (REP));             \
        if (cand && urlhealth(cand) == 200) {                     \
            free(best); best = cand; h = 200;                     \
        } else { free(cand); }                                    \
    } while (0)

    snprintf(p, sizeof p, "/archive/refs/tags/%s-v%s", nm, ver);
    snprintf(r, sizeof r, "/archive/refs/tags/v%s", ver);
    GH_TRY(p, r);                                                  /* L2640 */
    if (h != 200) {
        snprintf(p, sizeof p, "/archive/refs/tags/%s-%s", nm, ver);
        snprintf(r, sizeof r, "/archive/refs/tags/v%s", ver);
        GH_TRY(p, r);                                              /* L2647 */
    }
    if (h != 200) {
        snprintf(p, sizeof p, "/archive/refs/tags/%s-%s", nm, ver);
        snprintf(r, sizeof r, "/archive/refs/tags/%s", ver);
        GH_TRY(p, r);                                              /* L2654 (bare) */
    }
    if (h != 200) { char *vn = istr_replace_all(strdup(ver), "_", "."); GH_TRY(ver, vn); free(vn); }  /* L2662 */
    if (h != 200) { char *vn = istr_replace_all(strdup(ver), ".", "-"); GH_TRY(ver, vn); free(vn); }  /* L2669 */
    if (h != 200) { char *vn = istr_replace_all(strdup(ver), ".", "_"); GH_TRY(ver, vn); free(vn); }  /* L2676 */
    if (h != 200) {
        const char *d = strrchr(nm, '-');
        const char *nl = (d && d[1]) ? d + 1 : nm;
        snprintf(p, sizeof p, "/archive/refs/tags/%s-%s", nl, ver);
        snprintf(r, sizeof r, "/archive/refs/tags/v%s", ver);
        GH_TRY(p, r);                                             /* L2686 */
    }
#undef GH_TRY

    *out_health = h;
    return best;
}

/* M114 / PS L2710-2720: when a github Source0 has /archive/<name>- (NO
 * /refs/tags/) and 404s, PS rewrites the /<name>- segment to /refs/tags/
 * (then /refs/tags/v<ver> as a fallback) and adopts the variant that HEADs
 * 200. C mirrors that. Like gh_archive_tag_normalize, callers gate via
 * the per-spec allow-list so the broad form can't regress kubernetes/falco-
 * style detection-path shifts. Returns a heap-allocated string: the
 * rewritten URL when *out_health == 200, otherwise a copy of `save`. */
static char *gh_archive_no_refs_normalize(const char *save, const char *name,
                                          const char *version, int *out_health)
{
    const char *nm  = name    ? name    : "";
    const char *ver = version ? version : "";
    char *best = strdup(save);
    int h = 0;
    char pat[768];

    /* PS L2715: /archive/<name>- -> /archive/refs/tags/ */
    snprintf(pat, sizeof pat, "/archive/%s-", nm);
    char *cand = ireplace_re(save, pat, "/archive/refs/tags/");
    if (cand && urlhealth(cand) == 200) { free(best); best = cand; h = 200; }
    else free(cand);

    /* PS L2723: /archive/<name>- -> /archive/refs/tags/v */
    if (h != 200) {
        cand = ireplace_re(save, pat, "/archive/refs/tags/v");
        if (cand && urlhealth(cand) == 200) { free(best); best = cand; h = 200; }
        else free(cand);
    }

    *out_health = h;
    return best;
}

/* M120 / PS L2766-2790 (else branch of the github URL detection chain):
 * when a github Source0 has NEITHER /archive/refs/tags/ NOR /archive/<name>-
 * NOR /releases/download/ but DOES contain the literal "<name>-<ver>"
 * (typical when the spec's Source0 is just "%{name}-%{version}.tar.gz" and
 * the URL-prefix injection at source0_substitute concatenates a URL with
 * no trailing slash), PS rewrites "<name>-<ver>" anywhere in the URL to
 * "/archive/refs/tags/v<ver>", then to "/archive/refs/tags/<ver>" as a
 * fallback. The slash reappears in the rewritten URL as a side effect
 * (the URL prefix "github.com/<owner>/<repo>" was concatenated without
 * its trailing slash, and the rewrite happens to put the slash back).
 * Allow-listed via gh_no_archive_normalize_allowed. */
static char *gh_no_archive_normalize(const char *save, const char *name,
                                     const char *version, int *out_health)
{
    const char *nm  = name    ? name    : "";
    const char *ver = version ? version : "";
    char *best = strdup(save);
    int h = 0;
    char pat[768];

    /* PS L2773-2774: <name>-<ver> -> /archive/refs/tags/v<ver> */
    snprintf(pat, sizeof pat, "%s-%s", nm, ver);
    char rep[768];
    snprintf(rep, sizeof rep, "/archive/refs/tags/v%s", ver);
    char *cand = ireplace_re(save, pat, rep);
    if (cand && urlhealth(cand) == 200) { free(best); best = cand; h = 200; }
    else free(cand);

    /* PS L2781-2782: <name>-<ver> -> /archive/refs/tags/<ver> */
    if (h != 200) {
        snprintf(rep, sizeof rep, "/archive/refs/tags/%s", ver);
        cand = ireplace_re(save, pat, rep);
        if (cand && urlhealth(cand) == 200) { free(best); best = cand; h = 200; }
        else free(cand);
    }

    *out_health = h;
    return best;
}

/* PS L4848-4931: construct the update URL when an update is available but no
 * URL was set during detection. Mirrors PS exactly — operates on the resolved
 * Source0 (== PS $Source0Save / $Source0, funet-mirrored), applies the per-spec
 * rebuilds (libqmi/gtest/icu/libtirpc) and extension preservation, then tries
 * the version + versionshort cascade in dot / underscore / dash spellings and
 * a raw-template re-substitution, then the M81 archive-extension fallback.
 * Returns the urlhealth of the chosen URL: 200 -> *out_url set (heap); else the
 * last non-200 code with *out_url = NULL (caller emits the packaging warning).
 * Probes the network via urlhealth() — call only when allow_network. */
static int pr_build_update_url(pr_task_t *task, const char *source0_save,
                               const char *version, const char *update_avail,
                               char **out_url)
{
    *out_url = NULL;
    const char *spec = task && task->Spec ? task->Spec : "";
    char *ver = dup_or_empty(version);
    char *ua  = dup_or_empty(update_avail);
    char *s0  = dup_or_empty(source0_save);

    /* per-spec rebuilds (PS L4848-4861), in source order */
    if (spec_eq(spec, "libqmi.spec")) {
        char *n = NULL;
        if (asprintf(&n, "https://gitlab.freedesktop.org/mobile-broadband/"
                     "libqmi/-/archive/%s/libqmi-%s.tar.gz", ver, ver) >= 0) {
            free(s0); s0 = n;
        }
    }
    if (spec_eq(spec, "gtest.spec")) {
        char *nv = NULL, *nu = NULL;
        if (asprintf(&nv, "release-%s", ver) >= 0) { free(ver); ver = nv; }
        if (asprintf(&nu, "v%s", ua) >= 0)         { free(ua);  ua  = nu; }
    }
    if (spec_eq(spec, "icu.spec")) {
        char *uh = istr_replace_all(strdup(ua), ".", "-");
        char *uu = istr_replace_all(strdup(ua), ".", "_");
        char *n = NULL;
        if (asprintf(&n, "https://github.com/unicode-org/icu/releases/download/"
                     "release-%s/icu4c-%s-src.tgz", uh, uu) >= 0) {
            free(s0); s0 = n;
        }
        free(uh); free(uu);
    }
    if (spec_eq(spec, "libtirpc.spec")) {
        char *n = NULL;
        if (asprintf(&n, "https://downloads.sourceforge.net/project/libtirpc/"
                     "libtirpc/%s/libtirpc-%s.tar.bz2", ver, ver) >= 0) {
            free(s0); s0 = n;
        }
    }

    /* extension preservation (PS L4863-4866): if the ORIGINAL Source0 carried
     * a non-.tar.gz archive ext and the current s0 is .tar.gz, restore it.
     * Four independent guard-chained ifs (at most one fires). */
    if (strstr(source0_save, ".tar.bz2") && strstr(s0, ".tar.gz"))
        s0 = istr_replace_all(s0, ".tar.gz", ".tar.bz2");
    if (strstr(source0_save, ".tar.xz")  && strstr(s0, ".tar.gz"))
        s0 = istr_replace_all(s0, ".tar.gz", ".tar.xz");
    if (strstr(source0_save, ".tgz")     && strstr(s0, ".tar.gz"))
        s0 = istr_replace_all(s0, ".tar.gz", ".tgz");
    if (strstr(source0_save, ".zip")     && strstr(s0, ".tar.gz"))
        s0 = istr_replace_all(s0, ".tar.gz", ".zip");

    char *vshort = vmm(ver);                                /* PS L4868 */
    char *uashort = (strchr(ua, '.') != NULL) ? vmm(ua)    /* PS L4870-4874 */
                                              : dup_or_empty(ua);
    char *ua_us      = istr_replace_all(strdup(ua), ".", "_");
    char *ua_dash    = istr_replace_all(strdup(ua), ".", "-");
    char *uashort_us = istr_replace_all(strdup(uashort), ".", "_");

    char *url = NULL; int h = 0;

    /* A (L4876): s0, ver -> ua */
    url = ireplace_re(s0, ver, ua);
    h = urlhealth(url);
    /* Remember attempt A's url+health: on overall failure the caller needs
     * them to tell a transient network error (h==0, keep url, no warning)
     * apart from a real packaging change (clean 404, clear url + warn). */
    char *url_A = strdup(url); int h_A = h;
    /* B (L4880): chain versionshort -> uashort on A's url */
    if (h != 200) {
        char *t = ireplace_re(url, vshort, uashort); free(url); url = t;
        h = urlhealth(url);
    }
    /* C (L4884-4885): underscore ua, then versionshort */
    if (h != 200) {
        free(url); url = ireplace_re(s0, ver, ua_us);
        char *t = ireplace_re(url, vshort, uashort); free(url); url = t;
        h = urlhealth(url);
    }
    /* D (L4889-4890): underscore ua, underscore versionshort */
    if (h != 200) {
        free(url); url = ireplace_re(s0, ver, ua_us);
        char *t = ireplace_re(url, vshort, uashort_us); free(url); url = t;
        h = urlhealth(url);
    }
    /* E (L4894-4895): dash ua, then versionshort */
    if (h != 200) {
        free(url); url = ireplace_re(s0, ver, ua_dash);
        char *t = ireplace_re(url, vshort, uashort); free(url); url = t;
        h = urlhealth(url);
    }
    /* F (L4899-4902): raw template, dot ua */
    if (h != 200) {
        free(url);
        char *raw = dup_or_empty(task->Source0 ? task->Source0 : "");
        raw = istr_replace_all(raw, "%{name}", task->Name ? task->Name : "");
        raw = istr_replace_all(raw, "%{version}", ver);
        char *t1 = ireplace_re(raw, ver, ua);     free(raw);
        char *t2 = ireplace_re(t1, vshort, uashort); free(t1);
        url = t2; h = urlhealth(url);
    }
    /* G (L4906-4910): raw template, underscore then dot ua */
    if (h != 200) {
        free(url);
        char *raw = dup_or_empty(task->Source0 ? task->Source0 : "");
        raw = istr_replace_all(raw, "%{name}", task->Name ? task->Name : "");
        raw = istr_replace_all(raw, "%{version}", ver);
        char *t1 = ireplace_re(raw, ver, ua_us);  free(raw);
        char *t2 = ireplace_re(t1, ver, ua);       free(t1);
        char *t3 = ireplace_re(t2, vshort, uashort); free(t2);
        url = t3; h = urlhealth(url);
    }
    /* M81 archive-extension fallback (L4914-4924) */
    if (h != 200 && try_url_ext_fallback(&url) == 200) h = 200;

    free(ver); free(ua); free(s0);
    free(vshort); free(uashort); free(ua_us); free(ua_dash); free(uashort_us);

    if (h == 200) { free(url_A); *out_url = url; return 200; }
    /* All attempts failed. Return attempt-A's url + health so the caller can
     * preserve the transient (h==0) vs packaging-change (clean 404) split. */
    free(url);
    *out_url = url_A;
    return h_A;
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
    /* M145 (2026-06-06): treat empty-string env var the same as unset.
     * GitHub Actions workflow YAML cannot conditionally omit an env: entry,
     * so when sha_cache=false the workflow sets PR_SHA_CACHE="" -- but
     * getenv() returns "" (not NULL) for an empty-string-set env var, so
     * the old `getenv(...) == NULL` check let cache_file get computed and
     * later returned NULL inside pr_sha_of_url_cached, breaking the
     * live-download fallback. POSIX-conventional: empty == unset. */
    const char *e = getenv("PR_SHA_CACHE");
    if (e == NULL || e[0] == '\0') return NULL;
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

/* M90 / PS L 3368: the ftp.gnu.org/gnu/wget/ listing also hosts the separate
 * wget2 project (wget2-2.2.1.tar.gz, ...). Its "2.x" versions outrank wget's
 * 1.25.0 and win the version sort, so C reported "2-2.2.1" (wget2-2.2.1 with
 * "wget" stripped) instead of 1.25.0. PS drops any name containing "wget2-"
 * for wget.spec; mirror that. Once dropped, C detects 1.25.0 and funet_mirror
 * rewrites the gnu.org URL to the same FUNET path PS emits. */
static void drop_wget2_names(const char *spec, char **names, size_t n)
{
    if (!spec_eq(spec, "wget.spec")) return;
    for (size_t i = 0; i < n; i++) {
        if (names[i] == NULL) continue;
        if (strstr(names[i], "wget2-") != NULL) {
            free(names[i]); names[i] = NULL;
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
    /* M107: clone_root can contain MULTIPLE "photon-" segments — the
     * persistent cache layout (post ADR-0009 amendment) puts everything
     * under .../photon-upstreams/photon-<branch>/clones, so a leftmost
     * strstr matches the "photon-upstreams" parent and the substring after
     * it ("upstreams/...") never matches any branch prefix below → all
     * kernel-family specs fall through to the "6.1." default, which on
     * 3.0/4.0/common drops every candidate (kept=0 in PR_SCRAPE_DEBUG run
     * 26583592871). Find the LAST "photon-" instead. */
    const char *p = NULL;
    for (const char *q = strstr(clone_root, "photon-"); q; q = strstr(q + 1, "photon-")) {
        p = q;
    }
    if (p == NULL) return NULL;
    p += 7;  /* past "photon-" */
    if (strncmp(p, "3.0", 3) == 0)    return "4.19.";
    if (strncmp(p, "4.0", 3) == 0)    return "5.10.";
    if (strncmp(p, "common", 6) == 0) return "6.12.";
    return "6.1.";  /* 5.0 / 6.0 / master / dev / main */
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
    /* M100 / PS L 3296,3329 ($replace=@("Python-")): python2/python3 tarballs
     * are "Python-<ver>.tar.*"; strip the prefix so the version sorts. */
    else if (spec_eq(spec, "python2.spec"))           tok = "Python-";
    else if (spec_eq(spec, "python3.spec"))           tok = "Python-";
    /* M101 / PS L 4493 ($replace += "/wireguard-tools/snapshot/wireguard-
     * tools-"): the cgit tags page's snapshot hrefs basename to
     * "wireguard-tools-<ver>.tar.xz"; strip the prefix → version. */
    else if (spec_eq(spec, "wireguard-tools.spec"))   tok = "wireguard-tools-";
    /* M108 / PS L 4485 ($replace += "qemu-"): qemu-img scrapes
     * download.qemu.org and gets "qemu-<ver>.tar.xz" hrefs (apply_href_basename
     * has already removed any leading "/"). Strip the "qemu-" prefix so the
     * version passes the no-alpha post-filter. Mirrors the Q1 PS fix. */
    else if (spec_eq(spec, "qemu-img.spec"))          tok = "qemu-";
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
    int is_mozjs60 = spec_eq(spec, "mozjs60.spec");
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
        /* M103 / PS L3236-3237: mozjs60 pins the firefox-60 ESR series — keep
         * only "60."-bearing release dirs (60.0esr … 60.9.0esr) and strip the
         * "esr" suffix; the pipeline then picks 60.9.0 (the last 60 ESR) →
         * "(same version)". Other firefox versions are dropped here. */
        if (is_mozjs60) {
            if (strstr(names[i], "60.") == NULL) { free(names[i]); names[i] = NULL; continue; }
            names[i] = istr_replace_all(names[i], "esr", "");
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

/* M100 / PS L 3294-3336: python2/python3 two-level python.org listing.
 * dirname(Source0) is the CURRENT release's dir (.../ftp/python/3.7.5/),
 * which holds only that release — the newest release lives in a sibling
 * version directory. Scrape the parent index .../ftp/python/, pick the
 * highest <major>. version DIRECTORY (`2.` for python2, `3.` for python3),
 * then scrape that dir for the `Python-<ver>.tar.*` names. PS's do-until
 * retries the next-highest dir when the chosen one has no final tarball yet
 * (e.g. an empty pre-release dir); mirror that with a bounded drop-and-retry.
 * The returned tarball names run the standard pipeline — the `Python-` token
 * added in apply_generic_scrape_tokens strips the prefix. Returns the version
 * dir's tarball hrefs in *out_names (caller frees via pr_git_tags_free). */
/* PS L 3321-3332 retry condition: does this version dir's listing yield at
 * least one FINAL (non-pre-release) release after the standard reduction
 * (strip Python-/ext, keep has-digit, drop alpha-after-[pP]N)? A dir like
 * 3.15.0/ that holds only Python-3.15.0a1.tar.xz must be rejected so the
 * loop retries the next-highest dir (PS's `$replace += $NameLatest`). */
static int python_dir_yields_release(char **names, size_t n)
{
    char **probe = (char **)malloc((n ? n : 1) * sizeof *probe);
    if (probe == NULL) return 1;   /* OOM: accept rather than loop forever */
    size_t pc = 0;
    static const char *exts[] = {
        ".tar.gz", ".tar.xz", ".tar.bz2", ".tar.lz", ".tgz", NULL,
    };
    for (size_t i = 0; i < n; i++) {
        if (names[i] == NULL || strstr(names[i], ".tar.") == NULL) continue;
        char *t = istr_replace_all(dup_or_empty(names[i]), "Python-", "");
        if (t == NULL) continue;
        size_t ll = strlen(t);
        for (int e = 0; exts[e]; e++) {
            size_t el = strlen(exts[e]);
            if (ll >= el && strncasecmp(t + ll - el, exts[e], el) == 0) {
                t[ll - el] = '\0';
                break;
            }
        }
        probe[pc++] = t;
    }
    apply_name_post_filters(probe, pc);
    int ok = 0;
    for (size_t i = 0; i < pc; i++) {
        if (probe[i]) ok = 1;
        free(probe[i]);
    }
    free(probe);
    return ok;
}

static int python_dir_scrape(const char *spec, char ***out_names, size_t *out_n)
{
    *out_names = NULL;
    *out_n     = 0;
    const char *prefix    = spec_eq(spec, "python2.spec") ? "2." : "3.";
    const char *index_url = "https://www.python.org/ftp/python/";

    char **dirs = NULL;
    size_t nd   = 0;
    if (pr_scrape_listing(index_url, &dirs, &nd) != 0 || nd == 0) {
        pr_git_tags_free(dirs, nd);
        return -1;
    }
    /* basename + trailing-slash strip; keep only <prefix>* version dirs. */
    apply_href_basename(dirs, nd);
    for (size_t i = 0; i < nd; i++) {
        if (dirs[i] == NULL) continue;
        size_t L = strlen(dirs[i]);
        while (L && dirs[i][L - 1] == '/') dirs[i][--L] = '\0';
        if (strncmp(dirs[i], prefix, strlen(prefix)) != 0) {
            free(dirs[i]); dirs[i] = NULL;
        }
    }
    /* PS L 3315-3316: keep has-digit, drop alpha-after-[pP]N (pre-release
     * dirs like 3.15.0a1 fall out here). */
    apply_name_post_filters(dirs, nd);

    /* PS L 3297-3335 do-until: pick the highest dir, scrape it; if it has no
     * final tarball, drop it and retry the next-highest. Bounded to avoid an
     * unbounded loop when the host is misbehaving. */
    for (int attempt = 0; attempt < 8; attempt++) {
        char *latest = pr_get_latest_name(dirs, nd);
        if (latest == NULL || latest[0] == '\0') { free(latest); break; }

        char *dir_url = NULL;
        if (asprintf(&dir_url, "%s%s/", index_url, latest) < 0 || dir_url == NULL) {
            free(latest);
            break;
        }
        char **names = NULL;
        size_t n     = 0;
        int    ok    = (pr_scrape_listing(dir_url, &names, &n) == 0 && n > 0);
        free(dir_url);

        if (ok) {
            apply_href_basename(names, n);
            if (python_dir_yields_release(names, n)) {
                free(latest);
                *out_names = names;
                *out_n     = n;
                pr_git_tags_free(dirs, nd);
                return 0;
            }
        }
        pr_git_tags_free(names, n);
        /* drop the just-tried version and retry the next-highest. */
        for (size_t i = 0; i < nd; i++) {
            if (dirs[i] && strcmp(dirs[i], latest) == 0) { free(dirs[i]); dirs[i] = NULL; }
        }
        free(latest);
    }
    pr_git_tags_free(dirs, nd);
    return -1;
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


    /* L 4770: optional 'v' strip — strip a leading 'v' ONLY when it is a
     * version prefix (followed by a digit, e.g. "v1.2.3.tar.gz"). A 'v'
     * followed by a letter is part of a real word (versioningit,
     * virtualenv, valgrind) and must be preserved; a 'v' followed by '-'
     * is left for the L 4792 "v-" rule below. (M85: was `raw[1] != '-'`,
     * which mangled word-initial 'v' names — the PyPI sdist path now
     * surfaces such names so PS L 4969 must match this guard.) */
    if ((raw[0] == 'v' || raw[0] == 'V') && raw[1] >= '0' && raw[1] <= '9') {
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
                      const char                      *exclusion_list,
                      const char                      *working_dir)
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

    /* M106 / PS L 2376-2392, 3665-3679, 4020-4034: -UpstreamsExclusionList
     * short-circuit, SCOPED to the specs PS actually emits a minimal row
     * for. Empirically (vs PS snapshot 26500380639, m106 run 26559228021):
     *   raspberrypi-firmware → minimal row (col2 raw, col3..12 empty)
     *   chromium             → minimal row
     *   aufs-util / aufs-linux → PS still detects (col5 = 7.0 etc.)
     * So PS's exclusion-skip is NOT a blanket "exclusion = minimal". This
     * gate fires only for the two specs PS treats as minimal AND only when
     * the exclusion-list actually matches them (so flipping the user-supplied
     * `-UpstreamsExclusionList` to omit "firmware,chromium" reverts behaviour).
     * aufs-util/aufs-linux fall through unchanged. */
    if (exclusion_list && exclusion_list[0]
        && (spec_eq(task->Spec, "raspberrypi-firmware.spec")
            || spec_eq(task->Spec, "chromium.spec"))) {
        const pr_source0_lookup_t *r0 = lookup_row(lookup_table, task->Spec);
        if (r0 && r0->gitSource && r0->gitSource[0]) {
            char *repo_name = pr_extract_repo_name(r0->gitSource);
            if (repo_name) {
                int skip = pr_should_skip_clone(repo_name, exclusion_list);
                free(repo_name);
                if (skip) {
                    char *out = NULL;
                    if (asprintf(&out, "%s,%s,,,,,,%s,,,,",
                                 task->Spec,
                                 task->Source0 ? task->Source0 : "",
                                 task->Name    ? task->Name    : "") < 0) {
                        return NULL;
                    }
                    (void)clone_root;
                    return out;
                }
            }
        }
    }

    pr_state_t state;
    pr_state_init(&state);

    /* PS L 2140-2153: Source0Lookup CSV lookup. */
    const pr_source0_lookup_t *row = lookup_row(lookup_table, task->Spec);

    /* M118 / PS L 2396-2418: dtb-raspberrypi.spec is a special per-spec
     * override that PS sets up INLINE (no Source0Lookup row). The repo is
     * raspberrypi/linux.git with branch-specific gitBranch / replace
     * tokens (rpi-4.19.y → rpi-6.12.y). C had no equivalent, leaving
     * `row` NULL so the Phase 6d clone path never fired, col3/col5 stay
     * empty and the spec showed PS-only flagged on 6 branches. Synthesize
     * an in-memory lookup row keyed off the photonDir parsed out of
     * clone_root (".../<photonDir>/clones"). */
    static pr_source0_lookup_t dtb_rpi_row;
    static char dtb_branch_buf[32];
    static char dtb_replace_buf[32];
    if (row == NULL && spec_eq(task->Spec, "dtb-raspberrypi.spec")
        && clone_root && clone_root[0]) {
        const char *suffix = "/clones";
        size_t crl = strlen(clone_root);
        size_t sl  = strlen(suffix);
        if (crl > sl && strcmp(clone_root + crl - sl, suffix) == 0) {
            const char *end = clone_root + crl - sl;
            const char *start = end;
            while (start > clone_root && start[-1] != '/') start--;
            size_t plen = (size_t)(end - start);
            if (plen > 0 && plen < 32) {
                char photon_dir[32];
                memcpy(photon_dir, start, plen);
                photon_dir[plen] = '\0';

                const char *gbr = "rpi-6.12.y";
                const char *rep = "stable_";
                if      (strcmp(photon_dir, "photon-3.0") == 0) { gbr = "rpi-4.19.y"; rep = ""; }
                else if (strcmp(photon_dir, "photon-4.0") == 0) { gbr = "rpi-5.10.y"; rep = ""; }
                else if (strcmp(photon_dir, "photon-5.0") == 0) { gbr = "rpi-6.1.y";  rep = ""; }
                else if (strcmp(photon_dir, "photon-6.0") == 0) { gbr = "rpi-6.12.y"; rep = "rpi-6.12.y_"; }

                snprintf(dtb_branch_buf,  sizeof dtb_branch_buf,  "%s", gbr);
                snprintf(dtb_replace_buf, sizeof dtb_replace_buf, "%s", rep);

                memset(&dtb_rpi_row, 0, sizeof dtb_rpi_row);
                dtb_rpi_row.specfile       = (char *)"dtb-raspberrypi.spec";
                dtb_rpi_row.Source0Lookup  = (char *)"";
                dtb_rpi_row.gitSource      = (char *)"https://github.com/raspberrypi/linux.git";
                dtb_rpi_row.gitBranch      = dtb_branch_buf;
                dtb_rpi_row.customRegex    = (char *)"";
                dtb_rpi_row.replaceStrings = dtb_replace_buf;
                dtb_rpi_row.ignoreStrings  = (char *)"";
                dtb_rpi_row.Warning        = (char *)"";
                dtb_rpi_row.ArchivationDate= (char *)"";
                row = &dtb_rpi_row;
            }
        }
    }

    if (row && row->Source0Lookup && row->Source0Lookup[0] != '\0') {
        free(state.Source0);
        state.Source0 = dup_or_empty(row->Source0Lookup);
    } else {
        free(state.Source0);
        state.Source0 = dup_or_empty(task->Source0);
    }
    /* PS L 2152-2153: $Warning and $ArchivationDate are (re)initialised to ""
     * per CheckURLHealth task; PS NEVER reads the lookup row's Warning /
     * ArchivationDate columns back into the emitted values (verified: no
     * $currentTask.Warning / .ArchivationDate reads anywhere in PS). Those
     * columns hold only a legacy "1" Warning flag + a paired ArchivationDate
     * for 8 archived specs (dbxtool, dstat, kube-controllers, libcalico,
     * liota, openjdk10, photon-checksum-generator, python-m2r) — PS emits
     * neither. Emitted warnings + archivation dates come exclusively from the
     * per-spec override blocks / warning handlers below (e.g. cdrkit via M57).
     * Seeding them from the lookup (M89: an earlier misread of PS) leaked the
     * "1" flag into col11 (strict) and stale dates into col12. The lookup
     * ArchivationDate is still consulted as a deprecation flag via
     * row->ArchivationDate where genuinely needed. */
    free(state.Warning);         state.Warning = dup_or_empty("");
    free(state.ArchivationDate); state.ArchivationDate = dup_or_empty("");

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

    /* M102 / PS L 2627: if the modified Source0 STILL contains an unresolved
     * macro brace (a shell-style `${version}` the %{...} pass can't reach, or
     * an unmatched %{...}), PS reports the col4 sentinel
     * "substitution_unfinished". This is a col4 LABEL only — the detection
     * paths still run exactly as before (PS keeps e.g. nss's mozilla-detected
     * 3.124 alongside the sentinel). So `subst_unfinished` only (a) skips the
     * pointless urlhealth probe of a malformed URL and (b) overrides the col4
     * string; it must NOT gate the detection block, or it would drop a
     * legitimately-detected version (regression caught in run 26538995132).
     * Specs that genuinely detect nothing (dhcp, python3-msal,
     * openjdk8_aarch64) already emit empty col5 because health!=200 and no
     * eligible path fires — independent of this flag. A fully-resolved
     * Source0 has no brace, so working specs are byte-identical. */
    int subst_unfinished = (state.Source0 && strchr(state.Source0, '{') != NULL);

    /* M111: PS sets `$urlhealth = "200"` at multiple success-path set points
     * (L2531 / L3869 after a clone `git tag -l` succeeds, L4408 after a
     * generic scrape returns non-empty `$Names`). Those set points bypass
     * the L2627 substitution_unfinished else-branch, so PS emits col4=200
     * for libaio + apache-tomcat9/10/11/-9 despite their modified Source0
     * carrying a literal `{version}`/`%{_origname}` brace. C's M102
     * unconditionally emitted the sentinel, flagging cat2 on all 11 spec×
     * branch combinations (C-only parity gap). Mirror PS by tracking
     * whether the clone-tag or generic-scrape path produced tags; if so,
     * col4 emits the numeric "200" instead of the sentinel. moz_eligible /
     * gh_api / sf / etc. paths intentionally do NOT set the flag because
     * PS does not set `$urlhealth = "200"` there either (nss is the
     * counter-example — PS+C both emit substitution_unfinished, matched). */
    int health_overridden_200 = 0;

    /* Phase 5 urlhealth probe. Skipped offline so ctest stays hermetic. */
    int health = 0;
    const char *netenv = getenv("PR_TEST_NETWORK");
    int allow_network = (netenv && strcmp(netenv, "1") == 0);
    if (allow_network && !subst_unfinished) {
        health = urlhealth(state.Source0);
    }

    /* M96/M97 / PS L2630-2701: specs whose spec Source0 template is
     * .../archive/refs/tags/%{name}-%{version} but whose real github tags use
     * a different shape (valkey bare "9.1.0"; liblognorm "v2.1.0"; timescaledb
     * "<srcname>-X"; ...) — the templated Source0 404s, so the M91 cascade
     * builds the wrong tag URL -> empty col6/col10 + packaging warning.
     * Normalize the Source0 to the healthy real-tag form so the cascade then
     * builds the right latest-tag URL, matching PS. Gated to the proven-safe
     * allow-list (gh_tag_normalize_allowed) — NOT global — so it cannot touch
     * the redirect/detection-path specs the broad form regressed. Only fires
     * on health!=200, so specs whose Source0 already resolves are untouched. */
    if (allow_network && !subst_unfinished && health != 200 && gh_tag_normalize_allowed(task->Spec)
        && state.Source0
        && strstr(state.Source0, "github.com") != NULL
        && strstr(state.Source0, "/archive/refs/tags/") != NULL) {
        int nh = 0;
        char *norm = gh_archive_tag_normalize(
            state.Source0, task->Name, state.version ? state.version : "", &nh);
        if (nh == 200) {
            free(state.Source0);
            state.Source0 = norm;
            health = 200;
        } else {
            free(norm);
        }
    }

    /* M114 / PS L2710-2720: sibling of the M96/M97 normalize above, for
     * github Source0 of the /archive/<name>-<ver>.tar.gz shape (NO
     * /refs/tags/). PS rewrites those to /archive/refs/tags/<ver> when
     * the original 404s, then to /v<ver>. Without this, specs like
     * logrotate (no Source0Lookup row, no gitSource → no clone path)
     * keep the broken templated URL and the M91 cascade emits empty
     * col6/col10 + packaging warning. Allow-listed via
     * gh_archive_no_refs_normalize_allowed; only fires on health!=200. */
    if (allow_network && !subst_unfinished && health != 200
        && gh_archive_no_refs_normalize_allowed(task->Spec)
        && state.Source0
        && strstr(state.Source0, "github.com") != NULL
        && strstr(state.Source0, "/archive/") != NULL
        && strstr(state.Source0, "/refs/tags/") == NULL) {
        int nh = 0;
        char *norm = gh_archive_no_refs_normalize(
            state.Source0, task->Name, state.version ? state.version : "", &nh);
        if (nh == 200) {
            free(state.Source0);
            state.Source0 = norm;
            health = 200;
        } else {
            free(norm);
        }
    }

    /* M120 / PS L2766-2790: when a github Source0 has NEITHER /archive/
     * NOR /releases/ — i.e. the URL is the bare URL-prefix-injected form
     * "<host>/<owner>/<repo><name>-<ver>.tar.gz" (cbindgen + similar
     * specs whose spec Source0 is just "%{name}-%{version}.tar.gz" and
     * whose URL field has no trailing slash) — PS rewrites "<name>-<ver>"
     * anywhere in the URL to "/archive/refs/tags/v<ver>" then to
     * "/archive/refs/tags/<ver>". Allow-listed via
     * gh_no_archive_normalize_allowed (currently cbindgen only). */
    if (allow_network && !subst_unfinished && health != 200
        && gh_no_archive_normalize_allowed(task->Spec)
        && state.Source0
        && strstr(state.Source0, "github.com") != NULL
        && strstr(state.Source0, "/archive/") == NULL
        && strstr(state.Source0, "/releases/") == NULL) {
        int nh = 0;
        char *norm = gh_no_archive_normalize(
            state.Source0, task->Name, state.version ? state.version : "", &nh);
        if (nh == 200) {
            free(state.Source0);
            state.Source0 = norm;
            health = 200;
        } else {
            free(norm);
        }
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
                        /* M111: mirror PS L2531/L3869 — successful `git
                         * tag -l` sets `$urlhealth = "200"` before any
                         * version compare.
                         * M116: also mirror that into the in-memory
                         * `health` so downstream consumers (L2828 clear
                         * logic, gate checks) see the PS-equivalent state. */
                        health_overridden_200 = 1;
                        health = 200;
                        /* M117 / PS L 2546-2555: openjdk11/17/21 use the
                         * dedicated Get-HighestJdkVersion routine on the
                         * RAW tag list (before the M16/M19/M21/M22
                         * pipeline), because the Source0Lookup row's
                         * replaceStrings = "jdk-11" / "jdk-17" / "jdk-21"
                         * would otherwise strip the major-version prefix
                         * from "jdk-11.0.32+2" → ".0.32+2" with a leading
                         * dot, and pr_get_latest_name would pick the wrong
                         * tag. PS sets $Names=$null after the call to
                         * bypass the generic pipeline; C does the same via
                         * `skip_generic_pipeline`. */
                        char *latest_jdk = NULL;
                        int   skip_generic_pipeline = 0;
                        if (spec_eq(task->Spec, "openjdk11.spec")) {
                            latest_jdk = pr_get_highest_jdk_version(names, n, 11, "jdk-11");
                            skip_generic_pipeline = 1;
                        } else if (spec_eq(task->Spec, "openjdk17.spec")) {
                            latest_jdk = pr_get_highest_jdk_version(names, n, 17, "jdk-17");
                            skip_generic_pipeline = 1;
                        } else if (spec_eq(task->Spec, "openjdk21.spec")) {
                            latest_jdk = pr_get_highest_jdk_version(names, n, 21, "jdk-21");
                            skip_generic_pipeline = 1;
                        }
                        /* Apply replaceStrings from Source0Lookup row
                         * (PS L 2151). For clang/llvm specs this
                         * strips the `llvmorg-` prefix off tag names
                         * so version compare sees "22.1.5" not
                         * "llvmorg-22.1.5". Skipped for openjdk11/17/21
                         * via M117. */
                        if (!skip_generic_pipeline)
                            apply_replace_strings(names, n, row->replaceStrings);
                        char *latest = NULL;
                        if (skip_generic_pipeline) {
                            /* M117: openjdk pipeline already produced
                             * latest_jdk against the raw tag list. */
                            latest = latest_jdk;
                            latest_jdk = NULL;
                        } else {
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
                            latest = pr_get_latest_name(names, n);
                        }
                        free(latest_jdk);                /* in case set but not used */
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

                                /* M91 (PS L4848-4931): multi-attempt UpdateURL
                                 * construction — version/versionshort cascade in
                                 * dot/underscore/dash spellings + raw-template
                                 * rebuild + M81 ext-fallback, operating on the
                                 * resolved state.Source0. Replaces the former
                                 * single-attempt build (deferred-M18). */
                                char *built = NULL;
                                int h = pr_build_update_url(
                                            task, state.Source0 ? state.Source0 : "",
                                            state.version ? state.version : "",
                                            latest, &built);
                                /* M94 / PS L4853: gtest reports col5 with the
                                 * leading 'v' (PS mutates $UpdateAvailable in
                                 * place). col6/col10 already carry the 'v' via
                                 * the cascade; mirror it into col5. gtest-only. */
                                if (spec_eq(task->Spec, "gtest.spec")) {
                                    char *t = NULL;
                                    if (asprintf(&t, "v%s", latest) >= 0) {
                                        free(state.UpdateAvailable);
                                        state.UpdateAvailable = t;
                                    }
                                }
                                free(state.UpdateURL);
                                free(state.HealthUpdateURL);
                                if (h == 200) {
                                    state.UpdateURL = built;
                                    state.HealthUpdateURL = dup_or_empty("200");
                                } else if (h == 0) {
                                    /* Transient network error (not a 404): keep
                                     * the built URL, report health 0, no warning
                                     * — preserves prior cold-cache resilience. */
                                    state.UpdateURL = built;
                                    state.HealthUpdateURL = dup_or_empty("0");
                                } else {
                                    /* Clean failure: emit packaging warning,
                                     * clear UpdateURL + HealthUpdateURL (PS
                                     * L4925-4930). */
                                    free(built);
                                    state.UpdateURL = dup_or_empty("");
                                    state.HealthUpdateURL = dup_or_empty("");
                                    free(state.Warning);
                                    state.Warning = dup_or_empty(
                                        "Warning: Manufacturer may changed version packaging format.");
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
     * downstream pr_spec_warning() step. PS mirrors this block verbatim.
     *
     * M80: consult PyPI for EVERY python-* spec that is not deprecated, not
     * just github-sourced ones. A python package is on PyPI regardless of what
     * its Source0/Source0Lookup points at (pythonhosted-direct, a sourceforge
     * mirror, github, …), and the generic scraper can't enumerate most of
     * those, leaving them in cat 6. The dual-source max keeps the higher of the
     * already-detected version and PyPI, so correctly-detecting specs are
     * unaffected; PyPI-only/scrape-failed ones get filled. (The ~552 pinned
     * python subreleases short-circuit earlier and never reach here.) */
    if (allow_network
        && task->Spec && strncmp(task->Spec, "python-", 7) == 0
        && (state.ArchivationDate == NULL || state.ArchivationDate[0] == '\0')) {
        /* M89: gate on state.ArchivationDate, NOT row->ArchivationDate. PS
         * L4572 gates on its local $ArchivationDate, which is "" for every
         * python-* spec at this point (PS never seeds it from the lookup), so
         * PS queries PyPI for ALL python specs. Gating on the lookup column
         * (row->ArchivationDate) wrongly suppressed the query for the one
         * python spec carrying a lookup ArchivationDate (python-m2r), leaving
         * its col6/col10 on the github URL instead of PyPI's pythonhosted
         * sdist. state.ArchivationDate is "" here (M57 overrides run later),
         * mirroring PS exactly. */

        const char *cur = state.version ? state.version : "";
        /* M143: track whether the PyPI branch below adopts a new
         * UpdateURL / UpdateDownloadName. When set, the col9 SHA
         * computed at L2128 (against the github-tag-path URL and
         * dlname) is now stale and must be recomputed against the
         * new PyPI sdist after this block closes. PS computes col9
         * against the final UpdateDownloadFile, so this matches. */
        int pypi_adopted = 0;
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
                    if (sname && sname[0]) {
                        /* Raw PyPI sdist filename; PS uses $sdist.filename
                         * verbatim too, so col 10 stays byte-identical. (M88:
                         * set here, inside the surl block — `surl` is nulled
                         * above, so a later `if (surl ...)` guard would never
                         * fire and the udn would wrongly stay empty.) */
                        free(state.UpdateDownloadName); state.UpdateDownloadName = sname; sname = NULL;
                        pypi_adopted = 1;  /* M143: SHA needs recompute */
                    }
                    if (state.Warning && strstr(state.Warning, "packaging format") != NULL) {
                        free(state.Warning); state.Warning = dup_or_empty("");
                    }
                } else {
                    /* M86/M87: PyPI is newest but ships NO sdist (wheels-only,
                     * e.g. pyvmomi 9.1.0.0) and github has no tag for this
                     * version (pp > gh_latest). PS bumps UpdateAvailable, then
                     * rebuilds the download URL by substituting the new version
                     * into Source0 (PS L4895-4910); with no github tag it 404s,
                     * the M81 ext-fallback fails, and PS L4927-4930 emits the
                     * packaging-format warning with empty url. The git-tag path
                     * here already built a github URL for the OLDER version;
                     * clear it and emit the same warning to match PS exactly. */
                    free(state.UpdateURL); state.UpdateURL = dup_or_empty("");
                    free(state.HealthUpdateURL); state.HealthUpdateURL = dup_or_empty("");
                    free(state.UpdateDownloadName); state.UpdateDownloadName = dup_or_empty("");
                    free(state.Warning);
                    state.Warning = strdup("Warning: Manufacturer may changed version packaging format.");
                }
            } else if (gh_latest != NULL
                       && pr_version_compare(pp, gh_latest) == 0
                       && pp_gt_cur) {
                /* PyPI lists this SAME update version. Adopt PyPI's sdist URL +
                 * filename (canonical, hash-stable) regardless of whether the
                 * git path already built a github URL. This is REQUIRED for
                 * PS parity: PS's dual-source block runs before its URL-build,
                 * so $UpdateURL is empty there and its repair branch always
                 * fires -> PS emits the PyPI sdist for python updates. C builds
                 * the github URL first, so gating on "UpdateURL empty" made C
                 * keep the github URL -> ~104 col6/col10 strict diffs/branch.
                 * Dropping that gate aligns C with PS (and clears any obsolete
                 * packaging-format warning). */
                if (surl && surl[0]) {
                    free(state.UpdateURL); state.UpdateURL = surl; surl = NULL;
                    int h = urlhealth(state.UpdateURL);
                    char b[16]; snprintf(b, sizeof b, "%d", h);
                    free(state.HealthUpdateURL); state.HealthUpdateURL = strdup(b);
                }
                if (sname && sname[0]) {
                    free(state.UpdateDownloadName); state.UpdateDownloadName = sname; sname = NULL;
                    pypi_adopted = 1;  /* M143: SHA needs recompute */
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

        /* M143 (2026-06-05): when the PyPI block adopted a new
         * UpdateURL + UpdateDownloadName (overriding the github tag
         * path's URL/dlname), the col9 SHA computed at L2128 against
         * the github path's URL is now stale -- it points at a
         * different artefact than col6 and col10 advertise. PS
         * computes col9 against the final UpdateDownloadFile, so the
         * equivalent in C is to recompute SHA against the new
         * UpdateURL with the new UpdateDownloadName as cache key.
         *
         * Empirically observed on PS 27026736948 / C 27029718601:
         * 572 python-* both-differ rows where PS hashed the
         * pythonhosted sdist bytes (cache-matching) and C still
         * carried the github stable-asset SHA from the L2128 path.
         * Closes that cluster. Non-python specs are unaffected --
         * pypi_adopted is 0 by default and only the python PyPI
         * branch sets it. */
        if (pypi_adopted && state.UpdateURL && state.UpdateURL[0]
            && state.UpdateDownloadName && state.UpdateDownloadName[0]) {
            pr_sha_alg_t alg = PR_SHA512;
            for (size_t li = 0; li < task->content_lines; li++) {
                const char *line = task->content[li];
                if (line == NULL) continue;
                if (strstr(line, "%define sha1")   != NULL) { alg = PR_SHA1;   break; }
                if (strstr(line, "%define sha256") != NULL) { alg = PR_SHA256; break; }
                if (strstr(line, "%define sha512") != NULL) { alg = PR_SHA512; break; }
            }
            char *cache_file_py = col9_cache_path(
                clone_root, state.UpdateDownloadName);
            char *hex_py = pr_sha_of_url_cached(alg, state.UpdateURL, cache_file_py);
            if (hex_py) { free(state.SHAValue); state.SHAValue = hex_py; }
            free(cache_file_py);
        }
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
    /* M92 / PS L 2786-2849: ANY other github.com Source0 with no lookup
     * gitSource (and not one of the curated HTML tags-page specs above) is
     * detected via the github JSON API — /repos/<o>/<r>/tags for an /archive/
     * URL, /releases for a /releases/download/ URL. Closes the ~26-spec/branch
     * "no-gitSource github" gap (dhcpcd, libpng, hwdata, valkey, squid, the
     * timescaledb/python3 families, ...) that C previously left empty. */
    int gh_api_eligible = state.Source0
                          && pr_github_api_eligible_source0(state.Source0)
                          && (row == NULL || row->gitSource == NULL
                              || row->gitSource[0] == '\0')
                          && !pr_github_is_html_tags_spec(task->Spec);
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
    /* M100 / PS L 3294-3336: python2/python3 scrape the python.org parent
     * index for the highest version DIRECTORY, then that dir for the tarball
     * — dirname(Source0) is only the current release's dir. Admitted like the
     * moz/ao index scrapers (independent of file health). */
    int python_eligible = (spec_eq(task->Spec, "python2.spec")
                           || spec_eq(task->Spec, "python3.spec"))
                          && (row == NULL || row->gitSource == NULL
                              || row->gitSource[0] == '\0');
    /* M93 / PS L4332: generic listing fallback. PS's final detection branch
     * fires when the PARENT directory of Source0 is reachable
     * (urlhealth(dirname)==200), not the exact file — so specs whose file
     * 404'd because the old version was pruned upstream (libsodium, ebtables,
     * lasso, libmnl, ...) still get their release directory scraped. C
     * previously required the exact file to be 200, leaving them empty. Probe
     * the parent dir only when no other path is eligible, to avoid an extra
     * HEAD per spec. */
    int parentdir_eligible = 0;
    if (allow_network && health != 200 && state.Source0 && state.Source0[0]
        && !sf_eligible && !cpan_eligible && !gh_eligible && !gh_api_eligible
        && !ao_eligible && !moz_eligible && !jsonc_eligible && !gnome_eligible
        && !python_eligible
        && atom_url == NULL
        && (row == NULL || row->gitSource == NULL || row->gitSource[0] == '\0')
        && (state.UpdateAvailable == NULL || state.UpdateAvailable[0] == '\0')) {
        char *pd = dup_or_empty(state.Source0);
        char *ls = strrchr(pd, '/');
        if (ls && ls != pd) {
            ls[1] = '\0';   /* keep trailing slash (dir-listing semantics) */
            if (urlhealth(pd) == 200) parentdir_eligible = 1;
        }
        free(pd);
    }
    /* M105 / PS L 4490-4508: skip update-detection for VMware-internal
     * Source0 specs. PS emits the "Info: Source0 contains a VMware internal
     * url address." warning and leaves col5/6 empty by design. C previously
     * still ran detection here, which was masked only because the listing
     * (packages.vmware.com/photon_sources/) overflowed the 1MiB scrape body
     * cap. Gate explicitly so the cap value can be raised safely (M104). */
    if (allow_network && !pr_spec_is_vmware_internal(task->Spec)
        && (health == 200 || sf_eligible || cpan_eligible || gh_eligible || gh_api_eligible || ao_eligible || moz_eligible || jsonc_eligible || gnome_eligible || python_eligible || parentdir_eligible)
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
        } else if (gh_api_eligible) {
            /* M92 / PS L2786-2849: github JSON API. Names are clean tag/
             * release names, so (like the HTML tags page) they bypass the M23
             * HTML-href pre-filter via used_gh. */
            char **gnames = NULL; size_t gn = 0;
            if (pr_github_api_names(state.Source0, getenv("GITHUB_TOKEN"),
                                    &gnames, &gn) == 0 && gn > 0) {
                names = gnames; n = gn; scrape_ok = 1; used_gh = 1;
            } else {
                free(gnames);
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
        } else if (python_eligible) {
            /* M100 / PS L 3294-3336: two-level python.org dir scrape. Returns
             * Python-<ver>.tar.* hrefs from the highest version dir; the names
             * run the standard pipeline (M23 keep-.tar. + the "Python-" token
             * in apply_generic_scrape_tokens strip the prefix/extension). */
            scrape_ok = (python_dir_scrape(task->Spec, &names, &n) == 0);
        } else if (atom_url != NULL) {
            scrape_ok = (pr_scrape_atom_feed(atom_url, &names, &n) == 0);
            used_atom = 1;
        } else {
            scrape_ok = (pr_scrape_listing(parent, &names, &n) == 0);
            /* M54: reduce raw hrefs to their last path segment so
             * root-relative / absolute listing links (e.g. curl.se's
             * "download/curl-8.20.0.tar.xz") parse like bare basenames. */
            if (scrape_ok) apply_href_basename(names, n);
            /* M111: mirror PS L4408 — once the generic-else scrape
             * returns non-empty hrefs, PS sets `$urlhealth = "200"`
             * (bypassing L2627 substitution_unfinished). Applies only to
             * this generic branch; the _eligible branches above (moz,
             * gh, sf, ao, …) have their own per-path PS behaviour.
             * M116: also mirror into `health` (see clone-tag site). */
            if (scrape_ok && n > 0) { health_overridden_200 = 1; health = 200; }
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
            /* M109: apply the M28 per-spec drop-substring table to scrape-path
             * candidates too. Originally wired only on the clone path (Phase
             * 6d, L1722), but specs without a Source0Lookup row reach detection
             * via the gh_api / scrape branches and so missed the filter —
             * e.g. alternatives.spec, whose `r1-` chkconfig CVS tags need
             * dropping so version-compare picks the proper `1.33`. */
            pr_apply_per_spec_drop_substrings(task->Spec, names, n);
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
            /* M90 / PS L 3368: drop wget2-* before token processing so the
             * wget version sort ignores the co-hosted wget2 project. */
            drop_wget2_names(task->Spec, names, n);
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
                    /* M91 (PS L4848-4931): multi-attempt UpdateURL cascade on
                     * the resolved (funet-mirrored) state.Source0 — version/
                     * versionshort in dot/underscore/dash spellings + raw-
                     * template rebuild + M81 ext-fallback. Replaces the former
                     * single substitute (deferred-M18). */
                    char *built = NULL;
                    int h = pr_build_update_url(
                                task, state.Source0 ? state.Source0 : "",
                                state.version ? state.version : "",
                                latest, &built);
                    if (built == NULL) built = dup_or_empty("");
                    /* M94 / PS L4853: gtest reports col5 with the leading 'v'
                     * (PS mutates $UpdateAvailable in place). col6/col10 carry
                     * the 'v' via the cascade; mirror it into col5. gtest-only.
                     * gtest reaches detection via the HTML tags-page scrape, so
                     * the mutation belongs here (the git-tag site mirrors it). */
                    if (spec_eq(task->Spec, "gtest.spec")) {
                        char *t = NULL;
                        if (asprintf(&t, "v%s", latest) >= 0) {
                            free(state.UpdateAvailable);
                            state.UpdateAvailable = t;
                        }
                    }
                    /* M46: apparmor launchpad series-dir fixup (idempotent once
                     * the versionshort cascade has set the series dir). */
                    if (h == 200 && built[0] && spec_eq(task->Spec, "apparmor.spec"))
                        built = apparmor_series_fixup(built, latest);
                    free(state.UpdateURL);
                    state.UpdateURL = built;
                    free(state.HealthUpdateURL);
                    if (h != 0 && h != 200) {
                        /* Clean failure (PS L4925-4930): packaging warning. */
                        free(state.Warning);
                        state.Warning = dup_or_empty(
                            "Warning: Manufacturer may changed version packaging format.");
                        free(state.UpdateURL);
                        state.UpdateURL = dup_or_empty("");
                        state.HealthUpdateURL = dup_or_empty("");
                    } else {
                        /* h==200, or h==0 transient (keep url, no warning). */
                        char buf[16];
                        snprintf(buf, sizeof buf, "%d", h);
                        state.HealthUpdateURL = strdup(buf);
                        if (state.UpdateURL && state.UpdateURL[0]) {
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
     *
     * M144 (2026-06-05): col9 was previously left empty here under the
     * (incorrect) assumption that col9 was soft in the parity verdict.
     * col9 IS strict (ADR-0006), and PS DOES compute it for these specs
     * via Get-FileHashWithRetry against the pinned UpdateDownloadFile.
     * That left ~46-98 PS-only col9 rows (cdrkit, mpc, sendmail, runit,
     * vsftpd, python-daemon, python-Js2Py, python-ruamel-yaml, etc.) in
     * the residual gap. Below we compute SHA via the standard
     * cache-aware pipeline used by the github-tag / scraper / PyPI paths,
     * so PS-preserved cache bytes flow into col9 here too. */
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
            /* M144: compute col9 via the standard cache-aware pipeline so
             * PS-preserved cache bytes flow into the hardcoded-override
             * row too. Uses the same %define-sha1/256/512 detection
             * pattern as the github-tag / scraper / PyPI paths. */
            if (state.UpdateURL && state.UpdateURL[0]
                && state.UpdateDownloadName && state.UpdateDownloadName[0]) {
                pr_sha_alg_t alg = PR_SHA512;
                for (size_t li = 0; li < task->content_lines; li++) {
                    const char *line = task->content[li];
                    if (line == NULL) continue;
                    if (strstr(line, "%define sha1")   != NULL) { alg = PR_SHA1;   break; }
                    if (strstr(line, "%define sha256") != NULL) { alg = PR_SHA256; break; }
                    if (strstr(line, "%define sha512") != NULL) { alg = PR_SHA512; break; }
                }
                char *cache_file_hc = col9_cache_path(
                    clone_root, state.UpdateDownloadName);
                char *hex_hc = pr_sha_of_url_cached(alg, state.UpdateURL, cache_file_hc);
                if (hex_hc) { free(state.SHAValue); state.SHAValue = hex_hc; }
                free(cache_file_hc);
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

    /* M122 / M124 / PS L 5219-5222: when an update was detected AND the
     * candidate URL HEAD'd 200, PS calls ModifySpecFile to rewrite the
     * spec file under SPECS_NEW/<Name>/. C mirrors that under
     * SPECS_NEW_C (parallel dir so PS's authoritative output stays
     * byte-stable for the 90-day-green journal). Gated by env var
     * PR_MODIFY_SPEC — default OFF for parity-safe rollout.
     *
     * M124: `working_dir` carries the operator's --workingDir (root of
     * the photon-<branch>/SPECS trees) directly. Earlier M122 tried to
     * derive it from clone_root but parity-reconstruct.sh puts the
     * SPECS trees under <WDIR>/photon-<branch>/ while the upstream
     * clones live under <WDIR>/photon-upstreams/photon-<branch>/clones
     * — those roots differ, so the derivation produced the wrong path
     * and modify_spec couldn't find the source spec file. The photonDir
     * still comes from clone_root because that's where the per-branch
     * leaf is unambiguous. */
    if (getenv("PR_MODIFY_SPEC") != NULL
        && state.HealthUpdateURL && strcmp(state.HealthUpdateURL, "200") == 0
        && state.UpdateAvailable && state.UpdateAvailable[0]
        && strstr(state.UpdateAvailable, "Warning:") == NULL
        && strstr(state.UpdateAvailable, "(same version)") == NULL
        && strstr(state.UpdateAvailable, "Info:") == NULL
        && working_dir && working_dir[0]
        && clone_root && clone_root[0]) {
        const char *suffix = "/clones";
        size_t crl = strlen(clone_root);
        size_t sl  = strlen(suffix);
        if (crl > sl && strcmp(clone_root + crl - sl, suffix) == 0) {
            /* Extract photonDir from clone_root: "<...>/<photonDir>/clones". */
            const char *end = clone_root + crl - sl;
            const char *start = end - 1;
            while (start > clone_root && start[-1] != '/') start--;
            size_t pdlen = (size_t)(end - start);
            if (pdlen > 0 && pdlen < 64) {
                char photon_dir[64];
                memcpy(photon_dir, start, pdlen);
                photon_dir[pdlen] = '\0';
                /* Build sha_line — PS L 5198-5202. C's state.SHAValue
                 * holds the computed hash already. */
                const char *alg_name = "sha512";
                for (size_t li = 0; li < task->content_lines; li++) {
                    const char *cl = task->content[li];
                    if (cl == NULL) continue;
                    if (strstr(cl, "%define sha1")   != NULL) { alg_name = "sha1";   break; }
                    if (strstr(cl, "%define sha256") != NULL) { alg_name = "sha256"; break; }
                    if (strstr(cl, "%define sha512") != NULL) { alg_name = "sha512"; break; }
                }
                char *sha_line = NULL;
                if (state.SHAValue && state.SHAValue[0]) {
                    if (asprintf(&sha_line, "%%define %s %s=%s",
                                 alg_name, task->Name ? task->Name : "",
                                 state.SHAValue) < 0) sha_line = NULL;
                } else {
                    /* PS L 5218: " " sentinel when SHA computation failed. */
                    sha_line = strdup(" ");
                }
                int is_openjdk8 = spec_eq(task->Spec, "openjdk8.spec");
                /* netcat CommitId not yet plumbed through state; pass NULL
                 * for now. PS netcat-specific behaviour stays unchanged. */
                pr_modify_spec_file(task,
                                    working_dir,   /* source: SPECS tree */
                                    working_dir,   /* output: SPECS_NEW_C alongside SPECS */
                                    photon_dir,
                                    state.UpdateAvailable, sha_line,
                                    is_openjdk8, NULL, "SPECS_NEW_C");
                free(sha_line);
            }
        }
    }

    char *out = NULL;
    int rc;
    /* col4 UrlHealth: numeric HTTP status, or the "substitution_unfinished"
     * string sentinel (M102 / PS L2627) when the modified Source0 still
     * carries an unresolved macro brace. */
    char health_num[16];
    const char *health_field;
    if (subst_unfinished && !health_overridden_200) {
        health_field = "substitution_unfinished";
    } else if (health_overridden_200) {
        /* M111 + M115: PS L2531 (clone-tag success) and L4408 (generic-
         * scrape success) set `$urlhealth="200"` UNCONDITIONALLY — not
         * just when the modified Source0 had an unresolved macro brace.
         * M111 initially only honoured the override on the subst_unfinished
         * path; M115 extends it to the always-case so col4 mirrors PS for
         * every spec whose clone-tag/scrape detection succeeded even when
         * the templated Source0 URL itself 404s (containers-common,
         * gst-plugins-bad, libnss-ato, pcstat, re2, dtb-raspberrypi,
         * libmspack, etc.). */
        health_field = "200";
    } else {
        snprintf(health_num, sizeof health_num, "%d", health);
        health_field = health_num;
    }
    if (emit_multi_sha) {
        rc = asprintf(&out,
                     "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s",
                     task->Spec,
                     task->Source0 ? task->Source0 : "",
                     state.Source0,
                     health_field,
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
                     "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s",
                     task->Spec,                                      /*  1 Spec */
                     task->Source0 ? task->Source0 : "",              /*  2 Source0 original */
                     state.Source0,                                   /*  3 Source0 (rewritten) */
                     health_field,                                    /*  4 UrlHealth (0 offline) */
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
