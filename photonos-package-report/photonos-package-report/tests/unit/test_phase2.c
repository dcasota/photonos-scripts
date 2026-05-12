/* test_phase2.c — unit tests for Get-SpecValue + ParseDirectory.
 *
 * Invocation:
 *   test_phase2 <fixtures-dir>
 *
 * where <fixtures-dir> contains "photon-fixture/SPECS/...". The CMake
 * test command in tests/unit/CMakeLists.txt passes the absolute path
 * to the source-tree fixtures dir.
 *
 * Assertions cover:
 *   • Get-SpecValue happy path, no-match, case-insensitive, trim.
 *   • ParseDirectory accepted-task count (= 9 from 11 fixtures; 2 are
 *     skipped for missing Release / Version).
 *   • Per-fixture field values for representative cases:
 *     - hello:        sha1 SHAName, %{?dist} stripped from Release, Group.
 *     - 91/dbus:      SubRelease = "91", sha256 SHAName.
 *     - gnupg:        %{?kat_build:.kat} stripped, sha512 SHAName.
 *     - kernel:       %{?kernelsubrelease} stripped, ncursessubversion set.
 *     - dialog:       .%{dialogsubversion} stripped, dialogsubversion captured.
 *     - python-foo:   %global srcname overrides %define srcname.
 *     - rubygem-bar:  %global gem_name overrides %define gem_name.
 *     - commit-test:  %define commit_id overrides %global commit_id.
 *     - misc:         byaccdate / libedit_release / libedit_version /
 *                     cpan_name / xproto_ver / _url_src / _repo_ver /
 *                     extra_version / main_version / upstreamversion /
 *                     subversion all captured.
 */
#include "photonos_package_report.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;
#define EXPECT_STREQ(actual, expected) do {                                    \
    const char *_a = (actual);                                                 \
    const char *_e = (expected);                                               \
    if (_a == NULL || strcmp(_a, _e) != 0) {                                   \
        fprintf(stderr, "  FAIL %s:%d: expected %s='%s' but got '%s'\n",       \
                __FILE__, __LINE__, #actual, _e, _a ? _a : "(null)");          \
        failures++;                                                            \
    }                                                                          \
} while (0)
#define EXPECT_NULL(actual) do {                                               \
    const void *_a = (actual);                                                 \
    if (_a != NULL) {                                                          \
        fprintf(stderr, "  FAIL %s:%d: expected %s to be NULL\n",              \
                __FILE__, __LINE__, #actual);                                  \
        failures++;                                                            \
    }                                                                          \
} while (0)
#define EXPECT_INT_EQ(actual, expected) do {                                   \
    long _a = (long)(actual);                                                  \
    long _e = (long)(expected);                                                \
    if (_a != _e) {                                                            \
        fprintf(stderr, "  FAIL %s:%d: expected %s=%ld but got %ld\n",         \
                __FILE__, __LINE__, #actual, _e, _a);                          \
        failures++;                                                            \
    }                                                                          \
} while (0)

/* --------- Get-SpecValue tests --------------------------------------- */

static void test_get_spec_value(void)
{
    fprintf(stderr, "[test_get_spec_value]\n");

    char *lines[] = {
        (char *)"Summary:       Foo",
        (char *)"Name:          bar",
        (char *)"Version:       1.2.3",
        (char *)"Release:       7%{?dist}",
        (char *)"URL:           https://example.invalid/",
        (char *)"Source0:       https://example.invalid/bar-%{version}.tar.gz",
    };
    size_t n = sizeof lines / sizeof lines[0];

    char *v;

    /* Happy path: Release matches first */
    v = get_spec_value(lines, n, "^Release:", "Release:");
    EXPECT_STREQ(v, "7%{?dist}");
    free(v);

    /* URL with trailing trim. */
    v = get_spec_value(lines, n, "^URL:", "URL:");
    EXPECT_STREQ(v, "https://example.invalid/");
    free(v);

    /* Case-insensitive: 'name:' regex matches 'Name:' line. */
    v = get_spec_value(lines, n, "^name:", "name:");
    EXPECT_STREQ(v, "bar");
    free(v);

    /* No match → NULL */
    v = get_spec_value(lines, n, "^NonExistent:", "NonExistent:");
    EXPECT_NULL(v);

    /* Empty replace → keep full line (trimmed). */
    v = get_spec_value(lines, n, "^Summary:", "");
    EXPECT_STREQ(v, "Summary:       Foo");
    free(v);
}

/* --------- ParseDirectory helpers ----------------------------------- */

static pr_task_t *find_task(pr_task_list_t *L, const char *name)
{
    for (size_t i = 0; i < L->count; i++) {
        if (L->items[i].Name && strcmp(L->items[i].Name, name) == 0) {
            return &L->items[i];
        }
    }
    return NULL;
}

