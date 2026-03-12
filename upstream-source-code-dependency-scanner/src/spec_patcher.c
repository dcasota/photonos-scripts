#include "spec_patcher.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include <time.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
#include <libgen.h>

#pragma GCC diagnostic ignored "-Wformat-truncation"

#define INITIAL_LINE_CAP 4096

static int
mkdir_p(const char *pszPath, mode_t mode)
{
    char szBuf[MAX_PATH_LEN];
    size_t cbLen;

    snprintf(szBuf, sizeof(szBuf), "%s", pszPath);
    cbLen = strlen(szBuf);

    /* Strip trailing slash */
    if (cbLen > 1 && szBuf[cbLen - 1] == '/')
    {
        szBuf[cbLen - 1] = '\0';
    }

    for (char *p = szBuf + 1; *p; p++)
    {
        if (*p == '/')
        {
            *p = '\0';
            if (mkdir(szBuf, mode) != 0 && errno != EEXIST)
            {
                return -1;
            }
            *p = '/';
        }
    }

    if (mkdir(szBuf, mode) != 0 && errno != EEXIST)
    {
        return -1;
    }

    return 0;
}

static char **
read_lines(const char *pszPath, uint32_t *pdwCount)
{
    FILE *fp = fopen(pszPath, "r");
    if (!fp)
    {
        return NULL;
    }

    uint32_t dwCap = INITIAL_LINE_CAP;
    uint32_t dwCount = 0;
    char **ppLines = calloc(dwCap, sizeof(char *));
    if (!ppLines)
    {
        fclose(fp);
        return NULL;
    }

    char szLine[MAX_LINE_LEN];
    while (fgets(szLine, sizeof(szLine), fp))
    {
        if (dwCount >= dwCap)
        {
            dwCap *= 2;
            char **ppNew = realloc(ppLines, dwCap * sizeof(char *));
            if (!ppNew)
            {
                for (uint32_t i = 0; i < dwCount; i++)
                {
                    free(ppLines[i]);
                }
                free(ppLines);
                fclose(fp);
                return NULL;
            }
            ppLines = ppNew;
        }
        ppLines[dwCount] = strdup(szLine);
        if (!ppLines[dwCount])
        {
            for (uint32_t i = 0; i < dwCount; i++)
            {
                free(ppLines[i]);
            }
            free(ppLines);
            fclose(fp);
            return NULL;
        }
        dwCount++;
    }

    fclose(fp);
    *pdwCount = dwCount;
    return ppLines;
}

static void
free_lines(char **ppLines, uint32_t dwCount)
{
    if (!ppLines)
    {
        return;
    }
    for (uint32_t i = 0; i < dwCount; i++)
    {
        free(ppLines[i]);
    }
    free(ppLines);
}

static int
write_lines(const char *pszPath, char **ppLines, uint32_t dwCount)
{
    FILE *fp = fopen(pszPath, "w");
    if (!fp)
    {
        return -1;
    }

    for (uint32_t i = 0; i < dwCount; i++)
    {
        fputs(ppLines[i], fp);
    }

    fclose(fp);
    return 0;
}

/*
 * Check if a line starts a section header (%package, %description, etc.)
 * and extract the section name for %package lines.
 */
static int
is_section_header(const char *pszLine)
{
    if (pszLine[0] != '%')
    {
        return 0;
    }
    if (strncasecmp(pszLine, "%package", 8) == 0 ||
        strncasecmp(pszLine, "%description", 12) == 0 ||
        strncasecmp(pszLine, "%prep", 5) == 0 ||
        strncasecmp(pszLine, "%build", 6) == 0 ||
        strncasecmp(pszLine, "%install", 8) == 0 ||
        strncasecmp(pszLine, "%check", 6) == 0 ||
        strncasecmp(pszLine, "%clean", 6) == 0 ||
        strncasecmp(pszLine, "%files", 6) == 0 ||
        strncasecmp(pszLine, "%changelog", 10) == 0)
    {
        return 1;
    }
    return 0;
}

/*
 * Check whether a section line (%package or %description) matches a
 * given section identifier.  An empty szSection matches the main package
 * (header area / no subpackage qualifier).
 */
