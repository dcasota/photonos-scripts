/* pr_urlhealth.h — urlhealth() port.
 *
 * Mirrors photonos-package-report.ps1 L 1458-1518.
 *
 * The PS function probes a URL with a HEAD request, returns the HTTP
 * status code, and falls back to a full browser-mimic GET for known-
 * stubborn hosts (netfilter.org/ftp URLs that 403 on plain HEAD).
 *
 * Return values:
 *   200..599  : HTTP status (success or HTTP-level failure both surface)
 *   0         : libcurl/transport-level error (timeout, DNS, TLS, ...)
 *
 * Timeout: 120 seconds, matching PS L 1469 ($request.Timeout = 120000).
 */
#ifndef PR_URLHEALTH_H
#define PR_URLHEALTH_H

int urlhealth(const char *checkurl);

#endif /* PR_URLHEALTH_H */
