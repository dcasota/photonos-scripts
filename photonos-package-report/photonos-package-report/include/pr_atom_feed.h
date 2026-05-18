/* pr_atom_feed.h — Atom-feed tag-list scraper.
 *
 * FRD-019. PS dispatches many specs through
 *   https://gitlab.freedesktop.org/<group>/<proj>/-/tags?format=atom
 *   https://gitlab.com/<group>/<proj>/-/tags?format=atom
 * URLs that return atom XML. Each `<entry>` carries a `<title>` whose
 * content is the tag name (often `vX.Y.Z` or `X.Y.Z`).
 *
 * This module fetches the URL with libcurl and extracts the entry
 * titles via PCRE2, decoding the standard 5 XML entities
 * (`&amp; &lt; &gt; &quot; &apos;`). The feed-level title (the one
 * outside any `<entry>` element) is skipped.
 *
 * The result feeds into the same name-filter pipeline as
 * pr_scrape_listing (M22/M27/M28/M29/M21).
 */
#ifndef PR_ATOM_FEED_H
#define PR_ATOM_FEED_H

#include <stddef.h>

/* GET `url`, parse atom XML, populate *out_names with malloc'd entry
 * titles and *out_n with the count. Returns 0 on success, -1 on
 * any transport/parse failure. On failure *out_names is NULL and
 * *out_n is 0. */
int pr_scrape_atom_feed(const char *url,
                        char ***out_names,
                        size_t *out_n);

#endif /* PR_ATOM_FEED_H */
