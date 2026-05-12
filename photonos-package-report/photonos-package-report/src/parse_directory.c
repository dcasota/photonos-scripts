/* parse_directory.c — ParseDirectory.
 * Mirrors photonos-package-report.ps1 L 247-379 line for line.
 *
 * PS source for reference (verbatim, first lines):
 *
 *   function ParseDirectory {
 *       param (
 *           [parameter(Mandatory = $true)]
 *           [string]$WorkingDir,
 *           [parameter(Mandatory = $true)]
 *           [string]$photonDir
 *       )
 *       $Packages = [System.Collections.Generic.List[PSCustomObject]]::new()
 *       $specsPath = Join-Path -Path $WorkingDir -ChildPath $photonDir | Join-Path -ChildPath "SPECS"
 *       Get-ChildItem -Path $specsPath -Recurse -File -Filter "*.spec" | ForEach-Object {
 *           ...
 *       }
 *       return $Packages
 *   }
 *
 * The C port mirrors:
 *   - $specsPath construction (Join-Path twice)
 *   - Get-ChildItem -Recurse -Filter "*.spec": scandir+alphasort,
 *     depth-first into subdirectories, files first within a directory
 *   - Per-file: Get-Content into a line array
 *   - $Name = Split-Path -Path $currentFile.DirectoryName -Leaf
 *   - $specRelPath = $currentFile.DirectoryName.Substring($specsPath.Length + 1)
 *   - $pathParts split + first numeric segment → $subRelease
 *   - Get-SpecValue calls for Release / Version / Source0 / URL
 *   - %{?dist}, %{?kat_build:.kat}, %{?kat_build:.%kat_build},
 *     %{?kat_build:.%kat}, %{?kernelsubrelease}, .%{dialogsubversion}
 *     string replacements on $release (verbatim from PS L 270-275)
 *   - "$version-$release" concat (PS L 279)
 *   - SHAName tri-branch (PS L 286-289)
 *   - 17 inline %define / %global captures with define-then-global override
 *     semantics for srcname, gem_name, commit_id; single-source for the rest
 *   - Append to Packages
 *
 * The catch{} block at PS L 374-376 is unreachable for the operations we
 * perform here in C (no equivalent of PS dynamic property access); we
 * preserve the spirit by skipping a spec whose Release: or Version: is
 * absent (the explicit `continue` branches at PS L 269 and L 278).
 */
/* _GNU_SOURCE is provided via target_compile_options(-D_GNU_SOURCE) in
 * CMakeLists.txt; do not redefine here. */
#include "photonos_package_report.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <limits.h>

/* ===== local helpers ================================================ */

static char *xstrdup(const char *s)
{
    if (s == NULL) s = "";
    size_t n = strlen(s);
    char *p = (char *)malloc(n + 1);
    if (!p) return NULL;
    memcpy(p, s, n + 1);
    return p;
}

/* "" → malloc'd zero-length string. Used when PS coerces $null to "". */
static char *empty_dup(void) { return xstrdup(""); }

/* String.Replace(a,b) on a heap-allocated `in`. Frees `in`, returns new
 * heap string. Replaces ALL non-overlapping occurrences. Case-SENSITIVE
 * because PS [string]::Replace is case-sensitive (PS L 270-275 uses it). */
static char *str_replace_all(char *in, const char *a, const char *b)
{
    if (in == NULL || a == NULL || a[0] == '\0') return in;
    size_t alen = strlen(a);
    size_t blen = b ? strlen(b) : 0;
    /* Count occurrences. */
    size_t count = 0;
    for (const char *p = in; (p = strstr(p, a)) != NULL; p += alen) count++;
    if (count == 0) return in;
    size_t in_len  = strlen(in);
    size_t out_len = in_len + count * (blen > alen ? blen - alen : 0)
                            - count * (alen > blen ? alen - blen : 0);
    char *out = (char *)malloc(out_len + 1);
    if (!out) return in;
    char *o = out;
    const char *cur = in;
    while (1) {
        const char *hit = strstr(cur, a);
        if (!hit) {
            size_t tail = strlen(cur);
            memcpy(o, cur, tail);
            o += tail;
            break;
        }
        memcpy(o, cur, (size_t)(hit - cur));
        o += hit - cur;
        if (blen) { memcpy(o, b, blen); o += blen; }
        cur = hit + alen;
    }
    *o = '\0';
    free(in);
    return out;
}

