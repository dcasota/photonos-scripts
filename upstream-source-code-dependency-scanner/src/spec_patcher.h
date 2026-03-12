#ifndef DEPGRAPH_DEEP_SPEC_PATCHER_H
#define DEPGRAPH_DEEP_SPEC_PATCHER_H

#include "graph.h"

/* Generate patched spec files for all patch sets in the graph.
   pszOutputDir: base output directory (SPECS_DEPFIX will be created under it).
   Returns the number of specs patched. */
uint32_t spec_patch_all(DepGraph *pGraph, const char *pszOutputDir,
                        const char *pszBranch);

/* Patch a single spec file with the given patch set.
   Reads from pSet->szSpecPath, writes to pSet->szPatchedPath. */
int spec_patch_file(const SpecPatchSet *pSet);

#endif /* DEPGRAPH_DEEP_SPEC_PATCHER_H */
