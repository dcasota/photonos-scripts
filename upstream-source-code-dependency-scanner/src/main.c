#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include <sys/stat.h>

#include "graph.h"
#include "spec_parser.h"
#include "gomod_analyzer.h"
#include "gomod_to_package_map.h"
#include "pyproject_analyzer.h"
#include "api_version_extractor.h"
#include "virtual_provides.h"
#include "conflict_detector.h"
#include "spec_patcher.h"
#include "manifest_writer.h"
#include "json_output.h"
#include "prn_parser.h"
#include "tarball_analyzer.h"

static void usage(const char *pszProg)
{
    fprintf(stderr,
        "Usage: %s [OPTIONS]\n"
        "\n"
        "Options:\n"
        "  --specs-dir DIR       Path to vmware/photon SPECS/ directory (required)\n"
        "  --specs-new-dir DIR   Path to SPECS_NEW/ directory (latest version specs)\n"
        "  --upstreams-dir DIR   Path to photon-upstreams/{branch}/ directory\n"
        "  --sources-dir DIR     Path to photon_sources/1.0/ (current release tarballs)\n"
        "  --output-dir DIR      Output directory (default: ./output)\n"
        "  --data-dir DIR        Data directory with CSV mappings (default: ./data)\n"
        "  --branch NAME         Branch name (default: 5.0)\n"
        "  --prn-file FILE       PRN package report file (for package->clone mapping)\n"
        "  --json                Write enriched dependency graph JSON\n"
        "  --patch-specs         Generate patched spec files in SPECS_DEPFIX/\n"
        "  --help                Show this help\n",
        pszProg);
}

/* Check if a node has BuildRequires: go (indicating it's a Go package) */
static int
node_has_go_buildrequires(DepGraph *pGraph, uint32_t dwNodeIdx)
{
    for (uint32_t i = 0; i < pGraph->dwEdgeCount; i++)
    {
        GraphEdge *pEdge = &pGraph->pEdges[i];
        if (pEdge->dwFromIdx != dwNodeIdx)
            continue;
        if (pEdge->nType != EDGE_BUILDREQUIRES)
            continue;
        if (pEdge->nSource != EDGE_SRC_SPEC)
            continue;
        if (strcasecmp(pEdge->szTargetName, "go") == 0 ||
            strcasecmp(pEdge->szTargetName, "golang") == 0)
            return 1;
    }
    return 0;
}

/* Check if a node already has gomod-inferred edges (already analyzed from clone) */
static int
node_has_gomod_edges(DepGraph *pGraph, uint32_t dwNodeIdx)
{
    for (uint32_t i = 0; i < pGraph->dwEdgeCount; i++)
    {
        GraphEdge *pEdge = &pGraph->pEdges[i];
        if (pEdge->dwFromIdx == dwNodeIdx &&
            (pEdge->nSource == EDGE_SRC_GOMOD || pEdge->nSource == EDGE_SRC_TARBALL))
            return 1;
    }
    return 0;
}

/* Analyze sources from tarballs in a flat source directory.
   Only considers Go packages (BuildRequires: go) that were not
   already analyzed from clones. */
static void
analyze_tarball_sources(DepGraph *pGraph, const char *pszSourcesDir,
                        const GomodPackageMap *pGomodMap)
{
    if (!pGraph || !pszSourcesDir || !pGomodMap)
        return;

    struct stat st;
    if (stat(pszSourcesDir, &st) != 0 || !S_ISDIR(st.st_mode))
        return;

    uint32_t dwAnalyzed = 0;
    uint32_t dwSkippedClone = 0;
    for (uint32_t i = 0; i < pGraph->dwNodeCount; i++)
    {
        GraphNode *pNode = &pGraph->pNodes[i];
        if (pNode->bIsSubpackage || !pNode->szVersion[0])
            continue;

        /* Only analyze Go packages */
        if (!node_has_go_buildrequires(pGraph, i))
            continue;

        /* Skip if already analyzed from clone */
        if (node_has_gomod_edges(pGraph, i))
        {
            dwSkippedClone++;
            continue;
        }

        char szTarball[MAX_PATH_LEN];
        if (tarball_find_source(pszSourcesDir, pNode->szName,
                                pNode->szVersion,
                                szTarball, sizeof(szTarball)) == 0)
        {
            if (tarball_analyze_gomod(pGraph, szTarball,
                                      pNode->szName, pGomodMap) == 0)
            {
                dwAnalyzed++;
            }
        }
    }

    if (dwAnalyzed > 0 || dwSkippedClone > 0)
    {
        fprintf(stderr, "[Tarball] Analyzed %u source tarballs (%u skipped, already from clones)\n",
                dwAnalyzed, dwSkippedClone);
    }
}

