#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <ctype.h>
#include <sys/stat.h>

#include "pyproject_analyzer.h"

static void
_strip_trailing_whitespace(char *psz)
{
    size_t n = strlen(psz);
    while (n > 0 && (psz[n - 1] == '\n' || psz[n - 1] == '\r' ||
                     psz[n - 1] == ' '  || psz[n - 1] == '\t'))
    {
        psz[--n] = '\0';
    }
}

/* Extract bare package name from a Python dependency string like
   "requests>=2.0", "six", "PyYAML!=3.0,>=2.0". Writes into pszOut. */
static void
_extract_dep_name(const char *pszRaw, char *pszOut, size_t nMax)
{
    size_t i = 0;
    const char *p = pszRaw;

    /* skip leading whitespace and quotes */
    while (*p && (isspace((unsigned char)*p) || *p == '\'' || *p == '"'))
        p++;

    while (*p && i < nMax - 1)
    {
        if (*p == '>' || *p == '<' || *p == '=' || *p == '!' ||
            *p == ';' || *p == '[' || *p == '\'' || *p == '"' ||
            *p == ',' || *p == ' ' || *p == '\t')
            break;
        pszOut[i++] = (char)tolower((unsigned char)*p);
        p++;
    }
    pszOut[i] = '\0';

    /* normalise: replace _ with - */
    for (i = 0; pszOut[i]; i++)
    {
        if (pszOut[i] == '_')
            pszOut[i] = '-';
    }
}

/* Try to find a Photon node matching a Python dependency name. */
static int32_t
_find_python_node(DepGraph *pGraph, const char *pszDepName)
{
    int32_t idx;
    char szBuf[MAX_NAME_LEN];

    idx = graph_find_node(pGraph, pszDepName);
    if (idx >= 0)
        return idx;

    snprintf(szBuf, sizeof(szBuf), "python3-%s", pszDepName);
    idx = graph_find_node(pGraph, szBuf);
    if (idx >= 0)
        return idx;

    snprintf(szBuf, sizeof(szBuf), "python-%s", pszDepName);
    idx = graph_find_node(pGraph, szBuf);
    if (idx >= 0)
        return idx;

    /* try with underscores replaced by hyphens (already done) and vice-versa */
    {
        char szAlt[MAX_NAME_LEN];
        size_t i;
        snprintf(szAlt, sizeof(szAlt), "%s", pszDepName);
        for (i = 0; szAlt[i]; i++)
        {
            if (szAlt[i] == '-')
                szAlt[i] = '_';
        }
        snprintf(szBuf, sizeof(szBuf), "python3-%s", szAlt);
        idx = graph_find_node(pGraph, szBuf);
        if (idx >= 0)
            return idx;
    }

    return -1;
}

static void
_add_python_dep(DepGraph *pGraph, const char *pszPkgName,
                const char *pszDepRaw)
{
    char szDep[MAX_NAME_LEN];
    int32_t nFrom, nTo;
    char szEvidence[MAX_EVIDENCE_LEN];

    _extract_dep_name(pszDepRaw, szDep, sizeof(szDep));
    if (szDep[0] == '\0')
        return;

    nFrom = graph_find_node(pGraph, pszPkgName);
    if (nFrom < 0)
        return;

    nTo = _find_python_node(pGraph, szDep);
    if (nTo < 0 || nTo == nFrom)
        return;

    snprintf(szEvidence, sizeof(szEvidence), "pyproject: %s", pszDepRaw);
    graph_add_edge(pGraph, (uint32_t)nFrom, (uint32_t)nTo,
                   EDGE_REQUIRES, EDGE_SRC_PYPROJECT,
                   CONSTRAINT_NONE, "", szEvidence, szDep);
}