static void test_parse_directory(const char *fixtures_dir)
{
    fprintf(stderr, "[test_parse_directory] fixtures_dir=%s\n", fixtures_dir);

    pr_task_list_t L;
    pr_task_list_init(&L);

    int rc = parse_directory(fixtures_dir, "photon-fixture", &L);
    EXPECT_INT_EQ(rc, 0);

    /* 11 *.spec files, 2 skipped → 9 accepted tasks. */
    EXPECT_INT_EQ((long)L.count, 9);

    /* skip-no-release / skip-no-version must NOT appear. */
    EXPECT_NULL(find_task(&L, "skip-no-release"));
    EXPECT_NULL(find_task(&L, "skip-no-version"));

    /* hello: %{?dist} stripped, sha1 capture, Group set. */
    pr_task_t *hello = find_task(&L, "hello");
    if (hello) {
        EXPECT_STREQ(hello->Spec,             "hello.spec");
        EXPECT_STREQ(hello->Version,          "2.10-1");
        EXPECT_STREQ(hello->Name,             "hello");
        EXPECT_STREQ(hello->SubRelease,       "");
        EXPECT_STREQ(hello->SpecRelativePath, "hello");
        EXPECT_STREQ(hello->url,              "https://www.gnu.org/software/hello/");
        /* PS L 287: SHAName = ((line -split '=')[0]).replace('%define sha1',"").Trim()
         *   → keeps only what's BEFORE '=' minus the keyword, which here
         *     is just the source-tarball basename. */
        EXPECT_STREQ(hello->SHAName,          "hello-2.10.tar.gz");
        EXPECT_STREQ(hello->group,            "Applications/Text");
    } else {
        fprintf(stderr, "  FAIL: could not find task 'hello'\n"); failures++;
    }

    /* 91/dbus: SubRelease "91", sha256 capture. */
    pr_task_t *dbus = find_task(&L, "dbus");
    if (dbus) {
        EXPECT_STREQ(dbus->SubRelease,       "91");
        EXPECT_STREQ(dbus->SpecRelativePath, "91/dbus");
        EXPECT_STREQ(dbus->Version,          "1.12.20-7");
        EXPECT_STREQ(dbus->SHAName,          "dbus-1.12.20.tar.xz");
    } else {
        fprintf(stderr, "  FAIL: could not find task 'dbus'\n"); failures++;
    }

    /* gnupg: kat_build stripping in Release; sha512 capture. */
    pr_task_t *gnupg = find_task(&L, "gnupg");
    if (gnupg) {
        EXPECT_STREQ(gnupg->Version, "2.2.40-3");
        EXPECT_STREQ(gnupg->SHAName, "gnupg-2.2.40.tar.bz2");
    } else {
        fprintf(stderr, "  FAIL: could not find task 'gnupg'\n"); failures++;
    }

    /* kernel: %{?kernelsubrelease} stripped, ncursessubversion captured. */
    pr_task_t *kernel = find_task(&L, "kernel");
    if (kernel) {
        EXPECT_STREQ(kernel->Version,           "6.6.12-1.ph6");
        EXPECT_STREQ(kernel->ncursessubversion, "20221231");
    } else {
        fprintf(stderr, "  FAIL: could not find task 'kernel'\n"); failures++;
    }

    /* dialog: .%{dialogsubversion} stripped from release; dialogsubversion captured. */
    pr_task_t *dialog = find_task(&L, "dialog");
    if (dialog) {
        EXPECT_STREQ(dialog->Version,          "1.3-5");
        EXPECT_STREQ(dialog->dialogsubversion, "20230209");
    } else {
        fprintf(stderr, "  FAIL: could not find task 'dialog'\n"); failures++;
    }

    /* python-foo: %global srcname wins. */
    pr_task_t *pf = find_task(&L, "python-foo");
    if (pf) {
        EXPECT_STREQ(pf->srcname, "foo");
    } else {
        fprintf(stderr, "  FAIL: could not find task 'python-foo'\n"); failures++;
    }

    /* rubygem-bar: %global gem_name wins. */
    pr_task_t *rg = find_task(&L, "rubygem-bar");
    if (rg) {
        EXPECT_STREQ(rg->gem_name, "bar");
    } else {
        fprintf(stderr, "  FAIL: could not find task 'rubygem-bar'\n"); failures++;
    }

    /* commit-test: %define commit_id overrides %global commit_id. */
    pr_task_t *ct = find_task(&L, "commit-test");
    if (ct) {
        EXPECT_STREQ(ct->commit_id, "bbbb2222");
    } else {
        fprintf(stderr, "  FAIL: could not find task 'commit-test'\n"); failures++;
    }

    /* misc: all eleven %define captures populated. */
    pr_task_t *m = find_task(&L, "misc");
    if (m) {
        EXPECT_STREQ(m->byaccdate,       "20210808");
        EXPECT_STREQ(m->libedit_release, "50");
        EXPECT_STREQ(m->libedit_version, "20221030");
        EXPECT_STREQ(m->cpan_name,       "Misc::Bundle");
        EXPECT_STREQ(m->xproto_ver,      "7.0.31");
        EXPECT_STREQ(m->_url_src,        "https://example.invalid/src");
        EXPECT_STREQ(m->_repo_ver,       "9.9.9");
        EXPECT_STREQ(m->extra_version,   "rc1");
        EXPECT_STREQ(m->main_version,    "4.5");
        EXPECT_STREQ(m->upstreamversion, "4.5.6-beta");
        EXPECT_STREQ(m->subversion,      "6");
    } else {
        fprintf(stderr, "  FAIL: could not find task 'misc'\n"); failures++;
    }

    pr_task_list_free(&L);
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s <fixtures-dir>\n", argv[0]);
        return 2;
    }
    test_get_spec_value();
    test_parse_directory(argv[1]);

    if (failures == 0) {
        fprintf(stderr, "test_phase2: ALL PASSED\n");
        return 0;
    }
    fprintf(stderr, "test_phase2: %d failure(s)\n", failures);
    return 1;
}
