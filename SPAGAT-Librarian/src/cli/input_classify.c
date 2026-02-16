#include "input_classify.h"
#include <string.h>
#include <strings.h>
#include <stddef.h>

static const char *known_commands[] = {
    "tdnf", "systemctl", "journalctl", "dmesg", "ip", "ss",
    "iptables", "df", "free", "top", "ps", "lsblk", "mount",
    "fdisk", "docker", "crictl", "networkctl", "hostnamectl",
    "timedatectl", "useradd", "chmod", "chown", "find", "grep",
    "awk", "sed", "tar", "curl", "git", "ls", "cd", "cat",
    "head", "tail", "wc", "sort", "uniq", "mkdir", "rm", "cp",
    "mv", "touch", "echo", "pwd", "whoami", "uname", "uptime",
    "date", "which", "file", "stat", "du", "kill", "pkill",
    "rpm", "vi", "nano", "diff", "patch", "ssh", "scp",
    "ping", "traceroute", "dig", "nslookup", "ifconfig",
    NULL
};

static const char *question_words[] = {
    "what", "why", "how", "when", "where", "who", "which",
    "explain", "describe", "summarize", "analyze", "compare",
    "tell", "show me how", "help", "can you", "could you",
    "please", "is there", "are there", "do i", "does",
    NULL
};

InputMode classify_input(const char *input) {
    if (!input || !input[0]) return INPUT_LLM;

    char first[128];
    int i = 0;
    while (input[i] && input[i] != ' ' && input[i] != '\t' &&
           i < (int)sizeof(first) - 1) {
        first[i] = input[i];
        i++;
    }
    first[i] = '\0';

    /* Path-like command: starts with /, ./, or ~/ */
    if (first[0] == '/' || (first[0] == '.' && first[1] == '/') ||
        (first[0] == '~' && first[1] == '/'))
        return INPUT_SHELL;

    /* Check for question words at start (case-insensitive) */
    for (int q = 0; question_words[q]; q++) {
        size_t qlen = strlen(question_words[q]);
        if (strlen(input) >= qlen &&
            strncasecmp(input, question_words[q], qlen) == 0 &&
            (input[qlen] == '\0' || input[qlen] == ' ' ||
             input[qlen] == '?'))
            return INPUT_LLM;
    }

    /* Ends with ? -- likely a question */
    size_t len = strlen(input);
    if (len > 0 && input[len - 1] == '?') return INPUT_LLM;

    /* Check if first word is a known command */
    for (int k = 0; known_commands[k]; k++) {
        if (strcasecmp(first, known_commands[k]) == 0)
            return INPUT_SHELL;
    }

    /* Contains shell operators: pipes, redirects, semicolons, && */
    if (strchr(input, '|') || strchr(input, '>') ||
        strchr(input, ';') || strstr(input, "&&"))
        return INPUT_SHELL;

    /* Starts with sudo */
    if (strncmp(input, "sudo ", 5) == 0) return INPUT_SHELL;

    return INPUT_LLM;
}
