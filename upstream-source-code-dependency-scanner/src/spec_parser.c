#include "spec_parser.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include <dirent.h>
#include <sys/stat.h>

#pragma GCC diagnostic ignored "-Wformat-truncation"

#define MAX_MACROS        64
#define MAX_SUBPACKAGES   64
#define DIST_TAG          ".ph5"

typedef enum {
    SECTION_HEADER = 0,
    SECTION_PACKAGE,
    SECTION_DESCRIPTION,
    SECTION_PREP,
    SECTION_BUILD,
    SECTION_INSTALL,
    SECTION_CHECK,
    SECTION_CLEAN,
    SECTION_FILES,
    SECTION_CHANGELOG,
    SECTION_OTHER
} SpecSection;

typedef struct {
    char szKey[MAX_NAME_LEN];
    char szValue[MAX_LINE_LEN];
} MacroDef;

typedef struct {
    uint32_t dwNodeIdx;
    char     szSubName[MAX_NAME_LEN];
} SubPkgEntry;

typedef struct {
    DepGraph    *pGraph;
    char         szName[MAX_NAME_LEN];
    char         szVersion[MAX_VERSION_LEN];
    char         szRelease[MAX_VERSION_LEN];
    char         szEpoch[MAX_VERSION_LEN];
    char         szSpecPath[MAX_PATH_LEN];
    uint32_t     dwMainNodeIdx;
    SubPkgEntry  subPkgs[MAX_SUBPACKAGES];
    uint32_t     dwSubPkgCount;
    uint32_t     dwCurrentNodeIdx;
    SpecSection  nSection;
    MacroDef     macros[MAX_MACROS];
    uint32_t     dwMacroCount;
} ParseContext;

static void str_trim(char *psz)
{
    if (!psz || !*psz)
        return;
    /* Trim leading whitespace (single memmove) */
    char *pStart = psz;
    while (isspace((unsigned char)*pStart))
        pStart++;
    if (pStart != psz)
    {
        size_t cbLen = strlen(pStart);
        memmove(psz, pStart, cbLen + 1);
    }
    /* Trim trailing whitespace */
    size_t cbLen = strlen(psz);
    while (cbLen > 0 && isspace((unsigned char)psz[cbLen - 1]))
        psz[--cbLen] = '\0';
}

static void expand_macros(ParseContext *pCtx, char *pszBuf, size_t cbBuf)
{
    char szTmp[MAX_LINE_LEN];
    int nIter = 0;
    int bChanged = 1;

    while (bChanged && nIter < 16)
    {
        bChanged = 0;
        nIter++;
        char *pPos = pszBuf;
        char *pOut = szTmp;
        char *pOutEnd = szTmp + sizeof(szTmp) - 1;

        while (*pPos && pOut < pOutEnd)
        {
            if (pPos[0] == '%' && pPos[1] == '{')
            {
                char *pClose = strchr(pPos + 2, '}');
                if (pClose)
                {
                    char szMacro[MAX_NAME_LEN];
                    size_t cbMacro = (size_t)(pClose - pPos - 2);
                    if (cbMacro >= MAX_NAME_LEN)
                        cbMacro = MAX_NAME_LEN - 1;

                    memcpy(szMacro, pPos + 2, cbMacro);
                    szMacro[cbMacro] = '\0';

                    /* Handle %{?macro} conditional form - strip leading ? */
                    char *pszLookup = szMacro;
                    int bConditional = 0;
                    if (pszLookup[0] == '?')
                    {
                        pszLookup++;
                        bConditional = 1;
                    }

                    const char *pszRepl = NULL;
                    if (strcmp(pszLookup, "name") == 0)
                        pszRepl = pCtx->szName;
                    else if (strcmp(pszLookup, "version") == 0)
                        pszRepl = pCtx->szVersion;
                    else if (strcmp(pszLookup, "release") == 0)
                        pszRepl = pCtx->szRelease;
                    else if (strcmp(pszLookup, "epoch") == 0)
                        pszRepl = pCtx->szEpoch;
                    else if (strcmp(pszLookup, "dist") == 0)
                        pszRepl = DIST_TAG;
                    else
                    {
                        for (uint32_t i = 0; i < pCtx->dwMacroCount; i++)
                        {
                            if (strcmp(pCtx->macros[i].szKey, pszLookup) == 0)
                            {
                                pszRepl = pCtx->macros[i].szValue;
                                break;
                            }
                        }
                    }

                    if (pszRepl)
                    {
                        size_t cbRepl = strlen(pszRepl);
                        if (pOut + cbRepl < pOutEnd)
                        {
                            memcpy(pOut, pszRepl, cbRepl);
                            pOut += cbRepl;
                        }
                        bChanged = 1;
                    }
                    else if (bConditional)
                    {
                        /* conditional macro not defined: expand to empty */
                        bChanged = 1;
                    }
                    else
                    {
                        /* unknown macro: keep as-is */
                        size_t cbOrig = (size_t)(pClose - pPos + 1);
                        if (pOut + cbOrig < pOutEnd)
                        {
                            memcpy(pOut, pPos, cbOrig);
                            pOut += cbOrig;
                        }
                    }
                    pPos = pClose + 1;
                    continue;
                }
            }
            *pOut++ = *pPos++;
        }
        *pOut = '\0';
        snprintf(pszBuf, cbBuf, "%s", szTmp);
    }
}

