#include "docx_writer.h"
#include "chart_xml.h"
#include "security.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <zlib.h>

/* Minimal ZIP writer — creates ZIP files using zlib deflate */
typedef struct {
    FILE *fp;
    /* Central directory entries */
    struct zip_entry {
        char *name;
        unsigned int crc32;
        unsigned int comp_size;
        unsigned int uncomp_size;
        unsigned int local_offset;
    } entries[48];
    int nentries;
} zipwriter_t;

static int zip_open(zipwriter_t *z, const char *path)
{
    memset(z, 0, sizeof(*z));
    z->fp = fopen(path, "wb");
    return z->fp ? 0 : -1;
}

static void zip_write16(FILE *f, unsigned short v)
{
    fputc(v & 0xFF, f);
    fputc((v >> 8) & 0xFF, f);
}

static void zip_write32(FILE *f, unsigned int v)
{
    fputc(v & 0xFF, f);
    fputc((v >> 8) & 0xFF, f);
    fputc((v >> 16) & 0xFF, f);
    fputc((v >> 24) & 0xFF, f);
}

static int zip_add_file(zipwriter_t *z, const char *name, const void *data, size_t len)
{
    if (!z->fp || z->nentries >= 48)
        return -1;

    unsigned int crc = crc32(0L, Z_NULL, 0);
    crc = crc32(crc, (const Bytef *)data, (uInt)len);

    /* Deflate the data */
    uLongf comp_bound = compressBound((uLong)len);
    Bytef *comp = malloc(comp_bound);
    if (!comp)
        return -1;

    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    /* Use raw deflate (windowBits = -15) for ZIP compatibility */
    if (deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        free(comp);
        return -1;
    }
    strm.next_in = (Bytef *)data;
    strm.avail_in = (uInt)len;
    strm.next_out = comp;
    strm.avail_out = (uInt)comp_bound;
    deflate(&strm, Z_FINISH);
    unsigned int comp_size = (unsigned int)strm.total_out;
    deflateEnd(&strm);

    unsigned int local_offset = (unsigned int)ftell(z->fp);
    size_t name_len = strlen(name);

    /* Local file header */
    zip_write32(z->fp, 0x04034b50);  /* signature */
    zip_write16(z->fp, 20);           /* version needed */
    zip_write16(z->fp, 0);            /* flags */
    zip_write16(z->fp, 8);            /* compression: deflate */
    zip_write16(z->fp, 0);            /* mod time */
    zip_write16(z->fp, 0);            /* mod date */
    zip_write32(z->fp, crc);
    zip_write32(z->fp, comp_size);
    zip_write32(z->fp, (unsigned int)len);
    zip_write16(z->fp, (unsigned short)name_len);
    zip_write16(z->fp, 0);            /* extra field len */
    fwrite(name, 1, name_len, z->fp);
    fwrite(comp, 1, comp_size, z->fp);

    free(comp);

    /* Save entry for central directory */
    struct zip_entry *e = &z->entries[z->nentries];
    e->name = strdup(name);
    e->crc32 = crc;
    e->comp_size = comp_size;
    e->uncomp_size = (unsigned int)len;
    e->local_offset = local_offset;
    z->nentries++;

    return 0;
}

