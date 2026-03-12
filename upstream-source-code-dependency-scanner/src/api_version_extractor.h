#ifndef DEPGRAPH_DEEP_API_VERSION_EXTRACTOR_H
#define DEPGRAPH_DEEP_API_VERSION_EXTRACTOR_H

#include "graph.h"
#include "prn_parser.h"

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
   Adds virtual provides/requires to the graph.
   pPrnMap: optional PRN-derived package-to-clone mapping (may be NULL). */
int api_version_extract(DepGraph *pGraph, const char *pszClonesDir,
                        const ApiVersionPatterns *pPatterns,
                        const PrnMap *pPrnMap);

/* Docker SDK-to-API version mapping */
#define MAX_SDK_MAP_ENTRIES 64

typedef struct {
    double fSdkMin;
    double fSdkMax;
    char   szApiVersion[32];
} DockerSdkMapEntry;

typedef struct {
    DockerSdkMapEntry entries[MAX_SDK_MAP_ENTRIES];
    uint32_t          dwCount;
} DockerSdkApiMap;

/* Load docker-api-version-map.csv. Returns 0 on success. */
int docker_sdk_map_load(DockerSdkApiMap *pMap, const char *pszCsvPath);

/* Map a Docker SDK version (e.g. "28.5.1") to REST API version (e.g. "1.51").
   Returns pointer to static string, or NULL if not found. */
const char *docker_sdk_to_api_version(const DockerSdkApiMap *pMap,
                                      const char *pszSdkVersion);

/* Reverse: find the minimum Docker Engine version that supports a given API version.
   E.g. api "1.44" -> "25.0". Returns NULL if not found. */
const char *docker_api_to_min_engine(const DockerSdkApiMap *pMap,
                                     const char *pszApiVersion);

#endif /* DEPGRAPH_DEEP_API_VERSION_EXTRACTOR_H */