static ConstraintOp parse_dep_constraint(const char *pszIn,
                                         char *pszTarget, size_t cbTarget,
                                         char *pszVer, size_t cbVer)
{
    ConstraintOp nOp = CONSTRAINT_NONE;
    const char *p = pszIn;

    pszVer[0] = '\0';

    /* skip leading whitespace */
    while (isspace((unsigned char)*p))
        p++;

    /* extract target name (up to whitespace, comma, or constraint op) */
    size_t i = 0;
    while (*p && !isspace((unsigned char)*p) && *p != '>' && *p != '<' && *p != '=' && *p != ',' && i < cbTarget - 1)
        pszTarget[i++] = *p++;
    pszTarget[i] = '\0';

    /* skip whitespace */
    while (isspace((unsigned char)*p))
        p++;

    /* parse constraint operator */
    if (p[0] == '>' && p[1] == '=')      { nOp = CONSTRAINT_GE; p += 2; }
    else if (p[0] == '<' && p[1] == '=') { nOp = CONSTRAINT_LE; p += 2; }
    else if (p[0] == '>' )              { nOp = CONSTRAINT_GT; p += 1; }
    else if (p[0] == '<' )              { nOp = CONSTRAINT_LT; p += 1; }
    else if (p[0] == '=' )              { nOp = CONSTRAINT_EQ; p += 1; }

    if (nOp != CONSTRAINT_NONE)
    {
        while (isspace((unsigned char)*p))
            p++;
        i = 0;
        while (*p && !isspace((unsigned char)*p) && *p != ',' && i < cbVer - 1)
            pszVer[i++] = *p++;
        pszVer[i] = '\0';
    }

    return nOp;
}

static int is_script_section(const char *pszLine)
{
    static const char *aSections[] = {
        "%prep", "%build", "%install", "%check", "%clean",
        "%files", "%changelog", "%pre", "%post", "%preun",
        "%postun", "%pretrans", "%posttrans", "%verifyscript",
        "%triggerprein", "%triggerin", "%triggerun", "%triggerpostun",
        NULL
    };
    for (int i = 0; aSections[i]; i++)
    {
        size_t cbSec = strlen(aSections[i]);
        if (strncmp(pszLine, aSections[i], cbSec) == 0 &&
            (pszLine[cbSec] == '\0' || isspace((unsigned char)pszLine[cbSec])))
            return 1;
    }
    return 0;
}

