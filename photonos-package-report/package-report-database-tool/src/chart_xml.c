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



/* Convert YYYYMMDDHHmm datetime string to fractional year */
static double dt_to_fracyear(const char *dt)
{
    int y = 0, m = 1, d = 1, h = 0, mn = 0;
    if (strlen(dt) >= 4)  y  = (dt[0]-'0')*1000 + (dt[1]-'0')*100 + (dt[2]-'0')*10 + (dt[3]-'0');
    if (strlen(dt) >= 6)  m  = (dt[4]-'0')*10 + (dt[5]-'0');
    if (strlen(dt) >= 8)  d  = (dt[6]-'0')*10 + (dt[7]-'0');
    if (strlen(dt) >= 10) h  = (dt[8]-'0')*10 + (dt[9]-'0');
    if (strlen(dt) >= 12) mn = (dt[10]-'0')*10 + (dt[11]-'0');
    if (m < 1) m = 1;
    if (d < 1) d = 1;
    double day_of_year = (m - 1) * 30.44 + (d - 1) + h / 24.0 + mn / 1440.0;
    return y + day_of_year / 365.25;
}

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
        "<c:spPr><a:ln><a:noFill/></a:ln></c:spPr>\r\n"
        "<c:chart><c:plotArea><c:layout/>\r\n"
        "<c:scatterChart><c:scatterStyle val=\"line\"/><c:varyColors val=\"0\"/>\r\n");

    for (int b = 0; b < idx.nbranches; b++) {
        int ci = b % 7;
        char *esc_branch = secure_xml_escape(idx.branches[b]);
        strbuf_printf(&sb, "<c:ser><c:idx val=\"%d\"/><c:order val=\"%d\"/>\r\n", b, b);
        strbuf_printf(&sb, "<c:tx><c:strRef><c:strCache><c:ptCount val=\"1\"/>"
                     "<c:pt idx=\"0\"><c:v>%s</c:v></c:pt></c:strCache></c:strRef></c:tx>\r\n",
                     esc_branch ? esc_branch : idx.branches[b]);
        free(esc_branch);

        strbuf_printf(&sb,
            "<c:marker><c:symbol val=\"none\"/></c:marker>\r\n");
        strbuf_printf(&sb,
            "<c:spPr><a:ln w=\"22225\"><a:solidFill><a:srgbClr val=\"%s\"/></a:solidFill>"
            "</a:ln></c:spPr>\r\n", series_colors[ci]);

        /* Collect only points where this branch has data */
        int npts = 0;
        for (int d = 0; d < idx.ndatetimes; d++) {
            if (get_value(data, idx.branches[b], idx.datetimes[d]) > 0)
                npts++;
        }

        /* X values (fractional years) */
        strbuf_printf(&sb, "<c:xVal><c:numRef><c:numCache>"
                     "<c:formatCode>0</c:formatCode><c:ptCount val=\"%d\"/>\r\n", npts);
        int pi = 0;
        for (int d = 0; d < idx.ndatetimes; d++) {
            if (get_value(data, idx.branches[b], idx.datetimes[d]) > 0) {
                strbuf_printf(&sb, "<c:pt idx=\"%d\"><c:v>%.4f</c:v></c:pt>\r\n",
                             pi++, dt_to_fracyear(idx.datetimes[d]));
            }
        }
        strbuf_append(&sb, "</c:numCache></c:numRef></c:xVal>\r\n");

        /* Y values (qualifying count) */
        strbuf_printf(&sb, "<c:yVal><c:numRef><c:numCache>"
                     "<c:formatCode>General</c:formatCode><c:ptCount val=\"%d\"/>\r\n", npts);
        pi = 0;
        for (int d = 0; d < idx.ndatetimes; d++) {
            int val = get_value(data, idx.branches[b], idx.datetimes[d]);
            if (val > 0)
                strbuf_printf(&sb, "<c:pt idx=\"%d\"><c:v>%d</c:v></c:pt>\r\n", pi++, val);
        }
        strbuf_append(&sb, "</c:numCache></c:numRef></c:yVal>\r\n");
        strbuf_append(&sb, "<c:smooth val=\"0\"/></c:ser>\r\n");
    }

    /* Add linear trend line for branch 5.0, data between 2024 and 2026 only.
       Compute least-squares regression, then draw as a dotted 2-point series. */
    {
        int b50 = -1;
        for (int b = 0; b < idx.nbranches; b++) {
            if (strcmp(idx.branches[b], "5.0") == 0) { b50 = b; break; }
        }
        if (b50 >= 0) {
            /* Collect 5.0 points in [2024, 2026) for regression */
            double sx = 0, sy = 0, sxx = 0, sxy = 0;
            int n = 0;
            for (int d = 0; d < idx.ndatetimes; d++) {
                double fx = dt_to_fracyear(idx.datetimes[d]);
                int val = get_value(data, idx.branches[b50], idx.datetimes[d]);
                if (val > 0 && fx >= 2024.0 && fx < 2026.0) {
                    sx += fx; sy += val; sxx += fx * fx; sxy += fx * val;
                    n++;
                }
            }
            /* Draw trend line from 2024.0 to 2026.0 */
            if (n >= 2) {
                double slope = (n * sxy - sx * sy) / (n * sxx - sx * sx);
                double intercept = (sy - slope * sx) / n;
                double y1 = slope * 2024.0 + intercept;
                double y2 = slope * 2026.0 + intercept;
                int ser_idx = idx.nbranches;

                strbuf_printf(&sb,
                    "<c:ser><c:idx val=\"%d\"/><c:order val=\"%d\"/>\r\n", ser_idx, ser_idx);
                strbuf_append(&sb,
                    "<c:tx><c:strRef><c:strCache><c:ptCount val=\"1\"/>"
                    "<c:pt idx=\"0\"><c:v>5.0 trend</c:v></c:pt></c:strCache></c:strRef></c:tx>\r\n"
                    "<c:marker><c:symbol val=\"none\"/></c:marker>\r\n"
                    "<c:spPr><a:ln w=\"12700\"><a:solidFill><a:srgbClr val=\"A5A5A5\"/>"
                    "</a:solidFill><a:prstDash val=\"dot\"/></a:ln></c:spPr>\r\n");
                strbuf_printf(&sb,
                    "<c:xVal><c:numRef><c:numCache>"
                    "<c:formatCode>0</c:formatCode><c:ptCount val=\"2\"/>"
                    "<c:pt idx=\"0\"><c:v>2024.0000</c:v></c:pt>"
                    "<c:pt idx=\"1\"><c:v>%.4f</c:v></c:pt>"
                    "</c:numCache></c:numRef></c:xVal>\r\n", 2026.0);
                strbuf_printf(&sb,
                    "<c:yVal><c:numRef><c:numCache>"
                    "<c:formatCode>General</c:formatCode><c:ptCount val=\"2\"/>"
                    "<c:pt idx=\"0\"><c:v>%.1f</c:v></c:pt>"
                    "<c:pt idx=\"1\"><c:v>%.1f</c:v></c:pt>"
                    "</c:numCache></c:numRef></c:yVal>\r\n", y1, y2);
                strbuf_append(&sb, "<c:smooth val=\"0\"/></c:ser>\r\n");
            }
        }
    }

    strbuf_append(&sb,
        "<c:axId val=\"1\"/><c:axId val=\"2\"/>"
        "</c:scatterChart>\r\n");

    /* Compute dynamic X-max: last scan + 3 months, rounded up to next half year */
    double max_x = 2023.0;
    for (int d = 0; d < idx.ndatetimes; d++) {
        double fx = dt_to_fracyear(idx.datetimes[d]);
        if (fx > max_x) max_x = fx;
    }
    /* Add 3 months (0.25 year), then round up to next 0.5 boundary */
    double end_frac = max_x + 0.25;
    int end_year = (int)end_frac;
    double remainder = end_frac - end_year;
    double x_max;
    if (remainder <= 0.0)
        x_max = (double)end_year;
    else if (remainder <= 0.5)
        x_max = end_year + 0.5;
    else
        x_max = end_year + 1.0;

    /* X-axis: linear value axis, major=1yr, minor=half-year, gridlines */
    strbuf_printf(&sb,
        "<c:valAx><c:axId val=\"1\"/>"
        "<c:scaling><c:orientation val=\"minMax\"/>"
        "<c:min val=\"2023\"/><c:max val=\"%.1f\"/></c:scaling>"
        "<c:delete val=\"0\"/><c:axPos val=\"b\"/><c:crossAx val=\"2\"/>"
        "<c:majorUnit val=\"1\"/><c:minorUnit val=\"0.5\"/>"
        "<c:numFmt formatCode=\"0\" sourceLinked=\"0\"/>"
        "<c:majorTickMark val=\"out\"/><c:minorTickMark val=\"out\"/>"
        "<c:majorGridlines><c:spPr><a:ln w=\"3175\"><a:solidFill>"
        "<a:srgbClr val=\"D9D9D9\"/></a:solidFill></a:ln></c:spPr></c:majorGridlines>"
        "<c:minorGridlines><c:spPr><a:ln w=\"3175\"><a:solidFill>"
        "<a:srgbClr val=\"F0F0F0\"/></a:solidFill><a:prstDash val=\"dot\"/>"
        "</a:ln></c:spPr></c:minorGridlines>"
        "<c:txPr><a:bodyPr/><a:lstStyle/>"
        "<a:p><a:pPr><a:defRPr sz=\"800\"/></a:pPr><a:endParaRPr lang=\"en-US\"/></a:p></c:txPr>"
        "</c:valAx>\r\n", x_max);

    /* Y-axis: major=100, gridlines, title positioned left */
    strbuf_append(&sb,
        "<c:valAx><c:axId val=\"2\"/>"
        "<c:scaling><c:orientation val=\"minMax\"/></c:scaling>"
        "<c:delete val=\"0\"/><c:axPos val=\"l\"/><c:crossAx val=\"1\"/>"
        "<c:majorUnit val=\"100\"/>"
        "<c:majorGridlines><c:spPr><a:ln w=\"3175\"><a:solidFill>"
        "<a:srgbClr val=\"D9D9D9\"/></a:solidFill></a:ln></c:spPr></c:majorGridlines>"
        "<c:minorGridlines><c:spPr><a:ln w=\"3175\"><a:solidFill>"
        "<a:srgbClr val=\"F0F0F0\"/></a:solidFill><a:prstDash val=\"dot\"/>"
        "</a:ln></c:spPr></c:minorGridlines>"
        "<c:title>"
        "<c:layout><c:manualLayout>"
        "<c:xMode val=\"edge\"/><c:yMode val=\"edge\"/>"
        "<c:x val=\"0.0\"/><c:y val=\"0.25\"/>"
        "</c:manualLayout></c:layout>"
        "<c:tx><c:rich>"
        "<a:bodyPr rot=\"-5400000\" vert=\"horz\"/><a:lstStyle/>"
        "<a:p><a:pPr><a:defRPr sz=\"800\"/></a:pPr>"
        "<a:r><a:rPr sz=\"800\"/><a:t>Qualifying packages</a:t></a:r></a:p>"
        "</c:rich></c:tx></c:title>"
        "<c:numFmt formatCode=\"#,##0\" sourceLinked=\"0\"/>"
        "<c:txPr><a:bodyPr/><a:lstStyle/>"
        "<a:p><a:pPr><a:defRPr sz=\"700\"/></a:pPr><a:endParaRPr lang=\"en-US\"/></a:p></c:txPr>"
        "</c:valAx>\r\n"
        "</c:plotArea>\r\n"
        "<c:legend><c:legendPos val=\"b\"/><c:overlay val=\"0\"/></c:legend>\r\n"
        "<c:plotVisOnly val=\"1\"/>"
        "</c:chart></c:chartSpace>\r\n");

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
        "<c:spPr><a:ln><a:noFill/></a:ln></c:spPr>\r\n"
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

