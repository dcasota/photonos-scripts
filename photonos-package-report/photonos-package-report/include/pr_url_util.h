/* pr_url_util.h — URL helpers shared across the C port.
 *
 * PS L 4716-4718:
 *
 *   if ($UpdateURL -match '/download$') {
 *       $segments = $UpdateURL -split '/'
 *       $UpdateDownloadName = $segments[-2]
 *   } else {
 *       $UpdateDownloadName = ($UpdateURL -split '/')[-1]
 *   }
 *
 * SourceForge mirror URLs end in `/download` as a redirect trigger;
 * the real filename is the penultimate path segment. For everything
 * else the basename is the last segment.
 */
#ifndef PR_URL_UTIL_H
#define PR_URL_UTIL_H

/* Returns a malloc'd basename string the caller frees.
 * Returns NULL on NULL/empty input. */
char *pr_basename_from_url(const char *url);

#endif /* PR_URL_UTIL_H */
