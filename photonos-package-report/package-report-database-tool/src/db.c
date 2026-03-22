#include "db.h"
#include "security.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>

/* SHA-256 implementation (standalone, no OpenSSL dependency) */
static const unsigned int K256[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

#define ROTR(x,n) (((x)>>(n))|((x)<<(32-(n))))
#define CH(x,y,z) (((x)&(y))^(~(x)&(z)))
#define MAJ(x,y,z) (((x)&(y))^((x)&(z))^((y)&(z)))
#define EP0(x) (ROTR(x,2)^ROTR(x,13)^ROTR(x,22))
#define EP1(x) (ROTR(x,6)^ROTR(x,11)^ROTR(x,25))
#define SIG0(x) (ROTR(x,7)^ROTR(x,18)^((x)>>3))
#define SIG1(x) (ROTR(x,17)^ROTR(x,19)^((x)>>10))

static void sha256_hash(const unsigned char *data, size_t len, char *hex_out)
{
    unsigned int h0=0x6a09e667, h1=0xbb67ae85, h2=0x3c6ef372, h3=0xa54ff53a;
    unsigned int h4=0x510e527f, h5=0x9b05688c, h6=0x1f83d9ab, h7=0x5be0cd19;

    size_t new_len = len + 1;
    while (new_len % 64 != 56) new_len++;
    unsigned char *msg = calloc(new_len + 8, 1);
    if (!msg) { hex_out[0] = '\0'; return; }
    memcpy(msg, data, len);
    msg[len] = 0x80;

    unsigned long long bit_len = (unsigned long long)len * 8;
    for (int i = 0; i < 8; i++)
        msg[new_len + 7 - i] = (unsigned char)(bit_len >> (i * 8));

    for (size_t offset = 0; offset < new_len + 8; offset += 64) {
        unsigned int w[64];
        for (int i = 0; i < 16; i++)
            w[i] = ((unsigned int)msg[offset+i*4]<<24)|((unsigned int)msg[offset+i*4+1]<<16)|
                    ((unsigned int)msg[offset+i*4+2]<<8)|((unsigned int)msg[offset+i*4+3]);
        for (int i = 16; i < 64; i++)
            w[i] = SIG1(w[i-2]) + w[i-7] + SIG0(w[i-15]) + w[i-16];

        unsigned int a=h0,b=h1,c=h2,d=h3,e=h4,f=h5,g=h6,hh=h7;
        for (int i = 0; i < 64; i++) {
            unsigned int t1 = hh + EP1(e) + CH(e,f,g) + K256[i] + w[i];
            unsigned int t2 = EP0(a) + MAJ(a,b,c);
            hh=g; g=f; f=e; e=d+t1; d=c; c=b; b=a; a=t1+t2;
        }
        h0+=a; h1+=b; h2+=c; h3+=d; h4+=e; h5+=f; h6+=g; h7+=hh;
    }
    free(msg);
    snprintf(hex_out, 65, "%08x%08x%08x%08x%08x%08x%08x%08x",
             h0, h1, h2, h3, h4, h5, h6, h7);
}

static int compute_file_sha256(const char *path, char *hex_out)
{
    hex_out[0] = '\0';
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz <= 0 || sz > MAX_FILE_SIZE) { fclose(f); return -1; }
    unsigned char *buf = malloc((size_t)sz);
    if (!buf) { fclose(f); return -1; }
    size_t rd = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    sha256_hash(buf, rd, hex_out);
    free(buf);
    return 0;
}

int db_open(db_t *db, const char *path)
{
    if (!db || !path) return -1;
    db->handle = NULL;
    int rc = sqlite3_open(path, &db->handle);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Cannot open database: %s\n", sqlite3_errmsg(db->handle));
        return -1;
    }
    sqlite3_exec(db->handle, "PRAGMA journal_mode=WAL", NULL, NULL, NULL);
    sqlite3_exec(db->handle, "PRAGMA foreign_keys=ON", NULL, NULL, NULL);
    sqlite3_exec(db->handle, "PRAGMA synchronous=NORMAL", NULL, NULL, NULL);
    return 0;
}

void db_close(db_t *db)
{
    if (db && db->handle) {
        sqlite3_close(db->handle);
        db->handle = NULL;
    }
}

