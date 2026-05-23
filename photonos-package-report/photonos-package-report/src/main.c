/* main.c — top-level entry point.
 *
 * Mirrors photonos-package-report.ps1 L 83-131 verbatim in execution order:
 *   1. `param()` block at L 83-108 → argument parsing in argv → pr_params_t.
 *   2. Convert-ToBoolean applied to each boolean parameter at L 120-131.
 *   3. (Subsequent phases extend main() to mirror the pre-flight,
 *      GitPhoton, GenerateUrlHealthReports calls in PS L 5200+.)
 *
 * Phase 2 adds a non-PS hidden helper mode: `--dump-tasks <branch>` which
 * runs parse_directory() and emits each task as one JSON line to stdout.
 * The parity harness uses this against a PS-side equivalent dump to prove
 * Get-SpecValue + ParseDirectory produce bit-identical task lists.
 *
 * The argument-parsing block uses getopt_long_only so that single-dash long
 * options (`-workingDir <p>`) match the PS native syntax. The order of
 * declarations in `options[]` mirrors the PS param-block order exactly.
 */
#include "photonos_package_report.h"

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>
#include <locale.h>
#include <pwd.h>

#include "pr_types.h"
#include "pr_check_urlhealth.h"
#include "pr_pool.h"
#include "pr_prn.h"
#include "pr_diff_report.h"
#include "pr_package_report.h"
#include "source0_lookup.h"
#include <time.h>

/* Forward declarations for helper subcommands. */
static int dump_tasks_main(const char *working_dir, const char *branch);
static int generate_urlhealth_main(const pr_params_t *params, const char *branch);

/* Helper: getenv() returning const char *""  rather than NULL,
 * matching the PS implicit-empty semantics for $env:FOO when unset. */
static const char *env_or(const char *name)
{
    const char *v = getenv(name);
    return v ? v : "";
}

/* L 87 default: $(if ($env:PUBLIC) { $env:PUBLIC } else { $HOME }) */
static const char *default_working_dir(void)
{
    const char *pub = getenv("PUBLIC");
    if (pub && pub[0]) return pub;
    const char *home = getenv("HOME");
    if (home && home[0]) return home;
    /* fallback: getpwuid */
    struct passwd *pw = getpwuid(getuid());
    return pw ? pw->pw_dir : "";
}

static void usage(const char *progname)
{
    /* The option names mirror the PS param-block field names verbatim. */
    fprintf(stderr,
        "Usage: %s [options]\n"
        "Options mirror the PowerShell script param() block at L 83-108 of\n"
        "photonos-package-report.ps1:\n"
        "\n"
        "  -github_token <s>                              ($env:GITHUB_TOKEN)\n"
        "  -gitlab_freedesktop_org_username <s>           ($env:GITLAB_...)\n"
        "  -gitlab_freedesktop_org_token <s>              ($env:GITLAB_...)\n"
        "  -workingDir <path>                             ($env:PUBLIC or $HOME)\n"
        "  -upstreamsDir <path>                           (default: workingDir/photon-upstreams)\n"
        "  -scansDir <path>                               (default: workingDir/scans)\n"
        "  -UpstreamsExclusionList <csv>                  (e.g. firmware,chromium)\n"
        "  -GeneratePh3URLHealthReport <true|false>       (default: true)\n"
        "  -GeneratePh4URLHealthReport <true|false>       (default: true)\n"
        "  -GeneratePh5URLHealthReport <true|false>       (default: true)\n"
        "  -GeneratePh6URLHealthReport <true|false>       (default: true)\n"
        "  -GeneratePhCommonURLHealthReport <true|false>  (default: true)\n"
        "  -GeneratePhDevURLHealthReport <true|false>     (default: true)\n"
        "  -GeneratePhMasterURLHealthReport <true|false>  (default: true)\n"
        "  -GeneratePhPackageReport <true|false>          (default: true)\n"
        "  -GeneratePhCommontoPhMasterDiffHigherPackageVersionReport <true|false> (default: true)\n"
        "  -GeneratePh5toPh6DiffHigherPackageVersionReport <true|false> (default: true)\n"
        "  -GeneratePh4toPh5DiffHigherPackageVersionReport <true|false> (default: true)\n"
        "  -GeneratePh3toPh4DiffHigherPackageVersionReport <true|false> (default: true)\n"
        "  -h | --help                                    show this message\n",
        progname);
}

