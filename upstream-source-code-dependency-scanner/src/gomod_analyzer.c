#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <ctype.h>
#include <sys/wait.h>
#include <fcntl.h>

#include "gomod_analyzer.h"

/* Validate a version string contains only safe characters.
   Rejects shell metacharacters to prevent command injection. */
static int
_is_safe_version(const char *psz)
{
    if (!psz || !*psz)
        return 0;
    for (const char *p = psz; *p; p++)
    {
        if (isalnum((unsigned char)*p) || *p == '.' || *p == '-' ||
            *p == '_' || *p == '+' || *p == '~')
            continue;
        return 0;
    }
    return 1;
}

/* Validate a directory/file name contains no path traversal or shell meta.  */
static int
_is_safe_name(const char *psz)
{
    if (!psz || !*psz)
        return 0;
    if (psz[0] == '-')
        return 0;
    for (const char *p = psz; *p; p++)
    {
        if (isalnum((unsigned char)*p) || *p == '.' || *p == '-' ||
            *p == '_' || *p == '+')
            continue;
        return 0;
    }
    /* Reject path traversal */
    if (strstr(psz, ".."))
        return 0;
    return 1;
}

/* Run "git -C <dir> show <ref>:go.mod" writing output to fd.
   Uses fork/exec to avoid shell injection.  Returns 0 on success. */
static int
_git_show_to_file(const char *pszCloneDir, const char *pszRef,
                  const char *pszOutPath)
{
    pid_t pid;
    int status;
    char szRefArg[MAX_PATH_LEN];

    snprintf(szRefArg, sizeof(szRefArg), "%s:go.mod", pszRef);

    pid = fork();
    if (pid < 0)
        return -1;

    if (pid == 0)
    {
        /* Child: redirect stdout to the output file */
        int fd = open(pszOutPath, O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (fd < 0)
            _exit(1);
        dup2(fd, STDOUT_FILENO);
        close(fd);

        /* Redirect stderr to /dev/null */
        int devnull = open("/dev/null", O_WRONLY);
        if (devnull >= 0)
        {
            dup2(devnull, STDERR_FILENO);
            close(devnull);
        }

        execlp("git", "git", "-C", pszCloneDir, "show", szRefArg, NULL);
        _exit(127);
    }

    /* Parent: wait for child */
    if (waitpid(pid, &status, 0) < 0)
        return -1;

    return (WIFEXITED(status) && WEXITSTATUS(status) == 0) ? 0 : -1;
}

static void
gomod_extract_major_constraint(const char *pszVersion, char *pszOut,
                               size_t nOutLen, const char *pszModulePath)
{
    int nMajor = 0;
    int nMinor = 0;
    const char *pVer = pszVersion;

    if (!pVer || !*pVer)
    {
        snprintf(pszOut, nOutLen, "0.0");
        return;
    }

    if (pVer[0] == 'v')
        pVer++;

    nMajor = atoi(pVer);
    const char *pDot = strchr(pVer, '.');
    if (pDot)
        nMinor = atoi(pDot + 1);

    /* k8s.io convention: v0.X.Y maps to Kubernetes 1.X */
    if (nMajor == 0 && pszModulePath &&
        strncmp(pszModulePath, "k8s.io/", 7) == 0)
    {
        snprintf(pszOut, nOutLen, "1.%d", nMinor);
        return;
    }

    /* For v0.X.Y modules, preserve major.minor instead of collapsing to 0.0 */
    if (nMajor == 0)
    {
        snprintf(pszOut, nOutLen, "%d.%d", nMajor, nMinor);
        return;
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
        if (!pszMappedPkg || strcmp(pszMappedPkg, pszPackageName) == 0 ||
            strcmp(pszMappedPkg, "SKIP") == 0)
        {
            continue;
        }

        dwToIdx = graph_find_node(pGraph, pszMappedPkg);
        if (dwToIdx < 0)
        {
            continue;
        }

        gomod_extract_major_constraint(szVersion, szConstraint,
                                       sizeof(szConstraint), szModulePath);

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
                     const GomodPackageMap *pMap, const PrnMap *pPrnMap)
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

            /* 0. PRN map: clone dir name -> Photon package name */
            if (!bFound && pPrnMap)
            {
                const char *pszPkg = prn_map_find_package(pPrnMap,
                                                          pEntry->d_name);
                if (pszPkg && graph_find_node(pGraph, pszPkg) >= 0)
                {
                    snprintf(szPkgName, sizeof(szPkgName), "%s", pszPkg);
                    bFound = 1;
                }
            }

            /* 1. Direct match */
            if (!bFound && graph_find_node(pGraph, pEntry->d_name) >= 0)
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

            /* Try version-matched go.mod via git show v{version}:go.mod */
            {
                int32_t nIdx = graph_find_node(pGraph, szPkgName);
                int bUsedVersioned = 0;

                if (nIdx >= 0 && pGraph->pNodes[nIdx].szVersion[0] &&
                    _is_safe_version(pGraph->pNodes[nIdx].szVersion) &&
                    _is_safe_name(pEntry->d_name))
                {
                    char szCloneDir[MAX_PATH_LEN];
                    char szTmpPath[MAX_PATH_LEN];
                    char szRef[MAX_VERSION_LEN];
                    const char *pszVer = pGraph->pNodes[nIdx].szVersion;

                    snprintf(szCloneDir, sizeof(szCloneDir), "%s/%s",
                             pszClonesDir, pEntry->d_name);

                    /* Use mkstemp for safe temp file creation */
                    snprintf(szTmpPath, sizeof(szTmpPath),
                             "/tmp/gomod-XXXXXX");
                    int nTmpFd = mkstemp(szTmpPath);
                    if (nTmpFd < 0)
                        goto skip_versioned;
                    close(nTmpFd);

                    /* Try v{version}, then {version} -- using fork/exec */
                    snprintf(szRef, sizeof(szRef), "v%s", pszVer);
                    if (_git_show_to_file(szCloneDir, szRef, szTmpPath) == 0)
                    {
                        struct stat stTmp;
                        if (stat(szTmpPath, &stTmp) == 0 && stTmp.st_size > 0)
                        {
                            gomod_parse_file(pGraph, szTmpPath, szPkgName, pMap);
                            bUsedVersioned = 1;
                        }
                    }

                    if (!bUsedVersioned)
                    {
                        snprintf(szRef, sizeof(szRef), "%s", pszVer);
                        if (_git_show_to_file(szCloneDir, szRef, szTmpPath) == 0)
                        {
                            struct stat stTmp;
                            if (stat(szTmpPath, &stTmp) == 0 && stTmp.st_size > 0)
                            {
                                gomod_parse_file(pGraph, szTmpPath, szPkgName, pMap);
                                bUsedVersioned = 1;
                            }
                        }
                    }

                    unlink(szTmpPath);
                }

                skip_versioned:
                if (!bUsedVersioned)
                {
                    gomod_parse_file(pGraph, szGomodPath, szPkgName, pMap);
                }
            }
        }
    }

    closedir(pDir);
    return 0;
}
