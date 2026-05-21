/* pr_sourceforge.h — sourceforge.net release detection (M35).
 *
 * Mirrors photonos-package-report.ps1 L 3459-3585: when a spec's
 * Source0 points at sourceforge.net, PS derives a project "files"
 * landing URL (the SourceTagURL), GETs it, and extracts the version
 * directory names from the embedded `net.sf.files = {...}};` JSON
 * blob (SourceForge renders the file listing as a JS object). The
 * version names then flow through the same replace/Clean-VersionNames/
 * post-filter pipeline as every other detection path.
 *
 * The two entry points split that work so check_urlhealth.c can reuse
 * its existing name-filter pipeline:
 *   - pr_sourceforge_tag_url   : Source0 -> SourceTagURL (+ per-spec
 *                                overrides, PS L 3476-3495).
 *   - pr_sourceforge_fetch_names: GET + net.sf.files name extraction
 *                                 (+ archive-extension strip, PS
 *                                 L 3532-3535).
 *
 * The libusb two-stage fetch (PS L 3503-3522) is intentionally NOT
 * handled here; callers must skip libusb so it falls through rather
 * than emit a wrong single-stage result.
 */
#ifndef PR_SOURCEFORGE_H
#define PR_SOURCEFORGE_H

#include <stddef.h>

/* Derive the SourceForge project "files" URL from `source0`, honouring
 * the per-spec overrides in PS L 3476-3495. Returns a malloc'd string
 * (caller frees) or NULL when `source0` is empty. */
char *pr_sourceforge_tag_url(const char *spec, const char *source0);

/* GET `url` and extract the version directory names from the embedded
 * `net.sf.files = {...}};` blob, stripping archive extensions. On
 * success returns 0 and sets *names_out (malloc'd array of malloc'd
 * strings) + *n_out. Returns non-zero on transport/parse failure. */
int pr_sourceforge_fetch_names(const char *url, char ***names_out, size_t *n_out);

#endif /* PR_SOURCEFORGE_H */
