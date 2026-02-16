#include "agent_input.h"
#include "../ai/autonomy.h"
#include "../util/journal.h"
#include <stdio.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

extern AutonomyConfig *active_autonomy;

static struct termios orig_termios;
static bool raw_mode = false;

static void enable_raw(void) {
    if (raw_mode) return;
    if (tcgetattr(STDIN_FILENO, &orig_termios) == -1) return;
    struct termios raw = orig_termios;
    raw.c_lflag &= ~(ICANON | ECHO);
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;
    if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0)
        raw_mode = true;
}

static void disable_raw(void) {
    if (!raw_mode) return;
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig_termios);
    raw_mode = false;
}

AgentInputResult agent_read_line(const char *prompt, char *buf, int buf_size) {
    if (buf_size < 2) return AINPUT_EOF;

    printf("%s", prompt);
    fflush(stdout);

    enable_raw();

    int pos = 0;
    while (pos < buf_size - 1) {
        char c;
        ssize_t n = read(STDIN_FILENO, &c, 1);
        if (n <= 0) {
            disable_raw();
            buf[pos] = '\0';
            return AINPUT_EOF;
        }

        if (c == CTRL_L) {
            disable_raw();
            printf("\n");
            buf[pos] = '\0';
            return AINPUT_CTRL_L;
        }

        if (c == '\n' || c == '\r') {
            disable_raw();
            write(STDOUT_FILENO, "\n", 1);
            buf[pos] = '\0';
            return AINPUT_LINE;
        }

        /* Backspace / DEL */
        if (c == 127 || c == '\b') {
            if (pos > 0) {
                pos--;
                write(STDOUT_FILENO, "\b \b", 3);
            }
            continue;
        }

        /* Ctrl-C: abort current line */
        if (c == 3) {
            disable_raw();
            printf("\n");
            buf[0] = '\0';
            return AINPUT_LINE;
        }

        /* Ctrl-D on empty line: EOF */
        if (c == 4 && pos == 0) {
            disable_raw();
            printf("\n");
            buf[0] = '\0';
            return AINPUT_EOF;
        }

        /* Skip other control chars except tab */
        if (c < 32 && c != '\t') continue;

        buf[pos++] = c;
        write(STDOUT_FILENO, &c, 1);
    }

    disable_raw();
    buf[pos] = '\0';
    return AINPUT_LINE;
}

static const char *level_names[] = {
    "none", "observe", "workspace", "home", "full"
};
static const char *level_descs[] = {
    "No tools allowed",
    "Read-only tools, allowlisted shell commands",
    "Read/write in project dir, most shell commands",
    "Read/write in home dir, all safe shell commands",
    "Full access, all commands (dangerous)"
};

bool agent_show_autonomy_picker(void) {
    if (!active_autonomy) {
        printf("  Autonomy not initialized.\n");
        return false;
    }

    AutonomyLevel current = active_autonomy->level;

    printf("\n  ┌─ Autonomy Level ─────────────────────────────┐\n");
    for (int i = 0; i <= 4; i++) {
        const char *marker = (i == (int)current) ? ">" : " ";
        printf("  │ %s %d. %-10s  %-33s│\n",
               marker, i, level_names[i], level_descs[i]);
    }
    printf("  ├─────────────────────────────────────────────────┤\n");
    printf("  │ Current: %-10s  Press 0-4 or Esc to cancel │\n",
           level_names[(int)current]);
    printf("  └─────────────────────────────────────────────────┘\n");
    fflush(stdout);

    enable_raw();
    char c;
    ssize_t n = read(STDIN_FILENO, &c, 1);
    disable_raw();

    if (n <= 0 || c == 27) {
        printf("  Cancelled.\n\n");
        return false;
    }

    if (c >= '0' && c <= '4') {
        AutonomyLevel new_level = (AutonomyLevel)(c - '0');
        if (new_level == current) {
            printf("  Already at '%s'.\n\n", level_names[(int)current]);
            return false;
        }
        active_autonomy->level = new_level;
        journal_log(JOURNAL_INFO,
                    "SESSION autonomy changed: %s -> %s",
                    level_names[(int)current],
                    level_names[(int)new_level]);
        printf("  Autonomy: %s -> %s (session only)\n\n",
               level_names[(int)current],
               level_names[(int)new_level]);
        return true;
    }

    printf("  Invalid selection. Press 0-4 or Esc.\n\n");
    return false;
}
