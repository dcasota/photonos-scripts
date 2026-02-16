#include "execpolicy.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define MAX_PREFIXES_PER_RULE 16
#define MAX_PREFIX_LEN        64
#define MAX_JUSTIFICATION_LEN 128
#define MAX_RULES             128

typedef struct {
    char           prefixes[MAX_PREFIXES_PER_RULE][MAX_PREFIX_LEN];
    int            prefix_count;
    PolicyDecision decision;
    char           justification[MAX_JUSTIFICATION_LEN];
} PolicyRule;

static PolicyRule  rules[MAX_RULES];
static int         rule_count;
static bool        initialized;

/* ------------------------------------------------------------------ */
/*  Helpers                                                           */
/* ------------------------------------------------------------------ */

static void trim_whitespace(char *s)
{
    char *end;
    while (*s && isspace((unsigned char)*s))
        memmove(s, s + 1, strlen(s));
    end = s + strlen(s) - 1;
    while (end > s && isspace((unsigned char)*end))
        *end-- = '\0';
}

static void add_rule(const char *prefixes[], int n,
                     PolicyDecision decision, const char *justification)
{
    PolicyRule *r;
    int i;

    if (rule_count >= MAX_RULES)
        return;

    r = &rules[rule_count++];
    r->decision = decision;
    r->prefix_count = 0;
    snprintf(r->justification, sizeof(r->justification), "%s", justification);

    for (i = 0; i < n && i < MAX_PREFIXES_PER_RULE; i++) {
        snprintf(r->prefixes[r->prefix_count], MAX_PREFIX_LEN, "%s", prefixes[i]);
        r->prefix_count++;
    }
}

/* ------------------------------------------------------------------ */
/*  Default rule tables                                               */
/* ------------------------------------------------------------------ */

static void load_defaults(void)
{
    /* ---------- FORBIDDEN ---------- */
    {
        const char *p[] = { "rm -rf /", "rm -rf /*", "rm -r /" };
        add_rule(p, 3, POLICY_FORBIDDEN, "Recursive deletion of root");
    }
    {
        const char *p[] = { "mkfs" };
        add_rule(p, 1, POLICY_FORBIDDEN, "Filesystem formatting");
    }
    {
        const char *p[] = { "dd if=/dev/zero", "dd if=/dev/urandom" };
        add_rule(p, 2, POLICY_FORBIDDEN, "Raw device write");
    }
    {
        const char *p[] = { "> /dev/sd", "> /dev/nvme" };
        add_rule(p, 2, POLICY_FORBIDDEN, "Direct device write");
    }
    {
        const char *p[] = { ":(){ :" };
        add_rule(p, 1, POLICY_FORBIDDEN, "Fork bomb");
    }
    {
        const char *p[] = { "chmod -R 777 /" };
        add_rule(p, 1, POLICY_FORBIDDEN, "Recursive world-writable root");
    }
    {
        const char *p[] = { "shutdown", "reboot", "poweroff", "halt" };
        add_rule(p, 4, POLICY_FORBIDDEN, "System power control");
    }
    {
        const char *p[] = { "init 0", "init 6" };
        add_rule(p, 2, POLICY_FORBIDDEN, "System runlevel change");
    }

    /* ---------- PROMPT ---------- */
    {
        const char *p[] = { "systemctl restart", "systemctl stop",
                            "systemctl enable",  "systemctl disable" };
        add_rule(p, 4, POLICY_PROMPT, "Service state change");
    }
    {
        const char *p[] = { "iptables", "ip6tables", "nft" };
        add_rule(p, 3, POLICY_PROMPT, "Firewall modification");
    }
    {
        const char *p[] = { "useradd", "userdel", "usermod",
                            "groupadd", "groupdel" };
        add_rule(p, 5, POLICY_PROMPT, "User/group management");
    }
    {
        const char *p[] = { "mount", "umount" };
        add_rule(p, 2, POLICY_PROMPT, "Filesystem mount/unmount");
    }
    {
        const char *p[] = { "fdisk", "parted", "lvm" };
        add_rule(p, 3, POLICY_PROMPT, "Partition management");
    }
    {
        const char *p[] = { "tdnf install", "tdnf remove", "tdnf erase" };
        add_rule(p, 3, POLICY_PROMPT, "Package installation/removal");
    }
    {
        const char *p[] = { "rpm -i", "rpm -e", "rpm -U" };
        add_rule(p, 3, POLICY_PROMPT, "RPM package management");
    }

    /* ---------- ALLOW ---------- */
    {
        const char *p[] = { "ls", "cat", "head", "tail", "wc",
                            "file", "stat", "find", "grep", "awk", "sed" };
        add_rule(p, 11, POLICY_ALLOW, "Read-only inspection");
    }
    {
        const char *p[] = { "ps", "top", "df", "du", "free",
                            "uptime", "uname", "hostname", "id", "whoami" };
        add_rule(p, 10, POLICY_ALLOW, "System info");
    }
    {
        const char *p[] = { "echo", "printf", "date", "cal",
                            "env", "printenv" };
        add_rule(p, 6, POLICY_ALLOW, "Safe output");
    }
    {
        const char *p[] = { "git status", "git log", "git diff",
                            "git branch", "git show" };
        add_rule(p, 5, POLICY_ALLOW, "Git read-only");
    }
    {
        const char *p[] = { "systemctl status" };
        add_rule(p, 1, POLICY_ALLOW, "Service status");
    }
    {
        const char *p[] = { "journalctl", "dmesg" };
        add_rule(p, 2, POLICY_ALLOW, "Log reading");
    }
    {
        const char *p[] = { "tdnf list", "tdnf info",
                            "tdnf search", "tdnf check-update" };
        add_rule(p, 4, POLICY_ALLOW, "Package query");
    }
    {
        const char *p[] = { "rpm -qa", "rpm -qi", "rpm -ql" };
        add_rule(p, 3, POLICY_ALLOW, "RPM query");
    }
}

