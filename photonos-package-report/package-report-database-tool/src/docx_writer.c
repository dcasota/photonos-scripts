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
    unsigned short dos_time;
    unsigned short dos_date;
} zipwriter_t;

static int zip_open(zipwriter_t *z, const char *path)
{
    memset(z, 0, sizeof(*z));
    z->fp = fopen(path, "wb");
    if (!z->fp) return -1;

    /* Encode current UTC time as MS-DOS timestamp */
    time_t now = time(NULL);
    struct tm *tm = gmtime(&now);
    z->dos_time = (unsigned short)(((tm->tm_hour & 0x1F) << 11) |
                                   ((tm->tm_min & 0x3F) << 5) |
                                   ((tm->tm_sec / 2) & 0x1F));
    z->dos_date = (unsigned short)((((tm->tm_year - 80) & 0x7F) << 9) |
                                   (((tm->tm_mon + 1) & 0x0F) << 5) |
                                   (tm->tm_mday & 0x1F));
    return 0;
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
    zip_write16(z->fp, z->dos_time);  /* mod time */
    zip_write16(z->fp, z->dos_date);  /* mod date */
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

/* Generate OOXML content type XML.
 * M127: when use_png_timeline=1, declare png as a Default extension AND drop
 * the chart1 override (Section 1's chart1.xml is replaced by the embedded
 * PNG). chart2 + chart3 (pie + drift) stay untouched. */
static char *gen_content_types(int use_png_timeline)
{
    strbuf_t sb; strbuf_init(&sb);
    strbuf_append(&sb,
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n"
        "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        "<Default Extension=\"xml\" ContentType=\"application/xml\"/>");
    if (use_png_timeline) {
        strbuf_append(&sb,
            "<Default Extension=\"png\" ContentType=\"image/png\"/>");
    }
    strbuf_append(&sb,
        "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>"
        "<Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/>"
        "<Override PartName=\"/word/settings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml\"/>"
        "<Override PartName=\"/word/webSettings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.webSettings+xml\"/>"
        "<Override PartName=\"/word/fontTable.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml\"/>");
    if (!use_png_timeline) {
        strbuf_append(&sb,
            "<Override PartName=\"/word/charts/chart1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/>");
    }
    strbuf_append(&sb,
        "<Override PartName=\"/word/charts/chart2.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/>"
        "<Override PartName=\"/word/charts/chart3.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/>"
        "</Types>");
    char *out = sb.data; sb.data = NULL; strbuf_free(&sb);
    return out;
}

static char *gen_rels(void)
{
    return strdup(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n"
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>"
        "</Relationships>");
}

/* M127: when use_png_timeline=1, rId2 points at the embedded PNG
 * (media/timeline.png) instead of charts/chart1.xml. */
static char *gen_doc_rels(int use_png_timeline)
{
    strbuf_t sb; strbuf_init(&sb);
    strbuf_append(&sb,
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n"
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>");
    if (use_png_timeline) {
        strbuf_append(&sb,
            "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/timeline.png\"/>");
    } else {
        strbuf_append(&sb,
            "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart\" Target=\"charts/chart1.xml\"/>");
    }
    strbuf_append(&sb,
        "<Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart\" Target=\"charts/chart2.xml\"/>"
        "<Relationship Id=\"rId4\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart\" Target=\"charts/chart3.xml\"/>"
        "<Relationship Id=\"rId5\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings\" Target=\"settings.xml\"/>"
        "<Relationship Id=\"rId6\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/webSettings\" Target=\"webSettings.xml\"/>"
        "<Relationship Id=\"rId7\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/fontTable\" Target=\"fontTable.xml\"/>"
        "</Relationships>");
    char *out = sb.data; sb.data = NULL; strbuf_free(&sb);
    return out;
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

/* M127 helpers: PNG embed -------------------------------------------- */

/* Slurp a file into a heap buffer. Returns malloc'd bytes (caller frees)
 * and writes *out_len. Returns NULL on any error. */
static unsigned char *read_file_bytes(const char *path, size_t *out_len)
{
    if (!path || !out_len) return NULL;
    FILE *fp = fopen(path, "rb");
    if (!fp) return NULL;
    if (fseek(fp, 0, SEEK_END) != 0) { fclose(fp); return NULL; }
    long n = ftell(fp);
    if (n < 0) { fclose(fp); return NULL; }
    if (fseek(fp, 0, SEEK_SET) != 0) { fclose(fp); return NULL; }
    unsigned char *buf = malloc((size_t)n);
    if (!buf) { fclose(fp); return NULL; }
    if (fread(buf, 1, (size_t)n, fp) != (size_t)n) { fclose(fp); free(buf); return NULL; }
    fclose(fp);
    *out_len = (size_t)n;
    return buf;
}

/* Parse PNG IHDR to get width/height in pixels. PNG layout:
 *   bytes 0-7   signature 89 50 4E 47 0D 0A 1A 0A
 *   bytes 8-11  chunk length (4 bytes, big-endian)
 *   bytes 12-15 chunk type "IHDR"
 *   bytes 16-19 width  (big-endian uint32)
 *   bytes 20-23 height (big-endian uint32)
 * Returns 0 on success. */
static int parse_png_dims(const unsigned char *b, size_t n,
                          unsigned *out_w, unsigned *out_h)
{
    static const unsigned char sig[8] = {0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A};
    if (!b || n < 24 || memcmp(b, sig, 8) != 0) return -1;
    if (memcmp(b + 12, "IHDR", 4) != 0) return -1;
    *out_w = (unsigned)b[16] << 24 | (unsigned)b[17] << 16 |
             (unsigned)b[18] <<  8 | (unsigned)b[19];
    *out_h = (unsigned)b[20] << 24 | (unsigned)b[21] << 16 |
             (unsigned)b[22] <<  8 | (unsigned)b[23];
    return 0;
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

/* M127: inline picture (PNG) reference. Uses the same wp:inline frame as
 * doc_add_chart_ref but swaps a:graphicData → DrawingML picture (pic:pic
 * with a:blip r:embed). EMU sizing keeps the rendered image at the same
 * 5486400 × ((cy × h)/w) box width so the layout matches the legacy chart.
 * 914400 EMU = 1 inch; 9525 EMU = 1 px at 96 DPI. */
static void doc_add_picture(strbuf_t *sb, const char *rid,
                            unsigned px_w, unsigned px_h)
{
    int dpid = s_next_docpr_id++;
    /* Hold display width at 6 inches (5,486,400 EMU); scale height to preserve aspect. */
    long long cx = 5486400LL;
    long long cy = (px_w > 0) ? (cx * (long long)px_h) / (long long)px_w : 3200400LL;
    if (cy <= 0) cy = 3200400LL;
    strbuf_printf(sb,
        "<w:p><w:r>"
        "<w:drawing>"
        "<wp:inline xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" "
        "distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\">"
        "<wp:extent cx=\"%lld\" cy=\"%lld\"/>"
        "<wp:docPr id=\"%d\" name=\"Timeline %d\"/>"
        "<wp:cNvGraphicFramePr>"
        "<a:graphicFrameLocks xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" noChangeAspect=\"1\"/>"
        "</wp:cNvGraphicFramePr>"
        "<a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\">"
        "<a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">"
        "<pic:pic xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">"
        "<pic:nvPicPr>"
        "<pic:cNvPr id=\"%d\" name=\"timeline.png\"/>"
        "<pic:cNvPicPr/>"
        "</pic:nvPicPr>"
        "<pic:blipFill>"
        "<a:blip xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" r:embed=\"%s\"/>"
        "<a:stretch><a:fillRect/></a:stretch>"
        "</pic:blipFill>"
        "<pic:spPr>"
        "<a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"%lld\" cy=\"%lld\"/></a:xfrm>"
        "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>"
        "</pic:spPr>"
        "</pic:pic>"
        "</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>\r\n",
        cx, cy, dpid, dpid, dpid, rid, cx, cy);
}

/* M127: when timeline_png_w/h > 0, Section 1 embeds a PNG via doc_add_picture
 * (rId2 now resolves to media/timeline.png). When both are 0, the legacy
 * c:chart reference path is used. */
static char *gen_document(const top_changed_data_t *top_changed,
                          const least_changed_data_t *least_changed,
                          unsigned timeline_png_w,
                          unsigned timeline_png_h)
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
    if (timeline_png_w > 0 && timeline_png_h > 0) {
        /* M127: dynamic per-run PNG generated by the workflow's Python step. */
        doc_add_picture(&sb, "rId2", timeline_png_w, timeline_png_h);
    } else {
        doc_add_chart_ref(&sb, "rId2");
    }

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
    doc_add_para(&sb, "Packages with the same release version in every scan. "
                      "Excludes VMware-internal and archived packages.");
    if (least_changed && least_changed->count > 0) {
        char list_buf[8192];
        int pos = 0;
        for (int i = 0; i < least_changed->count; i++) {
            if (i > 0)
                pos += snprintf(list_buf + pos, sizeof(list_buf) - (size_t)pos, ", ");
            pos += snprintf(list_buf + pos, sizeof(list_buf) - (size_t)pos, "%s",
                           least_changed->items[i].name);
            if (pos >= (int)sizeof(list_buf) - 64) break;
        }
        char count_buf[64];
        snprintf(count_buf, sizeof(count_buf), "%d packages: ", least_changed->count);
        strbuf_append(&sb, "<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>");
        strbuf_append(&sb, count_buf);
        strbuf_append(&sb, "</w:t></w:r><w:r><w:t xml:space=\"preserve\">");
        char *esc = secure_xml_escape(list_buf);
        strbuf_append(&sb, esc ? esc : list_buf);
        free(esc);
        strbuf_append(&sb, "</w:t></w:r></w:p>\r\n");
    } else {
        doc_add_para(&sb, "No packages found with unchanged release across all scans.");
    }

    /* Section 4: Source Category Drift */
    doc_add_heading(&sb, "4. Source Category Drift", "Heading2");
    doc_add_para(&sb, "Distribution of packages by source URL domain for branch 5.0 (latest scan). "
                      "Categories below 3% are merged into Other.");
    doc_add_chart_ref(&sb, "rId3");
    doc_add_para(&sb, "Category percentage drift over time for 5.0 branch.");
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
                      const category_drift_data_t *drift,
                      const char *timeline_chart_png)
{
    if (!output_path)
        return -1;

    /* M127: optional PNG embed. When the file is given AND readable AND
     * its IHDR parses cleanly, the workflow's pre-rendered chart wins
     * Section 1. Otherwise we silently fall back to the OOXML c:chart. */
    unsigned char *png_bytes = NULL;
    size_t         png_len   = 0;
    unsigned       png_w = 0, png_h = 0;
    int            use_png  = 0;
    if (timeline_chart_png && timeline_chart_png[0]) {
        png_bytes = read_file_bytes(timeline_chart_png, &png_len);
        if (png_bytes && parse_png_dims(png_bytes, png_len, &png_w, &png_h) == 0) {
            use_png = 1;
        } else {
            fprintf(stderr,
                "::warning::timeline_chart_png='%s' unreadable or not a valid PNG — "
                "falling back to OOXML c:chart\n", timeline_chart_png);
            free(png_bytes);
            png_bytes = NULL;
            png_len = 0;
        }
    }

    zipwriter_t z;
    if (zip_open(&z, output_path) != 0) {
        fprintf(stderr, "Cannot create output file: %s\n", output_path);
        free(png_bytes);
        return -1;
    }

    /* Generate all XML content */
    char *content_types = gen_content_types(use_png);
    char *rels = gen_rels();
    char *doc_rels = gen_doc_rels(use_png);
    char *styles = gen_styles();
    char *settings = gen_settings();
    char *web_settings = gen_web_settings();
    char *font_table = gen_font_table();
    char *document = gen_document(top_changed, least_changed,
                                  use_png ? png_w : 0,
                                  use_png ? png_h : 0);
    char *chart1 = use_png ? NULL : chart_xml_timeline(timeline);
    char *chart2 = chart_xml_pie(categories);
    char *chart3 = chart_xml_bar_stacked_branch(drift, "5.0");

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

    if (use_png) {
        if (zip_add_file(&z, "word/media/timeline.png", png_bytes, png_len) != 0)
            rc = -1;
    } else if (chart1 && zip_add_file(&z, "word/charts/chart1.xml", chart1, strlen(chart1)) != 0) {
        rc = -1;
    }
    if (chart2 && zip_add_file(&z, "word/charts/chart2.xml", chart2, strlen(chart2)) != 0)
        rc = -1;
    if (chart3 && zip_add_file(&z, "word/charts/chart3.xml", chart3, strlen(chart3)) != 0)
        rc = -1;

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
    free(png_bytes);

    if (zip_close(&z) != 0)
        rc = -1;

    return rc;
}
