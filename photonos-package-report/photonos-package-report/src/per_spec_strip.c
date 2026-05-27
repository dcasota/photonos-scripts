/* per_spec_strip.c — per-spec strip-token application.
 *
 * Phase M task M27. Mirrors PS L 2839-3060: a switch statement on
 * `$currentTask.spec` that adds custom strip tokens to the candidate
 * tag-name list. PS's pattern is `$replace += "X"; $replace += "Y"`
 * — append-only. We mirror via `istr_replace_all` over each token
 * for every candidate name.
 *
 * Only the simple "$replace += "X"; ... break" entries are ported here.
 * PS entries that also do custom `$Names = @($Names | ... )` filters
 * are deferred to per-spec hooks (Phase 3b territory).
 *
 * The PowerShell `switch` operator is case-INsensitive by default, so
 * the spec-name compare here uses `strcasecmp`.
 *
 * Pipeline placement: between apply_ignore_strings (M26) and
 * apply_name_replace_augmentations (M19), matching PS where the
 * switch executes before the L 2507-2516 standard augmentations.
 */
#include "pr_per_spec.h"
#include "pr_strutil.h"

#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

struct per_spec_entry {
    const char        *spec_name;
    const char *const *tokens;   /* NULL-terminated */
};

/* Per-spec token lists. Each array is NULL-terminated. */
static const char *const k_aide[]                 = {"cs.tut.fi.import", ".release", NULL};
static const char *const k_at_spi2_core[]         = {"AT_SPI2_CORE_3_6_3", "AT_SPI2_CORE_", NULL};
static const char *const k_bcc[]                  = {"src-with-submodule.tar.gz", NULL};
static const char *const k_bpftrace[]             = {"binary.tools.man-bundle.tar.xz", NULL};
static const char *const k_calico_cni[]           = {"calico-amd64", "calico-arm64", NULL};
static const char *const k_calico_confd[]         = {"-darwin-amd64", "confd-", NULL};
static const char *const k_chrpath[]              = {"RELEASE_", NULL};
static const char *const k_cloud_init[]           = {"ubuntu-", "ubuntu/", NULL};
static const char *const k_colm[]                 = {"colm-barracuda-v5", "colm-barracuda-v4", "colm-barracuda-v3", "colm-barracuda-v2", "colm-barracuda-v1", "colm-", NULL};
static const char *const k_cni[]                  = {"v", NULL};
static const char *const k_dracut[]               = {"RHEL-", NULL};
static const char *const k_ecdsa[]                = {"python-ecdsa-", NULL};
static const char *const k_efibootmgr[]           = {"rhel-", "Revision_", "release-tag", "-branchpoint", NULL};
static const char *const k_frr[]                  = {"reindent-master-", "reindent-", "before", "after", NULL};
static const char *const k_fribidi[]              = {"INIT", NULL};
static const char *const k_fuse_overlayfs[]       = {"aarch64", NULL};
static const char *const k_glib[]                 = {"start", "PRE_CLEANUP", "GNOME_PRINT_", NULL};
static const char *const k_glibmm[]               = {"start", NULL};
static const char *const k_glib_networking[]      = {"glib-", NULL};
static const char *const k_glslang[]              = {"master-tot", "main-tot", "sdk-", "SDK-candidate-26-Jul-2020", "Overload400-PrecQual", "SDK-candidate", "SDK-candidate-2", "GL_EXT_shader_subgroup_extended_types-2016-05-10", "SPIRV99", NULL};
static const char *const k_gnome_common[]         = {"version_", "v7status", "update_for_spell_branch_1", "twodaysago", "toshok-libmimedir-base", "threedaysago", NULL};
static const char *const k_gobject_introspection[]= {"INITIAL_RELEASE", "GOBJECT_INTROSPECTION_", NULL};
static const char *const k_gstreamer[]            = {"sharp-", NULL};
static const char *const k_gtk3[]                 = {"VIRTUAL_ATOM-22-06-", "GTK_ALL_", "TRISTAN_NATIVE_LAYOUT_START", "START", NULL};
static const char *const k_gtk_doc[]              = {"GTK_DOC_", "start", NULL};
static const char *const k_inih[]                 = {"r", NULL};
static const char *const k_iperf[]                = {"trunk", "iperf3", NULL};
static const char *const k_iputils[]              = {"s", NULL};
static const char *const k_initscripts[]          = {"upstart-", "unstable", NULL};
static const char *const k_json_glib[]            = {"json-glib-", NULL};
static const char *const k_jsoncpp[]              = {"svn-release-", "svn-import", NULL};
static const char *const k_krb5[]                 = {"-final", NULL};
static const char *const k_kubernetes_dns[]       = {"test", NULL};
static const char *const k_kubernetes_metrics[]   = {"metrics-ser-helm-chart-3.8.3", NULL};
static const char *const k_libevent[]             = {"-stable", NULL};
static const char *const k_libgd[]                = {"gd-", NULL};
static const char *const k_libev[]                = {"rel-", NULL};
static const char *const k_libnl[]                = {"libnl", NULL};
static const char *const k_libpsl[]               = {"libpsl-", "debian/", NULL};
static const char *const k_librepo[]              = {"librepo-", NULL};
static const char *const k_libselinux[]           = {"sepolgen-", "checkpolicy-3.5", NULL};
static const char *const k_libsolv[]              = {"BASE-SuSE-Code-13_", "BASE-SuSE-Code-12_3-Branch", "BASE-SuSE-Code-12_2-Branch", "BASE-SuSE-Code-12_1-Branch", "1-Branch", NULL};
static const char *const k_libxinerama[]          = {"XORG-7_1", NULL};
static const char *const k_libxslt[]              = {"LIXSLT_", NULL};
static const char *const k_linux_pam[]            = {"pam_unix_refactor", NULL};
static const char *const k_mc[]                   = {"mc-", NULL};
static const char *const k_modemmanager[]         = {"-dev", NULL};
static const char *const k_mysql[]                = {"mysql-cluster-", NULL};
static const char *const k_newt[]                 = {"r", NULL};
static const char *const k_open_vm_tools[]        = {"stable-", NULL};
static const char *const k_pandoc[]               = {"pandoc-server-", "pandoc-lua-engine-", "pandoc-cli-0.1", "new1.16deb", "list", NULL};
static const char *const k_pango[]                = {"tical-branch-point", NULL};
static const char *const k_popt[]                 = {"-release", NULL};
static const char *const k_powershell[]           = {"hashes.sha256", NULL};
static const char *const k_python_babel[]         = {"dev-2a51c9b95d06", NULL};
static const char *const k_python_cassandra[]     = {"3.9-doc-backports-from-3.1", "-backport-prepared-slack", NULL};
static const char *const k_python_ethtool[]       = {"libnl-1-v0.6", NULL};
static const char *const k_python_fuse[]          = {"start", NULL};
static const char *const k_python_lxml[]          = {"lxml-", NULL};
static const char *const k_python_more_itertools[]= {"v", NULL};
static const char *const k_python_networkx[]      = {"python-networkx-", "networkx-", NULL};
static const char *const k_python_numpy[]         = {"with_maskna", NULL};
static const char *const k_python_pyparsing[]     = {"pyparsing_", NULL};
static const char *const k_python_setproctitle[]  = {"version-", NULL};
static const char *const k_python_twisted[]       = {"python-", "twisted-", NULL};
static const char *const k_python_webob[]         = {"sprint-coverage", NULL};
static const char *const k_python_pytz[]          = {"release_", NULL};
static const char *const k_ragel[]                = {"ragel-pre-colm", "ragel-barracuda-v5", "barracuda-v4", "barracuda-v3", "barracuda-v2", "barracuda-v1", NULL};
static const char *const k_redis[]                = {"with-deprecated-diskstore", "vm-playpen", "twitter-20100825", "twitter-20100804", NULL};
static const char *const k_s3fs_fuse[]            = {"Pre-v", NULL};
static const char *const k_spirv_tools[]          = {"sdk-", NULL};
static const char *const k_squashfs_tools[]       = {"CVE-2021-41072", NULL};
static const char *const k_uwsgi[]                = {"no_server_mode", NULL};
static const char *const k_vulkan_headers[]       = {"vksc", NULL};
static const char *const k_vulkan_loader[]        = {"windows-rt-", NULL};
static const char *const k_vulkan_tools[]         = {"sdk-", NULL};
static const char *const k_wavefront_proxy[]      = {"wavefront-", "proxy-", NULL};
static const char *const k_zstd[]                 = {"zstd", NULL};

