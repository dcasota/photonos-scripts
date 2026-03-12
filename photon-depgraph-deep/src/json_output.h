#ifndef DEPGRAPH_DEEP_JSON_OUTPUT_H
#define DEPGRAPH_DEEP_JSON_OUTPUT_H

#include "graph.h"

/* Write the full enriched dependency graph as JSON.
   Filename: dependency-graph-{branch}-deep-{timestamp}.json
   Returns 0 on success. */
int json_output_write(const DepGraph *pGraph, const char *pszOutputDir);

#endif /* DEPGRAPH_DEEP_JSON_OUTPUT_H */