static SpecSection classify_section(const char *pszLine)
{
    if (strncmp(pszLine, "%description", 12) == 0)  return SECTION_DESCRIPTION;
    if (strncmp(pszLine, "%prep", 5) == 0)          return SECTION_PREP;
    if (strncmp(pszLine, "%build", 6) == 0)         return SECTION_BUILD;
    if (strncmp(pszLine, "%install", 8) == 0)       return SECTION_INSTALL;
    if (strncmp(pszLine, "%check", 6) == 0)         return SECTION_CHECK;
    if (strncmp(pszLine, "%clean", 6) == 0)         return SECTION_CLEAN;
    if (strncmp(pszLine, "%files", 6) == 0)         return SECTION_FILES;
    if (strncmp(pszLine, "%changelog", 10) == 0)    return SECTION_CHANGELOG;
    if (is_script_section(pszLine))                  return SECTION_OTHER;
    return SECTION_HEADER; /* fallback */
}

static void add_macro(ParseContext *pCtx, const char *pszKey, const char *pszValue)
{
    /* update existing */
    for (uint32_t i = 0; i < pCtx->dwMacroCount; i++)
    {
        if (strcmp(pCtx->macros[i].szKey, pszKey) == 0)
        {
            snprintf(pCtx->macros[i].szValue, sizeof(pCtx->macros[i].szValue),
                     "%s", pszValue);
            return;
        }
    }
    if (pCtx->dwMacroCount < MAX_MACROS)
    {
        snprintf(pCtx->macros[pCtx->dwMacroCount].szKey,
                 sizeof(pCtx->macros[0].szKey), "%s", pszKey);
        snprintf(pCtx->macros[pCtx->dwMacroCount].szValue,
                 sizeof(pCtx->macros[0].szValue), "%s", pszValue);
        pCtx->dwMacroCount++;
    }
}

static void parse_define_line(ParseContext *pCtx, const char *pszLine)
{
    /* %define key value  or  %global key value */
    const char *p = pszLine;
    if (strncmp(p, "%define", 7) == 0)
        p += 7;
    else if (strncmp(p, "%global", 7) == 0)
        p += 7;
    else
        return;

    while (isspace((unsigned char)*p))
        p++;

    char szKey[MAX_NAME_LEN];
    size_t i = 0;
    while (*p && !isspace((unsigned char)*p) && i < MAX_NAME_LEN - 1)
        szKey[i++] = *p++;
    szKey[i] = '\0';

    while (isspace((unsigned char)*p))
        p++;

    char szVal[MAX_LINE_LEN];
    snprintf(szVal, sizeof(szVal), "%s", p);
    str_trim(szVal);

    expand_macros(pCtx, szVal, sizeof(szVal));
    add_macro(pCtx, szKey, szVal);
}

static EdgeType dep_tag_to_type(const char *pszTag)
{
    if (strncasecmp(pszTag, "BuildConflicts", 14) == 0)  return EDGE_BUILDCONFLICTS;
    if (strncasecmp(pszTag, "BuildRequires", 13) == 0)   return EDGE_BUILDREQUIRES;
    if (strncasecmp(pszTag, "OrderWithRequires", 17) == 0) return EDGE_ORDERWITH;
    if (strncasecmp(pszTag, "Requires", 8) == 0)         return EDGE_REQUIRES;
    if (strncasecmp(pszTag, "Provides", 8) == 0)         return EDGE_PROVIDES;
    if (strncasecmp(pszTag, "Conflicts", 9) == 0)        return EDGE_CONFLICTS;
    if (strncasecmp(pszTag, "Obsoletes", 9) == 0)        return EDGE_OBSOLETES;
    if (strncasecmp(pszTag, "Recommends", 10) == 0)      return EDGE_RECOMMENDS;
    if (strncasecmp(pszTag, "Suggests", 8) == 0)         return EDGE_SUGGESTS;
    if (strncasecmp(pszTag, "Supplements", 11) == 0)     return EDGE_SUPPLEMENTS;
    if (strncasecmp(pszTag, "Enhances", 8) == 0)         return EDGE_ENHANCES;
    return EDGE_TYPE_COUNT;
}

