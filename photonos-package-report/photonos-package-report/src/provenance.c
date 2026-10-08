/* provenance.c — opt-in provenance verification of a downloaded tarball
 * (PR_VERIFY_PROVENANCE=1). See pr_provenance.h for the rung ladder.
 *
 * Not a PS port and never part of the .prn: the only output is the sidecar
 * SOURCES_NEW/<file>.provenance.json, so the PS parity journal is unchanged
 * whether the switch is on or off.
 */
#include "pr_provenance.h"
#include "pr_sha.h"

#include <curl/curl.h>
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

#define SIG_MAX   (64u * 1024u)
#define SUMS_MAX  (1024u * 1024u)
#define INDEX_MAX (32u * 1024u * 1024u)

static const char *R_SIGNATURE = "signature";
static const char *R_VENDOR    = "vendor_checksum";
static const char *R_REGISTRY  = "registry_digest";
static const char *R_CORROB    = "corroborated";
static const char *R_TOFU      = "tofu";

int pr_provenance_enabled(void)
{
    const char *v = getenv("PR_VERIFY_PROVENANCE");
    return v != NULL && v[0] != '\0' && strcmp(v, "0") != 0;
}

/* ------------------------------------------------------------------ */
/* small helpers                                                      */
/* ------------------------------------------------------------------ */

static int is_hex(const char *s, size_t n)
{
    for (size_t i = 0; i < n; i++)
        if (!isxdigit((unsigned char)s[i])) return 0;
    return 1;
}

static void lower_into(char *dst, const char *src, size_t n)
{
    for (size_t i = 0; i < n; i++) dst[i] = (char)tolower((unsigned char)src[i]);
    dst[n] = '\0';
}

int pr_prov_url_host(const char *url, char *out, size_t cap)
{
    if (!url || !out || cap == 0) return 0;
    const char *p = strstr(url, "://");
    if (!p) return 0;
    p += 3;
    const char *at = NULL;
    const char *e = p;
    while (*e && *e != '/' && *e != '?' && *e != '#') { if (*e == '@') at = e; e++; }
    if (at) p = at + 1;
    const char *colon = memchr(p, ':', (size_t)(e - p));
    if (colon) e = colon;
    size_t n = (size_t)(e - p);
    if (n == 0 || n >= cap) return 0;
    lower_into(out, p, n);
    return 1;
}

static int same_host(const char *a, const char *b)
{
    char ha[256], hb[256];
    return pr_prov_url_host(a, ha, sizeof ha) && pr_prov_url_host(b, hb, sizeof hb)
        && strcmp(ha, hb) == 0;
}

/* The last path segment of an URL, query and fragment dropped. */
static char *url_basename(const char *url)
{
    const char *e = url + strcspn(url, "?#");
    const char *s = e;
    while (s > url && s[-1] != '/') s--;
    return strndup(s, (size_t)(e - s));
}

/* The URL up to and including its last '/', query dropped. */
static char *url_dir(const char *url)
{
    const char *e = url + strcspn(url, "?#");
    const char *s = e;
    while (s > url && s[-1] != '/') s--;
    return strndup(url, (size_t)(s - url));
}

static char *url_noquery(const char *url)
{
    return strndup(url, strcspn(url, "?#"));
}

/* ------------------------------------------------------------------ */
/* pure parsers                                                       */
/* ------------------------------------------------------------------ */

static int set_digest(const char *h, size_t n, char *alg, char *hex, size_t cap)
{
    if (n != 64 && n != 128) return 0;
    if (n + 1 > cap) return 0;
    if (!is_hex(h, n)) return 0;
    if (alg) strcpy(alg, n == 64 ? "sha256" : "sha512");
    lower_into(hex, h, n);
    return 1;
}

int pr_prov_sums_lookup(const char *body, size_t len, const char *file,
                        int allow_bare, char alg[8], char hex[129])
{
    if (!body || !file || !file[0]) return 0;
    size_t flen = strlen(file);
    const char *p = body, *end = body + len;
    int lines = 0;
    const char *bare = NULL; size_t bare_n = 0;
    while (p < end) {
        const char *nl = memchr(p, '\n', (size_t)(end - p));
        const char *le = nl ? nl : end;
        const char *ls = p;
        p = nl ? nl + 1 : end;
        while (ls < le && isspace((unsigned char)*ls)) ls++;
        const char *re = le;
        while (re > ls && isspace((unsigned char)re[-1])) re--;
        if (re == ls) continue;
        lines++;
        /* BSD: "SHA256 (file) = hex" */
        if ((size_t)(re - ls) > 8 && (strncmp(ls, "SHA256 (", 8) == 0 || strncmp(ls, "SHA512 (", 8) == 0)) {
            const char *fs = ls + 8;
            const char *close = NULL;
            for (const char *q = re - 1; q > fs; q--) if (*q == ')') { close = q; break; }
            if (close && (size_t)(close - fs) == flen && memcmp(fs, file, flen) == 0) {
                const char *eq = close + 1;
                while (eq < re && (*eq == ' ' || *eq == '=')) eq++;
                if (set_digest(eq, (size_t)(re - eq), alg, hex, 129)) return 1;
            }
            continue;
        }
        /* GNU: "hex  [*]file" (also "hex file", "hex ./file") */
        const char *h = ls;
        while (h < re && isxdigit((unsigned char)*h)) h++;
        size_t hn = (size_t)(h - ls);
        if (hn == 0) continue;
        if (h == re) { bare = ls; bare_n = hn; continue; }
        if (!isspace((unsigned char)*h)) continue;
        const char *f = h;
        while (f < re && isspace((unsigned char)*f)) f++;
        if (f < re && *f == '*') f++;
        if ((size_t)(re - f) > 2 && f[0] == '.' && f[1] == '/') f += 2;
        /* Some files carry a path: match the last segment exactly. */
        const char *seg = re;
        while (seg > f && seg[-1] != '/') seg--;
        if ((size_t)(re - seg) == flen && memcmp(seg, file, flen) == 0
            && set_digest(ls, hn, alg, hex, 129)) return 1;
    }
    if (allow_bare && lines == 1 && bare) return set_digest(bare, bare_n, alg, hex, 129);
    return 0;
}

