/* test_phase6d.c — unit tests for the local-clone manager.
 *
 * Coverage:
 *   - pr_extract_repo_name on a range of git URL shapes
 *   - end-to-end pr_clone_ensure + pr_clone_list_tags against a tiny
 *     local bare repo created in /tmp (no network). Gated on whether
 *     git is on PATH.
 */
#include "pr_clone.h"
#include "pr_git_tags.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

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
#define EXPECT_NULL(actual) do {                                               \
    if ((actual) != NULL) {                                                    \
        fprintf(stderr, "  FAIL %s:%d: expected NULL\n", __FILE__, __LINE__);  \
        failures++;                                                            \
    }                                                                          \
} while (0)

/* --- pr_extract_repo_name ------------------------------------------ */
static void test_extract_repo_name(void)
{
    fprintf(stderr, "[test_extract_repo_name]\n");

    char *r;
    r = pr_extract_repo_name("https://github.com/abseil/abseil-cpp.git");
    EXPECT_STREQ(r, "abseil-cpp"); free(r);

    r = pr_extract_repo_name("https://gitlab.freedesktop.org/cairo/cairo.git");
    EXPECT_STREQ(r, "cairo"); free(r);

    /* Multiple path segments before .git */
    r = pr_extract_repo_name("https://gitlab.freedesktop.org/xorg/lib/libx11.git");
    EXPECT_STREQ(r, "libx11"); free(r);

    /* SSH-style. */
    r = pr_extract_repo_name("git@github.com:user/repo.git");
    /* Falls back: there is no '/' before "repo.git" — actually there
     * is one in "user/repo.git"; the function looks for the last '/'. */
    EXPECT_STREQ(r, "repo"); free(r);

    /* Missing .git → NULL */
    EXPECT_NULL(pr_extract_repo_name("https://github.com/foo/bar"));

    /* Just ".git" with no slash → NULL */
    EXPECT_NULL(pr_extract_repo_name(".git"));

    /* NULL → NULL */
    EXPECT_NULL(pr_extract_repo_name(NULL));
}

/* --- Local-bare-repo integration ----------------------------------- */

static int have_git(void)
{
    return system("git --version >/dev/null 2>&1") == 0;
}

static int run(const char *cmd)
{
    int rc = system(cmd);
    return WIFEXITED(rc) && WEXITSTATUS(rc) == 0 ? 0 : -1;
}

static void test_clone_and_tags(void)
{
    fprintf(stderr, "[test_clone_and_tags]\n");
    if (!have_git()) {
        fprintf(stderr, "  SKIP: git not on PATH\n");
        return;
    }

    char bare_tmpl[]  = "/tmp/pr_phase6d_bare_XXXXXX";
    char clone_tmpl[] = "/tmp/pr_phase6d_clone_XXXXXX";
    char *bare  = mkdtemp(bare_tmpl);
    char *clone = mkdtemp(clone_tmpl);
    if (!bare || !clone) {
        fprintf(stderr, "  FAIL: mkdtemp failed\n"); failures++;
        return;
    }

    /* Build a bare repo with three tags.
     *   workdir holds the working copy, bare is the .git that
     *   pr_clone_ensure clones from. */
    char workdir_tmpl[] = "/tmp/pr_phase6d_work_XXXXXX";
    char *workdir = mkdtemp(workdir_tmpl);
    if (!workdir) { fprintf(stderr, "  FAIL: mkdtemp workdir\n"); failures++; return; }

    char cmd[1024];
    snprintf(cmd, sizeof cmd,
        "set -e ;"
        "cd '%s' ;"
        "git init -q -b main . ;"
        "git config user.email t@t ;"
        "git config user.name t ;"
        "echo a > a.txt ; git add . ; git commit -q -m a ; git tag v1.0 ;"
        "echo b > b.txt ; git add . ; git commit -q -m b ; git tag v1.1 ;"
        "echo c > c.txt ; git add . ; git commit -q -m c ; git tag v2.0 ;"
        "cd '%s' ; git clone -q --bare '%s/.git' . ;",
        workdir, bare, workdir);
    if (run(cmd) != 0) {
        fprintf(stderr, "  FAIL: bare repo setup\n"); failures++;
        return;
    }

    /* Clone-ensure into clone_root/repo. */
    if (pr_clone_ensure(clone, bare, NULL, "repo") != 0) {
        fprintf(stderr, "  FAIL: pr_clone_ensure rc != 0\n"); failures++;
    }

    /* List tags. */
    char clone_path[1024];
    snprintf(clone_path, sizeof clone_path, "%s/repo", clone);
    char **names = NULL; size_t n = 0;
    if (pr_clone_list_tags(clone_path, NULL, &names, &n) != 0) {
        fprintf(stderr, "  FAIL: pr_clone_list_tags rc != 0\n"); failures++;
    }
    if (n != 3) {
        fprintf(stderr, "  FAIL: expected 3 tags, got %zu\n", n); failures++;
    }
    if (n >= 3) {
        /* git tag -l output is sorted; v1.0, v1.1, v2.0. */
        EXPECT_STREQ(names[0], "v1.0");
        EXPECT_STREQ(names[1], "v1.1");
        EXPECT_STREQ(names[2], "v2.0");
    }
    pr_git_tags_free(names, n);

    /* Second invocation should hit the fetch path (clone exists). */
    if (pr_clone_ensure(clone, bare, NULL, "repo") != 0) {
        fprintf(stderr, "  FAIL: second pr_clone_ensure (fetch path) rc != 0\n");
        failures++;
    }

    /* Cleanup — best-effort. */
    snprintf(cmd, sizeof cmd, "rm -rf '%s' '%s' '%s'", workdir, bare, clone);
    run(cmd);
}

int main(void)
{
    test_extract_repo_name();
    test_clone_and_tags();

    if (failures == 0) {
        fprintf(stderr, "test_phase6d: ALL PASSED\n");
        return 0;
    }
    fprintf(stderr, "test_phase6d: %d failure(s)\n", failures);
    return 1;
}
