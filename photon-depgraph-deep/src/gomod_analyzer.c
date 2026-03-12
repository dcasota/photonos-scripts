#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <dirent.h>
#include <sys/stat.h>

#include "gomod_analyzer.h"

static void
gomod_extract_major_constraint(const char *pszVersion, char *pszOut, size_t nOutLen)
{
    int nMajor = 0;

    /* Version format: vX.Y.Z or vX.Y.Z+incompatible */
    if (pszVersion && pszVersion[0] == 'v')
    {
        nMajor = atoi(pszVersion + 1);
    }
    else if (pszVersion)
    {
        nMajor = atoi(pszVersion);
    }

    snprintf(pszOut, nOutLen, "%d.0", nMajor);
}

int
gomod_parse_file(DepGraph *pGraph, const char *pszGomodPath,
                 const char *pszPackageName, const GomodPackageMap *pMap)
{
    FILE *fp = NULL;
    char szLine[MAX_LINE_LEN];
    int bInRequireBlock = 0;
    int32_t dwFromIdx = -1;

    if (!pGraph || !pszGomodPath || !pszPackageName || !pMap)
    {
        return -1;
    }

    dwFromIdx = graph_find_node(pGraph, pszPackageName);
    if (dwFromIdx < 0)
    {
        return 0;
    }

    fp = fopen(pszGomodPath, "r");
    if (!fp)
    {
        return -1;
    }

    while (fgets(szLine, sizeof(szLine), fp))
    {
        char *pszTrimmed = szLine;
        char szModulePath[MAX_MODULE_PATH_LEN];
        char szVersion[MAX_VERSION_LEN];
        char szEvidence[MAX_EVIDENCE_LEN];
        char szConstraint[MAX_CONSTRAINT_LEN];
        char *pszIncompat = NULL;
        const char *pszMappedPkg = NULL;
        int32_t dwToIdx = -1;

        /* Strip leading whitespace */
        while (*pszTrimmed == ' ' || *pszTrimmed == '\t')
        {
            pszTrimmed++;
        }
        /* Strip trailing newline */
        pszTrimmed[strcspn(pszTrimmed, "\r\n")] = '\0';

        /* Detect require block start */
        if (strncmp(pszTrimmed, "require (", 9) == 0 ||
            strncmp(pszTrimmed, "require(", 8) == 0)
        {
            bInRequireBlock = 1;
            continue;
        }

        /* Detect block end */
        if (bInRequireBlock && pszTrimmed[0] == ')')
        {
            bInRequireBlock = 0;
            continue;
        }

        szModulePath[0] = '\0';
        szVersion[0] = '\0';

        if (bInRequireBlock)
        {
            /* Lines inside require block: module/path vX.Y.Z */
            if (sscanf(pszTrimmed, "%511s %63s", szModulePath, szVersion) != 2)
            {
                continue;
            }
        }
        else if (strncmp(pszTrimmed, "require ", 8) == 0)
        {
            /* Single-line require directive */
            if (sscanf(pszTrimmed + 8, "%511s %63s", szModulePath, szVersion) != 2)
            {
                continue;
            }
        }
        else
        {
            continue;
        }

        /* Strip +incompatible suffix */
        pszIncompat = strstr(szVersion, "+incompatible");
        if (pszIncompat)
        {
            *pszIncompat = '\0';
        }

        pszMappedPkg = gomod_map_lookup(pMap, szModulePath);
        if (!pszMappedPkg || strcmp(pszMappedPkg, pszPackageName) == 0)
        {
            continue;
        }

        dwToIdx = graph_find_node(pGraph, pszMappedPkg);
        if (dwToIdx < 0)
        {
            continue;
        }

        gomod_extract_major_constraint(szVersion, szConstraint,
                                       sizeof(szConstraint));

        snprintf(szEvidence, sizeof(szEvidence), "go.mod: %s %s",
                 szModulePath, szVersion);

        graph_add_edge(pGraph, (uint32_t)dwFromIdx, (uint32_t)dwToIdx,
                       EDGE_REQUIRES, EDGE_SRC_GOMOD,
                       CONSTRAINT_GE, szConstraint,
                       szEvidence, pszMappedPkg);
    }

    fclose(fp);
    return 0;
}

