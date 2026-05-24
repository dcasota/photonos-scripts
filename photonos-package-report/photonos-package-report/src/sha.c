/* sha.c — SHA1/256/512 helpers via libcrypto + URL download.
 * Mirrors Get-FileHash / Get-FileHashWithRetry semantics from PS L 1952-2000.
 */
#include "pr_sha.h"

#include <curl/curl.h>
#include <openssl/evp.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const EVP_MD *md_for(pr_sha_alg_t alg)
{
    switch (alg) {
    case PR_SHA1:   return EVP_sha1();
    case PR_SHA256: return EVP_sha256();
    case PR_SHA512: return EVP_sha512();
    }
    return NULL;
}

/* Lowercase byte → uppercase hex pair. */
static char *to_hex_upper(const unsigned char *bytes, size_t n)
{
    static const char HEX[] = "0123456789ABCDEF";
    char *out = (char *)malloc(n * 2 + 1);
    if (!out) return NULL;
    for (size_t i = 0; i < n; i++) {
        out[i * 2]     = HEX[(bytes[i] >> 4) & 0xF];
        out[i * 2 + 1] = HEX[ bytes[i]       & 0xF];
    }
    out[n * 2] = '\0';
    return out;
}

char *pr_sha_hex(pr_sha_alg_t alg, const void *data, size_t len)
{
    const EVP_MD *md = md_for(alg);
    if (!md) return NULL;
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    if (!ctx) return NULL;
    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int  digest_len = 0;
    char *hex = NULL;
    if (EVP_DigestInit_ex(ctx, md, NULL) == 1 &&
        EVP_DigestUpdate(ctx, data, len) == 1 &&
        EVP_DigestFinal_ex(ctx, digest, &digest_len) == 1) {
        hex = to_hex_upper(digest, digest_len);
    }
    EVP_MD_CTX_free(ctx);
    return hex;
}

char *pr_sha_file(pr_sha_alg_t alg, const char *path)
{
    if (path == NULL) return NULL;
    const EVP_MD *md = md_for(alg);
    if (!md) return NULL;

    FILE *f = fopen(path, "rb");
    if (!f) return NULL;

    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    if (!ctx) { fclose(f); return NULL; }

    char *hex = NULL;
    if (EVP_DigestInit_ex(ctx, md, NULL) != 1) goto cleanup;

    unsigned char buf[64 * 1024];
    size_t n;
    while ((n = fread(buf, 1, sizeof buf, f)) > 0) {
        if (EVP_DigestUpdate(ctx, buf, n) != 1) goto cleanup;
    }
    if (ferror(f)) goto cleanup;

    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int  digest_len = 0;
    if (EVP_DigestFinal_ex(ctx, digest, &digest_len) != 1) goto cleanup;
    hex = to_hex_upper(digest, digest_len);

cleanup:
    EVP_MD_CTX_free(ctx);
    fclose(f);
    return hex;
}

/* libcurl WRITEFUNCTION → fwrite into the temp file. */
static size_t write_to_file(char *p, size_t s, size_t n, void *u)
{
    return fwrite(p, s, n, (FILE *)u);
}

/* mkdir -p the parent directory of `path` (best-effort). */
static void mkdir_parents(const char *path)
{
    char *dup = strdup(path);
    if (!dup) return;
    for (char *p = dup + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            mkdir(dup, 0775);
            *p = '/';
        }
    }
    free(dup);
}

/* Download `url` into `dest` (persistent path). Creates parent dirs.
 * Returns 0 on a 2xx response with the file written, -1 otherwise
 * (and removes any partial file). */