int db_init_schema(db_t *db)
{
    const char *sql =
        "CREATE TABLE IF NOT EXISTS scan_files ("
        "  id INTEGER PRIMARY KEY,"
        "  filename TEXT UNIQUE NOT NULL,"
        "  branch TEXT NOT NULL,"
        "  scan_datetime TEXT NOT NULL,"
        "  file_sha256 TEXT NOT NULL,"
        "  schema_version INTEGER NOT NULL,"
        "  imported_at TEXT DEFAULT (datetime('now'))"
        ");"
        "CREATE TABLE IF NOT EXISTS packages ("
        "  id INTEGER PRIMARY KEY,"
        "  scan_file_id INTEGER NOT NULL REFERENCES scan_files(id),"
        "  spec TEXT,"
        "  source0_original TEXT,"
        "  modified_source0 TEXT,"
        "  url_health TEXT,"
        "  update_available TEXT,"
        "  update_url TEXT,"
        "  health_update_url TEXT,"
        "  name TEXT,"
        "  sha_name TEXT,"
        "  update_download_name TEXT,"
        "  warning TEXT,"
        "  archivation_date TEXT"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_packages_scan ON packages(scan_file_id);"
        "CREATE INDEX IF NOT EXISTS idx_packages_name ON packages(name);"
        "CREATE INDEX IF NOT EXISTS idx_scan_files_branch ON scan_files(branch);";

    char *errmsg = NULL;
    int rc = sqlite3_exec(db->handle, sql, NULL, NULL, &errmsg);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Schema creation failed: %s\n", errmsg);
        sqlite3_free(errmsg);
        return -1;
    }
    return 0;
}

int db_scan_file_exists(db_t *db, const char *filename)
{
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db->handle,
        "SELECT 1 FROM scan_files WHERE filename=?1", -1, &stmt, NULL);
    if (rc != SQLITE_OK) return 0;
    sqlite3_bind_text(stmt, 1, filename, -1, SQLITE_STATIC);
    int exists = (sqlite3_step(stmt) == SQLITE_ROW) ? 1 : 0;
    sqlite3_finalize(stmt);
    return exists;
}

long long db_insert_scan_file(db_t *db, const char *filename, const char *branch,
                              const char *scan_datetime, const char *file_sha256,
                              int schema_version)
{
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db->handle,
        "INSERT INTO scan_files (filename, branch, scan_datetime, file_sha256, schema_version) "
        "VALUES (?1, ?2, ?3, ?4, ?5)", -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;

    sqlite3_bind_text(stmt, 1, filename, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, branch, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, scan_datetime, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 4, file_sha256, -1, SQLITE_STATIC);
    sqlite3_bind_int(stmt, 5, schema_version);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) return -1;
    return sqlite3_last_insert_rowid(db->handle);
}

int db_insert_packages(db_t *db, long long scan_file_id, const csv_data_t *data)
{
    sqlite3_exec(db->handle, "BEGIN TRANSACTION", NULL, NULL, NULL);

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db->handle,
        "INSERT INTO packages (scan_file_id, spec, source0_original, modified_source0, "
        "url_health, update_available, update_url, health_update_url, name, sha_name, "
        "update_download_name, warning, archivation_date) "
        "VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13)", -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        sqlite3_exec(db->handle, "ROLLBACK", NULL, NULL, NULL);
        return -1;
    }

    for (int i = 0; i < data->count; i++) {
        const csv_row_t *r = &data->rows[i];
        sqlite3_reset(stmt);
        sqlite3_clear_bindings(stmt);

        sqlite3_bind_int64(stmt, 1, scan_file_id);
        sqlite3_bind_text(stmt, 2, r->spec ? r->spec : "", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 3, r->source0_original ? r->source0_original : "", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 4, r->modified_source0 ? r->modified_source0 : "", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 5, r->url_health ? r->url_health : "", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 6, r->update_available ? r->update_available : "", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 7, r->update_url ? r->update_url : "", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 8, r->health_update_url ? r->health_update_url : "", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 9, r->name ? r->name : "", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 10, r->sha_name ? r->sha_name : "", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 11, r->update_download_name ? r->update_download_name : "", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 12, r->warning ? r->warning : "", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 13, r->archivation_date ? r->archivation_date : "", -1, SQLITE_STATIC);

        rc = sqlite3_step(stmt);
        if (rc != SQLITE_DONE) {
            sqlite3_finalize(stmt);
            sqlite3_exec(db->handle, "ROLLBACK", NULL, NULL, NULL);
            return -1;
        }
    }

    sqlite3_finalize(stmt);
    sqlite3_exec(db->handle, "COMMIT", NULL, NULL, NULL);
    return 0;
}