static int
_parse_setup_cfg(DepGraph *pGraph, const char *pszPath,
                 const char *pszPackageName)
{
    FILE *fp;
    char szLine[MAX_LINE_LEN];
    int bInOptions = 0;
    int bInInstallRequires = 0;

    fp = fopen(pszPath, "r");
    if (!fp)
        return -1;

    while (fgets(szLine, sizeof(szLine), fp))
    {
        _strip_trailing_whitespace(szLine);

        if (szLine[0] == '[')
        {
            bInOptions = (strstr(szLine, "[options]") != NULL) ? 1 : 0;
            bInInstallRequires = 0;
            continue;
        }

        if (bInOptions && !bInInstallRequires)
        {
            if (strncmp(szLine, "install_requires", 16) == 0)
            {
                char *eq = strchr(szLine, '=');
                if (eq)
                {
                    bInInstallRequires = 1;
                    eq++;
                    while (*eq && isspace((unsigned char)*eq))
                        eq++;
                    if (*eq)
                        _add_python_dep(pGraph, pszPackageName, eq);
                }
            }
            continue;
        }

        if (bInOptions && bInInstallRequires)
        {
            if (szLine[0] != ' ' && szLine[0] != '\t')
            {
                bInInstallRequires = 0;
                if (szLine[0] == '[')
                {
                    bInOptions = 0;
                }
                continue;
            }
            _add_python_dep(pGraph, pszPackageName, szLine);
        }
    }

    fclose(fp);
    return 0;
}

static int
_parse_setup_py(DepGraph *pGraph, const char *pszPath,
                const char *pszPackageName)
{
    FILE *fp;
    char *pBuf;
    long nLen;
    char *pStart, *p;

    fp = fopen(pszPath, "r");
    if (!fp)
        return -1;

    fseek(fp, 0, SEEK_END);
    nLen = ftell(fp);
    fseek(fp, 0, SEEK_SET);

    if (nLen <= 0 || nLen > 1024 * 1024)
    {
        fclose(fp);
        return -1;
    }

    pBuf = (char *)malloc((size_t)nLen + 1);
    if (!pBuf)
    {
        fclose(fp);
        return -1;
    }
    fread(pBuf, 1, (size_t)nLen, fp);
    pBuf[nLen] = '\0';
    fclose(fp);

    pStart = strstr(pBuf, "install_requires");
    if (!pStart)
    {
        free(pBuf);
        return 0;
    }

    /* find the opening bracket */
    p = strchr(pStart, '[');
    if (!p)
    {
        free(pBuf);
        return 0;
    }
    p++;

    /* extract quoted strings until closing bracket */
    while (*p && *p != ']')
    {
        if (*p == '\'' || *p == '"')
        {
            char cQuote = *p;
            char szDep[MAX_LINE_LEN];
            size_t i = 0;
            p++;
            while (*p && *p != cQuote && i < sizeof(szDep) - 1)
                szDep[i++] = *p++;
            szDep[i] = '\0';
            if (*p == cQuote)
                p++;
            _add_python_dep(pGraph, pszPackageName, szDep);
        }
        else
        {
            p++;
        }
    }

    free(pBuf);
    return 0;
}