static int download_url_to_file(const char *url, const char *dest)
{
    mkdir_parents(dest);
    FILE *f = fopen(dest, "w+b");
    if (!f) return -1;
    CURL *c = curl_easy_init();
    if (!c) { fclose(f); unlink(dest); return -1; }
    curl_easy_setopt(c, CURLOPT_URL,            url);
    curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(c, CURLOPT_TIMEOUT_MS,     120000);
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION,  write_to_file);
    curl_easy_setopt(c, CURLOPT_WRITEDATA,      f);
    curl_easy_setopt(c, CURLOPT_USERAGENT,      "photonos-package-report/C");
    CURLcode rc = curl_easy_perform(c);
    long status = 0;
    curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &status);
    curl_easy_cleanup(c);
    fflush(f);
    fclose(f);
    if (rc != CURLE_OK || status < 200 || status >= 300) {
        unlink(dest);
        return -1;
    }
    return 0;
}

char *pr_sha_of_url_cached(pr_sha_alg_t alg, const char *url,
                           const char *cache_file)
{
    if (cache_file == NULL || cache_file[0] == '\0')
        return pr_sha_of_url(alg, url);
    /* Already present (e.g. fetched by the PS run): hash in place so PS
     * and C produce byte-identical col9. */
    if (access(cache_file, R_OK) == 0)
        return pr_sha_file(alg, cache_file);
    /* M64: in SHARED-cache mode (PR_SHA_CACHE_BASE set, reading the PS run's
     * SOURCES_NEW), a miss means PS did NOT preserve this tarball — i.e. PS
     * itself produced an empty col9. Mirror that (return NULL → empty) instead
     * of downloading C's own bytes, which would create a spurious col9 diff
     * (C-has-SHA vs PS-empty, or auto-archive byte drift). */
    if (getenv("PR_SHA_CACHE_BASE") != NULL)
        return NULL;
    /* Legacy (C-local cache): download into the cache path, persist, hash. */
    if (download_url_to_file(url, cache_file) != 0)
        return NULL;
    return pr_sha_file(alg, cache_file);
}

int pr_sha_of_url_multi_cached(const char *url,
                               char **sha256_hex,
                               char **sha512_hex,
                               const char *cache_file)
{
    if (cache_file == NULL || cache_file[0] == '\0')
        return pr_sha_of_url_multi(url, sha256_hex, sha512_hex);
    if (sha256_hex) *sha256_hex = NULL;
    if (sha512_hex) *sha512_hex = NULL;
    if (access(cache_file, R_OK) != 0) {
        /* M64 shared-cache mode: miss → mirror PS's empty col9, don't fetch. */
        if (getenv("PR_SHA_CACHE_BASE") != NULL) return -1;
        if (download_url_to_file(url, cache_file) != 0) return -1;
    }
    if (sha256_hex) {
        *sha256_hex = pr_sha_file(PR_SHA256, cache_file);
        if (!*sha256_hex) goto fail;
    }
    if (sha512_hex) {
        *sha512_hex = pr_sha_file(PR_SHA512, cache_file);
        if (!*sha512_hex) goto fail;
    }
    return 0;
fail:
    if (sha256_hex && *sha256_hex) { free(*sha256_hex); *sha256_hex = NULL; }
    if (sha512_hex && *sha512_hex) { free(*sha512_hex); *sha512_hex = NULL; }
    return -1;
}

char *pr_sha_of_url(pr_sha_alg_t alg, const char *url)
{
    if (url == NULL || url[0] == '\0') return NULL;

    /* Download to a /tmp file, then hash it. The PS Get-FileHash
     * accepts a path, so this matches the PS flow. */
    char tmpl[] = "/tmp/pr_sha_XXXXXX";
    int fd = mkstemp(tmpl);
    if (fd < 0) return NULL;
    FILE *f = fdopen(fd, "w+b");
    if (!f) { close(fd); unlink(tmpl); return NULL; }

    CURL *c = curl_easy_init();
    if (!c) { fclose(f); unlink(tmpl); return NULL; }
    curl_easy_setopt(c, CURLOPT_URL,            url);
    curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(c, CURLOPT_TIMEOUT_MS,     120000);
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION,  write_to_file);
    curl_easy_setopt(c, CURLOPT_WRITEDATA,      f);
    curl_easy_setopt(c, CURLOPT_USERAGENT,      "photonos-package-report/C");
    CURLcode rc = curl_easy_perform(c);
    long status = 0;
    curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &status);
    curl_easy_cleanup(c);
    fflush(f);
    fclose(f);

    char *hex = NULL;
    if (rc == CURLE_OK && status >= 200 && status < 300) {
        hex = pr_sha_file(alg, tmpl);
    }
    unlink(tmpl);
    return hex;
}