static const struct per_spec_entry g_per_spec_table[] = {
    {"aide.spec",                          k_aide},
    {"at-spi2-core.spec",                  k_at_spi2_core},
    {"bcc.spec",                           k_bcc},
    {"bpftrace.spec",                      k_bpftrace},
    {"calico-cni.spec",                    k_calico_cni},
    {"calico-confd.spec",                  k_calico_confd},
    {"chrpath.spec",                       k_chrpath},
    {"cloud-init.spec",                    k_cloud_init},
    {"colm.spec",                          k_colm},
    {"cni.spec",                           k_cni},
    {"dracut.spec",                        k_dracut},
    {"ecdsa.spec",                         k_ecdsa},
    {"efibootmgr.spec",                    k_efibootmgr},
    {"frr.spec",                           k_frr},
    {"fribidi.spec",                       k_fribidi},
    /* PS source has the typo `fuse-overlayfs.spec.spec` literally. */
    {"fuse-overlayfs.spec.spec",           k_fuse_overlayfs},
    {"glib.spec",                          k_glib},
    {"glibmm.spec",                        k_glibmm},
    {"glib-networking.spec",               k_glib_networking},
    {"glslang.spec",                       k_glslang},
    {"gnome-common.spec",                  k_gnome_common},
    {"gobject-introspection.spec",         k_gobject_introspection},
    {"gstreamer.spec",                     k_gstreamer},
    {"gtk3.spec",                          k_gtk3},
    {"gtk-doc.spec",                       k_gtk_doc},
    {"inih.spec",                          k_inih},
    {"iperf.spec",                         k_iperf},
    {"iputils.spec",                       k_iputils},
    {"initscripts.spec",                   k_initscripts},
    {"json-glib.spec",                     k_json_glib},
    {"jsoncpp.spec",                       k_jsoncpp},
    {"krb5.spec",                          k_krb5},
    {"kubernetes-dns.spec",                k_kubernetes_dns},
    {"kubernetes-metrics-server.spec",     k_kubernetes_metrics},
    {"libevent.spec",                      k_libevent},
    {"libgd.spec",                         k_libgd},
    {"libev.spec",                         k_libev},
    {"libnl.spec",                         k_libnl},
    {"libpsl.spec",                        k_libpsl},
    {"librepo.spec",                       k_librepo},
    {"libselinux.spec",                    k_libselinux},
    {"libsolv.spec",                       k_libsolv},
    {"libXinerama.spec",                   k_libxinerama},
    {"libxslt.spec",                       k_libxslt},
    {"linux-PAM.spec",                     k_linux_pam},
    {"mc.spec",                            k_mc},
    {"ModemManager.spec",                  k_modemmanager},
    {"mysql.spec",                         k_mysql},
    {"newt.spec",                          k_newt},
    {"open-vm-tools.spec",                 k_open_vm_tools},
    {"pandoc.spec",                        k_pandoc},
    {"pango.spec",                         k_pango},
    {"popt.spec",                          k_popt},
    {"powershell.spec",                    k_powershell},
    {"python-babel.spec",                  k_python_babel},
    {"python-cassandra-driver.spec",       k_python_cassandra},
    {"python-ethtool.spec",                k_python_ethtool},
    {"python-fuse.spec",                   k_python_fuse},
    {"python-lxml.spec",                   k_python_lxml},
    {"python-more-itertools.spec",         k_python_more_itertools},
    {"python-networkx.spec",               k_python_networkx},
    {"python-numpy.spec",                  k_python_numpy},
    {"python-pyparsing.spec",              k_python_pyparsing},
    {"python-setproctitle.spec",           k_python_setproctitle},
    {"python-twisted.spec",                k_python_twisted},
    {"python-webob.spec",                  k_python_webob},
    {"python-pytz.spec",                   k_python_pytz},
    {"ragel.spec",                         k_ragel},
    {"redis.spec",                         k_redis},
    {"s3fs-fuse.spec",                     k_s3fs_fuse},
    {"spirv-tools.spec",                   k_spirv_tools},
    {"squashfs-tools.spec",                k_squashfs_tools},
    {"uwsgi.spec",                         k_uwsgi},
    {"vulkan-headers.spec",                k_vulkan_headers},
    {"vulkan-loader.spec",                 k_vulkan_loader},
    {"vulkan-tools.spec",                  k_vulkan_tools},
    {"wavefront-proxy.spec",               k_wavefront_proxy},
    {"zstd.spec",                          k_zstd},
};

