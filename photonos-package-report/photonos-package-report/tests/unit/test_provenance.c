/* test_provenance.c — PR_VERIFY_PROVENANCE: the rung ladder, its parsers,
 * the sidecar record, and gpgv against a throwaway key. No network: every
 * evidence fetch goes through a table-driven fake. */
#include "pr_provenance.h"
#include "pr_sha.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
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
#define EXPECT_INT(actual, expected) do {                                      \
    long _a = (long)(actual); long _e = (long)(expected);                      \
    if (_a != _e) {                                                            \
        fprintf(stderr, "  FAIL %s:%d: expected %ld got %ld\n",                \
                __FILE__, __LINE__, _e, _a);                                   \
        failures++;                                                            \
    }                                                                          \
} while (0)

/* --- fake fetcher ---------------------------------------------------- */

typedef struct { const char *url; const char *body; size_t len; } route_t;
typedef struct { route_t r[16]; int n; int calls; char seen[32][256]; } fake_t;

static void route(fake_t *f, const char *url, const char *body, size_t len)
{
    f->r[f->n].url = url;
    f->r[f->n].body = body;
    f->r[f->n].len = len ? len : strlen(body);
    f->n++;
}

static long fake_fetch(void *ctx, const char *url, const char *accept, size_t max,
                       char **body, size_t *len)
{
    fake_t *f = (fake_t *)ctx;
    if (f->calls < 32) snprintf(f->seen[f->calls], 256, "%s", url);
    f->calls++;
    /* pypi.org answers HTML unless the PEP 691 JSON type is negotiated. */
    if (strstr(url, "://pypi.org/simple/") != NULL
        && (accept == NULL || strcmp(accept, "application/vnd.pypi.simple.v1+json") != 0)) {
        *body = strdup("<!DOCTYPE html><html></html>");
        *len = strlen(*body);
        return 200;
    }
    *body = NULL; *len = 0;
    if (strncmp(url, "https://", 8) != 0) return 0;
    for (int i = 0; i < f->n; i++) {
        if (strcmp(f->r[i].url, url) == 0) {
            if (f->r[i].len > max) return 0;
            *body = malloc(f->r[i].len + 1);
            memcpy(*body, f->r[i].body, f->r[i].len);
            (*body)[f->r[i].len] = '\0';
            *len = f->r[i].len;
            return 200;
        }
    }
    return 404;
}

static char g_dir[] = "/tmp/test_provenance_XXXXXX";

static char *write_file(const char *name, const char *data)
{
    char *p = NULL;
    if (asprintf(&p, "%s/%s", g_dir, name) < 0) abort();
    FILE *f = fopen(p, "wb");
    fwrite(data, 1, strlen(data), f);
    fclose(f);
    return p;
}

static void lower(char *s) { for (; *s; s++) *s = (char)tolower((unsigned char)*s); }

static const char *TARBALL = "hello provenance\n";
static char SHA256[65], SHA512[129];

/* --- parsers --------------------------------------------------------- */