static int
section_matches(const char *pszLine, const char *pszKeyword,
                const char *pszSection)
{
    size_t cbKey = strlen(pszKeyword);

    if (strncasecmp(pszLine, pszKeyword, cbKey) != 0)
    {
        return 0;
    }

    const char *pRest = pszLine + cbKey;

    /* Skip whitespace */
    while (*pRest && isspace((unsigned char)*pRest))
    {
        pRest++;
    }

    /* Skip optional flags like -n */
    while (*pRest == '-' && isalpha((unsigned char)*(pRest + 1)))
    {
        pRest++;
        while (*pRest && !isspace((unsigned char)*pRest))
        {
            pRest++;
        }
        while (*pRest && isspace((unsigned char)*pRest))
        {
            pRest++;
        }
    }

    /* Trim trailing whitespace/newline from rest */
    char szRest[MAX_SECTION_LEN];
    snprintf(szRest, sizeof(szRest), "%s", pRest);
    char *pEnd = szRest + strlen(szRest) - 1;
    while (pEnd >= szRest && isspace((unsigned char)*pEnd))
    {
        *pEnd-- = '\0';
    }

    if (!pszSection || pszSection[0] == '\0')
    {
        /* Main package: rest should be empty */
        return (szRest[0] == '\0') ? 1 : 0;
    }

    return (strcasecmp(szRest, pszSection) == 0) ? 1 : 0;
}

/*
 * Find the insertion line for a directive in a given section.
 * Returns the line index *after which* to insert (0-based).
 * If not found, returns -1.
 */
static int32_t
find_insertion_point(char **ppLines, uint32_t dwCount,
                     const char *pszSection, const char *pszDirective)
{
    int bIsRequires = (strcasecmp(pszDirective, "Requires") == 0 ||
                       strcasecmp(pszDirective, "BuildRequires") == 0 ||
                       strcasecmp(pszDirective, "OrderWithRequires") == 0);
    int bIsProvides = (strcasecmp(pszDirective, "Provides") == 0);
    int bIsConflicts = (strcasecmp(pszDirective, "Conflicts") == 0 ||
                        strcasecmp(pszDirective, "BuildConflicts") == 0);

    /* Determine section boundaries */
    int32_t dwSectionStart = -1;
    int32_t dwSectionEnd = -1;

    if (!pszSection || pszSection[0] == '\0')
    {
        /* Main package: from line 0 until the first %package, %prep,
           %build, %install, %check, %files, %changelog, or %description
           that isn't the main one. Actually the header runs until the
           first section macro. */
        dwSectionStart = 0;
        for (uint32_t i = 0; i < dwCount; i++)
        {
            if (ppLines[i][0] == '%' &&
                (strncasecmp(ppLines[i], "%package", 8) == 0 ||
                 strncasecmp(ppLines[i], "%prep", 5) == 0 ||
                 strncasecmp(ppLines[i], "%build", 6) == 0 ||
                 strncasecmp(ppLines[i], "%install", 8) == 0 ||
                 strncasecmp(ppLines[i], "%check", 6) == 0 ||
                 strncasecmp(ppLines[i], "%clean", 6) == 0 ||
                 strncasecmp(ppLines[i], "%files", 6) == 0 ||
                 strncasecmp(ppLines[i], "%changelog", 10) == 0))
            {
                dwSectionEnd = (int32_t)i;
                break;
            }
        }
        if (dwSectionEnd < 0)
        {
            dwSectionEnd = (int32_t)dwCount;
        }
    }
    else
    {
        /* Subpackage section: find %package <section> */
        for (uint32_t i = 0; i < dwCount; i++)
        {
            if (section_matches(ppLines[i], "%package", pszSection))
            {
                dwSectionStart = (int32_t)i;
                /* Find end of this section */
                for (uint32_t j = i + 1; j < dwCount; j++)
                {
                    if (is_section_header(ppLines[j]) &&
                        !section_matches(ppLines[j], "%package", pszSection))
                    {
                        dwSectionEnd = (int32_t)j;
                        break;
                    }
                }
                if (dwSectionEnd < 0)
                {
                    dwSectionEnd = (int32_t)dwCount;
                }
                break;
            }
        }
    }

    if (dwSectionStart < 0)
    {
        return -1;
    }

    /* Look for the last matching directive line in the section */
    int32_t dwLastDirective = -1;
    const char *pszSearch = pszDirective;

    for (int32_t i = dwSectionStart; i < dwSectionEnd; i++)
    {
        size_t cbDir = strlen(pszSearch);
        if (strncasecmp(ppLines[i], pszSearch, cbDir) == 0 &&
            ppLines[i][cbDir] == ':')
        {
            dwLastDirective = i;
        }
    }

    if (dwLastDirective >= 0)
    {
        return dwLastDirective;
    }

    /* Fallback: insert after %description of this section */
    if (bIsRequires || bIsProvides || bIsConflicts)
    {
        for (int32_t i = dwSectionStart; i < dwSectionEnd; i++)
        {
            if (section_matches(ppLines[i], "%description", pszSection))
            {
                return i;
            }
        }

        /* If main package and no %description found, insert after last
           tag-like line (Name:, Version:, etc.) */
        if (!pszSection || pszSection[0] == '\0')
        {
            int32_t dwLastTag = -1;
            for (int32_t i = dwSectionStart; i < dwSectionEnd; i++)
            {
                if (strchr(ppLines[i], ':') && !isspace((unsigned char)ppLines[i][0])
                    && ppLines[i][0] != '#' && ppLines[i][0] != '%')
                {
                    dwLastTag = i;
                }
            }
            if (dwLastTag >= 0)
            {
                return dwLastTag;
            }
        }
    }

    /* Last resort: insert at end of section */
    return dwSectionEnd - 1;
}

