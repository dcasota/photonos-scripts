/*
 * Copyright (C) 2026 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#include "includes.h"

static uint32_t
SolvDepGraphAddEdge(
    PTDNF_DEP_GRAPH pGraph,
    uint32_t dwFromIdx,
    uint32_t dwToIdx,
    TDNF_DEP_EDGE_TYPE nType
    )
{
    uint32_t dwError = 0;
    PTDNF_DEP_EDGE pEdge = NULL;

    if (!pGraph || dwFromIdx >= pGraph->dwNodeCount ||
        dwToIdx >= pGraph->dwNodeCount)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFAllocateMemory(1, sizeof(TDNF_DEP_EDGE),
                                 (void **)&pEdge);
    BAIL_ON_TDNF_ERROR(dwError);

    pEdge->dwFromIdx = dwFromIdx;
    pEdge->dwToIdx = dwToIdx;
    pEdge->nType = nType;

    pEdge->pNext = pGraph->pNodes[dwFromIdx].pEdgesOut;
    pGraph->pNodes[dwFromIdx].pEdgesOut = pEdge;

    pGraph->pNodes[dwToIdx].dwReverseDepCount++;
    pGraph->dwEdgeCount++;

cleanup:
    return dwError;

error:
    TDNF_SAFE_FREE_MEMORY(pEdge);
    goto cleanup;
}

typedef struct {
    Id nSolvableKey;
    TDNF_DEP_EDGE_TYPE nEdgeType;
    int nReverse;
} DEP_KEY_MAP;

static void
SolvDepGraphResolveDeps(
    Pool *pool,
    Solvable *pSolv,
    PTDNF_DEP_GRAPH pGraph,
    uint32_t *pIdxMap,
    uint32_t dwSrcIdx,
    Id nSolvableKey,
    TDNF_DEP_EDGE_TYPE nType,
    int nReverse
    )
{
    Queue qDeps = {0};
    int i;
    Id dep, provider, pp;
    uint32_t dwProviderIdx;

    queue_init(&qDeps);
    solvable_lookup_deparray(pSolv, nSolvableKey, &qDeps, -1);

    for (i = 0; i < qDeps.count; i++)
    {
        dep = qDeps.elements[i];

        FOR_PROVIDES(provider, pp, dep)
        {
            if (provider <= 0 ||
                provider >= pool->nsolvables)
                continue;

            dwProviderIdx = pIdxMap[provider];
            if (dwProviderIdx == (uint32_t)-1)
                continue;
            if (dwProviderIdx == dwSrcIdx)
                continue;

            if (nReverse)
                SolvDepGraphAddEdge(pGraph, dwSrcIdx, dwProviderIdx, nType);
            else
                SolvDepGraphAddEdge(pGraph, dwProviderIdx, dwSrcIdx, nType);
        }
    }

    queue_free(&qDeps);
}

uint32_t
SolvBuildDepGraph(
    PSolvSack pSack,
    PTDNF_DEP_GRAPH *ppGraph
    )
{
    uint32_t dwError = 0;
    Pool *pool = NULL;
    PTDNF_DEP_GRAPH pGraph = NULL;
    uint32_t *pIdxMap = NULL;
    uint32_t dwNodeCount = 0;
    uint32_t dwIdx = 0;
    uint32_t dwSrcIdx;
    int nIsSource;
    int k;
    Id p;
    Solvable *s;
    const char *pszName;
    const char *pszArch;
    const char *pszEvr;
    const char *pszRepo;
    TDNF_DEP_EDGE_TYPE nType;
    static const DEP_KEY_MAP depKeys[] = {
        { SOLVABLE_REQUIRES,    DEP_EDGE_REQUIRES,    0 },
        { SOLVABLE_CONFLICTS,   DEP_EDGE_CONFLICTS,   1 },
        { SOLVABLE_OBSOLETES,   DEP_EDGE_OBSOLETES,   1 },
        { SOLVABLE_RECOMMENDS,  DEP_EDGE_RECOMMENDS,  0 },
        { SOLVABLE_SUGGESTS,    DEP_EDGE_SUGGESTS,    0 },
        { SOLVABLE_SUPPLEMENTS, DEP_EDGE_SUPPLEMENTS, 0 },
        { SOLVABLE_ENHANCES,    DEP_EDGE_ENHANCES,    0 },
    };

    if (!pSack || !pSack->pPool || !ppGraph)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pool = pSack->pPool;

    FOR_POOL_SOLVABLES(p)
    {
        dwNodeCount++;
    }

    if (dwNodeCount == 0)
    {
        dwError = ERROR_TDNF_NO_DATA;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFAllocateMemory(1, sizeof(TDNF_DEP_GRAPH),
                                 (void **)&pGraph);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFAllocateMemory(dwNodeCount, sizeof(TDNF_DEP_GRAPH_NODE),
                                 (void **)&pGraph->pNodes);
    BAIL_ON_TDNF_ERROR(dwError);

    pGraph->dwNodeCount = dwNodeCount;

    dwError = TDNFAllocateMemory(pool->nsolvables, sizeof(uint32_t),
                                 (void **)&pIdxMap);
    BAIL_ON_TDNF_ERROR(dwError);

    memset(pIdxMap, 0xff, pool->nsolvables * sizeof(uint32_t));

    /* Populate nodes */
    FOR_POOL_SOLVABLES(p)
    {
        s = pool_id2solvable(pool, p);
        pIdxMap[p] = dwIdx;

        pszName = pool_id2str(pool, s->name);
        pszArch = pool_id2str(pool, s->arch);
        pszEvr  = pool_id2str(pool, s->evr);
        pszRepo = s->repo ? s->repo->name : "(none)";

        dwError = TDNFAllocateString(pszName,
                                     &pGraph->pNodes[dwIdx].pszName);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFAllocateStringPrintf(
                      &pGraph->pNodes[dwIdx].pszNevra,
                      "%s-%s.%s", pszName, pszEvr, pszArch);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFAllocateString(pszArch,
                                     &pGraph->pNodes[dwIdx].pszArch);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFAllocateString(pszEvr,
                                     &pGraph->pNodes[dwIdx].pszEvr);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFAllocateString(pszRepo,
                                     &pGraph->pNodes[dwIdx].pszRepo);
        BAIL_ON_TDNF_ERROR(dwError);

        pGraph->pNodes[dwIdx].dwSolvableId = p;
        pGraph->pNodes[dwIdx].nIsSource =
            (strcmp(pszArch, "src") == 0) ? 1 : 0;

        dwIdx++;
    }

    /* Resolve dependencies and build edges */
    FOR_POOL_SOLVABLES(p)
    {
        dwSrcIdx = pIdxMap[p];
        s = pool_id2solvable(pool, p);

        nIsSource = pGraph->pNodes[dwSrcIdx].nIsSource;

        for (k = 0; k < (int)(sizeof(depKeys) / sizeof(depKeys[0])); k++)
        {
            nType = depKeys[k].nEdgeType;

            /* Tag Requires from source packages as BuildRequires */
            if (nIsSource && nType == DEP_EDGE_REQUIRES)
                nType = DEP_EDGE_BUILDREQUIRES;

            SolvDepGraphResolveDeps(
                pool, s, pGraph, pIdxMap, dwSrcIdx,
                depKeys[k].nSolvableKey, nType, depKeys[k].nReverse);
        }
    }

    *ppGraph = pGraph;

