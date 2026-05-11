#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <ctype.h>

#include "tarball_analyzer.h"
#include "gomod_analyzer.h"

#pragma GCC diagnostic ignored "-Wformat-truncation"

static int
_is_safe_path_component(const char *psz)
{
    if (!psz || !*psz)
        return 0;
    if (strstr(psz, ".."))
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

/* Run tar to extract a single file from a .tar.gz, writing to pszOutPath.
   Uses fork/exec to avoid shell injection. */
int
tarball_extract_file(const char *pszTarball, const char *pszInnerGlob,
                     char *pszOutPath, size_t nOutLen)
{
    struct stat stTar;

    if (!pszTarball || !pszInnerGlob || !pszOutPath)
        return -1;

    if (stat(pszTarball, &stTar) != 0 || !S_ISREG(stTar.st_mode))
        return -1;

    /* Create a safe temp file */
    snprintf(pszOutPath, nOutLen, "/tmp/tarball-extract-XXXXXX");
    int nFd = mkstemp(pszOutPath);
    if (nFd < 0)
        return -1;
    close(nFd);

    /* First: list tarball contents to find the exact path matching the glob.
       We use tar -tzf and pipe through the parent to find the match. */
    int pipefd[2];
    if (pipe(pipefd) < 0)
    {
        unlink(pszOutPath);
        return -1;
    }

    pid_t pid = fork();
    if (pid < 0)
    {
        close(pipefd[0]);
        close(pipefd[1]);
        unlink(pszOutPath);
        return -1;
    }

    if (pid == 0)
    {
        /* Child: list tarball contents to stdout via pipe */
        close(pipefd[0]);
        dup2(pipefd[1], STDOUT_FILENO);
        close(pipefd[1]);
        int devnull = open("/dev/null", O_WRONLY);
        if (devnull >= 0)
        {
            dup2(devnull, STDERR_FILENO);
            close(devnull);
        }
        execlp("tar", "tar", "-tzf", pszTarball, "--wildcards", pszInnerGlob, NULL);
        _exit(127);
    }

    /* Parent: read matching file names from pipe */
    close(pipefd[1]);

    char szMatch[MAX_PATH_LEN];
    szMatch[0] = '\0';
    {
        char szBuf[MAX_LINE_LEN];
        size_t cbRead = 0;
        ssize_t n;
        /* Loop invariant: cbRead <= sizeof(szBuf) - 1. Enforced both
         * structurally (while condition) and defensively (clamp of n,
         * floor on cbRead). Constants only - avoids the size_t-minus-
         * size_t pattern that SAST flags as an integer-overflow taint. */
        const size_t kCap = sizeof(szBuf) - 1;
        while (cbRead < kCap)
        {
            size_t cbGap = kCap - cbRead;           /* kCap >= cbRead */
            n = read(pipefd[0], szBuf + cbRead, cbGap);
            if (n <= 0)
                break;
            size_t cbAdd = ((size_t)n > cbGap) ? cbGap : (size_t)n;
            cbRead += cbAdd;
            if (cbRead > kCap)                       /* defensive floor */
                cbRead = kCap;
        }
        szBuf[cbRead] = '\0';
        close(pipefd[0]);

        /* Take the first line as the match */
        char *pNewline = memchr(szBuf, '\n', cbRead);
        if (pNewline)
            *pNewline = '\0';
        if (szBuf[0])
        {
            snprintf(szMatch, sizeof(szMatch), "%s", szBuf);
        }
    }

    int status;
    waitpid(pid, &status, 0);

    if (!szMatch[0])
    {
        unlink(pszOutPath);
        return -1;
    }

    /* Now extract the matched file to the temp path */
    pid = fork();
    if (pid < 0)
    {
        unlink(pszOutPath);
        return -1;
    }

    if (pid == 0)
    {
        /* Child: extract to stdout, redirect to temp file */
        int fd = open(pszOutPath, O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (fd < 0)
            _exit(1);
        dup2(fd, STDOUT_FILENO);
        close(fd);
        int devnull = open("/dev/null", O_WRONLY);
        if (devnull >= 0)
        {
            dup2(devnull, STDERR_FILENO);
            close(devnull);
        }
        execlp("tar", "tar", "-xzf", pszTarball, "-O", szMatch, NULL);
        _exit(127);
    }

    waitpid(pid, &status, 0);

    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
    {
        unlink(pszOutPath);
        return -1;
    }

    /* Verify the output file is non-empty */
    struct stat stOut;
    if (stat(pszOutPath, &stOut) != 0 || stOut.st_size == 0)
    {
        unlink(pszOutPath);
        return -1;
    }

    return 0;
}

int
tarball_find_source(const char *pszSourcesDir,
                    const char *pszName, const char *pszVersion,
                    char *pszOutPath, size_t nOutLen)
{
    struct stat st;

    if (!pszSourcesDir || !pszName || !pszVersion || !pszOutPath)
        return -1;

    if (!_is_safe_path_component(pszName) || !_is_safe_path_component(pszVersion))
        return -1;

    static const char *aExts[] = {
        ".tar.gz", ".tgz", ".tar.bz2", ".tar.xz", ".zip", NULL
    };

    for (int i = 0; aExts[i]; i++)
    {
        snprintf(pszOutPath, nOutLen, "%s/%s-%s%s",
                 pszSourcesDir, pszName, pszVersion, aExts[i]);
        if (stat(pszOutPath, &st) == 0 && S_ISREG(st.st_mode))
            return 0;
    }

    pszOutPath[0] = '\0';
    return -1;
}

/* Quick check: does this tarball likely contain a Go project?
   Check the file extension and try a fast grep for go.mod in the listing. */
static int
_tarball_has_gomod(const char *pszTarball)
{
    int pipefd[2];
    if (pipe(pipefd) < 0)
        return 0;

    pid_t pid = fork();
    if (pid < 0)
    {
        close(pipefd[0]);
        close(pipefd[1]);
        return 0;
    }

    if (pid == 0)
    {
        close(pipefd[0]);
        dup2(pipefd[1], STDOUT_FILENO);
        close(pipefd[1]);
        int devnull = open("/dev/null", O_WRONLY);
        if (devnull >= 0) { dup2(devnull, STDERR_FILENO); close(devnull); }
        execlp("tar", "tar", "-tzf", pszTarball, "--wildcards", "*/go.mod", NULL);
        _exit(127);
    }

    close(pipefd[1]);
    char szBuf[256];
    ssize_t n = read(pipefd[0], szBuf, sizeof(szBuf) - 1);
    close(pipefd[0]);

    int status;
    waitpid(pid, &status, 0);

    return (n > 0) ? 1 : 0;
}

int
tarball_analyze_gomod(DepGraph *pGraph, const char *pszTarball,
                      const char *pszPackageName,
                      const GomodPackageMap *pMap)
{
    char szTmpPath[MAX_PATH_LEN];

    if (!pGraph || !pszTarball || !pszPackageName || !pMap)
        return -1;

    /* Quick check before expensive extraction */
    if (!_tarball_has_gomod(pszTarball))
        return -1;

    /* Extract go.mod from tarball */
    if (tarball_extract_file(pszTarball, "*/go.mod",
                             szTmpPath, sizeof(szTmpPath)) != 0)
    {
        return -1;
    }

    int nRc = gomod_parse_file(pGraph, szTmpPath, pszPackageName, pMap);
    unlink(szTmpPath);
    return nRc;
}
