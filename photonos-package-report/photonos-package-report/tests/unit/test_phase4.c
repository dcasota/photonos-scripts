/* test_phase4.c — unit tests for the Source0 substitution core.
 *
 * Covers every branch of photonos-package-report.ps1 L 2172-2199:
 *
 *   • %{url}                                                  (PS L 2172)
 *   • %{url} when currentTask.url == ""                       (PS L 2172)
 *   • URL-prefix injection when Source0 has no "//"
 *     and currentTask.url ends with .tar.gz                   (PS L 2176)
 *   • URL-prefix injection (else branch, trim trailing '/')   (PS L 2178)
 *   • %{name}                                                 (PS L 2182)
 *   • %{version}                                              (PS L 2183)
 *   • Outer `*{*` gate short-circuits when no `{` remains     (PS L 2185)
 *   • Each of the 15 secondary tokens                         (PS L 2187-2202)
 *   • Case-insensitive matching: %{URL}, %{Name}, %{VERSION} all replaced
 */
#include "pr_substitute.h"
#include "pr_types.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;

#define EXPECT_STREQ(actual, expected) do {                                    \
    const char *_a = (actual);                                                 \
    const char *_e = (expected);                                               \
    if (_a == NULL || strcmp(_a, _e) != 0) {                                   \
        fprintf(stderr, "  FAIL %s:%d: expected '%s' got '%s'\n",              \
                __FILE__, __LINE__, _e, _a ? _a : "(null)");                   \
        failures++;                                                            \
    }                                                                          \
} while (0)

static char *xs(const char *s)
{
    size_t n = strlen(s);
    char *p = malloc(n + 1);
    memcpy(p, s, n + 1);
    return p;
}

/* Build a minimal pr_task_t with all string fields set to heap-allocated
 * empties unless overridden. Caller frees via pr_task_free. */
static void task_init_default(pr_task_t *t)
{
    memset(t, 0, sizeof *t);
#define E(field) t->field = xs("")
    E(Spec); E(Version); E(Name); E(SubRelease); E(SpecRelativePath);
    E(Source0); E(url); E(SHAName); E(srcname); E(gem_name); E(group);
    E(extra_version); E(main_version); E(upstreamversion);
    E(dialogsubversion); E(subversion); E(byaccdate);
    E(libedit_release); E(libedit_version); E(ncursessubversion);
    E(cpan_name); E(xproto_ver); E(_url_src); E(_repo_ver); E(commit_id);
#undef E
}

static void task_free(pr_task_t *t) { pr_task_free(t); }

/* ---- URL substitution ---------------------------------------------- */
static void test_url(void)
{
    fprintf(stderr, "[test_url]\n");

    pr_task_t t; task_init_default(&t);
    free(t.url); t.url = xs("https://example.invalid/upstream/");

    char *src = xs("%{url}foo-%{version}.tar.gz");
    if (pr_source0_substitute(&t, &src, "1.0") == 0)
        EXPECT_STREQ(src, "https://example.invalid/upstream/foo-1.0.tar.gz");
    free(src);
    task_free(&t);

    /* Case-insensitive: %{URL} also matches. */
    pr_task_t t2; task_init_default(&t2);
    free(t2.url); t2.url = xs("https://example.invalid/");
    char *src2 = xs("%{URL}bar.tar.gz");
    if (pr_source0_substitute(&t2, &src2, "") == 0)
        EXPECT_STREQ(src2, "https://example.invalid/bar.tar.gz");
    free(src2);
    task_free(&t2);

    /* %{url} present but currentTask.url is "" — empty replace. */
    pr_task_t t3; task_init_default(&t3);
    char *src3 = xs("%{url}baz.tar.gz");
    if (pr_source0_substitute(&t3, &src3, "") == 0)
        EXPECT_STREQ(src3, "baz.tar.gz");  /* prefix-injection then doesn't fire since url is "" */
    free(src3);
    task_free(&t3);
}

/* ---- URL-prefix injection (PS L 2174-2179) -------------------------- */
static void test_prefix_injection(void)
{
    fprintf(stderr, "[test_prefix_injection]\n");

    /* currentTask.url ends in .tar.gz, Source0 has no "//"
     *   → Source0 := currentTask.url, verbatim. */
    pr_task_t t; task_init_default(&t);
    free(t.url); t.url = xs("https://example.invalid/pkg-1.0.tar.gz");
    char *src = xs("pkg.tar.gz");
    if (pr_source0_substitute(&t, &src, "1.0") == 0)
        EXPECT_STREQ(src, "https://example.invalid/pkg-1.0.tar.gz");
    free(src);
    task_free(&t);

    /* else branch: trim trailing '/' from url, concat with Source0. */
    pr_task_t t2; task_init_default(&t2);
    free(t2.url); t2.url = xs("https://example.invalid/path/");
    char *src2 = xs("foo.zip");
    if (pr_source0_substitute(&t2, &src2, "") == 0)
        EXPECT_STREQ(src2, "https://example.invalid/pathfoo.zip");
    free(src2);
    task_free(&t2);

    /* No prefix injection when Source0 already has "//". */
    pr_task_t t3; task_init_default(&t3);
    free(t3.url); t3.url = xs("https://elsewhere.invalid/");
    char *src3 = xs("https://here.invalid/x.tar.gz");
    if (pr_source0_substitute(&t3, &src3, "") == 0)
        EXPECT_STREQ(src3, "https://here.invalid/x.tar.gz");
    free(src3);
    task_free(&t3);

    /* No injection when currentTask.url is "". */
    pr_task_t t4; task_init_default(&t4);
    char *src4 = xs("relative-path.tar.gz");
    if (pr_source0_substitute(&t4, &src4, "") == 0)
        EXPECT_STREQ(src4, "relative-path.tar.gz");
    free(src4);
    task_free(&t4);
}

