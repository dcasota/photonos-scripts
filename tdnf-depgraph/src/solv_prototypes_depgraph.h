/*
 * Copyright (C) 2026 VMware, Inc. All Rights Reserved.
 *
 * Prototype additions for solv/prototypes.h.
 *
 * Append these declarations to solv/prototypes.h,
 * before the closing #ifdef __cplusplus / #endif.
 */

/* ---- begin depgraph prototypes (solv layer) ---- */

// tdnfdepgraph.c
uint32_t
SolvBuildDepGraph(
    PSolvSack pSack,
    PTDNF_DEP_GRAPH *ppGraph
    );

void
SolvFreeDepGraph(
    PTDNF_DEP_GRAPH pGraph
    );

/* ---- end depgraph prototypes ---- */
