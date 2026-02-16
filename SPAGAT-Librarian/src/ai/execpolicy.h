#ifndef EXECPOLICY_H
#define EXECPOLICY_H

#include <stdbool.h>

typedef enum {
    POLICY_ALLOW,
    POLICY_PROMPT,
    POLICY_FORBIDDEN
} PolicyDecision;

typedef struct {
    PolicyDecision decision;
    char justification[256];
} PolicyResult;

/* Initialize default rules */
void execpolicy_init(void);

/* Evaluate a shell command against rules */
PolicyResult execpolicy_evaluate(const char *command);

/* Load additional rules from file (one rule per line format:
   allow: cmd1 cmd2
   prompt: cmd3 cmd4
   forbidden: cmd5 cmd6 */
bool execpolicy_load_rules(const char *path);

/* Reset to defaults */
void execpolicy_reset(void);

#endif