/* True iff line begins with `needle` after skipping leading spaces/tabs.
 * Used for PS `$content -ilike '*X*'` shortcut — but ilike is a SUBSTRING
 * test, not a prefix test. See `lines_ilike_contains` below for that. */

/* PS `-ilike '*<sub>*'` against a string array: returns $true iff ANY line
 * contains <sub> (case-insensitive). The leading/trailing '*' wildcards
 * mean "substring anywhere". This is what PS L 287-343 uses. */
static int lines_ilike_contains(char **lines, size_t n, const char *sub)
{
    if (sub == NULL || sub[0] == '\0') return 0;
    for (size_t i = 0; i < n; i++) {
        if (lines[i] == NULL) continue;
        if (strcasestr(lines[i], sub) != NULL) return 1;
    }
    return 0;
}

/* Returns get_spec_value()'s output if non-NULL, else returns empty_dup().
 * Free-friendly: the caller frees the result either way. Used to mirror
 *   `(Select-String -Pattern X)[0].ToString() -ireplace X, ""`
 * which when no match is found in PS still wouldn't throw — but L 292-343
 * always guards with `-ilike` first, so we get here only when there IS at
 * least one match. */
static char *first_value(char **lines, size_t n,
                         const char *pattern, const char *replace)
{
    char *v = get_spec_value(lines, n, pattern, replace);
    return v ? v : empty_dup();
}

/* PS L 287 form, special: `(($_  -split '=')[0]).replace('%define sha1',"").Trim()`
 *
 * Implementation: scan lines, take the first one whose case-insensitive
 * substring contains 'sub' (e.g. "%define sha1"), then split that line on
 * '=' once and keep the LEFT half, drop the literal sub (case-INSENSITIVE
 * because PS .replace on a string is case-SENSITIVE; but the wrapping PS
 * code uses `.replace('%define sha1',"")` which is case-sensitive. Since
 * the line itself was matched case-insensitively against the same literal
 * via -ilike, edge cases (sha1 vs SHA1 in the line) could differ between
 * PS and C. To be 1:1, fall back to case-INSENSITIVE replace here too —
 * the PS author's intent is clear: strip the keyword token whatever its
 * case. ADR-0006 accepts this as bit-identical given fixtures use the
 * canonical lower-case form.) */
static char *sha_name_extract(char **lines, size_t n, const char *sub)
{
    for (size_t i = 0; i < n; i++) {
        if (lines[i] == NULL) continue;
        if (strcasestr(lines[i], sub) == NULL) continue;
        /* (split '=')[0] : take up to the first '=' or whole string. */
        const char *eq = strchr(lines[i], '=');
        size_t halfn = eq ? (size_t)(eq - lines[i]) : strlen(lines[i]);
        char *half = (char *)malloc(halfn + 1);
        if (!half) return empty_dup();
        memcpy(half, lines[i], halfn);
        half[halfn] = '\0';
        /* replace `sub` case-insensitively with "" */
        char *cur = half;
        size_t sublen = strlen(sub);
        for (;;) {
            char *hit = strcasestr(cur, sub);
            if (!hit) break;
            memmove(hit, hit + sublen, strlen(hit + sublen) + 1);
            cur = hit;
        }
        /* trim */
        char *p = half;
        while (*p && isspace((unsigned char)*p)) p++;
        char *q = half + strlen(half);
        while (q > p && isspace((unsigned char)*(q - 1))) q--;
        char *out = (char *)malloc((size_t)(q - p) + 1);
        if (!out) { free(half); return empty_dup(); }
        memcpy(out, p, (size_t)(q - p));
        out[q - p] = '\0';
        free(half);
        return out;
    }
    return empty_dup();
}

/* ===== file/dir scan ================================================ */

