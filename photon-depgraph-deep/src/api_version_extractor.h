#ifndef DEPGRAPH_DEEP_API_VERSION_EXTRACTOR_H
#define DEPGRAPH_DEEP_API_VERSION_EXTRACTOR_H

#include "graph.h"

#define MAX_PATTERN_ENTRIES 128

typedef struct {
    char szPackage[256];
    char szFilePath[MAX_PATH_LEN];
    char szPattern[512];
    char szProvideType[64]; /* "provides" or "requires" */
    char szVirtualName[256]; /* e.g. "docker-api" */
} ApiVersionPattern;

typedef struct {
    ApiVersionPattern entries[MAX_PATTERN_ENTRIES];
    uint32_t          dwCount;
} ApiVersionPatterns;

/* Load api-version-patterns.csv. Returns 0 on success. */
int api_patterns_load(ApiVersionPatterns *pPatterns, const char *pszCsvPath);

/* Extract API version constants from clones using loaded patterns.
   Adds virtual provides/requires to the graph. */
int api_version_extract(DepGraph *pGraph, const char *pszClonesDir,
                        const ApiVersionPatterns *pPatterns);

#endif /* DEPGRAPH_DEEP_API_VERSION_EXTRACTOR_H */
