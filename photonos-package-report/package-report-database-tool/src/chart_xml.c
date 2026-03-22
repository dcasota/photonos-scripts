#include "chart_xml.h"
#include "security.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

void strbuf_init(strbuf_t *sb)
{
    sb->data = NULL;
    sb->len = 0;
    sb->cap = 0;
}

void strbuf_free(strbuf_t *sb)
{
    free(sb->data);
    sb->data = NULL;
    sb->len = 0;
    sb->cap = 0;
}

static int strbuf_grow(strbuf_t *sb, size_t need)
{
    if (sb->len + need + 1 <= sb->cap)
        return 0;
    size_t new_cap = sb->cap == 0 ? 4096 : sb->cap;
    while (new_cap < sb->len + need + 1)
        new_cap *= 2;
    char *nd = realloc(sb->data, new_cap);
    if (!nd)
        return -1;
    sb->data = nd;
    sb->cap = new_cap;
    return 0;
}

int strbuf_append(strbuf_t *sb, const char *s)
{
    if (!s)
        return 0;
    size_t slen = strlen(s);
    if (strbuf_grow(sb, slen) != 0)
        return -1;
    memcpy(sb->data + sb->len, s, slen);
    sb->len += slen;
    sb->data[sb->len] = '\0';
    return 0;
}

int strbuf_printf(strbuf_t *sb, const char *fmt, ...)
{
    char buf[4096];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (n < 0)
        return -1;
    if ((size_t)n >= sizeof(buf))
        n = (int)sizeof(buf) - 1;
    return strbuf_append(sb, buf);
}

/* Collect unique branches and unique datetimes from timeline data */
typedef struct {
    char branches[16][16];
    int nbranches;
    char datetimes[512][16];
    int ndatetimes;
} timeline_index_t;

static int find_or_add(char arr[][16], int *count, int max, const char *val)
{
    for (int i = 0; i < *count; i++) {
        if (strcmp(arr[i], val) == 0)
            return i;
    }
    if (*count >= max)
        return -1;
    secure_strncpy(arr[*count], val, 16);
    (*count)++;
    return *count - 1;
}

static void build_timeline_index(const timeline_data_t *data, timeline_index_t *idx)
{
    idx->nbranches = 0;
    idx->ndatetimes = 0;
    for (int i = 0; i < data->count; i++) {
        find_or_add(idx->branches, &idx->nbranches, 16, data->points[i].branch);
        find_or_add(idx->datetimes, &idx->ndatetimes, 512, data->points[i].scan_datetime);
    }
}

static int get_value(const timeline_data_t *data, const char *branch, const char *dt)
{
    for (int i = 0; i < data->count; i++) {
        if (strcmp(data->points[i].branch, branch) == 0 &&
            strcmp(data->points[i].scan_datetime, dt) == 0)
            return data->points[i].qualifying_count;
    }
    return 0;
}

/* OOXML color palette for branch series */
static const char *series_colors[] = {
    "4472C4", "ED7D31", "A5A5A5", "FFC000",
    "5B9BD5", "70AD47", "264478"
};

