#ifndef DEPGRAPH_DEEP_GOMOD_ANALYZER_H
#define DEPGRAPH_DEEP_GOMOD_ANALYZER_H

#include "graph.h"
#include "gomod_to_package_map.h"

/* Analyze all go.mod files in photon-upstreams clones directory.
   pszClonesDir: path to photon-upstreams/{branch}/clones/
   Adds inferred edges to pGraph. Returns 0 on success. */
int gomod_analyze_clones(DepGraph *pGraph, const char *pszClonesDir,
                         const GomodPackageMap *pMap);

/* Parse a single go.mod file and add inferred edges.
   pszPackageName: the Photon package name that owns this go.mod. */
int gomod_parse_file(DepGraph *pGraph, const char *pszGomodPath,
                     const char *pszPackageName, const GomodPackageMap *pMap);

#endif /* DEPGRAPH_DEEP_GOMOD_ANALYZER_H */
