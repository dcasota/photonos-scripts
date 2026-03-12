#ifndef DEPGRAPH_DEEP_PRN_PARSER_H
#define DEPGRAPH_DEEP_PRN_PARSER_H

#include <stdint.h>

#define PRN_MAX_ENTRIES 2048
#define PRN_MAX_NAME    256

typedef struct _PrnEntry
{
    char szSpec[PRN_MAX_NAME];       /* spec filename without .spec */
    char szRepoOwner[PRN_MAX_NAME];  /* github owner (e.g. "moby") */
    char szRepoName[PRN_MAX_NAME];   /* github repo  (e.g. "moby") */
    char szCloneName[PRN_MAX_NAME];  /* clone dir = szRepoName */
} PrnEntry;

typedef struct _PrnMap
{
    PrnEntry entries[PRN_MAX_ENTRIES];
    uint32_t dwCount;
} PrnMap;

/* Load a PRN file and extract spec -> github repo mappings.
   Returns 0 on success. */
int prn_map_load(PrnMap *pMap, const char *pszPath);

/* Look up clone directory name for a Photon package name.
   Returns the clone name string, or NULL if not found. */
const char *prn_map_find_clone(const PrnMap *pMap, const char *pszPackage);

/* Reverse lookup: given a clone directory name, find the Photon package name.
   Returns the spec/package name string, or NULL if not found. */
const char *prn_map_find_package(const PrnMap *pMap, const char *pszCloneName);

#endif /* DEPGRAPH_DEEP_PRN_PARSER_H */
