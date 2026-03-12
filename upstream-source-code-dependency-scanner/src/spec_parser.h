#ifndef DEPGRAPH_DEEP_SPEC_PARSER_H
#define DEPGRAPH_DEEP_SPEC_PARSER_H

#include "graph.h"

/* Parse all .spec files under pszSpecsDir, populating pGraph with nodes and edges.
   Returns 0 on success, nonzero on error. */
int spec_parse_directory(DepGraph *pGraph, const char *pszSpecsDir);

/* Parse a single .spec file. */
int spec_parse_file(DepGraph *pGraph, const char *pszSpecPath);

#endif /* DEPGRAPH_DEEP_SPEC_PARSER_H */
