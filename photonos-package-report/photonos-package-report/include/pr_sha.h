/* pr_sha.h — SHA1/256/512 digest helpers backed by libcrypto.
 *
 * Mirrors Get-FileHash + Get-FileHashWithRetry at
 * photonos-package-report.ps1 L 1952-2000.
 *
 * The PS author retries on Win32 "file in use" errors (HResult
 * 0x80070020). On Linux that lock class doesn't exist, so the C port
 * simply uses libcrypto's streaming EVP API directly with no retry.
 *
 * Algorithms supported (subset of PS Get-FileHash):
 *   PR_SHA1   — 40-char hex digest
 *   PR_SHA256 — 64-char hex digest
 *   PR_SHA512 — 128-char hex digest
 *
 * All returned strings are uppercase hex (matching PS Get-FileHash).
 */
#ifndef PR_SHA_H
#define PR_SHA_H

#include <stddef.h>

typedef enum {
    PR_SHA1 = 0,
    PR_SHA256,
    PR_SHA512,
} pr_sha_alg_t;

/* Hash a buffer in memory. Returns malloc'd uppercase-hex digest or
 * NULL on failure. */
char *pr_sha_hex(pr_sha_alg_t alg, const void *data, size_t len);

/* Hash a local file. Returns malloc'd uppercase-hex digest or NULL. */
char *pr_sha_file(pr_sha_alg_t alg, const char *path);

/* Download `url` via libcurl into a temp file, then hash it.
 * Returns malloc'd uppercase-hex digest or NULL on transport / I/O /
 * hash failure. */
char *pr_sha_of_url(pr_sha_alg_t alg, const char *url);

/* ADR-0014 (Option B): single libcurl GET, fan bytes into multiple
 * EVP_MD_CTX hashers. On success fills *sha256_hex and *sha512_hex
 * with malloc'd uppercase-hex digests and returns 0. On any
 * transport/I-O/hash error returns -1 and both outputs are NULL.
 *
 * Either output pointer may be NULL to skip that algorithm. */
int pr_sha_of_url_multi(const char *url,
                        char **sha256_hex,
                        char **sha512_hex);

/* Tarball-cache variants (ADR-0009 amendment, 2026-05-21). When
 * `cache_file` is non-NULL, the tarball is read from / written to that
 * persistent path (the shared SOURCES_NEW the PS run also uses) so PS
 * and C hash byte-identical bytes: if the file already exists it is
 * hashed in place; otherwise `url` is downloaded INTO it (creating
 * parent dirs) and then hashed. When `cache_file` is NULL these behave
 * exactly like their non-cached counterparts. */
char *pr_sha_of_url_cached(pr_sha_alg_t alg, const char *url,
                           const char *cache_file);
int   pr_sha_of_url_multi_cached(const char *url,
                                 char **sha256_hex,
                                 char **sha512_hex,
                                 const char *cache_file);

#endif /* PR_SHA_H */
