#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>

#include "graph.h"

int
graph_init(DepGraph *pGraph, const char *pszBranch)
{
    if (!pGraph)
    {
        return -1;
    }

    memset(pGraph, 0, sizeof(*pGraph));

    pGraph->pNodes = calloc(INITIAL_NODE_CAP, sizeof(GraphNode));
    if (!pGraph->pNodes)
    {
        return -1;
    }
    pGraph->dwNodeCap = INITIAL_NODE_CAP;

    pGraph->pEdges = calloc(INITIAL_EDGE_CAP, sizeof(GraphEdge));
    if (!pGraph->pEdges)
    {
        free(pGraph->pNodes);
        pGraph->pNodes = NULL;
        return -1;
    }
    pGraph->dwEdgeCap = INITIAL_EDGE_CAP;

    pGraph->pVirtuals = calloc(INITIAL_NODE_CAP, sizeof(VirtualProvide));
    if (!pGraph->pVirtuals)
    {
        free(pGraph->pEdges);
        free(pGraph->pNodes);
        pGraph->pNodes = NULL;
        pGraph->pEdges = NULL;
        return -1;
    }
    pGraph->dwVirtualCap = INITIAL_NODE_CAP;

    if (pszBranch)
    {
        snprintf(pGraph->szBranch, sizeof(pGraph->szBranch), "%s", pszBranch);
    }

    return 0;
}

void
graph_free(DepGraph *pGraph)
{
    if (!pGraph)
    {
        return;
    }

    free(pGraph->pNodes);
    free(pGraph->pEdges);
    free(pGraph->pVirtuals);

    /* Free conflict linked list */
    ConflictRecord *pConf = pGraph->pConflicts;
    while (pConf)
    {
        ConflictRecord *pNext = pConf->pNext;
        free(pConf);
        pConf = pNext;
    }

    /* Free patchset linked list and each set's addition list */
    SpecPatchSet *pSet = pGraph->pPatchSets;
    while (pSet)
    {
        SpecPatch *pPatch = pSet->pAdditions;
        while (pPatch)
        {
            SpecPatch *pPatchNext = pPatch->pNext;
            free(pPatch);
            pPatch = pPatchNext;
        }
        SpecPatchSet *pSetNext = pSet->pNext;
        free(pSet);
        pSet = pSetNext;
    }

    memset(pGraph, 0, sizeof(*pGraph));
}

uint32_t
graph_add_node(DepGraph *pGraph, const char *pszName,
               const char *pszVersion, const char *pszRelease,
               const char *pszEpoch, const char *pszSpecPath,
               const char *pszParent)
{
    if (!pGraph || !pszName)
    {
        return (uint32_t)-1;
    }

    if (pGraph->dwNodeCount >= pGraph->dwNodeCap)
    {
        uint32_t dwNewCap = pGraph->dwNodeCap * 2;
        if (dwNewCap < pGraph->dwNodeCap || /* overflow check */
            (size_t)dwNewCap * sizeof(GraphNode) / sizeof(GraphNode) != dwNewCap)
        {
            return (uint32_t)-1;
        }
        GraphNode *pNew = realloc(pGraph->pNodes,
                                  dwNewCap * sizeof(GraphNode));
        if (!pNew)
        {
            return (uint32_t)-1;
        }
        pGraph->pNodes = pNew;
        pGraph->dwNodeCap = dwNewCap;
    }

    uint32_t dwIdx = pGraph->dwNodeCount;
    GraphNode *pNode = &pGraph->pNodes[dwIdx];
    memset(pNode, 0, sizeof(*pNode));

    pNode->dwId = dwIdx;
    snprintf(pNode->szName, sizeof(pNode->szName), "%s", pszName);

    if (pszVersion)
    {
        snprintf(pNode->szVersion, sizeof(pNode->szVersion), "%s", pszVersion);
    }
    if (pszRelease)
    {
        snprintf(pNode->szRelease, sizeof(pNode->szRelease), "%s", pszRelease);
    }
    if (pszEpoch)
    {
        snprintf(pNode->szEpoch, sizeof(pNode->szEpoch), "%s", pszEpoch);
    }
    if (pszSpecPath)
    {
        snprintf(pNode->szSpecPath, sizeof(pNode->szSpecPath), "%s", pszSpecPath);
    }
    if (pszParent)
    {
        snprintf(pNode->szParentPackage, sizeof(pNode->szParentPackage),
                 "%s", pszParent);
        pNode->bIsSubpackage = (pszParent[0] != '\0') ? 1 : 0;
    }

    pGraph->dwNodeCount++;
    return dwIdx;
}

