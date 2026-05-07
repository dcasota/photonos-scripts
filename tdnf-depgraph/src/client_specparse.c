/*
 * Copyright (C) 2026 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

/*
 * specparse.c
 *
 * Parses RPM .spec files from a SPECS/ directory to build a dependency graph.
 * Recognizes: Requires, BuildRequires, Conflicts, Obsoletes, Recommends,
 * Suggests, Supplements, Enhances, Requires(pre/post/preun/postun), Provides,
 * and %package subpackages with %{name}/%{version} macro expansion.
 */

#include "includes.h"
#include <dirent.h>
#include <ctype.h>

#pragma GCC diagnostic ignored "-Wformat-truncation"

#define MAX_SPEC_LINE 4096
#define MAX_PACKAGES  8192
#define MAX_DEPS_PER_PKG 512
#define MAX_NAME 256

typedef struct _SPEC_DEP {
    char szTarget[MAX_NAME];
    TDNF_DEP_EDGE_TYPE nType;
} SPEC_DEP;

typedef struct _SPEC_PACKAGE {
    char szName[MAX_NAME];
    char szSpecFile[MAX_NAME];
    int nIsMain;
    SPEC_DEP deps[MAX_DEPS_PER_PKG];
    uint32_t dwDepCount;
    char szProvides[64][MAX_NAME];
    uint32_t dwProvidesCount;
} SPEC_PACKAGE;

static void
ExpandMacros(
    char *pszDst,
    size_t nDstLen,
    const char *pszSrc,
    const char *pszName,
    const char *pszVersion
    )
{
    const char *p = pszSrc;
    char *d = pszDst;
    char *dend = pszDst + nDstLen - 1;

    while (*p && d < dend)
    {
        if (p[0] == '%' && p[1] == '{')
        {
            const char *close = strchr(p + 2, '}');
            if (close)
            {
                size_t mlen = close - (p + 2);
                if (mlen == 4 && strncmp(p + 2, "name", 4) == 0)
                {
                    size_t nlen = strlen(pszName);
                    if (d + nlen < dend)
                    {
                        memcpy(d, pszName, nlen);
                        d += nlen;
                    }
                    p = close + 1;
                    continue;
                }
                else if (mlen == 7 && strncmp(p + 2, "version", 7) == 0)
                {
                    size_t vlen = strlen(pszVersion);
                    if (d + vlen < dend)
                    {
                        memcpy(d, pszVersion, vlen);
                        d += vlen;
                    }
                    p = close + 1;
                    continue;
                }
                else if (mlen == 7 && strncmp(p + 2, "release", 7) == 0)
                {
                    *d++ = '1';
                    p = close + 1;
                    continue;
                }
                else if (mlen >= 4 && strncmp(p + 2, "?dis", 4) == 0)
                {
                    p = close + 1;
                    continue;
                }
            }
        }
        *d++ = *p++;
    }
    *d = '\0';
}

/* Strip version constraints: "foo >= 1.2" -> "foo" */
static void
StripVersionConstraint(char *pszDep)
{
    char *p = pszDep;
    while (*p)
    {
        if (*p == '>' || *p == '<' || *p == '=')
        {
            /* Walk back to trim trailing spaces */
            while (p > pszDep && *(p - 1) == ' ')
                p--;
            *p = '\0';
            return;
        }
        p++;
    }
    /* Trim trailing whitespace */
    p = pszDep + strlen(pszDep) - 1;
    while (p > pszDep && isspace((unsigned char)*p))
        *p-- = '\0';
}

static TDNF_DEP_EDGE_TYPE
ParseDepTag(const char *pszTag)
{
    if (strcasecmp(pszTag, "Requires") == 0 ||
        strcasecmp(pszTag, "Requires(pre)") == 0 ||
        strcasecmp(pszTag, "Requires(post)") == 0 ||
        strcasecmp(pszTag, "Requires(preun)") == 0 ||
        strcasecmp(pszTag, "Requires(postun)") == 0)
        return DEP_EDGE_REQUIRES;
    if (strcasecmp(pszTag, "BuildRequires") == 0)
        return DEP_EDGE_BUILDREQUIRES;
    if (strcasecmp(pszTag, "Conflicts") == 0 ||
        strcasecmp(pszTag, "BuildConflicts") == 0)
        return DEP_EDGE_CONFLICTS;
    if (strcasecmp(pszTag, "Obsoletes") == 0)
        return DEP_EDGE_OBSOLETES;
    if (strcasecmp(pszTag, "Recommends") == 0)
        return DEP_EDGE_RECOMMENDS;
    if (strcasecmp(pszTag, "Suggests") == 0)
        return DEP_EDGE_SUGGESTS;
    if (strcasecmp(pszTag, "Supplements") == 0)
        return DEP_EDGE_SUPPLEMENTS;
    if (strcasecmp(pszTag, "Enhances") == 0)
        return DEP_EDGE_ENHANCES;
    return (TDNF_DEP_EDGE_TYPE)-1;
}

