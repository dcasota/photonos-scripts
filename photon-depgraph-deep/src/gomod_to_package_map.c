#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "gomod_to_package_map.h"

int
gomod_map_load(GomodPackageMap *pMap, const char *pszCsvPath)
{
    FILE *fp = NULL;
    char szLine[MAX_MODULE_PATH_LEN + 256 + 4];
    char *pszComma = NULL;

    if (!pMap || !pszCsvPath)
    {
        return -1;
    }

    memset(pMap, 0, sizeof(*pMap));

    fp = fopen(pszCsvPath, "r");
    if (!fp)
    {
        fprintf(stderr, "gomod_map_load: cannot open %s\n", pszCsvPath);
        return -1;
    }

    while (fgets(szLine, sizeof(szLine), fp))
    {
        /* Strip trailing newline */
        szLine[strcspn(szLine, "\r\n")] = '\0';

        /* Skip empty lines and comments */
        if (szLine[0] == '\0' || szLine[0] == '#')
        {
            continue;
        }

        pszComma = strchr(szLine, ',');
        if (!pszComma)
        {
            continue;
        }

        if (pMap->dwCount >= MAX_MAP_ENTRIES)
        {
            fprintf(stderr, "gomod_map_load: exceeded %d entries\n",
                    MAX_MAP_ENTRIES);
            break;
        }

        *pszComma = '\0';
        snprintf(pMap->entries[pMap->dwCount].szModulePath,
                 MAX_MODULE_PATH_LEN, "%s", szLine);
        snprintf(pMap->entries[pMap->dwCount].szPhotonPackage,
                 sizeof(pMap->entries[0].szPhotonPackage), "%s", pszComma + 1);

        pMap->dwCount++;
    }

    fclose(fp);
    return 0;
}

const char *
gomod_map_lookup(const GomodPackageMap *pMap, const char *pszModulePath)
{
    uint32_t i = 0;
    size_t nBestLen = 0;
    const char *pszBest = NULL;

    if (!pMap || !pszModulePath)
    {
        return NULL;
    }

    for (i = 0; i < pMap->dwCount; i++)
    {
        const char *pszEntry = pMap->entries[i].szModulePath;
        size_t nEntryLen = strlen(pszEntry);

        /* Prefix match: the module path must start with the map entry */
        if (strstr(pszModulePath, pszEntry) == pszModulePath)
        {
            /* Exact match or the next char is '/' (subpath) */
            if (pszModulePath[nEntryLen] == '\0' ||
                pszModulePath[nEntryLen] == '/')
            {
                if (nEntryLen > nBestLen)
                {
                    nBestLen = nEntryLen;
                    pszBest = pMap->entries[i].szPhotonPackage;
                }
            }
        }
    }

    return pszBest;
}
