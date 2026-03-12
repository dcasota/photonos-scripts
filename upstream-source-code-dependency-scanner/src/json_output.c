#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <json-c/json.h>

#include "json_output.h"

static const char *
_constraint_op_str(ConstraintOp op)
{
    switch (op)
    {
        case CONSTRAINT_EQ: return "=";
        case CONSTRAINT_GE: return ">=";
        case CONSTRAINT_GT: return ">";
        case CONSTRAINT_LE: return "<=";
        case CONSTRAINT_LT: return "<";
        default:            return "";
    }
}

int
json_output_write(const DepGraph *pGraph, const char *pszOutputDir)
{
    char szTimestamp[64];
    char szFilePath[MAX_PATH_LEN];
    time_t tNow;
    struct tm *pTm;
    struct json_object *pRoot = NULL;
    struct json_object *pObj = NULL;
    FILE *fp = NULL;
    const char *pszJson = NULL;
    int nResult = -1;
    uint32_t i;

    if (!pGraph || !pszOutputDir)
    {
        return -1;
    }

    tNow = time(NULL);
    pTm = localtime(&tNow);
    strftime(szTimestamp, sizeof(szTimestamp), "%Y%m%d_%H%M%S", pTm);

    snprintf(szFilePath, sizeof(szFilePath),
             "%s/dependency-graph-%s-deep-%s.json",
             pszOutputDir, pGraph->szBranch, szTimestamp);

    pRoot = json_object_new_object();
    if (!pRoot)
    {
        goto cleanup;
    }

    /* metadata */
    pObj = json_object_new_object();
    json_object_object_add(pObj, "generator",
                           json_object_new_string("upstream-dep-scanner"));
    json_object_object_add(pObj, "timestamp",
                           json_object_new_string(szTimestamp));
    json_object_object_add(pObj, "branch",
                           json_object_new_string(pGraph->szBranch));
    json_object_object_add(pRoot, "metadata", pObj);

    json_object_object_add(pRoot, "node_count",
                           json_object_new_int((int32_t)pGraph->dwNodeCount));
    json_object_object_add(pRoot, "edge_count",
                           json_object_new_int((int32_t)pGraph->dwEdgeCount));

    /* virtual_provides */
    pObj = json_object_new_array();
    for (i = 0; i < pGraph->dwVirtualCount; i++)
    {
        const VirtualProvide *pV = &pGraph->pVirtuals[i];
        struct json_object *pEntry = json_object_new_object();

        json_object_object_add(pEntry, "name",
                               json_object_new_string(pV->szName));
        json_object_object_add(pEntry, "version",
                               json_object_new_string(pV->szVersion));
        json_object_object_add(pEntry, "provider",
                               json_object_new_string(
                                   pV->dwProviderIdx < pGraph->dwNodeCount
                                       ? pGraph->pNodes[pV->dwProviderIdx].szName
                                       : "(unknown)"));
        json_object_object_add(pEntry, "provider_id",
                               json_object_new_int((int32_t)pV->dwProviderIdx));
        json_object_object_add(pEntry, "source",
                               json_object_new_string(
                                   edge_source_str(pV->nSource)));
        json_object_object_add(pEntry, "evidence",
                               json_object_new_string(pV->szEvidence));

        json_object_array_add(pObj, pEntry);
    }
    json_object_object_add(pRoot, "virtual_provides", pObj);

    /* nodes */
    pObj = json_object_new_array();
    for (i = 0; i < pGraph->dwNodeCount; i++)
    {
        const GraphNode *pN = &pGraph->pNodes[i];
        struct json_object *pEntry = json_object_new_object();

        json_object_object_add(pEntry, "id",
                               json_object_new_int((int32_t)pN->dwId));
        json_object_object_add(pEntry, "name",
                               json_object_new_string(pN->szName));
        json_object_object_add(pEntry, "version",
                               json_object_new_string(pN->szVersion));
        json_object_object_add(pEntry, "release",
                               json_object_new_string(pN->szRelease));
        json_object_object_add(pEntry, "epoch",
                               json_object_new_string(pN->szEpoch));
        json_object_object_add(pEntry, "spec_path",
                               json_object_new_string(pN->szSpecPath));
        json_object_object_add(pEntry, "is_subpackage",
                               json_object_new_boolean(pN->bIsSubpackage));
        json_object_object_add(pEntry, "parent",
                               json_object_new_string(pN->szParentPackage));

        json_object_array_add(pObj, pEntry);
    }
    json_object_object_add(pRoot, "nodes", pObj);

    /* edges */
    pObj = json_object_new_array();
    for (i = 0; i < pGraph->dwEdgeCount; i++)
    {
        const GraphEdge *pE = &pGraph->pEdges[i];
        struct json_object *pEntry = json_object_new_object();

        json_object_object_add(pEntry, "from",
                               json_object_new_int((int32_t)pE->dwFromIdx));
        json_object_object_add(pEntry, "to",
                               json_object_new_int((int32_t)pE->dwToIdx));
        json_object_object_add(pEntry, "from_name",
                               json_object_new_string(
                                   pE->dwFromIdx < pGraph->dwNodeCount
                                       ? pGraph->pNodes[pE->dwFromIdx].szName
                                       : "(unresolved)"));
        json_object_object_add(pEntry, "to_name",
                               json_object_new_string(
                                   pE->dwToIdx < pGraph->dwNodeCount
                                       ? pGraph->pNodes[pE->dwToIdx].szName
                                       : "(unresolved)"));
        json_object_object_add(pEntry, "type",
                               json_object_new_string(
                                   edge_type_str(pE->nType)));
        json_object_object_add(pEntry, "source",
                               json_object_new_string(
                                   edge_source_str(pE->nSource)));
        json_object_object_add(pEntry, "constraint_op",
                               json_object_new_string(
                                   _constraint_op_str(pE->nConstraintOp)));
        json_object_object_add(pEntry, "constraint_ver",
                               json_object_new_string(pE->szConstraintVer));
        json_object_object_add(pEntry, "evidence",
                               json_object_new_string(pE->szEvidence));
        json_object_object_add(pEntry, "target_name",
                               json_object_new_string(pE->szTargetName));

        json_object_array_add(pObj, pEntry);
    }
    json_object_object_add(pRoot, "edges", pObj);

    /* conflicts_detected */
    pObj = json_object_new_array();
    {
        const ConflictRecord *pC = pGraph->pConflicts;
        while (pC)
        {
            struct json_object *pEntry = json_object_new_object();

            json_object_object_add(pEntry, "type",
                                   json_object_new_string(pC->szType));
            json_object_object_add(pEntry, "consumer",
                                   json_object_new_string(pC->szConsumer));
            json_object_object_add(pEntry, "consumer_version",
                                   json_object_new_string(pC->szConsumerVer));
            json_object_object_add(pEntry, "provider",
                                   json_object_new_string(pC->szProvider));
            json_object_object_add(pEntry, "provider_version",
                                   json_object_new_string(pC->szProviderVer));
            json_object_object_add(pEntry, "required_api",
                                   json_object_new_string(pC->szRequiredApi));
            json_object_object_add(pEntry, "provided_range",
                                   json_object_new_string(
                                       pC->szProvidedRange));
            json_object_object_add(pEntry, "status",
                                   json_object_new_string(pC->szStatus));
            json_object_object_add(pEntry, "note",
                                   json_object_new_string(pC->szNote));

            json_object_array_add(pObj, pEntry);
            pC = pC->pNext;
        }
    }
    json_object_object_add(pRoot, "conflicts_detected", pObj);

    pszJson = json_object_to_json_string_ext(pRoot, JSON_C_TO_STRING_PRETTY);
    if (!pszJson)
    {
        goto cleanup;
    }

    fp = fopen(szFilePath, "w");
    if (!fp)
    {
        fprintf(stderr, "Error: cannot open %s for writing\n", szFilePath);
        goto cleanup;
    }

    fprintf(fp, "%s\n", pszJson);
    fclose(fp);
    fp = NULL;

    fprintf(stdout, "Wrote dependency graph JSON: %s\n", szFilePath);
    nResult = 0;

cleanup:
    if (fp)
    {
        fclose(fp);
    }
    if (pRoot)
    {
        json_object_put(pRoot);
    }
    return nResult;
}
