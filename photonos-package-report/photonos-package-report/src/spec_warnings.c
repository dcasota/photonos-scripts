/* spec_warnings.c — per-spec warning lookup, port of PS L 4442-4519.
 *
 * Phase M task M13. Static table of (spec, text, requires_empty_ua).
 * PS iterates 6 separate `if/elseif` chains, last $warning=$warningText
 * assignment wins. We preserve that "last match wins" semantic by
 * walking the table front-to-back and remembering the most recent hit.
 */
#include "pr_spec_warnings.h"

#include <stddef.h>
#include <string.h>   /* strncmp */
#include <strings.h>  /* strcasecmp */

struct warning_entry {
    const char *spec;            /* spec basename, case-insensitive compare */
    const char *text;            /* full warning text (incl. any suffix) */
    int         requires_empty_ua;
};

/* Order matches PS L 4442-4519. */
static const struct warning_entry table[] = {
    /* ---- "Warning: repo isn't maintained anymore." (PS L 4442-4460) ---- */
    {"dhcp.spec",                          "Warning: repo isn't maintained anymore. See https://www.isc.org/dhcp_migration/", 0},
    {"c-rest-engine.spec",                 "Warning: repo isn't maintained anymore.", 0},
    {"copenapi.spec",                      "Warning: repo isn't maintained anymore.", 0},
    {"cloud-network-setup.spec",           "Warning: repo isn't maintained anymore.", 0},
    {"confd.spec",                         "Warning: repo isn't maintained anymore.", 0},
    {"cve-check-tool.spec",                "Warning: repo isn't maintained anymore.", 0},
    {"fcgi.spec",                          "Warning: repo isn't maintained anymore. See https://github.com/FastCGI-Archives/fcgi2/archive/refs/tags/%{version}.tar.gz .", 0},
    {"heapster.spec",                      "Warning: repo isn't maintained anymore.", 0},
    {"http-parser.spec",                   "Warning: repo isn't maintained anymore.", 0},
    {"kubernetes-dashboard.spec",          "Warning: repo isn't maintained anymore.", 0},
    {"libtar.spec",                        "Warning: repo isn't maintained anymore. See https://sources.debian.org/patches/libtar", 0},
    {"lightwave.spec",                     "Warning: repo isn't maintained anymore.", 0},
    {"python-argparse.spec",               "Warning: repo isn't maintained anymore.", 0},
    {"python-atomicwrites.spec",           "Warning: repo isn't maintained anymore.", 0},
    {"python-ipaddr.spec",                 "Warning: repo isn't maintained anymore.", 0},
    {"python-lockfile.spec",               "Warning: repo isn't maintained anymore.", 0},
    {"python-subprocess32.spec",           "Warning: repo isn't maintained anymore.", 0},
    {"python-terminaltables.spec",         "Warning: repo isn't maintained anymore.", 0},

    /* ---- "Warning: Cannot detect correlating tags from the repo provided." (PS L 4462-4485) ---- */
    /* All gated on $UpdateAvailable -eq "" */
    {"bluez-tools.spec",                          "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"cpulimit.spec",                             "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"dbxtool.spec",                              "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"dcerpc.spec",                               "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"dotnet-sdk.spec",                           "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"fuse-overlayfs-snapshotter.spec",           "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"hawkey.spec",                               "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"libgsystem.spec",                           "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"libselinux.spec",                           "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"libsepol.spec",                             "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"lightwave.spec",                            "Warning: Cannot detect correlating tags from the repo provided.", 1},  /* overrides prior "repo isn't maintained" */
    {"likewise-open.spec",                        "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"linux-firmware.spec",                       "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"motd.spec",                                 "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"netmgmt.spec",                              "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"pcstat.spec",                               "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"python-backports.ssl_match_hostname.spec",  "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"python-iniparse.spec",                      "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"python-geomet.spec",                        "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"python-pyjsparser.spec",                    "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"python-ruamel-yaml.spec",                   "Warning: Cannot detect correlating tags from the repo provided. Also, see https://github.com/commx/ruamel-yaml/archive/refs/tags/%{version}.tar.gz", 1},
    {"sqlite2.spec",                              "Warning: Cannot detect correlating tags from the repo provided.", 1},
    {"tornado.spec",                              "Warning: Cannot detect correlating tags from the repo provided.", 1},

    /* ---- "Warning: duplicate of python-pam.spec" (PS L 4487-4488) ---- */
    {"python-pycodestyle.spec",            "Warning: duplicate of python-pam.spec", 0},

    /* ---- "Info: Source0 contains a VMware internal url address." (PS L 4490-4508) ---- */
    {"abupdate.spec",                      "Info: Source0 contains a VMware internal url address.", 0},
    {"ant-contrib.spec",                   "Info: Source0 contains a VMware internal url address.", 0},
    {"basic.spec",                         "Info: Source0 contains a VMware internal url address.", 0},
    {"build-essential.spec",               "Info: Source0 contains a VMware internal url address.", 0},
    {"ca-certificates.spec",               "Info: Source0 contains a VMware internal url address.", 0},
    {"distrib-compat.spec",                "Info: Source0 contains a VMware internal url address.", 0},
    {"docker-vsock.spec",                  "Info: Source0 contains a VMware internal url address.", 0},
    {"fipsify.spec",                       "Info: Source0 contains a VMware internal url address.", 0},
    {"grub2-theme.spec",                   "Info: Source0 contains a VMware internal url address.", 0},
    {"initramfs.spec",                     "Info: Source0 contains a VMware internal url address.", 0},
    {"minimal.spec",                       "Info: Source0 contains a VMware internal url address.", 0},
    {"photon-iso-config.spec",             "Info: Source0 contains a VMware internal url address.", 0},
    {"photon-release.spec",                "Info: Source0 contains a VMware internal url address.", 0},
    {"photon-repos.spec",                  "Info: Source0 contains a VMware internal url address.", 0},
    {"photon-upgrade.spec",                "Info: Source0 contains a VMware internal url address.", 0},
    {"rubygem-async-io.spec",              "Info: Source0 contains a VMware internal url address.", 0},
    {"shim-signed.spec",                   "Info: Source0 contains a VMware internal url address.", 0},
    {"stig-hardening.spec",                "Info: Source0 contains a VMware internal url address.", 0},

    /* ---- "Warning: Source0 seems invalid and no other Official source has been found." (PS L 4510-4516) ---- */
    {"cdrkit.spec",                        "Warning: Source0 seems invalid and no other Official source has been found.", 0},
    {"crash.spec",                         "Warning: Source0 seems invalid and no other Official source has been found.", 0},
    {"finger.spec",                        "Warning: Source0 seems invalid and no other Official source has been found.", 0},
    {"ndsend.spec",                        "Warning: Source0 seems invalid and no other Official source has been found.", 0},
    {"pcre.spec",                          "Warning: Source0 seems invalid and no other Official source has been found.", 0},
    {"pypam.spec",                         "Warning: Source0 seems invalid and no other Official source has been found.", 0},

    /* ---- "Info: Source0 contains a static version number." (PS L 4518-4520) ---- */
    {"autoconf213.spec",                   "Info: Source0 contains a static version number.", 0},
    {"etcd-3.3.27.spec",                   "Info: Source0 contains a static version number.", 0},
};

#define N_ENTRIES (sizeof(table) / sizeof(table[0]))

const char *pr_spec_warning(const char *spec, const char *update_available)
{
    if (spec == NULL || *spec == '\0') return NULL;

    /* PS "last match wins" across the chains. Walk forward, remember
     * the most recent hit. */
    const char *match = NULL;
    int ua_is_empty = (update_available == NULL || *update_available == '\0');

    for (size_t i = 0; i < N_ENTRIES; i++) {
        const struct warning_entry *e = &table[i];
        if (strcasecmp(e->spec, spec) != 0) continue;
        if (e->requires_empty_ua && !ua_is_empty) continue;
        match = e->text;
    }
    return match;
}

/* M105 / PS L 4490-4508: specs whose Source0 is a VMware-internal URL get an
 * "Info: …" warning AND PS skips update-detection for them (col5/6 stay
 * empty by design). C previously only added the warning; it still ran
 * detection, so once the body cap is large enough to scrape the listing
 * (M104), it over-detects (e.g. ant-contrib → "2018.08.24") where PS is
 * empty. Returns 1 if `spec` is in the vmware-internal subset of the table
 * above (identified by the "Info: Source0 contains a VMware internal"
 * warning text). Used by check_urlhealth.c to gate the detection block. */
int pr_spec_is_vmware_internal(const char *spec)
{
    if (spec == NULL || *spec == '\0') return 0;
    static const char prefix[] = "Info: Source0 contains a VMware internal";
    const size_t plen = sizeof prefix - 1;
    for (size_t i = 0; i < N_ENTRIES; i++) {
        if (strcasecmp(table[i].spec, spec) != 0) continue;
        if (strncmp(table[i].text, prefix, plen) == 0) return 1;
    }
    return 0;
}