/* ---- %{name} and %{version} ---------------------------------------- */
static void test_name_version(void)
{
    fprintf(stderr, "[test_name_version]\n");

    pr_task_t t; task_init_default(&t);
    free(t.Name); t.Name = xs("hello");
    free(t.url);  t.url  = xs("https://example.invalid/");
    char *src = xs("https://example.invalid/%{name}-%{version}.tar.gz");
    if (pr_source0_substitute(&t, &src, "2.10") == 0)
        EXPECT_STREQ(src, "https://example.invalid/hello-2.10.tar.gz");
    free(src);
    task_free(&t);

    /* Case-insensitive: %{Name} %{VERSION} also replaced. */
    pr_task_t t2; task_init_default(&t2);
    free(t2.Name); t2.Name = xs("world");
    char *src2 = xs("https://example.invalid/%{Name}-%{VERSION}.tar.gz");
    if (pr_source0_substitute(&t2, &src2, "9.9") == 0)
        EXPECT_STREQ(src2, "https://example.invalid/world-9.9.tar.gz");
    free(src2);
    task_free(&t2);
}

/* ---- Outer `*{*` gate ---------------------------------------------- */
static void test_outer_gate(void)
{
    fprintf(stderr, "[test_outer_gate]\n");

    /* No `{` left → none of the 15 secondary patterns are even tested. */
    pr_task_t t; task_init_default(&t);
    free(t.srcname); t.srcname = xs("WILL_NOT_APPLY");
    char *src = xs("https://example.invalid/already-resolved.tar.gz");
    if (pr_source0_substitute(&t, &src, "") == 0)
        EXPECT_STREQ(src, "https://example.invalid/already-resolved.tar.gz");
    free(src);
    task_free(&t);
}

/* ---- 15 secondary tokens (PS L 2187-2202) -------------------------- */
static void test_secondary(void)
{
    fprintf(stderr, "[test_secondary]\n");

    /* For each token, build a task with only that field set and a
     * Source0 template that uses it. Confirm the result is the field
     * value alone (proving the token was replaced). */
    struct {
        const char *token;          /* literal token, e.g. "%{srcname}" */
        size_t      field_offset;   /* offsetof(pr_task_t, srcname) etc. */
        const char *value;
        const char *fieldname;      /* for failure messages */
    } cases[] = {
        { "%{srcname}",           offsetof(pr_task_t, srcname),           "Foo",          "srcname" },
        { "%{gem_name}",          offsetof(pr_task_t, gem_name),          "bar",          "gem_name" },
        { "%{extra_version}",     offsetof(pr_task_t, extra_version),     "rc1",          "extra_version" },
        { "%{main_version}",      offsetof(pr_task_t, main_version),      "4.5",          "main_version" },
        { "%{byaccdate}",         offsetof(pr_task_t, byaccdate),         "20210808",     "byaccdate" },
        { "%{dialogsubversion}",  offsetof(pr_task_t, dialogsubversion),  "20230209",     "dialogsubversion" },
        { "%{subversion}",        offsetof(pr_task_t, subversion),        "6",            "subversion" },
        { "%{upstreamversion}",   offsetof(pr_task_t, upstreamversion),   "4.5.6-beta",   "upstreamversion" },
        { "%{libedit_release}",   offsetof(pr_task_t, libedit_release),   "50",           "libedit_release" },
        { "%{libedit_version}",   offsetof(pr_task_t, libedit_version),   "20221030",     "libedit_version" },
        { "%{ncursessubversion}", offsetof(pr_task_t, ncursessubversion), "20221231",     "ncursessubversion" },
        { "%{cpan_name}",         offsetof(pr_task_t, cpan_name),         "Misc::Bundle", "cpan_name" },
        { "%{xproto_ver}",        offsetof(pr_task_t, xproto_ver),        "7.0.31",       "xproto_ver" },
        { "%{_url_src}",          offsetof(pr_task_t, _url_src),          "https://src",  "_url_src" },
        { "%{_repo_ver}",         offsetof(pr_task_t, _repo_ver),         "9.9.9",        "_repo_ver" },
        { "%{commit_id}",         offsetof(pr_task_t, commit_id),         "abc123",       "commit_id" },
    };
    size_t n = sizeof cases / sizeof cases[0];
    for (size_t i = 0; i < n; i++) {
        pr_task_t t; task_init_default(&t);
        char **slot = (char **)((char *)&t + cases[i].field_offset);
        free(*slot);
        *slot = xs(cases[i].value);

        size_t tlen = strlen(cases[i].token);
        char *src = malloc(strlen("https://h/") + tlen + 1);
        strcpy(src, "https://h/");
        strcat(src, cases[i].token);

        if (pr_source0_substitute(&t, &src, "") == 0) {
            char *expected = malloc(strlen("https://h/") + strlen(cases[i].value) + 1);
            strcpy(expected, "https://h/");
            strcat(expected, cases[i].value);
            if (strcmp(src, expected) != 0) {
                fprintf(stderr, "  FAIL %s: expected '%s' got '%s'\n",
                        cases[i].fieldname, expected, src);
                failures++;
            }
            free(expected);
        }
        free(src);
        task_free(&t);
    }
}

int main(void)
{
    test_url();
    test_prefix_injection();
    test_name_version();
    test_outer_gate();
    test_secondary();

    if (failures == 0) {
        fprintf(stderr, "test_phase4: ALL PASSED\n");
        return 0;
    }
    fprintf(stderr, "test_phase4: %d failure(s)\n", failures);
    return 1;
}