static int
_parse_pyproject_toml(DepGraph *pGraph, const char *pszPath,
                      const char *pszPackageName)
{
    FILE *fp;
    char szLine[MAX_LINE_LEN];
    int bInProject = 0;
    int bInDeps = 0;

    fp = fopen(pszPath, "r");
    if (!fp)
        return -1;

    while (fgets(szLine, sizeof(szLine), fp))
    {
        _strip_trailing_whitespace(szLine);

        if (szLine[0] == '[')
        {
            if (strcmp(szLine, "[project]") == 0)
            {
                bInProject = 1;
                bInDeps = 0;
            }
            else
            {
                if (bInProject)
                    bInProject = 0;
                bInDeps = 0;
            }
            continue;
        }

        if (bInProject && !bInDeps)
        {
            if (strncmp(szLine, "dependencies", 12) == 0)
            {
                char *bracket = strchr(szLine, '[');
                if (bracket)
                {
                    bInDeps = 1;
                    /* check if closing bracket on same line */
                    if (strchr(bracket, ']'))
                    {
                        /* inline list - extract quoted strings */
                        char *q = bracket;
                        while (*q && *q != ']')
                        {
                            if (*q == '"' || *q == '\'')
                            {
                                char cQ = *q;
                                char szDep[MAX_LINE_LEN];
                                size_t i = 0;
                                q++;
                                while (*q && *q != cQ && i < sizeof(szDep) - 1)
                                    szDep[i++] = *q++;
                                szDep[i] = '\0';
                                if (*q == cQ)
                                    q++;
                                _add_python_dep(pGraph, pszPackageName, szDep);
                            }
                            else
                            {
                                q++;
                            }
                        }
                        bInDeps = 0;
                    }
                }
            }
            continue;
        }

        if (bInDeps)
        {
            if (strchr(szLine, ']'))
            {
                /* extract any remaining quoted string before ] */
                char *q = szLine;
                while (*q && *q != ']')
                {
                    if (*q == '"' || *q == '\'')
                    {
                        char cQ = *q;
                        char szDep[MAX_LINE_LEN];
                        size_t i = 0;
                        q++;
                        while (*q && *q != cQ && i < sizeof(szDep) - 1)
                            szDep[i++] = *q++;
                        szDep[i] = '\0';
                        if (*q == cQ)
                            q++;
                        _add_python_dep(pGraph, pszPackageName, szDep);
                    }
                    else
                    {
                        q++;
                    }
                }
                bInDeps = 0;
                continue;
            }

            /* extract quoted string from continuation line */
            {
                char *q = szLine;
                while (*q)
                {
                    if (*q == '"' || *q == '\'')
                    {
                        char cQ = *q;
                        char szDep[MAX_LINE_LEN];
                        size_t i = 0;
                        q++;
                        while (*q && *q != cQ && i < sizeof(szDep) - 1)
                            szDep[i++] = *q++;
                        szDep[i] = '\0';
                        if (*q == cQ)
                            q++;
                        _add_python_dep(pGraph, pszPackageName, szDep);
                    }
                    else
                    {
                        q++;
                    }
                }
            }
        }
    }

    fclose(fp);
    return 0;
}

int
pyproject_parse_project(DepGraph *pGraph, const char *pszProjectDir,
                        const char *pszPackageName)
{
    char szPath[MAX_PATH_LEN];
    struct stat st;

    snprintf(szPath, sizeof(szPath), "%s/setup.cfg", pszProjectDir);
    if (stat(szPath, &st) == 0)
        return _parse_setup_cfg(pGraph, szPath, pszPackageName);

    snprintf(szPath, sizeof(szPath), "%s/setup.py", pszProjectDir);
    if (stat(szPath, &st) == 0)
        return _parse_setup_py(pGraph, szPath, pszPackageName);

    snprintf(szPath, sizeof(szPath), "%s/pyproject.toml", pszProjectDir);
    if (stat(szPath, &st) == 0)
        return _parse_pyproject_toml(pGraph, szPath, pszPackageName);

    return 0;
}

int
pyproject_analyze_clones(DepGraph *pGraph, const char *pszClonesDir)
{
    DIR *pDir;
    struct dirent *pEntry;
    char szSubDir[MAX_PATH_LEN];
    struct stat st;
    int32_t nIdx;
    int nResult = 0;

    pDir = opendir(pszClonesDir);
    if (!pDir)
    {
        fprintf(stderr, "pyproject: cannot open clones dir: %s\n",
                pszClonesDir);
        return -1;
    }

    while ((pEntry = readdir(pDir)) != NULL)
    {
        if (pEntry->d_name[0] == '.')
            continue;

        snprintf(szSubDir, sizeof(szSubDir), "%s/%s",
                 pszClonesDir, pEntry->d_name);
        if (stat(szSubDir, &st) != 0 || !S_ISDIR(st.st_mode))
            continue;

        /* Map clone dir name to Photon package */
        nIdx = graph_find_node(pGraph, pEntry->d_name);
        if (nIdx < 0)
        {
            char szPrefixed[MAX_NAME_LEN];
            snprintf(szPrefixed, sizeof(szPrefixed), "python3-%s",
                     pEntry->d_name);
            nIdx = graph_find_node(pGraph, szPrefixed);
        }
        if (nIdx < 0)
        {
            char szPrefixed[MAX_NAME_LEN];
            snprintf(szPrefixed, sizeof(szPrefixed), "python-%s",
                     pEntry->d_name);
            nIdx = graph_find_node(pGraph, szPrefixed);
        }
        if (nIdx < 0)
            continue;

        pyproject_parse_project(pGraph, szSubDir,
                                pGraph->pNodes[nIdx].szName);
    }

    closedir(pDir);
    return nResult;
}
