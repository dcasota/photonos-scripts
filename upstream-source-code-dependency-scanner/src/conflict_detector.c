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
conflict_detect(DepGraph *pGraph, const DockerSdkApiMap *pSdkMap)
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

    /* 3. API version conflict detection + Conflicts: patch generation.
       For each gomod edge targeting "docker", resolve the Docker SDK version
       to a REST API version, then compare against the engine's min/max API.
       Track emitted (consumer, conflict_value) to avoid duplicates when
       go.mod lists both docker/docker and docker/cli at the same major. */
    #define MAX_DEDUP 512
    struct { uint32_t dwFromIdx; char szValue[MAX_VERSION_LEN]; } dedup[MAX_DEDUP];
    uint32_t dwDedupCount = 0;

    for (uint32_t i = 0; i < pGraph->dwEdgeCount; i++)
    {
        GraphEdge *pEdge = &pGraph->pEdges[i];

        if (pEdge->nSource != EDGE_SRC_GOMOD)
        {
            continue;
        }
        if (pEdge->dwFromIdx >= pGraph->dwNodeCount ||
            pEdge->dwToIdx >= pGraph->dwNodeCount)
        {
            continue;
        }

        /* Only process edges targeting the docker package */
        const char *pszTarget = pEdge->szTargetName;
        if (!pszTarget[0])
        {
            pszTarget = pGraph->pNodes[pEdge->dwToIdx].szName;
        }
        if (strcasecmp(pszTarget, "docker") != 0)
        {
            continue;
        }

        /* Extract the SDK version from evidence: "go.mod: github.com/docker/docker vX.Y.Z" */
        const char *pSdk = strstr(pEdge->szEvidence, "github.com/docker/docker ");
        if (!pSdk) pSdk = strstr(pEdge->szEvidence, "github.com/moby/moby ");
        if (!pSdk) pSdk = strstr(pEdge->szEvidence, "github.com/docker/cli ");
        if (!pSdk)
        {
            continue;
        }
        /* Advance past the module name to the version */
        pSdk = strchr(pSdk, ' ');
        if (!pSdk)
        {
            continue;
        }
        pSdk++;
        char szSdkVer[MAX_VERSION_LEN];
        snprintf(szSdkVer, sizeof(szSdkVer), "%s", pSdk);
        /* Strip +incompatible */
        char *pInc = strstr(szSdkVer, "+");
        if (pInc) *pInc = '\0';
        /* Strip trailing whitespace */
        char *pEnd = szSdkVer + strlen(szSdkVer) - 1;
        while (pEnd > szSdkVer && (*pEnd == ' ' || *pEnd == '\n' || *pEnd == '\r'))
        {
            *pEnd-- = '\0';
        }

        /* Map SDK version to API version */
        const char *pszClientApi = NULL;
        if (pSdkMap)
        {
            pszClientApi = docker_sdk_to_api_version(pSdkMap, szSdkVer);
        }
        if (!pszClientApi)
        {
            continue;
        }

        GraphNode *pConsumer = &pGraph->pNodes[pEdge->dwFromIdx];

        /* Find docker-api-min virtual provide (engine's defaultMinAPIVersion) */
        const char *pszServerMinApi = NULL;
        const char *pszServerMaxApi = NULL;
        uint32_t dwEngineNodeIdx = UINT32_MAX;
        for (uint32_t v = 0; v < pGraph->dwVirtualCount; v++)
        {
            if (strcasecmp(pGraph->pVirtuals[v].szName, "docker-api-min") == 0)
            {
                pszServerMinApi = pGraph->pVirtuals[v].szVersion;
                dwEngineNodeIdx = pGraph->pVirtuals[v].dwProviderIdx;
            }
            if (strcasecmp(pGraph->pVirtuals[v].szName, "docker-api") == 0)
            {
                pszServerMaxApi = pGraph->pVirtuals[v].szVersion;
                if (dwEngineNodeIdx == UINT32_MAX)
                {
                    dwEngineNodeIdx = pGraph->pVirtuals[v].dwProviderIdx;
                }
            }
        }

        if (!pszServerMinApi && !pszServerMaxApi)
        {
            continue;
        }

        const char *pszEngineSubpkg = "docker-engine";
        int32_t nEngineIdx = graph_find_node(pGraph, pszEngineSubpkg);
        if (nEngineIdx < 0)
        {
            pszEngineSubpkg = "docker";
            nEngineIdx = graph_find_node(pGraph, pszEngineSubpkg);
        }

        /* Create conflict record */
        ConflictRecord *pRec = calloc(1, sizeof(ConflictRecord));
        if (!pRec) continue;

        snprintf(pRec->szType, sizeof(pRec->szType), "docker-api");
        snprintf(pRec->szConsumer, sizeof(pRec->szConsumer),
                 "%s", pConsumer->szName);
        snprintf(pRec->szConsumerVer, sizeof(pRec->szConsumerVer),
                 "%s", pConsumer->szVersion);
        snprintf(pRec->szProvider, sizeof(pRec->szProvider),
                 "%s", pszEngineSubpkg);
        snprintf(pRec->szProviderVer, sizeof(pRec->szProviderVer),
                 "%s", nEngineIdx >= 0
                     ? pGraph->pNodes[nEngineIdx].szVersion : "");
        snprintf(pRec->szRequiredApi, sizeof(pRec->szRequiredApi),
                 "%s (from SDK %s)", pszClientApi, szSdkVer);
        snprintf(pRec->szProvidedRange, sizeof(pRec->szProvidedRange),
                 "%s..%s",
                 pszServerMinApi ? pszServerMinApi : "?",
                 pszServerMaxApi ? pszServerMaxApi : "?");

        int bBroken = 0;
        if (pszServerMinApi &&
            version_compare(pszClientApi, pszServerMinApi) < 0)
        {
            bBroken = 1;
        }

        if (bBroken)
        {
            snprintf(pRec->szStatus, sizeof(pRec->szStatus), "BROKEN");
            snprintf(pRec->szNote, sizeof(pRec->szNote),
                     "client API %s < server minAPI %s",
                     pszClientApi, pszServerMinApi);
        }
        else
        {
            snprintf(pRec->szStatus, sizeof(pRec->szStatus), "ok");
            snprintf(pRec->szNote, sizeof(pRec->szNote),
                     "client API %s within [%s, %s]",
                     pszClientApi,
                     pszServerMinApi ? pszServerMinApi : "?",
                     pszServerMaxApi ? pszServerMaxApi : "?");
        }

        graph_add_conflict(pGraph, pRec);

        /* Generate Conflicts: patch on the consumer spec.
           The consumer needs an engine that supports its client API version.
           Find the minimum engine version that provides that API. */
        const char *pszMinEngine = NULL;
        if (pSdkMap)
        {
            pszMinEngine = docker_api_to_min_engine(pSdkMap, pszClientApi);
        }

        if (pszMinEngine)
        {
            /* Deduplicate: skip if same consumer already has this Conflicts value */
            char szConflictVal[MAX_VERSION_LEN];
            snprintf(szConflictVal, sizeof(szConflictVal), "%s < %s",
                     pszEngineSubpkg, pszMinEngine);
            int bDup = 0;
            for (uint32_t d = 0; d < dwDedupCount; d++)
            {
                if (dedup[d].dwFromIdx == pEdge->dwFromIdx &&
                    strcmp(dedup[d].szValue, szConflictVal) == 0)
                {
                    bDup = 1;
                    break;
                }
            }
            if (bDup)
                goto skip_conflict_patch;

            if (dwDedupCount < MAX_DEDUP)
            {
                dedup[dwDedupCount].dwFromIdx = pEdge->dwFromIdx;
                snprintf(dedup[dwDedupCount].szValue,
                         sizeof(dedup[dwDedupCount].szValue),
                         "%s", szConflictVal);
                dwDedupCount++;
            }

            SpecPatchSet *pSet = find_or_create_patchset(
                pGraph, pConsumer->szSpecPath, pConsumer->szName);
            if (pSet)
            {
                SpecPatch *pPatch = calloc(1, sizeof(SpecPatch));
                if (pPatch)
                {
                    snprintf(pPatch->szPackage, sizeof(pPatch->szPackage),
                             "%s", pConsumer->szName);
                    snprintf(pPatch->szDirective, sizeof(pPatch->szDirective),
                             "Conflicts");
                    snprintf(pPatch->szValue, sizeof(pPatch->szValue),
                             "%s", szConflictVal);
                    pPatch->nSource = EDGE_SRC_GOMOD;
                    snprintf(pPatch->szEvidence, sizeof(pPatch->szEvidence),
                             "go.mod docker SDK %s -> API %s, "
                             "requires engine >= %s",
                             szSdkVer, pszClientApi, pszMinEngine);
                    pPatch->nSeverity = SEVERITY_CRITICAL;
                    add_patch_to_set(pSet, pPatch);
                    dwIssueCount++;
                }
            }
            skip_conflict_patch: ;
        }

        /* If BROKEN, also add a Conflicts: for the upper bound */
        if (bBroken && pszServerMinApi)
        {
            const char *pszBreakEngine = docker_api_to_min_engine(
                pSdkMap, pszServerMinApi);
            if (pszBreakEngine)
            {
                SpecPatchSet *pSet = find_or_create_patchset(
                    pGraph, pConsumer->szSpecPath, pConsumer->szName);
                if (pSet)
                {
                    SpecPatch *pPatch = calloc(1, sizeof(SpecPatch));
                    if (pPatch)
                    {
                        snprintf(pPatch->szPackage, sizeof(pPatch->szPackage),
                                 "%s", pConsumer->szName);
                        snprintf(pPatch->szDirective,
                                 sizeof(pPatch->szDirective), "Conflicts");
                        snprintf(pPatch->szValue, sizeof(pPatch->szValue),
                                 "%s >= %s", pszEngineSubpkg, pszBreakEngine);
                        pPatch->nSource = EDGE_SRC_GOMOD;
                        snprintf(pPatch->szEvidence,
                                 sizeof(pPatch->szEvidence),
                                 "client API %s < engine minAPI %s "
                                 "(engine %s+ requires API >= %s)",
                                 pszClientApi, pszServerMinApi,
                                 pszBreakEngine, pszServerMinApi);
                        pPatch->nSeverity = SEVERITY_CRITICAL;
                        add_patch_to_set(pSet, pPatch);
                        dwIssueCount++;
                    }
                }
            }
        }
    }

    return dwIssueCount;
}