static int zip_close(zipwriter_t *z)
{
    if (!z->fp)
        return -1;

    unsigned int cd_offset = (unsigned int)ftell(z->fp);

    /* Write central directory */
    for (int i = 0; i < z->nentries; i++) {
        struct zip_entry *e = &z->entries[i];
        size_t name_len = strlen(e->name);

        zip_write32(z->fp, 0x02014b50);  /* central dir signature */
        zip_write16(z->fp, 20);           /* version made by */
        zip_write16(z->fp, 20);           /* version needed */
        zip_write16(z->fp, 0);            /* flags */
        zip_write16(z->fp, 8);            /* compression */
        zip_write16(z->fp, 0);            /* mod time */
        zip_write16(z->fp, 0);            /* mod date */
        zip_write32(z->fp, e->crc32);
        zip_write32(z->fp, e->comp_size);
        zip_write32(z->fp, e->uncomp_size);
        zip_write16(z->fp, (unsigned short)name_len);
        zip_write16(z->fp, 0);            /* extra field len */
        zip_write16(z->fp, 0);            /* comment len */
        zip_write16(z->fp, 0);            /* disk number */
        zip_write16(z->fp, 0);            /* internal attr */
        zip_write32(z->fp, 0);            /* external attr */
        zip_write32(z->fp, e->local_offset);
        fwrite(e->name, 1, name_len, z->fp);
    }

    unsigned int cd_size = (unsigned int)ftell(z->fp) - cd_offset;

    /* End of central directory */
    zip_write32(z->fp, 0x06054b50);
    zip_write16(z->fp, 0);            /* disk number */
    zip_write16(z->fp, 0);            /* disk with CD */
    zip_write16(z->fp, (unsigned short)z->nentries);
    zip_write16(z->fp, (unsigned short)z->nentries);
    zip_write32(z->fp, cd_size);
    zip_write32(z->fp, cd_offset);
    zip_write16(z->fp, 0);            /* comment len */

    fclose(z->fp);
    z->fp = NULL;

    for (int i = 0; i < z->nentries; i++)
        free(z->entries[i].name);

    return 0;
}

/* Generate OOXML content type XML */
static char *gen_content_types(void)
{
    return strdup(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n"
        "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>"
        "<Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/>"
        "<Override PartName=\"/word/settings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml\"/>"
        "<Override PartName=\"/word/webSettings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.webSettings+xml\"/>"
        "<Override PartName=\"/word/fontTable.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml\"/>"
        "<Override PartName=\"/word/charts/chart1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/>"
        "<Override PartName=\"/word/charts/chart2.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/>"
        "<Override PartName=\"/word/charts/chart3.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/>"
        "</Types>");
}

static char *gen_rels(void)
{
    return strdup(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n"
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>"
        "</Relationships>");
}

static char *gen_doc_rels(void)
{
    return strdup(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n"
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart\" Target=\"charts/chart1.xml\"/>"
        "<Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart\" Target=\"charts/chart2.xml\"/>"
        "<Relationship Id=\"rId4\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart\" Target=\"charts/chart3.xml\"/>"
        "<Relationship Id=\"rId5\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings\" Target=\"settings.xml\"/>"
        "<Relationship Id=\"rId6\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/webSettings\" Target=\"webSettings.xml\"/>"
        "<Relationship Id=\"rId7\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/fontTable\" Target=\"fontTable.xml\"/>"
        "</Relationships>");
}

static char *gen_styles(void)
{
    return strdup(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n"
        "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
        "<w:style w:type=\"paragraph\" w:styleId=\"Heading1\">"
        "<w:name w:val=\"heading 1\"/><w:pPr><w:spacing w:before=\"240\" w:after=\"120\"/></w:pPr>"
        "<w:rPr><w:b/><w:sz w:val=\"32\"/></w:rPr></w:style>"
        "<w:style w:type=\"paragraph\" w:styleId=\"Heading2\">"
        "<w:name w:val=\"heading 2\"/><w:pPr><w:spacing w:before=\"200\" w:after=\"80\"/></w:pPr>"
        "<w:rPr><w:b/><w:sz w:val=\"26\"/></w:rPr></w:style>"
        "<w:style w:type=\"table\" w:styleId=\"TableGrid\">"
        "<w:name w:val=\"Table Grid\"/><w:tblPr><w:tblBorders>"
        "<w:top w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"000000\"/>"
        "<w:left w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"000000\"/>"
        "<w:bottom w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"000000\"/>"
        "<w:right w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"000000\"/>"
        "<w:insideH w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"000000\"/>"
        "<w:insideV w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"000000\"/>"
        "</w:tblBorders></w:tblPr></w:style>"
        "</w:styles>");
}

