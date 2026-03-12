#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>

#pragma GCC diagnostic ignored "-Wformat-truncation"

#include "conflict_detector.h"
#include "virtual_provides.h"

static SpecPatchSet *
find_or_create_patchset(DepGraph *pGraph, const char *szSpecPath,
                        const char *szPackageName)
{
    SpecPatchSet *pSet = pGraph->pPatchSets;
    while (pSet)
    {
        if (strcmp(pSet->szSpecPath, szSpecPath) == 0)
        {
            return pSet;
        }
        pSet = pSet->pNext;
    }

    pSet = calloc(1, sizeof(SpecPatchSet));
    if (!pSet)
    {
        return NULL;
    }

    snprintf(pSet->szSpecPath, sizeof(pSet->szSpecPath), "%s", szSpecPath);
    snprintf(pSet->szPackageName, sizeof(pSet->szPackageName),
             "%s", szPackageName);
    graph_add_patchset(pGraph, pSet);

    return pSet;
}

static void
extract_major_version(const char *pszVersion, char *pszOut, size_t nOutLen)
{
    if (!pszVersion || !*pszVersion)
    {
        snprintf(pszOut, nOutLen, "0.0");
        return;
    }

    char szBuf[MAX_VERSION_LEN];
    snprintf(szBuf, sizeof(szBuf), "%s", pszVersion);

    char *pDot = strchr(szBuf, '.');
    if (pDot)
    {
        *pDot = '\0';
    }

    snprintf(pszOut, nOutLen, "%s.0", szBuf);
}

static int
has_spec_edge_for(DepGraph *pGraph, uint32_t dwFromIdx,
                  uint32_t dwToIdx, const char *pszTargetName)
{
    for (uint32_t i = 0; i < pGraph->dwEdgeCount; i++)
    {
        GraphEdge *pEdge = &pGraph->pEdges[i];

        if (pEdge->nSource != EDGE_SRC_SPEC)
        {
            continue;
        }
        if (pEdge->dwFromIdx != dwFromIdx)
        {
            continue;
        }

        if (pEdge->dwToIdx == dwToIdx)
        {
            return 1;
        }

        if (pszTargetName && pszTargetName[0] &&
            pEdge->szTargetName[0] &&
            strcasecmp(pEdge->szTargetName, pszTargetName) == 0)
        {
            return 1;
        }
    }

    return 0;
}

static int
provider_has_provides_edge(DepGraph *pGraph, uint32_t dwProviderIdx,
                           const char *pszVirtualName)
{
    for (uint32_t i = 0; i < pGraph->dwEdgeCount; i++)
    {
        GraphEdge *pEdge = &pGraph->pEdges[i];

        if (pEdge->dwFromIdx != dwProviderIdx)
        {
            continue;
        }
        if (pEdge->nType != EDGE_PROVIDES)
        {
            continue;
        }
        if (pEdge->nSource != EDGE_SRC_SPEC)
        {
            continue;
        }
        if (strcasecmp(pEdge->szTargetName, pszVirtualName) == 0)
        {
            return 1;
        }
    }

    return 0;
}

static void
add_patch_to_set(SpecPatchSet *pSet, SpecPatch *pPatch)
{
    pPatch->pNext = pSet->pAdditions;
    pSet->pAdditions = pPatch;
    pSet->dwAdditionCount++;
}