int main(int argc, char **argv)
{
    /* NFR-6 in PRD: locale-independent sort. */
    setlocale(LC_ALL, "C");

    /* ===== PS L 83-108: `param(...)` block ===================== */
    pr_params_t params;
    memset(&params, 0, sizeof params);

    /* Defaults — mirror PS L 84-89 + 95 + 96-107 */
    params.github_token                          = env_or("GITHUB_TOKEN");                                    /* L 84 */
    params.gitlab_freedesktop_org_username       = env_or("GITLAB_FREEDESKTOP_ORG_USERNAME");                 /* L 85 */
    params.gitlab_freedesktop_org_token          = env_or("GITLAB_FREEDESKTOP_ORG_TOKEN");                    /* L 86 */
    params.workingDir                            = default_working_dir();                                     /* L 87 */
    params.upstreamsDir                          = "";                                                        /* L 88 */
    params.scansDir                              = "";                                                        /* L 89 */
    params.UpstreamsExclusionList                = "";                                                        /* L 95 */
    /* L 96-107: all boolean flags default to $true; values arrive as
     * strings via argv and pass through convert_to_boolean below. We
     * pre-initialise to 1 (true). */
    params.GeneratePh3URLHealthReport                                          = 1;  /* L 96  */
    params.GeneratePh4URLHealthReport                                          = 1;  /* L 97  */
    params.GeneratePh5URLHealthReport                                          = 1;  /* L 98  */
    params.GeneratePh6URLHealthReport                                          = 1;  /* L 99  */
    params.GeneratePhCommonURLHealthReport                                     = 1;  /* L 100 */
    params.GeneratePhDevURLHealthReport                                        = 1;  /* L 101 */
    params.GeneratePhMasterURLHealthReport                                     = 1;  /* L 102 */
    params.GeneratePhPackageReport                                             = 1;  /* L 103 */
    params.GeneratePhCommontoPhMasterDiffHigherPackageVersionReport            = 1;  /* L 104 */
    params.GeneratePh5toPh6DiffHigherPackageVersionReport                      = 1;  /* L 105 */
    params.GeneratePh4toPh5DiffHigherPackageVersionReport                      = 1;  /* L 106 */
    params.GeneratePh3toPh4DiffHigherPackageVersionReport                      = 1;  /* L 107 */
    params.ThrottleLimit                                                       = 20; /* PS L 5214 */

    /* Long-option table, declaration order matches PS param-block order. */
    enum {
        OPT_github_token = 1000,
        OPT_gitlab_freedesktop_org_username,
        OPT_gitlab_freedesktop_org_token,
        OPT_workingDir,
        OPT_upstreamsDir,
        OPT_scansDir,
        OPT_UpstreamsExclusionList,
        OPT_GeneratePh3URLHealthReport,
        OPT_GeneratePh4URLHealthReport,
        OPT_GeneratePh5URLHealthReport,
        OPT_GeneratePh6URLHealthReport,
        OPT_GeneratePhCommonURLHealthReport,
        OPT_GeneratePhDevURLHealthReport,
        OPT_GeneratePhMasterURLHealthReport,
        OPT_GeneratePhPackageReport,
        OPT_GeneratePhCommontoPhMasterDiffHigherPackageVersionReport,
        OPT_GeneratePh5toPh6DiffHigherPackageVersionReport,
        OPT_GeneratePh4toPh5DiffHigherPackageVersionReport,
        OPT_GeneratePh3toPh4DiffHigherPackageVersionReport,
        OPT_dump_tasks,                /* Phase 2 parity helper, not in PS. */
        OPT_generate_urlhealth_report, /* Phase 6a end-to-end pipeline.    */
        OPT_throttle_limit,            /* Phase 7 worker count override.   */
    };
    const char *dump_tasks_branch          = NULL;
    const char *generate_urlhealth_branch  = NULL;
    static const struct option long_opts[] = {
        { "github_token",                                                       required_argument, 0, OPT_github_token },
        { "gitlab_freedesktop_org_username",                                    required_argument, 0, OPT_gitlab_freedesktop_org_username },
        { "gitlab_freedesktop_org_token",                                       required_argument, 0, OPT_gitlab_freedesktop_org_token },
        { "workingDir",                                                         required_argument, 0, OPT_workingDir },
        { "upstreamsDir",                                                       required_argument, 0, OPT_upstreamsDir },
        { "scansDir",                                                           required_argument, 0, OPT_scansDir },
        { "UpstreamsExclusionList",                                             required_argument, 0, OPT_UpstreamsExclusionList },
        { "GeneratePh3URLHealthReport",                                         required_argument, 0, OPT_GeneratePh3URLHealthReport },
        { "GeneratePh4URLHealthReport",                                         required_argument, 0, OPT_GeneratePh4URLHealthReport },
        { "GeneratePh5URLHealthReport",                                         required_argument, 0, OPT_GeneratePh5URLHealthReport },
        { "GeneratePh6URLHealthReport",                                         required_argument, 0, OPT_GeneratePh6URLHealthReport },
        { "GeneratePhCommonURLHealthReport",                                    required_argument, 0, OPT_GeneratePhCommonURLHealthReport },
        { "GeneratePhDevURLHealthReport",                                       required_argument, 0, OPT_GeneratePhDevURLHealthReport },
        { "GeneratePhMasterURLHealthReport",                                    required_argument, 0, OPT_GeneratePhMasterURLHealthReport },
        { "GeneratePhPackageReport",                                            required_argument, 0, OPT_GeneratePhPackageReport },
        { "GeneratePhCommontoPhMasterDiffHigherPackageVersionReport",           required_argument, 0, OPT_GeneratePhCommontoPhMasterDiffHigherPackageVersionReport },
        { "GeneratePh5toPh6DiffHigherPackageVersionReport",                     required_argument, 0, OPT_GeneratePh5toPh6DiffHigherPackageVersionReport },
        { "GeneratePh4toPh5DiffHigherPackageVersionReport",                     required_argument, 0, OPT_GeneratePh4toPh5DiffHigherPackageVersionReport },
        { "GeneratePh3toPh4DiffHigherPackageVersionReport",                     required_argument, 0, OPT_GeneratePh3toPh4DiffHigherPackageVersionReport },
        { "dump-tasks",                                                         required_argument, 0, OPT_dump_tasks },
        { "generate-urlhealth-report",                                          required_argument, 0, OPT_generate_urlhealth_report },
        { "ThrottleLimit",                                                      required_argument, 0, OPT_throttle_limit },
        { "help",                                                               no_argument,       0, 'h' },
        { 0, 0, 0, 0 },
    };

    int opt;
    int idx = 0;
    while ((opt = getopt_long_only(argc, argv, "h", long_opts, &idx)) != -1) {
        switch (opt) {
        case OPT_github_token:                          params.github_token                          = optarg; break;
        case OPT_gitlab_freedesktop_org_username:       params.gitlab_freedesktop_org_username       = optarg; break;
        case OPT_gitlab_freedesktop_org_token:          params.gitlab_freedesktop_org_token          = optarg; break;
        case OPT_workingDir:                            params.workingDir                            = optarg; break;
        case OPT_upstreamsDir:                          params.upstreamsDir                          = optarg; break;
        case OPT_scansDir:                              params.scansDir                              = optarg; break;
        case OPT_UpstreamsExclusionList:                params.UpstreamsExclusionList                = optarg; break;
        case OPT_GeneratePh3URLHealthReport:            params.GeneratePh3URLHealthReport            = convert_to_boolean(optarg); break;
        case OPT_GeneratePh4URLHealthReport:            params.GeneratePh4URLHealthReport            = convert_to_boolean(optarg); break;
        case OPT_GeneratePh5URLHealthReport:            params.GeneratePh5URLHealthReport            = convert_to_boolean(optarg); break;
        case OPT_GeneratePh6URLHealthReport:            params.GeneratePh6URLHealthReport            = convert_to_boolean(optarg); break;
        case OPT_GeneratePhCommonURLHealthReport:       params.GeneratePhCommonURLHealthReport       = convert_to_boolean(optarg); break;
        case OPT_GeneratePhDevURLHealthReport:          params.GeneratePhDevURLHealthReport          = convert_to_boolean(optarg); break;
        case OPT_GeneratePhMasterURLHealthReport:       params.GeneratePhMasterURLHealthReport       = convert_to_boolean(optarg); break;
        case OPT_GeneratePhPackageReport:               params.GeneratePhPackageReport               = convert_to_boolean(optarg); break;
        case OPT_GeneratePhCommontoPhMasterDiffHigherPackageVersionReport:
            params.GeneratePhCommontoPhMasterDiffHigherPackageVersionReport = convert_to_boolean(optarg); break;
        case OPT_GeneratePh5toPh6DiffHigherPackageVersionReport:
            params.GeneratePh5toPh6DiffHigherPackageVersionReport = convert_to_boolean(optarg); break;
        case OPT_GeneratePh4toPh5DiffHigherPackageVersionReport:
            params.GeneratePh4toPh5DiffHigherPackageVersionReport = convert_to_boolean(optarg); break;
        case OPT_GeneratePh3toPh4DiffHigherPackageVersionReport:
            params.GeneratePh3toPh4DiffHigherPackageVersionReport = convert_to_boolean(optarg); break;
        case OPT_dump_tasks:
            dump_tasks_branch = optarg; break;
        case OPT_generate_urlhealth_report:
            generate_urlhealth_branch = optarg; break;
        case OPT_throttle_limit:
            params.ThrottleLimit = (int)strtol(optarg, NULL, 10);
            if (params.ThrottleLimit < 1)   params.ThrottleLimit = 1;
            if (params.ThrottleLimit > 256) params.ThrottleLimit = 256;
            break;
        case 'h':
            usage(argv[0]);
            return 0;
        default:
            usage(argv[0]);
            return 2;
        }
    }

    /* ===== PS L 120-131: Convert-ToBoolean re-applied to bool flags =====
     * In the PS port, the re-application loop appears AFTER the param-block
     * because the boolean defaults can arrive as the literal strings
     * "true"/"false" when invoked via `pwsh -File`. We applied
     * convert_to_boolean inline as values arrive (above), which is the
     * same effect. The explicit reassignment block from L 120-131 is
     * therefore a no-op in C; leaving the mirrored comments here so future
     * readers see the correspondence: */
    /* params.GeneratePh3URLHealthReport = convert_to_boolean_str(params.GeneratePh3URLHealthReport);  L 120 */
    /* ... L 121-131 follow the same pattern ... */

    /* Phase 1 stop point: print resolved params to stdout for the harness.
     * Subsequent phases extend main() to mirror PS L 5200+ (pre-flight,
     * GitPhoton, GenerateUrlHealthReports).
     *
     * When --dump-tasks <branch> is specified, the param echo is skipped:
     * the parity harness compares ONLY the JSON dump on stdout. */
    if (dump_tasks_branch == NULL) {
    /* Mask secret values in the param echo. CI runners mask via the
     * `***` substitution on workflow log lines, but local invocations
     * (gdb, smoke tests) emit the raw value otherwise. Keep a non-empty
     * "(set)" marker so operators can still tell whether a token was
     * supplied. */
    printf("github_token=%s\n",                                                 (params.github_token && params.github_token[0]) ? "(set)" : "");
    printf("gitlab_freedesktop_org_username=%s\n",                              params.gitlab_freedesktop_org_username);
    printf("gitlab_freedesktop_org_token=%s\n",                                 (params.gitlab_freedesktop_org_token && params.gitlab_freedesktop_org_token[0]) ? "(set)" : "");
    printf("workingDir=%s\n",                                                   params.workingDir);
    printf("upstreamsDir=%s\n",                                                 params.upstreamsDir);
    printf("scansDir=%s\n",                                                     params.scansDir);
    printf("UpstreamsExclusionList=%s\n",                                       params.UpstreamsExclusionList);
    printf("GeneratePh3URLHealthReport=%d\n",                                   params.GeneratePh3URLHealthReport);
    printf("GeneratePh4URLHealthReport=%d\n",                                   params.GeneratePh4URLHealthReport);
    printf("GeneratePh5URLHealthReport=%d\n",                                   params.GeneratePh5URLHealthReport);
    printf("GeneratePh6URLHealthReport=%d\n",                                   params.GeneratePh6URLHealthReport);
    printf("GeneratePhCommonURLHealthReport=%d\n",                              params.GeneratePhCommonURLHealthReport);
    printf("GeneratePhDevURLHealthReport=%d\n",                                 params.GeneratePhDevURLHealthReport);
    printf("GeneratePhMasterURLHealthReport=%d\n",                              params.GeneratePhMasterURLHealthReport);
    printf("GeneratePhPackageReport=%d\n",                                      params.GeneratePhPackageReport);
    printf("GeneratePhCommontoPhMasterDiffHigherPackageVersionReport=%d\n",     params.GeneratePhCommontoPhMasterDiffHigherPackageVersionReport);
    printf("GeneratePh5toPh6DiffHigherPackageVersionReport=%d\n",               params.GeneratePh5toPh6DiffHigherPackageVersionReport);
    printf("GeneratePh4toPh5DiffHigherPackageVersionReport=%d\n",               params.GeneratePh4toPh5DiffHigherPackageVersionReport);
    printf("GeneratePh3toPh4DiffHigherPackageVersionReport=%d\n",               params.GeneratePh3toPh4DiffHigherPackageVersionReport);
    }

    /* ===== Phase 2 parity helper: --dump-tasks <branch> ============
     * Bypasses the rest of the PS workflow and emits the ParseDirectory
     * result as one JSON line per task, in PS source order. The parity
     * harness compares this against an equivalent PS dump produced by
     * tools/dump-tasks.ps1. */
    if (dump_tasks_branch != NULL && dump_tasks_branch[0] != '\0') {
        return dump_tasks_main(params.workingDir, dump_tasks_branch);
    }

    if (generate_urlhealth_branch != NULL && generate_urlhealth_branch[0] != '\0') {
        return generate_urlhealth_main(&params, generate_urlhealth_branch);
    }

    /* Phase M task M60: package version-matrix report (PS L 5556-5585).
     * One row per package with its version in each of the 7 branches, plus
     * appended subrelease rows. Parses all 7 branch SPECS trees (no network)
     * and writes photonos-package-report_<ts>.prn. */
    if (params.GeneratePhPackageReport) {
        static const char *const br[7] =
            { "3.0", "4.0", "5.0", "6.0", "common", "dev", "master" };
        static const char *const labels[7] =
            { "photon-3.0", "photon-4.0", "photon-5.0", "photon-6.0",
              "photon-common", "photon-dev", "photon-master" };
        pr_task_list_t lists[7];
        const pr_task_list_t *lp[7];
        int parsed_ok = 1;
        for (int k = 0; k < 7; k++) {
            pr_task_list_init(&lists[k]);
            char pd[64];
            snprintf(pd, sizeof pd, "photon-%s", br[k]);
            if (parse_directory(params.workingDir, pd, &lists[k]) != 0) {
                fprintf(stderr, "::warning::package-report: parse_directory(%s) failed\n", pd);
                parsed_ok = 0;
            }
            lp[k] = &lists[k];
        }
        if (parsed_ok) {
            char ts[16];
            time_t now = time(NULL); struct tm tm; localtime_r(&now, &tm);
            strftime(ts, sizeof ts, "%Y%m%d%H%M", &tm);
            const char *scans_dir = (params.scansDir && params.scansDir[0])
                                    ? params.scansDir : params.workingDir;
            char out_path[PR_MAX_PATH];
            snprintf(out_path, sizeof out_path,
                     "%s/photonos-package-report_%s.prn", scans_dir, ts);
            if (pr_write_package_report(lp, labels, out_path) == 0)
                fprintf(stderr, "Wrote %s\n", out_path);
            else
                fprintf(stderr, "::warning::package-report: write failed\n");
        }
        for (int k = 0; k < 7; k++) pr_task_list_free(&lists[k]);
    }

    /* Phase M task M59: cross-branch diff reports (PS L 5585-5660).
     * For each enabled pair, parse the two branch SPECS trees and emit
     * `photonos-diff-report-<a>-<b>_<ts>.prn` listing specs where branch
     * <a> has a HIGHER version than <b>. The generator (pr_write_diff_report)
     * is the PS L5440-5500 port; this wires the 4 PS-side report blocks. */
    {
        static const struct { size_t flag_off; const char *a, *b; } diffs[] = {
            { offsetof(pr_params_t, GeneratePhCommontoPhMasterDiffHigherPackageVersionReport), "common", "master" },
            { offsetof(pr_params_t, GeneratePh5toPh6DiffHigherPackageVersionReport),           "5.0",    "6.0"    },
            { offsetof(pr_params_t, GeneratePh4toPh5DiffHigherPackageVersionReport),           "4.0",    "5.0"    },
            { offsetof(pr_params_t, GeneratePh3toPh4DiffHigherPackageVersionReport),           "3.0",    "4.0"    },
        };
        int any_diff = 0, diff_rc = 0;
        char ts[16];
        time_t now = time(NULL); struct tm tm; localtime_r(&now, &tm);
        strftime(ts, sizeof ts, "%Y%m%d%H%M", &tm);
        const char *scans_dir = (params.scansDir && params.scansDir[0])
                                ? params.scansDir : params.workingDir;
        for (size_t i = 0; i < sizeof diffs / sizeof diffs[0]; i++) {
            if (!*(int *)((char *)&params + diffs[i].flag_off)) continue;
            any_diff = 1;
            char pd_a[64], pd_b[64], lbl_a[80], lbl_b[80], out_path[PR_MAX_PATH];
            snprintf(pd_a, sizeof pd_a, "photon-%s", diffs[i].a);
            snprintf(pd_b, sizeof pd_b, "photon-%s", diffs[i].b);
            snprintf(lbl_a, sizeof lbl_a, "photon-%s", diffs[i].a);
            snprintf(lbl_b, sizeof lbl_b, "photon-%s", diffs[i].b);
            snprintf(out_path, sizeof out_path,
                     "%s/photonos-diff-report-%s-%s_%s.prn",
                     scans_dir, diffs[i].a, diffs[i].b, ts);
            pr_task_list_t la, lb;
            pr_task_list_init(&la); pr_task_list_init(&lb);
            if (parse_directory(params.workingDir, pd_a, &la) != 0 ||
                parse_directory(params.workingDir, pd_b, &lb) != 0) {
                fprintf(stderr, "::warning::diff %s-%s: parse_directory failed\n",
                        diffs[i].a, diffs[i].b);
                diff_rc = 1;
            } else if (pr_write_diff_report(&la, &lb, lbl_a, lbl_b, out_path) != 0) {
                fprintf(stderr, "::warning::diff %s-%s: write failed\n",
                        diffs[i].a, diffs[i].b);
                diff_rc = 1;
            } else {
                fprintf(stderr, "Wrote %s\n", out_path);
            }
            pr_task_list_free(&la); pr_task_list_free(&lb);
        }
        (void)any_diff;  /* diff reports run alongside urlhealth, not exclusively */
        if (diff_rc != 0) { /* fall through; urlhealth dispatch still runs */ }
    }

    /* Phase M task M02: multi-branch dispatcher.
     *
     * When the hidden --generate-urlhealth-report flag is NOT given,
     * fall through to PS-style behaviour: iterate the 7 GeneratePh*
     * URL-health flags and call generate_urlhealth_main() for each
     * enabled branch. Mirrors PS photonos-package-report.ps1 L 5040-5215
     * (the cluster orchestrator loop).
     *
     * A failed branch (missing SPECS, parse_directory error, …) only
     * sets the exit code; remaining branches still run. PS-side errors
     * are similarly soft per-branch. */
    {
        static const struct { int enabled_offset; const char *branch; }
            branch_dispatch[] = {
                { offsetof(pr_params_t, GeneratePh3URLHealthReport),      "3.0"    },
                { offsetof(pr_params_t, GeneratePh4URLHealthReport),      "4.0"    },
                { offsetof(pr_params_t, GeneratePh5URLHealthReport),      "5.0"    },
                { offsetof(pr_params_t, GeneratePh6URLHealthReport),      "6.0"    },
                { offsetof(pr_params_t, GeneratePhCommonURLHealthReport), "common" },
                { offsetof(pr_params_t, GeneratePhDevURLHealthReport),    "dev"    },
                { offsetof(pr_params_t, GeneratePhMasterURLHealthReport), "master" },
            };
        int any_enabled = 0;
        int rc          = 0;
        for (size_t i = 0; i < sizeof branch_dispatch / sizeof branch_dispatch[0]; i++) {
            int enabled = *(int *)((char *)&params + branch_dispatch[i].enabled_offset);
            if (!enabled) continue;
            any_enabled = 1;
            int br_rc = generate_urlhealth_main(&params, branch_dispatch[i].branch);
            if (br_rc != 0) {
                fprintf(stderr, "::warning::generate_urlhealth_main(%s) returned %d\n",
                        branch_dispatch[i].branch, br_rc);
                rc = br_rc;
            }
        }
        if (any_enabled) return rc;
    }

    return 0;
}

