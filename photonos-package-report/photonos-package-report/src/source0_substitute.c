/* source0_substitute.c — Source0 substitution core.
 *
 * 1:1 port of photonos-package-report.ps1 L 2172-2199. Order of
 * mutations on $Source0 is preserved verbatim (CLAUDE.md invariant #3).
 *
 * PS source (verbatim, comments included):
 *
 *     if ($Source0 -ilike '*%{url}*') { $Source0 = $Source0 -ireplace '%{url}',$currentTask.url }
 *     # add url path if necessary and possible
 *     if (($Source0 -notlike '*//*') -and ($currentTask.url -ne ""))
 *     {
 *         if (($currentTask.url -match '.tar.gz$') -or ($currentTask.url -match '.tar.xz$') -or ($currentTask.url -match '.tar.bz2$') -or ($currentTask.url -match '.tgz$'))
 *         {$Source0=$currentTask.url}
 *         else
 *         { $Source0 = [System.String]::Concat(($currentTask.url).Trimend('/'),$Source0) }
 *     }
 *     # replace variables
 *     $Source0 = $Source0 -ireplace '%{name}',$currentTask.Name
 *     $Source0 = $Source0 -ireplace '%{version}',$version
 *
 *     if ($Source0 -like '*{*')
 *     {
 *         if ($Source0 -ilike '*%{srcname}*')           { $Source0 = $Source0 -ireplace '%{srcname}',$currentTask.srcname }
 *         if ($Source0 -ilike '*%{gem_name}*')          { $Source0 = $Source0 -ireplace '%{gem_name}',$currentTask.gem_name }
 *         if ($Source0 -ilike '*%{extra_version}*')     { $Source0 = $Source0 -ireplace '%{extra_version}',$currentTask.extra_version }
 *         if ($Source0 -ilike '*%{main_version}*')      { $Source0 = $Source0 -ireplace '%{main_version}',$currentTask.main_version }
 *         if ($Source0 -ilike '*%{byaccdate}*')         { $Source0 = $Source0 -ireplace '%{byaccdate}',$currentTask.byaccdate }
 *         if ($Source0 -ilike '*%{dialogsubversion}*')  { $Source0 = $Source0 -ireplace '%{dialogsubversion}',$currentTask.dialogsubversion }
 *         if ($Source0 -ilike '*%{subversion}*')        { $Source0 = $Source0 -ireplace '%{subversion}',$currentTask.subversion }
 *         if ($Source0 -ilike '*%{upstreamversion}*')   { $Source0 = $Source0 -ireplace '%{upstreamversion}',$currentTask.upstreamversion }
 *         if ($Source0 -ilike '*%{libedit_release}*')   { $Source0 = $Source0 -ireplace '%{libedit_release}',$currentTask.libedit_release }
 *         if ($Source0 -ilike '*%{libedit_version}*')   { $Source0 = $Source0 -ireplace '%{libedit_version}',$currentTask.libedit_version }
 *         if ($Source0 -ilike '*%{ncursessubversion}*') { $Source0 = $Source0 -ireplace '%{ncursessubversion}',$currentTask.ncursessubversion }
 *         if ($Source0 -ilike '*%{cpan_name}*')         { $Source0 = $Source0 -ireplace '%{cpan_name}',$currentTask.cpan_name }
 *         if ($Source0 -ilike '*%{xproto_ver}*')        { $Source0 = $Source0 -ireplace '%{xproto_ver}',$currentTask.xproto_ver }
 *         if ($Source0 -ilike '*%{_url_src}*')          { $Source0 = $Source0 -ireplace '%{_url_src}',$currentTask._url_src }
 *         if ($Source0 -ilike '*%{_repo_ver}*')         { $Source0 = $Source0 -ireplace '%{_repo_ver}',$currentTask._repo_ver }
 *         if ($Source0 -ilike '*%{commit_id}*')         { $Source0 = $Source0 -ireplace '%{commit_id}',$currentTask.commit_id }
 *     }
 *
 * Implementation notes:
 *   - "$x -ilike '*Y*'" → strcasestr() != NULL
 *   - "$x -ireplace 'literal', value" → istr_replace_all() (the patterns
 *     contain only `%`, `{`, `}`, lowercase letters and `_` — none of
 *     these have regex quantifier semantics, so literal replace is
 *     byte-identical to .NET regex on these inputs).
 *   - "$x -match 'literal.tar.gz$'" → suffix string compare. PS treats
 *     '.' as regex metachar but the inputs (real tarball URLs) never
 *     contain non-period bytes at those positions, so suffix-match is
 *     byte-identical here.
 *   - "[string]::Concat(a.TrimEnd('/'), b)" → trim trailing '/' from a,
 *     then concatenate.
 *
 * The function MUTATES *source0 — caller's old pointer is freed by the
 * helpers; the new pointer lands in *source0.
 */
