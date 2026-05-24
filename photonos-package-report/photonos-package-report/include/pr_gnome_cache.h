/* pr_gnome_cache.h — gnome download-server version enumeration (cat-6 cluster B).
 *
 * See src/gnome_cache.c. Fetches https://download.gnome.org/sources/<module>/
 * cache.json and returns the flat version array gnome publishes for the module
 * (element [2] of the cache). The caller runs the result through the standard
 * version-name pipeline (pr_get_latest_name + compare), exactly like the HTTP
 * listing scraper.
 */
#ifndef PR_GNOME_CACHE_H
#define PR_GNOME_CACHE_H

#include <stddef.h>

/* GET the gnome cache.json for `module` and return its released versions in
 * *out_names / *out_n (heap-allocated, caller frees with pr_git_tags_free).
 * Returns 0 on success with at least one version, -1 otherwise. */
int pr_gnome_cache_versions(const char *module, char ***out_names, size_t *out_n);

#endif /* PR_GNOME_CACHE_H */