static int is_dep_tag(const char *pszLine)
{
    static const char *aTags[] = {
        "Requires:", "BuildRequires:", "Provides:", "Conflicts:",
        "Obsoletes:", "Recommends:", "Suggests:", "Supplements:",
        "Enhances:", "BuildConflicts:", "OrderWithRequires:",
        NULL
    };
    for (int i = 0; aTags[i]; i++)
    {
        if (strncasecmp(pszLine, aTags[i], strlen(aTags[i])) == 0)
            return 1;
    }
    /* Handle Requires(pre): Requires(post): etc. */
    if (strncasecmp(pszLine, "Requires(", 9) == 0)
    {
        const char *pClose = strchr(pszLine + 9, ')');
        if (pClose && pClose[1] == ':')
            return 1;
    }
    return 0;
}

static void process_dep_entry(ParseContext *pCtx, EdgeType nType,
                              const char *pszRaw, const char *pszQualifier)
{
    char szExpanded[MAX_LINE_LEN];
    snprintf(szExpanded, sizeof(szExpanded), "%s", pszRaw);
    expand_macros(pCtx, szExpanded, sizeof(szExpanded));
    str_trim(szExpanded);

    if (szExpanded[0] == '\0')
        return;

    /* skip file-path dependencies like /usr/bin/foo */
    if (szExpanded[0] == '/')
        return;

    char szTarget[MAX_NAME_LEN];
    char szVer[MAX_VERSION_LEN];
    ConstraintOp nOp = parse_dep_constraint(szExpanded, szTarget,
                                            sizeof(szTarget),
                                            szVer, sizeof(szVer));

    if (szTarget[0] == '\0')
        return;

    /* For Provides, register a virtual provide */
    if (nType == EDGE_PROVIDES)
    {
        graph_add_virtual(pCtx->pGraph, szTarget, szVer,
                          pCtx->dwCurrentNodeIdx, EDGE_SRC_SPEC, szExpanded);
    }

    int32_t nToIdx = graph_find_node(pCtx->pGraph, szTarget);
    uint32_t dwTo = (nToIdx >= 0) ? (uint32_t)nToIdx : UINT32_MAX;

    int nRc = graph_add_edge(pCtx->pGraph, pCtx->dwCurrentNodeIdx, dwTo,
                             nType, EDGE_SRC_SPEC, nOp, szVer, szExpanded, szTarget);

    /* Store the qualifier on the newly added edge */
    if (nRc == 0 && pszQualifier && pszQualifier[0] &&
        pCtx->pGraph->dwEdgeCount > 0)
    {
        GraphEdge *pEdge = &pCtx->pGraph->pEdges[pCtx->pGraph->dwEdgeCount - 1];
        snprintf(pEdge->szQualifier, sizeof(pEdge->szQualifier),
                 "%s", pszQualifier);
    }
}

