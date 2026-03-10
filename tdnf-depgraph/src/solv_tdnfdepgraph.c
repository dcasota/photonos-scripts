/*
 * Copyright (C) 2026 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

/*
 * solv/tdnfdepgraph.c
 *
 * Walks the libsolv Pool to build a complete RPM dependency graph.
 * Resolves Requires, Conflicts, Obsoletes, Recommends, Suggests,
 * Supplements, and Enhances via FOR_PROVIDES -- the same resolution
 * path used by tdnf install/update.
 *
 * Place this file in tdnf/solv/ and add to solv/CMakeLists.txt.
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

static void
SolvDepGraphWalkDepArray(
    Pool *pPool,
    Id *pIdArray,
    PTDNF_DEP_GRAPH pGraph,
    uint32_t *pIdxMap,
    uint32_t dwSrcIdx,
    TDNF_DEP_EDGE_TYPE nType,
    int nReverse
    )
{
    Id dep;
    Id provider, pp;

    if (!pIdArray)
        return;

    while ((dep = *pIdArray++) != 0)
    {
        if (ISRELDEP(dep))
        {
            Reldep *rd = GETRELDEP(pPool, dep);
            if (rd->flags == REL_AND || rd->flags == REL_OR ||
                rd->flags == REL_WITH || rd->flags == REL_WITHOUT ||
                rd->flags == REL_COND || rd->flags == REL_UNLESS)
            {
                continue;
            }
        }

        FOR_PROVIDES(provider, pp, dep)
        {
            if (provider <= 0 ||
                provider >= pPool->nsolvables)
                continue;

            uint32_t dwProviderIdx = pIdxMap[provider];
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
}

uint32_t
SolvBuildDepGraph(
    PSolvSack pSack,
    PTDNF_DEP_GRAPH *ppGraph
    )
{
    uint32_t dwError = 0;
    Pool *pPool = NULL;
    PTDNF_DEP_GRAPH pGraph = NULL;
    uint32_t *pIdxMap = NULL;
    uint32_t dwNodeCount = 0;
    Id p;
    Solvable *s;

    if (!pSack || !pSack->pPool || !ppGraph)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pPool = pSack->pPool;

    /* First pass: count solvables */
    FOR_POOL_SOLVABLES(p)
    {
        if (pPool->considered && !MAPTST(pPool->considered, p))
            continue;
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

    /* Solvable ID -> node index map */
    dwError = TDNFAllocateMemory(pPool->nsolvables, sizeof(uint32_t),
                                 (void **)&pIdxMap);
    BAIL_ON_TDNF_ERROR(dwError);

    memset(pIdxMap, 0xff, pPool->nsolvables * sizeof(uint32_t));

    /* Second pass: populate nodes */
    uint32_t dwIdx = 0;
    FOR_POOL_SOLVABLES(p)
    {
        if (pPool->considered && !MAPTST(pPool->considered, p))
            continue;

        s = pool_id2solvable(pPool, p);
        pIdxMap[p] = dwIdx;

        const char *pszName = pool_id2str(pPool, s->name);
        const char *pszArch = pool_id2str(pPool, s->arch);
        const char *pszEvr = pool_id2str(pPool, s->evr);
        const char *pszRepo = s->repo ? s->repo->name : "(none)";

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

    /* Third pass: resolve dependencies and build edges */
    FOR_POOL_SOLVABLES(p)
    {
        if (pPool->considered && !MAPTST(pPool->considered, p))
            continue;

        uint32_t dwSrcIdx = pIdxMap[p];
        s = pool_id2solvable(pPool, p);

        int nIsSource = pGraph->pNodes[dwSrcIdx].nIsSource;
        TDNF_DEP_EDGE_TYPE nReqType = nIsSource ?
            DEP_EDGE_BUILDREQUIRES : DEP_EDGE_REQUIRES;

        /* Requires (or BuildRequires for src packages) */
        if (s->requires)
        {
            SolvDepGraphWalkDepArray(
                pPool,
                pPool->idarraydata + s->requires,
                pGraph, pIdxMap, dwSrcIdx, nReqType, 0);
        }

        /* Conflicts: src -> conflicting package */
        if (s->conflicts)
        {
            SolvDepGraphWalkDepArray(
                pPool,
                pPool->idarraydata + s->conflicts,
                pGraph, pIdxMap, dwSrcIdx, DEP_EDGE_CONFLICTS, 1);
        }

        /* Obsoletes: src -> obsoleted package */
        if (s->obsoletes)
        {
            SolvDepGraphWalkDepArray(
                pPool,
                pPool->idarraydata + s->obsoletes,
                pGraph, pIdxMap, dwSrcIdx, DEP_EDGE_OBSOLETES, 1);
        }

        /* Recommends */
        if (s->recommends)
        {
            SolvDepGraphWalkDepArray(
                pPool,
                pPool->idarraydata + s->recommends,
                pGraph, pIdxMap, dwSrcIdx, DEP_EDGE_RECOMMENDS, 0);
        }

        /* Suggests */
        if (s->suggests)
        {
            SolvDepGraphWalkDepArray(
                pPool,
                pPool->idarraydata + s->suggests,
                pGraph, pIdxMap, dwSrcIdx, DEP_EDGE_SUGGESTS, 0);
        }

        /* Supplements */
        if (s->supplements)
        {
            SolvDepGraphWalkDepArray(
                pPool,
                pPool->idarraydata + s->supplements,
                pGraph, pIdxMap, dwSrcIdx, DEP_EDGE_SUPPLEMENTS, 0);
        }

        /* Enhances */
        if (s->enhances)
        {
            SolvDepGraphWalkDepArray(
                pPool,
                pPool->idarraydata + s->enhances,
                pGraph, pIdxMap, dwSrcIdx, DEP_EDGE_ENHANCES, 0);
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
