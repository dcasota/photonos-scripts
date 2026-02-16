/*
 * Copyright (C) 2021-2022 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

/*
 * Module   : parsereposyncargs.c
 *
 * Abstract :
 *
 *            tdnf
 *
 *            command line tools
 */

#include "includes.h"
#include "../llconf/nodes.h"

uint32_t
TDNFCliParseRepoSyncArgs(
    PTDNF_CMD_ARGS pArgs,
    PTDNF_REPOSYNC_ARGS* ppReposyncArgs
    )
{
    uint32_t dwError = 0;
    PTDNF_REPOSYNC_ARGS pReposyncArgs = NULL;
    struct cnfnode *cn = NULL;
    int i;

    if (!pArgs || !ppReposyncArgs)
    {
        dwError = ERROR_TDNF_CLI_INVALID_ARGUMENT;
        BAIL_ON_CLI_ERROR(dwError);
    }

    dwError = TDNFAllocateMemory(
        1,
        sizeof(TDNF_REPOSYNC_ARGS),
        (void**) &pReposyncArgs);
    BAIL_ON_CLI_ERROR(dwError);

    for (cn = pArgs->cn_setopts->first_child; cn; cn = cn->next) {
        if (strcasecmp(cn->name, "arch") == 0)
        {
            if (pReposyncArgs->ppszArchs == NULL)
            {
                dwError = TDNFAllocateMemory(TDNF_REPOSYNC_MAXARCHS+1, sizeof(char *),
                    (void **)&pReposyncArgs->ppszArchs);
                BAIL_ON_CLI_ERROR(dwError);
            }
            for (i = 0; i < TDNF_REPOSYNC_MAXARCHS && pReposyncArgs->ppszArchs[i]; i++);
            if (i < TDNF_REPOSYNC_MAXARCHS)
            {
                dwError = TDNFAllocateString(
                    cn->value,
                    &(pReposyncArgs->ppszArchs[i]));
                BAIL_ON_CLI_ERROR(dwError);
            }
        }
        else if (strcasecmp(cn->name, "delete") == 0)
        {
            pReposyncArgs->nDelete = 1;
        }
        else if (strcasecmp(cn->name, "download-metadata") == 0)
        {
            pReposyncArgs->nDownloadMetadata = 1;
        }
        else if (strcasecmp(cn->name, "gpgcheck") == 0)
        {
            pReposyncArgs->nGPGCheck = 1;
        }
        else if (strcasecmp(cn->name, "newest-only") == 0)
        {
            pReposyncArgs->nNewestOnly = 1;
        }
        else if (strcasecmp(cn->name, "norepopath") == 0)
        {
            pReposyncArgs->nNoRepoPath = 1;
        }
        else if (strcasecmp(cn->name, "source") == 0)
        {
            pReposyncArgs->nSourceOnly = 1;
        }
        else if (strcasecmp(cn->name, "urls") == 0)
        {
            pReposyncArgs->nPrintUrlsOnly = 1;
        }
        else if (strcasecmp(cn->name, "download-path") == 0)
        {
            dwError = TDNFAllocateString(
                cn->value,
                &pReposyncArgs->pszDownloadPath);
            BAIL_ON_CLI_ERROR(dwError);
        }
        else if (strcasecmp(cn->name, "metadata-path") == 0)
        {
            dwError = TDNFAllocateString(
                cn->value,
                &pReposyncArgs->pszMetaDataPath);
            BAIL_ON_CLI_ERROR(dwError);
        }
    }
    *ppReposyncArgs = pReposyncArgs;
cleanup:
    return dwError;
error:
    if (pReposyncArgs)
    {
        TDNFCliFreeRepoSyncArgs(pReposyncArgs);
    }
    goto cleanup;
}

void
TDNFCliFreeRepoSyncArgs(
    PTDNF_REPOSYNC_ARGS pReposyncArgs
    )
{
    if(pReposyncArgs)
    {
        TDNF_CLI_SAFE_FREE_STRINGARRAY(pReposyncArgs->ppszArchs);
        TDNF_SAFE_FREE_MEMORY(pReposyncArgs->pszDownloadPath);
        TDNF_SAFE_FREE_MEMORY(pReposyncArgs->pszMetaDataPath);
        TDNFFreeMemory(pReposyncArgs);
    }
}