static void process_dep_line(ParseContext *pCtx, const char *pszLine)
{
    /* Find the tag and value */
    const char *pColon = strchr(pszLine, ':');
    if (!pColon)
        return;

    /* Determine edge type from tag */
    char szTag[MAX_NAME_LEN];
    size_t cbTag = (size_t)(pColon - pszLine);
    if (cbTag >= MAX_NAME_LEN)
        cbTag = MAX_NAME_LEN - 1;
    memcpy(szTag, pszLine, cbTag);
    szTag[cbTag] = '\0';

    /* Extract qualifier from Requires(qualifier) before stripping */
    char szQualifier[MAX_QUALIFIER_LEN];
    szQualifier[0] = '\0';
    char *pParen = strchr(szTag, '(');
    if (pParen)
    {
        char *pClose = strchr(pParen + 1, ')');
        if (pClose)
        {
            size_t cbQual = (size_t)(pClose - pParen - 1);
            if (cbQual >= MAX_QUALIFIER_LEN)
                cbQual = MAX_QUALIFIER_LEN - 1;
            memcpy(szQualifier, pParen + 1, cbQual);
            szQualifier[cbQual] = '\0';
        }
        *pParen = '\0';
    }

    EdgeType nType = dep_tag_to_type(szTag);
    if (nType == EDGE_TYPE_COUNT)
        return;

    const char *pszVal = pColon + 1;
    while (isspace((unsigned char)*pszVal))
        pszVal++;

    /* Split comma or whitespace-separated dep entries.
       Entries may have version constraints: "foo >= 1.0, bar" */
    char szBuf[MAX_LINE_LEN];
    snprintf(szBuf, sizeof(szBuf), "%s", pszVal);

    char *pSave = NULL;
    char *pTok = strtok_r(szBuf, ",", &pSave);
    while (pTok)
    {
        str_trim(pTok);
        if (pTok[0] != '\0')
            process_dep_entry(pCtx, nType, pTok, szQualifier);
        pTok = strtok_r(NULL, ",", &pSave);
    }
}

static void handle_package_directive(ParseContext *pCtx, const char *pszLine)
{
    const char *p = pszLine + 8; /* skip "%package" */
    while (isspace((unsigned char)*p))
        p++;

    char szSubName[MAX_NAME_LEN];

    if (strncmp(p, "-n", 2) == 0 && (isspace((unsigned char)p[2]) || p[2] == '\0'))
    {
        p += 2;
        while (isspace((unsigned char)*p))
            p++;
        snprintf(szSubName, sizeof(szSubName), "%s", p);
    }
    else
    {
        snprintf(szSubName, sizeof(szSubName), "%s-%s", pCtx->szName, p);
    }
    str_trim(szSubName);

    /* Expand macros in subpackage name */
    expand_macros(pCtx, szSubName, sizeof(szSubName));

    uint32_t dwIdx = graph_add_node(pCtx->pGraph, szSubName,
                                    pCtx->szVersion, pCtx->szRelease,
                                    pCtx->szEpoch, pCtx->szSpecPath,
                                    pCtx->szName);

    pCtx->dwCurrentNodeIdx = dwIdx;
    pCtx->nSection = SECTION_PACKAGE;

    if (pCtx->dwSubPkgCount < MAX_SUBPACKAGES)
    {
        pCtx->subPkgs[pCtx->dwSubPkgCount].dwNodeIdx = dwIdx;
        snprintf(pCtx->subPkgs[pCtx->dwSubPkgCount].szSubName,
                 sizeof(pCtx->subPkgs[0].szSubName), "%s", szSubName);
        pCtx->dwSubPkgCount++;
    }
}

