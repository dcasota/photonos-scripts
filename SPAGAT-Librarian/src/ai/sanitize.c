#include "sanitize.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* ------------------------------------------------------------------ */
/*  Helpers                                                           */
/* ------------------------------------------------------------------ */

static int is_base64_char(char c)
{
    return isalnum((unsigned char)c) || c == '+' || c == '/' || c == '=';
}

/*
 * Replace `len` bytes at position `pos` in `text` with `replacement`.
 * `text_size` is the total buffer capacity.  Returns the length delta
 * (new_len - old_len) or 0 on overflow.
 */
static int replace_range(char *text, int text_size,
                         int pos, int len, const char *replacement)
{
    int tlen   = (int)strlen(text);
    int rlen   = (int)strlen(replacement);
    int delta  = rlen - len;
    int newlen = tlen + delta;

    if (newlen >= text_size)
        return 0;

    memmove(text + pos + rlen, text + pos + len,
            (size_t)(tlen - pos - len + 1));   /* +1 for NUL */
    memcpy(text + pos, replacement, (size_t)rlen);
    return delta;
}

/* ------------------------------------------------------------------ */
/*  Private key blocks                                                */
/* ------------------------------------------------------------------ */

static int redact_private_keys(char *text, int text_size)
{
    int count = 0;
    char *p   = text;

    while ((p = strstr(p, "-----BEGIN")) != NULL) {
        char *key_hdr = strstr(p, "PRIVATE KEY-----");
        if (!key_hdr || key_hdr - p > 80) {
            p++;
            continue;
        }
        /* find matching END marker */
        char *end = strstr(key_hdr, "-----END");
        if (!end) {
            p++;
            continue;
        }
        char *end_line = strchr(end, '\n');
        if (!end_line)
            end_line = end + strlen(end);
        else
            end_line++;

        int pos = (int)(p - text);
        int len = (int)(end_line - p);
        int d   = replace_range(text, text_size, pos, len,
                                "[REDACTED: private key]\n");
        if (d == 0) { p++; continue; }
        p = text + pos + (int)strlen("[REDACTED: private key]\n");
        count++;
    }
    return count;
}

/* ------------------------------------------------------------------ */
/*  Shadow file entries                                               */
/* ------------------------------------------------------------------ */

static int is_shadow_hash(const char *s)
{
    /* look for $1$, $5$, $6$, $y$ */
    if (s[0] != '$') return 0;
    if ((s[1] == '1' || s[1] == '5' || s[1] == '6' || s[1] == 'y') &&
        s[2] == '$')
        return 1;
    return 0;
}

static int redact_shadow_entries(char *text, int text_size)
{
    int   count = 0;
    char *p     = text;

    while (*p) {
        /* find start of line */
        char *line_start = p;
        char *eol        = strchr(p, '\n');
        int   line_len   = eol ? (int)(eol - p) : (int)strlen(p);

        /* shadow format: "user:$hash:..." — look for colon then hash */
        char *colon = memchr(line_start, ':', (size_t)line_len);
        if (colon && colon < line_start + line_len - 3) {
            if (is_shadow_hash(colon + 1)) {
                int pos = (int)(line_start - text);
                int d   = replace_range(text, text_size, pos, line_len,
                                        "[REDACTED: shadow entry]");
                if (d != 0) {
                    count++;
                    p = text + pos + (int)strlen("[REDACTED: shadow entry]");
                    if (*p == '\n') p++;
                    continue;
                }
            }
        }

        p = eol ? eol + 1 : line_start + line_len;
    }
    return count;
}

/* ------------------------------------------------------------------ */
/*  AWS-style keys                                                    */
/* ------------------------------------------------------------------ */

static int redact_aws_keys(char *text, int text_size)
{
    int   count = 0;
    char *p     = text;

    while (*p) {
        /* look for AKIA or ABIA prefix */
        if ((p[0] == 'A' && p[1] == 'K' && p[2] == 'I' && p[3] == 'A') ||
            (p[0] == 'A' && p[1] == 'B' && p[2] == 'I' && p[3] == 'A')) {
            /* count contiguous uppercase + digits */
            int len = 0;
            while (isupper((unsigned char)p[len]) ||
                   isdigit((unsigned char)p[len]))
                len++;
            if (len >= 20) {
                int pos = (int)(p - text);
                int d   = replace_range(text, text_size, pos, len,
                                        "[REDACTED: API key]");
                if (d != 0) {
                    count++;
                    p = text + pos + (int)strlen("[REDACTED: API key]");
                    continue;
                }
            }
        }
        p++;
    }
    return count;
}