int main(int argc, char *argv[])
{
    const char *pszSpecsDir = NULL;
    const char *pszSpecsNewDir = NULL;
    const char *pszUpstreamsDir = NULL;
    const char *pszSourcesDir = NULL;
    const char *pszOutputDir = "./output";
    const char *pszDataDir = "./data";
    const char *pszBranch = "5.0";
    const char *pszPrnFile = NULL;
    int bJson = 0;
    int bPatchSpecs = 0;

    static struct option aoLong[] = {
        {"specs-dir",     required_argument, 0, 's'},
        {"specs-new-dir", required_argument, 0, 'n'},
        {"upstreams-dir", required_argument, 0, 'u'},
        {"sources-dir",   required_argument, 0, 'S'},
        {"output-dir",    required_argument, 0, 'o'},
        {"data-dir",      required_argument, 0, 'd'},
        {"branch",        required_argument, 0, 'b'},
        {"prn-file",      required_argument, 0, 'r'},
        {"json",          no_argument,       0, 'j'},
        {"patch-specs",   no_argument,       0, 'p'},
        {"help",          no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };

    int nOpt;
    while ((nOpt = getopt_long(argc, argv, "s:n:u:S:o:d:b:r:jph", aoLong, NULL)) != -1)
    {
        switch (nOpt)
        {
            case 's': pszSpecsDir = optarg; break;
            case 'n': pszSpecsNewDir = optarg; break;
            case 'u': pszUpstreamsDir = optarg; break;
            case 'S': pszSourcesDir = optarg; break;
            case 'o': pszOutputDir = optarg; break;
            case 'd': pszDataDir = optarg; break;
            case 'b': pszBranch = optarg; break;
            case 'r': pszPrnFile = optarg; break;
            case 'j': bJson = 1; break;
            case 'p': bPatchSpecs = 1; break;
            case 'h': usage(argv[0]); return 0;
            default:  usage(argv[0]); return 1;
        }
    }

    if (!pszSpecsDir)
    {
        fprintf(stderr, "Error: --specs-dir is required\n");
        usage(argv[0]);
        return 1;
    }

    /* Reject path traversal in branch name and output dir */
    if (strstr(pszBranch, ".."))
    {
        fprintf(stderr, "Error: branch name must not contain '..'\n");
        return 1;
    }
    if (strstr(pszOutputDir, ".."))
    {
        fprintf(stderr, "Error: output directory must not contain '..'\n");
        return 1;
    }

    mkdir(pszOutputDir, 0755);

    DepGraph graph;
    if (graph_init(&graph, pszBranch) != 0)
    {
        fprintf(stderr, "Error: failed to initialize graph\n");
        return 1;
    }

    /* Load PRN package->clone mapping if provided */
    PrnMap prnMap;
    memset(&prnMap, 0, sizeof(prnMap));
    const PrnMap *pPrnMap = NULL;
    if (pszPrnFile)
    {
        if (prn_map_load(&prnMap, pszPrnFile) == 0)
        {
            fprintf(stderr, "[Data] Loaded PRN map: %u package->clone entries from %s\n",
                    prnMap.dwCount, pszPrnFile);
            pPrnMap = &prnMap;
        }
        else
        {
            fprintf(stderr, "[Data] Warning: could not load PRN file %s\n", pszPrnFile);
        }
    }

    /* Load gomod-package-map early; needed by multiple phases */
    char szMapPath[MAX_PATH_LEN];
    snprintf(szMapPath, sizeof(szMapPath), "%s/gomod-package-map.csv", pszDataDir);

    GomodPackageMap gomodMap;
    memset(&gomodMap, 0, sizeof(gomodMap));
    int bHaveGomodMap = (gomod_map_load(&gomodMap, szMapPath) == 0);

    /* ================================================================
       Phase 1a: Parse current release spec files
       ================================================================ */
    fprintf(stderr, "[Phase 1a] Parsing current specs from %s ...\n", pszSpecsDir);
    int nRc = spec_parse_directory(&graph, pszSpecsDir);
    if (nRc != 0)
    {
        fprintf(stderr, "Warning: spec parsing returned %d errors\n", nRc);
    }
    fprintf(stderr, "[Phase 1a] Done: %u nodes, %u edges\n",
            graph.dwNodeCount, graph.dwEdgeCount);

    uint32_t dwSpecsScanned = graph.dwNodeCount;
    uint32_t dwPhase1Edges = graph.dwEdgeCount;

    /* ================================================================
       Phase 1b: Parse latest version specs from SPECS_NEW (if provided)
       ================================================================ */
    uint32_t dwLatestNodesStart = graph.dwNodeCount;
    if (pszSpecsNewDir)
    {
        struct stat stNew;
        if (stat(pszSpecsNewDir, &stNew) == 0 && S_ISDIR(stNew.st_mode))
        {
            fprintf(stderr, "[Phase 1b] Parsing latest specs from %s ...\n",
                    pszSpecsNewDir);
            nRc = spec_parse_directory(&graph, pszSpecsNewDir);
            if (nRc != 0)
            {
                fprintf(stderr, "Warning: SPECS_NEW parsing returned %d errors\n", nRc);
            }

            /* Tag nodes from SPECS_NEW as latest */
            for (uint32_t i = dwLatestNodesStart; i < graph.dwNodeCount; i++)
            {
                graph.pNodes[i].bIsLatest = 1;
            }

            fprintf(stderr, "[Phase 1b] Done: %u latest nodes added (%u total nodes)\n",
                    graph.dwNodeCount - dwLatestNodesStart, graph.dwNodeCount);
            dwSpecsScanned = graph.dwNodeCount;
        }
        else
        {
            fprintf(stderr, "[Phase 1b] Skipped: %s not found\n", pszSpecsNewDir);
        }
    }

    /* ================================================================
       Phase 2: Upstream source analysis
       ================================================================ */
    if (pszUpstreamsDir)
    {
        char szClonesDir[MAX_PATH_LEN];
        snprintf(szClonesDir, sizeof(szClonesDir), "%s/clones", pszUpstreamsDir);

        struct stat st;
        if (stat(szClonesDir, &st) == 0 && S_ISDIR(st.st_mode))
        {
            /* Phase 2a: Go module analysis from clones */
            if (bHaveGomodMap)
            {
                fprintf(stderr, "[Phase 2a] Analyzing Go modules in %s ...\n", szClonesDir);
                gomod_analyze_clones(&graph, szClonesDir, &gomodMap, pPrnMap);
                fprintf(stderr, "[Phase 2a] Done: %u edges total (+%u inferred)\n",
                        graph.dwEdgeCount, graph.dwEdgeCount - dwPhase1Edges);
            }
            else
            {
                fprintf(stderr, "[Phase 2a] Skipped: could not load %s\n", szMapPath);
            }

            /* Phase 2b: Python dependency analysis */
            fprintf(stderr, "[Phase 2b] Analyzing Python projects in %s ...\n", szClonesDir);
            pyproject_analyze_clones(&graph, szClonesDir);
            fprintf(stderr, "[Phase 2b] Done: %u edges total\n", graph.dwEdgeCount);

            /* Phase 2c: API version extraction */
            char szPatternsPath[MAX_PATH_LEN];
            snprintf(szPatternsPath, sizeof(szPatternsPath),
                     "%s/api-version-patterns.csv", pszDataDir);

            ApiVersionPatterns apiPatterns;
            memset(&apiPatterns, 0, sizeof(apiPatterns));
            if (api_patterns_load(&apiPatterns, szPatternsPath) == 0)
            {
                fprintf(stderr, "[Phase 2c] Extracting API version constants ...\n");
                api_version_extract(&graph, szClonesDir, &apiPatterns, pPrnMap);
                fprintf(stderr, "[Phase 2c] Done: %u virtual provides\n",
                        graph.dwVirtualCount);
            }
            else
            {
                fprintf(stderr, "[Phase 2c] Skipped: could not load %s\n", szPatternsPath);
            }

            /* Resolve virtual provides */
            uint32_t dwResolved = virtual_resolve_edges(&graph);
            fprintf(stderr, "[Resolve] Resolved %u edges via virtual provides\n", dwResolved);
        }
        else
        {
            fprintf(stderr, "[Phase 2] Skipped: %s not found\n", szClonesDir);
        }

        /* Phase 2d: Tarball analysis for SOURCES_NEW (latest version tarballs) */
        if (bHaveGomodMap)
        {
            char szSourcesNewDir[MAX_PATH_LEN];
            snprintf(szSourcesNewDir, sizeof(szSourcesNewDir),
                     "%s/SOURCES_NEW", pszUpstreamsDir);
            struct stat stSrcNew;
            if (stat(szSourcesNewDir, &stSrcNew) == 0 && S_ISDIR(stSrcNew.st_mode))
            {
                uint32_t dwPreEdges = graph.dwEdgeCount;
                fprintf(stderr, "[Phase 2d] Analyzing SOURCES_NEW tarballs in %s ...\n",
                        szSourcesNewDir);
                analyze_tarball_sources(&graph, szSourcesNewDir, &gomodMap);
                fprintf(stderr, "[Phase 2d] Done: %u edges total (+%u from tarballs)\n",
                        graph.dwEdgeCount, graph.dwEdgeCount - dwPreEdges);
            }
        }
    }
    else
    {
        fprintf(stderr, "[Phase 2] Skipped: no --upstreams-dir provided\n");
    }

    /* Phase 2e: Tarball analysis for current release sources */
    if (pszSourcesDir && bHaveGomodMap)
    {
        uint32_t dwPreEdges = graph.dwEdgeCount;
        fprintf(stderr, "[Phase 2e] Analyzing current source tarballs in %s ...\n",
                pszSourcesDir);
        analyze_tarball_sources(&graph, pszSourcesDir, &gomodMap);
        fprintf(stderr, "[Phase 2e] Done: %u edges total (+%u from tarballs)\n",
                graph.dwEdgeCount, graph.dwEdgeCount - dwPreEdges);
    }

    /* Load Docker SDK-to-API version map */
    DockerSdkApiMap sdkMap;
    memset(&sdkMap, 0, sizeof(sdkMap));
    {
        char szSdkMapPath[MAX_PATH_LEN];
        snprintf(szSdkMapPath, sizeof(szSdkMapPath),
                 "%s/docker-api-version-map.csv", pszDataDir);
        if (docker_sdk_map_load(&sdkMap, szSdkMapPath) == 0)
        {
            fprintf(stderr, "[Data] Loaded Docker SDK-to-API map: %u entries\n",
                    sdkMap.dwCount);
        }
        else
        {
            fprintf(stderr, "[Data] Warning: could not load %s\n", szSdkMapPath);
        }
    }

    /* ================================================================
       Phase 3: Conflict detection and spec patching
       ================================================================ */
    fprintf(stderr, "[Phase 3] Running conflict detection ...\n");
    uint32_t dwIssues = conflict_detect(&graph,
                                        sdkMap.dwCount > 0 ? &sdkMap : NULL);
    fprintf(stderr, "[Phase 3] Found %u issues\n", dwIssues);

    uint32_t dwSpecsPatched = 0;
    if (bPatchSpecs && graph.pPatchSets)
    {
        fprintf(stderr, "[Phase 3] Generating patched spec files ...\n");
        dwSpecsPatched = spec_patch_all(&graph, pszOutputDir, pszBranch);
        fprintf(stderr, "[Phase 3] Patched %u spec files\n", dwSpecsPatched);
    }

    /* Write manifest */
    fprintf(stderr, "[Output] Writing depfix manifest ...\n");
    manifest_write(&graph, pszOutputDir, dwSpecsScanned, dwSpecsPatched);

    /* Write JSON graph */
    if (bJson)
    {
        fprintf(stderr, "[Output] Writing enriched dependency graph JSON ...\n");
        json_output_write(&graph, pszOutputDir);
    }

    /* Summary */
    fprintf(stderr, "\n=== Summary ===\n");
    fprintf(stderr, "Branch:           %s\n", pszBranch);
    fprintf(stderr, "Nodes:            %u\n", graph.dwNodeCount);
    if (pszSpecsNewDir)
    {
        fprintf(stderr, "  current:        %u\n", dwLatestNodesStart);
        fprintf(stderr, "  latest:         %u\n", graph.dwNodeCount - dwLatestNodesStart);
    }
    fprintf(stderr, "Edges (total):    %u\n", graph.dwEdgeCount);
    fprintf(stderr, "  spec-declared:  %u\n", dwPhase1Edges);
    fprintf(stderr, "  inferred:       %u\n", graph.dwEdgeCount - dwPhase1Edges);
    fprintf(stderr, "Virtual provides: %u\n", graph.dwVirtualCount);
    fprintf(stderr, "Issues detected:  %u\n", dwIssues);
    fprintf(stderr, "Specs patched:    %u\n", dwSpecsPatched);
    fprintf(stderr, "Output dir:       %s\n", pszOutputDir);

    graph_free(&graph);
    return 0;
}
