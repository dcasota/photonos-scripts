#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <json-c/json.h>

#include "manifest_writer.h"

int
manifest_write(const DepGraph *pGraph, const char *pszOutputDir,
               uint32_t dwSpecsScanned, uint32_t dwSpecsPatched)
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
    uint32_t dwCritical = 0;
    uint32_t dwImportant = 0;
    uint32_t dwInformational = 0;

    if (!pGraph || !pszOutputDir)
    {
        return -1;
    }

    tNow = time(NULL);
    pTm = localtime(&tNow);
    strftime(szTimestamp, sizeof(szTimestamp), "%Y%m%d_%H%M%S", pTm);

    snprintf(szFilePath, sizeof(szFilePath),
             "%s/depfix-manifest-%s-%s.json",
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
    json_object_object_add(pObj, "specs_scanned",
                           json_object_new_int((int32_t)dwSpecsScanned));
    json_object_object_add(pObj, "specs_patched",
                           json_object_new_int((int32_t)dwSpecsPatched));
    json_object_object_add(pRoot, "metadata", pObj);

    /* patched_specs */
    pObj = json_object_new_array();
    {
        const SpecPatchSet *pSet = pGraph->pPatchSets;
        while (pSet)
        {
            struct json_object *pSetObj = json_object_new_object();

            json_object_object_add(pSetObj, "package",
                                   json_object_new_string(
                                       pSet->szPackageName));
            json_object_object_add(pSetObj, "original_spec",
                                   json_object_new_string(pSet->szSpecPath));
            json_object_object_add(pSetObj, "patched_spec",
                                   json_object_new_string(
                                       pSet->szPatchedPath));

            struct json_object *pAdds = json_object_new_array();
            const SpecPatch *pPatch = pSet->pAdditions;
            while (pPatch)
            {
                struct json_object *pAddObj = json_object_new_object();

                json_object_object_add(pAddObj, "type",
                                       json_object_new_string(
                                           pPatch->szDirective));
                json_object_object_add(pAddObj, "section",
                                       json_object_new_string(
                                           pPatch->szSection));
                json_object_object_add(pAddObj, "value",
                                       json_object_new_string(
                                           pPatch->szValue));
                json_object_object_add(pAddObj, "source",
                                       json_object_new_string(
                                           edge_source_str(pPatch->nSource)));
                json_object_object_add(pAddObj, "evidence",
                                       json_object_new_string(
                                           pPatch->szEvidence));
                json_object_object_add(pAddObj, "severity",
                                       json_object_new_string(
                                           severity_str(pPatch->nSeverity)));

                switch (pPatch->nSeverity)
                {
                    case SEVERITY_CRITICAL:      dwCritical++;      break;
                    case SEVERITY_IMPORTANT:     dwImportant++;     break;
                    case SEVERITY_INFORMATIONAL: dwInformational++; break;
                }

                json_object_array_add(pAdds, pAddObj);
                pPatch = pPatch->pNext;
            }

            json_object_object_add(pSetObj, "additions", pAdds);
            json_object_array_add(pObj, pSetObj);
            pSet = pSet->pNext;
        }
    }
    json_object_object_add(pRoot, "patched_specs", pObj);

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

    /* severity_summary */
    pObj = json_object_new_object();
    json_object_object_add(pObj, "critical",
                           json_object_new_int((int32_t)dwCritical));
    json_object_object_add(pObj, "important",
                           json_object_new_int((int32_t)dwImportant));
    json_object_object_add(pObj, "informational",
                           json_object_new_int((int32_t)dwInformational));
    json_object_object_add(pRoot, "severity_summary", pObj);

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

    fprintf(stdout, "Wrote depfix manifest: %s\n", szFilePath);
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