static uint32_t
ParseOneSpec(
    const char *pszSpecPath,
    const char *pszRelSpec,
    SPEC_PACKAGE *pPkgs,
    uint32_t *pdwPkgCount,
    uint32_t dwMaxPkgs
    )
{
    uint32_t dwError = 0;
    FILE *fp = NULL;
    char szLine[MAX_SPEC_LINE];
    char szName[MAX_NAME] = {0};
    char szVersion[MAX_NAME] = {0};
    SPEC_PACKAGE *pCur = NULL;
    char *line;
    size_t len;

    fp = fopen(pszSpecPath, "r");
    if (!fp)
    {
        /* Skip unreadable files */
        goto cleanup;
    }

    while (fgets(szLine, sizeof(szLine), fp))
    {
        line = szLine;
        /* Trim leading whitespace */
        while (*line && isspace((unsigned char)*line))
            line++;

        /* Remove trailing newline */
        len = strlen(line);
        if (len > 0 && line[len - 1] == '\n')
            line[len - 1] = '\0';
        len = strlen(line);
        if (len > 0 && line[len - 1] == '\r')
            line[len - 1] = '\0';

        /* Skip comments and empty */
        if (*line == '#' || *line == '\0')
            continue;

        /* Skip preprocessor directives we can't resolve */
        if (*line == '%')
        {
            if (strncmp(line, "%package", 8) == 0)
            {
                /* Subpackage */
                char *sub = line + 8;
                while (*sub && isspace((unsigned char)*sub))
                    sub++;

                if (*pdwPkgCount >= dwMaxPkgs)
                    continue;

                pCur = &pPkgs[*pdwPkgCount];
                memset(pCur, 0, sizeof(*pCur));
                pCur->nIsMain = 0;

                /* Handle "-n <absolute_name>" */
                if (strncmp(sub, "-n", 2) == 0 && isspace((unsigned char)sub[2]))
                {
                    sub += 3;
                    while (*sub && isspace((unsigned char)*sub))
                        sub++;
                    ExpandMacros(pCur->szName, sizeof(pCur->szName),
                                 sub, szName, szVersion);
                }
                else
                {
                    char szFull[MAX_NAME];
                    snprintf(szFull, sizeof(szFull), "%s-%s", szName, sub);
                    ExpandMacros(pCur->szName, sizeof(pCur->szName),
                                 szFull, szName, szVersion);
                }

                snprintf(pCur->szSpecFile, sizeof(pCur->szSpecFile),
                         "%s", pszRelSpec);

                /* Self-provide */
                snprintf(pCur->szProvides[0], MAX_NAME, "%s", pCur->szName);
                pCur->dwProvidesCount = 1;

                (*pdwPkgCount)++;
            }
            continue;
        }

        /* Name: */
        if (strncasecmp(line, "Name:", 5) == 0)
        {
            char *val = line + 5;
            while (*val && isspace((unsigned char)*val))
                val++;
            snprintf(szName, sizeof(szName), "%s", val);

            /* Trim trailing whitespace */
            len = strlen(szName);
            while (len > 0 && isspace((unsigned char)szName[len - 1]))
                szName[--len] = '\0';

            if (*pdwPkgCount >= dwMaxPkgs)
                continue;

            pCur = &pPkgs[*pdwPkgCount];
            memset(pCur, 0, sizeof(*pCur));
            pCur->nIsMain = 1;
            snprintf(pCur->szName, sizeof(pCur->szName), "%s", szName);
            snprintf(pCur->szSpecFile, sizeof(pCur->szSpecFile),
                     "%s", pszRelSpec);
            snprintf(pCur->szProvides[0], MAX_NAME, "%s", szName);
            pCur->dwProvidesCount = 1;
            (*pdwPkgCount)++;
            continue;
        }

        /* Version: */
        if (strncasecmp(line, "Version:", 8) == 0)
        {
            char *val = line + 8;
            while (*val && isspace((unsigned char)*val))
                val++;
            snprintf(szVersion, sizeof(szVersion), "%s", val);
            len = strlen(szVersion);
            while (len > 0 && isspace((unsigned char)szVersion[len - 1]))
                szVersion[--len] = '\0';
            continue;
        }

        /* Provides: */
        if (strncasecmp(line, "Provides:", 9) == 0 && pCur)
        {
            char *val;
            char szExp[MAX_NAME];

            val = line + 9;
            while (*val && isspace((unsigned char)*val))
                val++;

            ExpandMacros(szExp, sizeof(szExp), val, szName, szVersion);
            StripVersionConstraint(szExp);

            if (szExp[0] && pCur->dwProvidesCount < 64)
            {
                snprintf(pCur->szProvides[pCur->dwProvidesCount],
                         MAX_NAME, "%s", szExp);
                pCur->dwProvidesCount++;
            }
            continue;
        }

        /* Dependency tags */
        {
            static const char *depTags[] = {
                "BuildRequires:", "Requires(pre):", "Requires(post):",
                "Requires(preun):", "Requires(postun):",
                "Requires:", "BuildConflicts:", "Conflicts:", "Obsoletes:",
                "Recommends:", "Suggests:", "Supplements:", "Enhances:",
                NULL
            };
            int t;

            if (!pCur)
                continue;

            for (t = 0; depTags[t]; t++)
            {
                size_t tlen = strlen(depTags[t]);
                if (strncasecmp(line, depTags[t], tlen) == 0)
                {
                    char *val;
                    char szTag[64];
                    char szExp[MAX_NAME];
                    TDNF_DEP_EDGE_TYPE nType;

                    val = line + tlen;
                    while (*val && isspace((unsigned char)*val))
                        val++;

                    /* Extract tag name (without colon) for type lookup */
                    snprintf(szTag, sizeof(szTag), "%.*s",
                             (int)(tlen - 1), depTags[t]);

                    nType = ParseDepTag(szTag);
                    if ((int)nType == -1)
                        break;

                    ExpandMacros(szExp, sizeof(szExp), val, szName, szVersion);
                    StripVersionConstraint(szExp);

                    /* Skip file deps and pkgconfig() */
                    if (szExp[0] == '/' || strncmp(szExp, "pkgconfig(", 10) == 0)
                        break;

                    if (szExp[0] && pCur->dwDepCount < MAX_DEPS_PER_PKG)
                    {
                        snprintf(pCur->deps[pCur->dwDepCount].szTarget,
                                 MAX_NAME, "%s", szExp);
                        pCur->deps[pCur->dwDepCount].nType = nType;
                        pCur->dwDepCount++;
                    }
                    break;
                }
            }
        }
    }

cleanup:
    if (fp)
        fclose(fp);
    return dwError;
}

