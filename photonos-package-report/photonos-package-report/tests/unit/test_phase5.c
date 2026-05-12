/* test_phase5.c — unit tests for Phase 5 helpers.
 *
 * The live HTTP entry points (urlhealth(), koji_fedora_lookup()) are
 * exercised only when PR_TEST_NETWORK=1 is set in the environment, so
 * ctest stays offline-friendly. The pure HTML-parse helpers run
 * unconditionally against canned input.
 */
#include "pr_urlhealth.h"
#include "pr_koji.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;

#define EXPECT_STREQ(actual, expected) do {                                    \
    const char *_a = (actual);                                                 \
    const char *_e = (expected);                                               \
    if (_a == NULL || strcmp(_a, _e) != 0) {                                   \
        fprintf(stderr, "  FAIL %s:%d: expected '%s' got '%s'\n",              \
                __FILE__, __LINE__, _e, _a ? _a : "(null)");                   \
        failures++;                                                            \
    }                                                                          \
} while (0)
#define EXPECT_NULL(actual) do {                                               \
    if ((actual) != NULL) {                                                    \
        fprintf(stderr, "  FAIL %s:%d: expected NULL\n", __FILE__, __LINE__);  \
        failures++;                                                            \
    }                                                                          \
} while (0)

static void test_parse_artefact_download_name(void)
{
    fprintf(stderr, "[test_parse_artefact_download_name]\n");

    /* Realistic shape of the src.fedoraproject.org sources page. */
    const char *html =
        "<html><body>\n"
        "<pre><code class=\"hash\">SHA512\n"
        "abc123</code> (libaio-0.3.111.tar.gz)\n"
        "</pre></body></html>";
    char *v = pr_koji_parse_artefact_download_name(html);
    EXPECT_STREQ(v, "libaio-0.3.111.tar.gz");
    free(v);

    /* No <code> block at all → NULL. */
    EXPECT_NULL(pr_koji_parse_artefact_download_name("no code here"));

    /* <code> but no ()/) after it → NULL. */
    EXPECT_NULL(pr_koji_parse_artefact_download_name(
        "<code class=\"x\">abc</code> no parens"));
}

static void test_derive_version(void)
{
    fprintf(stderr, "[test_derive_version]\n");

    /* Default: strip "<name>-" + ".tar.gz" + "v" (everywhere).
     * NOTE the trailing "v" wildcard-strip — every 'v' in the string
     * is removed by the PS author's final ireplace. */
    char *v = pr_koji_derive_version("libaio", "libaio-0.3.111.tar.gz");
    /* libaio-0.3.111.tar.gz → "0.3.111.tar.gz" → "0.3.111" → "0.3.111" */
    EXPECT_STREQ(v, "0.3.111");
    free(v);

    /* The 'v'-strip eats letters too. */
    v = pr_koji_derive_version("dummy", "dummy-v1.2.3.tar.gz");
    EXPECT_STREQ(v, "1.2.3");
    free(v);

    /* connect-proxy special case: strip "ssh-connect-" instead of "<name>-". */
    v = pr_koji_derive_version("connect-proxy", "ssh-connect-1.103.tar.gz");
    EXPECT_STREQ(v, "1.103");
    free(v);

    /* python-pbr special case: strip "pbr-" instead. */
    v = pr_koji_derive_version("python-pbr", "pbr-5.11.1.tar.gz");
    EXPECT_STREQ(v, "5.11.1");
    free(v);
}

static void test_pick_latest_release(void)
{
    fprintf(stderr, "[test_pick_latest_release]\n");

    /* PS splits on '/">' and '/</a>'. After tokenisation the surviving
     * candidates are the directory names embedded between `<a href=".../">`
     * and `/</a>`. */
    const char *html =
        "<a href=\"19.fc41/\">19.fc41/</a>\n"
        "<a href=\"20.fc42/\">20.fc42/</a>\n"
        "<a href=\"21.fc42/\">21.fc42/</a>\n";
    char *w = pr_koji_pick_latest_release(html);
    /* 21 > 20 > 19 → "21.fc42" wins. */
    EXPECT_STREQ(w, "21.fc42");
    free(w);

    /* Empty input → NULL. */
    EXPECT_NULL(pr_koji_pick_latest_release(""));
}

static void test_pick_latest_srpm(void)
{
    fprintf(stderr, "[test_pick_latest_srpm]\n");

    /* Real Koji src/ listings: bare .src.rpm files only, no .asc
     * signatures. (When the listing does include a .asc, PS L 1551 keeps
     * it because `-simplematch '.src.rpm'` is a substring test, and PS
     * subsequently picks the last entry — known PS quirk preserved
     * per CLAUDE.md invariant #2; we mirror, not fix.) */
    const char *html =
        "<a href=\"libaio-0.3.111-19.fc41.src.rpm\">libaio-0.3.111-19.fc41.src.rpm</a>\n"
        "<a href=\"libaio-0.3.111-21.fc42.src.rpm\">libaio-0.3.111-21.fc42.src.rpm</a>\n";
    char *w = pr_koji_pick_latest_srpm(html);
    EXPECT_STREQ(w, "libaio-0.3.111-21.fc42.src.rpm");
    free(w);
}

static void test_urlhealth_live(void)
{
    const char *enable = getenv("PR_TEST_NETWORK");
    if (enable == NULL || strcmp(enable, "1") != 0) {
        fprintf(stderr, "[test_urlhealth_live] SKIP (set PR_TEST_NETWORK=1 to run)\n");
        return;
    }
    fprintf(stderr, "[test_urlhealth_live]\n");
    int s = urlhealth("https://www.gnu.org/");
    if (s != 200 && s != 301 && s != 302) {
        fprintf(stderr, "  FAIL: expected 2xx/3xx from gnu.org, got %d\n", s);
        failures++;
    }
}

int main(void)
{
    test_parse_artefact_download_name();
    test_derive_version();
    test_pick_latest_release();
    test_pick_latest_srpm();
    test_urlhealth_live();

    if (failures == 0) {
        fprintf(stderr, "test_phase5: ALL PASSED\n");
        return 0;
    }
    fprintf(stderr, "test_phase5: %d failure(s)\n", failures);
    return 1;
}
