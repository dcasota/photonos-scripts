/* pr_netcat.h — netcat.spec bespoke version detection.
 *
 * Phase M task M62. Mirrors photonos-package-report.ps1 L 2540-2556.
 *
 * netcat is a self-built tarball (vendored on packages.broadcom.com with a
 * pinned commit_id), so there is no upstream release listing. PS derives:
 *   - the version  from the CVS revision in the netcat.c header
 *     (`$OpenBSD: netcat.c,v <maj>.<min>`), via the raw GitHub file, and
 *   - the commit_id from the GitHub Commits API (first 7 of the latest
 *     commit sha touching usr.bin/nc), used for the download name.
 */
#ifndef PR_NETCAT_H
#define PR_NETCAT_H

/* On return:
 *   *out_version    — malloc'd "maj.min" (e.g. "1.238"), or NULL if the
 *                     raw file / regex failed.
 *   *out_commit_id  — malloc'd 7-char short sha (e.g. "c2d3847"), or NULL
 *                     if the Commits API failed.
 * Caller frees both. `github_token` may be NULL/empty (the Commits API
 * then runs unauthenticated, subject to the 60/h rate limit).
 * Returns 0 if the version was extracted, -1 otherwise. */
int pr_netcat_detect(const char *github_token,
                     char **out_version, char **out_commit_id);

#endif /* PR_NETCAT_H */