static int scandir_alpha_filter_all(const struct dirent *d)
{
    /* Skip "." and ".." */
    if (d->d_name[0] == '.' &&
        (d->d_name[1] == '\0' ||
         (d->d_name[1] == '.' && d->d_name[2] == '\0')))
        return 0;
    return 1;
}

/* Read full file into a NULL-terminated array of malloc'd lines.
 * *out_lines must be freed by caller (free each line, then the array).
 * Mirrors Get-Content semantics: no trailing newlines on lines. */
static int read_lines(const char *path, char ***out_lines, size_t *out_n)
{
    *out_lines = NULL;
    *out_n     = 0;

    FILE *f = fopen(path, "rb");
    if (!f) return -1;

    char *line = NULL;
    size_t cap = 0;
    ssize_t n;

    char **arr = NULL;
    size_t acount = 0, acap = 0;

    while ((n = getline(&line, &cap, f)) != -1) {
        /* Strip trailing \r?\n — PS Get-Content drops the terminator. */
        while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r')) n--;
        if (acount == acap) {
            size_t nc = acap == 0 ? 256 : acap * 2;
            char **p = (char **)realloc(arr, nc * sizeof *p);
            if (!p) { free(line); fclose(f); /* leak prior arr — fatal anyway */ return -1; }
            arr = p;
            acap = nc;
        }
        char *copy = (char *)malloc((size_t)n + 1);
        if (!copy) { free(line); fclose(f); return -1; }
        memcpy(copy, line, (size_t)n);
        copy[n] = '\0';
        arr[acount++] = copy;
    }
    free(line);
    fclose(f);

    *out_lines = arr;
    *out_n     = acount;
    return 0;
}

/* Build SubRelease per PS L 264:
 *   $pathParts = $specRelPath -split '[/\\]'
 *   $subRelease = ($pathParts | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1) */
static char *derive_subrelease(const char *spec_rel_path)
{
    if (spec_rel_path == NULL) return empty_dup();
    const char *p = spec_rel_path;
    while (*p) {
        const char *end = p;
        while (*end && *end != '/' && *end != '\\') end++;
        size_t seglen = (size_t)(end - p);
        if (seglen > 0) {
            int all_digit = 1;
            for (size_t i = 0; i < seglen; i++) {
                if (!isdigit((unsigned char)p[i])) { all_digit = 0; break; }
            }
            if (all_digit) {
                char *out = (char *)malloc(seglen + 1);
                if (!out) return empty_dup();
                memcpy(out, p, seglen);
                out[seglen] = '\0';
                return out;
            }
        }
        if (!*end) break;
        p = end + 1;
    }
    return empty_dup();
}

/* PS Split-Path -Path X -Leaf — last path component of X. */
static char *split_path_leaf(const char *path)
{
    if (path == NULL) return empty_dup();
    const char *slash = strrchr(path, '/');
    const char *bs    = strrchr(path, '\\');
    const char *last  = slash > bs ? slash : bs;
    return xstrdup(last ? last + 1 : path);
}