/* First capture of `pat` in `s`, from `from`. Returns malloc'd text. */
static char *re_capture(const char *pat, const char *s, size_t len, size_t from,
                        size_t *match_end)
{
    int err = 0; PCRE2_SIZE off = 0;
    pcre2_code *re = pcre2_compile((PCRE2_SPTR)pat, PCRE2_ZERO_TERMINATED,
                                   PCRE2_DOTALL, &err, &off, NULL);
    if (!re) return NULL;
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(re, NULL);
    char *out = NULL;
    if (md && pcre2_match(re, (PCRE2_SPTR)s, len, from, 0, md, NULL) >= 2) {
        PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md);
        out = strndup(s + ov[2], ov[3] - ov[2]);
        if (match_end) *match_end = ov[1];
    }
    pcre2_match_data_free(md);
    pcre2_code_free(re);
    return out;
}

/* `s` with PCRE2 metacharacters escaped. */
static char *re_quote(const char *s)
{
    size_t n = strlen(s);
    char *o = malloc(n * 2 + 1);
    if (!o) return NULL;
    char *w = o;
    for (; *s; s++) {
        if (strchr("\\^$.|?*+()[]{}", *s)) *w++ = '\\';
        *w++ = *s;
    }
    *w = '\0';
    return o;
}

/* The JSON object that directly contains position `at`: [*ob, *oe] spans
 * its '{' .. '}' (string contents honoured). 1 / 0. */
static int json_enclosing_object(const char *s, size_t len, size_t at,
                                 size_t *ob, size_t *oe)
{
    size_t stack[256];
    int sp = 0, in_str = 0;
    size_t i;
    if (at >= len) return 0;
    for (i = 0; i < at; i++) {
        char c = s[i];
        if (in_str) { if (c == '\\') i++; else if (c == '"') in_str = 0; continue; }
        if (c == '"') in_str = 1;
        else if (c == '{') { if (sp >= 256) return 0; stack[sp++] = i; }
        else if (c == '}') { if (sp > 0) sp--; }
    }
    if (sp == 0) return 0;
    *ob = stack[sp - 1];
    int depth = 1;
    in_str = 0;
    for (i = *ob + 1; i < len; i++) {
        char c = s[i];
        if (in_str) { if (c == '\\') i++; else if (c == '"') in_str = 0; continue; }
        if (c == '"') in_str = 1;
        else if (c == '{') depth++;
        else if (c == '}' && --depth == 0) { *oe = i; return 1; }
    }
    return 0;
}

/* A copy of the object text [ob, oe] with everything nested deeper than its
 * own keys blanked, so a key match is a match of THIS object's key. */
static char *json_own_keys(const char *s, size_t ob, size_t oe)
{
    size_t n = oe - ob + 1;
    char *o = malloc(n + 1);
    if (!o) return NULL;
    int depth = 0, in_str = 0;
    for (size_t i = 0; i < n; i++) {
        char c = s[ob + i];
        int keep = depth <= 1;
        if (in_str) {
            if (c == '\\' && i + 1 < n) {
                o[i] = keep ? c : ' ';
                i++;
                o[i] = keep ? s[ob + i] : ' ';
                continue;
            }
            if (c == '"') in_str = 0;
        } else if (c == '"') {
            in_str = 1;
        } else if (c == '{' || c == '[') {
            depth++;
            keep = depth <= 1;
        } else if (c == '}' || c == ']') {
            keep = depth <= 1;
            depth--;
        }
        o[i] = keep ? c : ' ';
    }
    o[n] = '\0';
    return o;
}

int pr_prov_pypi_sha256(const char *json, size_t len, const char *file, char hex[65])
{
    if (!json || !file) return 0;
    char *q = re_quote(file);
    if (!q) return 0;
    char *pat = NULL;
    int ok = 0;
    if (asprintf(&pat, "\"filename\"\\s*:\\s*\"(%s)\"", q) >= 0) {
        size_t mend = 0;
        char *m = re_capture(pat, json, len, 0, &mend);
        if (m) {
            size_t ob = 0, oe = 0;
            if (json_enclosing_object(json, len, mend - 1, &ob, &oe)) {
                /* "hashes" is the file object's own key; its value is the
                 * one nested object searched. */
                char *h = re_capture("\"hashes\"\\s*:\\s*\\{[^}]*?\"sha256\"\\s*:\\s*\"([0-9a-fA-F]{64})\"",
                                     json + ob, oe - ob + 1, 0, NULL);
                if (h) { ok = set_digest(h, strlen(h), NULL, hex, 65); free(h); }
            }
            free(m);
        }
        free(pat);
    }
    free(q);
    return ok;
}

int pr_prov_rubygems_sha256(const char *json, size_t len, char hex[65])
{
    if (!json) return 0;
    char *h = re_capture("\"sha\"\\s*:\\s*\"([0-9a-fA-F]{64})\"", json, len, 0, NULL);
    int ok = h ? set_digest(h, strlen(h), NULL, hex, 65) : 0;
    free(h);
    return ok;
}

int pr_prov_github_digest(const char *json, size_t len, const char *name, char hex[65])
{
    if (!json || !name) return 0;
    char *q = re_quote(name);
    if (!q) return 0;
    char *pat = NULL;
    int ok = 0;
    /* An asset object: "name":"<asset>" ... "browser_download_url". The
     * digest must lie in the same object. */
    if (asprintf(&pat, "\"name\"\\s*:\\s*\"(%s)\"", q) >= 0) {
        size_t from = 0, mend = 0;
        char *m;
        while (!ok && (m = re_capture(pat, json, len, from, &mend)) != NULL) {
            free(m);
            size_t ob = 0, oe = 0;
            char *own = json_enclosing_object(json, len, mend - 1, &ob, &oe)
                      ? json_own_keys(json, ob, oe) : NULL;
            if (own) {
                size_t on = oe - ob + 1;
                char *bdu = re_capture("\"(browser_download_url)\"", own, on, 0, NULL);
                if (bdu) {
                    free(bdu);
                    char *h = re_capture("\"digest\"\\s*:\\s*\"sha256:([0-9a-fA-F]{64})\"", own, on, 0, NULL);
                    if (h) { ok = set_digest(h, strlen(h), NULL, hex, 65); free(h); }
                }
                free(own);
            }
            from = mend;
        }
        free(pat);
    }
    free(q);
    return ok;
}

int pr_prov_fedora_sha512(const char *body, size_t len, const char *file, char hex[129])
{
    if (!body || !file) return 0;
    char alg[8];
    char h[129];
    if (!pr_prov_sums_lookup(body, len, file, 0, alg, h)) return 0;
    if (strcmp(alg, "sha512") != 0) return 0;
    memcpy(hex, h, 129);
    return 1;
}