static double drift_get_pct(const category_drift_data_t *data,
                            const char *branch, const char *dt, const char *cat)
{
    for (int i = 0; i < data->count; i++) {
        if (strcmp(data->points[i].branch, branch) == 0 &&
            strcmp(data->points[i].scan_datetime, dt) == 0 &&
            strcmp(data->points[i].category, cat) == 0)
            return data->points[i].percentage;
    }
    return 0.0;
}

static int drift_collect_datetimes(const category_drift_data_t *data,
                                   char out[][16], int max)
{
    int n = 0;
    for (int i = 0; i < data->count; i++) {
        int found = 0;
        for (int j = 0; j < n; j++) {
            if (strcmp(out[j], data->points[i].scan_datetime) == 0) { found = 1; break; }
        }
        if (!found && n < max) {
            secure_strncpy(out[n], data->points[i].scan_datetime, 16);
            n++;
        }
    }
    return n;
}

char *chart_xml_bar3d_drift(const category_drift_data_t *data)
{
    if (!data || data->count == 0)
        return NULL;

    /* Collect unique scan datetimes sorted */
    char datetimes[512][16];
    int ndt = drift_collect_datetimes(data, datetimes, 512);
    for (int i = 0; i < ndt - 1; i++)
        for (int j = i + 1; j < ndt; j++)
            if (strcmp(datetimes[i], datetimes[j]) > 0) {
                char tmp[16];
                memcpy(tmp, datetimes[i], 16);
                memcpy(datetimes[i], datetimes[j], 16);
                memcpy(datetimes[j], tmp, 16);
            }

    /* Build evenly-spaced quarterly time slots from 2023-Q1 to dynamic end.
       Each slot = 0.25 year. This ensures linear time spacing. */
    double last_fx = 2023.0;
    for (int d = 0; d < ndt; d++) {
        double fx = dt_to_fracyear(datetimes[d]);
        if (fx > last_fx) last_fx = fx;
    }
    double end_frac = last_fx + 0.25;
    int end_year = (int)end_frac;
    double remainder = end_frac - end_year;
    double x_max;
    if (remainder <= 0.0) x_max = (double)end_year;
    else if (remainder <= 0.5) x_max = end_year + 0.5;
    else x_max = end_year + 1.0;

    int nslots = (int)((x_max - 2023.0) / 0.25 + 0.5);
    if (nslots < 1) nslots = 1;
    if (nslots > 64) nslots = 64;

    /* Option C: line3DChart, one series per category, branches averaged.
       pct_grid[category][slot] = avg pct across branches with data */
    double pct_grid[32][64];
    memset(pct_grid, 0, sizeof(pct_grid));

    for (int c = 0; c < data->ncategories && c < 32; c++) {
        double last_avg = 0.0;
        for (int s = 0; s < nslots; s++) {
            double slot_start = 2023.0 + s * 0.25;
            double slot_end = slot_start + 0.25;
            double sum = 0.0;
            int cnt = 0;
            for (int d = 0; d < ndt; d++) {
                double fx = dt_to_fracyear(datetimes[d]);
                if (fx >= slot_start && fx < slot_end) {
                    for (int b = 0; b < data->nbranches; b++) {
                        double p = drift_get_pct(data, data->branches[b],
                                                 datetimes[d], data->categories[c]);
                        if (p > 0.0) { sum += p; cnt++; }
                    }
                }
            }
            if (cnt > 0) last_avg = sum / cnt;
            pct_grid[c][s] = last_avg;
        }
    }

    /* 9 distinct category colors */
    static const char *cat_colors[] = {
        "4472C4", "ED7D31", "A5A5A5", "FFC000", "5B9BD5",
        "70AD47", "264478", "9B59B6", "E74C3C"
    };

    strbuf_t sb;
    strbuf_init(&sb);

    strbuf_append(&sb,
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n"
        "<c:chartSpace xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" "
        "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" "
        "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">\r\n"
        "<c:spPr><a:ln><a:noFill/></a:ln></c:spPr>\r\n"
        "<c:chart><c:plotArea><c:layout/>\r\n"
        "<c:barChart><c:barDir val=\"col\"/><c:grouping val=\"percentStacked\"/>"
        "<c:varyColors val=\"0\"/>\r\n");

    /* One series per source category, stacked to 100% */
    for (int c = 0; c < data->ncategories; c++) {
        int ci = c % 9;
        char *esc_cat = secure_xml_escape(data->categories[c]);
        strbuf_printf(&sb, "<c:ser><c:idx val=\"%d\"/><c:order val=\"%d\"/>\r\n", c, c);
        strbuf_printf(&sb, "<c:tx><c:strRef><c:strCache><c:ptCount val=\"1\"/>"
            "<c:pt idx=\"0\"><c:v>%s</c:v></c:pt></c:strCache></c:strRef></c:tx>\r\n",
            esc_cat ? esc_cat : data->categories[c]);
        free(esc_cat);

        strbuf_printf(&sb,
            "<c:spPr><a:solidFill><a:srgbClr val=\"%s\"/></a:solidFill>"
            "<a:ln w=\"3175\"><a:solidFill><a:srgbClr val=\"FFFFFF\"/>"
            "</a:solidFill></a:ln></c:spPr>\r\n", cat_colors[ci]);

        /* Cat axis: quarterly slots, year labels only */
        strbuf_printf(&sb, "<c:cat><c:strRef><c:strCache><c:ptCount val=\"%d\"/>\r\n", nslots);
        for (int s = 0; s < nslots; s++) {
            double slot_start = 2023.0 + s * 0.25;
            int yr = (int)slot_start;
            double frac = slot_start - yr;
            if (frac < 0.01)
                strbuf_printf(&sb, "<c:pt idx=\"%d\"><c:v>%d</c:v></c:pt>\r\n", s, yr);
            else
                strbuf_printf(&sb, "<c:pt idx=\"%d\"><c:v></c:v></c:pt>\r\n", s);
        }
        strbuf_append(&sb, "</c:strCache></c:strRef></c:cat>\r\n");

        strbuf_printf(&sb, "<c:val><c:numRef><c:numCache><c:formatCode>0.0</c:formatCode>"
            "<c:ptCount val=\"%d\"/>\r\n", nslots);
        for (int s = 0; s < nslots; s++) {
            strbuf_printf(&sb, "<c:pt idx=\"%d\"><c:v>%.1f</c:v></c:pt>\r\n",
                         s, pct_grid[c][s]);
        }
        strbuf_append(&sb, "</c:numCache></c:numRef></c:val>\r\n");
        strbuf_append(&sb, "</c:ser>\r\n");
    }

    strbuf_append(&sb,
        "<c:overlap val=\"100\"/><c:gapWidth val=\"50\"/>"
        "<c:axId val=\"1\"/><c:axId val=\"2\"/>"
        "</c:barChart>\r\n");

    /* catAx (X) = Scan timeline */
    strbuf_append(&sb,
        "<c:catAx><c:axId val=\"1\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling>"
        "<c:delete val=\"0\"/><c:axPos val=\"b\"/><c:crossAx val=\"2\"/>"
        "<c:tickLblSkip val=\"1\"/>"
        "<c:txPr><a:bodyPr rot=\"0\" vert=\"horz\"/><a:lstStyle/>"
        "<a:p><a:pPr><a:defRPr sz=\"800\"/></a:pPr><a:endParaRPr lang=\"en-US\"/></a:p></c:txPr>"
        "</c:catAx>\r\n");

    /* valAx (Y) = 0-100% */
    strbuf_append(&sb,
        "<c:valAx><c:axId val=\"2\"/>"
        "<c:scaling><c:orientation val=\"minMax\"/>"
        "<c:min val=\"0\"/><c:max val=\"1\"/></c:scaling>"
        "<c:delete val=\"0\"/><c:axPos val=\"l\"/><c:crossAx val=\"1\"/>"
        "<c:numFmt formatCode=\"0%\" sourceLinked=\"0\"/>"
        "<c:majorUnit val=\"0.2\"/>"
        "<c:txPr><a:bodyPr/><a:lstStyle/>"
        "<a:p><a:pPr><a:defRPr sz=\"800\"/></a:pPr><a:endParaRPr lang=\"en-US\"/></a:p></c:txPr>"
        "</c:valAx>\r\n"
        "</c:plotArea>\r\n"
        "<c:legend><c:legendPos val=\"b\"/><c:overlay val=\"0\"/></c:legend>\r\n"
        "<c:plotVisOnly val=\"1\"/></c:chart></c:chartSpace>\r\n");

    char *drift_result = sb.data;
    sb.data = NULL;
    strbuf_free(&sb);
    return drift_result;
}

