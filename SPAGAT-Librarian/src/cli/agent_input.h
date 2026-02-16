#ifndef AGENT_INPUT_H
#define AGENT_INPUT_H

#include <stdbool.h>

#define CTRL_L 0x0C

typedef enum {
    AINPUT_LINE,
    AINPUT_EOF,
    AINPUT_CTRL_L
} AgentInputResult;

/* Read a line from stdin with raw terminal handling.
 * Returns AINPUT_LINE on normal input, AINPUT_CTRL_L on Ctrl-L,
 * AINPUT_EOF on EOF/error. buf is null-terminated on AINPUT_LINE. */
AgentInputResult agent_read_line(const char *prompt, char *buf, int buf_size);

/* Show autonomy level picker.  Returns true if level was changed. */
bool agent_show_autonomy_picker(void);

#endif
