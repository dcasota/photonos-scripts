/*
 * Copyright (C) 2026 VMware, Inc. All Rights Reserved.
 *
 * Type additions for tdnf depgraph command.
 *
 * Append these definitions to include/tdnftypes.h,
 * before the closing #ifdef __cplusplus / #endif.
 */

/* ---- begin depgraph types ---- */

typedef enum {
    DEP_EDGE_REQUIRES,
    DEP_EDGE_BUILDREQUIRES,
    DEP_EDGE_RECOMMENDS,
    DEP_EDGE_SUGGESTS,
    DEP_EDGE_SUPPLEMENTS,
    DEP_EDGE_ENHANCES,
    DEP_EDGE_CONFLICTS,
    DEP_EDGE_OBSOLETES
} TDNF_DEP_EDGE_TYPE;

typedef struct _TDNF_DEP_EDGE {
    uint32_t dwFromIdx;
    uint32_t dwToIdx;
    TDNF_DEP_EDGE_TYPE nType;
    struct _TDNF_DEP_EDGE *pNext;
} TDNF_DEP_EDGE, *PTDNF_DEP_EDGE;

typedef struct _TDNF_DEP_GRAPH_NODE {
    char *pszName;
    char *pszNevra;
    char *pszArch;
    char *pszEvr;
    char *pszRepo;
    uint32_t dwSolvableId;
    uint32_t dwReverseDepCount;
    int nIsSource;
    PTDNF_DEP_EDGE pEdgesOut;
} TDNF_DEP_GRAPH_NODE, *PTDNF_DEP_GRAPH_NODE;

typedef struct _TDNF_DEP_GRAPH {
    uint32_t dwNodeCount;
    uint32_t dwEdgeCount;
    PTDNF_DEP_GRAPH_NODE pNodes;
} TDNF_DEP_GRAPH, *PTDNF_DEP_GRAPH;

/* ---- end depgraph types ---- */
