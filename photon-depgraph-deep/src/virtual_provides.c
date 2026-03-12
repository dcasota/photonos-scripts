#define _POSIX_C_SOURCE 200809L

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <stdint.h>

#include "virtual_provides.h"

#define MAX_COMPONENTS 32

static int
parse_component(const char *pszComp, long *plVal)
{
    char *pEnd = NULL;
    if (!pszComp || !*pszComp)
    {
        return 0;
    }
    *plVal = strtol(pszComp, &pEnd, 10);
    return (pEnd != pszComp && *pEnd == '\0') ? 1 : 0;
}

static int
split_version(const char *pszVer, char aComponents[][MAX_VERSION_LEN],
              int nMax)
{
    char szBuf[MAX_VERSION_LEN];
    int nCount = 0;

    if (!pszVer || !*pszVer)
    {
        return 0;
    }

    snprintf(szBuf, sizeof(szBuf), "%s", pszVer);

    char *pSave = NULL;
    char *pTok = strtok_r(szBuf, ".-", &pSave);
    while (pTok && nCount < nMax)
    {
        snprintf(aComponents[nCount], MAX_VERSION_LEN, "%s", pTok);
        nCount++;
        pTok = strtok_r(NULL, ".-", &pSave);
    }

    return nCount;
}

int
version_compare(const char *pszA, const char *pszB)
{
    const char *pA = pszA;
    const char *pB = pszB;

    if (!pA) pA = "";
    if (!pB) pB = "";

    /* Strip leading 'v' or 'V' */
    if (*pA == 'v' || *pA == 'V') pA++;
    if (*pB == 'v' || *pB == 'V') pB++;

    if (!*pA && !*pB) return 0;
    if (!*pA) return -1;
    if (!*pB) return 1;

    char aCompsA[MAX_COMPONENTS][MAX_VERSION_LEN];
    char aCompsB[MAX_COMPONENTS][MAX_VERSION_LEN];

    int nCountA = split_version(pA, aCompsA, MAX_COMPONENTS);
    int nCountB = split_version(pB, aCompsB, MAX_COMPONENTS);

    int nMax = (nCountA > nCountB) ? nCountA : nCountB;

    for (int i = 0; i < nMax; i++)
    {
        const char *pCompA = (i < nCountA) ? aCompsA[i] : "";
        const char *pCompB = (i < nCountB) ? aCompsB[i] : "";

        long lValA, lValB;
        int bNumA = parse_component(pCompA, &lValA);
        int bNumB = parse_component(pCompB, &lValB);

        int nResult;
        if (bNumA && bNumB)
        {
            if (lValA < lValB) nResult = -1;
            else if (lValA > lValB) nResult = 1;
            else nResult = 0;
        }
        else
        {
            nResult = strcmp(pCompA, pCompB);
        }

        if (nResult != 0)
        {
            return nResult;
        }
    }

    return 0;
}

int
version_satisfies(const char *pszVersion, ConstraintOp nOp,
                  const char *pszConstraint)
{
    if (nOp == CONSTRAINT_NONE)
    {
        return 1;
    }

    int nCmp = version_compare(pszVersion, pszConstraint);

    switch (nOp)
    {
        case CONSTRAINT_EQ:
            return (nCmp == 0) ? 1 : 0;
        case CONSTRAINT_GE:
            return (nCmp >= 0) ? 1 : 0;
        case CONSTRAINT_GT:
            return (nCmp > 0) ? 1 : 0;
        case CONSTRAINT_LE:
            return (nCmp <= 0) ? 1 : 0;
        case CONSTRAINT_LT:
            return (nCmp < 0) ? 1 : 0;
        default:
            return 0;
    }
}

uint32_t
virtual_resolve_edges(DepGraph *pGraph)
{
    uint32_t dwResolved = 0;

    if (!pGraph || !pGraph->pEdges || !pGraph->pVirtuals)
    {
        return 0;
    }

    for (uint32_t i = 0; i < pGraph->dwEdgeCount; i++)
    {
        GraphEdge *pEdge = &pGraph->pEdges[i];

        if (pEdge->dwToIdx != UINT32_MAX)
        {
            continue;
        }

        for (uint32_t j = 0; j < pGraph->dwVirtualCount; j++)
        {
            VirtualProvide *pVirt = &pGraph->pVirtuals[j];

            if (strcmp(pEdge->szTargetName, pVirt->szName) == 0)
            {
                pEdge->dwToIdx = pVirt->dwProviderIdx;
                dwResolved++;
                break;
            }
        }
    }

    return dwResolved;
}
