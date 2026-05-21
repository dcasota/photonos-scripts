/* pr_github_tags.h — github.com tags-page release detection (M38).
 *
 * Ports the HTML "special-case" half of PS's github branch
 * (photonos-package-report.ps1 L 2766-2872). For a fixed list of specs
 * whose Source0 points at github.com but which have NO gitSource row,
 * PS scrapes the HTML tags page
 *   https://github.com/<owner>/<repo>/tags
 * and harvests the tag names from the embedded
 *   /archive/refs/tags/<tag>.tar.gz
 * download links (PS L 2869-2871). The names then run through
 * check_urlhealth.c's existing version pipeline.
 *
 * The api.github.com path (PS L 2784-2788, used for non-special-case
 * github specs) is NOT ported here — it needs an auth token and is out
 * of scope for the special-case list.
 */
#ifndef PR_GITHUB_TAGS_H
#define PR_GITHUB_TAGS_H

#include <stddef.h>

/* True when `spec` is in PS's github special-case list (L 2791-2816),
 * i.e. the specs that scrape the HTML tags page rather than the API. */
int pr_github_is_html_tags_spec(const char *spec);

/* Derive the HTML tags URL "https://github.com/<owner>/<repo>/tags"
 * from a github Source0 (PS L 2774-2784). Returns malloc'd string
 * (caller frees) or NULL when owner/repo can't be extracted. */
char *pr_github_tags_html_url(const char *source0);

/* GET `url` (the HTML tags page) and harvest tag names from the
 * /archive/refs/tags/<tag> download links, dropping .whl/.asc/.dmg/
 * .zip/.exe entries and stripping archive extensions (PS L 2878-2885).
 * On success returns 0 and sets *names_out / *n_out. */
int pr_github_scrape_tags_html(const char *url, char ***names_out, size_t *n_out);

#endif /* PR_GITHUB_TAGS_H */
