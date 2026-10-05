/* pr_provenance.h — opt-in provenance verification of a downloaded tarball.
 *
 * Not a PS port: there is no PowerShell counterpart, and the .prn is never
 * touched. With PR_VERIFY_PROVENANCE=1, every tarball the url-health pass
 * downloads into SOURCES_NEW/<file> gets a sidecar
 * SOURCES_NEW/<file>.provenance.json that says which provenance rung vouched
 * for those bytes, with the evidence URLs and the expected and actual
 * digests. Strongest rung first:
 *
 *   signature        a vendor detached signature (<url>.sig / .asc) or a
 *                    clearsigned checksum file (sha256sums.asc), verified by
 *                    gpgv against PR_PROVENANCE_KEYRING. The record names the
 *                    signing key's fingerprint; whether that key is the
 *                    right key FOR THIS PACKAGE is the consumer's policy.
 *   vendor_checksum  a checksum file published next to the tarball
 *                    (<url>.sha256, SHA256SUMS, GNOME .sha256sum, ...).
 *                    From the same origin it proves integrity, not
 *                    authenticity: whoever controls the host controls both.
 *   registry_digest  the package index's own digest (PyPI sha256, rubygems
 *                    sha, the GitHub release asset digest).
 *   corroborated     another distribution recorded the same file with the
 *                    same digest (Fedora lookaside `sources`, SHA512).
 *   tofu             none of the above: the bytes are only self-measured.
 *
 * A rung that contradicts the bytes is a `mismatch`, and a mismatch from any
 * rung makes the record's verdict `mismatch` whatever else verified.
 *
 * Every evidence fetch is https only, HTTP 200 only, size-capped. A missing
 * keyring, a missing gpgv or an unreachable index make a rung
 * `unverifiable` (recorded, never fatal).
 */
#ifndef PR_PROVENANCE_H
#define PR_PROVENANCE_H

#include <stddef.h>

#define PR_PROVENANCE_SCHEMA   "photonos-package-report.provenance.v1"
#define PR_PROVENANCE_SUFFIX   ".provenance.json"
#define PR_PROV_MAX_EVIDENCE   24

/* Fetch `url` (https only, 200 only, at most `max` bytes), sending
 * `accept` as the Accept header when not NULL. Returns the HTTP status (200
 * with *body malloc'd and NUL-terminated) or 0 on a transport error /
 * refused scheme / oversize body. */
typedef long (*pr_prov_fetch_fn)(void *ctx, const char *url, const char *accept,
                                 size_t max, char **body, size_t *len);

typedef struct {
    const char       *package;    /* task->Name                          */
    const char       *spec;       /* task->Spec                          */
    const char       *url;        /* the URL the bytes were fetched from */
    const char       *file_path;  /* SOURCES_NEW/<file>                  */
    const char       *keyring;    /* gpgv keyring, NULL = no rung 1      */
    const char       *gpgv;       /* gpgv binary, NULL = "gpgv" on PATH  */
    pr_prov_fetch_fn  fetch;      /* NULL = libcurl                      */
    void             *fetch_ctx;
} pr_prov_input_t;

typedef enum {
    PR_EV_VERIFIED     = 0,
    PR_EV_MISMATCH     = 1,
    PR_EV_UNVERIFIABLE = 2
} pr_prov_result_t;

typedef struct {
    const char      *rung;        /* static string */
    char            *url;
    pr_prov_result_t result;
    int              same_origin; /* evidence host == tarball host */
    char             algorithm[8];
    char             expected[129];
    char             actual[129];
    char             fingerprint[41];
    char            *detail;
} pr_prov_evidence_t;

typedef struct {
    char               *file;
    char               *url;
    char               *package;
    char               *spec;
    char                sha256[65];
    char                sha512[129];
    unsigned long long  size;
    const char         *rung;     /* strongest verified rung, or "tofu" */
    const char         *verdict;  /* "verified" | "mismatch" | "unverified" */
    pr_prov_evidence_t  ev[PR_PROV_MAX_EVIDENCE];
    size_t              n;
} pr_prov_record_t;

/* 1 when PR_VERIFY_PROVENANCE is set to anything but "" or "0". */
int  pr_provenance_enabled(void);

/* Run every rung for in->file_path. 0 on success (out filled, free with
 * pr_provenance_free), -1 when the file cannot be read. */
int  pr_provenance_verify(const pr_prov_input_t *in, pr_prov_record_t *out);

/* Write `r` as JSON to `path` atomically (tmp + rename). 0 / -1. */
int  pr_provenance_write(const pr_prov_record_t *r, const char *path);

/* Serialise to a malloc'd JSON string. */
char *pr_provenance_json(const pr_prov_record_t *r);

void pr_provenance_free(pr_prov_record_t *r);

/* The check_urlhealth hook: when enabled and `file_path` exists, verify it
 * and write <file_path>.provenance.json. Never fails the caller. */
void pr_provenance_after_download(const char *package, const char *spec,
                                  const char *url, const char *file_path);

/* ---- pure parsers (exported for tests) ---- */

/* Find `file`'s digest in a checksum file: GNU (`<hex>  [*]file`), BSD
 * (`SHA256 (file) = <hex>`), or — when allow_bare — a lone hex digest.
 * Only sha256 (64 hex) and sha512 (128 hex) count. Returns 1 and fills
 * alg ("sha256"/"sha512") and hex (lowercase), else 0. */
int pr_prov_sums_lookup(const char *body, size_t len, const char *file,
                        int allow_bare, char alg[8], char hex[129]);

/* PyPI simple JSON (PEP 691): the sha256 of `file`. 1 / 0. */
int pr_prov_pypi_sha256(const char *json, size_t len, const char *file,
                        char hex[65]);

/* rubygems /api/v2/rubygems/<gem>/versions/<ver>.json: `sha`. 1 / 0. */
int pr_prov_rubygems_sha256(const char *json, size_t len, char hex[65]);

/* GitHub release JSON: the `digest` (sha256:) of asset `name`. 1 / 0. */
int pr_prov_github_digest(const char *json, size_t len, const char *name,
                          char hex[65]);

/* Fedora lookaside `sources`: SHA512 of `file`. 1 / 0. */
int pr_prov_fedora_sha512(const char *body, size_t len, const char *file,
                          char hex[129]);

/* The signed text of a clearsigned message (dash-escaping undone).
 * 1 with *text malloc'd, 0 when `body` is not clearsigned. */
int pr_prov_clearsigned_text(const char *body, size_t len,
                             char **text, size_t *tlen);

/* gpgv --status-fd: 1 = VALIDSIG (fpr filled), 0 = BADSIG, -1 = no public
 * key (keyid filled when known) or other error, -2 = gpgv could not run.
 * data_path NULL verifies a clearsigned/inline signature in sig_path. */
int pr_prov_gpgv(const char *gpgv, const char *keyring, const char *sig_path,
                 const char *data_path, char fpr[41], char keyid[17]);

/* Host of an URL, lowercased, into out (cap bytes). 1 / 0. */
int pr_prov_url_host(const char *url, char *out, size_t cap);

#endif /* PR_PROVENANCE_H */
