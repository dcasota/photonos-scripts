/* clone.c — local-clone manager (Phase 6d, sequential).
 * Mirrors photonos-package-report.ps1 L 2358-2456.
 */
/* _GNU_SOURCE for asprintf comes from CMake; do not redefine. */
#include "pr_clone.h"
#include "pr_git_tags.h"
#include "photonos_package_report.h"  /* invoke_git_with_timeout from Phase 1 */

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <ftw.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

/* --- helpers -------------------------------------------------------- */

static int dir_exists(const char *path)
{
    struct stat st;
    if (stat(path, &st) != 0) return 0;
    return S_ISDIR(st.st_mode);
}

static int rm_walker(const char *fpath, const struct stat *sb,
                     int typeflag, struct FTW *ftwbuf)
{
    (void)sb; (void)typeflag; (void)ftwbuf;
    return remove(fpath);
}

/* `rm -rf path`. Returns 0 on success or if path doesn't exist. */
static int rm_rf(const char *path)
{
    if (!dir_exists(path) && access(path, F_OK) != 0) return 0;
    /* nftw post-order: deepest first. */
    return nftw(path, rm_walker, 16, FTW_DEPTH | FTW_PHYS);
}

static int mkdir_p(const char *path)
{
    char *copy = strdup(path);
    if (!copy) return -1;
    for (char *p = copy + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(copy, 0755) != 0 && errno != EEXIST) { free(copy); return -1; }
            *p = '/';
        }
    }
    int rc = mkdir(copy, 0755);
    if (rc != 0 && errno == EEXIST) rc = 0;
    free(copy);
    return rc;
}

/* --- pr_extract_repo_name ------------------------------------------ */

char *pr_extract_repo_name(const char *git_url)
{
    /* PS L 2363: /([^/]+)\.git$ */
    if (git_url == NULL) return NULL;
    size_t n = strlen(git_url);
    if (n < 5) return NULL;                              /* min: "/a.git" */
    if (strcmp(git_url + n - 4, ".git") != 0) return NULL;
    const char *end = git_url + n - 4;                    /* points to '.git' */
    const char *slash = end;
    while (slash > git_url && *(slash - 1) != '/') slash--;
    if (slash == git_url) return NULL;                    /* no '/' found */
    size_t len = (size_t)(end - slash);
    if (len == 0) return NULL;
    char *out = (char *)malloc(len + 1);
    if (!out) return NULL;
    memcpy(out, slash, len);
    out[len] = '\0';
    return out;
}

/* --- pr_clone_ensure ----------------------------------------------- */

static int do_clone(const char *clone_root,
                    const char *git_url,
                    const char *git_branch,
                    const char *repo_name)
{
    char *args = NULL;
    if (git_branch && git_branch[0]) {
        if (asprintf(&args, "clone %s -b %s %s", git_url, git_branch, repo_name) < 0) return -1;
    } else {
        if (asprintf(&args, "clone %s %s", git_url, repo_name) < 0) return -1;
    }
    char *stdout_buf = NULL;
    int rc = invoke_git_with_timeout(args, clone_root, 0, &stdout_buf);
    free(args);
    free(stdout_buf);
    return rc == 0 ? 0 : -1;
}

static int do_fetch(const char *clone_path, const char *git_branch)
{
    char *args = NULL;
    if (git_branch && git_branch[0]) {
        if (asprintf(&args, "fetch --prune --prune-tags --tags --force origin %s",
                     git_branch) < 0) return -1;
    } else {
        if (asprintf(&args, "fetch --prune --prune-tags --tags --force") < 0) return -1;
    }
    char *stdout_buf = NULL;
    int rc = invoke_git_with_timeout(args, clone_path, 0, &stdout_buf);
    free(args);
    free(stdout_buf);
    return rc == 0 ? 0 : -1;
}

int pr_clone_ensure(const char *clone_root,
                    const char *git_url,
                    const char *git_branch,
                    const char *repo_name)
{
    if (clone_root == NULL || git_url == NULL || repo_name == NULL) return -1;
    if (mkdir_p(clone_root) != 0) {
        fprintf(stderr, "pr_clone_ensure: mkdir_p(%s) failed\n", clone_root);
        return -1;
    }

    char *clone_path = NULL;
    if (asprintf(&clone_path, "%s/%s", clone_root, repo_name) < 0) return -1;

    char *git_dir = NULL;
    if (asprintf(&git_dir, "%s/.git", clone_path) < 0) { free(clone_path); return -1; }

    /* Phase 7: per-repo flock so concurrent workers can't collide on
     * the same clone directory. Mirrors PS L 2028 Wait-ForFetchCompletion
     * mutex (simplified — flock is sufficient when we always finish a
     * clone/fetch under the lock, which our path does).
     *
     * Lock-file path: <clone_root>/.<repo_name>.lock. We never delete
     * the lock file — leaving it in place is harmless and avoids races
     * around unlink. */
    char *lock_path = NULL;
    int   lock_fd   = -1;
    if (asprintf(&lock_path, "%s/.%s.lock", clone_root, repo_name) >= 0) {
        lock_fd = open(lock_path, O_CREAT | O_RDWR, 0644);
        if (lock_fd >= 0) {
            /* Block until acquired — short critical section. */
            (void)flock(lock_fd, LOCK_EX);
        }
        free(lock_path);
    }

    /* PS L 2390-2421: up to 2 attempts, deleting and re-cloning on
     * a corrupt working tree. */
    int rc = -1;
    for (int attempt = 1; attempt <= 2; attempt++) {
        if (!dir_exists(clone_path)) {
            if (do_clone(clone_root, git_url, git_branch, repo_name) != 0) {
                fprintf(stderr, "pr_clone_ensure: clone failed (attempt %d/2)\n", attempt);
            }
        } else if (!dir_exists(git_dir)) {
            fprintf(stderr, "pr_clone_ensure: %s exists but no .git; rm+retry\n", clone_path);
            rm_rf(clone_path);
            continue;
        } else {
            if (do_fetch(clone_path, git_branch) != 0) {
                fprintf(stderr, "pr_clone_ensure: fetch failed (attempt %d/2)\n", attempt);
            }
        }
        if (dir_exists(clone_path) && dir_exists(git_dir)) { rc = 0; break; }
        if (attempt == 1) {
            rm_rf(clone_path);
        }
    }

    if (lock_fd >= 0) {
        flock(lock_fd, LOCK_UN);
        close(lock_fd);
    }
    free(git_dir);
    free(clone_path);
    return rc;
}

/* --- pr_clone_list_tags -------------------------------------------- */

int pr_clone_list_tags(const char *clone_path,
                       const char *custom_regex,
                       char     ***out_names,
                       size_t     *out_n)
{
    if (out_names == NULL || out_n == NULL) return -1;
    *out_names = NULL;
    *out_n     = 0;
    if (clone_path == NULL) return -1;

    char *stdout_buf = NULL;
    int rc = invoke_git_with_timeout("tag -l", clone_path, 120, &stdout_buf);
    if (rc != 0) {
        free(stdout_buf);
        return -1;
    }

    int prc = pr_parse_tag_list(stdout_buf, custom_regex, out_names, out_n);
    free(stdout_buf);
    return prc == 0 ? 0 : -1;
}
