/* pr_scraper.h — HTTP directory-listing scraper.
 *
 * Phase M task M20, FRD-018.
 *
 * Mirrors PS L 4258-4283: GET the directory-listing URL, extract
 * every `<a href="...">` value from the response body. Used by
 * CheckURLHealth as the non-git update-detection path, alongside
 * the existing git-tag detection.
 */
#ifndef PR_SCRAPER_H
#define PR_SCRAPER_H

#include <stddef.h>

/* Fetch <url> via HTTP GET (libcurl), parse the response body as
 * HTML, return every <a href="..."> value.
 *
 *   url        — listing URL (e.g. http://ftp.gnome.org/pub/gnome/sources/GConf/3.2/)
 *   out_names  — set to a malloc'd array of malloc'd strings on success
 *   out_n      — count of names
 *
 * Caller frees via pr_git_tags_free (the same free convention the
 * tag-list API uses; in fact pr_clone_list_tags's caller pattern is
 * the model we mirror here).
 *
 * Returns:
 *    0  — success (may be 0 names if body had no <a href>)
 *   -1  — HTTP error, body too large (>1 MiB), or allocation failure
 *
 * The 1 MiB body cap protects against accidentally GET-ing a huge
 * page (e.g. when a listing URL accidentally points at a binary
 * resource). PS doesn't cap; we add it as a defensive measure.
 */
int pr_scrape_listing(const char *url, char ***out_names, size_t *out_n);

/* M44: extract <Key>...</Key> values from an S3-bucket XML listing
 * (e.g. json-c on s3.amazonaws.com). On success returns 0 and sets
 * *out_names / *out_n (caller frees); -1 on transport/alloc failure. */
int pr_scrape_keys(const char *url, char ***out_names, size_t *out_n);

#endif /* PR_SCRAPER_H */
