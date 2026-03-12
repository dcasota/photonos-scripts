#include "prn_parser.h"

#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>

/* Extract github.com/{owner}/{repo} from a URL string.
   Returns 0 on success, fills pszOwner and pszRepo. */
static int
_extract_github_repo(const char *pszUrl, char *pszOwner, size_t nOwnerMax,
                     char *pszRepo, size_t nRepoMax)
{
    const char *p = strstr(pszUrl, "github.com/");
    if (!p)
        return -1;

    p += strlen("github.com/");

    /* owner */
    size_t i = 0;
    while (*p && *p != '/' && i < nOwnerMax - 1)
        pszOwner[i++] = *p++;
    pszOwner[i] = '\0';
    if (i == 0 || *p != '/')
        return -1;
    p++;

    /* repo - strip .git suffix and stop at / or end */
    i = 0;
    while (*p && *p != '/' && i < nRepoMax - 1)
        pszRepo[i++] = *p++;
    pszRepo[i] = '\0';

    /* Strip trailing .git */
    size_t len = strlen(pszRepo);
    if (len > 4 && strcmp(pszRepo + len - 4, ".git") == 0)
        pszRepo[len - 4] = '\0';

    return (pszRepo[0] != '\0') ? 0 : -1;
}

/* Simple CSV field extraction: find the first N fields separated by commas.
   Handles quoted fields. Returns number of fields extracted. */
static int
_csv_split(char *pszLine, char **ppFields, int nMaxFields)
{
    int nField = 0;
    char *p = pszLine;

    while (*p && nField < nMaxFields)
    {
        if (*p == '"')
        {
            p++;
            ppFields[nField++] = p;
            while (*p && !(*p == '"' && (*(p + 1) == ',' || *(p + 1) == '\0' || *(p + 1) == '\n')))
                p++;
            if (*p == '"')
                *p++ = '\0';
            if (*p == ',')
                *p++ = '\0';
        }
        else
        {
            ppFields[nField++] = p;
            while (*p && *p != ',' && *p != '\n' && *p != '\r')
                p++;
            if (*p == ',')
                *p++ = '\0';
            else if (*p)
                *p++ = '\0';
        }
    }
    return nField;
}

int
prn_map_load(PrnMap *pMap, const char *pszPath)
{
    FILE *fp;
    char szLine[4096];

    if (!pMap || !pszPath)
        return -1;

    memset(pMap, 0, sizeof(*pMap));

    fp = fopen(pszPath, "r");
    if (!fp)
        return -1;

    /* Skip header line */
    if (!fgets(szLine, sizeof(szLine), fp))
    {
        fclose(fp);
        return -1;
    }

    while (fgets(szLine, sizeof(szLine), fp))
    {
        if (pMap->dwCount >= PRN_MAX_ENTRIES)
            break;

        char *pFields[15];
        int nFields = _csv_split(szLine, pFields, 15);
        if (nFields < 2)
            continue;

        /* Column 0: Spec (e.g. "docker.spec")
           Column 1: Source0 original URL */
        char *pszSpec = pFields[0];
        char *pszSource0 = pFields[1];

        /* Strip .spec suffix from spec name */
        char szSpec[PRN_MAX_NAME];
        snprintf(szSpec, sizeof(szSpec), "%s", pszSpec);
        size_t len = strlen(szSpec);
        if (len > 5 && strcmp(szSpec + len - 5, ".spec") == 0)
            szSpec[len - 5] = '\0';

        /* Strip trailing whitespace */
        len = strlen(szSpec);
        while (len > 0 && isspace((unsigned char)szSpec[len - 1]))
            szSpec[--len] = '\0';

        if (szSpec[0] == '\0')
            continue;

        /* Try to extract github repo from Source0 */
        char szOwner[PRN_MAX_NAME], szRepo[PRN_MAX_NAME];
        if (_extract_github_repo(pszSource0, szOwner, sizeof(szOwner),
                                 szRepo, sizeof(szRepo)) != 0)
            continue;

        /* Reject entries with path traversal in repo/owner names */
        if (strstr(szRepo, "..") || strchr(szRepo, '/') ||
            strstr(szOwner, "..") || strchr(szOwner, '/') ||
            strstr(szSpec, "..") || strchr(szSpec, '/'))
            continue;

        PrnEntry *pEntry = &pMap->entries[pMap->dwCount];
        snprintf(pEntry->szSpec, sizeof(pEntry->szSpec), "%s", szSpec);
        snprintf(pEntry->szRepoOwner, sizeof(pEntry->szRepoOwner), "%s", szOwner);
        snprintf(pEntry->szRepoName, sizeof(pEntry->szRepoName), "%s", szRepo);
        snprintf(pEntry->szCloneName, sizeof(pEntry->szCloneName), "%s", szRepo);
        pMap->dwCount++;
    }

    fclose(fp);
    return 0;
}

const char *
prn_map_find_clone(const PrnMap *pMap, const char *pszPackage)
{
    if (!pMap || !pszPackage)
        return NULL;

    for (uint32_t i = 0; i < pMap->dwCount; i++)
    {
        if (strcasecmp(pMap->entries[i].szSpec, pszPackage) == 0)
            return pMap->entries[i].szCloneName;
    }
    return NULL;
}

const char *
prn_map_find_package(const PrnMap *pMap, const char *pszCloneName)
{
    if (!pMap || !pszCloneName)
        return NULL;

    for (uint32_t i = 0; i < pMap->dwCount; i++)
    {
        if (strcasecmp(pMap->entries[i].szCloneName, pszCloneName) == 0)
            return pMap->entries[i].szSpec;
    }
    return NULL;
}
