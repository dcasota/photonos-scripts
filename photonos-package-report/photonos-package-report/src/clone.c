/* clone.c — local-clone manager (Phase 6d, sequential).
 * Mirrors photonos-package-report.ps1 L 2358-2456.
 */
/* _GNU_SOURCE for asprintf comes from CMake; do not redefine. */
#include "pr_clone.h"
#include "pr_git_tags.h"
#include "photonos_package_report.h"  /* invoke_git_with_timeout from Phase 1 */

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <ftw.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#include <pthread.h>

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

/* Case-insensitive substring (POSIX strcasestr is GNU/BSD only; roll
 * our own to keep src/clone.c self-contained). Returns 1 iff `needle`
 * occurs in `haystack` ignoring ASCII case. */
static int ci_substr(const char *haystack, const char *needle)
{
    if (!haystack || !needle || !*needle) return 0;
    size_t hl = strlen(haystack);
    size_t nl = strlen(needle);
    if (nl > hl) return 0;
    for (size_t i = 0; i + nl <= hl; i++) {
        if (strncasecmp(haystack + i, needle, nl) == 0) return 1;
    }
    return 0;
}

/* --- pr_should_skip_clone ------------------------------------------- */

int pr_should_skip_clone(const char *repo_name, const char *exclusion_list)
{
    if (!repo_name || !exclusion_list || !*exclusion_list) return 0;

    /* Walk comma-separated tokens. Trim ASCII whitespace. Empty tokens
     * (consecutive commas, all-whitespace cells) are skipped. */
    const char *p = exclusion_list;
    while (*p) {
        const char *comma = strchr(p, ',');
        const char *end   = comma ? comma : p + strlen(p);

        const char *tok_start = p;
        const char *tok_end   = end;
        while (tok_start < tok_end && isspace((unsigned char)*tok_start)) tok_start++;
        while (tok_end > tok_start && isspace((unsigned char)*(tok_end - 1))) tok_end--;

        size_t len = (size_t)(tok_end - tok_start);
        if (len > 0) {
            char *tok = (char *)malloc(len + 1);
            if (!tok) return 0;
            memcpy(tok, tok_start, len);
            tok[len] = '\0';
            int hit = ci_substr(repo_name, tok);
            free(tok);
            if (hit) return 1;
        }

        if (!comma) break;
        p = comma + 1;
    }
    return 0;
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
    /* Partial clone: --no-checkout skips populating the working tree;
     * --filter=blob:none defers blob fetches. The C binary only ever
     * calls `git tag -l` on the result (see pr_clone_list_tags), so
     * blobs are never demanded and tags resolve from the lightweight
     * commit/tree object set. For big repos (llvm-project, dotnet/
     * runtime, elasticsearch, …) this cuts clone time 10–100×.
     *
     * Parity impact: zero. `.prn` columns 5/6/10 depend only on the
     * tag list, which is identical between full and partial clones. */
    char *args = NULL;
    if (git_branch && git_branch[0]) {
        if (asprintf(&args, "clone --no-checkout --filter=blob:none %s -b %s %s",
                     git_url, git_branch, repo_name) < 0) return -1;
    } else {
        if (asprintf(&args, "clone --no-checkout --filter=blob:none %s %s",
                     git_url, repo_name) < 0) return -1;
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

/* --- M65 / Option-D step 1: recorded-SHA tag pin -------------------
 *
 * Temporal drift: C clones upstreams LIVE, so `git tag -l` includes tags
 * pushed AFTER the PS snapshot, making C pick a newer version than PS did.
 * Fix (record-replay): the snapshot's upstream-clones-manifest.tsv records
 * each upstream's HEAD SHA at PS-time. When PR_UPSTREAM_SHA_MANIFEST points
 * at it, list tags AS OF that SHA via `git tag --merged <sha>` — tags whose
 * commit is reachable from the recorded HEAD, i.e. the set PS saw. Tags on
 * later commits are excluded → deterministic, no temporal drift. Falls back
 * to `git tag -l` when no SHA is recorded or --merged fails. */
struct sha_ent { char *branch; char *repo; char *sha; };
static struct sha_ent *g_sha_man = NULL;
static size_t           g_sha_n   = 0;
static pthread_once_t   g_sha_once = PTHREAD_ONCE_INIT;

static void load_sha_manifest(void)
{
    const char *path = getenv("PR_UPSTREAM_SHA_MANIFEST");
    if (path == NULL || path[0] == '\0') return;
    FILE *f = fopen(path, "r");
    if (!f) return;
    size_t cap = 1024;
    g_sha_man = (struct sha_ent *)malloc(cap * sizeof *g_sha_man);
    if (!g_sha_man) { fclose(f); return; }
    char line[4096];
    while (fgets(line, sizeof line, f)) {
        char *nl = strchr(line, '\n'); if (nl) *nl = '\0';
        /* branch \t repo \t url \t sha */
        char *b = line;
        char *t1 = strchr(b, '\t'); if (!t1) continue; *t1 = '\0';
        char *r = t1 + 1;
        char *t2 = strchr(r, '\t'); if (!t2) continue; *t2 = '\0';
        char *u = t2 + 1;
        char *t3 = strchr(u, '\t'); if (!t3) continue; *t3 = '\0';
        char *s = t3 + 1;
        if (s[0] == '\0' || strcmp(s, "unknown") == 0) continue;
        if (g_sha_n == cap) {
            cap *= 2;
            struct sha_ent *p = (struct sha_ent *)realloc(g_sha_man, cap * sizeof *g_sha_man);
            if (!p) break;
            g_sha_man = p;
        }
        g_sha_man[g_sha_n].branch = strdup(b);
        g_sha_man[g_sha_n].repo   = strdup(r);
        g_sha_man[g_sha_n].sha    = strdup(s);
        if (g_sha_man[g_sha_n].branch && g_sha_man[g_sha_n].repo && g_sha_man[g_sha_n].sha)
            g_sha_n++;
    }
    fclose(f);
}

/* clone_path is ".../photon-<branch>/clones/<repo>"; look up the recorded
 * SHA for (branch, repo). Returns a borrowed pointer or NULL. */
static const char *recorded_sha_for(const char *clone_path)
{
    pthread_once(&g_sha_once, load_sha_manifest);
    if (g_sha_man == NULL || clone_path == NULL) return NULL;
    size_t n = strlen(clone_path);
    /* repo = last path segment */
    const char *repo = clone_path + n;
    while (repo > clone_path && *(repo - 1) != '/') repo--;
    /* branch = the "photon-<branch>" two levels up (.../photon-<b>/clones/<repo>) */
    const char *clones_end = repo;            /* points just past the last '/' */
    if (clones_end > clone_path) clones_end--; /* the '/' before repo */
    const char *clones = clones_end;
    while (clones > clone_path && *(clones - 1) != '/') clones--;   /* "clones" seg start */
    const char *brdir_end = (clones > clone_path) ? clones - 1 : clones;
    const char *brdir = brdir_end;
    while (brdir > clone_path && *(brdir - 1) != '/') brdir--;       /* "photon-<branch>" start */
    /* brdir .. brdir_end is the full "photon-<branch>" dir name — the manifest
     * records the branch column as basename(branch_dir), i.e. "photon-5.0". */
    size_t brlen = (size_t)(brdir_end - brdir);
    for (size_t i = 0; i < g_sha_n; i++) {
        if (strcmp(g_sha_man[i].repo, repo) == 0
            && strncmp(g_sha_man[i].branch, brdir, brlen) == 0
            && g_sha_man[i].branch[brlen] == '\0')
            return g_sha_man[i].sha;
    }
    return NULL;
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
    int rc = -1;
    /* M65: pin to the recorded SHA when replaying a snapshot. */
    const char *sha = recorded_sha_for(clone_path);
    if (sha) {
        char *args = NULL;
        if (asprintf(&args, "tag --merged %s", sha) >= 0 && args) {
            rc = invoke_git_with_timeout(args, clone_path, 120, &stdout_buf);
            free(args);
        }
    }
    /* Fall back to the live tag list when not pinned, or if --merged failed
     * (e.g. the recorded SHA isn't present after a force-push). */
    if (rc != 0) {
        free(stdout_buf); stdout_buf = NULL;
        rc = invoke_git_with_timeout("tag -l", clone_path, 120, &stdout_buf);
    }
    if (rc != 0) {
        free(stdout_buf);
        return -1;
    }

    int prc = pr_parse_tag_list(stdout_buf, custom_regex, out_names, out_n);
    free(stdout_buf);
    return prc == 0 ? 0 : -1;
}