int pr_prov_clearsigned_text(const char *body, size_t len, char **text, size_t *tlen)
{
    static const char HDR[] = "-----BEGIN PGP SIGNED MESSAGE-----";
    static const char SIG[] = "\n-----BEGIN PGP SIGNATURE-----";
    if (!body || len < sizeof HDR - 1 || memcmp(body, HDR, sizeof HDR - 1) != 0) return 0;
    /* Armor headers end at the first empty line. */
    const char *p = body + sizeof HDR - 1, *end = body + len;
    const char *start = NULL;
    while (p < end) {
        const char *nl = memchr(p, '\n', (size_t)(end - p));
        if (!nl) return 0;
        const char *ls = p;
        p = nl + 1;
        size_t n = (size_t)(nl - ls);
        if (n > 0 && ls[n - 1] == '\r') n--;
        if (n == 0 && ls != body + sizeof HDR - 1) { start = p; break; }
        if (n == 0) continue;
    }
    if (!start) return 0;
    const char *sig = NULL;
    for (const char *q = start - 1; q + sizeof SIG - 1 <= end; q++) {
        if (memcmp(q, SIG, sizeof SIG - 1) == 0) { sig = q; break; }
    }
    if (!sig || sig < start) return 0;
    size_t cap = (size_t)(sig - start) + 1;
    char *o = malloc(cap + 1);
    if (!o) return 0;
    size_t w = 0;
    const char *q = start;
    int bol = 1;
    while (q < sig) {
        if (bol && q + 1 < sig && q[0] == '-' && q[1] == ' ') q += 2;
        bol = (*q == '\n');
        o[w++] = *q++;
    }
    o[w] = '\0';
    *text = o;
    if (tlen) *tlen = w;
    return 1;
}

/* ------------------------------------------------------------------ */
/* gpgv                                                               */
/* ------------------------------------------------------------------ */

/* Remove `dir` and the plain files gpgv may have left in it. */
static void remove_flat_dir(const char *dir)
{
    DIR *d = opendir(dir);
    if (d) {
        struct dirent *e;
        while ((e = readdir(d)) != NULL) {
            if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
            char p[512];
            snprintf(p, sizeof p, "%s/%s", dir, e->d_name);
            unlink(p);
        }
        closedir(d);
    }
    rmdir(dir);
}

/* The `n`th (1-based) space-separated field after a status keyword, copied
 * into out when it is exactly `len` hex digits. */
static int status_hex_field(const char *args, int n, size_t len, char *out)
{
    const char *p = args;
    for (int i = 1; i < n; i++) {
        p += strcspn(p, " ");
        if (*p == '\0') return 0;
        p++;
    }
    size_t fl = strcspn(p, " ");
    if (fl != len || !is_hex(p, len)) return 0;
    for (size_t i = 0; i < len; i++) out[i] = (char)toupper((unsigned char)p[i]);
    out[len] = '\0';
    return 1;
}

int pr_prov_gpgv(const char *gpgv, const char *keyring, const char *sig_path,
                 const char *data_path, char primary[41], char subkey[41],
                 char keyid[17])
{
    if (primary) primary[0] = '\0';
    if (subkey) subkey[0] = '\0';
    if (keyid) keyid[0] = '\0';
    if (!keyring || !sig_path) return PR_GPGV_NOKEY;
    char home[] = "/tmp/pr_prov_gnupg_XXXXXX";
    if (!mkdtemp(home)) return PR_GPGV_NORUN;
    int pfd[2];
    if (pipe(pfd) != 0) { remove_flat_dir(home); return PR_GPGV_NORUN; }
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, pfd[1], 1);
    posix_spawn_file_actions_addclose(&fa, pfd[0]);
    posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0);
    const char *bin = (gpgv && gpgv[0]) ? gpgv : "gpgv";
    char *argv[12];
    int a = 0;
    argv[a++] = (char *)bin;
    argv[a++] = (char *)"--homedir";
    argv[a++] = home;
    argv[a++] = (char *)"--status-fd";
    argv[a++] = (char *)"1";
    argv[a++] = (char *)"--keyring";
    argv[a++] = (char *)keyring;
    argv[a++] = (char *)"--";
    argv[a++] = (char *)sig_path;
    if (data_path) argv[a++] = (char *)data_path;
    argv[a] = NULL;
    /* A minimal environment: gpgv needs no token, proxy or locale of ours,
     * and LC_ALL=C keeps the status lines parseable. */
    char *envp[] = { (char *)"PATH=/usr/local/bin:/usr/bin:/bin", (char *)"LC_ALL=C", NULL };
    pid_t pid;
    int rc = posix_spawnp(&pid, bin, &fa, NULL, argv, envp);
    posix_spawn_file_actions_destroy(&fa);
    close(pfd[1]);
    if (rc != 0) { close(pfd[0]); remove_flat_dir(home); return PR_GPGV_NORUN; }
    char buf[8192];
    size_t used = 0;
    ssize_t n;
    while ((n = read(pfd[0], buf + used, sizeof buf - 1 - used)) > 0) {
        used += (size_t)n;
        if (used >= sizeof buf - 1) break;
    }
    /* Drain whatever remains so gpgv never blocks on a full pipe. */
    char sink[1024];
    while (read(pfd[0], sink, sizeof sink) > 0) {}
    close(pfd[0]);
    buf[used] = '\0';
    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    remove_flat_dir(home);
    if (WIFEXITED(status) && WEXITSTATUS(status) == 127) return PR_GPGV_NORUN;

    /* gpgv prints exactly one of GOODSIG / EXPSIG / EXPKEYSIG / REVKEYSIG /
     * BADSIG / ERRSIG per signature; VALIDSIG accompanies the good, expired
     * and revoked ones:
     *   VALIDSIG <signing-fpr> <date> <ts> <expire> <ver> <rsvd> <pkalgo>
     *            <hashalgo> <class> <primary-fpr>                         */
    int bad = 0, good = 0, revoked = 0, expired = 0, valid = 0;
    char sk[41] = "", pk[41] = "";
    char *save = NULL;
    for (char *line = strtok_r(buf, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
        if (strncmp(line, "[GNUPG:] ", 9) != 0) continue;
        const char *kw = line + 9;
        const char *args = kw + strcspn(kw, " ");
        if (*args == ' ') args++;
        size_t kwl = strcspn(kw, " ");
#define KW(s) (kwl == sizeof(s) - 1 && strncmp(kw, s, kwl) == 0)
        if (KW("VALIDSIG")) {
            valid = status_hex_field(args, 1, 40, sk);
            /* field 10 is the primary key; absent on very old gpgv, where
             * the signing key is then the primary */
            if (!status_hex_field(args, 10, 40, pk)) memcpy(pk, sk, sizeof pk);
        } else if (KW("GOODSIG")) {
            good = 1;
        } else if (KW("REVKEYSIG")) {
            revoked = 1;
        } else if (KW("EXPSIG") || KW("EXPKEYSIG")) {
            expired = 1;
        } else if (KW("BADSIG")) {
            bad = 1;
            if (keyid) status_hex_field(args, 1, 16, keyid);
        } else if (KW("ERRSIG") || KW("NO_PUBKEY")) {
            if (keyid) status_hex_field(args, 1, 16, keyid);
        }
#undef KW
    }
    if (bad) return PR_GPGV_BAD;
    if (valid) {
        if (primary) memcpy(primary, pk, 41);
        if (subkey) memcpy(subkey, sk, 41);
    }
    /* Revoked dominates expired dominates good. */
    if (revoked) return PR_GPGV_REVOKED;
    if (expired) return PR_GPGV_EXPIRED;
    /* GOODSIG + VALIDSIG + exit 0: a good signature by a key in the keyring
     * (gpgv never consults a trust database). */
    if (good && valid && WIFEXITED(status) && WEXITSTATUS(status) == 0) return PR_GPGV_GOOD;
    if (primary) primary[0] = '\0';
    if (subkey) subkey[0] = '\0';
    return PR_GPGV_NOKEY;
}