/* ===== Phase 2 parity helper: --dump-tasks <branch> =================
 *
 * One JSON object per task, one line per task, no surrounding array.
 * Field order matches the PS PSCustomObject construction in
 * photonos-package-report.ps1 L 345-372 exactly:
 *   Spec, Version, Name, SubRelease, SpecRelativePath, Source0, url,
 *   SHAName, srcname, gem_name, group, extra_version, main_version,
 *   upstreamversion, dialogsubversion, subversion, byaccdate,
 *   libedit_release, libedit_version, ncursessubversion, cpan_name,
 *   xproto_ver, _url_src, _repo_ver, commit_id.
 * The `content` array is NOT emitted (it's deterministic per file and
 * would balloon the dump). The PS side dump-tasks helper omits it too.
 *
 * Records are sorted by SpecRelativePath then Spec before emission so
 * the C and PS dumps stay byte-identical regardless of underlying
 * filesystem ordering (ADR-0006 bit-identical mandate). */

static void json_escape(FILE *out, const char *s)
{
    if (s == NULL) { fputs("\"\"", out); return; }
    fputc('"', out);
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        switch (*p) {
        case '"':  fputs("\\\"", out); break;
        case '\\': fputs("\\\\", out); break;
        case '\b': fputs("\\b",  out); break;
        case '\f': fputs("\\f",  out); break;
        case '\n': fputs("\\n",  out); break;
        case '\r': fputs("\\r",  out); break;
        case '\t': fputs("\\t",  out); break;
        default:
            if (*p < 0x20) fprintf(out, "\\u%04x", *p);
            else fputc(*p, out);
        }
    }
    fputc('"', out);
}

