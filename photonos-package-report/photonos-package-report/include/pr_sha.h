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

#endif /* PR_SHA_H */