/* ------------------------------------------------------------------ */
/* default fetcher (libcurl)                                          */
/* ------------------------------------------------------------------ */

struct mem { char *d; size_t n, cap, max; int over; };

static size_t mem_cb(char *p, size_t s, size_t k, void *u)
{
    struct mem *m = (struct mem *)u;
    size_t b = s * k;
    if (m->n + b > m->max) { m->over = 1; return 0; }
    if (m->n + b + 1 > m->cap) {
        size_t nc = m->cap ? m->cap * 2 : 16384;
        while (nc < m->n + b + 1) nc *= 2;
        char *q = realloc(m->d, nc);
        if (!q) { m->over = 1; return 0; }
        m->d = q; m->cap = nc;
    }
    memcpy(m->d + m->n, p, b);
    m->n += b;
    m->d[m->n] = '\0';
    return b;
}

int pr_prov_fetch_cap(size_t own, size_t *out)
{
    pr_download_policy_t pol;
    if (pr_download_policy_from_env(&pol) != 0) return -1;
    size_t cap = own;
    if (pol.max_bytes > 0 && (unsigned long long)cap > pol.max_bytes)
        cap = (size_t)pol.max_bytes;
    *out = cap;
    return 0;
}

static long curl_fetch(void *ctx, const char *url, const char *accept, size_t max,
                       char **body, size_t *len)
{
    (void)ctx;
    *body = NULL; *len = 0;
    if (strncmp(url, "https://", 8) != 0) return 0;
    /* PR_MAX_DOWNLOAD_BYTES bounds every evidence fetch too; a malformed
     * value refuses the fetch, as it refuses the tarball download (#324). */
    if (pr_prov_fetch_cap(max, &max) != 0) {
        fprintf(stderr, "::warning::provenance: PR_MAX_DOWNLOAD_BYTES is not a decimal byte "
                "count; evidence fetch refused: %s\n", url);
        return 0;
    }
    CURL *c = curl_easy_init();
    if (!c) return 0;
    struct mem m = { NULL, 0, 0, max, 0 };
    struct curl_slist *h = NULL;
    char host[256];
    const char *tok = getenv("GITHUB_TOKEN");
    char *auth = NULL;
    if (tok && tok[0] && pr_prov_url_host(url, host, sizeof host)
        && strcmp(host, "api.github.com") == 0
        && asprintf(&auth, "Authorization: Bearer %s", tok) >= 0) {
        h = curl_slist_append(h, auth);
    }
    char *acc = NULL;
    if (accept && asprintf(&acc, "Accept: %s", accept) >= 0) h = curl_slist_append(h, acc);
    curl_easy_setopt(c, CURLOPT_URL, url);
    curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(c, CURLOPT_MAXREDIRS, 10L);
#if LIBCURL_VERSION_NUM >= 0x075500
    curl_easy_setopt(c, CURLOPT_PROTOCOLS_STR,       "https");
    curl_easy_setopt(c, CURLOPT_REDIR_PROTOCOLS_STR, "https");
#else
    curl_easy_setopt(c, CURLOPT_PROTOCOLS,       (long)CURLPROTO_HTTPS);
    curl_easy_setopt(c, CURLOPT_REDIR_PROTOCOLS, (long)CURLPROTO_HTTPS);
#endif
    curl_easy_setopt(c, CURLOPT_MAXFILESIZE_LARGE, (curl_off_t)max);
    curl_easy_setopt(c, CURLOPT_TIMEOUT_MS, 30000L);
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, mem_cb);
    curl_easy_setopt(c, CURLOPT_WRITEDATA, &m);
    curl_easy_setopt(c, CURLOPT_USERAGENT, "photonos-package-report/C");
    curl_easy_setopt(c, CURLOPT_ACCEPT_ENCODING, "");
    if (h) curl_easy_setopt(c, CURLOPT_HTTPHEADER, h);
    CURLcode rc = curl_easy_perform(c);
    long status = 0;
    curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &status);
    curl_easy_cleanup(c);
    curl_slist_free_all(h);
    if (auth) { memset(auth, 0, strlen(auth)); free(auth); }
    free(acc);
    if (rc != CURLE_OK || m.over || status != 200) {
        free(m.d);
        return rc == CURLE_OK && !m.over ? status : 0;
    }
    if (!m.d) { m.d = strdup(""); if (!m.d) return 0; }
    *body = m.d; *len = m.n;
    return 200;
}

/* ------------------------------------------------------------------ */
/* the ladder                                                         */
/* ------------------------------------------------------------------ */

