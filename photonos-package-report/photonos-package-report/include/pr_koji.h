/* pr_koji.h — KojiFedoraProjectLookUp port.
 *
 * Mirrors photonos-package-report.ps1 L 1520-1572.
 *
 * Given a package name (e.g. "libaio") the function walks:
 *   1. https://src.fedoraproject.org/rpms/<name>/blob/main/f/sources
 *      → extract upstream tarball name from the embedded `<code>...(...)</code>`
 *   2. The tarball name → upstream version (strip leading "<name>-" / "v" / ".tar.gz")
 *      Special cases: "connect-proxy" strips "ssh-connect-"; "python-pbr" strips "pbr-".
 *   3. https://kojipkgs.fedoraproject.org/packages/<name>/<version>
 *      → list build-release subdirs; pick the highest numeric prefix.
 *   4. https://kojipkgs.fedoraproject.org/packages/<name>/<version>/<release>/src/
 *      → list .src.rpm files; pick the highest numeric prefix.
 *   5. Return the final .src.rpm URL.
 *
 * Returns 0 on success (writes a malloc'd URL into *out_url; caller frees).
 * Returns 0 with *out_url = strdup("") if any step missed (mirrors PS
 * silent-catch at L 1571).
 * Returns -1 on memory failure.
 */
#ifndef PR_KOJI_H
#define PR_KOJI_H

int koji_fedora_lookup(const char *artefact_name, char **out_url);

/* --- Parsing helpers exposed for unit tests ----------------------- */

/* Step 1 parser: extract the tarball filename inside the FIRST
 *   <code class...>...</code>(...)
 * pair on the page. Returns malloc'd string or NULL on miss. */
char *pr_koji_parse_artefact_download_name(const char *html);

/* Step 2 helper: given (artefact_name, download_name) return the
 * upstream version with PS L 1545-1547 strippings applied. malloc'd. */
char *pr_koji_derive_version(const char *artefact_name, const char *download_name);

/* Step 3 parser: from the directory listing HTML, return the highest-
 * numbered release name. Returns malloc'd string or NULL. */
char *pr_koji_pick_latest_release(const char *html);

/* Step 4 parser: from the src/ listing HTML, return the highest-
 * numbered .src.rpm filename. Returns malloc'd string or NULL. */
char *pr_koji_pick_latest_srpm(const char *html);

#endif /* PR_KOJI_H */