int
gomod_analyze_clones(DepGraph *pGraph, const char *pszClonesDir,
                     const GomodPackageMap *pMap)
{
    DIR *pDir = NULL;
    struct dirent *pEntry = NULL;

    if (!pGraph || !pszClonesDir || !pMap)
    {
        return -1;
    }

    pDir = opendir(pszClonesDir);
    if (!pDir)
    {
        fprintf(stderr, "gomod_analyze_clones: cannot open %s\n", pszClonesDir);
        return -1;
    }

    while ((pEntry = readdir(pDir)) != NULL)
    {
        char szGomodPath[MAX_PATH_LEN];
        struct stat st;

        if (pEntry->d_name[0] == '.')
        {
            continue;
        }

        /* Check that this is a directory */
        snprintf(szGomodPath, sizeof(szGomodPath), "%s/%s",
                 pszClonesDir, pEntry->d_name);
        if (stat(szGomodPath, &st) != 0 || !S_ISDIR(st.st_mode))
        {
            continue;
        }

        /* Check if go.mod exists at root level */
        snprintf(szGomodPath, sizeof(szGomodPath), "%s/%s/go.mod",
                 pszClonesDir, pEntry->d_name);
        if (stat(szGomodPath, &st) != 0 || !S_ISREG(st.st_mode))
        {
            continue;
        }

        /* Map clone directory name to Photon package.
           Try: direct name, then gomod-package-map reverse lookup via
           the go.mod module line, then common prefixes. */
        {
            char szPkgName[MAX_NAME_LEN];
            int bFound = 0;

            /* 1. Direct match */
            if (graph_find_node(pGraph, pEntry->d_name) >= 0)
            {
                snprintf(szPkgName, sizeof(szPkgName), "%s", pEntry->d_name);
                bFound = 1;
            }

            /* 2. Try reading module path from go.mod and reverse-map */
            if (!bFound)
            {
                FILE *fpMod = fopen(szGomodPath, "r");
                if (fpMod)
                {
                    char szModLine[MAX_LINE_LEN];
                    while (fgets(szModLine, sizeof(szModLine), fpMod))
                    {
                        char *pTrim = szModLine;
                        while (*pTrim == ' ' || *pTrim == '\t') pTrim++;
                        if (strncmp(pTrim, "module ", 7) == 0)
                        {
                            char szMod[MAX_MODULE_PATH_LEN];
                            pTrim += 7;
                            pTrim[strcspn(pTrim, " \t\r\n")] = '\0';
                            snprintf(szMod, sizeof(szMod), "%s", pTrim);
                            const char *pszMapped = gomod_map_lookup(pMap, szMod);
                            if (pszMapped && graph_find_node(pGraph, pszMapped) >= 0)
                            {
                                snprintf(szPkgName, sizeof(szPkgName), "%s", pszMapped);
                                bFound = 1;
                            }
                            break;
                        }
                    }
                    fclose(fpMod);
                }
            }

            /* 3. Try common prefixes: docker-{name} */
            if (!bFound)
            {
                char szTry[MAX_NAME_LEN];
                snprintf(szTry, sizeof(szTry), "docker-%s", pEntry->d_name);
                if (graph_find_node(pGraph, szTry) >= 0)
                {
                    snprintf(szPkgName, sizeof(szPkgName), "%s", szTry);
                    bFound = 1;
                }
            }

            if (!bFound)
            {
                continue;
            }

            gomod_parse_file(pGraph, szGomodPath, szPkgName, pMap);
        }
    }

    closedir(pDir);
    return 0;
}
