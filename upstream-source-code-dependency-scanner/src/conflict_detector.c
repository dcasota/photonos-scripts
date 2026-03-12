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

/* Parse "target op version" from a patch value string.
   E.g. "docker >= 28.0" -> target="docker", op=">=", ver="28.0"
   Returns 0 on success, -1 if not parseable. */
static int
parse_patch_value(const char *pszValue, char *pszTarget, size_t nTargetLen,
                  char *pszOp, size_t nOpLen,
                  char *pszVer, size_t nVerLen)
{
    char szBuf[MAX_NAME_LEN];
    snprintf(szBuf, sizeof(szBuf), "%s", pszValue);

    char *pSpace = strchr(szBuf, ' ');
    if (!pSpace)
        return -1;

    *pSpace = '\0';
    snprintf(pszTarget, nTargetLen, "%s", szBuf);

    char *pOp = pSpace + 1;
    while (*pOp == ' ') pOp++;
    if (!*pOp)
        return -1;

    char *pVer = pOp;
    while (*pVer && *pVer != ' ') pVer++;
    if (*pVer)
    {
        char szOp[8];
        size_t nLen = (size_t)(pVer - pOp);
        if (nLen >= sizeof(szOp)) nLen = sizeof(szOp) - 1;
        memcpy(szOp, pOp, nLen);
        szOp[nLen] = '\0';
        snprintf(pszOp, nOpLen, "%s", szOp);

        pVer++;
        while (*pVer == ' ') pVer++;
        snprintf(pszVer, nVerLen, "%s", pVer);
    }
    else
    {
        return -1;
    }

    return 0;
}

/* Global deduplication with version-strength consolidation.
   - Exact (directive, value) duplicates are suppressed.
   - For "Requires: X >= A" and "Requires: X >= B", keep only the higher.
   - For "Conflicts: X < A" and "Conflicts: X < B", keep only the higher.
   Returns 1 if patch was added (or replaced), 0 if suppressed. */
static int
add_patch_to_set(SpecPatchSet *pSet, SpecPatch *pPatch)
{
    char szNewTarget[MAX_NAME_LEN], szNewOp[8], szNewVer[MAX_VERSION_LEN];
    int bNewParsed = parse_patch_value(pPatch->szValue, szNewTarget,
                        sizeof(szNewTarget), szNewOp, sizeof(szNewOp),
                        szNewVer, sizeof(szNewVer));

    for (SpecPatch *p = pSet->pAdditions; p; p = p->pNext)
    {
        if (strcmp(p->szDirective, pPatch->szDirective) != 0)
            continue;

        /* Exact duplicate */
        if (strcmp(p->szValue, pPatch->szValue) == 0)
        {
            free(pPatch);
            return 0;
        }

        /* Version-strength consolidation */
        if (bNewParsed != 0)
            continue;

        char szOldTarget[MAX_NAME_LEN], szOldOp[8], szOldVer[MAX_VERSION_LEN];
        if (parse_patch_value(p->szValue, szOldTarget, sizeof(szOldTarget),
                              szOldOp, sizeof(szOldOp),
                              szOldVer, sizeof(szOldVer)) != 0)
            continue;

        if (strcmp(szNewTarget, szOldTarget) != 0)
            continue;
        if (strcmp(szNewOp, szOldOp) != 0)
            continue;

        /* Same directive, same target, same operator -- keep strongest.
           For >= : higher version wins (stronger requirement).
           For < : higher version wins (less restrictive, subsumes lower).
           For > : lower version wins (more restrictive upper bound). */
        int nCmp = version_compare(szNewVer, szOldVer);

        if (strcmp(szNewOp, ">=") == 0 || strcmp(szNewOp, "<") == 0)
        {
            if (nCmp > 0)
            {
                /* New is stronger/subsumes old -- replace */
                snprintf(p->szValue, sizeof(p->szValue),
                         "%s", pPatch->szValue);
                snprintf(p->szEvidence, sizeof(p->szEvidence),
                         "%s", pPatch->szEvidence);
                p->nSource = pPatch->nSource;
                free(pPatch);
                return 0;
            }
            else
            {
                /* Old is stronger -- suppress new */
                free(pPatch);
                return 0;
            }
        }
        else if (strcmp(szNewOp, ">") == 0)
        {
            if (nCmp < 0)
            {
                /* New is more restrictive -- replace */
                snprintf(p->szValue, sizeof(p->szValue),
                         "%s", pPatch->szValue);
                snprintf(p->szEvidence, sizeof(p->szEvidence),
                         "%s", pPatch->szEvidence);
                p->nSource = pPatch->nSource;
                free(pPatch);
                return 0;
            }
            else
            {
                free(pPatch);
                return 0;
            }
        }
    }

    pPatch->pNext = pSet->pAdditions;
    pSet->pAdditions = pPatch;
    pSet->dwAdditionCount++;
    return 1;
}

