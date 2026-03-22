#ifndef CHART_XML_H
#define CHART_XML_H

#include "db.h"

/* Dynamic string buffer for XML generation */
typedef struct {
    char *data;
    size_t len;
    size_t cap;
} strbuf_t;

void strbuf_init(strbuf_t *sb);
void strbuf_free(strbuf_t *sb);
int strbuf_append(strbuf_t *sb, const char *s);
int strbuf_printf(strbuf_t *sb, const char *fmt, ...);

/* Generate OOXML chart XML for a timeline line chart.
   Returns malloc'd XML string; caller frees. */
char *chart_xml_timeline(const timeline_data_t *data);

/* Generate OOXML chart XML for a pie chart.
   Returns malloc'd XML string; caller frees. */
char *chart_xml_pie(const category_data_t *data);

/* Generate OOXML chart XML for a 3D bar chart showing category drift.
   X-axis: scan runs, Y-axis: branches, Z-axis: percentage.
   Returns malloc'd XML string; caller frees. */
char *chart_xml_bar3d_drift(const category_drift_data_t *data);

#endif