static void test_sums_lookup(void)
{
    fprintf(stderr, "[test_sums_lookup]\n");
    char alg[8], hex[129];
    char body[2048];
    snprintf(body, sizeof body,
             "%s  other-1.0.tar.xz\n%s *zlib-1.3.2.tar.xz\n", SHA256, SHA512);
    EXPECT_INT(pr_prov_sums_lookup(body, strlen(body), "zlib-1.3.2.tar.xz", 0, alg, hex), 1);
    EXPECT_STREQ(alg, "sha512");
    EXPECT_STREQ(hex, SHA512);
    /* a name that is only a suffix of a listed name does not match */
    EXPECT_INT(pr_prov_sums_lookup(body, strlen(body), "lib-1.3.2.tar.xz", 0, alg, hex), 0);

    snprintf(body, sizeof body, "SHA256 (zlib-1.3.2.tar.xz) = %s\n", SHA256);
    EXPECT_INT(pr_prov_sums_lookup(body, strlen(body), "zlib-1.3.2.tar.xz", 0, alg, hex), 1);
    EXPECT_STREQ(alg, "sha256");
    EXPECT_STREQ(hex, SHA256);

    snprintf(body, sizeof body, "%s  ./dist/zlib-1.3.2.tar.xz\r\n", SHA256);
    EXPECT_INT(pr_prov_sums_lookup(body, strlen(body), "zlib-1.3.2.tar.xz", 0, alg, hex), 1);

    /* a lone digest only counts for a per-file sidecar */
    snprintf(body, sizeof body, "%s\n", SHA256);
    EXPECT_INT(pr_prov_sums_lookup(body, strlen(body), "zlib-1.3.2.tar.xz", 0, alg, hex), 0);
    EXPECT_INT(pr_prov_sums_lookup(body, strlen(body), "zlib-1.3.2.tar.xz", 1, alg, hex), 1);

    /* sha1 / md5 are not evidence */
    const char *weak = "a9993e364706816aba3e25717850c26c9cd0d89d  zlib-1.3.2.tar.xz\n"
                       "900150983cd24fb0d6963f7d28e17f72  zlib-1.3.2.tar.xz\n";
    EXPECT_INT(pr_prov_sums_lookup(weak, strlen(weak), "zlib-1.3.2.tar.xz", 1, alg, hex), 0);
    /* an HTML soft-404 is not a checksum file */
    const char *html = "<html><body>Not found</body></html>\n";
    EXPECT_INT(pr_prov_sums_lookup(html, strlen(html), "zlib-1.3.2.tar.xz", 1, alg, hex), 0);
}

static void test_registry_parsers(void)
{
    fprintf(stderr, "[test_registry_parsers]\n");
    char hex[129];
    char j[4096];
    /* PEP 691: core-metadata carries its own sha256 before the file's. */
    snprintf(j, sizeof j,
        "{\"files\":[{\"core-metadata\":{\"sha256\":\"%s\"},\"filename\":\"PyYAML-6.0.tar.gz\","
        "\"hashes\":{\"sha256\":\"%s\"},\"url\":\"u\"},"
        "{\"filename\":\"PyYAML-6.0.1.tar.gz\",\"hashes\":{\"sha256\":\"%s\"}}],\"name\":\"pyyaml\"}",
        "00000000000000000000000000000000000000000000000000000000000000ff", SHA256,
        "1111111111111111111111111111111111111111111111111111111111111111");
    EXPECT_INT(pr_prov_pypi_sha256(j, strlen(j), "PyYAML-6.0.tar.gz", hex), 1);
    EXPECT_STREQ(hex, SHA256);
    EXPECT_INT(pr_prov_pypi_sha256(j, strlen(j), "PyYAML-6.0.1.tar.gz", hex), 1);
    EXPECT_STREQ(hex, "1111111111111111111111111111111111111111111111111111111111111111");
    EXPECT_INT(pr_prov_pypi_sha256(j, strlen(j), "PyYAML-7.0.tar.gz", hex), 0);
    /* metacharacters in a file name are literal */
    EXPECT_INT(pr_prov_pypi_sha256(j, strlen(j), "PyYAML-6.0.tar.g.", hex), 0);

    snprintf(j, sizeof j, "{\"number\":\"7.1.0\",\"spec_sha\":\"%s\",\"platform\":\"ruby\",\"sha\":\"%s\"}",
             "2222222222222222222222222222222222222222222222222222222222222222", SHA256);
    EXPECT_INT(pr_prov_rubygems_sha256(j, strlen(j), hex), 1);
    EXPECT_STREQ(hex, SHA256);

    snprintf(j, sizeof j,
        "{\"name\":\"v1.2.3\",\"assets\":["
        "{\"name\":\"tool-1.2.3.tar.gz\",\"uploader\":{\"login\":\"x\",\"name\":\"tool-1.2.3.tar.gz\"},"
        "\"digest\":\"sha256:%s\",\"browser_download_url\":\"https://github.com/o/r/releases/download/v1.2.3/tool-1.2.3.tar.gz\"},"
        "{\"name\":\"tool-1.2.3.zip\",\"digest\":null,\"browser_download_url\":\"z\"}]}", SHA256);
    EXPECT_INT(pr_prov_github_digest(j, strlen(j), "tool-1.2.3.tar.gz", hex), 1);
    EXPECT_STREQ(hex, SHA256);
    EXPECT_INT(pr_prov_github_digest(j, strlen(j), "tool-1.2.3.zip", hex), 0);
    EXPECT_INT(pr_prov_github_digest(j, strlen(j), "v1.2.3", hex), 0);

    char f[1024];
    snprintf(f, sizeof f, "SHA512 (zlib-1.3.2.tar.xz) = %s\nSHA512 (zlib.sig) = %s\n", SHA512, SHA512);
    EXPECT_INT(pr_prov_fedora_sha512(f, strlen(f), "zlib-1.3.2.tar.xz", hex), 1);
    EXPECT_STREQ(hex, SHA512);
    EXPECT_INT(pr_prov_fedora_sha512(f, strlen(f), "zlib-1.3.3.tar.xz", hex), 0);
}

