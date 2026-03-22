#include "csv_parser.h"
#include "security.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static void csv_row_init(csv_row_t *r)
{
    memset(r, 0, sizeof(*r));
}

static char *safe_strdup(const char *s)
{
    if (!s || s[0] == '\0')
        return NULL;
    size_t len = strlen(s);
    if (len > MAX_FIELD_LEN)
        len = MAX_FIELD_LEN;
    char *d = malloc(len + 1);
    if (!d)
        return NULL;
    memcpy(d, s, len);
    d[len] = '\0';
    return d;
}

static void csv_row_free_fields(csv_row_t *r)
{
    free(r->spec);
    free(r->source0_original);
    free(r->modified_source0);
    free(r->url_health);
    free(r->update_available);
    free(r->update_url);
    free(r->health_update_url);
    free(r->name);
    free(r->sha_name);
    free(r->update_download_name);
    free(r->warning);
    free(r->archivation_date);
}

void csv_data_free(csv_data_t *data)
{
    if (!data)
        return;
    for (int i = 0; i < data->count; i++)
        csv_row_free_fields(&data->rows[i]);
    free(data->rows);
    data->rows = NULL;
    data->count = 0;
    data->capacity = 0;
}

static int csv_data_grow(csv_data_t *data)
{
    int new_cap = data->capacity == 0 ? 256 : data->capacity * 2;
    if (new_cap > MAX_ROWS_PER_FILE)
        new_cap = MAX_ROWS_PER_FILE;
    if (data->count >= new_cap)
        return -1;
    csv_row_t *nr = realloc(data->rows, (size_t)new_cap * sizeof(csv_row_t));
    if (!nr)
        return -1;
    data->rows = nr;
    data->capacity = new_cap;
    return 0;
}

/* Parse a CSV line, handling quoted fields (commas inside quotes).
   fields[] is filled with pointers into the mutable line buffer.
   Returns field count. */
static int parse_csv_line(char *line, char **fields, int max_fields)
{
    int count = 0;
    char *p = line;

    while (*p && count < max_fields) {
        if (*p == '"') {
            p++;
            fields[count] = p;
            while (*p) {
                if (*p == '"') {
                    if (*(p + 1) == '"') {
                        memmove(p, p + 1, strlen(p));
                        p++;
                    } else {
                        *p = '\0';
                        p++;
                        if (*p == ',')
                            p++;
                        break;
                    }
                } else {
                    p++;
                }
            }
        } else {
            fields[count] = p;
            while (*p && *p != ',')
                p++;
            if (*p == ',') {
                *p = '\0';
                p++;
            }
        }
        count++;
    }
    return count;
}

char *utf16le_to_utf8(const unsigned char *buf, size_t byte_len)
{
    size_t out_alloc = byte_len + 1;
    char *out = malloc(out_alloc);
    if (!out)
        return NULL;

    size_t oi = 0;
    size_t i = 0;

    /* Skip BOM if present */
    if (byte_len >= 2 && buf[0] == 0xFF && buf[1] == 0xFE)
        i = 2;

    while (i + 1 < byte_len && oi < out_alloc - 4) {
        unsigned int cp = (unsigned int)buf[i] | ((unsigned int)buf[i + 1] << 8);
        i += 2;

        /* Handle surrogate pairs */
        if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < byte_len) {
            unsigned int lo = (unsigned int)buf[i] | ((unsigned int)buf[i + 1] << 8);
            if (lo >= 0xDC00 && lo <= 0xDFFF) {
                cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                i += 2;
            }
        }

        if (cp < 0x80) {
            out[oi++] = (char)cp;
        } else if (cp < 0x800) {
            out[oi++] = (char)(0xC0 | (cp >> 6));
            out[oi++] = (char)(0x80 | (cp & 0x3F));
        } else if (cp < 0x10000) {
            out[oi++] = (char)(0xE0 | (cp >> 12));
            out[oi++] = (char)(0x80 | ((cp >> 6) & 0x3F));
            out[oi++] = (char)(0x80 | (cp & 0x3F));
        } else {
            out[oi++] = (char)(0xF0 | (cp >> 18));
            out[oi++] = (char)(0x80 | ((cp >> 12) & 0x3F));
            out[oi++] = (char)(0x80 | ((cp >> 6) & 0x3F));
            out[oi++] = (char)(0x80 | (cp & 0x3F));
        }
    }
    out[oi] = '\0';
    return out;
}