/* Extract branch and datetime from filename like photonos-urlhealth-5.0_202603150144.prn */
static int parse_prn_filename(const char *filename, char *branch, size_t bsz,
                              char *dt, size_t dsz)
{
    const char *prefix = "photonos-urlhealth-";
    if (strncmp(filename, prefix, strlen(prefix)) != 0)
        return -1;

    const char *rest = filename + strlen(prefix);
    const char *underscore = strrchr(rest, '_');
    if (!underscore || underscore == rest)
        return -1;

    size_t branch_len = (size_t)(underscore - rest);
    if (branch_len >= bsz)
        return -1;
    memcpy(branch, rest, branch_len);
    branch[branch_len] = '\0';

    const char *dtstart = underscore + 1;
    const char *dot = strrchr(dtstart, '.');
    if (!dot)
        return -1;
    size_t dt_len = (size_t)(dot - dtstart);
    if (dt_len >= dsz || dt_len < 8)
        return -1;
    memcpy(dt, dtstart, dt_len);
    dt[dt_len] = '\0';

    return 0;
}

int db_import_file(db_t *db, const char *filepath)
{
    const char *filename = strrchr(filepath, '/');
    filename = filename ? filename + 1 : filepath;

    if (secure_validate_filename(filename) != 0)
        return -1;

    if (db_scan_file_exists(db, filename))
        return 1;

    char branch[64], dt[32];
    if (parse_prn_filename(filename, branch, sizeof(branch), dt, sizeof(dt)) != 0) {
        fprintf(stderr, "Cannot parse filename: %s\n", filename);
        return -1;
    }

    char sha_hex[65];
    if (compute_file_sha256(filepath, sha_hex) != 0)
        return -1;

    csv_data_t data;
    if (csv_parse_file(filepath, &data) != 0)
        return -1;

    if (data.count == 0) {
        csv_data_free(&data);
        return -1;
    }

    long long scan_id = db_insert_scan_file(db, filename, branch, dt, sha_hex,
                                            data.schema_version);
    if (scan_id < 0) {
        csv_data_free(&data);
        return -1;
    }

    int rc = db_insert_packages(db, scan_id, &data);
    csv_data_free(&data);
    return rc;
}

int db_import_directory(db_t *db, const char *dirpath)
{
    DIR *d = opendir(dirpath);
    if (!d) {
        fprintf(stderr, "Cannot open directory: %s\n", dirpath);
        return -1;
    }

    int imported = 0;
    int skipped = 0;
    int errors = 0;
    int file_count = 0;
    struct dirent *ent;

    while ((ent = readdir(d)) != NULL) {
        if (file_count >= MAX_IMPORT_FILES)
            break;
        if (strncmp(ent->d_name, "photonos-urlhealth-", 19) != 0)
            continue;
        size_t nlen = strlen(ent->d_name);
        if (nlen < 5 || strcmp(ent->d_name + nlen - 4, ".prn") != 0)
            continue;

        file_count++;
        char fullpath[MAX_PATH_LEN];
        snprintf(fullpath, sizeof(fullpath), "%s/%s", dirpath, ent->d_name);

        struct stat st;
        if (stat(fullpath, &st) != 0 || st.st_size == 0)
            continue;

        int rc = db_import_file(db, fullpath);
        if (rc == 0) {
            imported++;
            printf("  Imported: %s (%d rows)\n", ent->d_name, 0);
        } else if (rc == 1) {
            skipped++;
        } else {
            errors++;
            fprintf(stderr, "  Error importing: %s\n", ent->d_name);
        }
    }
    closedir(d);

    printf("Import complete: %d imported, %d skipped (duplicate), %d errors\n",
           imported, skipped, errors);
    return imported;
}

/* Report queries */