static void test_clearsigned(void)
{
    fprintf(stderr, "[test_clearsigned]\n");
    const char *m =
        "-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA256\n\n"
        "abc  a.tar.xz\n- -dash line\n"
        "-----BEGIN PGP SIGNATURE-----\n\nxyz\n-----END PGP SIGNATURE-----\n";
    char *t = NULL; size_t n = 0;
    EXPECT_INT(pr_prov_clearsigned_text(m, strlen(m), &t, &n), 1);
    EXPECT_STREQ(t, "abc  a.tar.xz\n-dash line");
    free(t);
    EXPECT_INT(pr_prov_clearsigned_text("plain", 5, &t, &n), 0);
}

static void test_url_host(void)
{
    fprintf(stderr, "[test_url_host]\n");
    char h[64];
    EXPECT_INT(pr_prov_url_host("https://User@Download.GNOME.org:443/x", h, sizeof h), 1);
    EXPECT_STREQ(h, "download.gnome.org");
    EXPECT_INT(pr_prov_url_host("not a url", h, sizeof h), 0);
}

/* --- the ladder ------------------------------------------------------ */

static void run(const char *url, const char *path, fake_t *f, const char *keyring,
                pr_prov_record_t *r)
{
    pr_prov_input_t in = { 0 };
    in.package = "zlib";
    in.spec = "zlib.spec";
    in.url = url;
    in.file_path = path;
    in.keyring = keyring;
    in.fetch = fake_fetch;
    in.fetch_ctx = f;
    EXPECT_INT(pr_provenance_verify(&in, r), 0);
}

static const pr_prov_evidence_t *find(const pr_prov_record_t *r, const char *rung)
{
    for (size_t i = 0; i < r->n; i++) if (!strcmp(r->ev[i].rung, rung)) return &r->ev[i];
    return NULL;
}

