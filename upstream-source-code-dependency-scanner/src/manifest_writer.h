#ifndef DEPGRAPH_DEEP_MANIFEST_WRITER_H
#define DEPGRAPH_DEEP_MANIFEST_WRITER_H

#include "graph.h"

/* Write the depfix manifest JSON to the output directory.
   Filename: depfix-manifest-{branch}-{timestamp}.json
   Returns 0 on success. */
int manifest_write(const DepGraph *pGraph, const char *pszOutputDir,
                   uint32_t dwSpecsScanned, uint32_t dwSpecsPatched);

#endif /* DEPGRAPH_DEEP_MANIFEST_WRITER_H */
