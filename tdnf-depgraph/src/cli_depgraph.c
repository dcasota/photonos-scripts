/*
 * Copyright (C) 2026 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU General Public License v2 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

/*
 * tools/cli/lib/depgraph.c
 *
 * CLI handler for `tdnf depgraph`. Supports three output formats:
 *   --json        JSON with nodes and edges arrays (default if --json global flag)
 *   --dot         Graphviz DOT format
 *   (default)     Adjacency list: one line per package
 *
 * Place this file in tdnf/tools/cli/lib/ and add to tools/cli/lib/CMakeLists.txt.
 */

#include "includes.h"
#include "../../../llconf/nodes.h"

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
    PTDNF_DEP_GRAPH pGraph
    )
{
    uint32_t dwError = 0;
    uint32_t i;
    struct json_dump *jd = NULL;
    struct json_dump *jd_meta = NULL;
    struct json_dump *jd_nodes = NULL;
    struct json_dump *jd_edges = NULL;
    struct json_dump *jd_node = NULL;
    struct json_dump *jd_edge = NULL;
    PTDNF_DEP_EDGE pEdge = NULL;

    jd = jd_create(4096);
    CHECK_JD_NULL(jd);
    CHECK_JD_RC(jd_map_start(jd));

    /* metadata */
    jd_meta = jd_create(0);
    CHECK_JD_NULL(jd_meta);
    CHECK_JD_RC(jd_map_start(jd_meta));
    CHECK_JD_RC(jd_map_add_string(jd_meta, "generator", "tdnf depgraph"));
    CHECK_JD_RC(jd_map_add_int(jd_meta, "node_count", pGraph->dwNodeCount));
    CHECK_JD_RC(jd_map_add_int(jd_meta, "edge_count", pGraph->dwEdgeCount));
    CHECK_JD_RC(jd_map_add_child(jd, "metadata", jd_meta));
    JD_SAFE_DESTROY(jd_meta);

    /* nodes */
    jd_nodes = jd_create(4096);
    CHECK_JD_NULL(jd_nodes);
    CHECK_JD_RC(jd_list_start(jd_nodes));

    for (i = 0; i < pGraph->dwNodeCount; i++)
    {
        jd_node = jd_create(0);
        CHECK_JD_NULL(jd_node);
        CHECK_JD_RC(jd_map_start(jd_node));

        CHECK_JD_RC(jd_map_add_int(jd_node, "id", i));
        CHECK_JD_RC(jd_map_add_string(jd_node, "name",
                                       pGraph->pNodes[i].pszName));
        CHECK_JD_RC(jd_map_add_string(jd_node, "nevra",
                                       pGraph->pNodes[i].pszNevra));
        CHECK_JD_RC(jd_map_add_string(jd_node, "arch",
                                       pGraph->pNodes[i].pszArch));
        CHECK_JD_RC(jd_map_add_string(jd_node, "evr",
                                       pGraph->pNodes[i].pszEvr));
        CHECK_JD_RC(jd_map_add_string(jd_node, "repo",
                                       pGraph->pNodes[i].pszRepo));
        CHECK_JD_RC(jd_map_add_int(jd_node, "reverse_dep_count",
                                    pGraph->pNodes[i].dwReverseDepCount));
        CHECK_JD_RC(jd_map_add_bool(jd_node, "is_source",
                                     pGraph->pNodes[i].nIsSource));

        CHECK_JD_RC(jd_list_add_child(jd_nodes, jd_node));
        JD_SAFE_DESTROY(jd_node);
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
            jd_edge = jd_create(0);
            CHECK_JD_NULL(jd_edge);
            CHECK_JD_RC(jd_map_start(jd_edge));

            CHECK_JD_RC(jd_map_add_int(jd_edge, "from", pEdge->dwFromIdx));
            CHECK_JD_RC(jd_map_add_int(jd_edge, "to", pEdge->dwToIdx));
            CHECK_JD_RC(jd_map_add_string(jd_edge, "type",
                                           DepEdgeTypeName(pEdge->nType)));

            CHECK_JD_RC(jd_list_add_child(jd_edges, jd_edge));
            JD_SAFE_DESTROY(jd_edge);
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
    JD_SAFE_DESTROY(jd_node);
    JD_SAFE_DESTROY(jd_edge);
    goto cleanup;
}

static uint32_t
TDNFCliDepGraphPrintDot(
    PTDNF_DEP_GRAPH pGraph
    )
{
    uint32_t i;
    PTDNF_DEP_EDGE pEdge;

    pr_crit("digraph depgraph {\n");
    pr_crit("  rankdir=LR;\n");
    pr_crit("  node [shape=box, fontsize=10];\n\n");

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
    PTDNF_DEP_GRAPH pGraph
    )
{
    uint32_t i;
    PTDNF_DEP_EDGE pEdge;

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
    int nDotOutput = 0;
    struct cnfnode *cn = NULL;

    if (!pContext || !pContext->hTdnf || !pCmdArgs)
    {
        dwError = ERROR_TDNF_CLI_INVALID_ARGUMENT;
        BAIL_ON_CLI_ERROR(dwError);
    }

    /* Check for --dot option */
    for (cn = pCmdArgs->cn_setopts->first_child; cn; cn = cn->next)
    {
        if (strcasecmp(cn->name, "dot") == 0)
        {
            nDotOutput = 1;
        }
    }

    dwError = TDNFDepGraph(pContext->hTdnf, &pGraph);
    BAIL_ON_CLI_ERROR(dwError);

    pr_info("Dependency graph: %u nodes, %u edges\n",
            pGraph->dwNodeCount, pGraph->dwEdgeCount);

    if (pCmdArgs->nJsonOutput)
    {
        dwError = TDNFCliDepGraphPrintJson(pGraph);
    }
    else if (nDotOutput)
    {
        dwError = TDNFCliDepGraphPrintDot(pGraph);
    }
    else
    {
        dwError = TDNFCliDepGraphPrintAdjacency(pGraph);
    }
    BAIL_ON_CLI_ERROR(dwError);

cleanup:
    if (pGraph)
    {
        SolvFreeDepGraph(pGraph);
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