static void parse_header_field(ParseContext *pCtx, const char *pszLine)
{
    char szExpanded[MAX_LINE_LEN];

    if (strncasecmp(pszLine, "Name:", 5) == 0)
    {
        snprintf(szExpanded, sizeof(szExpanded), "%s", pszLine + 5);
        str_trim(szExpanded);
        expand_macros(pCtx, szExpanded, sizeof(szExpanded));
        snprintf(pCtx->szName, sizeof(pCtx->szName), "%s", szExpanded);
    }
    else if (strncasecmp(pszLine, "Version:", 8) == 0)
    {
        snprintf(szExpanded, sizeof(szExpanded), "%s", pszLine + 8);
        str_trim(szExpanded);
        expand_macros(pCtx, szExpanded, sizeof(szExpanded));
        snprintf(pCtx->szVersion, sizeof(pCtx->szVersion), "%s", szExpanded);
    }
    else if (strncasecmp(pszLine, "Release:", 8) == 0)
    {
        snprintf(szExpanded, sizeof(szExpanded), "%s", pszLine + 8);
        str_trim(szExpanded);
        expand_macros(pCtx, szExpanded, sizeof(szExpanded));
        snprintf(pCtx->szRelease, sizeof(pCtx->szRelease), "%s", szExpanded);
    }
    else if (strncasecmp(pszLine, "Epoch:", 6) == 0)
    {
        snprintf(szExpanded, sizeof(szExpanded), "%s", pszLine + 6);
        str_trim(szExpanded);
        expand_macros(pCtx, szExpanded, sizeof(szExpanded));
        snprintf(pCtx->szEpoch, sizeof(pCtx->szEpoch), "%s", szExpanded);
    }

    /* Architecture/OS exclusion directives -- store on current node */
    if (pCtx->dwCurrentNodeIdx != UINT32_MAX &&
        pCtx->dwCurrentNodeIdx < pCtx->pGraph->dwNodeCount)
    {
        GraphNode *pNode = &pCtx->pGraph->pNodes[pCtx->dwCurrentNodeIdx];

        if (strncasecmp(pszLine, "ExcludeArch:", 12) == 0)
        {
            snprintf(szExpanded, sizeof(szExpanded), "%s", pszLine + 12);
            str_trim(szExpanded);
            expand_macros(pCtx, szExpanded, sizeof(szExpanded));
            snprintf(pNode->szExcludeArch, sizeof(pNode->szExcludeArch),
                     "%s", szExpanded);
        }
        else if (strncasecmp(pszLine, "ExclusiveArch:", 14) == 0)
        {
            snprintf(szExpanded, sizeof(szExpanded), "%s", pszLine + 14);
            str_trim(szExpanded);
            expand_macros(pCtx, szExpanded, sizeof(szExpanded));
            snprintf(pNode->szExclusiveArch, sizeof(pNode->szExclusiveArch),
                     "%s", szExpanded);
        }
        else if (strncasecmp(pszLine, "ExcludeOS:", 10) == 0)
        {
            snprintf(szExpanded, sizeof(szExpanded), "%s", pszLine + 10);
            str_trim(szExpanded);
            expand_macros(pCtx, szExpanded, sizeof(szExpanded));
            snprintf(pNode->szExcludeOS, sizeof(pNode->szExcludeOS),
                     "%s", szExpanded);
        }
        else if (strncasecmp(pszLine, "ExclusiveOS:", 12) == 0)
        {
            snprintf(szExpanded, sizeof(szExpanded), "%s", pszLine + 12);
            str_trim(szExpanded);
            expand_macros(pCtx, szExpanded, sizeof(szExpanded));
            snprintf(pNode->szExclusiveOS, sizeof(pNode->szExclusiveOS),
                     "%s", szExpanded);
        }
        else if (strncasecmp(pszLine, "BuildArch:", 10) == 0 ||
                 strncasecmp(pszLine, "BuildArchitectures:", 19) == 0)
        {
            const char *pVal = strchr(pszLine, ':');
            if (pVal)
            {
                pVal++;
                snprintf(szExpanded, sizeof(szExpanded), "%s", pVal);
                str_trim(szExpanded);
                expand_macros(pCtx, szExpanded, sizeof(szExpanded));
                snprintf(pNode->szBuildArch, sizeof(pNode->szBuildArch),
                         "%s", szExpanded);
            }
        }
    }
}

