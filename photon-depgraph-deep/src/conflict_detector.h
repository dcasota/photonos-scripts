#ifndef DEPGRAPH_DEEP_CONFLICT_DETECTOR_H
#define DEPGRAPH_DEEP_CONFLICT_DETECTOR_H

#include "graph.h"

/* Run conflict detection across the graph.
   Compares declared (Phase 1) against inferred (Phase 2) dependencies.
   Populates pGraph->pConflicts and pGraph->pPatchSets.
   Returns the number of issues found. */
uint32_t conflict_detect(DepGraph *pGraph);

#endif /* DEPGRAPH_DEEP_CONFLICT_DETECTOR_H */