int
spec_patch_file(const SpecPatchSet *pSet)
{
    if (!pSet || !pSet->szSpecPath[0] || !pSet->szPatchedPath[0])
    {
        return -1;
    }

    uint32_t dwOrigCount = 0;
    char **ppOrig = read_lines(pSet->szSpecPath, &dwOrigCount);
    if (!ppOrig)
    {
        fprintf(stderr, "spec_patcher: cannot read %s\n", pSet->szSpecPath);
        return -1;
    }

    /* Allocate output array large enough for original + injections.
       Worst case: each patch adds 3 lines + 2 comment delimiters per
       section + changelog entry per patch. Over-allocate for safety. */
    uint32_t dwOutCap = dwOrigCount + pSet->dwAdditionCount * 4 + 64;
    char **ppOut = calloc(dwOutCap, sizeof(char *));
    if (!ppOut)
    {
        free_lines(ppOrig, dwOrigCount);
        return -1;
    }

    /* Build a bitmap of which original lines have been processed */
    /* We process by collecting insertion points, grouping patches by
       (section, directive), then injecting blocks. */

    /* Collect unique (section, directive) pairs and their insertion points */
    typedef struct {
        char szSection[MAX_SECTION_LEN];
        char szDirective[MAX_DIRECTIVE_LEN];
        int32_t dwInsertAfter;
    } InsertGroup;

    InsertGroup groups[256];
    uint32_t dwGroupCount = 0;

    for (const SpecPatch *pPatch = pSet->pAdditions; pPatch; pPatch = pPatch->pNext)
    {
        /* See if we already have this group */
        int bFound = 0;
        for (uint32_t g = 0; g < dwGroupCount; g++)
        {
            if (strcasecmp(groups[g].szSection, pPatch->szSection) == 0 &&
                strcasecmp(groups[g].szDirective, pPatch->szDirective) == 0)
            {
                bFound = 1;
                break;
            }
        }
        if (!bFound && dwGroupCount < 256)
        {
            snprintf(groups[dwGroupCount].szSection,
                     sizeof(groups[dwGroupCount].szSection),
                     "%s", pPatch->szSection);
            snprintf(groups[dwGroupCount].szDirective,
                     sizeof(groups[dwGroupCount].szDirective),
                     "%s", pPatch->szDirective);
            groups[dwGroupCount].dwInsertAfter =
                find_insertion_point(ppOrig, dwOrigCount,
                                    pPatch->szSection, pPatch->szDirective);
            dwGroupCount++;
        }
    }

    /* Sort groups by insertion point descending so later inserts don't
       shift earlier indices */
    for (uint32_t i = 0; i < dwGroupCount; i++)
    {
        for (uint32_t j = i + 1; j < dwGroupCount; j++)
        {
            if (groups[j].dwInsertAfter > groups[i].dwInsertAfter)
            {
                InsertGroup tmp = groups[i];
                groups[i] = groups[j];
                groups[j] = tmp;
            }
        }
    }

    /* Copy original lines and inject at insertion points */
    uint32_t dwOutCount = 0;

    /* Helper to append a line with allocation checks */
    #define APPEND_LINE(line) do { \
        char *_ln = (line); \
        if (!_ln) goto cleanup; \
        if (dwOutCount >= dwOutCap) { \
            uint32_t _newcap = dwOutCap * 2; \
            if (_newcap < dwOutCap) { free(_ln); goto cleanup; } \
            char **ppNew = realloc(ppOut, _newcap * sizeof(char *)); \
            if (!ppNew) { free(_ln); goto cleanup; } \
            ppOut = ppNew; \
            dwOutCap = _newcap; \
        } \
        ppOut[dwOutCount++] = _ln; \
    } while (0)

    /* We process original lines, and after certain lines, inject blocks */
    for (uint32_t i = 0; i < dwOrigCount; i++)
    {
        APPEND_LINE(strdup(ppOrig[i]));

        /* Check if any group needs injection after this line */
        for (uint32_t g = 0; g < dwGroupCount; g++)
        {
            if (groups[g].dwInsertAfter == (int32_t)i)
            {
                APPEND_LINE(strdup(
                    "# --- begin upstream-dep-scanner additions (auto-generated) ---\n"));

                for (const SpecPatch *pPatch = pSet->pAdditions;
                     pPatch; pPatch = pPatch->pNext)
                {
                    if (strcasecmp(pPatch->szSection,
                                   groups[g].szSection) == 0 &&
                        strcasecmp(pPatch->szDirective,
                                   groups[g].szDirective) == 0)
                    {
                        char szBuf[MAX_LINE_LEN];
                        snprintf(szBuf, sizeof(szBuf),
                                 "# Source: %s\n", pPatch->szEvidence);
                        APPEND_LINE(strdup(szBuf));

                        snprintf(szBuf, sizeof(szBuf),
                                 "%s:       %s\n",
                                 pPatch->szDirective, pPatch->szValue);
                        APPEND_LINE(strdup(szBuf));
                    }
                }

                APPEND_LINE(strdup(
                    "# --- end upstream-dep-scanner additions ---\n"));
            }
        }

        /* Changelog injection */
        if (strncasecmp(ppOrig[i], "%changelog", 10) == 0)
        {
            time_t tNow = time(NULL);
            struct tm *pTm = localtime(&tNow);
            char szDate[64];
            strftime(szDate, sizeof(szDate), "%a %b %d %Y", pTm);

            char szEntry[MAX_LINE_LEN];
            snprintf(szEntry, sizeof(szEntry),
                     "* %s upstream-dep-scanner <upstream-dep-scanner@photon> %%{version}-%%{release}\n",
                     szDate);
            APPEND_LINE(strdup(szEntry));

            for (const SpecPatch *pPatch = pSet->pAdditions;
                 pPatch; pPatch = pPatch->pNext)
            {
                char szBuf[MAX_LINE_LEN];
                snprintf(szBuf, sizeof(szBuf),
                         "- Add missing dependency: %s (from %s analysis)\n",
                         pPatch->szValue,
                         edge_source_str(pPatch->nSource));
                APPEND_LINE(strdup(szBuf));
            }

            APPEND_LINE(strdup("\n"));
        }
    }

    #undef APPEND_LINE

    if (write_lines(pSet->szPatchedPath, ppOut, dwOutCount) != 0)
    {
        fprintf(stderr, "spec_patcher: cannot write %s\n", pSet->szPatchedPath);
        free_lines(ppOrig, dwOrigCount);
        free_lines(ppOut, dwOutCount);
        return -1;
    }

    free_lines(ppOrig, dwOrigCount);
    free_lines(ppOut, dwOutCount);
    return 0;