int spec_parse_file(DepGraph *pGraph, const char *pszSpecPath)
{
    FILE *fp = fopen(pszSpecPath, "r");
    if (!fp)
        return -1;

    ParseContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.pGraph = pGraph;
    ctx.nSection = SECTION_HEADER;
    ctx.dwMainNodeIdx = UINT32_MAX;
    ctx.dwCurrentNodeIdx = UINT32_MAX;
    snprintf(ctx.szSpecPath, sizeof(ctx.szSpecPath), "%s", pszSpecPath);

    char szLine[MAX_LINE_LEN];
    char szAccum[MAX_LINE_LEN];
    szAccum[0] = '\0';
    int bContinuation = 0;
    int bMainNodeCreated = 0;

    while (fgets(szLine, sizeof(szLine), fp))
    {
        /* Strip trailing newline/CR */
        size_t cbLine = strlen(szLine);
        while (cbLine > 0 && (szLine[cbLine - 1] == '\n' || szLine[cbLine - 1] == '\r'))
            szLine[--cbLine] = '\0';

        /* Handle line continuation */
        if (bContinuation)
        {
            /* strip leading whitespace of continuation */
            char *pCont = szLine;
            while (isspace((unsigned char)*pCont))
                pCont++;

            size_t cbAccum = strlen(szAccum);
            snprintf(szAccum + cbAccum, sizeof(szAccum) - cbAccum, " %s", pCont);

            if (cbLine > 0 && szLine[cbLine - 1] == '\\')
            {
                szAccum[strlen(szAccum) - 1] = '\0';
                continue;
            }
            bContinuation = 0;
            snprintf(szLine, sizeof(szLine), "%s", szAccum);
            szAccum[0] = '\0';
            cbLine = strlen(szLine);
        }
        else if (cbLine > 0 && szLine[cbLine - 1] == '\\')
        {
            szLine[cbLine - 1] = '\0';
            snprintf(szAccum, sizeof(szAccum), "%s", szLine);
            bContinuation = 1;
            continue;
        }

        /* Skip empty lines */
        char *pTrimmed = szLine;
        while (isspace((unsigned char)*pTrimmed))
            pTrimmed++;
        if (*pTrimmed == '\0')
            continue;

        /* Skip comments */
        if (*pTrimmed == '#')
            continue;

        /* Handle %define / %global anywhere */
        if (strncmp(pTrimmed, "%define", 7) == 0 || strncmp(pTrimmed, "%global", 7) == 0)
        {
            parse_define_line(&ctx, pTrimmed);
            continue;
        }

        /* Handle section transitions */
        if (pTrimmed[0] == '%')
        {
            if (strncmp(pTrimmed, "%package", 8) == 0 &&
                (isspace((unsigned char)pTrimmed[8]) || pTrimmed[8] == '\0'))
            {
                /* Before processing subpackage, ensure main node exists */
                if (!bMainNodeCreated && ctx.szName[0] != '\0')
                {
                    ctx.dwMainNodeIdx = graph_add_node(
                        pGraph, ctx.szName, ctx.szVersion, ctx.szRelease,
                        ctx.szEpoch, ctx.szSpecPath, "");
                    ctx.dwCurrentNodeIdx = ctx.dwMainNodeIdx;
                    bMainNodeCreated = 1;
                }
                handle_package_directive(&ctx, pTrimmed);
                continue;
            }

            if (strncmp(pTrimmed, "%description", 12) == 0 ||
                is_script_section(pTrimmed))
            {
                ctx.nSection = classify_section(pTrimmed);
                continue;
            }

            /* %include and other directives: skip */
            if (strncmp(pTrimmed, "%include", 8) == 0 ||
                strncmp(pTrimmed, "%if", 3) == 0 ||
                strncmp(pTrimmed, "%else", 5) == 0 ||
                strncmp(pTrimmed, "%endif", 6) == 0 ||
                strncmp(pTrimmed, "%attr", 5) == 0 ||
                strncmp(pTrimmed, "%dir", 4) == 0 ||
                strncmp(pTrimmed, "%doc", 4) == 0 ||
                strncmp(pTrimmed, "%license", 8) == 0 ||
                strncmp(pTrimmed, "%config", 7) == 0 ||
                strncmp(pTrimmed, "%defattr", 8) == 0 ||
                strncmp(pTrimmed, "%ghost", 6) == 0)
            {
                continue;
            }
        }

        /* In non-parseable sections, skip lines */
        if (ctx.nSection == SECTION_PREP ||
            ctx.nSection == SECTION_BUILD ||
            ctx.nSection == SECTION_INSTALL ||
            ctx.nSection == SECTION_CHECK ||
            ctx.nSection == SECTION_CLEAN ||
            ctx.nSection == SECTION_FILES ||
            ctx.nSection == SECTION_CHANGELOG ||
            ctx.nSection == SECTION_OTHER ||
            ctx.nSection == SECTION_DESCRIPTION)
        {
            continue;
        }

        /* In header or package section: parse header fields and deps */
        if (ctx.nSection == SECTION_HEADER)
        {
            parse_header_field(&ctx, pTrimmed);

            /* Once we have Name, create the main node */
            if (!bMainNodeCreated && ctx.szName[0] != '\0')
            {
                ctx.dwMainNodeIdx = graph_add_node(
                    pGraph, ctx.szName, ctx.szVersion, ctx.szRelease,
                    ctx.szEpoch, ctx.szSpecPath, "");
                ctx.dwCurrentNodeIdx = ctx.dwMainNodeIdx;
                bMainNodeCreated = 1;
            }

            /* Backfill version/release if node was created before those fields */
            if (bMainNodeCreated && ctx.dwMainNodeIdx < pGraph->dwNodeCount)
            {
                GraphNode *pN = &pGraph->pNodes[ctx.dwMainNodeIdx];
                if (!pN->szVersion[0] && ctx.szVersion[0])
                {
                    snprintf(pN->szVersion, sizeof(pN->szVersion),
                             "%s", ctx.szVersion);
                }
                if (!pN->szRelease[0] && ctx.szRelease[0])
                {
                    snprintf(pN->szRelease, sizeof(pN->szRelease),
                             "%s", ctx.szRelease);
                }
                if (!pN->szEpoch[0] && ctx.szEpoch[0])
                {
                    snprintf(pN->szEpoch, sizeof(pN->szEpoch),
                             "%s", ctx.szEpoch);
                }
            }
        }

        /* Parse dependency tags in header or package sections */
        if ((ctx.nSection == SECTION_HEADER || ctx.nSection == SECTION_PACKAGE) &&
            ctx.dwCurrentNodeIdx != UINT32_MAX &&
            is_dep_tag(pTrimmed))
        {
            process_dep_line(&ctx, pTrimmed);
        }
    }

    /* If we never created the main node (no Name:) skip */
    if (!bMainNodeCreated && ctx.szName[0] != '\0')
    {
        ctx.dwMainNodeIdx = graph_add_node(
            pGraph, ctx.szName, ctx.szVersion, ctx.szRelease,
            ctx.szEpoch, ctx.szSpecPath, "");
    }

    fclose(fp);
    return 0;
}

