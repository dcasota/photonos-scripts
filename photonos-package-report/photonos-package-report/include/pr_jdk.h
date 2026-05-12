/* pr_jdk.h — Get-HighestJdkVersion port.
 *
 * Mirrors photonos-package-report.ps1 L 1638-1735.
 *
 * Given a list of OpenJDK-style tag names ("jdk-11.0.28+6",
 * "jdk-11.0.28-ga", "jdk-11+0", ...), pick the highest. Sorting keys
 * (descending priority): Major, Minor, Patch, then GA-wins-over-Build
 * (GA acts as max int).
 *
 * Returns the winner's Original-stripped-of-"jdk-" prefix as a heap
 * string (caller frees), or NULL if no candidate matched the prefix.
 *
 * `major_release` is used as the default Major when the tag has no
 * version-number component (e.g. bare "jdk-11" → Major=11). `filter`
 * is the literal "jdk-NN" prefix to match against (PS uses
 * "jdk-11" / "jdk-17" / "jdk-21").
 */
#ifndef PR_JDK_H
#define PR_JDK_H

#include <stddef.h>

char *pr_get_highest_jdk_version(char **names, size_t n,
                                 int major_release,
                                 const char *filter);

#endif /* PR_JDK_H */