char *chart_xml_bar_stacked_branch(const category_drift_data_t *data, const char *branch)
{
    if (!data || data->count == 0 || !branch)
        return NULL;

    char datetimes[512][16];
    int ndt = 0;
    for (int i = 0; i < data->count && ndt < 512; i++) {
        if (strcmp(data->points[i].branch, branch) != 0) continue;
        int found = 0;
        for (int j = 0; j < ndt; j++)
            if (strcmp(datetimes[j], data->points[i].scan_datetime) == 0) { found = 1; break; }
        if (!found) {
            secure_strncpy(datetimes[ndt], data->points[i].scan_datetime, 16);
            ndt++;
        }
    }
    for (int i = 0; i < ndt - 1; i++)
        for (int j = i + 1; j < ndt; j++)
            if (strcmp(datetimes[i], datetimes[j]) > 0) {
                char tmp[16];
                memcpy(tmp, datetimes[i], 16);
                memcpy(datetimes[i], datetimes[j], 16);
                memcpy(datetimes[j], tmp, 16);
            }

    if (ndt == 0) return NULL;

    double last_fx = 2023.0;
    for (int d = 0; d < ndt; d++) {
        double fx = dt_to_fracyear(datetimes[d]);
        if (fx > last_fx) last_fx = fx;
    }
    double end_frac = last_fx + 0.25;
    int end_year = (int)end_frac;
    double rem = end_frac - end_year;
    double x_max;
    if (rem <= 0.0) x_max = (double)end_year;
    else if (rem <= 0.5) x_max = end_year + 0.5;
    else x_max = end_year + 1.0;

    int nslots = (int)((x_max - 2023.0) / 0.25 + 0.5);
    if (nslots < 1) nslots = 1;
    if (nslots > 64) nslots = 64;

    double pct_grid[32][64];
    memset(pct_grid, 0, sizeof(pct_grid));
    for (int c = 0; c < data->ncategories && c < 32; c++) {
        double last_pct = 0.0;
        for (int s = 0; s < nslots; s++) {
            double slot_start = 2023.0 + s * 0.25;
            double slot_end = slot_start + 0.25;
            double best = 0.0;
            int found_slot = 0;
            for (int d = 0; d < ndt; d++) {
                double fx = dt_to_fracyear(datetimes[d]);
                if (fx >= slot_start && fx < slot_end) {
                    double p = drift_get_pct(data, branch, datetimes[d], data->categories[c]);
                    if (p > 0.0) { best = p; found_slot = 1; break; }
                }
            }
            if (found_slot) last_pct = best;
            pct_grid[c][s] = last_pct;
        }
    }

    static const char *cat_colors[] = {
        "4472C4", "ED7D31", "A5A5A5", "FFC000", "5B9BD5",
        "70AD47", "264478", "9B59B6", "E74C3C"
    };

    strbuf_t sb;
    strbuf_init(&sb);

    strbuf_append(&sb,
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n"
        "<c:chartSpace xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" "
        "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" "
        "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">\r\n"
        "<c:spPr><a:ln><a:noFill/></a:ln></c:spPr>\r\n");

    strbuf_append(&sb, "<c:chart>\r\n");

    strbuf_append(&sb,
        "<c:plotArea><c:layout/>\r\n"
        "<c:barChart><c:barDir val=\"col\"/><c:grouping val=\"percentStacked\"/>"
        "<c:varyColors val=\"0\"/>\r\n");

    for (int c = 0; c < data->ncategories; c++) {
        int ci = c % 9;
        char *esc_cat = secure_xml_escape(data->categories[c]);
        strbuf_printf(&sb, "<c:ser><c:idx val=\"%d\"/><c:order val=\"%d\"/>\r\n", c, c);
        strbuf_printf(&sb, "<c:tx><c:strRef><c:strCache><c:ptCount val=\"1\"/>"
            "<c:pt idx=\"0\"><c:v>%s</c:v></c:pt></c:strCache></c:strRef></c:tx>\r\n",
            esc_cat ? esc_cat : data->categories[c]);
        free(esc_cat);
        strbuf_printf(&sb,
            "<c:spPr><a:solidFill><a:srgbClr val=\"%s\"/></a:solidFill>"
            "<a:ln w=\"3175\"><a:solidFill><a:srgbClr val=\"FFFFFF\"/>"
            "</a:solidFill></a:ln></c:spPr>\r\n", cat_colors[ci]);

        strbuf_printf(&sb, "<c:cat><c:strRef><c:strCache><c:ptCount val=\"%d\"/>\r\n", nslots);
        for (int s = 0; s < nslots; s++) {
            double slot_start = 2023.0 + s * 0.25;
            int yr = (int)slot_start;
            double frac = slot_start - yr;
            if (frac < 0.01)
                strbuf_printf(&sb, "<c:pt idx=\"%d\"><c:v>%d</c:v></c:pt>\r\n", s, yr);
            else
                strbuf_printf(&sb, "<c:pt idx=\"%d\"><c:v></c:v></c:pt>\r\n", s);
        }
        strbuf_append(&sb, "</c:strCache></c:strRef></c:cat>\r\n");

        strbuf_printf(&sb, "<c:val><c:numRef><c:numCache><c:formatCode>0.0</c:formatCode>"
            "<c:ptCount val=\"%d\"/>\r\n", nslots);
        for (int s = 0; s < nslots; s++)
            strbuf_printf(&sb, "<c:pt idx=\"%d\"><c:v>%.1f</c:v></c:pt>\r\n", s, pct_grid[c][s]);
        strbuf_append(&sb, "</c:numCache></c:numRef></c:val>\r\n");
        strbuf_append(&sb, "</c:ser>\r\n");
    }

    strbuf_append(&sb,
        "<c:overlap val=\"100\"/><c:gapWidth val=\"50\"/>"
        "<c:axId val=\"1\"/><c:axId val=\"2\"/>"
        "</c:barChart>\r\n"
        "<c:catAx><c:axId val=\"1\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling>"
        "<c:delete val=\"0\"/><c:axPos val=\"b\"/><c:crossAx val=\"2\"/>"
        "<c:tickLblSkip val=\"1\"/>"
        "<c:txPr><a:bodyPr rot=\"0\" vert=\"horz\"/><a:lstStyle/>"
        "<a:p><a:pPr><a:defRPr sz=\"700\"/></a:pPr><a:endParaRPr lang=\"en-US\"/></a:p></c:txPr>"
        "</c:catAx>\r\n"
        "<c:valAx><c:axId val=\"2\"/>"
        "<c:scaling><c:orientation val=\"minMax\"/>"
        "<c:min val=\"0\"/><c:max val=\"1\"/></c:scaling>"
        "<c:delete val=\"0\"/><c:axPos val=\"l\"/><c:crossAx val=\"1\"/>"
        "<c:numFmt formatCode=\"0%\" sourceLinked=\"0\"/>"
        "<c:majorUnit val=\"0.2\"/>"
        "<c:txPr><a:bodyPr/><a:lstStyle/>"
        "<a:p><a:pPr><a:defRPr sz=\"700\"/></a:pPr><a:endParaRPr lang=\"en-US\"/></a:p></c:txPr>"
        "</c:valAx>\r\n"
        "</c:plotArea>\r\n"
        "<c:legend><c:legendPos val=\"b\"/><c:overlay val=\"0\"/></c:legend>\r\n"
        "<c:plotVisOnly val=\"1\"/></c:chart></c:chartSpace>\r\n");

    char *branch_result = sb.data;
    sb.data = NULL;
    strbuf_free(&sb);
    return branch_result;
}