static void test_ladder(void)
{
    fprintf(stderr, "[test_ladder]\n");
    char *path = write_file("zlib-1.3.2.tar.xz", TARBALL);
    const char *U = "https://zlib.net/zlib-1.3.2.tar.xz";
    pr_prov_record_t r;
    char body[1024];

    /* TOFU: nothing published anywhere. */
    fake_t f0 = { 0 };
    run(U, path, &f0, NULL, &r);
    EXPECT_STREQ(r.verdict, "unverified");
    EXPECT_STREQ(r.rung, "tofu");
    EXPECT_INT(r.n, 0);
    EXPECT_STREQ(r.sha512, SHA512);
    EXPECT_INT(r.size, strlen(TARBALL));
    pr_provenance_free(&r);

    /* A per-file .sha256 at the vendor origin that agrees. */
    fake_t f1 = { 0 };
    snprintf(body, sizeof body, "%s\n", SHA256);
    route(&f1, "https://zlib.net/zlib-1.3.2.tar.xz.sha256", body, 0);
    run(U, path, &f1, NULL, &r);
    EXPECT_STREQ(r.verdict, "verified");
    EXPECT_STREQ(r.rung, "vendor_checksum");
    const pr_prov_evidence_t *e = find(&r, "vendor_checksum");
    EXPECT_INT(e != NULL, 1);
    if (e) {
        EXPECT_INT(e->same_origin, 1);
        EXPECT_STREQ(e->expected, SHA256);
        EXPECT_STREQ(e->actual, SHA256);
        EXPECT_STREQ(e->url, "https://zlib.net/zlib-1.3.2.tar.xz.sha256");
    }
    pr_provenance_free(&r);

    /* A directory SHA256SUMS that DISAGREES: mismatch, whatever else holds. */
    fake_t f2 = { 0 };
    char sums[512];
    snprintf(sums, sizeof sums, "%s  zlib-1.3.2.tar.xz\n",
             "3333333333333333333333333333333333333333333333333333333333333333");
    route(&f2, "https://zlib.net/SHA256SUMS", sums, 0);
    char fed[512];
    snprintf(fed, sizeof fed, "SHA512 (zlib-1.3.2.tar.xz) = %s\n", SHA512);
    route(&f2, "https://src.fedoraproject.org/rpms/zlib/raw/rawhide/f/sources", fed, 0);
    run(U, path, &f2, NULL, &r);
    EXPECT_STREQ(r.verdict, "mismatch");
    e = find(&r, "vendor_checksum");
    EXPECT_INT(e && e->result == PR_EV_MISMATCH, 1);
    e = find(&r, "corroborated");
    EXPECT_INT(e && e->result == PR_EV_VERIFIED, 1);
    pr_provenance_free(&r);

    /* Corroboration alone. */
    fake_t f3 = { 0 };
    route(&f3, "https://src.fedoraproject.org/rpms/zlib/raw/rawhide/f/sources", fed, 0);
    run(U, path, &f3, NULL, &r);
    EXPECT_STREQ(r.verdict, "verified");
    EXPECT_STREQ(r.rung, "corroborated");
    pr_provenance_free(&r);

    /* Fedora recording ANOTHER digest under this name is a mismatch. */
    fake_t f4 = { 0 };
    char fed_bad[512];
    snprintf(fed_bad, sizeof fed_bad, "SHA512 (zlib-1.3.2.tar.xz) = %0128d\n", 0);
    route(&f4, "https://src.fedoraproject.org/rpms/zlib/raw/rawhide/f/sources", fed_bad, 0);
    run(U, path, &f4, NULL, &r);
    EXPECT_STREQ(r.verdict, "mismatch");
    pr_provenance_free(&r);

    /* PyPI: the registry digest, from another host than the tarball. */
    char *py = write_file("PyYAML-6.0.tar.gz", TARBALL);
    fake_t f5 = { 0 };
    char pj[1024];
    snprintf(pj, sizeof pj, "{\"files\":[{\"filename\":\"PyYAML-6.0.tar.gz\",\"hashes\":{\"sha256\":\"%s\"}}]}", SHA256);
    route(&f5, "https://pypi.org/simple/pyyaml/", pj, 0);
    pr_prov_input_t in = { 0 };
    in.package = "python3-PyYAML"; in.spec = "python3-pyyaml.spec";
    in.url = "https://files.pythonhosted.org/packages/source/P/PyYAML/PyYAML-6.0.tar.gz";
    in.file_path = py; in.fetch = fake_fetch; in.fetch_ctx = &f5;
    EXPECT_INT(pr_provenance_verify(&in, &r), 0);
    EXPECT_STREQ(r.rung, "registry_digest");
    e = find(&r, "registry_digest");
    EXPECT_INT(e && e->same_origin == 0, 1);
    /* the JSON form of the simple index is content-negotiated */
    EXPECT_INT(f5.calls > 0, 1);
    pr_provenance_free(&r);

    /* rubygems: <gem>-<version>.gem split at the last "-<digit>". */
    char *gem = write_file("aws-sdk-core-3.1.0.gem", TARBALL);
    fake_t f6 = { 0 };
    char gj[512];
    snprintf(gj, sizeof gj, "{\"sha\":\"%s\"}", SHA256);
    route(&f6, "https://rubygems.org/api/v2/rubygems/aws-sdk-core/versions/3.1.0.json", gj, 0);
    in.url = "https://rubygems.org/downloads/aws-sdk-core-3.1.0.gem";
    in.file_path = gem; in.fetch_ctx = &f6; in.package = "rubygem-aws-sdk-core";
    EXPECT_INT(pr_provenance_verify(&in, &r), 0);
    EXPECT_STREQ(r.rung, "registry_digest");
    pr_provenance_free(&r);

    /* The local file name may differ from the vendor's (download_name_post):
     * vendor evidence is matched on the URL's file name. */
    char *ren = write_file("open-vm-tools-12.0.tar.gz", TARBALL);
    fake_t f7 = { 0 };
    char s7[512];
    snprintf(s7, sizeof s7, "%s  12.0.tar.gz\n", SHA256);
    route(&f7, "https://example.org/rel/SHA256SUMS", s7, 0);
    in.url = "https://example.org/rel/12.0.tar.gz";
    in.file_path = ren; in.fetch_ctx = &f7; in.package = "open-vm-tools";
    EXPECT_INT(pr_provenance_verify(&in, &r), 0);
    EXPECT_STREQ(r.rung, "vendor_checksum");
    pr_provenance_free(&r);

    /* An http:// tarball URL: no vendor evidence is fetched at all (a
     * plaintext checksum vouches for nothing); corroboration still runs. */
    fake_t f8 = { 0 };
    run("http://zlib.net/zlib-1.3.2.tar.xz", path, &f8, NULL, &r);
    EXPECT_STREQ(r.rung, "tofu");
    EXPECT_INT(f8.calls, 1);
    EXPECT_INT(strstr(f8.seen[0], "src.fedoraproject.org") != NULL, 1);
    pr_provenance_free(&r);

    /* A signature present but no keyring: recorded unverifiable, not verified. */
    fake_t f9 = { 0 };
    route(&f9, "https://zlib.net/zlib-1.3.2.tar.xz.asc", "-----BEGIN PGP SIGNATURE-----\nx\n", 0);
    run(U, path, &f9, NULL, &r);
    EXPECT_STREQ(r.verdict, "unverified");
    e = find(&r, "signature");
    EXPECT_INT(e && e->result == PR_EV_UNVERIFIABLE, 1);
    pr_provenance_free(&r);

    /* An unreadable file is an error, never a record. */
    pr_prov_input_t bad = { 0 };
    bad.url = U; bad.file_path = "/nonexistent/x.tar.xz";
    EXPECT_INT(pr_provenance_verify(&bad, &r), -1);

    free(path); free(py); free(gem); free(ren);
}

