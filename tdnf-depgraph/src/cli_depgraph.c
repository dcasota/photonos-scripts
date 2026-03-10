/*
 * Copyright (C) 2026 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU General Public License v2 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#include "includes.h"

static const char *
DepEdgeTypeName(TDNF_DEP_EDGE_TYPE nType)
{
    switch (nType)
    {
        case DEP_EDGE_REQUIRES:      return "requires";
        case DEP_EDGE_BUILDREQUIRES: return "buildrequires";
        case DEP_EDGE_RECOMMENDS:    return "recommends";
        case DEP_EDGE_SUGGESTS:      return "suggests";
        case DEP_EDGE_SUPPLEMENTS:   return "supplements";
        case DEP_EDGE_ENHANCES:      return "enhances";
        case DEP_EDGE_CONFLICTS:     return "conflicts";
        case DEP_EDGE_OBSOLETES:     return "obsoletes";
        default:                     return "unknown";
    }
}

static uint32_t
TDNFCliDepGraphPrintJson(
    PTDNF_DEP_GRAPH pGraph,
    const char *pszBranch
    )
{
    uint32_t dwError = 0;
    uint32_t i;
    struct json_dump *jd = NULL;
    struct json_dump *jd_meta = NULL;
    struct json_dump *jd_nodes = NULL;
    struct json_dump *jd_edges = NULL;
    struct json_dump *jd_item = NULL;
    PTDNF_DEP_EDGE pEdge = NULL;
    time_t now;
    struct tm *tm_utc;
    char szTimestamp[64] = {0};

    time(&now);
    tm_utc = gmtime(&now);
    strftime(szTimestamp, sizeof(szTimestamp), "%Y-%m-%dT%H:%M:%SZ", tm_utc);

    jd = jd_create(4096);
    CHECK_JD_NULL(jd);
    CHECK_JD_RC(jd_map_start(jd));

    /* metadata block */
    jd_meta = jd_create(0);
    CHECK_JD_NULL(jd_meta);
    CHECK_JD_RC(jd_map_start(jd_meta));
    CHECK_JD_RC(jd_map_add_string(jd_meta, "generator", "tdnf depgraph"));
    CHECK_JD_RC(jd_map_add_string(jd_meta, "timestamp", szTimestamp));
    if (pszBranch && *pszBranch)
    {
        CHECK_JD_RC(jd_map_add_string(jd_meta, "branch", pszBranch));
    }
    CHECK_JD_RC(jd_map_add_child(jd, "metadata", jd_meta));
    JD_SAFE_DESTROY(jd_meta);

    CHECK_JD_RC(jd_map_add_int(jd, "node_count", pGraph->dwNodeCount));
    CHECK_JD_RC(jd_map_add_int(jd, "edge_count", pGraph->dwEdgeCount));

    /* nodes */
    jd_nodes = jd_create(4096);
    CHECK_JD_NULL(jd_nodes);
    CHECK_JD_RC(jd_list_start(jd_nodes));

    for (i = 0; i < pGraph->dwNodeCount; i++)
    {
        jd_item = jd_create(0);
        CHECK_JD_NULL(jd_item);
        CHECK_JD_RC(jd_map_start(jd_item));

        CHECK_JD_RC(jd_map_add_int(jd_item, "id", i));
        CHECK_JD_RC(jd_map_add_string(jd_item, "name",
                                       pGraph->pNodes[i].pszName));
        CHECK_JD_RC(jd_map_add_string(jd_item, "nevra",
                                       pGraph->pNodes[i].pszNevra));
        CHECK_JD_RC(jd_map_add_string(jd_item, "arch",
                                       pGraph->pNodes[i].pszArch));
        CHECK_JD_RC(jd_map_add_string(jd_item, "evr",
                                       pGraph->pNodes[i].pszEvr));
        CHECK_JD_RC(jd_map_add_string(jd_item, "repo",
                                       pGraph->pNodes[i].pszRepo));
        CHECK_JD_RC(jd_map_add_int(jd_item, "reverse_dep_count",
                                    pGraph->pNodes[i].dwReverseDepCount));

        CHECK_JD_RC(jd_list_add_child(jd_nodes, jd_item));
        JD_SAFE_DESTROY(jd_item);
    }

    CHECK_JD_RC(jd_map_add_child(jd, "nodes", jd_nodes));
    JD_SAFE_DESTROY(jd_nodes);

    /* edges */
    jd_edges = jd_create(4096);
    CHECK_JD_NULL(jd_edges);
    CHECK_JD_RC(jd_list_start(jd_edges));

    for (i = 0; i < pGraph->dwNodeCount; i++)
    {
        for (pEdge = pGraph->pNodes[i].pEdgesOut; pEdge;
             pEdge = pEdge->pNext)
        {
            jd_item = jd_create(0);
            CHECK_JD_NULL(jd_item);
            CHECK_JD_RC(jd_map_start(jd_item));

            CHECK_JD_RC(jd_map_add_int(jd_item, "from", pEdge->dwFromIdx));
            CHECK_JD_RC(jd_map_add_int(jd_item, "to", pEdge->dwToIdx));
            CHECK_JD_RC(jd_map_add_string(jd_item, "type",
                                           DepEdgeTypeName(pEdge->nType)));

            CHECK_JD_RC(jd_list_add_child(jd_edges, jd_item));
            JD_SAFE_DESTROY(jd_item);
        }
    }

    CHECK_JD_RC(jd_map_add_child(jd, "edges", jd_edges));
    JD_SAFE_DESTROY(jd_edges);

    pr_json(jd->buf);

