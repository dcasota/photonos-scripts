#ifndef DEPGRAPH_DEEP_PYPROJECT_ANALYZER_H
#define DEPGRAPH_DEEP_PYPROJECT_ANALYZER_H

#include "graph.h"

/* Analyze Python projects in clones directory for install_requires/dependencies.
   Looks for setup.py, setup.cfg, pyproject.toml in each clone.
   Returns 0 on success. */
int pyproject_analyze_clones(DepGraph *pGraph, const char *pszClonesDir);

/* Parse a single Python project for dependencies. */
int pyproject_parse_project(DepGraph *pGraph, const char *pszProjectDir,
                            const char *pszPackageName);

#endif /* DEPGRAPH_DEEP_PYPROJECT_ANALYZER_H */