static void test_record_json(void)
{
    fprintf(stderr, "[test_record_json]\n");
    char *path = write_file("q\"uote.tar.gz", TARBALL);
    fake_t f = { 0 };
    pr_prov_record_t r;
    run("https://h.example/q%22uote.tar.gz?token=SECRET#frag", path, &f, NULL, &r);
    char *j = pr_provenance_json(&r);
    EXPECT_INT(j != NULL, 1);
    if (j) {
        EXPECT_INT(strstr(j, "\"schema\":\"" PR_PROVENANCE_SCHEMA "\"") != NULL, 1);
        EXPECT_INT(strstr(j, "\"file\":\"q\\\"uote.tar.gz\"") != NULL, 1);
        /* the query (a possible token) never reaches the record */
        EXPECT_INT(strstr(j, "SECRET") == NULL, 1);
        EXPECT_INT(strstr(j, "\"rung\":\"tofu\"") != NULL, 1);
        EXPECT_INT(strstr(j, "\"evidence\":[]") != NULL, 1);
        free(j);
    }
    char *out = NULL;
    if (asprintf(&out, "%s%s", path, PR_PROVENANCE_SUFFIX) < 0) abort();
    EXPECT_INT(pr_provenance_write(&r, out), 0);
    struct stat st;
    EXPECT_INT(stat(out, &st), 0);
    unlink(out);
    pr_provenance_free(&r);

    /* The hook is a no-op unless PR_VERIFY_PROVENANCE is set. */
    unsetenv("PR_VERIFY_PROVENANCE");
    pr_provenance_after_download("p", "p.spec", "http://h.example/x", path);
    EXPECT_INT(stat(out, &st), -1);
    setenv("PR_VERIFY_PROVENANCE", "0", 1);
    EXPECT_INT(pr_provenance_enabled(), 0);
    setenv("PR_VERIFY_PROVENANCE", "1", 1);
    EXPECT_INT(pr_provenance_enabled(), 1);
    /* http URL + no package: no network is touched, a tofu record lands. */
    pr_provenance_after_download("", "p.spec", "http://h.example/x", path);
    EXPECT_INT(stat(out, &st), 0);
    unlink(out);
    unsetenv("PR_VERIFY_PROVENANCE");
    free(out);
    free(path);
}