static pr_prov_evidence_t *add_ev(pr_prov_record_t *r, const char *rung,
                                  const char *url, pr_prov_result_t res)
{
    if (r->n >= PR_PROV_MAX_EVIDENCE) return NULL;
    pr_prov_evidence_t *e = &r->ev[r->n++];
    memset(e, 0, sizeof *e);
    e->rung = rung;
    e->url = url ? url_noquery(url) : NULL;
    e->result = res;
    e->same_origin = (url && r->url) ? same_host(url, r->url) : 0;
    return e;
}

static void ev_detail(pr_prov_evidence_t *e, const char *fmt, const char *arg)
{
    if (!e) return;
    free(e->detail);
    if (asprintf(&e->detail, fmt, arg ? arg : "") < 0) e->detail = NULL;
}

/* Compare a published digest to the measured bytes. */
static void ev_compare(pr_prov_evidence_t *e, const pr_prov_record_t *r,
                       const char *alg, const char *hex)
{
    if (!e) return;
    snprintf(e->algorithm, sizeof e->algorithm, "%s", alg);
    snprintf(e->expected, sizeof e->expected, "%s", hex);
    const char *act = strcmp(alg, "sha256") == 0 ? r->sha256 : r->sha512;
    snprintf(e->actual, sizeof e->actual, "%s", act);
    e->result = strcmp(hex, act) == 0 ? PR_EV_VERIFIED : PR_EV_MISMATCH;
}

static int write_tmp(const char *data, size_t n, char *path_out, size_t cap)
{
    snprintf(path_out, cap, "/tmp/pr_prov_XXXXXX");
    int fd = mkstemp(path_out);
    if (fd < 0) return -1;
    size_t w = 0;
    while (w < n) {
        ssize_t k = write(fd, data + w, n - w);
        if (k <= 0) { close(fd); unlink(path_out); return -1; }
        w += (size_t)k;
    }
    close(fd);
    return 0;
}

typedef struct {
    const pr_prov_input_t *in;
    pr_prov_fetch_fn       fetch;
    void                  *ctx;
    const char            *vname;  /* the file name the vendor publishes */
} ladder_t;

static long L_fetch(ladder_t *L, const char *url, size_t max, char **b, size_t *n)
{
    return L->fetch(L->ctx, url, NULL, max, b, n);
}

static long L_fetch_accept(ladder_t *L, const char *url, const char *accept,
                           size_t max, char **b, size_t *n)
{
    return L->fetch(L->ctx, url, accept, max, b, n);
}

/* Signature over `data_path` (or inline when NULL) at `sig_url`, whose
 * bytes are `sig`. Fills an evidence row. Returns gpgv's result. */
static int verify_sig(ladder_t *L, pr_prov_record_t *r, const char *sig_url,
                      const char *sig, size_t sig_n, const char *data_path,
                      pr_prov_evidence_t **out_ev)
{
    pr_prov_evidence_t *e = add_ev(r, R_SIGNATURE, sig_url, PR_EV_UNVERIFIABLE);
    if (out_ev) *out_ev = e;
    if (!L->in->keyring || !L->in->keyring[0]) {
        ev_detail(e, "signature present; no keyring configured (PR_PROVENANCE_KEYRING)%s", NULL);
        return PR_GPGV_NOKEY;
    }
    if (L->in->keyring[0] != '/') {
        /* gpgv resolves a bare name against its --homedir, which is a
         * private empty temporary directory: a relative path would silently
         * verify nothing. Refuse it loudly instead. */
        ev_detail(e, "PR_PROVENANCE_KEYRING must be an absolute path; %s was refused",
                  L->in->keyring);
        return PR_GPGV_NOKEY;
    }
    char tmp[64];
    if (write_tmp(sig, sig_n, tmp, sizeof tmp) != 0) {
        ev_detail(e, "could not stage the signature%s", NULL);
        return PR_GPGV_NOKEY;
    }
    char fpr[41], sub[41], keyid[17];
    int g = pr_prov_gpgv(L->in->gpgv, L->in->keyring, tmp, data_path, fpr, sub, keyid);
    unlink(tmp);
    if (!e) return g;
    switch (g) {
    case PR_GPGV_GOOD:
        e->result = PR_EV_VERIFIED;
        memcpy(e->fingerprint, fpr, 41);
        memcpy(e->signing_subkey, sub, 41);
        ev_detail(e, "good signature by a key in the configured keyring%s", NULL);
        break;
    case PR_GPGV_REVOKED:
        e->result = PR_EV_REVOKED;
        memcpy(e->fingerprint, fpr, 41);
        memcpy(e->signing_subkey, sub, 41);
        ev_detail(e, "the signing key %s is REVOKED: not evidence, a stop", fpr);
        break;
    case PR_GPGV_EXPIRED:
        e->result = PR_EV_EXPIRED;
        memcpy(e->fingerprint, fpr, 41);
        memcpy(e->signing_subkey, sub, 41);
        ev_detail(e, "the signature or the signing key %s is EXPIRED: not counted", fpr);
        break;
    case PR_GPGV_BAD:
        e->result = PR_EV_MISMATCH;
        ev_detail(e, "BAD signature by key %s", keyid);
        break;
    case PR_GPGV_NORUN:
        ev_detail(e, "gpgv could not run%s", NULL);
        break;
    default:
        if (keyid[0]) ev_detail(e, "signing key %s is not in the configured keyring", keyid);
        else ev_detail(e, "signature could not be verified%s", NULL);
        break;
    }
    return g;
}

static void rung_detached_signature(ladder_t *L, pr_prov_record_t *r, const char *u)
{
    static const char *EXT[] = { ".sig", ".asc", NULL };
    for (int i = 0; EXT[i]; i++) {
        char *su = NULL;
        if (asprintf(&su, "%s%s", u, EXT[i]) < 0) return;
        char *b = NULL; size_t n = 0;
        long st = L_fetch(L, su, SIG_MAX, &b, &n);
        int is_sig = st == 200 && b && n > 0
            && (strncmp(b, "-----BEGIN PGP SIGNATURE", 24) == 0
                || (unsigned char)b[0] == 0x88 || (unsigned char)b[0] == 0x89
                || (unsigned char)b[0] == 0xc2);
        if (is_sig) verify_sig(L, r, su, b, n, L->in->file_path, NULL);
        free(b);
        free(su);
        if (is_sig) return;
    }
}

/* One checksum file at `url` with body `b`. Records vendor_checksum and,
 * when it is signed, signature evidence. Returns 1 when it listed the file. */