static uint32_t
WalkSpecsDir(
    const char *pszSpecsDir,
    SPEC_PACKAGE *pPkgs,
    uint32_t *pdwPkgCount,
    uint32_t dwMaxPkgs
    )
{
    uint32_t dwError = 0;
    DIR *pDir = NULL;
    struct dirent *pEntry = NULL;
    char szSubDir[PATH_MAX];
    DIR *pSub;
    struct dirent *pSpec;
    size_t nlen;
    char szSpec[PATH_MAX];
    char szRel[MAX_NAME];

    pDir = opendir(pszSpecsDir);
    if (!pDir)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    while ((pEntry = readdir(pDir)) != NULL)
    {
        if (pEntry->d_name[0] == '.')
            continue;

        snprintf(szSubDir, sizeof(szSubDir), "%s/%s",
                 pszSpecsDir, pEntry->d_name);

        /* Each SPECS/<pkg>/ may contain one or more .spec files */
        pSub = opendir(szSubDir);
        if (!pSub)
            continue;

        while ((pSpec = readdir(pSub)) != NULL)
        {
            nlen = strlen(pSpec->d_name);
            if (nlen < 6 || strcmp(pSpec->d_name + nlen - 5, ".spec") != 0)
                continue;

            snprintf(szSpec, sizeof(szSpec), "%s/%s", szSubDir, pSpec->d_name);
            snprintf(szRel, sizeof(szRel), "%s/%s",
                     pEntry->d_name, pSpec->d_name);

            ParseOneSpec(szSpec, szRel, pPkgs, pdwPkgCount, dwMaxPkgs);
        }
        closedir(pSub);
    }

cleanup:
    if (pDir)
        closedir(pDir);
    return dwError;

error:
    goto cleanup;
}