int spec_parse_directory(DepGraph *pGraph, const char *pszSpecsDir)
{
    DIR *pDir = opendir(pszSpecsDir);
    if (!pDir)
        return -1;

    struct dirent *pEntry;
    while ((pEntry = readdir(pDir)) != NULL)
    {
        if (pEntry->d_name[0] == '.')
            continue;

        char szSubDir[MAX_PATH_LEN];
        snprintf(szSubDir, sizeof(szSubDir), "%s/%s", pszSpecsDir, pEntry->d_name);

        struct stat st;
        if (stat(szSubDir, &st) != 0 || !S_ISDIR(st.st_mode))
            continue;

        /* Scan subdirectory for .spec files */
        DIR *pSub = opendir(szSubDir);
        if (!pSub)
            continue;

        struct dirent *pSubEntry;
        while ((pSubEntry = readdir(pSub)) != NULL)
        {
            size_t cbName = strlen(pSubEntry->d_name);
            if (cbName < 6)
                continue;
            if (strcmp(pSubEntry->d_name + cbName - 5, ".spec") != 0)
                continue;

            char szSpecPath[MAX_PATH_LEN];
            snprintf(szSpecPath, sizeof(szSpecPath), "%s/%s",
                     szSubDir, pSubEntry->d_name);

            struct stat stFile;
            if (stat(szSpecPath, &stFile) != 0 || !S_ISREG(stFile.st_mode))
                continue;

            spec_parse_file(pGraph, szSpecPath);
        }
        closedir(pSub);
    }

    closedir(pDir);
    return 0;
}