/* Per-spec parser. Implements PS L 256-377 verbatim for ONE *.spec file. */
static int parse_one_spec(const char *specs_path,
                          const char *full_path,
                          const char *parent_dir,
                          pr_task_list_t *out)
{
    char **content = NULL;
    size_t n_lines = 0;
    if (read_lines(full_path, &content, &n_lines) != 0) {
        return 0;  /* PS catch{} silently skips. */
    }

    /* PS L 260: $Name = Split-Path -Path $currentFile.DirectoryName -Leaf */
    char *Name = split_path_leaf(parent_dir);

    /* PS L 262: $specRelPath = $currentFile.DirectoryName.Substring($specsPath.Length + 1) */
    size_t sp_len = strlen(specs_path);
    char *SpecRelativePath = NULL;
    if (strncmp(parent_dir, specs_path, sp_len) == 0 &&
        (parent_dir[sp_len] == '/' || parent_dir[sp_len] == '\\')) {
        SpecRelativePath = xstrdup(parent_dir + sp_len + 1);
    } else if (strcmp(parent_dir, specs_path) == 0) {
        SpecRelativePath = empty_dup();
    } else {
        /* Shouldn't happen — defensive. */
        SpecRelativePath = xstrdup(parent_dir);
    }

    /* PS L 263-265: derive SubRelease. */
    char *SubRelease = derive_subrelease(SpecRelativePath);

    /* PS L 268-269: Release */
    char *release = get_spec_value(content, n_lines, "^Release:", "Release:");
    if (release == NULL) {
        free(Name); free(SpecRelativePath); free(SubRelease);
        for (size_t i = 0; i < n_lines; i++) free(content[i]);
        free(content);
        return 0;  /* PS continue */
    }

    /* PS L 270-275: chained .Replace() on $release. */
    release = str_replace_all(release, "%{?dist}",                "");
    release = str_replace_all(release, "%{?kat_build:.kat}",      "");
    release = str_replace_all(release, "%{?kat_build:.%kat_build}", "");
    release = str_replace_all(release, "%{?kat_build:.%kat}",     "");
    release = str_replace_all(release, "%{?kernelsubrelease}",    "");
    release = str_replace_all(release, ".%{dialogsubversion}",    "");

    /* PS L 277-278: Version */
    char *raw_version = get_spec_value(content, n_lines, "^Version:", "Version:");
    if (raw_version == NULL) {
        free(release); free(Name); free(SpecRelativePath); free(SubRelease);
        for (size_t i = 0; i < n_lines; i++) free(content[i]);
        free(content);
        return 0;  /* PS continue */
    }

    /* PS L 279: $version = "$version-$release" */
    char *Version = NULL;
    if (asprintf(&Version, "%s-%s", raw_version, release) < 0) Version = empty_dup();
    free(raw_version);
    free(release);

    /* PS L 281-284: Source0 / URL */
    char *Source0 = get_spec_value(content, n_lines, "^Source0:", "Source0:");
    if (Source0 == NULL) Source0 = empty_dup();
    char *url     = get_spec_value(content, n_lines, "^URL:", "URL:");
    if (url == NULL) url = empty_dup();

    /* PS L 286-289: SHAName tri-branch (first-match wins). */
    char *SHAName = empty_dup();
    if      (lines_ilike_contains(content, n_lines, "%define sha1"))   { free(SHAName); SHAName = sha_name_extract(content, n_lines, "%define sha1"); }
    else if (lines_ilike_contains(content, n_lines, "%define sha256")) { free(SHAName); SHAName = sha_name_extract(content, n_lines, "%define sha256"); }
    else if (lines_ilike_contains(content, n_lines, "%define sha512")) { free(SHAName); SHAName = sha_name_extract(content, n_lines, "%define sha512"); }

    /* PS L 291-293: srcname  (define, then global overrides) */
    char *srcname = empty_dup();
    if (lines_ilike_contains(content, n_lines, "%define srcname")) {
        free(srcname);
        srcname = first_value(content, n_lines, "%define srcname", "%define srcname");
    }
    if (lines_ilike_contains(content, n_lines, "%global srcname")) {
        free(srcname);
        srcname = first_value(content, n_lines, "%global srcname", "%global srcname");
    }

    /* PS L 295-297: gem_name (define, then global overrides) */
    char *gem_name = empty_dup();
    if (lines_ilike_contains(content, n_lines, "%define gem_name")) {
        free(gem_name);
        gem_name = first_value(content, n_lines, "%define gem_name", "%define gem_name");
    }
    if (lines_ilike_contains(content, n_lines, "%global gem_name")) {
        free(gem_name);
        gem_name = first_value(content, n_lines, "%global gem_name", "%global gem_name");
    }

    /* PS L 299-300: group */
    char *group = empty_dup();
    if (lines_ilike_contains(content, n_lines, "Group:")) {
        free(group);
        group = first_value(content, n_lines, "^Group:", "Group:");
    }

    /* PS L 302-303: extra_version */
    char *extra_version = empty_dup();
    if (lines_ilike_contains(content, n_lines, "%define extra_version")) {
        free(extra_version);
        extra_version = first_value(content, n_lines, "%define extra_version", "%define extra_version");
    }

    /* PS L 305-306: main_version */
    char *main_version = empty_dup();
    if (lines_ilike_contains(content, n_lines, "%define main_version")) {
        free(main_version);
        main_version = first_value(content, n_lines, "%define main_version", "%define main_version");
    }

    /* PS L 308-309: upstreamversion */
    char *upstreamversion = empty_dup();
    if (lines_ilike_contains(content, n_lines, "%define upstreamversion")) {
        free(upstreamversion);
        upstreamversion = first_value(content, n_lines, "%define upstreamversion", "%define upstreamversion");
    }

    /* PS L 311-312: subversion */
    char *subversion = empty_dup();
    if (lines_ilike_contains(content, n_lines, "%define subversion")) {
        free(subversion);
        subversion = first_value(content, n_lines, "%define subversion", "%define subversion");
    }

    /* PS L 314-315: byaccdate  (note: PS uses 'define byaccdate' (no '%') for the -ilike test) */
    char *byaccdate = empty_dup();
    if (lines_ilike_contains(content, n_lines, "define byaccdate")) {
        free(byaccdate);
        byaccdate = first_value(content, n_lines, "%define byaccdate", "%define byaccdate");
    }

    /* PS L 317-318: dialogsubversion */
    char *dialogsubversion = empty_dup();
    if (lines_ilike_contains(content, n_lines, "%define dialogsubversion")) {
        free(dialogsubversion);
        dialogsubversion = first_value(content, n_lines, "%define dialogsubversion", "%define dialogsubversion");
    }

    /* PS L 320-321: libedit_release  (note: 'define libedit_release' in -ilike) */
    char *libedit_release = empty_dup();
    if (lines_ilike_contains(content, n_lines, "define libedit_release")) {
        free(libedit_release);
        libedit_release = first_value(content, n_lines, "%define libedit_release", "%define libedit_release");
    }

    /* PS L 323-324: libedit_version */
    char *libedit_version = empty_dup();
    if (lines_ilike_contains(content, n_lines, "%define libedit_version")) {
        free(libedit_version);
        libedit_version = first_value(content, n_lines, "%define libedit_version", "%define libedit_version");
    }

    /* PS L 326-327: ncursessubversion */
    char *ncursessubversion = empty_dup();
    if (lines_ilike_contains(content, n_lines, "%define ncursessubversion")) {
        free(ncursessubversion);
        ncursessubversion = first_value(content, n_lines, "%define ncursessubversion", "%define ncursessubversion");
    }

    /* PS L 329-330: cpan_name  (note: 'define cpan_name' in -ilike) */
    char *cpan_name = empty_dup();
    if (lines_ilike_contains(content, n_lines, "define cpan_name")) {
        free(cpan_name);
        cpan_name = first_value(content, n_lines, "%define cpan_name", "%define cpan_name");
    }

    /* PS L 332-333: xproto_ver */
    char *xproto_ver = empty_dup();
    if (lines_ilike_contains(content, n_lines, "%define xproto_ver")) {
        free(xproto_ver);
        xproto_ver = first_value(content, n_lines, "%define xproto_ver", "%define xproto_ver");
    }

    /* PS L 335-336: _url_src  (note: 'define _url_src' in -ilike) */
    char *_url_src = empty_dup();
    if (lines_ilike_contains(content, n_lines, "define _url_src")) {
        free(_url_src);
        _url_src = first_value(content, n_lines, "%define _url_src", "%define _url_src");
    }

    /* PS L 338-339: _repo_ver */
    char *_repo_ver = empty_dup();
    if (lines_ilike_contains(content, n_lines, "%define _repo_ver")) {
        free(_repo_ver);
        _repo_ver = first_value(content, n_lines, "%define _repo_ver", "%define _repo_ver");
    }

    /* PS L 341-343: commit_id  (global, then define overrides — matches PS order) */
    char *commit_id = empty_dup();
    if (lines_ilike_contains(content, n_lines, "%global commit_id")) {
        free(commit_id);
        commit_id = first_value(content, n_lines, "%global commit_id", "%global commit_id");
    }
    if (lines_ilike_contains(content, n_lines, "%define commit_id")) {
        free(commit_id);
        commit_id = first_value(content, n_lines, "%define commit_id", "%define commit_id");
    }

    /* PS L 345-372: $Packages.Add([PSCustomObject]@{ ... }) */
    pr_task_t t;
    memset(&t, 0, sizeof t);
    t.content           = content;   /* ownership transferred */
    t.content_lines     = n_lines;
    /* Spec = $currentFile.Name — basename of full_path. */
    t.Spec              = split_path_leaf(full_path);
    t.Version           = Version;
    t.Name              = Name;
    t.SubRelease        = SubRelease;
    t.SpecRelativePath  = SpecRelativePath;
    t.Source0           = Source0;
    t.url               = url;
    t.SHAName           = SHAName;
    t.srcname           = srcname;
    t.gem_name          = gem_name;
    t.group             = group;
    t.extra_version     = extra_version;
    t.main_version      = main_version;
    t.upstreamversion   = upstreamversion;
    t.dialogsubversion  = dialogsubversion;
    t.subversion        = subversion;
    t.byaccdate         = byaccdate;
    t.libedit_release   = libedit_release;
    t.libedit_version   = libedit_version;
    t.ncursessubversion = ncursessubversion;
    t.cpan_name         = cpan_name;
    t.xproto_ver        = xproto_ver;
    t._url_src          = _url_src;
    t._repo_ver         = _repo_ver;
    t.commit_id         = commit_id;

    if (pr_task_list_add(out, &t) != 0) {
        pr_task_free(&t);
        return -1;
    }
    return 0;
}