cleanup:
    TDNF_SAFE_FREE_MEMORY(pIdxMap);
    return dwError;

error:
    if (pGraph)
    {
        SolvFreeDepGraph(pGraph);
    }
    goto cleanup;
}

void
SolvFreeDepGraph(
    PTDNF_DEP_GRAPH pGraph
    )
{
    uint32_t i;
    PTDNF_DEP_EDGE pEdge, pNext;

    if (!pGraph)
        return;

    if (pGraph->pNodes)
    {
        for (i = 0; i < pGraph->dwNodeCount; i++)
        {
            TDNF_SAFE_FREE_MEMORY(pGraph->pNodes[i].pszName);
            TDNF_SAFE_FREE_MEMORY(pGraph->pNodes[i].pszNevra);
            TDNF_SAFE_FREE_MEMORY(pGraph->pNodes[i].pszArch);
            TDNF_SAFE_FREE_MEMORY(pGraph->pNodes[i].pszEvr);
            TDNF_SAFE_FREE_MEMORY(pGraph->pNodes[i].pszRepo);

            pEdge = pGraph->pNodes[i].pEdgesOut;
            while (pEdge)
            {
                pNext = pEdge->pNext;
                TDNFFreeMemory(pEdge);
                pEdge = pNext;
            }
        }
        TDNFFreeMemory(pGraph->pNodes);
    }
    TDNFFreeMemory(pGraph);
}