static int consider_sums(ladder_t *L, pr_prov_record_t *r, const char *url,
                         const char *b, size_t n, int allow_bare)
{
    char alg[8], hex[129];
    char *text = NULL; size_t tn = 0;
    int clear = pr_prov_clearsigned_text(b, n, &text, &tn);
    int found = clear ? pr_prov_sums_lookup(text, tn, L->vname, allow_bare, alg, hex)
                      : pr_prov_sums_lookup(b, n, L->vname, allow_bare, alg, hex);
    free(text);
    if (!found) return 0;
    pr_prov_evidence_t *v = add_ev(r, R_VENDOR, url, PR_EV_MISMATCH);
    ev_compare(v, r, alg, hex);
    if (v && v->result == PR_EV_MISMATCH)
        ev_detail(v, "the vendor checksum file disagrees with the downloaded bytes%s", NULL);
    else if (v && v->same_origin)
        ev_detail(v, "same origin as the tarball: integrity, not authenticity%s", NULL);
    /* Signed checksums: inline (clearsigned) or a detached .asc/.sig. */
    pr_prov_evidence_t *s = NULL;
    if (clear) {
        verify_sig(L, r, url, b, n, NULL, &s);
    } else {
        static const char *EXT[] = { ".asc", ".sig", ".gpg", NULL };
        char tmp[64];
        if (write_tmp(b, n, tmp, sizeof tmp) == 0) {
            for (int i = 0; EXT[i]; i++) {
                char *su = NULL;
                if (asprintf(&su, "%s%s", url, EXT[i]) < 0) break;
                char *sb = NULL; size_t sn = 0;
                long st = L_fetch(L, su, SIG_MAX, &sb, &sn);
                int hit = st == 200 && sb && sn > 0;
                if (hit) verify_sig(L, r, su, sb, sn, tmp, &s);
                free(sb); free(su);
                if (hit) break;
            }
            unlink(tmp);
        }
    }
    /* A signature over a checksum list vouches for the tarball only through
     * that list's digest. */
    if (s && v) {
        snprintf(s->algorithm, sizeof s->algorithm, "%s", v->algorithm);
        snprintf(s->expected, sizeof s->expected, "%s", v->expected);
        snprintf(s->actual, sizeof s->actual, "%s", v->actual);
        if (s->result == PR_EV_VERIFIED && v->result != PR_EV_VERIFIED) {
            s->result = PR_EV_MISMATCH;
            ev_detail(s, "the signed checksum list disagrees with the downloaded bytes%s", NULL);
        }
    }
    return 1;
}

static void rung_vendor_checksum(ladder_t *L, pr_prov_record_t *r, const char *u)
{
    char *dir = url_dir(u);
    if (!dir) return;
    /* Per-file sidecars first (a lone digest is accepted there). */
    static const char *PER[] = { ".sha256", ".sha256sum", ".sha512", ".sha512sum", ".sha256.txt", NULL };
    for (int i = 0; PER[i]; i++) {
        char *cu = NULL;
        if (asprintf(&cu, "%s%s", u, PER[i]) < 0) break;
        char *b = NULL; size_t n = 0;
        long st = L_fetch(L, cu, SUMS_MAX, &b, &n);
        int hit = st == 200 && b && consider_sums(L, r, cu, b, n, 1);
        free(b); free(cu);
        if (hit) { free(dir); return; }
    }
    /* GNOME: <stem>.sha256sum beside <stem>.tar.xz. */
    char stem[512];
    snprintf(stem, sizeof stem, "%s", L->vname);
    static const char *ARCH[] = { ".tar.xz", ".tar.gz", ".tar.bz2", ".tar.zst", ".tgz", ".zip", NULL };
    for (int i = 0; ARCH[i]; i++) {
        size_t sl = strlen(stem), al = strlen(ARCH[i]);
        if (sl > al && strcmp(stem + sl - al, ARCH[i]) == 0) { stem[sl - al] = '\0'; break; }
    }
    const char *DIRF[] = { NULL, "SHA256SUMS", "SHA512SUMS", "sha256sums.asc",
                           "sha256sums.txt", "SHA256SUMS.txt", "checksums.txt", NULL };
    char gnome[600];
    snprintf(gnome, sizeof gnome, "%s.sha256sum", stem);
    DIRF[0] = gnome;
    for (int i = 0; DIRF[i]; i++) {
        char *cu = NULL;
        if (asprintf(&cu, "%s%s", dir, DIRF[i]) < 0) break;
        char *b = NULL; size_t n = 0;
        long st = L_fetch(L, cu, SUMS_MAX, &b, &n);
        int hit = st == 200 && b && consider_sums(L, r, cu, b, n, 0);
        free(b); free(cu);
        if (hit) break;
    }
    free(dir);
}

static void normalise_pypi(char *s)
{
    char *w = s;
    int dash = 0;
    for (char *p = s; *p; p++) {
        char c = (char)tolower((unsigned char)*p);
        if (c == '-' || c == '_' || c == '.') { if (!dash) *w++ = '-'; dash = 1; }
        else { *w++ = c; dash = 0; }
    }
    *w = '\0';
}