int db_query_timeline(db_t *db, timeline_data_t *out)
{
    memset(out, 0, sizeof(*out));
    const char *sql =
        "SELECT sf.branch, sf.scan_datetime, COUNT(*) as cnt "
        "FROM packages p "
        "JOIN scan_files sf ON p.scan_file_id = sf.id "
        "WHERE p.url_health = '200' "
        "  AND p.update_available NOT IN ('', '(same version)', 'pinned') "
        "  AND p.update_available IS NOT NULL "
        "  AND LENGTH(p.update_available) > 0 "
        "  AND (sf.schema_version = 5 OR ("
        "    p.update_download_name IS NOT NULL "
        "    AND LENGTH(p.update_download_name) > 0 "
        "    AND p.update_download_name LIKE '%-%.tar%')) "
        "GROUP BY sf.branch, sf.scan_datetime "
        "ORDER BY sf.scan_datetime, sf.branch";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;

    int cap = 256;
    out->points = malloc((size_t)cap * sizeof(timeline_point_t));
    if (!out->points) { sqlite3_finalize(stmt); return -1; }

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        if (out->count >= cap) {
            cap *= 2;
            timeline_point_t *np = realloc(out->points, (size_t)cap * sizeof(timeline_point_t));
            if (!np) break;
            out->points = np;
        }
        timeline_point_t *pt = &out->points[out->count];
        secure_strncpy(pt->branch, (const char *)sqlite3_column_text(stmt, 0), sizeof(pt->branch));
        secure_strncpy(pt->scan_datetime, (const char *)sqlite3_column_text(stmt, 1), sizeof(pt->scan_datetime));
        pt->qualifying_count = sqlite3_column_int(stmt, 2);
        out->count++;
    }
    sqlite3_finalize(stmt);
    return 0;
}

void timeline_data_free(timeline_data_t *data)
{
    free(data->points);
    data->points = NULL;
    data->count = 0;
}

int db_query_top_changed(db_t *db, top_changed_data_t *out, int limit)
{
    memset(out, 0, sizeof(*out));

    const char *sql =
        "WITH ordered AS ("
        "  SELECT p.name, p.update_available, sf.branch, sf.scan_datetime,"
        "    LAG(p.update_available) OVER (PARTITION BY p.name, sf.branch ORDER BY sf.scan_datetime) AS prev_ua"
        "  FROM packages p"
        "  JOIN scan_files sf ON p.scan_file_id = sf.id"
        "  WHERE sf.scan_datetime >= '2023'"
        "    AND p.name IS NOT NULL AND LENGTH(p.name) > 0"
        "),"
        "changes AS ("
        "  SELECT name, branch, scan_datetime,"
        "    CASE WHEN update_available != prev_ua AND prev_ua IS NOT NULL THEN 1 ELSE 0 END AS changed"
        "  FROM ordered"
        ")"
        "SELECT name,"
        "  SUM(CASE WHEN scan_datetime LIKE '2023%' THEN changed ELSE 0 END) as c23,"
        "  SUM(CASE WHEN scan_datetime LIKE '2024%' THEN changed ELSE 0 END) as c24,"
        "  SUM(CASE WHEN scan_datetime LIKE '2025%' THEN changed ELSE 0 END) as c25,"
        "  SUM(CASE WHEN scan_datetime LIKE '2026%' THEN changed ELSE 0 END) as c26,"
        "  SUM(changed) as total,"
        "  GROUP_CONCAT(DISTINCT branch) as branches "
        "FROM changes "
        "GROUP BY name "
        "HAVING total > 0 "
        "ORDER BY total DESC "
        "LIMIT ?1";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Top-changed query error: %s\n", sqlite3_errmsg(db->handle));
        return -1;
    }
    sqlite3_bind_int(stmt, 1, limit > 0 ? limit : 10);

    out->items = malloc(sizeof(top_changed_t) * (size_t)(limit > 0 ? limit : 10));
    if (!out->items) { sqlite3_finalize(stmt); return -1; }

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        top_changed_t *it = &out->items[out->count];
        const char *n = (const char *)sqlite3_column_text(stmt, 0);
        const char *b = (const char *)sqlite3_column_text(stmt, 6);
        secure_strncpy(it->name, n ? n : "", sizeof(it->name));
        it->changes_2023 = sqlite3_column_int(stmt, 1);
        it->changes_2024 = sqlite3_column_int(stmt, 2);
        it->changes_2025 = sqlite3_column_int(stmt, 3);
        it->changes_2026 = sqlite3_column_int(stmt, 4);
        it->total = sqlite3_column_int(stmt, 5);
        secure_strncpy(it->branches, b ? b : "", sizeof(it->branches));
        out->count++;
    }
    sqlite3_finalize(stmt);
    return 0;
}