static const size_t g_per_spec_table_count =
    sizeof g_per_spec_table / sizeof g_per_spec_table[0];

void pr_apply_per_spec_strip_tokens(const char *spec_name,
                                    char **names, size_t n)
{
    if (spec_name == NULL || names == NULL || n == 0) return;

    /* PowerShell switch is case-insensitive by default; use strcasecmp. */
    const char *const *tokens = NULL;
    for (size_t e = 0; e < g_per_spec_table_count; e++) {
        if (strcasecmp(g_per_spec_table[e].spec_name, spec_name) == 0) {
            tokens = g_per_spec_table[e].tokens;
            break;
        }
    }
    if (tokens == NULL) return;

    /* Apply each token via global case-insensitive literal substring
     * strip (PS `-replace` on a literal: case-sensitive in PS but PS
     * here uses `-replace` not `-ireplace`; however, the augmentation
     * loop at PS L 2517 wraps tokens with [regex]::Escape and uses
     * `-replace` which is case-sensitive by default. For parity I use
     * str_replace_all (case-SENSITIVE) — but note that PS occasionally
     * relies on case-insensitive matching via -ireplace elsewhere.
     * If a per-spec token misses due to case, that's a follow-up. */
    for (int t = 0; tokens[t] != NULL; t++) {
        if (tokens[t][0] == '\0') continue;
        for (size_t i = 0; i < n; i++) {
            if (names[i] == NULL) continue;
            names[i] = str_replace_all(names[i], tokens[t], "");
        }
    }
}

