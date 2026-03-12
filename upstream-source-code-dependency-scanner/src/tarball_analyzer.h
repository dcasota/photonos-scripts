#ifndef DEPGRAPH_DEEP_TARBALL_ANALYZER_H
#define DEPGRAPH_DEEP_TARBALL_ANALYZER_H

#include "graph.h"
#include "gomod_to_package_map.h"

/* Extract a single file from a .tar.gz tarball to a temp file.
   pszTarball: path to the .tar.gz archive.
   pszInnerGlob: glob pattern for the file inside (e.g. go.mod wildcard).
   pszOutPath: buffer to receive the temp file path (must be MAX_PATH_LEN).
   Returns 0 on success, -1 on failure. Caller must unlink pszOutPath. */
int tarball_extract_file(const char *pszTarball, const char *pszInnerGlob,
                         char *pszOutPath, size_t nOutLen);

/* Find and analyze go.mod inside a tarball for a given package.
   Looks for go.mod at the first directory level inside the archive.
   Returns 0 on success, -1 if no go.mod found or on error. */
int tarball_analyze_gomod(DepGraph *pGraph, const char *pszTarball,
                          const char *pszPackageName,
                          const GomodPackageMap *pMap);

/* Find a tarball in a flat sources directory matching {name}-{version}.tar.gz.
   Tries common extensions: .tar.gz, .tar.bz2, .tar.xz, .tgz, .zip.
   Returns 0 and fills pszOutPath on success, -1 if not found. */
int tarball_find_source(const char *pszSourcesDir,
                        const char *pszName, const char *pszVersion,
                        char *pszOutPath, size_t nOutLen);

#endif /* DEPGRAPH_DEEP_TARBALL_ANALYZER_H */