/* ------------------------------------------------------------------ */
/*  Generic long base64                                               */
/* ------------------------------------------------------------------ */

static int redact_long_base64(char *text, int text_size)
{
    int   count = 0;
    char *p     = text;

    while (*p) {
        if (is_base64_char(*p)) {
            int run = 0;
            while (p[run] && is_base64_char(p[run]) && p[run] != '\n')
                run++;
            if (run >= 40) {
                int pos = (int)(p - text);
                int d   = replace_range(text, text_size, pos, run,
                                        "[REDACTED: encoded credential]");
                if (d != 0) {
                    count++;
                    p = text + pos +
                        (int)strlen("[REDACTED: encoded credential]");
                    continue;
                }
            }
            p += (run > 0 ? run : 1);
        } else {
            p++;
        }
    }
    return count;
}

/* ------------------------------------------------------------------ */
/*  Bearer tokens                                                     */
/* ------------------------------------------------------------------ */

static int redact_bearer_tokens(char *text, int text_size)
{
    int         count  = 0;
    const char *needle = "Bearer ";
    int         nlen   = (int)strlen(needle);
    char       *p      = text;

    while ((p = strstr(p, needle)) != NULL) {
        char *tok = p + nlen;
        int   tlen = 0;
        while (tok[tlen] && !isspace((unsigned char)tok[tlen]) &&
               tok[tlen] != '"' && tok[tlen] != '\'')
            tlen++;
        if (tlen > 8) {
            int pos = (int)(tok - text);
            int d   = replace_range(text, text_size, pos, tlen,
                                    "[REDACTED]");
            if (d != 0) {
                count++;
                p = text + pos + (int)strlen("[REDACTED]");
                continue;
            }
        }
        p = tok + tlen;
    }
    return count;
}

/* ------------------------------------------------------------------ */
/*  Password patterns                                                 */
/* ------------------------------------------------------------------ */

static int redact_passwords(char *text, int text_size)
{
    int         count = 0;
    const char *pats[] = { "password=", "passwd=" };
    int         npats  = 2;
    int         pi;

    for (pi = 0; pi < npats; pi++) {
        char *p = text;
        int   plen = (int)strlen(pats[pi]);

        while ((p = strstr(p, pats[pi])) != NULL) {
            char *val = p + plen;
            int   vlen = 0;
            while (val[vlen] && !isspace((unsigned char)val[vlen]) &&
                   val[vlen] != '\n')
                vlen++;
            if (vlen > 0) {
                int pos = (int)(val - text);
                int d   = replace_range(text, text_size, pos, vlen,
                                        "[REDACTED]");
                if (d != 0) {
                    count++;
                    p = text + pos + (int)strlen("[REDACTED]");
                    continue;
                }
            }
            p = val + vlen;
        }
    }
    return count;
}

/* ------------------------------------------------------------------ */
/*  Public API                                                        */
/* ------------------------------------------------------------------ */

int sanitize_redact_secrets(char *text, int text_size)
{
    int total = 0;

    if (!text || text_size <= 0)
        return 0;

    /* Order matters: private keys first (they contain base64),
       then shadow, AWS, bearer, passwords, then generic base64 last
       to avoid false-positives on already-redacted text. */
    total += redact_private_keys(text, text_size);
    total += redact_shadow_entries(text, text_size);
    total += redact_aws_keys(text, text_size);
    total += redact_bearer_tokens(text, text_size);
    total += redact_passwords(text, text_size);
    total += redact_long_base64(text, text_size);

    return total;
}

bool sanitize_contains_secret(const char *text)
{
    char *buf;
    int   len;
    int   n;

    if (!text)
        return false;

    len = (int)strlen(text);
    buf = (char *)malloc((size_t)(len + 1));
    if (!buf)
        return false;

    memcpy(buf, text, (size_t)(len + 1));
    n = sanitize_redact_secrets(buf, len + 1);
    free(buf);

    return n > 0;
}

void sanitize_redact_value(const char *value, char *output, int output_size)
{
    int vlen;

    if (!value || !output || output_size <= 0)
        return;

    vlen = (int)strlen(value);

    if (vlen < 5) {
        snprintf(output, (size_t)output_size, "***");
    } else {
        snprintf(output, (size_t)output_size, "%.3s***%c",
                 value, value[vlen - 1]);
    }
}