static int task_sort_cmp(const void *a, const void *b)
{
    const pr_task_t *ta = (const pr_task_t *)a;
    const pr_task_t *tb = (const pr_task_t *)b;
    int r = strcmp(ta->SpecRelativePath ? ta->SpecRelativePath : "",
                   tb->SpecRelativePath ? tb->SpecRelativePath : "");
    if (r != 0) return r;
    return strcmp(ta->Spec ? ta->Spec : "", tb->Spec ? tb->Spec : "");
}

static int dump_tasks_main(const char *working_dir, const char *branch)
{
    pr_task_list_t list;
    pr_task_list_init(&list);
    if (parse_directory(working_dir, branch, &list) != 0) {
        pr_task_list_free(&list);
        return 1;
    }

    qsort(list.items, list.count, sizeof *list.items, task_sort_cmp);

    for (size_t i = 0; i < list.count; i++) {
        pr_task_t *t = &list.items[i];
        FILE *o = stdout;
        fputc('{', o);
        #define FIELD(name) do { \
            fputs("\"" #name "\":", o); \
            json_escape(o, t->name); \
        } while (0)
        FIELD(Spec);              fputc(',', o);
        FIELD(Version);           fputc(',', o);
        FIELD(Name);              fputc(',', o);
        FIELD(SubRelease);        fputc(',', o);
        FIELD(SpecRelativePath);  fputc(',', o);
        FIELD(Source0);           fputc(',', o);
        FIELD(url);               fputc(',', o);
        FIELD(SHAName);           fputc(',', o);
        FIELD(srcname);           fputc(',', o);
        FIELD(gem_name);          fputc(',', o);
        FIELD(group);             fputc(',', o);
        FIELD(extra_version);     fputc(',', o);
        FIELD(main_version);      fputc(',', o);
        FIELD(upstreamversion);   fputc(',', o);
        FIELD(dialogsubversion);  fputc(',', o);
        FIELD(subversion);        fputc(',', o);
        FIELD(byaccdate);         fputc(',', o);
        FIELD(libedit_release);   fputc(',', o);
        FIELD(libedit_version);   fputc(',', o);
        FIELD(ncursessubversion); fputc(',', o);
        FIELD(cpan_name);         fputc(',', o);
        FIELD(xproto_ver);        fputc(',', o);
        FIELD(_url_src);          fputc(',', o);
        FIELD(_repo_ver);         fputc(',', o);
        FIELD(commit_id);
        #undef FIELD
        fputs("}\n", o);
    }

    pr_task_list_free(&list);
    return 0;
}