int
graph_add_edge(DepGraph *pGraph, uint32_t dwFrom, uint32_t dwTo,
               EdgeType nType, EdgeSource nSource,
               ConstraintOp nOp, const char *pszConstraintVer,
               const char *pszEvidence, const char *pszTargetName)
{
    if (!pGraph)
    {
        return -1;
    }

    if (pGraph->dwEdgeCount >= pGraph->dwEdgeCap)
    {
        uint32_t dwNewCap = pGraph->dwEdgeCap * 2;
        if (dwNewCap < pGraph->dwEdgeCap)
        {
            return -1;
        }
        GraphEdge *pNew = realloc(pGraph->pEdges,
                                  dwNewCap * sizeof(GraphEdge));
        if (!pNew)
        {
            return -1;
        }
        pGraph->pEdges = pNew;
        pGraph->dwEdgeCap = dwNewCap;
    }

    GraphEdge *pEdge = &pGraph->pEdges[pGraph->dwEdgeCount];
    memset(pEdge, 0, sizeof(*pEdge));

    pEdge->dwFromIdx = dwFrom;
    pEdge->dwToIdx = dwTo;
    pEdge->nType = nType;
    pEdge->nSource = nSource;
    pEdge->nConstraintOp = nOp;

    if (pszConstraintVer)
    {
        snprintf(pEdge->szConstraintVer, sizeof(pEdge->szConstraintVer),
                 "%s", pszConstraintVer);
    }
    if (pszEvidence)
    {
        snprintf(pEdge->szEvidence, sizeof(pEdge->szEvidence),
                 "%s", pszEvidence);
    }
    if (pszTargetName)
    {
        snprintf(pEdge->szTargetName, sizeof(pEdge->szTargetName),
                 "%s", pszTargetName);
    }

    pGraph->dwEdgeCount++;
    return 0;
}

int
graph_add_virtual(DepGraph *pGraph, const char *pszName,
                  const char *pszVersion, uint32_t dwProviderIdx,
                  EdgeSource nSource, const char *pszEvidence)
{
    if (!pGraph || !pszName)
    {
        return -1;
    }

    if (pGraph->dwVirtualCount >= pGraph->dwVirtualCap)
    {
        uint32_t dwNewCap = pGraph->dwVirtualCap * 2;
        if (dwNewCap < pGraph->dwVirtualCap)
        {
            return -1;
        }
        VirtualProvide *pNew = realloc(pGraph->pVirtuals,
                                       dwNewCap * sizeof(VirtualProvide));
        if (!pNew)
        {
            return -1;
        }
        pGraph->pVirtuals = pNew;
        pGraph->dwVirtualCap = dwNewCap;
    }

    VirtualProvide *pVirt = &pGraph->pVirtuals[pGraph->dwVirtualCount];
    memset(pVirt, 0, sizeof(*pVirt));

    snprintf(pVirt->szName, sizeof(pVirt->szName), "%s", pszName);
    if (pszVersion)
    {
        snprintf(pVirt->szVersion, sizeof(pVirt->szVersion),
                 "%s", pszVersion);
    }
    pVirt->dwProviderIdx = dwProviderIdx;
    pVirt->nSource = nSource;
    if (pszEvidence)
    {
        snprintf(pVirt->szEvidence, sizeof(pVirt->szEvidence),
                 "%s", pszEvidence);
    }

    pGraph->dwVirtualCount++;
    return 0;
}

int32_t
graph_find_node(DepGraph *pGraph, const char *pszName)
{
    if (!pGraph || !pszName)
    {
        return -1;
    }

    for (uint32_t i = 0; i < pGraph->dwNodeCount; i++)
    {
        if (strcasecmp(pGraph->pNodes[i].szName, pszName) == 0)
        {
            return (int32_t)i;
        }
    }

    return -1;
}

void
graph_add_conflict(DepGraph *pGraph, ConflictRecord *pRec)
{
    if (!pGraph || !pRec)
    {
        return;
    }

    pRec->pNext = pGraph->pConflicts;
    pGraph->pConflicts = pRec;
}

void
graph_add_patchset(DepGraph *pGraph, SpecPatchSet *pSet)
{
    if (!pGraph || !pSet)
    {
        return;
    }

    pSet->pNext = pGraph->pPatchSets;
    pGraph->pPatchSets = pSet;
}

const char *
edge_type_str(EdgeType t)
{
    switch (t)
    {
        case EDGE_REQUIRES:      return "Requires";
        case EDGE_BUILDREQUIRES: return "BuildRequires";
        case EDGE_PROVIDES:      return "Provides";
        case EDGE_CONFLICTS:     return "Conflicts";
        case EDGE_OBSOLETES:     return "Obsoletes";
        case EDGE_RECOMMENDS:    return "Recommends";
        case EDGE_SUGGESTS:      return "Suggests";
        case EDGE_SUPPLEMENTS:   return "Supplements";
        default:                 return "Unknown";
    }
}

const char *
edge_source_str(EdgeSource s)
{
    switch (s)
    {
        case EDGE_SRC_SPEC:         return "spec";
        case EDGE_SRC_GOMOD:        return "go.mod";
        case EDGE_SRC_PYPROJECT:    return "pyproject";
        case EDGE_SRC_API_CONSTANT: return "api-constant";
        default:                    return "unknown";
    }
}

const char *
severity_str(PatchSeverity s)
{
    switch (s)
    {
        case SEVERITY_CRITICAL:      return "critical";
        case SEVERITY_IMPORTANT:     return "important";
        case SEVERITY_INFORMATIONAL: return "informational";
        default:                     return "unknown";
    }
}

ConstraintOp
parse_constraint_op(const char *pszOp)
{
    if (!pszOp || !*pszOp)
    {
        return CONSTRAINT_NONE;
    }

    if (strcmp(pszOp, ">=") == 0) return CONSTRAINT_GE;
    if (strcmp(pszOp, ">")  == 0) return CONSTRAINT_GT;
    if (strcmp(pszOp, "<=") == 0) return CONSTRAINT_LE;
    if (strcmp(pszOp, "<")  == 0) return CONSTRAINT_LT;
    if (strcmp(pszOp, "=")  == 0) return CONSTRAINT_EQ;

    return CONSTRAINT_NONE;
}