cleanup:
    free_lines(ppOrig, dwOrigCount);
    free_lines(ppOut, dwOutCount);
    return -1;
}

uint32_t
spec_patch_all(DepGraph *pGraph, const char *pszOutputDir,
               const char *pszBranch)
{
    if (!pGraph || !pszOutputDir || !pszBranch)
    {
        return 0;
    }

    /* Reject branch names with path traversal */
    if (strstr(pszBranch, "..") || strchr(pszBranch, '/'))
    {
        fprintf(stderr, "spec_patcher: rejecting unsafe branch name '%s'\n",
                pszBranch);
        return 0;
    }

    uint32_t dwPatched = 0;

    for (SpecPatchSet *pSet = pGraph->pPatchSets; pSet; pSet = pSet->pNext)
    {
        /* Reject package/branch names with path traversal sequences */
        if (strstr(pSet->szPackageName, "..") || strchr(pSet->szPackageName, '/'))
        {
            fprintf(stderr, "spec_patcher: rejecting unsafe package name '%s'\n",
                    pSet->szPackageName);
            continue;
        }

        /* Extract basename from spec path */
        char szSpecCopy[MAX_PATH_LEN];
        snprintf(szSpecCopy, sizeof(szSpecCopy), "%s", pSet->szSpecPath);
        const char *pszBase = strrchr(szSpecCopy, '/');
        if (pszBase)
        {
            pszBase++;
        }
        else
        {
            pszBase = szSpecCopy;
        }

        /* Reject basenames with path traversal */
        if (strstr(pszBase, "..") || strchr(pszBase, '/'))
        {
            fprintf(stderr, "spec_patcher: rejecting unsafe spec basename '%s'\n",
                    pszBase);
            continue;
        }

        /* Build output directory */
        char szDir[MAX_PATH_LEN];
        snprintf(szDir, sizeof(szDir), "%s/SPECS_DEPFIX/%s/%s",
                 pszOutputDir, pszBranch, pSet->szPackageName);

        if (mkdir_p(szDir, 0755) != 0)
        {
            fprintf(stderr, "spec_patcher: cannot create directory %s: %s\n",
                    szDir, strerror(errno));
            continue;
        }

        /* Build full output path */
        snprintf(pSet->szPatchedPath, sizeof(pSet->szPatchedPath),
                 "%s/%s", szDir, pszBase);

        if (spec_patch_file(pSet) == 0)
        {
            dwPatched++;
        }
    }

    return dwPatched;
}
