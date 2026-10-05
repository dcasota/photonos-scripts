# ADR-0017 — Opt-in provenance sidecar for downloaded tarballs

**Status**: Proposed

**Date**: 2026-10-05

**Deciders**: dcasota

## Context

With `PR_SHA_CACHE=1` the url-health pass downloads each newer vendor
tarball into `SOURCES_NEW/<file>` and hashes it (col 9, cols 13/14). The
hash only says which bytes arrived. Nothing checks whether the vendor
vouches for them: no detached signature, no published checksum file, no
package-index digest. A consumer that turns the row into a version bump
(SpagatLibrarian-Appliance ADR-0081, `SPECS_NEW_C`) therefore trusts
whatever the vendor host served on first use. #324 made the download itself
stricter (`PR_DOWNLOAD_HTTPS_ONLY`, `PR_MAX_DOWNLOAD_BYTES`); it does not
address provenance.

## Decision

A new module `src/provenance.c`, switched on by
**`PR_VERIFY_PROVENANCE=1`** (default off). When it is on, every
`SOURCES_NEW` tarball that a url-health download path produced gets a
sidecar **`SOURCES_NEW/<file>.provenance.json`**
(`photonos-package-report.provenance.v1`). The hook is called right after
each of the five `pr_sha_of_url*_cached` sites in `check_urlhealth.c`. The
rungs, strongest first:

| rung | evidence fetched | proves |
|---|---|---|
| `signature` | `<url>.sig` / `<url>.asc` over the tarball; or a clearsigned `sha256sums.asc`; or `SHA256SUMS` + `SHA256SUMS.asc/.sig`; verified by `gpgv --keyring $PR_PROVENANCE_KEYRING` | a key in that keyring signed the bytes (the record names the fingerprint; the binding of a key to a package is the consumer's policy) |
| `vendor_checksum` | `<url>.sha256[sum]`, `<url>.sha512[sum]`, GNOME `<stem>.sha256sum`, `SHA256SUMS`, `SHA512SUMS`, `sha256sums.txt`, `checksums.txt` | integrity against the vendor's own listing; from the same host this is **not** authenticity |
| `registry_digest` | PyPI PEP 691 JSON (`sha256`), rubygems `/api/v2/.../versions/<v>.json` (`sha`), GitHub release asset `digest` | the bytes the index recorded at upload |
| `corroborated` | Fedora `src.fedoraproject.org/rpms/<Name>/raw/rawhide/f/sources` (`SHA512 (file) = …`) | a second party fetched the same bytes |
| `tofu` | none of the above | only self-measured |

- **Any contradiction wins.** A `mismatch` on any rung (a BAD signature, a
  checksum file or index digest for other bytes, Fedora recording another
  sha512 under the same name) makes `verdict = mismatch`, whatever else
  verified.
- **Never fatal.** Without a keyring, without gpgv or without a reachable
  index, a rung is `unverifiable`, and that is recorded.
- **Bounded fetches.** Every evidence fetch is https only (initial request
  and redirects), HTTP 200 only, and size-capped (64 KiB for a signature,
  1 MiB for a checksum file, 32 MiB for an index document).
- **An http tarball gets no vendor evidence.** For an `http://` tarball URL
  no vendor evidence is fetched: a checksum over plaintext vouches for
  nothing. Corroboration still runs.
- **Vendor file name.** Vendor evidence is matched on the URL's file name,
  which can differ from the `UpdateDownloadName` that `download_name_post`
  produced.
- **No credentials in the record.** The URL's query and fragment never
  reach the record. `GITHUB_TOKEN`, when set, is sent to `api.github.com`
  only.
- **gpgv.** It runs via `posix_spawnp` with a private, temporary
  `--homedir`. It never consults a trust database.

## Parity

No `.prn` byte changes, whether the switch is on or off: the sidecar is a
separate file, and the PS script has no counterpart. `Parity: n/a`.

## Consequences

- One extra file per downloaded tarball, and up to about 15 small HTTPS
  requests per update row when the switch is on.
- Requires `gpgv` (gnupg) at run time for the signature rung. Without it
  the rung is `unverifiable`.
- Tests: `tests/unit/test_provenance.c` (parsers, the rung ladder over a
  table-driven fake fetcher, the sidecar JSON, gpgv against a throwaway
  ed25519 key, skipped when gpg is absent).