/* _GNU_SOURCE for strcasestr is provided via CMake target_compile_options;
 * do not redefine here. */
#include "pr_substitute.h"
#include "pr_strutil.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

/* Helper: PS -notlike '*X*' against a string == strcasestr returned NULL. */
static int icontains(const char *hay, const char *needle)
{
    if (hay == NULL || needle == NULL || needle[0] == '\0') return 0;
    return strcasestr(hay, needle) != NULL;
}

/* Helper: case-sensitive substring test (PS -like, not -ilike). */
static int contains(const char *hay, const char *needle)
{
    if (hay == NULL || needle == NULL || needle[0] == '\0') return 0;
    return strstr(hay, needle) != NULL;
}

/* Helper: case-sensitive suffix test, mirroring `$x -match 'literal$'`
 * for the four tarball extensions used at PS L 2176. */
static int has_suffix(const char *s, const char *suf)
{
    if (s == NULL || suf == NULL) return 0;
    size_t slen = strlen(s);
    size_t suflen = strlen(suf);
    return slen >= suflen && memcmp(s + slen - suflen, suf, suflen) == 0;
}

/* Helper: TrimEnd('/'). Returns a heap copy with all trailing '/' bytes
 * removed. */
static char *trim_trailing_slashes_dup(const char *s)
{
    if (s == NULL) s = "";
    size_t n = strlen(s);
    while (n > 0 && s[n - 1] == '/') n--;
    char *out = (char *)malloc(n + 1);
    if (!out) return NULL;
    memcpy(out, s, n);
    out[n] = '\0';
    return out;
}

/* Helper: concatenate two strings into a fresh heap buffer. */
static char *concat_dup(const char *a, const char *b)
{
    size_t la = a ? strlen(a) : 0;
    size_t lb = b ? strlen(b) : 0;
    char *out = (char *)malloc(la + lb + 1);
    if (!out) return NULL;
    if (la) memcpy(out, a, la);
    if (lb) memcpy(out + la, b, lb);
    out[la + lb] = '\0';
    return out;
}

/* Replace *source0 entirely with a new heap string, freeing the old. */
static int replace_pointer(char **source0, char *new_value)
{
    if (new_value == NULL) return -1;
    free(*source0);
    *source0 = new_value;
    return 0;
}