void top_changed_data_free(top_changed_data_t *data)
{
    free(data->items);
    data->items = NULL;
    data->count = 0;
}

int db_query_least_changed(db_t *db, least_changed_data_t *out)
{
    memset(out, 0, sizeof(*out));

    const char *sql =
        "WITH valid_pkgs AS ("
        "  SELECT p.name, p.update_available, sf.branch, sf.scan_datetime"
        "  FROM packages p"
        "  JOIN scan_files sf ON p.scan_file_id = sf.id"
        "  WHERE sf.scan_datetime >= '2023'"
        "    AND p.name IS NOT NULL AND LENGTH(p.name) > 0"
        "    AND p.update_available IS NOT NULL AND LENGTH(p.update_available) > 0"
        "    AND p.update_available NOT IN ('(same version)', 'pinned')"
        "    AND (p.warning IS NULL OR p.warning NOT LIKE '%VMware internal%')"
        "    AND (p.source0_original IS NULL OR (p.source0_original NOT LIKE '%vmware.com%'"
        "         AND p.source0_original NOT LIKE '%broadcom.com%'"
        "         AND p.source0_original NOT LIKE '%packages.vmware.com%'"
        "         AND p.source0_original NOT LIKE '%packages.broadcom.com%'))"
        "    AND (p.archivation_date IS NULL OR LENGTH(p.archivation_date) = 0)"
        ")"
        "SELECT name, GROUP_CONCAT(DISTINCT branch) as branches, 0 "
        "FROM valid_pkgs "
        "GROUP BY name "
        "HAVING COUNT(DISTINCT update_available) = 1 "
        "ORDER BY name ASC "
        "LIMIT 200";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Least-changed query error: %s\n", sqlite3_errmsg(db->handle));
        return -1;
    }

    int cap = 64;
    out->items = malloc(sizeof(least_changed_t) * (size_t)cap);
    if (!out->items) { sqlite3_finalize(stmt); return -1; }

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        if (out->count >= cap) break;
        least_changed_t *it = &out->items[out->count];
        const char *n = (const char *)sqlite3_column_text(stmt, 0);
        const char *b = (const char *)sqlite3_column_text(stmt, 1);
        secure_strncpy(it->name, n ? n : "", sizeof(it->name));
        secure_strncpy(it->branches, b ? b : "", sizeof(it->branches));
        it->total_changes = sqlite3_column_int(stmt, 2);
        out->count++;
    }
    sqlite3_finalize(stmt);
    return 0;
}

void least_changed_data_free(least_changed_data_t *data)
{
    free(data->items);
    data->items = NULL;
    data->count = 0;
}