/* --- gpgv against a throwaway key ------------------------------------ */

static int sh(const char *cmd)
{
    int rc = system(cmd);
    return (rc == -1) ? -1 : WEXITSTATUS(rc);
}

static char *slurp(const char *p, size_t *n)
{
    FILE *f = fopen(p, "rb");
    if (!f) return NULL;
    char *b = malloc(1 << 16);
    *n = fread(b, 1, (1 << 16) - 1, f);
    b[*n] = '\0';
    fclose(f);
    return b;
}

static void test_gpgv(void)
{
    fprintf(stderr, "[test_gpgv]\n");
    if (sh("command -v gpg >/dev/null 2>&1 && command -v gpgv >/dev/null 2>&1") != 0) {
        fprintf(stderr, "  SKIP: gpg/gpgv not installed\n");
        return;
    }
    char cmd[2048];
    snprintf(cmd, sizeof cmd,
        "set -e; export GNUPGHOME=%1$s/gh; mkdir -m 700 -p $GNUPGHOME; "
        "gpg -q --batch --pinentry-mode loopback --passphrase '' "
        "--quick-gen-key 'Vendor <vendor@example.invalid>' ed25519 sign never 2>/dev/null; "
        "gpg -q --batch --export > %1$s/vendor.gpg; "
        "gpg -q --batch --pinentry-mode loopback --passphrase '' --detach-sign "
        "-o %1$s/zlib-1.3.2.tar.xz.sig %1$s/zlib-1.3.2.tar.xz; "
        "printf '%%s  zlib-1.3.2.tar.xz\\n' %2$s > %1$s/SHA256SUMS; "
        "gpg -q --batch --pinentry-mode loopback --passphrase '' --clearsign "
        "-o %1$s/sha256sums.asc %1$s/SHA256SUMS; "
        "gpg -q --batch --with-colons --fingerprint | awk -F: '/^fpr/{print $10; exit}' > %1$s/fpr; "
        "GNUPGHOME=%1$s/gh2; mkdir -m 700 -p %1$s/gh2; export GNUPGHOME=%1$s/gh2; "
        "gpg -q --batch --pinentry-mode loopback --passphrase '' "
        "--quick-gen-key 'Other <other@example.invalid>' ed25519 sign never 2>/dev/null; "
        "gpg -q --batch --export > %1$s/other.gpg",
        g_dir, SHA256);
    char *path = write_file("zlib-1.3.2.tar.xz", TARBALL);
    if (sh(cmd) != 0) {
        fprintf(stderr, "  SKIP: could not create a throwaway key\n");
        free(path);
        return;
    }
    char p[512];
    size_t fn = 0, sn = 0, an = 0;
    snprintf(p, sizeof p, "%s/fpr", g_dir);
    char *fpr = slurp(p, &fn);
    while (fn && isspace((unsigned char)fpr[fn - 1])) fpr[--fn] = '\0';
    snprintf(p, sizeof p, "%s/zlib-1.3.2.tar.xz.sig", g_dir);
    char *sig = slurp(p, &sn);
    snprintf(p, sizeof p, "%s/sha256sums.asc", g_dir);
    char *asc = slurp(p, &an);
    char kr[512], other[512];
    snprintf(kr, sizeof kr, "%s/vendor.gpg", g_dir);
    snprintf(other, sizeof other, "%s/other.gpg", g_dir);
    const char *U = "https://zlib.net/zlib-1.3.2.tar.xz";
    pr_prov_record_t r;

    /* detached signature, pinned key: the strongest rung, with its fpr */
    fake_t f1 = { 0 };
    route(&f1, "https://zlib.net/zlib-1.3.2.tar.xz.sig", sig, sn);
    run(U, path, &f1, kr, &r);
    EXPECT_STREQ(r.verdict, "verified");
    EXPECT_STREQ(r.rung, "signature");
    const pr_prov_evidence_t *e = find(&r, "signature");
    EXPECT_STREQ(e ? e->fingerprint : NULL, fpr);
    pr_provenance_free(&r);

    /* the key is not in the keyring: unverifiable, the keyid is named */
    run(U, path, &f1, other, &r);
    EXPECT_STREQ(r.verdict, "unverified");
    e = find(&r, "signature");
    EXPECT_INT(e && e->result == PR_EV_UNVERIFIABLE && e->fingerprint[0] == '\0', 1);
    EXPECT_INT(e && e->detail && strstr(e->detail, "not in the configured keyring") != NULL, 1);
    pr_provenance_free(&r);

    /* clearsigned checksum list (kernel.org style) */
    fake_t f2 = { 0 };
    route(&f2, "https://zlib.net/sha256sums.asc", asc, an);
    run(U, path, &f2, kr, &r);
    EXPECT_STREQ(r.verdict, "verified");
    EXPECT_STREQ(r.rung, "signature");
    e = find(&r, "signature");
    EXPECT_INT(e && !strcmp(e->expected, SHA256), 1);
    pr_provenance_free(&r);

    /* tampered bytes: BAD signature -> mismatch */
    char *tampered = write_file("zlib-1.3.2.tar.xz", "hello provenancE\n");
    run(U, tampered, &f1, kr, &r);
    EXPECT_STREQ(r.verdict, "mismatch");
    pr_provenance_free(&r);
    /* ...and a good signature over a checksum list that lists other bytes */
    run(U, tampered, &f2, kr, &r);
    EXPECT_STREQ(r.verdict, "mismatch");
    pr_provenance_free(&r);

    /* gpgv missing */
    char f_[41], k_[17];
    snprintf(p, sizeof p, "%s/zlib-1.3.2.tar.xz.sig", g_dir);
    EXPECT_INT(pr_prov_gpgv("/nonexistent/gpgv", kr, p, tampered, f_, k_), -2);

    free(fpr); free(sig); free(asc); free(path); free(tampered);
}

int main(void)
{
    if (!mkdtemp(g_dir)) { perror("mkdtemp"); return 1; }
    char *h = pr_sha_hex(PR_SHA256, TARBALL, strlen(TARBALL));
    snprintf(SHA256, sizeof SHA256, "%s", h); lower(SHA256); free(h);
    h = pr_sha_hex(PR_SHA512, TARBALL, strlen(TARBALL));
    snprintf(SHA512, sizeof SHA512, "%s", h); lower(SHA512); free(h);

    test_sums_lookup();
    test_registry_parsers();
    test_clearsigned();
    test_url_host();
    test_ladder();
    test_record_json();
    test_gpgv();

    char rm[256];
    snprintf(rm, sizeof rm, "rm -rf '%s'", g_dir);
    if (system(rm) != 0) { /* best effort */ }

    if (failures == 0) {
        fprintf(stderr, "test_provenance: ALL PASSED\n");
        return 0;
    }
    fprintf(stderr, "test_provenance: %d failure(s)\n", failures);
    return 1;
}