int pr_source0_substitute(pr_task_t *task, char **source0, const char *version)
{
    if (task == NULL || source0 == NULL || *source0 == NULL) return -1;

    const char *url = task->url ? task->url : "";

    /* PS L 2172: %{url} */
    if (icontains(*source0, "%{url}")) {
        *source0 = istr_replace_all(*source0, "%{url}", url);
        if (*source0 == NULL) return -1;
    }

    /* PS L 2174-2179: URL-prefix injection when Source0 lacks `//`. */
    if (!contains(*source0, "//") && url[0] != '\0') {
        if (has_suffix(url, ".tar.gz") || has_suffix(url, ".tar.xz") ||
            has_suffix(url, ".tar.bz2") || has_suffix(url, ".tgz")) {
            /* $Source0 = $currentTask.url */
            char *dup = (char *)malloc(strlen(url) + 1);
            if (!dup) return -1;
            memcpy(dup, url, strlen(url) + 1);
            if (replace_pointer(source0, dup) != 0) { free(dup); return -1; }
        } else {
            char *trimmed = trim_trailing_slashes_dup(url);
            if (!trimmed) return -1;
            char *combined = concat_dup(trimmed, *source0);
            free(trimmed);
            if (!combined) return -1;
            if (replace_pointer(source0, combined) != 0) { free(combined); return -1; }
        }
    }

    /* PS L 2182: %{name} */
    *source0 = istr_replace_all(*source0, "%{name}", task->Name ? task->Name : "");
    if (*source0 == NULL) return -1;

    /* PS L 2183: %{version} — note: PS local $version, not task->Version. */
    *source0 = istr_replace_all(*source0, "%{version}", version ? version : "");
    if (*source0 == NULL) return -1;

    /* PS L 2185-2202: gated by `*{*` (case-SENSITIVE -like, since `{` is
     * the only meta we care about and it has no case). */
    if (contains(*source0, "{")) {

        /* PS L 2187: %{srcname} */
        if (icontains(*source0, "%{srcname}")) {
            *source0 = istr_replace_all(*source0, "%{srcname}", task->srcname ? task->srcname : "");
            if (*source0 == NULL) return -1;
        }
        /* PS L 2188: %{gem_name} */
        if (icontains(*source0, "%{gem_name}")) {
            *source0 = istr_replace_all(*source0, "%{gem_name}", task->gem_name ? task->gem_name : "");
            if (*source0 == NULL) return -1;
        }
        /* PS L 2189: %{extra_version} */
        if (icontains(*source0, "%{extra_version}")) {
            *source0 = istr_replace_all(*source0, "%{extra_version}", task->extra_version ? task->extra_version : "");
            if (*source0 == NULL) return -1;
        }
        /* PS L 2190: %{main_version} */
        if (icontains(*source0, "%{main_version}")) {
            *source0 = istr_replace_all(*source0, "%{main_version}", task->main_version ? task->main_version : "");
            if (*source0 == NULL) return -1;
        }
        /* PS L 2191: %{byaccdate} */
        if (icontains(*source0, "%{byaccdate}")) {
            *source0 = istr_replace_all(*source0, "%{byaccdate}", task->byaccdate ? task->byaccdate : "");
            if (*source0 == NULL) return -1;
        }
        /* PS L 2192: %{dialogsubversion} */
        if (icontains(*source0, "%{dialogsubversion}")) {
            *source0 = istr_replace_all(*source0, "%{dialogsubversion}", task->dialogsubversion ? task->dialogsubversion : "");
            if (*source0 == NULL) return -1;
        }
        /* PS L 2193: %{subversion} */
        if (icontains(*source0, "%{subversion}")) {
            *source0 = istr_replace_all(*source0, "%{subversion}", task->subversion ? task->subversion : "");
            if (*source0 == NULL) return -1;
        }
        /* PS L 2194: %{upstreamversion} */
        if (icontains(*source0, "%{upstreamversion}")) {
            *source0 = istr_replace_all(*source0, "%{upstreamversion}", task->upstreamversion ? task->upstreamversion : "");
            if (*source0 == NULL) return -1;
        }
        /* PS L 2195: %{libedit_release} */
        if (icontains(*source0, "%{libedit_release}")) {
            *source0 = istr_replace_all(*source0, "%{libedit_release}", task->libedit_release ? task->libedit_release : "");
            if (*source0 == NULL) return -1;
        }
        /* PS L 2196: %{libedit_version} */
        if (icontains(*source0, "%{libedit_version}")) {
            *source0 = istr_replace_all(*source0, "%{libedit_version}", task->libedit_version ? task->libedit_version : "");
            if (*source0 == NULL) return -1;
        }
        /* PS L 2197: %{ncursessubversion} */
        if (icontains(*source0, "%{ncursessubversion}")) {
            *source0 = istr_replace_all(*source0, "%{ncursessubversion}", task->ncursessubversion ? task->ncursessubversion : "");
            if (*source0 == NULL) return -1;
        }
        /* PS L 2198: %{cpan_name} */
        if (icontains(*source0, "%{cpan_name}")) {
            *source0 = istr_replace_all(*source0, "%{cpan_name}", task->cpan_name ? task->cpan_name : "");
            if (*source0 == NULL) return -1;
        }
        /* PS L 2199: %{xproto_ver} */
        if (icontains(*source0, "%{xproto_ver}")) {
            *source0 = istr_replace_all(*source0, "%{xproto_ver}", task->xproto_ver ? task->xproto_ver : "");
            if (*source0 == NULL) return -1;
        }
        /* PS L 2200: %{_url_src} */
        if (icontains(*source0, "%{_url_src}")) {
            *source0 = istr_replace_all(*source0, "%{_url_src}", task->_url_src ? task->_url_src : "");
            if (*source0 == NULL) return -1;
        }
        /* PS L 2201: %{_repo_ver} */
        if (icontains(*source0, "%{_repo_ver}")) {
            *source0 = istr_replace_all(*source0, "%{_repo_ver}", task->_repo_ver ? task->_repo_ver : "");
            if (*source0 == NULL) return -1;
        }
        /* PS L 2202: %{commit_id} */
        if (icontains(*source0, "%{commit_id}")) {
            *source0 = istr_replace_all(*source0, "%{commit_id}", task->commit_id ? task->commit_id : "");
            if (*source0 == NULL) return -1;
        }
    }

    return 0;
}
