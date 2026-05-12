/* urlhealth.c — urlhealth() port.
 * Mirrors photonos-package-report.ps1 L 1458-1518 line-by-line.
 *
 * PS source (verbatim, condensed):
 *
 *   function urlhealth {
 *       param([parameter(Mandatory=$true)]$checkurl)
 *       $urlhealthrc = ""
 *       try {
 *           $request = [System.Net.HttpWebRequest]::Create($checkurl)
 *           $request.Method  = "HEAD"
 *           $request.Timeout = 120000
 *           $rc = $request.GetResponse()
 *           $urlhealthrc = [int]$rc.StatusCode
 *           $rc.Close()
 *       } catch {
 *           $urlhealthrc = [int]$_.Exception.Response.StatusCode.value__
 *           if (($checkurl -ilike '*netfilter.org*') -or
 *               ($checkurl -ilike 'https://ftp.*')) {
 *               # browser-mimic fallback: build a WebSession with
 *               # User-Agent + Referer + Sec-Fetch-* headers, retry HEAD.
 *           }
 *       }
 *       return $urlhealthrc
 *   }
 *
 * Implementation notes:
 *   - libcurl handles "HEAD" via CURLOPT_NOBODY=1 + CURLOPT_CUSTOMREQUEST.
 *   - PS catches the WebException and reads .Response.StatusCode. libcurl
 *     surfaces both layers in the same call: CURLINFO_RESPONSE_CODE is
 *     the HTTP status (any value), and the curl_easy_perform return code
 *     tells us whether the transport itself succeeded.
 *   - For the netfilter/ftp fallback we re-run with full Chrome-mimic
 *     headers, lifting the same User-Agent and Sec-Fetch-* string PS uses.
 */
#include "pr_urlhealth.h"

#include <curl/curl.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

static const char *PR_UA_CHROME =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/113.0.0.0 Safari/537.36";

/* Discard any response body from curl. */
static size_t discard_cb(char *p, size_t s, size_t n, void *u)
{
    (void)p; (void)u;
    return s * n;
}

/* Look up the netfilter Referer for a given checkurl by case-insensitive
 * substring match. Mirrors PS L 1485-1494. Returns NULL when checkurl is
 * outside the netfilter family. */
static const char *netfilter_referer(const char *url)
{
    struct { const char *needle; const char *referer; } map[] = {
        { "libnetfilter_conntrack",  "https://www.netfilter.org/projects/libnetfilter_conntrack/downloads.html" },
        { "libmnl",                  "https://www.netfilter.org/projects/libmnl/downloads.html" },
        { "libnetfilter_cthelper",   "https://www.netfilter.org/projects/libnetfilter_cthelper/downloads.html" },
        { "libnetfilter_cttimeout",  "https://www.netfilter.org/projects/libnetfilter_cttimeout/downloads.html" },
        { "libnetfilter_queue",      "https://www.netfilter.org/projects/libnetfilter_queue/downloads.html" },
        { "libnfnetlink",            "https://www.netfilter.org/projects/libnfnetlink/downloads.html" },
        { "libnftnl",                "https://www.netfilter.org/projects/libnftnl/downloads.html" },
        { "nftables",                "https://www.netfilter.org/projects/nftables/downloads.html" },
        { "conntrack-tools",         "https://www.netfilter.org/projects/conntrack-tools/downloads.html" },
        { "iptables",                "https://www.netfilter.org/projects/iptables/downloads.html" },
    };
    size_t n = sizeof map / sizeof map[0];
    for (size_t i = 0; i < n; i++) {
        if (strcasestr(url, map[i].needle) != NULL) return map[i].referer;
    }
    return NULL;
}

/* True iff the URL qualifies for the browser-mimic fallback (PS L 1480). */
static int needs_browser_fallback(const char *url)
{
    if (url == NULL) return 0;
    if (strcasestr(url, "netfilter.org") != NULL) return 1;
    if (strncasecmp(url, "https://ftp.", 12) == 0) return 1;
    return 0;
}