/* ------------------------------------------------------------------ */
/*  Public API                                                        */
/* ------------------------------------------------------------------ */

void execpolicy_init(void)
{
    if (initialized)
        return;
    rule_count = 0;
    load_defaults();
    initialized = true;
}

void execpolicy_reset(void)
{
    rule_count  = 0;
    initialized = false;
    execpolicy_init();
}

PolicyResult execpolicy_evaluate(const char *command)
{
    PolicyResult result;
    const char  *cmd;
    int          best_len;
    int          i, j;

    result.decision = POLICY_PROMPT;          /* default-deny */
    snprintf(result.justification, sizeof(result.justification),
             "Unknown command – requires approval");

    if (!command)
        return result;

    /* skip leading whitespace */
    cmd = command;
    while (*cmd && isspace((unsigned char)*cmd))
        cmd++;

    if (*cmd == '\0')
        return result;

    if (!initialized)
        execpolicy_init();

    /*
     * Walk every rule.  For each matching prefix keep the longest
     * match, but let stricter decisions (FORBIDDEN > PROMPT > ALLOW)
     * win when prefix lengths are equal.
     */
    best_len = -1;

    for (i = 0; i < rule_count; i++) {
        for (j = 0; j < rules[i].prefix_count; j++) {
            int plen = (int)strlen(rules[i].prefixes[j]);

            if (strncmp(cmd, rules[i].prefixes[j], (size_t)plen) != 0)
                continue;

            /*
             * For single-word prefixes (no space inside), the next
             * char in cmd must be space, NUL or a shell metachar so
             * that "cat" doesn't match "catalog".
             */
            if (!strchr(rules[i].prefixes[j], ' ')) {
                char next = cmd[plen];
                if (next != '\0' && !isspace((unsigned char)next) &&
                    next != '|' && next != '&' && next != ';' &&
                    next != '>' && next != '<' && next != '(')
                    continue;
            }

            if (plen > best_len ||
                (plen == best_len &&
                 rules[i].decision > result.decision)) {
                best_len = plen;
                result.decision = rules[i].decision;
                snprintf(result.justification,
                         sizeof(result.justification), "%s",
                         rules[i].justification);
            }
        }
    }

    return result;
}

bool execpolicy_load_rules(const char *path)
{
    FILE *fp;
    char  line[1024];

    if (!path)
        return false;

    if (!initialized)
        execpolicy_init();

    fp = fopen(path, "r");
    if (!fp)
        return false;

    while (fgets(line, (int)sizeof(line), fp)) {
        PolicyDecision decision;
        const char    *prefixes[MAX_PREFIXES_PER_RULE];
        int            n_prefixes = 0;
        char          *colon;
        char          *tok;
        char          *rest;

        trim_whitespace(line);

        if (line[0] == '\0' || line[0] == '#')
            continue;

        colon = strchr(line, ':');
        if (!colon)
            continue;
        *colon = '\0';

        trim_whitespace(line);

        if (strcmp(line, "allow") == 0)
            decision = POLICY_ALLOW;
        else if (strcmp(line, "prompt") == 0)
            decision = POLICY_PROMPT;
        else if (strcmp(line, "forbidden") == 0)
            decision = POLICY_FORBIDDEN;
        else
            continue;

        rest = colon + 1;
        trim_whitespace(rest);

        tok = strtok(rest, " \t");
        while (tok && n_prefixes < MAX_PREFIXES_PER_RULE) {
            prefixes[n_prefixes++] = tok;
            tok = strtok(NULL, " \t");
        }

        if (n_prefixes > 0) {
            char justification[MAX_JUSTIFICATION_LEN];
            snprintf(justification, sizeof(justification),
                     "User-defined %s rule",
                     decision == POLICY_ALLOW     ? "allow" :
                     decision == POLICY_PROMPT    ? "prompt" :
                                                    "forbidden");
            add_rule(prefixes, n_prefixes, decision, justification);
        }
    }

    fclose(fp);
    return true;
}