/* M28 — per-spec drop-substring blacklists.
 *
 * PS pattern at L 2839 switch:
 *   $Names = @($Names | foreach-object { if (!($_ | select-string
 *      -pattern 'X' -simplematch)) {$_}})
 *
 * Drop any candidate name containing any of the blacklisted substrings.
 * `select-string -simplematch` is case-INsensitive by default. */
static const char *const k_drop_docker_20_10[] = {"xdocs-v", NULL};
static const char *const k_drop_falco[]        = {"agent/", NULL};
static const char *const k_drop_glib[]         = {"GTK_", "gobject_", NULL};
static const char *const k_drop_glslang[]      = {"untagged-", "vulkan-", NULL};
static const char *const k_drop_go[]           = {"weekly", "release", NULL};
static const char *const k_drop_httpd[]        = {"apache", "mpm-", "djg", "dg_", "wrowe", "striker", "PCRE_", "MOD_SSL_", "HTTPD_LDAP_", NULL};

static const struct per_spec_entry g_per_spec_drop_table[] = {
    {"docker-20.10.spec", k_drop_docker_20_10},
    {"falco.spec",        k_drop_falco},
    {"glib.spec",         k_drop_glib},
    {"glslang.spec",      k_drop_glslang},
    {"go.spec",           k_drop_go},
    {"httpd.spec",        k_drop_httpd},
};