int db_query_categories(db_t *db, category_data_t *out)
{
    memset(out, 0, sizeof(*out));

    /* Get the latest scan per branch, then categorize packages by URL domain */
    const char *sql =
        "WITH latest_scans AS ("
        "  SELECT branch, MAX(scan_datetime) as max_dt FROM scan_files GROUP BY branch"
        "),"
        "latest_pkgs AS ("
        "  SELECT DISTINCT p.name, COALESCE(NULLIF(p.source0_original,''), p.modified_source0) as url"
        "  FROM packages p"
        "  JOIN scan_files sf ON p.scan_file_id = sf.id"
        "  JOIN latest_scans ls ON sf.branch = ls.branch AND sf.scan_datetime = ls.max_dt"
        "  WHERE p.name IS NOT NULL AND LENGTH(p.name) > 0"
        "),"
        "raw_cats AS ("
        "  SELECT "
        "    CASE "
        "      WHEN url NOT LIKE '%://%' THEN '(scan issues)'"
        "      WHEN url LIKE '%github.com%' THEN 'github.com'"
        "      WHEN url LIKE '%pythonhosted.org%' OR url LIKE '%pypi.python.org%'"
        "           OR url LIKE '%pypi.io%' OR url LIKE '%pypi.org%' THEN 'pypi'"
        "      WHEN url LIKE '%kernel.org%' THEN 'kernel.org'"
        "      WHEN url LIKE '%freedesktop.org%' THEN 'freedesktop.org'"
        "      WHEN url LIKE '%gnu.org%' THEN 'gnu.org'"
        "      WHEN url LIKE '%rubygems.org%' THEN 'rubygems.org'"
        "      WHEN url LIKE '%sourceforge.net%' THEN 'sourceforge.net'"
        "      WHEN url LIKE '%cpan.org%' THEN 'cpan.org'"
        "      WHEN url LIKE '%gnome.org%' THEN 'gnome.org'"
        "      WHEN url LIKE '%x.org%' OR url LIKE '%xorg%' THEN 'x.org'"
        "      WHEN url LIKE '%apache.org%' THEN 'apache.org'"
        "      WHEN url LIKE '%gnupg.org%' OR url LIKE '%gnupg%' THEN 'gnupg.org'"
        "      WHEN url LIKE '%netfilter.org%' THEN 'netfilter.org'"
        "      WHEN url LIKE '%pagure.org%' THEN 'pagure.org'"
        "      WHEN url LIKE '%mozilla.org%' THEN 'mozilla.org'"
        "      WHEN url LIKE '%gitlab.com%' THEN 'gitlab.com'"
        "      ELSE 'Other'"
        "    END as category,"
        "    COUNT(*) as cnt "
        "  FROM latest_pkgs "
        "  WHERE url IS NOT NULL AND LENGTH(url) > 0 "
        "  GROUP BY category"
        "),"
        "total AS (SELECT SUM(cnt) as n FROM raw_cats) "
        "SELECT "
        "  CASE WHEN cnt * 100.0 / total.n >= 3.0 THEN category ELSE 'Other' END as cat,"
        "  SUM(cnt) as cnt "
        "FROM raw_cats, total "
        "GROUP BY cat "
        "ORDER BY cnt DESC";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Category query error: %s\n", sqlite3_errmsg(db->handle));
        return -1;
    }

    int cap = 32;
    out->items = malloc(sizeof(category_t) * (size_t)cap);
    if (!out->items) { sqlite3_finalize(stmt); return -1; }
    out->total = 0;

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        if (out->count >= cap) break;
        category_t *it = &out->items[out->count];
        secure_strncpy(it->category, (const char *)sqlite3_column_text(stmt, 0), sizeof(it->category));
        it->count = sqlite3_column_int(stmt, 1);
        out->total += it->count;
        out->count++;
    }
    sqlite3_finalize(stmt);

    for (int i = 0; i < out->count; i++) {
        out->items[i].percentage = out->total > 0 ?
            (double)out->items[i].count / (double)out->total * 100.0 : 0.0;
    }
    return 0;
}