static void rung_registry(ladder_t *L, pr_prov_record_t *r, const char *u)
{
    char host[256];
    if (!pr_prov_url_host(u, host, sizeof host)) return;
    const char *path = strstr(u, "://") + 3;
    path += strcspn(path, "/");
    char *api = NULL;
    char hex[65];
    int kind = 0;
    if (!strcmp(host, "files.pythonhosted.org") || !strcmp(host, "pypi.org")
        || !strcmp(host, "pypi.io") || !strcmp(host, "pypi.python.org")) {
        char proj[256] = "";
        const char *s = strstr(path, "/packages/source/");
        if (s) {
            s += 17;
            const char *a = strchr(s, '/');
            if (a) { const char *b = strchr(a + 1, '/');
                if (b && (size_t)(b - a - 1) < sizeof proj) { memcpy(proj, a + 1, (size_t)(b - a - 1)); proj[b - a - 1] = '\0'; } }
        }
        if (!proj[0]) {
            /* hashed /packages/xx/yy/<hash>/<file>: the sdist name up to
             * the version. */
            const char *f = L->vname;
            size_t i = 0;
            while (f[i] && !(f[i] == '-' && isdigit((unsigned char)f[i + 1])) && i < sizeof proj - 1) { proj[i] = f[i]; i++; }
            proj[i] = '\0';
        }
        normalise_pypi(proj);
        /* PEP 691 JSON is content-negotiated (the ?format= query is not
         * honoured by pypi.org). */
        if (proj[0] && asprintf(&api, "https://pypi.org/simple/%s/", proj) >= 0)
            kind = 1;
    } else if (!strcmp(host, "rubygems.org") && strncmp(path, "/downloads/", 11) == 0) {
        const char *f = L->vname;
        size_t fl = strlen(f);
        if (fl > 4 && !strcmp(f + fl - 4, ".gem")) {
            const char *dash = NULL;
            for (const char *q = f; q < f + fl - 4; q++)
                if (*q == '-' && isdigit((unsigned char)q[1])) dash = q;
            if (dash && asprintf(&api, "https://rubygems.org/api/v2/rubygems/%.*s/versions/%.*s.json",
                                 (int)(dash - f), f, (int)(f + fl - 4 - dash - 1), dash + 1) >= 0)
                kind = 2;
        }
    } else if (!strcmp(host, "github.com")) {
        /* /<o>/<r>/releases/download/<tag>/<asset> */
        char o[128], rp[128], tag[256];
        if (sscanf(path, "/%127[^/]/%127[^/]/releases/download/%255[^/]/", o, rp, tag) == 3
            && asprintf(&api, "https://api.github.com/repos/%s/%s/releases/tags/%s", o, rp, tag) >= 0)
            kind = 3;
    }
    if (!kind) return;
    char *b = NULL; size_t n = 0;
    long st = kind == 1
        ? L_fetch_accept(L, api, "application/vnd.pypi.simple.v1+json", INDEX_MAX, &b, &n)
        : L_fetch_accept(L, api, kind == 3 ? "application/vnd.github+json" : NULL, INDEX_MAX, &b, &n);
    int ok = 0;
    if (st == 200 && b) {
        if (kind == 1) ok = pr_prov_pypi_sha256(b, n, L->vname, hex);
        else if (kind == 2) ok = pr_prov_rubygems_sha256(b, n, hex);
        else ok = pr_prov_github_digest(b, n, L->vname, hex);
    }
    if (ok) {
        pr_prov_evidence_t *e = add_ev(r, R_REGISTRY, api, PR_EV_MISMATCH);
        ev_compare(e, r, "sha256", hex);
        if (e && e->result == PR_EV_MISMATCH)
            ev_detail(e, "the package index's digest disagrees with the downloaded bytes%s", NULL);
    } else if (st == 200) {
        pr_prov_evidence_t *e = add_ev(r, R_REGISTRY, api, PR_EV_UNVERIFIABLE);
        ev_detail(e, "the package index lists no digest for this file%s", NULL);
    }
    free(b);
    free(api);
}

static void rung_corroboration(ladder_t *L, pr_prov_record_t *r)
{
    if (!r->package || !r->package[0]) return;
    for (const char *p = r->package; *p; p++)
        if (!(isalnum((unsigned char)*p) || strchr("+-._", *p))) return;
    char *fu = NULL;
    if (asprintf(&fu, "https://src.fedoraproject.org/rpms/%s/raw/rawhide/f/sources", r->package) < 0) return;
    char *b = NULL; size_t n = 0;
    long st = L_fetch(L, fu, SUMS_MAX, &b, &n);
    char hex[129];
    if (st == 200 && b && (pr_prov_fedora_sha512(b, n, L->vname, hex)
                           || pr_prov_fedora_sha512(b, n, r->file, hex))) {
        pr_prov_evidence_t *e = add_ev(r, R_CORROB, fu, PR_EV_MISMATCH);
        ev_compare(e, r, "sha512", hex);
        if (e) ev_detail(e, e->result == PR_EV_VERIFIED
            ? "Fedora's lookaside records the same file with the same digest%s"
            : "Fedora's lookaside records this file name with ANOTHER digest%s", NULL);
    }
    free(b);
    free(fu);
}

static const char *rank[] = { "signature", "vendor_checksum", "registry_digest", "corroborated", NULL };

static void conclude(pr_prov_record_t *r)
{
    int mismatch = 0, best = 99;
    for (size_t i = 0; i < r->n; i++) {
        /* A revoked signer is as much a stop as a contradiction. */
        if (r->ev[i].result == PR_EV_MISMATCH || r->ev[i].result == PR_EV_REVOKED) mismatch = 1;
        if (r->ev[i].result != PR_EV_VERIFIED) continue;
        for (int k = 0; rank[k]; k++)
            if (!strcmp(rank[k], r->ev[i].rung) && k < best) best = k;
    }
    if (mismatch) { r->verdict = "mismatch"; r->rung = best < 99 ? rank[best] : R_TOFU; }
    else if (best < 99) { r->verdict = "verified"; r->rung = rank[best]; }
    else { r->verdict = "unverified"; r->rung = R_TOFU; }
}

int pr_provenance_verify(const pr_prov_input_t *in, pr_prov_record_t *out)
{
    memset(out, 0, sizeof *out);
    if (!in || !in->file_path || !in->url) return -1;
    struct stat st;
    if (stat(in->file_path, &st) != 0 || !S_ISREG(st.st_mode)) return -1;
    char *h256 = pr_sha_file(PR_SHA256, in->file_path);
    char *h512 = pr_sha_file(PR_SHA512, in->file_path);
    if (!h256 || !h512) { free(h256); free(h512); return -1; }
    lower_into(out->sha256, h256, 64);
    lower_into(out->sha512, h512, 128);
    free(h256); free(h512);
    out->size = (unsigned long long)st.st_size;
    out->url = url_noquery(in->url);
    const char *fp = strrchr(in->file_path, '/');
    out->file = strdup(fp ? fp + 1 : in->file_path);
    out->package = strdup(in->package ? in->package : "");
    out->spec = strdup(in->spec ? in->spec : "");
    if (!out->url || !out->file || !out->package || !out->spec) { pr_provenance_free(out); return -1; }

    char *vname = url_basename(out->url);
    if (!vname) { pr_provenance_free(out); return -1; }
    ladder_t L = { in, in->fetch ? in->fetch : curl_fetch, in->fetch_ctx, vname };
    if (strncmp(out->url, "https://", 8) == 0) {
        rung_detached_signature(&L, out, out->url);
        rung_vendor_checksum(&L, out, out->url);
        rung_registry(&L, out, out->url);
    }
    rung_corroboration(&L, out);
    conclude(out);
    free(vname);
    return 0;
}