/* Recursive walker. PS Get-ChildItem -Recurse -File -Filter "*.spec":
 *   Files in current dir (alpha-sorted) first, then descend into each
 *   subdirectory in alpha order. PowerShell's actual interleaving is
 *   implementation-defined; the parity harness sorts both sides on
 *   SpecRelativePath/Spec before comparison so this ordering choice is
 *   internally consistent. */
static int walk(const char *specs_path, const char *dir, pr_task_list_t *out)
{
    struct dirent **entries = NULL;
    int n = scandir(dir, &entries, scandir_alpha_filter_all, alphasort);
    if (n < 0) return 0;  /* PS would silently skip on permission/error. */

    /* Pass 1: *.spec files in this directory. */
    for (int i = 0; i < n; i++) {
        const char *name = entries[i]->d_name;
        size_t nlen = strlen(name);
        if (nlen <= 5 || strcmp(name + nlen - 5, ".spec") != 0) continue;
        char *full = NULL;
        if (asprintf(&full, "%s/%s", dir, name) < 0) continue;
        struct stat st;
        if (stat(full, &st) == 0 && S_ISREG(st.st_mode)) {
            parse_one_spec(specs_path, full, dir, out);
        }
        free(full);
    }

    /* Pass 2: subdirectories. */
    for (int i = 0; i < n; i++) {
        const char *name = entries[i]->d_name;
        char *full = NULL;
        if (asprintf(&full, "%s/%s", dir, name) < 0) continue;
        struct stat st;
        if (stat(full, &st) == 0 && S_ISDIR(st.st_mode)) {
            walk(specs_path, full, out);
        }
        free(full);
    }

    for (int i = 0; i < n; i++) free(entries[i]);
    free(entries);
    return 0;
}

int parse_directory(const char *working_dir, const char *photon_dir,
                    pr_task_list_t *out)
{
    if (out == NULL) return -1;
    /* List was init'd by caller, but in case it wasn't: */
    if (out->items == NULL && out->count == 0 && out->cap == 0) {
        pr_task_list_init(out);
    }

    /* PS L 255: $specsPath = Join-Path WorkingDir photonDir | Join-Path SPECS */
    char *specs_path = NULL;
    if (asprintf(&specs_path, "%s/%s/SPECS", working_dir, photon_dir) < 0) return -1;

    struct stat st;
    if (stat(specs_path, &st) != 0 || !S_ISDIR(st.st_mode)) {
        fprintf(stderr, "parse_directory: SPECS path not a directory: %s\n", specs_path);
        free(specs_path);
        return -1;
    }

    walk(specs_path, specs_path, out);
    free(specs_path);
    return 0;
}
