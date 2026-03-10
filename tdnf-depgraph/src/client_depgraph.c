/*
 * Copyright (C) 2026 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

/*
 * client/depgraph.c
 *
 * Client API entry point for the dependency graph command.
 * Delegates to the solv layer after refreshing metadata.
 *
 * Place this file in tdnf/client/ and add to client/CMakeLists.txt.
 */

#include "includes.h"

uint32_t
TDNFDepGraph(
    PTDNF pTdnf,
    PTDNF_DEP_GRAPH *ppGraph
    )
{
    uint32_t dwError = 0;

    if (!pTdnf || !pTdnf->pSack || !ppGraph)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFRefresh(pTdnf);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = SolvBuildDepGraph(pTdnf->pSack, ppGraph);
    BAIL_ON_TDNF_ERROR(dwError);

cleanup:
    return dwError;

error:
    if (ppGraph)
    {
        *ppGraph = NULL;
    }
    goto cleanup;
}