int db_query_categories_branch(db_t *db, category_data_t *out, const char *branch)
{
    memset(out, 0, sizeof(*out));

    const char *sql =
        "WITH latest_scan AS ("
        "  SELECT MAX(scan_datetime) as max_dt FROM scan_files WHERE branch = ?1"
        "),"
        "latest_pkgs AS ("
        "  SELECT DISTINCT p.name, COALESCE(NULLIF(p.source0_original,''), p.modified_source0) as url"
        "  FROM packages p"
        "  JOIN scan_files sf ON p.scan_file_id = sf.id"
        "  JOIN latest_scan ls ON sf.scan_datetime = ls.max_dt"
        "  WHERE sf.branch = ?1 AND p.name IS NOT NULL AND LENGTH(p.name) > 0"
        "),"
        "raw_cats AS ("
        "  SELECT "
        "    CASE "
        "      WHEN url NOT LIKE '%://%' THEN '(scan issues)'"
        "      WHEN url LIKE '%github.com%' THEN 'github.com'"
        "      WHEN url LIKE '%pythonhosted.org%' OR url LIKE '%pypi.python.org%'"
        "           OR url LIKE '%pypi.io%' OR url LIKE '%pypi.org%' THEN 'pypi'"
        "      WHEN url LIKE '%kernel.org%' THEN 'kernel.org'"
        "      WHEN url LIKE '%freedesktop.org%' THEN 'freedesktop.org'"
        "      WHEN url LIKE '%gnu.org%' THEN 'gnu.org'"
        "      WHEN url LIKE '%rubygems.org%' THEN 'rubygems.org'"
        "      WHEN url LIKE '%sourceforge.net%' THEN 'sourceforge.net'"
        "      WHEN url LIKE '%cpan.org%' THEN 'cpan.org'"
        "      WHEN url LIKE '%gnome.org%' THEN 'gnome.org'"
        "      WHEN url LIKE '%x.org%' OR url LIKE '%xorg%' THEN 'x.org'"
        "      WHEN url LIKE '%apache.org%' THEN 'apache.org'"
        "      WHEN url LIKE '%gnupg.org%' OR url LIKE '%gnupg%' THEN 'gnupg.org'"
        "      WHEN url LIKE '%netfilter.org%' THEN 'netfilter.org'"
        "      WHEN url LIKE '%pagure.org%' THEN 'pagure.org'"
        "      WHEN url LIKE '%mozilla.org%' THEN 'mozilla.org'"
        "      WHEN url LIKE '%gitlab.com%' THEN 'gitlab.com'"
        "      ELSE 'Other'"
        "    END as category,"
        "    COUNT(*) as cnt "
        "  FROM latest_pkgs "
        "  WHERE url IS NOT NULL AND LENGTH(url) > 0 "
        "  GROUP BY category"
        "),"
        "total AS (SELECT SUM(cnt) as n FROM raw_cats) "
        "SELECT "
        "  CASE WHEN cnt * 100.0 / total.n >= 3.0 THEN category ELSE 'Other' END as cat,"
        "  SUM(cnt) as cnt "
        "FROM raw_cats, total "
        "GROUP BY cat "
        "ORDER BY cnt DESC";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;
    sqlite3_bind_text(stmt, 1, branch, -1, SQLITE_STATIC);

    int cap = 32;
    out->items = malloc(sizeof(category_t) * (size_t)cap);
    if (!out->items) { sqlite3_finalize(stmt); return -1; }
    out->total = 0;

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        if (out->count >= cap) break;
        category_t *it = &out->items[out->count];
        secure_strncpy(it->category, (const char *)sqlite3_column_text(stmt, 0), sizeof(it->category));
        it->count = sqlite3_column_int(stmt, 1);
        out->total += it->count;
        out->count++;
    }
    sqlite3_finalize(stmt);

    for (int i = 0; i < out->count; i++) {
        out->items[i].percentage = out->total > 0 ?
            (double)out->items[i].count / (double)out->total * 100.0 : 0.0;
    }
    return 0;
}

void category_data_free(category_data_t *data)
{
    free(data->items);
    data->items = NULL;
    data->count = 0;
}

static int find_or_add_str(char arr[][64], int *count, int max, const char *val, size_t sz)
{
    for (int i = 0; i < *count; i++)
        if (strcmp(arr[i], val) == 0) return i;
    if (*count >= max) return -1;
    secure_strncpy(arr[*count], val, sz);
    (*count)++;
    return *count - 1;
}

static int find_or_add_br(char arr[][16], int *count, int max, const char *val)
{
    for (int i = 0; i < *count; i++)
        if (strcmp(arr[i], val) == 0) return i;
    if (*count >= max) return -1;
    secure_strncpy(arr[*count], val, 16);
    (*count)++;
    return *count - 1;
}