static const size_t g_per_spec_drop_table_count =
    sizeof g_per_spec_drop_table / sizeof g_per_spec_drop_table[0];

/* Case-insensitive substring match (PS `select-string -simplematch`). */
static int contains_icase(const char *hay, const char *needle)
{
    if (hay == NULL || needle == NULL) return 0;
    return strcasestr(hay, needle) != NULL;
}

void pr_apply_per_spec_drop_substrings(const char *spec_name,
                                       char **names, size_t n)
{
    if (spec_name == NULL || names == NULL || n == 0) return;

    const char *const *substrings = NULL;
    for (size_t e = 0; e < g_per_spec_drop_table_count; e++) {
        if (strcasecmp(g_per_spec_drop_table[e].spec_name, spec_name) == 0) {
            substrings = g_per_spec_drop_table[e].tokens;
            break;
        }
    }
    if (substrings == NULL) return;

    for (size_t i = 0; i < n; i++) {
        if (names[i] == NULL) continue;
        for (int s = 0; substrings[s] != NULL; s++) {
            if (contains_icase(names[i], substrings[s])) {
                free(names[i]);
                names[i] = NULL;
                break;
            }
        }
    }
}

/* M29 — per-spec global character replacement.
 *
 * PS pattern at L 2849, 2929, 2965:
 *   $Names = $Names -ireplace "X","Y"       (case-insensitive)
 *   $Names = $Names -replace  "X","Y"       (case-sensitive)
 *
 * The cases we port here are all single-character substitutions
 * ("-" → ".") where case has no effect. For the literal substring
 * replace we use `istr_replace_all` defensively. */
struct per_spec_replace {
    const char *spec_name;
    const char *from;
    const char *to;
};

static const struct per_spec_replace g_per_spec_replace_table[] = {
    {"automake.spec", "-", "."},
    {"newt.spec",     "-", "."},
    {"salt3.spec",    "-", "."},
};

static const size_t g_per_spec_replace_table_count =
    sizeof g_per_spec_replace_table / sizeof g_per_spec_replace_table[0];

void pr_apply_per_spec_global_replace(const char *spec_name,
                                      char **names, size_t n)
{
    if (spec_name == NULL || names == NULL || n == 0) return;

    const struct per_spec_replace *match = NULL;
    for (size_t e = 0; e < g_per_spec_replace_table_count; e++) {
        if (strcasecmp(g_per_spec_replace_table[e].spec_name, spec_name) == 0) {
            match = &g_per_spec_replace_table[e];
            break;
        }
    }
    if (match == NULL) return;

    for (size_t i = 0; i < n; i++) {
        if (names[i] == NULL) continue;
        names[i] = istr_replace_all(names[i], match->from, match->to);
    }
}

/* M33 / FRD-019 — per-spec SourceTagURL override table.
 *
 * Mirrors PS L 3815-3866. When PS's standard github-tag-list path
 * returns no Names, PS falls back to the spec's atom-feed URL. The C
 * port wires this override into the non-git scraper dispatcher
 * (check_urlhealth.c) — when this function returns non-NULL, we
 * skip dirname(state.Source0) and use the override URL instead, then
 * dispatch to the atom-feed parser since these URLs all end with
 * `?format=atom`. */
struct per_spec_url {
    const char *spec_name;
    const char *url;
};