cleanup:
    JD_SAFE_DESTROY(jd);
    return dwError;

error:
    JD_SAFE_DESTROY(jd_meta);
    JD_SAFE_DESTROY(jd_nodes);
    JD_SAFE_DESTROY(jd_edges);
    JD_SAFE_DESTROY(jd_item);
    goto cleanup;
}

static uint32_t
TDNFCliDepGraphPrintDot(
    PTDNF_DEP_GRAPH pGraph,
    const char *pszBranch
    )
{
    uint32_t i;
    PTDNF_DEP_EDGE pEdge;

    if (pszBranch && *pszBranch)
        pr_crit("digraph \"depgraph_%s\" {\n", pszBranch);
    else
        pr_crit("digraph depgraph {\n");

    pr_crit("  rankdir=LR;\n");
    pr_crit("  node [shape=box, fontsize=10];\n");

    if (pszBranch && *pszBranch)
        pr_crit("  label=\"Photon OS %s dependency graph\";\n", pszBranch);

    pr_crit("\n");

    for (i = 0; i < pGraph->dwNodeCount; i++)
    {
        for (pEdge = pGraph->pNodes[i].pEdgesOut; pEdge;
             pEdge = pEdge->pNext)
        {
            const char *pszStyle = "";
            const char *pszColor = "";

            if (pEdge->nType == DEP_EDGE_CONFLICTS)
            {
                pszStyle = ", style=dashed";
                pszColor = ", color=red";
            }
            else if (pEdge->nType == DEP_EDGE_OBSOLETES)
            {
                pszStyle = ", style=dotted";
                pszColor = ", color=orange";
            }
            else if (pEdge->nType == DEP_EDGE_BUILDREQUIRES)
            {
                pszStyle = ", style=bold";
                pszColor = ", color=blue";
            }

            pr_crit("  \"%s\" -> \"%s\" [label=\"%s\"%s%s];\n",
                    pGraph->pNodes[pEdge->dwFromIdx].pszName,
                    pGraph->pNodes[pEdge->dwToIdx].pszName,
                    DepEdgeTypeName(pEdge->nType),
                    pszStyle, pszColor);
        }
    }

    pr_crit("}\n");
    return 0;
}

