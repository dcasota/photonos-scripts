/*
 * Copyright (C) 2026 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU General Public License v2 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#include "includes.h"
#include "../../../llconf/nodes.h"

/*
 * Default values calibrated against Photon OS 5.0 Docker image:
 * - Install size from package metadata ≈ actual rootfs size
 * - gzip -9 compression achieves ~44% of original size
 * - 2% buffer for size variations
 */
#define DEFAULT_BUFFER_PERCENT 2
#define DEFAULT_COMPRESSION_RATIO 0.44

typedef struct _TDNF_SIZE_ESTIMATE_ARGS
{
    int nBufferPercent;
    double dCompressionRatio;
    int nVerbose;
    char **ppszPackages;
    int nPackageCount;
} TDNF_SIZE_ESTIMATE_ARGS, *PTDNF_SIZE_ESTIMATE_ARGS;

static uint32_t
TDNFCliParseSizeEstimateArgs(
    PTDNF_CMD_ARGS pCmdArgs,
    PTDNF_SIZE_ESTIMATE_ARGS *ppSizeEstArgs
    )
{
    uint32_t dwError = 0;
    PTDNF_SIZE_ESTIMATE_ARGS pSizeEstArgs = NULL;
    struct cnfnode *cn_opt = NULL;
    int i;

    if (!pCmdArgs || !ppSizeEstArgs)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_CLI_ERROR(dwError);
    }

    dwError = TDNFAllocateMemory(
                  1,
                  sizeof(TDNF_SIZE_ESTIMATE_ARGS),
                  (void **)&pSizeEstArgs);
    BAIL_ON_CLI_ERROR(dwError);

    pSizeEstArgs->nBufferPercent = DEFAULT_BUFFER_PERCENT;
    pSizeEstArgs->dCompressionRatio = DEFAULT_COMPRESSION_RATIO;
    pSizeEstArgs->nVerbose = pCmdArgs->nVerbose;

    if (pCmdArgs->cn_setopts)
    {
        for (cn_opt = pCmdArgs->cn_setopts->first_child;
             cn_opt;
             cn_opt = cn_opt->next)
        {
            if (cn_opt->name && cn_opt->value)
            {
                if (strcasecmp(cn_opt->name, "buffer-percent") == 0)
                {
                    pSizeEstArgs->nBufferPercent = atoi(cn_opt->value);
                    if (pSizeEstArgs->nBufferPercent < 0 ||
                        pSizeEstArgs->nBufferPercent > 100)
                    {
                        pr_err("buffer-percent must be between 0 and 100\n");
                        dwError = ERROR_TDNF_INVALID_PARAMETER;
                        BAIL_ON_CLI_ERROR(dwError);
                    }
                }
                else if (strcasecmp(cn_opt->name, "comp-ratio") == 0)
                {
                    pSizeEstArgs->dCompressionRatio = atof(cn_opt->value);
                    if (pSizeEstArgs->dCompressionRatio <= 0.0 ||
                        pSizeEstArgs->dCompressionRatio > 1.0)
                    {
                        pr_err("comp-ratio must be between 0 and 1\n");
                        dwError = ERROR_TDNF_INVALID_PARAMETER;
                        BAIL_ON_CLI_ERROR(dwError);
                    }
                }
            }
        }
    }

    if (pCmdArgs->nCmdCount > 1)
    {
        pSizeEstArgs->nPackageCount = pCmdArgs->nCmdCount - 1;
        dwError = TDNFAllocateMemory(
                      pSizeEstArgs->nPackageCount + 1,
                      sizeof(char *),
                      (void **)&pSizeEstArgs->ppszPackages);
        BAIL_ON_CLI_ERROR(dwError);

        for (i = 0; i < pSizeEstArgs->nPackageCount; i++)
        {
            dwError = TDNFAllocateString(
                          pCmdArgs->ppszCmds[i + 1],
                          &pSizeEstArgs->ppszPackages[i]);
            BAIL_ON_CLI_ERROR(dwError);
        }
    }

    *ppSizeEstArgs = pSizeEstArgs;

cleanup:
    return dwError;

error:
    if (pSizeEstArgs)
    {
        if (pSizeEstArgs->ppszPackages)
        {
            TDNFFreeStringArray(pSizeEstArgs->ppszPackages);
        }
        TDNFFreeMemory(pSizeEstArgs);
    }
    goto cleanup;
}

