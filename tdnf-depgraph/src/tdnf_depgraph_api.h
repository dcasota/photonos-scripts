/*
 * Copyright (C) 2026 VMware, Inc. All Rights Reserved.
 *
 * Public API additions for tdnf depgraph command.
 *
 * Append these declarations to include/tdnf.h,
 * before the closing #ifdef __cplusplus / #endif.
 */

/* ---- begin depgraph API ---- */

uint32_t
TDNFDepGraph(
    PTDNF pTdnf,
    PTDNF_DEP_GRAPH *ppGraph
    );

void
TDNFFreeDepGraph(
    PTDNF_DEP_GRAPH pGraph
    );

/* ---- end depgraph API ---- */