static char *gen_settings(void)
{
    return strdup(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n"
        "<w:settings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" "
        "xmlns:o=\"urn:schemas-microsoft-com:office:office\" "
        "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" "
        "xmlns:m=\"http://schemas.openxmlformats.org/officeDocument/2006/math\" "
        "xmlns:v=\"urn:schemas-microsoft-com:vml\">"
        "<w:zoom w:percent=\"100\"/>"
        "<w:defaultTabStop w:val=\"720\"/>"
        "<w:characterSpacingControl w:val=\"doNotCompress\"/>"
        "<w:compat><w:compatSetting w:name=\"compatibilityMode\" "
        "w:uri=\"http://schemas.microsoft.com/office/word\" w:val=\"15\"/></w:compat>"
        "</w:settings>");
}

static char *gen_web_settings(void)
{
    return strdup(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n"
        "<w:webSettings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" "
        "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
        "<w:optimizeForBrowser/>"
        "<w:allowPNG/>"
        "</w:webSettings>");
}

static char *gen_font_table(void)
{
    return strdup(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n"
        "<w:fonts xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" "
        "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
        "<w:font w:name=\"Calibri\"><w:panose1 w:val=\"020F0502020204030204\"/>"
        "<w:charset w:val=\"00\"/><w:family w:val=\"swiss\"/>"
        "<w:pitch w:val=\"variable\"/></w:font>"
        "<w:font w:name=\"Times New Roman\"><w:panose1 w:val=\"02020603050405020304\"/>"
        "<w:charset w:val=\"00\"/><w:family w:val=\"roman\"/>"
        "<w:pitch w:val=\"variable\"/></w:font>"
        "</w:fonts>");
}

/* Helper: add a heading paragraph */
static void doc_add_heading(strbuf_t *sb, const char *text, const char *style)
{
    char *esc = secure_xml_escape(text);
    strbuf_printf(sb,
        "<w:p><w:pPr><w:pStyle w:val=\"%s\"/></w:pPr>"
        "<w:r><w:t>%s</w:t></w:r></w:p>\r\n",
        style, esc ? esc : text);
    free(esc);
}

/* Helper: add a plain paragraph */
static void doc_add_para(strbuf_t *sb, const char *text)
{
    char *esc = secure_xml_escape(text);
    strbuf_printf(sb, "<w:p><w:r><w:t xml:space=\"preserve\">%s</w:t></w:r></w:p>\r\n",
                 esc ? esc : text);
    free(esc);
}

/* Helper: add a table cell */
static void doc_add_cell(strbuf_t *sb, const char *text)
{
    char *esc = secure_xml_escape(text);
    strbuf_printf(sb,
        "<w:tc><w:p><w:r><w:t>%s</w:t></w:r></w:p></w:tc>",
        esc ? esc : text);
    free(esc);
}

/* Helper: inline chart reference (docPr id must be unique per document) */
static int s_next_docpr_id = 1;

static void doc_add_chart_ref(strbuf_t *sb, const char *rid)
{
    int dpid = s_next_docpr_id++;
    strbuf_printf(sb,
        "<w:p><w:r>"
        "<w:drawing>"
        "<wp:inline xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" "
        "distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\">"
        "<wp:extent cx=\"5486400\" cy=\"3200400\"/>"
        "<wp:docPr id=\"%d\" name=\"Chart %d\"/>"
        "<a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\">"
        "<a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/chart\">"
        "<c:chart xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" "
        "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" "
        "r:id=\"%s\"/>"
        "</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>\r\n",
        dpid, dpid, rid);
}