/* Find the Docker SDK version string from a gomod edge's evidence field */
static int
extract_docker_sdk_version(const GraphEdge *pEdge, char *pszSdkVer, size_t nLen)
{
    const char *pSdk = strstr(pEdge->szEvidence, "github.com/docker/docker ");
    if (!pSdk) pSdk = strstr(pEdge->szEvidence, "github.com/moby/moby ");
    if (!pSdk) pSdk = strstr(pEdge->szEvidence, "github.com/docker/cli ");
    if (!pSdk)
        return -1;

    pSdk = strchr(pSdk, ' ');
    if (!pSdk)
        return -1;
    pSdk++;

    snprintf(pszSdkVer, nLen, "%s", pSdk);

    /* Strip +incompatible */
    char *pInc = strstr(pszSdkVer, "+");
    if (pInc) *pInc = '\0';

    /* Strip trailing whitespace */
    char *pEnd = pszSdkVer + strlen(pszSdkVer) - 1;
    while (pEnd > pszSdkVer && (*pEnd == ' ' || *pEnd == '\n' || *pEnd == '\r'))
        *pEnd-- = '\0';

    return 0;
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
            pEdge->nSource != EDGE_SRC_PYPROJECT &&
            pEdge->nSource != EDGE_SRC_TARBALL)
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

        const char *pszConstraintVer = pEdge->szConstraintVer;
        if (!pszConstraintVer[0])
            pszConstraintVer = "0.0";

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
                 "%s >= %s", pszTargetName, pszConstraintVer);
        pPatch->nSource = pEdge->nSource;
        snprintf(pPatch->szEvidence, sizeof(pPatch->szEvidence),
                 "%s", pEdge->szEvidence);
        pPatch->nSeverity = SEVERITY_CRITICAL;

        dwIssueCount += add_patch_to_set(pSet, pPatch);
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

        dwIssueCount += add_patch_to_set(pSet, pPatch);
    }

    /* 3. API version conflict detection + Conflicts: patch generation.
       For each gomod edge targeting "docker", resolve the Docker SDK version
       to a REST API version, then compare against the engine's min/max API.
       Global dedup in add_patch_to_set() handles duplicate suppression. */
    for (uint32_t i = 0; i < pGraph->dwEdgeCount; i++)
    {
        GraphEdge *pEdge = &pGraph->pEdges[i];

        if (pEdge->nSource != EDGE_SRC_GOMOD &&
            pEdge->nSource != EDGE_SRC_TARBALL)
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

        char szSdkVer[MAX_VERSION_LEN];
        if (extract_docker_sdk_version(pEdge, szSdkVer, sizeof(szSdkVer)) != 0)
        {
            continue;
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

        /* Generate lower-bound Conflicts: patch on the consumer spec.
           The consumer needs an engine >= the version that first provides
           the required API level. */
        const char *pszMinEngine = NULL;
        if (pSdkMap)
        {
            pszMinEngine = docker_api_to_min_engine(pSdkMap, pszClientApi);
        }

        if (pszMinEngine)
        {
            char szConflictVal[MAX_NAME_LEN];
            snprintf(szConflictVal, sizeof(szConflictVal), "%s < %s",
                     pszEngineSubpkg, pszMinEngine);

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
                    pPatch->nSource = pEdge->nSource;
                    snprintf(pPatch->szEvidence, sizeof(pPatch->szEvidence),
                             "go.mod docker SDK %s -> API %s, "
                             "requires engine >= %s",
                             szSdkVer, pszClientApi, pszMinEngine);
                    pPatch->nSeverity = SEVERITY_CRITICAL;
                    dwIssueCount += add_patch_to_set(pSet, pPatch);
                }
            }
        }

        /* Upper-bound Conflicts: if the client API exceeds what the current
           engine can provide (max API), generate Conflicts: > engine_ver.
           This is a cross-version constellation check -- the latest version
           requires an API newer than what the current engine supports. */
        if (pszServerMaxApi &&
            version_compare(pszClientApi, pszServerMaxApi) > 0)
        {
            /* The consumer requires API pszClientApi which exceeds the
               engine's max API. Find the engine version that first requires
               an API higher than what this consumer can handle. */
            const char *pszMaxEngine = docker_api_to_min_engine(
                pSdkMap, pszServerMaxApi);
            if (pszMaxEngine)
            {
                char szUpperVal[MAX_NAME_LEN];
                snprintf(szUpperVal, sizeof(szUpperVal), "%s > %s",
                         pszEngineSubpkg, pszMaxEngine);

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
                                 "%s", szUpperVal);
                        pPatch->nSource = pEdge->nSource;
                        snprintf(pPatch->szEvidence,
                                 sizeof(pPatch->szEvidence),
                                 "client requires API %s but engine max API "
                                 "is %s (engine %s provides up to %s)",
                                 pszClientApi, pszServerMaxApi,
                                 pszMaxEngine, pszServerMaxApi);
                        pPatch->nSeverity = SEVERITY_CRITICAL;
                        dwIssueCount += add_patch_to_set(pSet, pPatch);
                    }
                }
            }
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
                        pPatch->nSource = pEdge->nSource;
                        snprintf(pPatch->szEvidence,
                                 sizeof(pPatch->szEvidence),
                                 "client API %s < engine minAPI %s "
                                 "(engine %s+ requires API >= %s)",
                                 pszClientApi, pszServerMinApi,
                                 pszBreakEngine, pszServerMinApi);
                        pPatch->nSeverity = SEVERITY_CRITICAL;
                        dwIssueCount += add_patch_to_set(pSet, pPatch);
                    }
                }
            }
        }
    }

    return dwIssueCount;
}
