#ifndef SANITIZE_H
#define SANITIZE_H

#include <stdbool.h>

/* Sanitize model output before persisting to conversation DB or MEMORY.md.
   Modifies `text` in-place, replacing detected secrets with [REDACTED].
   Returns number of redactions made. */
int sanitize_redact_secrets(char *text, int text_size);

/* Check if a string looks like it contains sensitive data */
bool sanitize_contains_secret(const char *text);

/* Redact a specific config value for display (e.g. skill config) */
void sanitize_redact_value(const char *value, char *output, int output_size);

#endif