static char *gen_document(const top_changed_data_t *top_changed,
                          const least_changed_data_t *least_changed)
{
    s_next_docpr_id = 1;
    strbuf_t sb;
    strbuf_init(&sb);

    strbuf_append(&sb,
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n"
        "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" "
        "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">\r\n"
        "<w:body>\r\n");

    /* Title */
    doc_add_heading(&sb, "Photon OS Package Report", "Heading1");

    {
        char datebuf[64];
        time_t now = time(NULL);
        struct tm *tm = gmtime(&now);
        snprintf(datebuf, sizeof(datebuf), "Generated: %04d-%02d-%02d",
                tm->tm_year + 1900, tm->tm_mon + 1, tm->tm_mday);
        doc_add_para(&sb, datebuf);
    }

    /* Section 1: Timeline Chart */
    doc_add_heading(&sb, "1. Package Health Timeline", "Heading2");
    doc_add_para(&sb, "Packages matching UrlHealth=200, UpdateAvailable with version, "
                      "and correct UpdateDownloadName (name-version.tar.*), per branch over time.");
    doc_add_chart_ref(&sb, "rId2");

    /* Section 2: Top 10 Most-Changed Packages (all branches) */
    doc_add_heading(&sb, "2. Top 10 Most-Changed Packages (all branches, 2023-current)", "Heading2");
    if (top_changed && top_changed->count > 0) {
        strbuf_append(&sb,
            "<w:tbl><w:tblPr><w:tblStyle w:val=\"TableGrid\"/>"
            "<w:tblW w:w=\"0\" w:type=\"auto\"/></w:tblPr>"
            "<w:tblGrid><w:gridCol w:w=\"2400\"/><w:gridCol w:w=\"900\"/>"
            "<w:gridCol w:w=\"900\"/><w:gridCol w:w=\"900\"/>"
            "<w:gridCol w:w=\"900\"/><w:gridCol w:w=\"900\"/>"
            "<w:gridCol w:w=\"3100\"/></w:tblGrid>\r\n");
        /* Header row */
        strbuf_append(&sb, "<w:tr>");
        doc_add_cell(&sb, "Package");
        doc_add_cell(&sb, "2023");
        doc_add_cell(&sb, "2024");
        doc_add_cell(&sb, "2025");
        doc_add_cell(&sb, "2026");
        doc_add_cell(&sb, "Total");
        doc_add_cell(&sb, "Branches");
        strbuf_append(&sb, "</w:tr>\r\n");

        for (int i = 0; i < top_changed->count; i++) {
            const top_changed_t *it = &top_changed->items[i];
            char buf[32];
            strbuf_append(&sb, "<w:tr>");
            doc_add_cell(&sb, it->name);
            snprintf(buf, sizeof(buf), "%d", it->changes_2023);
            doc_add_cell(&sb, buf);
            snprintf(buf, sizeof(buf), "%d", it->changes_2024);
            doc_add_cell(&sb, buf);
            snprintf(buf, sizeof(buf), "%d", it->changes_2025);
            doc_add_cell(&sb, buf);
            snprintf(buf, sizeof(buf), "%d", it->changes_2026);
            doc_add_cell(&sb, buf);
            snprintf(buf, sizeof(buf), "%d", it->total);
            doc_add_cell(&sb, buf);
            doc_add_cell(&sb, it->branches);
            strbuf_append(&sb, "</w:tr>\r\n");
        }
        strbuf_append(&sb, "</w:tbl>\r\n");
    } else {
        doc_add_para(&sb, "No change data available.");
    }

    /* Section 3: Least-Changed Packages */
    doc_add_heading(&sb, "3. Least-Changed Packages (all branches, 2023-current)", "Heading2");
    doc_add_para(&sb, "Excludes VMware-internal and archived packages.");
    if (least_changed && least_changed->count > 0) {
        strbuf_append(&sb,
            "<w:tbl><w:tblPr><w:tblStyle w:val=\"TableGrid\"/>"
            "<w:tblW w:w=\"0\" w:type=\"auto\"/></w:tblPr>"
            "<w:tblGrid><w:gridCol w:w=\"3000\"/><w:gridCol w:w=\"4500\"/>"
            "<w:gridCol w:w=\"1500\"/></w:tblGrid>\r\n");
        strbuf_append(&sb, "<w:tr>");
        doc_add_cell(&sb, "Package");
        doc_add_cell(&sb, "Branches");
        doc_add_cell(&sb, "Total Changes");
        strbuf_append(&sb, "</w:tr>\r\n");

        for (int i = 0; i < least_changed->count; i++) {
            const least_changed_t *it = &least_changed->items[i];
            char buf[32];
            strbuf_append(&sb, "<w:tr>");
            doc_add_cell(&sb, it->name);
            doc_add_cell(&sb, it->branches);
            snprintf(buf, sizeof(buf), "%d", it->total_changes);
            doc_add_cell(&sb, buf);
            strbuf_append(&sb, "</w:tr>\r\n");
        }
        strbuf_append(&sb, "</w:tbl>\r\n");
    } else {
        doc_add_para(&sb, "No change data available.");
    }

    /* Section 4: Source Category Drift */
    doc_add_heading(&sb, "4. Source Category Drift", "Heading2");
    doc_add_para(&sb, "Distribution of packages by source URL domain (latest scan per branch). "
                      "Categories below 3% are merged into Other.");
    doc_add_chart_ref(&sb, "rId3");
    doc_add_para(&sb, "3D chart showing category percentage drift over time per branch.");
    doc_add_chart_ref(&sb, "rId4");

    strbuf_append(&sb, "</w:body></w:document>\r\n");

    char *result = sb.data;
    sb.data = NULL;
    strbuf_free(&sb);
    return result;
}

