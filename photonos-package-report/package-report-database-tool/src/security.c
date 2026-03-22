#include "security.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <limits.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

int secure_resolve_path(const char *input, char *resolved, size_t resolved_sz)
{
    if (!input || !resolved || resolved_sz < 2)
        return -1;
    resolved[0] = '\0';

    if (strlen(input) >= MAX_PATH_LEN)
        return -1;

#ifdef _WIN32
    char tmp[MAX_PATH_LEN];
    DWORD ret = GetFullPathNameA(input, sizeof(tmp), tmp, NULL);
    if (ret == 0 || ret >= sizeof(tmp))
        return -1;
    secure_strncpy(resolved, tmp, resolved_sz);
#else
    char *rp = realpath(input, NULL);
    if (!rp) {
        /* Path may not exist yet; resolve parent */
        char buf[MAX_PATH_LEN];
        secure_strncpy(buf, input, sizeof(buf));
        char *slash = strrchr(buf, '/');
        if (slash && slash != buf) {
            *slash = '\0';
            rp = realpath(buf, NULL);
            if (!rp)
                return -1;
            size_t len = strlen(rp);
            if (len + 1 + strlen(slash + 1) + 1 > resolved_sz) {
                free(rp);
                return -1;
            }
            snprintf(resolved, resolved_sz, "%s/%s", rp, slash + 1);
            free(rp);
            return 0;
        }
        return -1;
    }
    if (strlen(rp) >= resolved_sz) {
        free(rp);
        return -1;
    }
    secure_strncpy(resolved, rp, resolved_sz);
    free(rp);
#endif
    return 0;
}

int secure_check_path_prefix(const char *resolved, const char *base_dir)
{
    if (!resolved || !base_dir)
        return -1;
    size_t base_len = strlen(base_dir);
    if (strncmp(resolved, base_dir, base_len) != 0)
        return -1;
    if (resolved[base_len] != '/' && resolved[base_len] != '\0')
        return -1;
    return 0;
}

int secure_validate_filename(const char *filename)
{
    if (!filename || filename[0] == '\0')
        return -1;
    if (strlen(filename) >= MAX_PATH_LEN)
        return -1;
    if (strstr(filename, "..") != NULL)
        return -1;
    for (const char *p = filename; *p; p++) {
        if (*p == '/' || *p == '\\')
            return -1;
        if ((unsigned char)*p < 0x20 && *p != '\t')
            return -1;
    }
    return 0;
}

char *secure_xml_escape(const char *input)
{
    if (!input)
        return NULL;

    size_t len = 0;
    for (const char *p = input; *p; p++) {
        switch (*p) {
        case '&':  len += 5; break;
        case '<':  len += 4; break;
        case '>':  len += 4; break;
        case '"':  len += 6; break;
        case '\'': len += 6; break;
        default:   len += 1; break;
        }
    }

    char *out = malloc(len + 1);
    if (!out)
        return NULL;

    char *d = out;
    for (const char *p = input; *p; p++) {
        switch (*p) {
        case '&':  memcpy(d, "&amp;", 5);  d += 5; break;
        case '<':  memcpy(d, "&lt;", 4);   d += 4; break;
        case '>':  memcpy(d, "&gt;", 4);   d += 4; break;
        case '"':  memcpy(d, "&quot;", 6); d += 6; break;
        case '\'': memcpy(d, "&apos;", 6); d += 6; break;
        default:   *d++ = *p; break;
        }
    }
    *d = '\0';
    return out;
}

void secure_strncpy(char *dst, const char *src, size_t dst_sz)
{
    if (!dst || dst_sz == 0)
        return;
    if (!src) {
        dst[0] = '\0';
        return;
    }
    size_t i;
    for (i = 0; i < dst_sz - 1 && src[i]; i++)
        dst[i] = src[i];
    dst[i] = '\0';
}