uint32_t
conflict_detect(DepGraph *pGraph)
{
    uint32_t dwIssueCount = 0;

    if (!pGraph)
    {
        return 0;
    }

    /* 1. Missing dependency detection */
    for (uint32_t i = 0; i < pGraph->dwEdgeCount; i++)
    {
        GraphEdge *pEdge = &pGraph->pEdges[i];

        if (pEdge->nSource != EDGE_SRC_GOMOD &&
            pEdge->nSource != EDGE_SRC_PYPROJECT)
        {
            continue;
        }

        if (has_spec_edge_for(pGraph, pEdge->dwFromIdx,
                              pEdge->dwToIdx, pEdge->szTargetName))
        {
            continue;
        }

        GraphNode *pFromNode = &pGraph->pNodes[pEdge->dwFromIdx];

        const char *pszTargetName = pEdge->szTargetName;
        if (!pszTargetName[0] && pEdge->dwToIdx < pGraph->dwNodeCount)
        {
            pszTargetName = pGraph->pNodes[pEdge->dwToIdx].szName;
        }

        char szMajorVer[MAX_VERSION_LEN];
        extract_major_version(pEdge->szConstraintVer, szMajorVer,
                              sizeof(szMajorVer));

        SpecPatchSet *pSet = find_or_create_patchset(
            pGraph, pFromNode->szSpecPath, pFromNode->szName);
        if (!pSet)
        {
            continue;
        }

        SpecPatch *pPatch = calloc(1, sizeof(SpecPatch));
        if (!pPatch)
        {
            continue;
        }

        snprintf(pPatch->szPackage, sizeof(pPatch->szPackage),
                 "%s", pFromNode->szName);
        snprintf(pPatch->szDirective, sizeof(pPatch->szDirective),
                 "Requires");
        snprintf(pPatch->szValue, sizeof(pPatch->szValue),
                 "%s >= %s", pszTargetName, szMajorVer);
        pPatch->nSource = pEdge->nSource;
        snprintf(pPatch->szEvidence, sizeof(pPatch->szEvidence),
                 "%s", pEdge->szEvidence);
        pPatch->nSeverity = SEVERITY_CRITICAL;

        add_patch_to_set(pSet, pPatch);
        dwIssueCount++;
    }

    /* 2. Missing virtual provides detection */
    for (uint32_t i = 0; i < pGraph->dwVirtualCount; i++)
    {
        VirtualProvide *pVirt = &pGraph->pVirtuals[i];

        if (pVirt->dwProviderIdx >= pGraph->dwNodeCount)
        {
            continue;
        }

        if (provider_has_provides_edge(pGraph, pVirt->dwProviderIdx,
                                       pVirt->szName))
        {
            continue;
        }

        GraphNode *pProvider = &pGraph->pNodes[pVirt->dwProviderIdx];

        SpecPatchSet *pSet = find_or_create_patchset(
            pGraph, pProvider->szSpecPath, pProvider->szName);
        if (!pSet)
        {
            continue;
        }

        SpecPatch *pPatch = calloc(1, sizeof(SpecPatch));
        if (!pPatch)
        {
            continue;
        }

        snprintf(pPatch->szPackage, sizeof(pPatch->szPackage),
                 "%s", pProvider->szName);
        snprintf(pPatch->szDirective, sizeof(pPatch->szDirective),
                 "Provides");
        snprintf(pPatch->szValue, sizeof(pPatch->szValue),
                 "%s = %s", pVirt->szName, pVirt->szVersion);
        pPatch->nSource = pVirt->nSource;
        snprintf(pPatch->szEvidence, sizeof(pPatch->szEvidence),
                 "%s", pVirt->szEvidence);
        pPatch->nSeverity = SEVERITY_IMPORTANT;

        add_patch_to_set(pSet, pPatch);
        dwIssueCount++;
    }

    /* 3. API version conflict detection */
    for (uint32_t i = 0; i < pGraph->dwVirtualCount; i++)
    {
        VirtualProvide *pVirt = &pGraph->pVirtuals[i];

        if (!strcasestr(pVirt->szName, "api"))
        {
            continue;
        }

        if (pVirt->dwProviderIdx >= pGraph->dwNodeCount)
        {
            continue;
        }

        GraphNode *pProvider = &pGraph->pNodes[pVirt->dwProviderIdx];

        for (uint32_t j = 0; j < pGraph->dwEdgeCount; j++)
        {
            GraphEdge *pEdge = &pGraph->pEdges[j];

            if (strcasecmp(pEdge->szTargetName, pVirt->szName) != 0)
            {
                continue;
            }

            if (pEdge->dwFromIdx >= pGraph->dwNodeCount)
            {
                continue;
            }

            GraphNode *pConsumer = &pGraph->pNodes[pEdge->dwFromIdx];

            ConflictRecord *pRec = calloc(1, sizeof(ConflictRecord));
            if (!pRec)
            {
                continue;
            }

            snprintf(pRec->szType, sizeof(pRec->szType),
                     "%s", pVirt->szName);
            snprintf(pRec->szConsumer, sizeof(pRec->szConsumer),
                     "%s", pConsumer->szName);
            snprintf(pRec->szConsumerVer, sizeof(pRec->szConsumerVer),
                     "%s", pConsumer->szVersion);
            snprintf(pRec->szProvider, sizeof(pRec->szProvider),
                     "%s", pProvider->szName);
            snprintf(pRec->szProviderVer, sizeof(pRec->szProviderVer),
                     "%s", pProvider->szVersion);
            snprintf(pRec->szRequiredApi, sizeof(pRec->szRequiredApi),
                     "%s", pEdge->szConstraintVer);
            snprintf(pRec->szProvidedRange, sizeof(pRec->szProvidedRange),
                     "%s", pVirt->szVersion);

            if (pEdge->nConstraintOp != CONSTRAINT_NONE &&
                pEdge->szConstraintVer[0] &&
                !version_satisfies(pVirt->szVersion,
                                   pEdge->nConstraintOp,
                                   pEdge->szConstraintVer))
            {
                snprintf(pRec->szStatus, sizeof(pRec->szStatus), "BROKEN");
                dwIssueCount++;
            }
            else
            {
                snprintf(pRec->szStatus, sizeof(pRec->szStatus), "ok");
            }

            graph_add_conflict(pGraph, pRec);
        }
    }

    return dwIssueCount;
}