static const struct per_spec_url g_per_spec_url_table[] = {
    /* PS L 3687 — gnome.org atom feed (single-entry; outside the L 3815+ block). */
    {"python-pygobject.spec",     "https://gitlab.gnome.org/GNOME/pygobject/-/tags?format=atom"},

    /* PS L 3815-3866 — atom-feed dispatcher entries. */
    {"asciidoc3.spec",            "https://gitlab.com/asciidoc3/asciidoc3/-/tags?format=atom"},
    {"atk.spec",                  "https://gitlab.gnome.org/Archive/atk/-/tags?format=atom"},
    {"cairo.spec",                "https://gitlab.freedesktop.org/cairo/cairo/-/tags?format=atom"},
    {"dbus.spec",                 "https://gitlab.freedesktop.org/dbus/dbus/-/tags?format=atom"},
    {"dbus-glib.spec",            "https://gitlab.freedesktop.org/dbus/dbus-glib/-/tags?format=atom"},
    {"dbus-python.spec",          "https://gitlab.freedesktop.org/dbus/dbus-python/-/tags?format=atom"},
    {"fontconfig.spec",           "https://gitlab.freedesktop.org/fontconfig/fontconfig/-/tags?format=atom"},
    {"gstreamer.spec",            "https://gitlab.freedesktop.org/gstreamer/gstreamer/-/tags?format=atom"},
    {"ipcalc.spec",               "https://gitlab.com/ipcalc/ipcalc/-/tags?format=atom"},
    {"libslirp.spec",             "https://gitlab.freedesktop.org/slirp/libslirp/-/tags?format=atom"},
    {"libtiff.spec",              "https://gitlab.com/libtiff/libtiff/-/tags?format=atom"},
    {"libx11.spec",               "https://gitlab.freedesktop.org/xorg/lib/libx11/-/tags?format=atom"},
    {"libxinerama.spec",          "https://gitlab.freedesktop.org/xorg/lib/libxinerama/-/tags?format=atom"},
    {"man-db.spec",               "https://gitlab.com/man-db/man-db/-/tags?format=atom"},
    {"mesa.spec",                 "https://gitlab.freedesktop.org/mesa/mesa/-/tags?format=atom"},
    {"mm-common.spec",            "https://gitlab.gnome.org/GNOME/mm-common/-/tags?format=atom"},
    {"modemmanager.spec",         "https://gitlab.freedesktop.org/modemmanager/modemmanager/-/tags?format=atom"},
    {"pixman.spec",               "https://gitlab.freedesktop.org/pixman/pixman/-/tags?format=atom"},
    {"pkg-config.spec",           "https://gitlab.freedesktop.org/pkg-config/pkg-config/-/tags?format=atom"},
    {"polkit.spec",               "https://gitlab.freedesktop.org/polkit/polkit/-/tags?format=atom"},
    {"psmisc.spec",               "https://gitlab.com/psmisc/psmisc/-/tags?format=atom"},
    {"pygobject.spec",            "https://gitlab.gnome.org/GNOME/pygobject/-/tags?format=atom"},
    {"python-M2Crypto.spec",      "https://gitlab.com/m2crypto/m2crypto/-/tags?format=atom"},
    {"shared-mime-info.spec",     "https://gitlab.freedesktop.org/xdg/shared-mime-info/-/tags?format=atom"},
    {"wayland.spec",              "https://gitlab.freedesktop.org/wayland/wayland/-/tags?format=atom"},
    {"wayland-protocols.spec",    "https://gitlab.freedesktop.org/wayland/wayland-protocols/-/tags?format=atom"},
    /* M39 / PS L 3691-3695: samba family — single repo, filtered by a
     * per-library `search=` query. Each also strips its own prefix token
     * (see apply_samba_tokens in check_urlhealth.c). */
    {"libldb.spec",               "https://gitlab.com/samba-team/devel/samba/-/tags?sort=updated_desc&search=ldb*&format=atom"},
    {"libtalloc.spec",            "https://gitlab.com/samba-team/devel/samba/-/tags?sort=updated_desc&search=talloc*&format=atom"},
    {"libtdb.spec",               "https://gitlab.com/samba-team/devel/samba/-/tags?sort=updated_desc&search=tdb*&format=atom"},
    {"libtevent.spec",            "https://gitlab.com/samba-team/devel/samba/-/tags?sort=updated_desc&search=tevent*&format=atom"},
    {"samba-client.spec",         "https://gitlab.com/samba-team/devel/samba/-/tags?sort=updated_desc&search=samba*&format=atom"},
};

