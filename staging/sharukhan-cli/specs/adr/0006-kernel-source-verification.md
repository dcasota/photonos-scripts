# ADR-0006 — A tarball pin is established by verification, never copied

Status: accepted, implemented
Date: 2026-09-27
Feature: [FRD-001](../features/kernel-wrapper.md)

## Context

A wrapper pins the kernel tarball by sha512. The 7.3-rc4 digest was recorded by hand from a download.
kernel.org signs its cdn tarballs (`.tar.sign` over the uncompressed tar), but release candidates are
git.kernel.org snapshots with no signature at all (`releases.json` lists `pgp: null`).

## Decision

`sharukhan wrapper verify` establishes the pin; `profile-new` calls it; `verify --profile` re-proves
an existing profile.

- **Trust anchors:** `profiles/kernel/kernel-org-signers.json`, the four fingerprints published on
  kernel.org/signature.html (Torvalds, Kroah-Hartman, Levin, Hutchings), reviewed 2026-09-27. Keys
  are fetched from kernel.org's pgpkeys repository by long ID and imported into a keyring private to
  the run only if `--import-options show-only` shows exactly the reviewed primary fingerprint.
- **Signature judgement:** exactly one `GOODSIG` and one `VALIDSIG` whose primary fingerprint is a
  reviewed signer; any `BADSIG`, `ERRSIG`, `EXPSIG`, `EXPKEYSIG`, `REVKEYSIG`, `NO_PUBKEY` or
  `FAILURE` refuses.
- **cdn releases:** the decompressed stream is fed to `gpg --verify <sig> -` in one pass.
- **RC snapshots:** the tag `vX.Y-rcN` is fetched (depth 1) from torvalds/linux.git over https;
  the tag object must say `type commit` and `tag vX.Y-rcN`; `git verify-tag` must pass the judgement;
  the decompressed snapshot must be byte-identical to `git archive --prefix=linux-X.Y-rcN/` of the
  tagged commit, and its pax `comment` must be that commit. (Measured 2026-09-27: identical.)
- **Both:** every tar entry must lie under `linux-<release>/` with no `..` component, and the archive
  must end properly, so a validly signed tarball of another release cannot stand in.
- **Transport:** curl with `--proto =https --proto-redir =https --tlsv1.2`, only
  `https://{www,cdn,git}.kernel.org/<plain path>`; git with only the https protocol allowed.
- The profile records `method`, `signer`, `commit` (signed-tag only) and the date.

## Alternatives

- Pin from the branch manifest: copies a value instead of establishing it.
- Accept the snapshot's pax comment alone: a claim inside the file being verified.
- WKD key discovery: gpg's WKD lookup failed on this host ("Invalid URI"); fetching by long ID and
  checking the fingerprint is equally sound because trust rests on the reviewed fingerprint.

## Consequences

Verifying an RC costs a depth-1 fetch (~290 MB, cached under the kernel cache) and two full tar
streams; about 2.5 minutes on this host. A signed-tag release whose `git archive` output ever
differs from the snapshot (a git format change on either side) fails closed.