static int detect_schema(const char *header_line)
{
    int commas = 0;
    for (const char *p = header_line; *p; p++) {
        if (*p == ',')
            commas++;
    }
    /* 12-column has 11 commas, 5-column has 4 commas */
    if (commas >= 10)
        return CSV_SCHEMA_NEW;
    return CSV_SCHEMA_OLD;
}

static void strip_trailing_whitespace(char *s)
{
    if (!s)
        return;
    size_t len = strlen(s);
    while (len > 0 && (s[len - 1] == '\r' || s[len - 1] == '\n' || s[len - 1] == ' ' || s[len - 1] == '\t'))
        s[--len] = '\0';
}

int csv_parse_file(const char *filepath, csv_data_t *out)
{
    if (!filepath || !out)
        return -1;

    memset(out, 0, sizeof(*out));

    struct stat st;
    if (stat(filepath, &st) != 0)
        return -1;
    if (st.st_size == 0)
        return -1;
    if (st.st_size > MAX_FILE_SIZE) {
        fprintf(stderr, "File too large (>50MB): %s\n", filepath);
        return -1;
    }

    FILE *f = fopen(filepath, "rb");
    if (!f)
        return -1;

    size_t fsize = (size_t)st.st_size;
    unsigned char *raw = malloc(fsize + 1);
    if (!raw) {
        fclose(f);
        return -1;
    }

    size_t nread = fread(raw, 1, fsize, f);
    fclose(f);
    if (nread == 0) {
        free(raw);
        return -1;
    }
    raw[nread] = '\0';

    char *text = NULL;
    /* Detect UTF-16LE BOM */
    if (nread >= 2 && raw[0] == 0xFF && raw[1] == 0xFE) {
        text = utf16le_to_utf8(raw, nread);
        free(raw);
        if (!text)
            return -1;
    } else {
        /* Skip UTF-8 BOM if present */
        if (nread >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF) {
            text = malloc(nread - 2);
            if (!text) { free(raw); return -1; }
            memcpy(text, raw + 3, nread - 3);
            text[nread - 3] = '\0';
            free(raw);
        } else {
            text = (char *)raw;
        }
    }

    /* Parse line by line */
    char *saveptr = NULL;
    char *line = strtok_r(text, "\n", &saveptr);
    if (!line) {
        free(text);
        return -1;
    }

    strip_trailing_whitespace(line);
    out->schema_version = detect_schema(line);

    /* Skip header line */
    line = strtok_r(NULL, "\n", &saveptr);

    while (line) {
        strip_trailing_whitespace(line);
        if (line[0] == '\0') {
            line = strtok_r(NULL, "\n", &saveptr);
            continue;
        }

        if (out->count >= MAX_ROWS_PER_FILE)
            break;

        if (out->count >= out->capacity) {
            if (csv_data_grow(out) != 0)
                break;
        }

        char *fields[16];
        memset(fields, 0, sizeof(fields));
        int nfields = parse_csv_line(line, fields, 16);

        csv_row_t *r = &out->rows[out->count];
        csv_row_init(r);

        if (nfields >= 1) r->spec = safe_strdup(fields[0]);
        if (nfields >= 2) r->source0_original = safe_strdup(fields[1]);
        if (nfields >= 3) r->modified_source0 = safe_strdup(fields[2]);
        if (nfields >= 4) r->url_health = safe_strdup(fields[3]);
        if (nfields >= 5) r->update_available = safe_strdup(fields[4]);

        if (out->schema_version == CSV_SCHEMA_NEW) {
            if (nfields >= 6)  r->update_url = safe_strdup(fields[5]);
            if (nfields >= 7)  r->health_update_url = safe_strdup(fields[6]);
            if (nfields >= 8)  r->name = safe_strdup(fields[7]);
            if (nfields >= 9)  r->sha_name = safe_strdup(fields[8]);
            if (nfields >= 10) r->update_download_name = safe_strdup(fields[9]);
            if (nfields >= 11) r->warning = safe_strdup(fields[10]);
            if (nfields >= 12) r->archivation_date = safe_strdup(fields[11]);
        }

        /* Derive name from spec if missing */
        if (!r->name && r->spec) {
            char tmp[512];
            secure_strncpy(tmp, r->spec, sizeof(tmp));
            char *dot = strstr(tmp, ".spec");
            if (dot)
                *dot = '\0';
            r->name = safe_strdup(tmp);
        }

        out->count++;
        line = strtok_r(NULL, "\n", &saveptr);
    }

    free(text);
    return 0;
}