/* ADR-0014 multi-hash: one libcurl GET, two EVP_MD_CTX. */
struct multi_ctx {
    EVP_MD_CTX *c256;
    EVP_MD_CTX *c512;
    int        err;
};

static size_t write_to_multi(char *p, size_t s, size_t n, void *u)
{
    struct multi_ctx *m = (struct multi_ctx *)u;
    size_t bytes = s * n;
    if (m->err) return bytes;
    if (m->c256 && EVP_DigestUpdate(m->c256, p, bytes) != 1) { m->err = 1; }
    if (m->c512 && EVP_DigestUpdate(m->c512, p, bytes) != 1) { m->err = 1; }
    return bytes;
}

int pr_sha_of_url_multi(const char *url,
                        char **sha256_hex,
                        char **sha512_hex)
{
    if (sha256_hex) *sha256_hex = NULL;
    if (sha512_hex) *sha512_hex = NULL;
    if (url == NULL || url[0] == '\0') return -1;
    if (sha256_hex == NULL && sha512_hex == NULL) return -1;

    struct multi_ctx m = { NULL, NULL, 0 };
    if (sha256_hex) {
        m.c256 = EVP_MD_CTX_new();
        if (!m.c256) goto err;
        if (EVP_DigestInit_ex(m.c256, EVP_sha256(), NULL) != 1) goto err;
    }
    if (sha512_hex) {
        m.c512 = EVP_MD_CTX_new();
        if (!m.c512) goto err;
        if (EVP_DigestInit_ex(m.c512, EVP_sha512(), NULL) != 1) goto err;
    }

    CURL *c = curl_easy_init();
    if (!c) goto err;
    curl_easy_setopt(c, CURLOPT_URL,            url);
    curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(c, CURLOPT_TIMEOUT_MS,     120000);
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION,  write_to_multi);
    curl_easy_setopt(c, CURLOPT_WRITEDATA,      &m);
    curl_easy_setopt(c, CURLOPT_USERAGENT,      "photonos-package-report/C");
    CURLcode rc = curl_easy_perform(c);
    long status = 0;
    curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &status);
    curl_easy_cleanup(c);

    if (rc != CURLE_OK || status < 200 || status >= 300 || m.err) goto err;

    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int  digest_len = 0;
    if (m.c256) {
        if (EVP_DigestFinal_ex(m.c256, digest, &digest_len) != 1) goto err;
        *sha256_hex = to_hex_upper(digest, digest_len);
        EVP_MD_CTX_free(m.c256); m.c256 = NULL;
        if (!*sha256_hex) goto err;
    }
    if (m.c512) {
        if (EVP_DigestFinal_ex(m.c512, digest, &digest_len) != 1) goto err;
        *sha512_hex = to_hex_upper(digest, digest_len);
        EVP_MD_CTX_free(m.c512); m.c512 = NULL;
        if (!*sha512_hex) goto err;
    }

    return 0;

err:
    if (m.c256) EVP_MD_CTX_free(m.c256);
    if (m.c512) EVP_MD_CTX_free(m.c512);
    if (sha256_hex && *sha256_hex) { free(*sha256_hex); *sha256_hex = NULL; }
    if (sha512_hex && *sha512_hex) { free(*sha512_hex); *sha512_hex = NULL; }
    return -1;
}