static const size_t g_per_spec_url_table_count =
    sizeof g_per_spec_url_table / sizeof g_per_spec_url_table[0];

const char *pr_per_spec_source_tag_url(const char *spec_name)
{
    if (spec_name == NULL) return NULL;
    for (size_t e = 0; e < g_per_spec_url_table_count; e++) {
        if (strcasecmp(g_per_spec_url_table[e].spec_name, spec_name) == 0) {
            return g_per_spec_url_table[e].url;
        }
    }
    return NULL;
}

/* M41 / PS L 4294-4305: "all other types" per-spec SourceTagURL
 * overrides. These specs' Source0 dir is not a usable listing, so PS
 * points at a project download page whose <a href> tarball links are
 * full URLs (path-split to the basename happens in the caller). Only
 * the launchpad/standard-listing subset is ported here; the bot-walled
 * / bespoke-parse ones (json-c S3, js, ipset install.html, chrpath,
 * docbook two-stage, …) are deferred. */
static const struct {
    const char *spec_name;
    const char *url;
} g_all_other_url_table[] = {
    {"apparmor.spec",   "https://launchpad.net/apparmor/+download"},
    {"bzr.spec",        "https://launchpad.net/bzr/+download"},
    {"intltool.spec",   "https://launchpad.net/intltool/+download"},
    {"itstool.spec",    "https://itstool.org/download.html"},
    {"openvswitch.spec","https://www.openvswitch.org/download/"},
    {"ipset.spec",      "https://ipset.netfilter.org/install.html"},
    /* M101 / PS L 4376: cgit tags page. dirname(Source0) is the cgit
     * /snapshot/ DOWNLOAD endpoint (not a listing), so the generic path
     * sees nothing; the /refs/tags page lists the snapshot tarball hrefs
     * (.../snapshot/wireguard-tools-<ver>.tar.xz) which the ao path
     * basenames + the "wireguard-tools-" token (apply_generic_scrape_tokens)
     * reduces to the version. */
    {"wireguard-tools.spec", "https://git.zx2c4.com/wireguard-tools/refs/tags"},
};

static const size_t g_all_other_url_table_count =
    sizeof g_all_other_url_table / sizeof g_all_other_url_table[0];

const char *pr_all_other_source_tag_url(const char *spec_name)
{
    if (spec_name == NULL) return NULL;
    for (size_t e = 0; e < g_all_other_url_table_count; e++) {
        if (strcasecmp(g_all_other_url_table[e].spec_name, spec_name) == 0) {
            return g_all_other_url_table[e].url;
        }
    }
    return NULL;
}

/* M43 / PS L 3206-3272: the mozilla family detects the latest version by
 * scraping a releases INDEX (not the spec's current-version dir, which
 * is all the generic scraper sees):
 *   nspr  -> vX.Y dirs; leading "v" stripped by apply_clean_version_names;
 *            col6 = re-substitution of /v%{version}/ Source0 (valid URL).
 *   nss   -> NSS_X_Y_RTM dirs; apply_mozilla_transform strips NSS_/_RTM
 *            and the pipeline _->. yields the dotted version.
 *   mozjs -> firefox version dirs verbatim.
 * mozjs/nss are "update available" but their Source0 hardcodes a stale
 * version dir (%{version}esr / NSS_3_78_RTM); re-substitution 404s, so C
 * clears col6/7 and emits the "Manufacturer may changed..." warning —
 * which is EXACTLY what PS emits (verified row-identical), so no special
 * handling is needed. */
const char *pr_mozilla_releases_url(const char *spec_name)
{
    if (spec_name == NULL) return NULL;
    if (strcasecmp(spec_name, "nspr.spec") == 0)
        return "https://ftp.mozilla.org/pub/nspr/releases/";
    if (strcasecmp(spec_name, "nss.spec") == 0)
        return "https://ftp.mozilla.org/pub/security/nss/releases/";
    if (strcasecmp(spec_name, "mozjs.spec") == 0)
        return "https://ftp.mozilla.org/pub/firefox/releases/";
    return NULL;
}