char *chart_xml_timeline(const timeline_data_t *data)
{
    if (!data || data->count == 0)
        return NULL;

    timeline_index_t idx;
    build_timeline_index(data, &idx);

    strbuf_t sb;
    strbuf_init(&sb);

    strbuf_append(&sb,
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n"
        "<c:chartSpace xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" "
        "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" "
        "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">\r\n"
        "<c:chart><c:plotArea><c:layout/>\r\n"
        "<c:lineChart><c:grouping val=\"standard\"/><c:varyColors val=\"0\"/>\r\n");

    for (int b = 0; b < idx.nbranches; b++) {
        int ci = b % 7;
        char *esc_branch = secure_xml_escape(idx.branches[b]);
        strbuf_printf(&sb, "<c:ser><c:idx val=\"%d\"/><c:order val=\"%d\"/>\r\n", b, b);
        strbuf_printf(&sb, "<c:tx><c:strRef><c:strCache><c:ptCount val=\"1\"/>"
                     "<c:pt idx=\"0\"><c:v>%s</c:v></c:pt></c:strCache></c:strRef></c:tx>\r\n",
                     esc_branch ? esc_branch : idx.branches[b]);
        free(esc_branch);

        strbuf_printf(&sb,
            "<c:spPr><a:ln w=\"22225\"><a:solidFill><a:srgbClr val=\"%s\"/></a:solidFill>"
            "<a:prstDash val=\"dash\"/></a:ln></c:spPr>\r\n", series_colors[ci]);

        /* Category (X-axis) references */
        strbuf_printf(&sb, "<c:cat><c:strRef><c:strCache><c:ptCount val=\"%d\"/>\r\n",
                     idx.ndatetimes);
        for (int d = 0; d < idx.ndatetimes; d++) {
            char *esc_dt = secure_xml_escape(idx.datetimes[d]);
            strbuf_printf(&sb, "<c:pt idx=\"%d\"><c:v>%s</c:v></c:pt>\r\n",
                         d, esc_dt ? esc_dt : idx.datetimes[d]);
            free(esc_dt);
        }
        strbuf_append(&sb, "</c:strCache></c:strRef></c:cat>\r\n");

        /* Values (Y-axis) */
        strbuf_printf(&sb, "<c:val><c:numRef><c:numCache><c:formatCode>General</c:formatCode>"
                     "<c:ptCount val=\"%d\"/>\r\n", idx.ndatetimes);
        for (int d = 0; d < idx.ndatetimes; d++) {
            int val = get_value(data, idx.branches[b], idx.datetimes[d]);
            strbuf_printf(&sb, "<c:pt idx=\"%d\"><c:v>%d</c:v></c:pt>\r\n", d, val);
        }
        strbuf_append(&sb, "</c:numCache></c:numRef></c:val>\r\n");
        strbuf_append(&sb, "<c:smooth val=\"0\"/></c:ser>\r\n");
    }

    strbuf_append(&sb,
        "<c:marker val=\"1\"/></c:lineChart>\r\n"
        "<c:catAx><c:axId val=\"1\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling>"
        "<c:delete val=\"0\"/><c:axPos val=\"b\"/><c:crossAx val=\"2\"/></c:catAx>\r\n"
        "<c:valAx><c:axId val=\"2\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling>"
        "<c:delete val=\"0\"/><c:axPos val=\"l\"/><c:crossAx val=\"1\"/></c:valAx>\r\n"
        "</c:plotArea>\r\n"
        "<c:legend><c:legendPos val=\"b\"/><c:overlay val=\"0\"/></c:legend>\r\n"
        "<c:plotVisOnly val=\"1\"/></c:chart></c:chartSpace>\r\n");

    char *result = sb.data;
    sb.data = NULL;
    strbuf_free(&sb);
    return result;
}

char *chart_xml_pie(const category_data_t *data)
{
    if (!data || data->count == 0)
        return NULL;

    strbuf_t sb;
    strbuf_init(&sb);

    strbuf_append(&sb,
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n"
        "<c:chartSpace xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" "
        "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" "
        "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">\r\n"
        "<c:chart><c:plotArea><c:layout/>\r\n"
        "<c:pieChart><c:varyColors val=\"1\"/>\r\n"
        "<c:ser><c:idx val=\"0\"/><c:order val=\"0\"/>\r\n"
        "<c:tx><c:strRef><c:strCache><c:ptCount val=\"1\"/>"
        "<c:pt idx=\"0\"><c:v>Package Sources</c:v></c:pt></c:strCache></c:strRef></c:tx>\r\n");

    /* Categories */
    strbuf_printf(&sb, "<c:cat><c:strRef><c:strCache><c:ptCount val=\"%d\"/>\r\n", data->count);
    for (int i = 0; i < data->count; i++) {
        char label[128];
        snprintf(label, sizeof(label), "%s (%d, %.1f%%)",
                data->items[i].category, data->items[i].count, data->items[i].percentage);
        char *esc = secure_xml_escape(label);
        strbuf_printf(&sb, "<c:pt idx=\"%d\"><c:v>%s</c:v></c:pt>\r\n", i, esc ? esc : label);
        free(esc);
    }
    strbuf_append(&sb, "</c:strCache></c:strRef></c:cat>\r\n");

    /* Values */
    strbuf_printf(&sb, "<c:val><c:numRef><c:numCache><c:formatCode>General</c:formatCode>"
                 "<c:ptCount val=\"%d\"/>\r\n", data->count);
    for (int i = 0; i < data->count; i++) {
        strbuf_printf(&sb, "<c:pt idx=\"%d\"><c:v>%d</c:v></c:pt>\r\n", i, data->items[i].count);
    }
    strbuf_append(&sb, "</c:numCache></c:numRef></c:val>\r\n");

    strbuf_append(&sb,
        "</c:ser></c:pieChart></c:plotArea>\r\n"
        "<c:legend><c:legendPos val=\"r\"/><c:overlay val=\"0\"/></c:legend>\r\n"
        "<c:plotVisOnly val=\"1\"/></c:chart></c:chartSpace>\r\n");

    char *result = sb.data;
    sb.data = NULL;
    strbuf_free(&sb);
    return result;
}