int docx_write_report(const char *output_path,
                      const timeline_data_t *timeline,
                      const top_changed_data_t *top_changed,
                      const least_changed_data_t *least_changed,
                      const category_data_t *categories,
                      const category_drift_data_t *drift)
{
    if (!output_path)
        return -1;

    zipwriter_t z;
    if (zip_open(&z, output_path) != 0) {
        fprintf(stderr, "Cannot create output file: %s\n", output_path);
        return -1;
    }

    /* Generate all XML content */
    char *content_types = gen_content_types();
    char *rels = gen_rels();
    char *doc_rels = gen_doc_rels();
    char *styles = gen_styles();
    char *settings = gen_settings();
    char *web_settings = gen_web_settings();
    char *font_table = gen_font_table();
    char *document = gen_document(top_changed, least_changed);
    char *chart1 = chart_xml_timeline(timeline);
    char *chart2 = chart_xml_pie(categories);
    char *chart3 = chart_xml_bar3d_drift(drift);

    int rc = 0;

    if (!content_types || !rels || !doc_rels || !styles || !settings ||
        !web_settings || !font_table || !document) {
        rc = -1;
        goto cleanup;
    }

    if (zip_add_file(&z, "[Content_Types].xml", content_types, strlen(content_types)) != 0 ||
        zip_add_file(&z, "_rels/.rels", rels, strlen(rels)) != 0 ||
        zip_add_file(&z, "word/document.xml", document, strlen(document)) != 0 ||
        zip_add_file(&z, "word/styles.xml", styles, strlen(styles)) != 0 ||
        zip_add_file(&z, "word/settings.xml", settings, strlen(settings)) != 0 ||
        zip_add_file(&z, "word/webSettings.xml", web_settings, strlen(web_settings)) != 0 ||
        zip_add_file(&z, "word/fontTable.xml", font_table, strlen(font_table)) != 0 ||
        zip_add_file(&z, "word/_rels/document.xml.rels", doc_rels, strlen(doc_rels)) != 0) {
        rc = -1;
        goto cleanup;
    }

    if (chart1) {
        if (zip_add_file(&z, "word/charts/chart1.xml", chart1, strlen(chart1)) != 0)
            rc = -1;
    }
    if (chart2) {
        if (zip_add_file(&z, "word/charts/chart2.xml", chart2, strlen(chart2)) != 0)
            rc = -1;
    }
    if (chart3) {
        if (zip_add_file(&z, "word/charts/chart3.xml", chart3, strlen(chart3)) != 0)
            rc = -1;
    }

cleanup:
    free(content_types);
    free(rels);
    free(doc_rels);
    free(styles);
    free(settings);
    free(web_settings);
    free(font_table);
    free(document);
    free(chart1);
    free(chart2);
    free(chart3);

    if (zip_close(&z) != 0)
        rc = -1;

    return rc;
}
