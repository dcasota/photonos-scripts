#ifndef DEPGRAPH_DEEP_GRAPH_H
#define DEPGRAPH_DEEP_GRAPH_H

#include <stdint.h>
#include <stddef.h>

#define MAX_NAME_LEN     256
#define MAX_VERSION_LEN   64
#define MAX_CONSTRAINT_LEN 64
#define MAX_EVIDENCE_LEN  512
#define MAX_PATH_LEN      512
#define MAX_SECTION_LEN   128
#define MAX_DIRECTIVE_LEN  32
#define MAX_LINE_LEN     4096

#define INITIAL_NODE_CAP  2048
#define INITIAL_EDGE_CAP  16384

/* Edge types */
typedef enum {
    EDGE_REQUIRES = 0,
    EDGE_BUILDREQUIRES,
    EDGE_PROVIDES,
    EDGE_CONFLICTS,
    EDGE_OBSOLETES,
    EDGE_RECOMMENDS,
    EDGE_SUGGESTS,
    EDGE_SUPPLEMENTS,
    EDGE_TYPE_COUNT
} EdgeType;

/* Edge provenance */
typedef enum {
    EDGE_SRC_SPEC = 0,
    EDGE_SRC_GOMOD,
    EDGE_SRC_PYPROJECT,
    EDGE_SRC_API_CONSTANT
} EdgeSource;

/* Severity for spec patches */
typedef enum {
    SEVERITY_CRITICAL = 0,
    SEVERITY_IMPORTANT,
    SEVERITY_INFORMATIONAL
} PatchSeverity;

/* Constraint operator */
typedef enum {
    CONSTRAINT_NONE = 0,
    CONSTRAINT_EQ,       /* = */
    CONSTRAINT_GE,       /* >= */
    CONSTRAINT_GT,       /* > */
    CONSTRAINT_LE,       /* <= */
    CONSTRAINT_LT        /* < */
} ConstraintOp;

/* Node: represents a package or subpackage */
typedef struct {
    uint32_t dwId;
    char     szName[MAX_NAME_LEN];
    char     szVersion[MAX_VERSION_LEN];
    char     szRelease[MAX_VERSION_LEN];
    char     szEpoch[MAX_VERSION_LEN];
    char     szSpecPath[MAX_PATH_LEN];
    char     szParentPackage[MAX_NAME_LEN]; /* empty if main package */
    uint32_t bIsSubpackage;
} GraphNode;

/* Edge: dependency relationship */
typedef struct {
    uint32_t    dwFromIdx;
    uint32_t    dwToIdx;
    EdgeType    nType;
    EdgeSource  nSource;
    ConstraintOp nConstraintOp;
    char        szConstraintVer[MAX_VERSION_LEN];
    char        szEvidence[MAX_EVIDENCE_LEN];
    char        szTargetName[MAX_NAME_LEN]; /* raw target before resolution */
} GraphEdge;

/* Virtual provide: e.g. docker-api = 1.53 */
typedef struct {
    char     szName[MAX_NAME_LEN];
    char     szVersion[MAX_VERSION_LEN];
    uint32_t dwProviderIdx; /* node id of the provider */
    EdgeSource nSource;
    char     szEvidence[MAX_EVIDENCE_LEN];
} VirtualProvide;

/* Spec patch action */
typedef struct _SpecPatch {
    char          szPackage[MAX_NAME_LEN];
    char          szSection[MAX_SECTION_LEN];
    char          szDirective[MAX_DIRECTIVE_LEN];
    char          szValue[MAX_NAME_LEN];
    EdgeSource    nSource;
    char          szEvidence[MAX_EVIDENCE_LEN];
    PatchSeverity nSeverity;
    struct _SpecPatch *pNext;
} SpecPatch;

/* Per-spec patch set */
typedef struct _SpecPatchSet {
    char          szSpecPath[MAX_PATH_LEN];
    char          szPatchedPath[MAX_PATH_LEN];
    char          szPackageName[MAX_NAME_LEN];
    uint32_t      dwAdditionCount;
    SpecPatch    *pAdditions;
    struct _SpecPatchSet *pNext;
} SpecPatchSet;

/* Conflict record */
typedef struct _ConflictRecord {
    char     szType[MAX_NAME_LEN];
    char     szConsumer[MAX_NAME_LEN];
    char     szConsumerVer[MAX_VERSION_LEN];
    char     szProvider[MAX_NAME_LEN];
    char     szProviderVer[MAX_VERSION_LEN];
    char     szRequiredApi[MAX_VERSION_LEN];
    char     szProvidedRange[MAX_EVIDENCE_LEN];
    char     szStatus[MAX_DIRECTIVE_LEN];
    char     szNote[MAX_EVIDENCE_LEN];
    struct _ConflictRecord *pNext;
} ConflictRecord;

/* Main graph container */
typedef struct {
    GraphNode      *pNodes;
    uint32_t        dwNodeCount;
    uint32_t        dwNodeCap;

    GraphEdge      *pEdges;
    uint32_t        dwEdgeCount;
    uint32_t        dwEdgeCap;

    VirtualProvide *pVirtuals;
    uint32_t        dwVirtualCount;
    uint32_t        dwVirtualCap;

    ConflictRecord *pConflicts;
    SpecPatchSet   *pPatchSets;

    char            szBranch[MAX_VERSION_LEN];
} DepGraph;

/* graph.c */
int      graph_init(DepGraph *pGraph, const char *pszBranch);
void     graph_free(DepGraph *pGraph);
uint32_t graph_add_node(DepGraph *pGraph, const char *pszName,
                        const char *pszVersion, const char *pszRelease,
                        const char *pszEpoch, const char *pszSpecPath,
                        const char *pszParent);
int      graph_add_edge(DepGraph *pGraph, uint32_t dwFrom, uint32_t dwTo,
                        EdgeType nType, EdgeSource nSource,
                        ConstraintOp nOp, const char *pszConstraintVer,
                        const char *pszEvidence, const char *pszTargetName);
int      graph_add_virtual(DepGraph *pGraph, const char *pszName,
                           const char *pszVersion, uint32_t dwProviderIdx,
                           EdgeSource nSource, const char *pszEvidence);
int32_t  graph_find_node(DepGraph *pGraph, const char *pszName);
void     graph_add_conflict(DepGraph *pGraph, ConflictRecord *pRec);
void     graph_add_patchset(DepGraph *pGraph, SpecPatchSet *pSet);

const char *edge_type_str(EdgeType t);
const char *edge_source_str(EdgeSource s);
const char *severity_str(PatchSeverity s);
ConstraintOp parse_constraint_op(const char *pszOp);

#endif /* DEPGRAPH_DEEP_GRAPH_H */