uint32_t
TDNFBuildDepGraphFromSpecs(
    const char *pszSpecsDir,
    PTDNF_DEP_GRAPH *ppGraph
    )
{
    uint32_t dwError = 0;
    PTDNF_DEP_GRAPH pGraph = NULL;
    SPEC_PACKAGE *pPkgs = NULL;
    uint32_t dwPkgCount = 0;
    uint32_t i, j, d, p;
    const char *pszTarget;
    TDNF_DEP_EDGE_TYPE nType;
    int nFound;
    PTDNF_DEP_EDGE pEdge;

    if (!pszSpecsDir || !ppGraph)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFAllocateMemory(MAX_PACKAGES, sizeof(SPEC_PACKAGE),
                                 (void **)&pPkgs);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = WalkSpecsDir(pszSpecsDir, pPkgs, &dwPkgCount, MAX_PACKAGES);
    BAIL_ON_TDNF_ERROR(dwError);

    if (dwPkgCount == 0)
    {
        dwError = ERROR_TDNF_NO_DATA;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    /* Build provides -> package index map (simple linear scan) */

    /* Allocate graph */
    dwError = TDNFAllocateMemory(1, sizeof(TDNF_DEP_GRAPH),
                                 (void **)&pGraph);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFAllocateMemory(dwPkgCount, sizeof(TDNF_DEP_GRAPH_NODE),
                                 (void **)&pGraph->pNodes);
    BAIL_ON_TDNF_ERROR(dwError);

    pGraph->dwNodeCount = dwPkgCount;

    /* Populate nodes */
    for (i = 0; i < dwPkgCount; i++)
    {
        dwError = TDNFAllocateString(pPkgs[i].szName,
                                     &pGraph->pNodes[i].pszName);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFAllocateString(pPkgs[i].szName,
                                     &pGraph->pNodes[i].pszNevra);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFAllocateString("x86_64",
                                     &pGraph->pNodes[i].pszArch);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFAllocateString("",
                                     &pGraph->pNodes[i].pszEvr);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFAllocateString(pPkgs[i].szSpecFile,
                                     &pGraph->pNodes[i].pszRepo);
        BAIL_ON_TDNF_ERROR(dwError);

        pGraph->pNodes[i].dwSolvableId = i;
        pGraph->pNodes[i].nIsSource = pPkgs[i].nIsMain;
    }

    /* Resolve deps: for each dep target, find the providing package by name */
    for (i = 0; i < dwPkgCount; i++)
    {
        for (d = 0; d < pPkgs[i].dwDepCount; d++)
        {
            pszTarget = pPkgs[i].deps[d].szTarget;
            nType = pPkgs[i].deps[d].nType;
            nFound = 0;

            /* Search provides */
            for (j = 0; j < dwPkgCount && !nFound; j++)
            {
                if (j == i)
                    continue;
                for (p = 0; p < pPkgs[j].dwProvidesCount; p++)
                {
                    if (strcmp(pszTarget, pPkgs[j].szProvides[p]) == 0)
                    {
                        pEdge = NULL;
                        dwError = TDNFAllocateMemory(1, sizeof(TDNF_DEP_EDGE),
                                                     (void **)&pEdge);
                        BAIL_ON_TDNF_ERROR(dwError);

                        pEdge->dwFromIdx = i;
                        pEdge->dwToIdx = j;
                        pEdge->nType = nType;
                        pEdge->pNext = pGraph->pNodes[i].pEdgesOut;
                        pGraph->pNodes[i].pEdgesOut = pEdge;
                        pGraph->pNodes[j].dwReverseDepCount++;
                        pGraph->dwEdgeCount++;
                        nFound = 1;
                        break;
                    }
                }
            }

            /* If not found via provides, try direct name match */
            if (!nFound)
            {
                for (j = 0; j < dwPkgCount; j++)
                {
                    if (j == i)
                        continue;
                    if (strcmp(pszTarget, pPkgs[j].szName) == 0)
                    {
                        pEdge = NULL;
                        dwError = TDNFAllocateMemory(1, sizeof(TDNF_DEP_EDGE),
                                                     (void **)&pEdge);
                        BAIL_ON_TDNF_ERROR(dwError);

                        pEdge->dwFromIdx = i;
                        pEdge->dwToIdx = j;
                        pEdge->nType = nType;
                        pEdge->pNext = pGraph->pNodes[i].pEdgesOut;
                        pGraph->pNodes[i].pEdgesOut = pEdge;
                        pGraph->pNodes[j].dwReverseDepCount++;
                        pGraph->dwEdgeCount++;
                        break;
                    }
                }
            }
        }
    }

    *ppGraph = pGraph;

cleanup:
    TDNF_SAFE_FREE_MEMORY(pPkgs);
    return dwError;

error:
    if (pGraph)
    {
        SolvFreeDepGraph(pGraph);
    }
    goto cleanup;
}
