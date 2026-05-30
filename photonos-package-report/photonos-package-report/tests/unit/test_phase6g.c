/* test_phase6g.c — unit tests for pr_modify_spec_file (M122).
 *
 * Asserts the line-by-line transformation matches PS L 1394-1480:
 *   - Version: line replaced
 *   - Release: line replaced with "1%{?dist}"
 *   - %define sha512 line injected right after Source0:
 *   - %changelog block prepended with new entry
 *   - %define subversion updated when present
 *   - %global commit_id updated when CommitId given
 *   - openjdk8 → Version becomes "1.8.0.<Update>"
 *   - Output file path: <upstreams>/<photon>/<subdir>/<Name>/
 *                       <basename-no-.spec>-<Update>.spec
 *   - .asc suffix stripped from the Update in the filename
 */
#include "pr_modify_spec.h"
#include "pr_types.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static int failures = 0;

#define EXPECT(cond) do {                                                  \
    if (!(cond)) {                                                         \
        fprintf(stderr, "  FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);  \
        failures++;                                                        \
    }                                                                      \
} while (0)

/* Helpers ----------------------------------------------------------- */

static char *slurp(const char *path)
{
    FILE *fp = fopen(path, "rb");
    if (!fp) return NULL;
    fseek(fp, 0, SEEK_END);
    long n = ftell(fp);
    if (n < 0) { fclose(fp); return NULL; }
    fseek(fp, 0, SEEK_SET);
    char *buf = malloc((size_t)n + 1);
    if (!buf) { fclose(fp); return NULL; }
    if (fread(buf, 1, (size_t)n, fp) != (size_t)n) { fclose(fp); free(buf); return NULL; }
    buf[n] = '\0';
    fclose(fp);
    return buf;
}

static int file_exists(const char *p) { struct stat st; return stat(p, &st) == 0; }

/* Build a minimal pr_task_t whose `content` lines and source-file
 * existence both satisfy pr_modify_spec_file. */
static pr_task_t *make_task(const char *name, const char *spec_file,
                            const char *workdir, const char *photon_dir,
                            const char **lines, size_t n_lines)
{
    pr_task_t *t = (pr_task_t *)calloc(1, sizeof *t);
    if (!t) return NULL;
    t->Name = strdup(name);
    t->Spec = strdup(spec_file);
    t->content_lines = n_lines;
    t->content = (char **)calloc(n_lines + 1, sizeof *t->content);
    for (size_t i = 0; i < n_lines; i++) t->content[i] = strdup(lines[i]);

    /* Create a placeholder source file at <workdir>/<photondir>/SPECS/<Name>/<spec_file>. */
    char dir[1024];
    snprintf(dir, sizeof dir, "%s/%s/SPECS/%s", workdir, photon_dir, name);
    char cmd[1200]; snprintf(cmd, sizeof cmd, "mkdir -p %s", dir); system(cmd);
    char path[1300]; snprintf(path, sizeof path, "%s/%s", dir, spec_file);
    FILE *fp = fopen(path, "w");
    if (fp) { for (size_t i = 0; i < n_lines; i++) fprintf(fp, "%s\n", lines[i]); fclose(fp); }
    return t;
}

static void free_task(pr_task_t *t)
{
    if (!t) return;
    free(t->Name); free(t->Spec);
    for (size_t i = 0; i < t->content_lines; i++) free(t->content[i]);
    free(t->content);
    free(t);
}

/* Tests ------------------------------------------------------------- */

static void test_default_spec(const char *tmp)
{
    fprintf(stderr, "[test_default_spec]\n");
    const char *lines[] = {
        "Name:           foo",
        "Version:        1.2.3",
        "Release:        7%{?dist}",
        "Source0:        https://example.com/foo-%{version}.tar.gz",
        "%define sha512 foo=OLDHASH",
        "BuildRequires:  gcc",
        "",
        "%changelog",
        "* Wed Jan 01 2025 Old User <old@example.com> 1.2.3-7",
        "- previous entry",
    };
    pr_task_t *t = make_task("foo", "foo.spec", tmp, "photon-5.0",
                             lines, sizeof lines / sizeof lines[0]);
    EXPECT(t != NULL);

    int rc = pr_modify_spec_file(t, tmp, tmp, "photon-5.0",
                                 "1.2.5", "%define sha512 foo=NEWHASH",
                                 0, NULL, "SPECS_NEW_C");
    EXPECT(rc == 0);

    char out_path[1024];
    snprintf(out_path, sizeof out_path,
             "%s/photon-5.0/SPECS_NEW_C/foo/foo-1.2.5.spec", tmp);
    EXPECT(file_exists(out_path));

    char *body = slurp(out_path);
    EXPECT(body != NULL);
    if (body) {
        /* Version line replaced. */
        EXPECT(strstr(body, "Version:        1.2.5") != NULL);
        EXPECT(strstr(body, "Version:        1.2.3") == NULL);
        /* Release line replaced. */
        EXPECT(strstr(body, "Release:        1%{?dist}") != NULL);
        EXPECT(strstr(body, "Release:        7%{?dist}") == NULL);
        /* Source0 kept verbatim. */
        EXPECT(strstr(body, "Source0:        https://example.com/foo-%{version}.tar.gz") != NULL);
        /* New SHA line injected, old %define sha512 dropped via $skip=$true. */
        EXPECT(strstr(body, "%define sha512 foo=NEWHASH") != NULL);
        EXPECT(strstr(body, "%define sha512 foo=OLDHASH") == NULL);
        /* %changelog: new entry block. */
        EXPECT(strstr(body, "First Last <firstname.lastname@broadcom.com> 1.2.5-1") != NULL);
        EXPECT(strstr(body, "- automatic version bump for testing purposes DO NOT USE") != NULL);
        /* Other lines untouched. */
        EXPECT(strstr(body, "BuildRequires:  gcc") != NULL);
        free(body);
    }
    free_task(t);
}

static void test_openjdk8_version(const char *tmp)
{
    fprintf(stderr, "[test_openjdk8_version]\n");
    const char *lines[] = {
        "Name:           openjdk",
        "Version:        1.8.0.382",
        "Release:        1%{?dist}",
        "Source0:        https://example.com/jdk8u382-b05.tar.gz",
        "%define sha512 openjdk=OLD",
        "%changelog",
    };
    pr_task_t *t = make_task("openjdk", "openjdk8.spec", tmp, "photon-3.0",
                             lines, sizeof lines / sizeof lines[0]);
    int rc = pr_modify_spec_file(t, tmp, tmp, "photon-3.0",
                                 "402b05", "%define sha512 openjdk=NEW",
                                 1 /* openjdk8 */, NULL, "SPECS_NEW_C");
    EXPECT(rc == 0);

    char out_path[1024];
    snprintf(out_path, sizeof out_path,
             "%s/photon-3.0/SPECS_NEW_C/openjdk/openjdk8-402b05.spec", tmp);
    EXPECT(file_exists(out_path));
    char *body = slurp(out_path);
    EXPECT(body != NULL);
    if (body) {
        EXPECT(strstr(body, "Version:        1.8.0.402b05") != NULL);
        free(body);
    }
    free_task(t);
}

static void test_subversion_and_commit_id(const char *tmp)
{
    fprintf(stderr, "[test_subversion_and_commit_id]\n");
    const char *lines[] = {
        "Name:           netcat",
        "Version:        1.0",
        "Release:        1%{?dist}",
        "%define subversion 0.0.1",
        "%global commit_id abc1234",
        "Source0:        https://example.com/nc.tar.xz",
        "%define sha512 netcat=OLD",
        "%changelog",
    };
    pr_task_t *t = make_task("netcat", "netcat.spec", tmp, "photon-6.0",
                             lines, sizeof lines / sizeof lines[0]);
    int rc = pr_modify_spec_file(t, tmp, tmp, "photon-6.0",
                                 "1.1", "%define sha512 netcat=NEW",
                                 0, "deadbeef", "SPECS_NEW_C");
    EXPECT(rc == 0);
    char out_path[1024];
    snprintf(out_path, sizeof out_path,
             "%s/photon-6.0/SPECS_NEW_C/netcat/netcat-1.1.spec", tmp);
    char *body = slurp(out_path);
    EXPECT(body != NULL);
    if (body) {
        EXPECT(strstr(body, "%define subversion 1.1") != NULL);
        EXPECT(strstr(body, "%define subversion 0.0.1") == NULL);
        EXPECT(strstr(body, "%global commit_id deadbeef") != NULL);
        EXPECT(strstr(body, "%global commit_id abc1234") == NULL);
        free(body);
    }
    free_task(t);
}

/* M125: changelog-author env-var overrides. The defaults must produce
 * the legacy "First Last <firstname.lastname@broadcom.com>" string;
 * setting any subset of PR_FIRST_NAME / PR_LAST_NAME / PR_EMAIL_ADDRESS
 * must show through, and remaining unset slots keep their defaults. */
static void test_changelog_author_default(const char *tmp)
{
    fprintf(stderr, "[test_changelog_author_default]\n");
    /* Ensure env is unset so defaults apply. */
    unsetenv("PR_FIRST_NAME"); unsetenv("PR_LAST_NAME"); unsetenv("PR_EMAIL_ADDRESS");
    const char *lines[] = {
        "Name:           foo",
        "Version:        1.0",
        "Release:        1%{?dist}",
        "Source0:        https://example.com/foo-%{version}.tar.gz",
        "%define sha512 foo=OLD",
        "%changelog",
    };
    pr_task_t *t = make_task("foo", "foo.spec", tmp, "photon-master",
                             lines, sizeof lines / sizeof lines[0]);
    int rc = pr_modify_spec_file(t, tmp, tmp, "photon-master",
                                 "2.0", "%define sha512 foo=NEW",
                                 0, NULL, "SPECS_NEW_C");
    EXPECT(rc == 0);
    char out_path[1024];
    snprintf(out_path, sizeof out_path,
             "%s/photon-master/SPECS_NEW_C/foo/foo-2.0.spec", tmp);
    char *body = slurp(out_path);
    EXPECT(body != NULL);
    if (body) {
        EXPECT(strstr(body, "First Last <firstname.lastname@broadcom.com> 2.0-1") != NULL);
        free(body);
    }
    free_task(t);
}

static void test_changelog_author_override(const char *tmp)
{
    fprintf(stderr, "[test_changelog_author_override]\n");
    setenv("PR_FIRST_NAME",    "Ada",                  1);
    setenv("PR_LAST_NAME",     "Lovelace",             1);
    setenv("PR_EMAIL_ADDRESS", "ada@example.com",      1);
    const char *lines[] = {
        "Name:           bar",
        "Version:        0.1",
        "Release:        1%{?dist}",
        "Source0:        https://example.com/bar-%{version}.tar.gz",
        "%define sha512 bar=OLD",
        "%changelog",
    };
    pr_task_t *t = make_task("bar", "bar.spec", tmp, "photon-6.0",
                             lines, sizeof lines / sizeof lines[0]);
    int rc = pr_modify_spec_file(t, tmp, tmp, "photon-6.0",
                                 "0.2", "%define sha512 bar=NEW",
                                 0, NULL, "SPECS_NEW_C");
    EXPECT(rc == 0);
    char out_path[1024];
    snprintf(out_path, sizeof out_path,
             "%s/photon-6.0/SPECS_NEW_C/bar/bar-0.2.spec", tmp);
    char *body = slurp(out_path);
    EXPECT(body != NULL);
    if (body) {
        EXPECT(strstr(body, "Ada Lovelace <ada@example.com> 0.2-1") != NULL);
        EXPECT(strstr(body, "First Last <firstname.lastname@broadcom.com>") == NULL);
        free(body);
    }
    free_task(t);
    unsetenv("PR_FIRST_NAME"); unsetenv("PR_LAST_NAME"); unsetenv("PR_EMAIL_ADDRESS");
}

static void test_asc_suffix_strip(const char *tmp)
{
    fprintf(stderr, "[test_asc_suffix_strip]\n");
    const char *lines[] = {
        "Name:           foo",
        "Version:        1.0",
        "Release:        1%{?dist}",
        "Source0:        https://example.com/foo-%{version}.tar.gz",
        "%define sha512 foo=OLD",
        "%changelog",
    };
    pr_task_t *t = make_task("foo", "foo.spec", tmp, "photon-dev",
                             lines, sizeof lines / sizeof lines[0]);
    int rc = pr_modify_spec_file(t, tmp, tmp, "photon-dev",
                                 "2.0.tar.asc", "%define sha512 foo=NEW",
                                 0, NULL, "SPECS_NEW_C");
    EXPECT(rc == 0);
    /* .asc stripped from the filename — PS L 1473. */
    char out_path[1024];
    snprintf(out_path, sizeof out_path,
             "%s/photon-dev/SPECS_NEW_C/foo/foo-2.0.tar.spec", tmp);
    EXPECT(file_exists(out_path));
    free_task(t);
}

int main(void)
{
    /* Set up a tmp tree. */
    char tmpdir[256];
    snprintf(tmpdir, sizeof tmpdir, "/tmp/test_phase6g_%d", (int)getpid());
    char cmd[400]; snprintf(cmd, sizeof cmd, "rm -rf %s && mkdir -p %s", tmpdir, tmpdir);
    system(cmd);

    test_default_spec(tmpdir);
    test_openjdk8_version(tmpdir);
    test_subversion_and_commit_id(tmpdir);
    test_changelog_author_default(tmpdir);
    test_changelog_author_override(tmpdir);
    test_asc_suffix_strip(tmpdir);

    /* Cleanup. */
    snprintf(cmd, sizeof cmd, "rm -rf %s", tmpdir); system(cmd);

    if (failures > 0) {
        fprintf(stderr, "FAIL: %d assertion(s) failed\n", failures);
        return 1;
    }
    fprintf(stderr, "PASS\n");
    return 0;
}
