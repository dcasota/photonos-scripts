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

/* Download policy for the tarball fetches above (pr_sha_of_url,
 * pr_sha_of_url_multi and the *_cached download-into-cache path).
 *
 * Opt-in hardening, read from the environment on every download, so a
 * default run (and the PS parity journal) is byte-identical to before:
 *
 *   PR_DOWNLOAD_HTTPS_ONLY=1   the initial request AND every redirect
 *                              may use https only (CURLOPT_PROTOCOLS /
 *                              CURLOPT_REDIR_PROTOCOLS), and only an
 *                              HTTP 200 is accepted (default: any 2xx).
 *   PR_MAX_DOWNLOAD_BYTES=<n>  a decimal byte ceiling: a body that is
 *                              announced or turns out larger aborts the
 *                              transfer and the partial file is removed.
 *                              0 or unset = no ceiling.
 *
 * Empty values count as unset (POSIX convention, see M145). A
 * PR_MAX_DOWNLOAD_BYTES that is not a plain decimal number fails CLOSED:
 * every download is refused rather than run without the ceiling the
 * caller asked for. */
typedef struct {
    int                https_only;   /* 1 = https only, redirects too, 200 only */
    unsigned long long max_bytes;    /* 0 = no ceiling */
} pr_download_policy_t;

/* Read the policy from the environment. Returns 0 on success and -1 when
 * PR_MAX_DOWNLOAD_BYTES is malformed; the download helpers refuse every
 * download in that case. */
int pr_download_policy_from_env(pr_download_policy_t *out);

/* Is `status` an acceptable final HTTP status under `p`? */
int pr_download_status_ok(const pr_download_policy_t *p, long status);

#endif /* PR_SHA_H */