int db_query_category_drift(db_t *db, category_drift_data_t *out)
{
    memset(out, 0, sizeof(*out));

    const char *sql =
        "WITH categorized AS ("
        "  SELECT sf.branch, sf.scan_datetime, p.name,"
        "    COALESCE(NULLIF(p.source0_original,''), p.modified_source0) as url"
        "  FROM packages p"
        "  JOIN scan_files sf ON p.scan_file_id = sf.id"
        "  WHERE p.name IS NOT NULL AND LENGTH(p.name) > 0"
        "),"
        "raw_cats AS ("
        "  SELECT branch, scan_datetime,"
        "    CASE"
        "      WHEN url IS NULL OR LENGTH(url) = 0 OR url NOT LIKE '%://%' THEN '(scan issues)'"
        "      WHEN url LIKE '%github.com%' THEN 'github.com'"
        "      WHEN url LIKE '%pythonhosted.org%' OR url LIKE '%pypi.python.org%'"
        "           OR url LIKE '%pypi.io%' OR url LIKE '%pypi.org%' THEN 'pypi'"
        "      WHEN url LIKE '%kernel.org%' THEN 'kernel.org'"
        "      WHEN url LIKE '%freedesktop.org%' THEN 'freedesktop.org'"
        "      WHEN url LIKE '%gnu.org%' THEN 'gnu.org'"
        "      WHEN url LIKE '%rubygems.org%' THEN 'rubygems.org'"
        "      WHEN url LIKE '%sourceforge.net%' THEN 'sourceforge.net'"
        "      WHEN url LIKE '%cpan.org%' THEN 'cpan.org'"
        "      WHEN url LIKE '%gnome.org%' THEN 'gnome.org'"
        "      WHEN url LIKE '%x.org%' OR url LIKE '%xorg%' THEN 'x.org'"
        "      WHEN url LIKE '%apache.org%' THEN 'apache.org'"
        "      WHEN url LIKE '%gnupg.org%' OR url LIKE '%gnupg%' THEN 'gnupg.org'"
        "      WHEN url LIKE '%netfilter.org%' THEN 'netfilter.org'"
        "      WHEN url LIKE '%pagure.org%' THEN 'pagure.org'"
        "      WHEN url LIKE '%mozilla.org%' THEN 'mozilla.org'"
        "      WHEN url LIKE '%gitlab.com%' THEN 'gitlab.com'"
        "      ELSE 'Other'"
        "    END as category,"
        "    COUNT(*) as cnt"
        "  FROM categorized"
        "  GROUP BY branch, scan_datetime, category"
        "),"
        "scan_totals AS ("
        "  SELECT branch, scan_datetime, SUM(cnt) as total"
        "  FROM raw_cats GROUP BY branch, scan_datetime"
        "),"
        "with_pct AS ("
        "  SELECT r.branch, r.scan_datetime, r.category,"
        "    ROUND(r.cnt * 100.0 / st.total, 1) as pct"
        "  FROM raw_cats r"
        "  JOIN scan_totals st ON r.branch = st.branch AND r.scan_datetime = st.scan_datetime"
        "),"
        "global_totals AS ("
        "  SELECT category, SUM(cnt) as gcnt FROM raw_cats GROUP BY category"
        "),"
        "total_all AS (SELECT SUM(gcnt) as n FROM global_totals) "
        "SELECT w.branch, w.scan_datetime, "
        "  CASE WHEN g.gcnt * 100.0 / t.n >= 3.0 THEN w.category ELSE 'Other' END as cat,"
        "  SUM(w.pct) as pct "
        "FROM with_pct w "
        "JOIN global_totals g ON g.category = w.category "
        "CROSS JOIN total_all t "
        "GROUP BY w.branch, w.scan_datetime, cat "
        "ORDER BY w.branch, w.scan_datetime, cat";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Category drift query error: %s\n", sqlite3_errmsg(db->handle));
        return -1;
    }

    int cap = 8192;
    out->points = malloc(sizeof(category_drift_point_t) * (size_t)cap);
    if (!out->points) { sqlite3_finalize(stmt); return -1; }

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        if (out->count >= cap) break;
        category_drift_point_t *pt = &out->points[out->count];
        const char *br = (const char *)sqlite3_column_text(stmt, 0);
        const char *dt = (const char *)sqlite3_column_text(stmt, 1);
        const char *cat = (const char *)sqlite3_column_text(stmt, 2);
        secure_strncpy(pt->branch, br ? br : "", sizeof(pt->branch));
        secure_strncpy(pt->scan_datetime, dt ? dt : "", sizeof(pt->scan_datetime));
        secure_strncpy(pt->category, cat ? cat : "", sizeof(pt->category));
        pt->percentage = sqlite3_column_double(stmt, 3);
        find_or_add_str(out->categories, &out->ncategories, 32, pt->category, 64);
        find_or_add_br(out->branches, &out->nbranches, 16, pt->branch);
        out->count++;
    }
    sqlite3_finalize(stmt);
    return 0;
}

void category_drift_data_free(category_drift_data_t *data)
{
    free(data->points);
    data->points = NULL;
    data->count = 0;
}