static int curl_head(const char *url, long timeout_ms,
                     struct curl_slist *headers, long *out_status)
{
    CURL *c = curl_easy_init();
    if (!c) return -1;
    curl_easy_setopt(c, CURLOPT_URL,           url);
    curl_easy_setopt(c, CURLOPT_NOBODY,        1L);          /* HEAD */
    curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION,1L);
    curl_easy_setopt(c, CURLOPT_TIMEOUT_MS,    timeout_ms);
    curl_easy_setopt(c, CURLOPT_USERAGENT,     "photonos-package-report/C");
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, discard_cb);
    if (headers) curl_easy_setopt(c, CURLOPT_HTTPHEADER, headers);

    long status = 0;
    CURLcode rc = curl_easy_perform(c);
    if (rc == CURLE_OK || rc == CURLE_HTTP_RETURNED_ERROR) {
        curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &status);
    }
    curl_easy_cleanup(c);
    *out_status = status;
    return rc == CURLE_OK ? 0 : -1;
}

int urlhealth(const char *checkurl)
{
    if (checkurl == NULL || checkurl[0] == '\0') return 0;

    long status = 0;
    int  rc     = curl_head(checkurl, 120000, NULL, &status);
    if (rc == 0 && status >= 200 && status < 400) {
        return (int)status;
    }

    /* PS L 1480: fallback for netfilter/ftp URLs. */
    if (!needs_browser_fallback(checkurl)) {
        return (int)status;  /* HTTP-level error surfaces directly */
    }

    /* Build the Chrome-mimic header set, mirroring PS L 1497-1513. */
    struct curl_slist *h = NULL;
    h = curl_slist_append(h, "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7");
    h = curl_slist_append(h, "Accept-Encoding: gzip, deflate, br");
    h = curl_slist_append(h, "Accept-Language: en-US,en;q=0.9");
    const char *ref = netfilter_referer(checkurl);
    if (ref) {
        char tmp[1024];
        snprintf(tmp, sizeof tmp, "Referer: %s", ref);
        h = curl_slist_append(h, tmp);
    } else {
        h = curl_slist_append(h, "Referer: ");
    }
    h = curl_slist_append(h, "Sec-Fetch-Dest: document");
    h = curl_slist_append(h, "Sec-Fetch-Mode: navigate");
    h = curl_slist_append(h, "Sec-Fetch-Site: same-origin");
    h = curl_slist_append(h, "Sec-Fetch-User: ?1");
    h = curl_slist_append(h, "Upgrade-Insecure-Requests: 1");
    h = curl_slist_append(h, "sec-ch-ua: \"Google Chrome\";v=\"113\", \"Chromium\";v=\"113\", \"Not-A.Brand\";v=\"24\"");
    h = curl_slist_append(h, "sec-ch-ua-mobile: ?0");
    h = curl_slist_append(h, "sec-ch-ua-platform: \"Windows\"");

    /* PS L 1497: -UseBasicParsing means "no DOM parsing"; in curl-land
     * we just don't follow any meta refresh and use NOBODY for HEAD. */
    /* PS L 1497: TimeoutSec 10 — PS uses 10s on the fallback path,
     * NOT 120s. Preserve this exactly. */
    CURL *c = curl_easy_init();
    if (!c) { curl_slist_free_all(h); return (int)status; }
    curl_easy_setopt(c, CURLOPT_URL,            checkurl);
    curl_easy_setopt(c, CURLOPT_NOBODY,         1L);
    curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(c, CURLOPT_TIMEOUT_MS,     10000);
    curl_easy_setopt(c, CURLOPT_USERAGENT,      PR_UA_CHROME);
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION,  discard_cb);
    curl_easy_setopt(c, CURLOPT_HTTPHEADER,     h);
    curl_easy_setopt(c, CURLOPT_ACCEPT_ENCODING,"");  /* "Accept-Encoding: gzip,deflate" + auto-decode */
    long fb_status = 0;
    CURLcode fb_rc = curl_easy_perform(c);
    if (fb_rc == CURLE_OK || fb_rc == CURLE_HTTP_RETURNED_ERROR) {
        curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &fb_status);
    }
    curl_easy_cleanup(c);
    curl_slist_free_all(h);

    /* PS L 1515: on success the fallback status wins; on inner-catch
     * we keep whatever .Exception.Response.StatusCode reported. */
    if (fb_rc == CURLE_OK || fb_status > 0) return (int)fb_status;
    return (int)status;
}