static void
TDNFCliFreeSizeEstimateArgs(
    PTDNF_SIZE_ESTIMATE_ARGS pSizeEstArgs
    )
{
    if (pSizeEstArgs)
    {
        if (pSizeEstArgs->ppszPackages)
        {
            TDNFFreeStringArray(pSizeEstArgs->ppszPackages);
        }
        TDNFFreeMemory(pSizeEstArgs);
    }
}

uint32_t
TDNFCliSizeEstimateCommand(
    PTDNF_CLI_CONTEXT pContext,
    PTDNF_CMD_ARGS pCmdArgs
    )
{
    uint32_t dwError = 0;
    PTDNF_SIZE_ESTIMATE_ARGS pSizeEstArgs = NULL;
    PTDNF_PKG_INFO pPkgInfo = NULL;
    PTDNF_PKG_INFO pPkgInfos = NULL;
    uint32_t dwCount = 0;
    uint32_t i;
    uint32_t nFoundPackages = 0;

    uint64_t dwTotalInstallSize = 0;
    uint64_t dwTotalDownloadSize = 0;
    uint64_t dwBufferSize = 0;
    uint64_t dwMaxAllowed = 0;
    uint64_t dwEstTarGzSize = 0;

    char *pszFmtInstall = NULL;
    char *pszFmtDownload = NULL;
    char *pszFmtBuffer = NULL;
    char *pszFmtMax = NULL;
    char *pszFmtTarGz = NULL;

    struct json_dump *jd = NULL;
    struct json_dump *jd_pkg = NULL;

    if (!pContext || !pContext->hTdnf || !pCmdArgs)
    {
        dwError = ERROR_TDNF_CLI_INVALID_ARGUMENT;
        BAIL_ON_CLI_ERROR(dwError);
    }

    dwError = TDNFCliParseSizeEstimateArgs(pCmdArgs, &pSizeEstArgs);
    BAIL_ON_CLI_ERROR(dwError);

    if (!pSizeEstArgs->ppszPackages || pSizeEstArgs->nPackageCount == 0)
    {
        pr_err("Error: No packages specified for size estimation.\n");
        pr_err("Usage: tdnf size-estimate [-v] [OPTIONS] PKG1 [PKG2 ...]\n");
        pr_err("\nEstimates the compressed .tar.gz size for a Docker rootfs tarball.\n");
        pr_err("Default output: size in bytes (use -v for detailed breakdown)\n");
        pr_err("\nOptions:\n");
        pr_err("  -v, --verbose               Show detailed size breakdown\n");
        pr_err("  --setopt=buffer-percent=N   Buffer percentage (default: %d)\n",
               DEFAULT_BUFFER_PERCENT);
        pr_err("  --setopt=comp-ratio=N       gzip -9 compression ratio (default: %.2f)\n",
               DEFAULT_COMPRESSION_RATIO);
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_CLI_ERROR(dwError);
    }

    if (pCmdArgs->nJsonOutput)
    {
        jd = jd_create(0);
        CHECK_JD_NULL(jd);
        CHECK_JD_RC(jd_map_start(jd));

        jd_pkg = jd_create(0);
        CHECK_JD_NULL(jd_pkg);
        CHECK_JD_RC(jd_list_start(jd_pkg));
    }
    else if (pSizeEstArgs->nVerbose)
    {
        pr_crit("\n=== Size Estimation for Photon Docker Image ===\n");
        pr_crit("Packages (%d): ", pSizeEstArgs->nPackageCount);
        for (i = 0; i < (uint32_t)pSizeEstArgs->nPackageCount; i++)
        {
            pr_crit("%s ", pSizeEstArgs->ppszPackages[i]);
        }
        pr_crit("\n\n");
        pr_crit("%-25s %12s %12s\n", "Package", "Install", "Download");
        pr_crit("─────────────────────────────────────────────────────\n");
    }

    for (i = 0; i < (uint32_t)pSizeEstArgs->nPackageCount; i++)
    {
        PTDNF_LIST_ARGS pListArgs = NULL;

        dwError = TDNFAllocateMemory(1, sizeof(TDNF_LIST_ARGS), (void **)&pListArgs);
        BAIL_ON_CLI_ERROR(dwError);

        pListArgs->nScope = SCOPE_AVAILABLE;

        dwError = TDNFAllocateMemory(2, sizeof(char *),
                                     (void **)&pListArgs->ppszPackageNameSpecs);
        if (dwError)
        {
            TDNFFreeMemory(pListArgs);
            BAIL_ON_CLI_ERROR(dwError);
        }

        dwError = TDNFAllocateString(pSizeEstArgs->ppszPackages[i],
                                     &pListArgs->ppszPackageNameSpecs[0]);
        if (dwError)
        {
            TDNFFreeStringArray(pListArgs->ppszPackageNameSpecs);
            TDNFFreeMemory(pListArgs);
            BAIL_ON_CLI_ERROR(dwError);
        }

        dwError = TDNFInfo(pContext->hTdnf,
                          pListArgs->nScope,
                          pListArgs->ppszPackageNameSpecs,
                          &pPkgInfos,
                          &dwCount);

        if (dwError == ERROR_TDNF_NO_MATCH || dwCount == 0)
        {
            if (!pCmdArgs->nJsonOutput && pSizeEstArgs->nVerbose)
            {
                pr_err("%-25s %12s %12s  [NOT FOUND]\n",
                       pSizeEstArgs->ppszPackages[i], "-", "-");
            }
            dwError = 0;
            TDNFFreeStringArray(pListArgs->ppszPackageNameSpecs);
            TDNFFreeMemory(pListArgs);
            continue;
        }
        BAIL_ON_CLI_ERROR(dwError);

        pPkgInfo = &pPkgInfos[0];
        nFoundPackages++;

        if (pCmdArgs->nJsonOutput)
        {
            struct json_dump *jd_entry = jd_create(0);
            CHECK_JD_NULL(jd_entry);

            CHECK_JD_RC(jd_map_start(jd_entry));
            CHECK_JD_RC(jd_map_add_string(jd_entry, "Name", pPkgInfo->pszName));
            CHECK_JD_RC(jd_map_add_string(jd_entry, "Version", pPkgInfo->pszEVR));
            CHECK_JD_RC(jd_map_add_int(jd_entry, "InstallSizeBytes",
                                       pPkgInfo->dwInstallSizeBytes));
            CHECK_JD_RC(jd_map_add_int(jd_entry, "DownloadSizeBytes",
                                       pPkgInfo->dwDownloadSizeBytes));
            CHECK_JD_RC(jd_list_add_child(jd_pkg, jd_entry));
            JD_SAFE_DESTROY(jd_entry);
        }
        else if (pSizeEstArgs->nVerbose)
        {
            pr_crit("%-25s %12u %12u\n",
                    pPkgInfo->pszName,
                    pPkgInfo->dwInstallSizeBytes,
                    pPkgInfo->dwDownloadSizeBytes);
        }

        dwTotalInstallSize += pPkgInfo->dwInstallSizeBytes;
        dwTotalDownloadSize += pPkgInfo->dwDownloadSizeBytes;

        if (pPkgInfos)
        {
            TDNFFreePackageInfoArray(pPkgInfos, dwCount);
            pPkgInfos = NULL;
        }

        TDNFFreeStringArray(pListArgs->ppszPackageNameSpecs);
        TDNFFreeMemory(pListArgs);
    }

    if (dwTotalInstallSize == 0)
    {
        pr_err("\nError: No package sizes obtained. Check repository configuration.\n");
        dwError = ERROR_TDNF_NO_DATA;
        BAIL_ON_CLI_ERROR(dwError);
    }

    /*
     * Calculation:
     * 1. Total install size ≈ uncompressed rootfs size (after standard cleanup)
     * 2. Add buffer for size variations
     * 3. Apply gzip -9 compression ratio
     *
     * Formula: tarball = install_size * (1 + buffer%) * comp_ratio
     */
    dwBufferSize = (dwTotalInstallSize * pSizeEstArgs->nBufferPercent) / 100;
    dwMaxAllowed = dwTotalInstallSize + dwBufferSize;
    dwEstTarGzSize = (uint64_t)(dwMaxAllowed * pSizeEstArgs->dCompressionRatio);

    dwError = TDNFUtilsFormatSize(dwTotalInstallSize, &pszFmtInstall);
    BAIL_ON_CLI_ERROR(dwError);

    dwError = TDNFUtilsFormatSize(dwTotalDownloadSize, &pszFmtDownload);
    BAIL_ON_CLI_ERROR(dwError);

    dwError = TDNFUtilsFormatSize(dwBufferSize, &pszFmtBuffer);
    BAIL_ON_CLI_ERROR(dwError);

    dwError = TDNFUtilsFormatSize(dwMaxAllowed, &pszFmtMax);
    BAIL_ON_CLI_ERROR(dwError);

    dwError = TDNFUtilsFormatSize(dwEstTarGzSize, &pszFmtTarGz);
    BAIL_ON_CLI_ERROR(dwError);

    if (pCmdArgs->nJsonOutput)
    {
        CHECK_JD_RC(jd_map_add_child(jd, "Packages", jd_pkg));
        JD_SAFE_DESTROY(jd_pkg);

        CHECK_JD_RC(jd_map_add_int(jd, "PackageCount", nFoundPackages));
        CHECK_JD_RC(jd_map_add_int(jd, "BufferPercent", pSizeEstArgs->nBufferPercent));
        CHECK_JD_RC(jd_map_add_fmt(jd, "CompressionRatio", "%.2f",
                                   pSizeEstArgs->dCompressionRatio));

        CHECK_JD_RC(jd_map_add_int64(jd, "TotalInstallSizeBytes", dwTotalInstallSize));
        CHECK_JD_RC(jd_map_add_string(jd, "TotalInstallSizeFormatted", pszFmtInstall));

        CHECK_JD_RC(jd_map_add_int64(jd, "TotalDownloadSizeBytes", dwTotalDownloadSize));
        CHECK_JD_RC(jd_map_add_string(jd, "TotalDownloadSizeFormatted", pszFmtDownload));

        CHECK_JD_RC(jd_map_add_int64(jd, "BufferSizeBytes", dwBufferSize));

        CHECK_JD_RC(jd_map_add_int64(jd, "MaxAllowedUncompressedBytes", dwMaxAllowed));
        CHECK_JD_RC(jd_map_add_string(jd, "MaxAllowedUncompressedFormatted", pszFmtMax));

        CHECK_JD_RC(jd_map_add_int64(jd, "EstimatedTarGzBytes", dwEstTarGzSize));
        CHECK_JD_RC(jd_map_add_string(jd, "EstimatedTarGzFormatted", pszFmtTarGz));

        pr_json(jd->buf);
    }
    else if (pSizeEstArgs->nVerbose)
    {
        pr_crit("─────────────────────────────────────────────────────\n");
        pr_crit("%-25s %12lu %12lu\n", "TOTAL", dwTotalInstallSize, dwTotalDownloadSize);
        pr_crit("\n");
        pr_crit("══════════════════════════════════════════════════════\n");
        pr_crit("                   SIZE SUMMARY\n");
        pr_crit("══════════════════════════════════════════════════════\n");
        pr_crit("Total Download Size       : %12lu bytes  (%s)\n",
                dwTotalDownloadSize, pszFmtDownload);
        pr_crit("Total Install Size        : %12lu bytes  (%s)\n",
                dwTotalInstallSize, pszFmtInstall);
        pr_crit("──────────────────────────────────────────────────────\n");
        pr_crit("Buffer (%d%%)               : %12lu bytes  (%s)\n",
                pSizeEstArgs->nBufferPercent, dwBufferSize, pszFmtBuffer);
        pr_crit("Max uncompressed rootfs   : %12lu bytes  (%s)\n",
                dwMaxAllowed, pszFmtMax);
        pr_crit("──────────────────────────────────────────────────────\n");
        pr_crit("Estimated .tar.gz (%.0f%%)  : %12lu bytes  (%s)\n",
                pSizeEstArgs->dCompressionRatio * 100, dwEstTarGzSize, pszFmtTarGz);
        pr_crit("══════════════════════════════════════════════════════\n");
        pr_crit("\nNote: Assumes standard cleanup (rm -rf usr/src/ home/* var/log/* var/cache/tdnf/)\n");
        pr_crit("      and gzip -9 compression.\n\n");
    }
    else
    {
        /* Default: just output the estimated tarball size in bytes */
        pr_crit("%lu\n", dwEstTarGzSize);
    }

cleanup:
    JD_SAFE_DESTROY(jd);
    JD_SAFE_DESTROY(jd_pkg);
    TDNF_CLI_SAFE_FREE_MEMORY(pszFmtInstall);
    TDNF_CLI_SAFE_FREE_MEMORY(pszFmtDownload);
    TDNF_CLI_SAFE_FREE_MEMORY(pszFmtBuffer);
    TDNF_CLI_SAFE_FREE_MEMORY(pszFmtMax);
    TDNF_CLI_SAFE_FREE_MEMORY(pszFmtTarGz);
    if (pPkgInfos)
    {
        TDNFFreePackageInfoArray(pPkgInfos, dwCount);
    }
    TDNFCliFreeSizeEstimateArgs(pSizeEstArgs);
    return dwError;

error:
    goto cleanup;
}
