#ifndef DEPGRAPH_DEEP_VIRTUAL_PROVIDES_H
#define DEPGRAPH_DEEP_VIRTUAL_PROVIDES_H

#include "graph.h"

/* Resolve unresolved edges by matching against virtual provides.
   For edges where dwToIdx == UINT32_MAX (unresolved), attempt to
   match szTargetName against virtual provides. Returns count of resolved. */
uint32_t virtual_resolve_edges(DepGraph *pGraph);

/* Compare two version strings. Returns <0, 0, >0. */
int version_compare(const char *pszA, const char *pszB);

/* Check if a version satisfies a constraint. */
int version_satisfies(const char *pszVersion, ConstraintOp nOp,
                      const char *pszConstraint);

#endif /* DEPGRAPH_DEEP_VIRTUAL_PROVIDES_H */
