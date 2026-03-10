/*
 * Copyright (C) 2026 VMware, Inc. All Rights Reserved.
 *
 * CLI declarations for tdnf depgraph command.
 *
 * Append these declarations to include/tdnfcli.h,
 * before the closing #ifdef __cplusplus / #endif.
 */

/* ---- begin depgraph CLI declarations ---- */

uint32_t
TDNFCliDepGraphCommand(
    PTDNF_CLI_CONTEXT pContext,
    PTDNF_CMD_ARGS pCmdArgs
    );

uint32_t
TDNFCliInvokeDepGraph(
    PTDNF_CLI_CONTEXT pContext,
    PTDNF_DEP_GRAPH *ppGraph
    );

/* ---- end depgraph CLI declarations ---- */