/* ===== Phase 6a: --generate-urlhealth-report <branch> ===============
 *
 * Walks parse_directory(workingDir, branch) → for each task, calls
 * check_urlhealth() → writes a .prn file named
 *
 *   photonos-urlhealth-<branch>_<yyyyMMddHHmm>.prn
 *
 * under scansDir (defaults to workingDir if -scansDir was not given).
 *
 * Sequential only. Parallel runspaces land in Phase 7. Columns past
 * UrlHealth are stubbed until Phase 6b-6f; the row schema itself is
 * already the final PS L 4933 layout. */

static int generate_urlhealth_main(const pr_params_t *params, const char *branch)
{
    /* `branch` is the bare PS-side tag — "3.0", "master", … — that names
     * the output `.prn` and matches the `-GeneratePh*URLHealthReport`
     * flag. The on-disk directory layout follows PS L 461:
     *
     *     $photonPath = Join-Path $WorkingDir "photon-$release"
     *
     * so SPECS lives under `<workingDir>/photon-<branch>/SPECS`. Compute
     * that prefix once here. */
    char photon_dir[64];
    int n = snprintf(photon_dir, sizeof photon_dir, "photon-%s", branch);
    if (n < 0 || (size_t)n >= sizeof photon_dir) {
        fprintf(stderr, "generate_urlhealth: branch '%s' too long\n", branch);
        return 1;
    }

    pr_task_list_t list;
    pr_task_list_init(&list);
    if (parse_directory(params->workingDir, photon_dir, &list) != 0) {
        pr_task_list_free(&list);
        return 1;
    }

    /* Source0LookupData (Phase 3a). Loaded once and shared across tasks. */
    pr_source0_lookup_table_t lut;
    if (source0_lookup(&lut) != 0) {
        pr_task_list_free(&list);
        return 1;
    }

    /* Build output path. */
    const char *scans_dir = (params->scansDir && params->scansDir[0])
                            ? params->scansDir : params->workingDir;
    time_t now = time(NULL);
    struct tm tm; localtime_r(&now, &tm);
    char ts[16];
    strftime(ts, sizeof ts, "%Y%m%d%H%M", &tm);

    char out_path[PR_MAX_PATH];
    snprintf(out_path, sizeof out_path,
             "%s/photonos-urlhealth-%s_%s.prn", scans_dir, branch, ts);

    pr_prn_t *p = pr_prn_open(out_path);
    if (!p) {
        fprintf(stderr, "generate_urlhealth: cannot open %s\n", out_path);
        pr_source0_lookup_free(&lut);
        pr_task_list_free(&list);
        return 1;
    }

    /* Build rows for every task. */
    char **rows = (char **)calloc(list.count, sizeof *rows);
    if (!rows) {
        pr_prn_close(p); pr_source0_lookup_free(&lut); pr_task_list_free(&list);
        return 1;
    }
    /* Phase 6d: pass upstreamsDir/photon-<branch>/clones as the clone
     * root so the git-tag chain populates UpdateDownloadName /
     * UpdateAvailable when PR_TEST_NETWORK=1 is set. Same photon-
     * prefix convention as parse_directory above (PS L 5304:
     *   $cloneDir = Join-Path $upstreamsDir "photon-$($entry.Key)" "clones"). */
    char *clone_root = NULL;
    const char *up_dir = (params->upstreamsDir && params->upstreamsDir[0])
                         ? params->upstreamsDir : params->workingDir;
    if (asprintf(&clone_root, "%s/%s/clones", up_dir, photon_dir) < 0) {
        clone_root = NULL;
    }

    const char *exclusion_list = params->UpstreamsExclusionList
                                 ? params->UpstreamsExclusionList : "";

    /* Phase 7: parallel execution when ThrottleLimit > 1. */
    if (params->ThrottleLimit <= 1) {
        for (size_t i = 0; i < list.count; i++) {
            rows[i] = check_urlhealth(&list.items[i], &lut, clone_root,
                                      exclusion_list);
        }
    } else {
        /* Per-task closure capturing (task, lut, clone_root, exclusion_list)
         * so the worker function only takes one `void *`. */
        typedef struct {
            pr_task_t                       *task;
            const pr_source0_lookup_table_t *lut;
            const char                      *clone_root;
            const char                      *exclusion_list;
        } closure_t;
        closure_t *closures = (closure_t *)calloc(list.count, sizeof *closures);
        if (!closures) {
            free(rows); free(clone_root);
            pr_prn_close(p); pr_source0_lookup_free(&lut); pr_task_list_free(&list);
            return 1;
        }
        pr_pool_t *pool = pr_pool_create(params->ThrottleLimit);
        if (!pool) { free(closures); free(rows); free(clone_root);
                     pr_prn_close(p); pr_source0_lookup_free(&lut);
                     pr_task_list_free(&list); return 1; }
        for (size_t i = 0; i < list.count; i++) {
            closures[i] = (closure_t){ &list.items[i], &lut, clone_root,
                                       exclusion_list };
        }
        /* Worker thunk — declared inline via a static helper. */
        extern void *pr_check_urlhealth_worker(void *arg);  /* below */
        for (size_t i = 0; i < list.count; i++) {
            pr_pool_submit(pool, pr_check_urlhealth_worker, &closures[i]);
        }
        size_t n_out = 0;
        void **results = pr_pool_run(pool, &n_out);
        for (size_t i = 0; i < list.count && i < n_out; i++) {
            rows[i] = (char *)results[i];
        }
        free(results);
        free(closures);
    }
    free(clone_root);
    pr_prn_append_rows(p, rows, list.count);

    for (size_t i = 0; i < list.count; i++) free(rows[i]);
    free(rows);

    pr_prn_close(p);
    pr_source0_lookup_free(&lut);
    pr_task_list_free(&list);

    fprintf(stderr, "Wrote %s\n", out_path);
    return 0;
}

/* Phase 7 worker thunk. Closure: { pr_task_t *, source0 lookup,
 * clone_root, exclusion_list }. Returns a malloc'd row string the
 * parent collects. */
typedef struct {
    pr_task_t                       *task;
    const pr_source0_lookup_table_t *lut;
    const char                      *clone_root;
    const char                      *exclusion_list;
} pr_check_urlhealth_closure_t;

void *pr_check_urlhealth_worker(void *arg)
{
    pr_check_urlhealth_closure_t *c = (pr_check_urlhealth_closure_t *)arg;
    return (void *)check_urlhealth(c->task, c->lut, c->clone_root,
                                   c->exclusion_list);
}