/* ------------------------------------------------------------------ */
/* JSON                                                               */
/* ------------------------------------------------------------------ */

struct sb { char *d; size_t n, cap; int err; };

static void sb_put(struct sb *s, const char *p, size_t k)
{
    if (s->err) return;
    if (s->n + k + 1 > s->cap) {
        size_t nc = s->cap ? s->cap * 2 : 1024;
        while (nc < s->n + k + 1) nc *= 2;
        char *q = realloc(s->d, nc);
        if (!q) { s->err = 1; return; }
        s->d = q; s->cap = nc;
    }
    memcpy(s->d + s->n, p, k);
    s->n += k;
    s->d[s->n] = '\0';
}

static void sb_s(struct sb *s, const char *p) { sb_put(s, p, strlen(p)); }

static void sb_str(struct sb *s, const char *v)
{
    sb_s(s, "\"");
    for (const unsigned char *p = (const unsigned char *)(v ? v : ""); *p; p++) {
        char esc[8];
        switch (*p) {
        case '"':  sb_s(s, "\\\""); break;
        case '\\': sb_s(s, "\\\\"); break;
        case '\n': sb_s(s, "\\n"); break;
        case '\r': sb_s(s, "\\r"); break;
        case '\t': sb_s(s, "\\t"); break;
        default:
            if (*p < 0x20) { snprintf(esc, sizeof esc, "\\u%04x", *p); sb_s(s, esc); }
            else sb_put(s, (const char *)p, 1);
        }
    }
    sb_s(s, "\"");
}

static void sb_kv(struct sb *s, const char *k, const char *v, int comma)
{
    sb_str(s, k); sb_s(s, ":"); sb_str(s, v); if (comma) sb_s(s, ",");
}

static const char *res_name(pr_prov_result_t r)
{
    switch (r) {
    case PR_EV_VERIFIED: return "verified";
    case PR_EV_MISMATCH: return "mismatch";
    case PR_EV_REVOKED:  return "revoked";
    case PR_EV_EXPIRED:  return "expired";
    case PR_EV_UNVERIFIABLE: break;
    }
    return "unverifiable";
}

char *pr_provenance_json(const pr_prov_record_t *r)
{
    struct sb s = { 0 };
    char num[32];
    sb_s(&s, "{");
    sb_kv(&s, "schema", PR_PROVENANCE_SCHEMA, 1);
    sb_kv(&s, "package", r->package, 1);
    sb_kv(&s, "spec", r->spec, 1);
    sb_kv(&s, "file", r->file, 1);
    sb_kv(&s, "url", r->url, 1);
    snprintf(num, sizeof num, "%llu", r->size);
    sb_str(&s, "size"); sb_s(&s, ":"); sb_s(&s, num); sb_s(&s, ",");
    sb_kv(&s, "sha256", r->sha256, 1);
    sb_kv(&s, "sha512", r->sha512, 1);
    sb_kv(&s, "verdict", r->verdict ? r->verdict : "unverified", 1);
    sb_kv(&s, "rung", r->rung ? r->rung : R_TOFU, 1);
    sb_str(&s, "evidence"); sb_s(&s, ":[");
    for (size_t i = 0; i < r->n; i++) {
        const pr_prov_evidence_t *e = &r->ev[i];
        if (i) sb_s(&s, ",");
        sb_s(&s, "{");
        sb_kv(&s, "rung", e->rung, 1);
        sb_kv(&s, "url", e->url, 1);
        sb_kv(&s, "result", res_name(e->result), 1);
        sb_str(&s, "same_origin"); sb_s(&s, e->same_origin ? ":true," : ":false,");
        sb_kv(&s, "algorithm", e->algorithm, 1);
        sb_kv(&s, "expected", e->expected, 1);
        sb_kv(&s, "actual", e->actual, 1);
        sb_kv(&s, "fingerprint", e->fingerprint, 1);
        sb_kv(&s, "signing_subkey", e->signing_subkey, 1);
        sb_kv(&s, "detail", e->detail, 0);
        sb_s(&s, "}");
    }
    sb_s(&s, "]}\n");
    if (s.err) { free(s.d); return NULL; }
    return s.d;
}

int pr_provenance_write(const pr_prov_record_t *r, const char *path)
{
    char *j = pr_provenance_json(r);
    if (!j) return -1;
    char *tmp = NULL;
    if (asprintf(&tmp, "%s.tmp.%ld", path, (long)getpid()) < 0) { free(j); return -1; }
    FILE *f = fopen(tmp, "wb");
    int rc = -1;
    if (f) {
        size_t n = strlen(j);
        int ok = fwrite(j, 1, n, f) == n;
        ok = (fflush(f) == 0) && ok;
        ok = (fsync(fileno(f)) == 0) && ok;
        ok = (fclose(f) == 0) && ok;
        if (ok && rename(tmp, path) == 0) rc = 0;
        else unlink(tmp);
    }
    free(tmp);
    free(j);
    return rc;
}

void pr_provenance_free(pr_prov_record_t *r)
{
    if (!r) return;
    free(r->file); free(r->url); free(r->package); free(r->spec);
    for (size_t i = 0; i < r->n; i++) { free(r->ev[i].url); free(r->ev[i].detail); }
    memset(r, 0, sizeof *r);
}

void pr_provenance_after_download(const char *package, const char *spec,
                                  const char *url, const char *file_path)
{
    if (!pr_provenance_enabled() || !url || !file_path) return;
    if (access(file_path, R_OK) != 0) return;
    pr_prov_input_t in = { 0 };
    in.package = package;
    in.spec = spec;
    in.url = url;
    in.file_path = file_path;
    const char *kr = getenv("PR_PROVENANCE_KEYRING");
    in.keyring = (kr && kr[0]) ? kr : NULL;
    const char *gv = getenv("PR_PROVENANCE_GPGV");
    in.gpgv = (gv && gv[0]) ? gv : NULL;
    pr_prov_record_t rec;
    if (pr_provenance_verify(&in, &rec) != 0) {
        fprintf(stderr, "::warning::provenance: %s could not be read; no record\n", file_path);
        return;
    }
    char *out = NULL;
    if (asprintf(&out, "%s%s", file_path, PR_PROVENANCE_SUFFIX) >= 0) {
        if (pr_provenance_write(&rec, out) != 0)
            fprintf(stderr, "::warning::provenance: could not write %s\n", out);
        free(out);
    }
    pr_provenance_free(&rec);
}
