#ifndef DOCX_WRITER_H
#define DOCX_WRITER_H

#include "db.h"

/* Write a complete .docx report file. Returns 0 on success.
 *
 * M127: `timeline_chart_png` is an OPTIONAL path to a PNG file. When non-NULL
 * and readable, Section 1's "Package Health Timeline" embeds that PNG image
 * instead of the hand-built OOXML c:chart (chart1.xml is then omitted). The
 * caller is expected to pre-render the PNG (the workflow does this via
 * .github/scripts/gen-timeline-chart.py before invoking photon-report-db).
 * When NULL or unreadable, the legacy chart1.xml c:chart path is preserved
 * byte-identically. */
int docx_write_report(const char *output_path,
                      const timeline_data_t *timeline,
                      const top_changed_data_t *top_changed,
                      const least_changed_data_t *least_changed,
                      const category_data_t *categories,
                      const category_drift_data_t *drift,
                      const char *timeline_chart_png);

#endif
