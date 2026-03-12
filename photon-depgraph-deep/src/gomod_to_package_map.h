#ifndef DEPGRAPH_DEEP_GOMOD_TO_PACKAGE_MAP_H
#define DEPGRAPH_DEEP_GOMOD_TO_PACKAGE_MAP_H

#include <stdint.h>

#define MAX_MODULE_PATH_LEN 512
#define MAX_MAP_ENTRIES     1024

typedef struct {
    char szModulePath[MAX_MODULE_PATH_LEN];
    char szPhotonPackage[256];
} GomodMapEntry;

typedef struct {
    GomodMapEntry entries[MAX_MAP_ENTRIES];
    uint32_t      dwCount;
} GomodPackageMap;

/* Load the gomod-package-map.csv file. Returns 0 on success. */
int gomod_map_load(GomodPackageMap *pMap, const char *pszCsvPath);

/* Look up a Go module path -> Photon package name. Returns NULL if not found. */
const char *gomod_map_lookup(const GomodPackageMap *pMap, const char *pszModulePath);

#endif /* DEPGRAPH_DEEP_GOMOD_TO_PACKAGE_MAP_H */
