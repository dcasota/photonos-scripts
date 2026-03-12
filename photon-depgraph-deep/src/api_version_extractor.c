#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <ctype.h>
#include <sys/stat.h>

#include "api_version_extractor.h"

int
api_patterns_load(ApiVersionPatterns *pPatterns, const char *pszCsvPath)
{
    FILE *fp;
    char szLine[MAX_LINE_LEN];

    if (!pPatterns || !pszCsvPath)
        return -1;

    pPatterns->dwCount = 0;

    fp = fopen(pszCsvPath, "r");
    if (!fp)
    {
        fprintf(stderr, "api_patterns: cannot open %s\n", pszCsvPath);
        return -1;
    }

    while (fgets(szLine, sizeof(szLine), fp))
    {
        char *p = szLine;
        char *pFields[5];
        int nField = 0;
        ApiVersionPattern *pEntry;

        /* strip newline */
        {
            size_t n = strlen(szLine);
            while (n > 0 && (szLine[n - 1] == '\n' || szLine[n - 1] == '\r'))
                szLine[--n] = '\0';
        }

        /* skip comments and blank lines */
        while (*p && isspace((unsigned char)*p))
            p++;
        if (*p == '#' || *p == '\0')
            continue;

        if (pPatterns->dwCount >= MAX_PATTERN_ENTRIES)
            break;

        /* parse CSV: package,filepath,regex_pattern,type,virtual_name */
        pFields[0] = p;
        for (nField = 1; nField < 5 && *p; p++)
        {
            if (*p == ',')
            {
                *p = '\0';
                pFields[nField++] = p + 1;
            }
        }
        if (nField < 5)
            continue;

        pEntry = &pPatterns->entries[pPatterns->dwCount];
        snprintf(pEntry->szPackage, sizeof(pEntry->szPackage), "%s",
                 pFields[0]);
        snprintf(pEntry->szFilePath, sizeof(pEntry->szFilePath), "%s",
                 pFields[1]);
        snprintf(pEntry->szPattern, sizeof(pEntry->szPattern), "%s",
                 pFields[2]);
        snprintf(pEntry->szProvideType, sizeof(pEntry->szProvideType), "%s",
                 pFields[3]);
        snprintf(pEntry->szVirtualName, sizeof(pEntry->szVirtualName), "%s",
                 pFields[4]);
        pPatterns->dwCount++;
    }

    fclose(fp);
    return 0;
}

/* Try to find clone directory for a package name. The clone dir may match the
   package name directly, or with python3-/python- prefix stripped, etc. */
static int
_find_clone_dir(const char *pszClonesDir, const char *pszPackage,
                char *pszOut, size_t nMax)
{
    struct stat st;

    snprintf(pszOut, nMax, "%s/%s", pszClonesDir, pszPackage);
    if (stat(pszOut, &st) == 0 && S_ISDIR(st.st_mode))
        return 0;

    /* try stripping python3- prefix */
    if (strncmp(pszPackage, "python3-", 8) == 0)
    {
        snprintf(pszOut, nMax, "%s/%s", pszClonesDir, pszPackage + 8);
        if (stat(pszOut, &st) == 0 && S_ISDIR(st.st_mode))
            return 0;
    }

    /* try stripping python- prefix */
    if (strncmp(pszPackage, "python-", 7) == 0)
    {
        snprintf(pszOut, nMax, "%s/%s", pszClonesDir, pszPackage + 7);
        if (stat(pszOut, &st) == 0 && S_ISDIR(st.st_mode))
            return 0;
    }

    return -1;
}

/* Extract value between double quotes following the literal pattern prefix.
   Returns 0 on success. */
static int
_extract_value(const char *pszContent, const char *pszPattern,
               char *pszOut, size_t nMax)
{
    const char *pFound;
    const char *p;
    size_t i;

    pFound = strstr(pszContent, pszPattern);
    if (!pFound)
        return -1;

    p = pFound + strlen(pszPattern);

    /* skip whitespace to reach the quote */
    while (*p && isspace((unsigned char)*p))
        p++;

    if (*p != '"')
        return -1;

    p++;
    i = 0;
    while (*p && *p != '"' && i < nMax - 1)
        pszOut[i++] = *p++;
    pszOut[i] = '\0';

    if (i == 0)
        return -1;

    return 0;
}

int
api_version_extract(DepGraph *pGraph, const char *pszClonesDir,
                    const ApiVersionPatterns *pPatterns)
{
    uint32_t i;

    if (!pGraph || !pszClonesDir || !pPatterns)
        return -1;

    for (i = 0; i < pPatterns->dwCount; i++)
    {
        const ApiVersionPattern *pEntry = &pPatterns->entries[i];
        char szCloneDir[MAX_PATH_LEN];
        char szFullPath[MAX_PATH_LEN];
        FILE *fp;
        char *pBuf;
        long nLen;
        char szValue[MAX_VERSION_LEN];
        int32_t nNodeIdx;
        char szEvidence[MAX_EVIDENCE_LEN];

        if (_find_clone_dir(pszClonesDir, pEntry->szPackage,
                            szCloneDir, sizeof(szCloneDir)) != 0)
            continue;

        snprintf(szFullPath, sizeof(szFullPath), "%s/%s",
                 szCloneDir, pEntry->szFilePath);

        fp = fopen(szFullPath, "r");
        if (!fp)
            continue;

        fseek(fp, 0, SEEK_END);
        nLen = ftell(fp);
        fseek(fp, 0, SEEK_SET);

        if (nLen <= 0 || nLen > 4 * 1024 * 1024)
        {
            fclose(fp);
            continue;
        }

        pBuf = (char *)malloc((size_t)nLen + 1);
        if (!pBuf)
        {
            fclose(fp);
            continue;
        }
        fread(pBuf, 1, (size_t)nLen, fp);
        pBuf[nLen] = '\0';
        fclose(fp);

        if (_extract_value(pBuf, pEntry->szPattern,
                           szValue, sizeof(szValue)) != 0)
        {
            free(pBuf);
            continue;
        }

        free(pBuf);

        nNodeIdx = graph_find_node(pGraph, pEntry->szPackage);
        if (nNodeIdx < 0)
            continue;

        snprintf(szEvidence, sizeof(szEvidence),
                 "api_version: %s in %s/%s",
                 pEntry->szPattern, pEntry->szPackage, pEntry->szFilePath);

        if (strcmp(pEntry->szProvideType, "provides") == 0)
        {
            graph_add_virtual(pGraph, pEntry->szVirtualName, szValue,
                              (uint32_t)nNodeIdx, EDGE_SRC_API_CONSTANT,
                              szEvidence);
        }
        else if (strcmp(pEntry->szProvideType, "requires") == 0)
        {
            int32_t nVirtProvider = graph_find_node(pGraph,
                                                    pEntry->szVirtualName);
            if (nVirtProvider >= 0 && nVirtProvider != nNodeIdx)
            {
                graph_add_edge(pGraph, (uint32_t)nNodeIdx,
                               (uint32_t)nVirtProvider,
                               EDGE_REQUIRES, EDGE_SRC_API_CONSTANT,
                               CONSTRAINT_GE, szValue,
                               szEvidence, pEntry->szVirtualName);
            }
        }
    }

    return 0;
}
