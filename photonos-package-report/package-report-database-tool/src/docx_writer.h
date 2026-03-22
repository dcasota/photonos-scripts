#ifndef DOCX_WRITER_H
#define DOCX_WRITER_H

#include "db.h"

/* Write a complete .docx report file. Returns 0 on success. */
int docx_write_report(const char *output_path,
                      const timeline_data_t *timeline,
                      const top_changed_data_t *top_changed,
                      const least_changed_data_t *least_changed,
                      const category_data_t *categories,
                      const category_drift_data_t *drift);

#endif