static uint32_t
TDNFCliDepGraphPrintAdjacency(
    PTDNF_DEP_GRAPH pGraph,
    const char *pszBranch
    )
{
    uint32_t i;
    PTDNF_DEP_EDGE pEdge;

    if (pszBranch && *pszBranch)
        pr_crit("# branch: %s\n", pszBranch);

    for (i = 0; i < pGraph->dwNodeCount; i++)
    {
        if (!pGraph->pNodes[i].pEdgesOut)
            continue;

        pr_crit("%s:", pGraph->pNodes[i].pszName);

        for (pEdge = pGraph->pNodes[i].pEdgesOut; pEdge;
             pEdge = pEdge->pNext)
        {
            if (pEdge->nType == DEP_EDGE_REQUIRES ||
                pEdge->nType == DEP_EDGE_BUILDREQUIRES)
            {
                pr_crit(" %s", pGraph->pNodes[pEdge->dwToIdx].pszName);
            }
        }
        pr_crit("\n");
    }
    return 0;
}

uint32_t
TDNFCliDepGraphCommand(
    PTDNF_CLI_CONTEXT pContext,
    PTDNF_CMD_ARGS pCmdArgs
    )
{
    uint32_t dwError = 0;
    PTDNF_DEP_GRAPH pGraph = NULL;
    PTDNF_CMD_OPT pSetOpt = NULL;
    int nDotOutput = 0;
    const char *pszBranch = NULL;
    const char *pszSpecsDir = NULL;

    if (!pContext || !pCmdArgs)
    {
        dwError = ERROR_TDNF_CLI_INVALID_ARGUMENT;
        BAIL_ON_CLI_ERROR(dwError);
    }

    for (pSetOpt = pCmdArgs->pSetOpt; pSetOpt; pSetOpt = pSetOpt->pNext)
    {
        if (strcasecmp(pSetOpt->pszOptName, "dot") == 0)
        {
            nDotOutput = 1;
        }
        else if (strcasecmp(pSetOpt->pszOptName, "branch") == 0)
        {
            pszBranch = pSetOpt->pszOptValue;
        }
        else if (strcasecmp(pSetOpt->pszOptName, "specsdir") == 0)
        {
            pszSpecsDir = pSetOpt->pszOptValue;
        }
    }

    /* Also allow "tdnf depgraph dot" as subcommand */
    if (pCmdArgs->nCmdCount > 1 &&
        strcasecmp(pCmdArgs->ppszCmds[1], "dot") == 0)
    {
        nDotOutput = 1;
    }

    if (pszSpecsDir)
    {
        dwError = TDNFBuildDepGraphFromSpecs(pszSpecsDir, &pGraph);
    }
    else
    {
        if (!pContext->hTdnf)
        {
            dwError = ERROR_TDNF_CLI_INVALID_ARGUMENT;
            BAIL_ON_CLI_ERROR(dwError);
        }
        dwError = TDNFCliInvokeDepGraph(pContext, &pGraph);
    }
    BAIL_ON_CLI_ERROR(dwError);

    if (pszBranch)
    {
        pr_info("Dependency graph [%s]: %u nodes, %u edges\n",
                pszBranch, pGraph->dwNodeCount, pGraph->dwEdgeCount);
    }
    else
    {
        pr_info("Dependency graph: %u nodes, %u edges\n",
                pGraph->dwNodeCount, pGraph->dwEdgeCount);
    }

    if (pCmdArgs->nJsonOutput)
    {
        dwError = TDNFCliDepGraphPrintJson(pGraph, pszBranch);
    }
    else if (nDotOutput)
    {
        dwError = TDNFCliDepGraphPrintDot(pGraph, pszBranch);
    }
    else
    {
        dwError = TDNFCliDepGraphPrintAdjacency(pGraph, pszBranch);
    }
    BAIL_ON_CLI_ERROR(dwError);

cleanup:
    if (pGraph)
    {
        TDNFFreeDepGraph(pGraph);
    }
    return dwError;

error:
    goto cleanup;
}

uint32_t
TDNFCliInvokeDepGraph(
    PTDNF_CLI_CONTEXT pContext,
    PTDNF_DEP_GRAPH *ppGraph
    )
{
    return TDNFDepGraph(pContext->hTdnf, ppGraph);
}
