#include "ai.h"
#include "../util/util.h"
#include "../util/journal.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <time.h>
#include <dirent.h>
#include <pwd.h>
#include <sys/utsname.h>
#include <sys/statvfs.h>
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <netinet/in.h>

/* --- helpers --- */

static void human_size(unsigned long bytes, char *buf, int buf_size) {
    if (bytes >= 1073741824UL)
        snprintf(buf, buf_size, "%.1f GiB", (double)bytes / 1073741824.0);
    else if (bytes >= 1048576UL)
        snprintf(buf, buf_size, "%.1f MiB", (double)bytes / 1048576.0);
    else if (bytes >= 1024UL)
        snprintf(buf, buf_size, "%.1f KiB", (double)bytes / 1024.0);
    else
        snprintf(buf, buf_size, "%lu B", bytes);
}

static int read_proc_file(const char *path, char *buf, int buf_size) {
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    int n = (int)fread(buf, 1, buf_size - 1, f);
    if (n < 0) n = 0;
    buf[n] = '\0';
    fclose(f);
    return n;
}

static bool parse_meminfo_field(const char *meminfo, const char *field,
                                unsigned long *out_kb) {
    const char *p = strstr(meminfo, field);
    if (!p) return false;
    p += strlen(field);
    while (*p && (*p == ' ' || *p == ':' || *p == '\t')) p++;
    *out_kb = strtoul(p, NULL, 10);
    return true;
}

/* --- category gatherers --- */

static int gather_os(char *buf, int sz) {
    struct utsname u;
    char name[64] = "Linux", ver[32] = "";

    char osr[2048];
    if (read_proc_file("/etc/os-release", osr, sizeof(osr)) > 0) {
        char *p = strstr(osr, "NAME=");
        if (p) {
            p += 5;
            if (*p == '"') p++;
            char *e = strchr(p, '"');
            if (!e) e = strchr(p, '\n');
            if (e) {
                size_t l = (size_t)(e - p);
                if (l >= sizeof(name)) l = sizeof(name) - 1;
                memcpy(name, p, l);
                name[l] = '\0';
            }
        }
        p = strstr(osr, "VERSION_ID=");
        if (p) {
            p += 11;
            if (*p == '"') p++;
            char *e = strchr(p, '"');
            if (!e) e = strchr(p, '\n');
            if (e) {
                size_t l = (size_t)(e - p);
                if (l >= sizeof(ver)) l = sizeof(ver) - 1;
                memcpy(ver, p, l);
                ver[l] = '\0';
            }
        }
    }

    if (uname(&u) == 0) {
        return snprintf(buf, sz, "OS: %s %s (Linux %s %s)\nHost: %s",
                        name, ver, u.release, u.machine, u.nodename);
    }
    return snprintf(buf, sz, "OS: %s %s", name, ver);
}

static int gather_cpu(char *buf, int sz) {
    char info[8192];
    int n = read_proc_file("/proc/cpuinfo", info, sizeof(info));
    char model[128] = "unknown";
    int cores = 0;

    if (n > 0) {
        char *p = strstr(info, "model name");
        if (p) {
            p = strchr(p, ':');
            if (p) {
                p++;
                while (*p == ' ' || *p == '\t') p++;
                char *e = strchr(p, '\n');
                if (e) {
                    size_t l = (size_t)(e - p);
                    if (l >= sizeof(model)) l = sizeof(model) - 1;
                    memcpy(model, p, l);
                    model[l] = '\0';
                }
            }
        }
        p = info;
        while ((p = strstr(p, "processor")) != NULL) {
            if (p == info || *(p - 1) == '\n') cores++;
            p += 9;
        }
    }

    char la[128] = "";
    char lavg[64];
    if (read_proc_file("/proc/loadavg", lavg, sizeof(lavg)) > 0) {
        float l1, l5, l15;
        if (sscanf(lavg, "%f %f %f", &l1, &l5, &l15) == 3)
            snprintf(la, sizeof(la), ", load: %.2f %.2f %.2f", l1, l5, l15);
    }

    return snprintf(buf, sz, "CPU: %s (%d cores)%s", model, cores, la);
}

static int gather_ram(char *buf, int sz) {
    char mi[4096];
    if (read_proc_file("/proc/meminfo", mi, sizeof(mi)) <= 0)
        return snprintf(buf, sz, "RAM: unavailable");

    unsigned long total = 0, free_m = 0, avail = 0, swt = 0, swf = 0;
    parse_meminfo_field(mi, "MemTotal", &total);
    parse_meminfo_field(mi, "MemFree", &free_m);
    parse_meminfo_field(mi, "MemAvailable", &avail);
    parse_meminfo_field(mi, "SwapTotal", &swt);
    parse_meminfo_field(mi, "SwapFree", &swf);

    char t[32], a[32], su[32], st2[32];
    human_size(total * 1024UL, t, sizeof(t));
    human_size(avail * 1024UL, a, sizeof(a));
    unsigned long swused = (swt > swf) ? swt - swf : 0;
    human_size(swused * 1024UL, su, sizeof(su));
    human_size(swt * 1024UL, st2, sizeof(st2));

    (void)free_m;
    return snprintf(buf, sz, "RAM: %s total, %s available, %s/%s swap",
                    t, a, su, st2);
}

static int gather_storage(char *buf, int sz) {
    int pos = 0;
    pos += snprintf(buf + pos, sz - pos, "Storage:");

    struct statvfs sv;
    const char *paths[] = {"/", "/home", NULL};

    dev_t root_dev = 0;
    struct statvfs root_sv;
    if (statvfs("/", &root_sv) == 0) root_dev = root_sv.f_fsid;

    for (int i = 0; paths[i] && pos < sz - 128; i++) {
        if (statvfs(paths[i], &sv) != 0) continue;
        if (i > 0 && sv.f_fsid == root_dev) continue;

        unsigned long total = (unsigned long)sv.f_blocks * sv.f_frsize;
        unsigned long free_s = (unsigned long)sv.f_bavail * sv.f_frsize;
        unsigned long used = total - (unsigned long)sv.f_bfree * sv.f_frsize;
        int pct = total ? (int)((used * 100UL) / total) : 0;

        char ts[32], us[32], fs[32];
        human_size(total, ts, sizeof(ts));
        human_size(used, us, sizeof(us));
        human_size(free_s, fs, sizeof(fs));

        pos += snprintf(buf + pos, sz - pos,
                        "\n  %-5s %s total, %s used (%d%%), %s free",
                        paths[i], ts, us, pct, fs);
    }

    return pos;
}

static int gather_network(char *buf, int sz) {
    struct ifaddrs *ifa, *p;
    if (getifaddrs(&ifa) != 0)
        return snprintf(buf, sz, "Network: unavailable");

    int pos = snprintf(buf, sz, "Network:");
    bool first = true;

    for (p = ifa; p && pos < sz - 64; p = p->ifa_next) {
        if (!p->ifa_addr || p->ifa_addr->sa_family != AF_INET) continue;
        if (strcmp(p->ifa_name, "lo") == 0) continue;

        char ip[INET_ADDRSTRLEN];
        struct sockaddr_in *sa = (struct sockaddr_in *)p->ifa_addr;
        inet_ntop(AF_INET, &sa->sin_addr, ip, sizeof(ip));

        pos += snprintf(buf + pos, sz - pos, "%s %s (%s)",
                        first ? " " : ", ", p->ifa_name, ip);
        first = false;
    }

    freeifaddrs(ifa);
    if (first) pos += snprintf(buf + pos, sz - pos, " none");
    return pos;
}

static int gather_time(char *buf, int sz) {
    time_t now = time(NULL);
    struct tm tm;
    localtime_r(&now, &tm);

    char ts[64];
    strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S %Z", &tm);

    char up[64] = "";
    char proc[64];
    if (read_proc_file("/proc/uptime", proc, sizeof(proc)) > 0) {
        double secs;
        if (sscanf(proc, "%lf", &secs) == 1) {
            int s = (int)secs;
            int d = s / 86400; s %= 86400;
            int h = s / 3600; s %= 3600;
            int m = s / 60;
            snprintf(up, sizeof(up), ", uptime: %dd %dh %dm", d, h, m);
        }
    }

    return snprintf(buf, sz, "Time: %s%s", ts, up);
}

static int gather_user(char *buf, int sz) {
    uid_t uid = getuid();
    struct passwd *pw = getpwuid(uid);
    if (pw)
        return snprintf(buf, sz, "User: %s (uid=%d), home=%s",
                        pw->pw_name, (int)uid, pw->pw_dir);
    return snprintf(buf, sz, "User: uid=%d", (int)uid);
}

/* --- public API --- */

typedef int (*category_fn)(char *, int);

static const struct {
    const char *name;
    category_fn fn;
} categories[] = {
    {"os",      gather_os},
    {"cpu",     gather_cpu},
    {"ram",     gather_ram},
    {"storage", gather_storage},
    {"network", gather_network},
    {"time",    gather_time},
    {"user",    gather_user},
};
#define NUM_CATEGORIES (int)(sizeof(categories) / sizeof(categories[0]))

int sysinfo_snapshot(char *buf, int buf_size) {
    if (!buf || buf_size < 1) return 0;
    int pos = 0;
    for (int i = 0; i < NUM_CATEGORIES && pos < buf_size - 128; i++) {
        if (i > 0 && pos < buf_size - 2) {
            buf[pos++] = '\n';
        }
        pos += categories[i].fn(buf + pos, buf_size - pos);
    }
    return pos;
}

int sysinfo_category(const char *category, char *buf, int buf_size) {
    if (!category || !buf || buf_size < 1) return 0;
    for (int i = 0; i < NUM_CATEGORIES; i++) {
        if (str_equals_ignore_case(category, categories[i].name))
            return categories[i].fn(buf, buf_size);
    }
    return snprintf(buf, buf_size,
                    "Error: unknown category '%s'. Use: os cpu ram storage network time user",
                    category);
}

/* --- tool handlers --- */

static bool tool_system_info(const char *input, char *output, int output_size) {
    if (!input || !input[0]) {
        sysinfo_snapshot(output, output_size);
        return true;
    }
    char cat[64];
    str_safe_copy(cat, input, sizeof(cat));
    str_trim(cat);
    int n = sysinfo_category(cat, output, output_size);
    /* sysinfo_category writes "Error:" prefix on unknown category */
    if (n > 0 && strncmp(output, "Error:", 6) == 0)
        return false;
    return true;
}

static bool tool_disk_usage(const char *input, char *output, int output_size) {
    if (!input || !input[0]) {
        str_safe_copy(output, "Error: no path provided", output_size);
        return false;
    }

    char path[512];
    str_safe_copy(path, input, sizeof(path));
    str_trim(path);

    struct statvfs sv;
    if (statvfs(path, &sv) != 0) {
        snprintf(output, output_size, "Error: statvfs '%s': %s",
                 path, strerror(errno));
        return false;
    }

    unsigned long total = (unsigned long)sv.f_blocks * sv.f_frsize;
    unsigned long free_s = (unsigned long)sv.f_bavail * sv.f_frsize;
    unsigned long used = total - (unsigned long)sv.f_bfree * sv.f_frsize;
    int pct = total ? (int)((used * 100UL) / total) : 0;
    unsigned long bsize = (unsigned long)sv.f_bsize;
    unsigned long itotal = (unsigned long)sv.f_files;
    unsigned long ifree = (unsigned long)sv.f_ffree;
    unsigned long iused = itotal - ifree;

    char ts[32], us[32], fs[32];
    human_size(total, ts, sizeof(ts));
    human_size(used, us, sizeof(us));
    human_size(free_s, fs, sizeof(fs));

    snprintf(output, output_size,
             "Path: %s\n"
             "Total: %s\n"
             "Used:  %s (%d%%)\n"
             "Free:  %s\n"
             "Block: %lu\n"
             "Inodes: %lu total, %lu used, %lu free",
             path, ts, us, pct, fs, bsize, itotal, iused, ifree);
    return true;
}

typedef struct {
    int pid;
    char name[64];
    char state;
    unsigned long rss_kb;
} ProcEntry;

static int cmp_rss(const void *a, const void *b) {
    const ProcEntry *pa = a, *pb = b;
    if (pb->rss_kb > pa->rss_kb) return 1;
    if (pb->rss_kb < pa->rss_kb) return -1;
    return 0;
}

static int cmp_name(const void *a, const void *b) {
    const ProcEntry *pa = a, *pb = b;
    return strcasecmp(pa->name, pb->name);
}

static bool tool_process_list(const char *input, char *output,
                              int output_size) {
    int (*cmpfn)(const void *, const void *) = cmp_rss;

    if (input && input[0]) {
        char opt[64];
        str_safe_copy(opt, input, sizeof(opt));
        str_trim(opt);
        if (strstr(opt, "sort=name"))
            cmpfn = cmp_name;
    }

    DIR *proc = opendir("/proc");
    if (!proc) {
        snprintf(output, output_size, "Error: cannot open /proc: %s",
                 strerror(errno));
        return false;
    }

    ProcEntry *entries = NULL;
    int count = 0, cap = 0;
    struct dirent *de;

    while ((de = readdir(proc)) != NULL) {
        if (de->d_name[0] < '0' || de->d_name[0] > '9') continue;
        int pid = atoi(de->d_name);
        if (pid <= 0) continue;

        char path[128], data[2048];
        ProcEntry e;
        e.pid = pid;
        e.name[0] = '\0';
        e.state = '?';
        e.rss_kb = 0;

        snprintf(path, sizeof(path), "/proc/%d/status", pid);
        if (read_proc_file(path, data, sizeof(data)) > 0) {
            char *p = strstr(data, "Name:");
            if (p) {
                p += 5;
                while (*p == ' ' || *p == '\t') p++;
                char *e2 = strchr(p, '\n');
                if (e2) {
                    size_t l = (size_t)(e2 - p);
                    if (l >= sizeof(e.name)) l = sizeof(e.name) - 1;
                    memcpy(e.name, p, l);
                    e.name[l] = '\0';
                }
            }
            p = strstr(data, "State:");
            if (p) {
                p += 6;
                while (*p == ' ' || *p == '\t') p++;
                e.state = *p;
            }
            p = strstr(data, "VmRSS:");
            if (p) {
                p += 6;
                while (*p == ' ' || *p == '\t') p++;
                e.rss_kb = strtoul(p, NULL, 10);
            }
        }

        if (count >= cap) {
            cap = cap ? cap * 2 : 256;
            entries = realloc(entries, sizeof(ProcEntry) * cap);
        }
        entries[count++] = e;
    }
    closedir(proc);

    if (count > 0) qsort(entries, count, sizeof(ProcEntry), cmpfn);

    int pos = snprintf(output, output_size,
                       "%-7s %-20s %-6s %s\n", "PID", "NAME", "STATE", "RSS");
    int show = count < 20 ? count : 20;
    for (int i = 0; i < show && pos < output_size - 80; i++) {
        char rs[32];
        human_size(entries[i].rss_kb * 1024UL, rs, sizeof(rs));
        pos += snprintf(output + pos, output_size - pos,
                        "%-7d %-20s %-6c %s\n",
                        entries[i].pid, entries[i].name,
                        entries[i].state, rs);
    }
    if (count > 20)
        snprintf(output + pos, output_size - pos,
                 "... (%d more)", count - 20);

    free(entries);
    return true;
}

/* --- init --- */

void tools_sysinfo_init(void) {
    ai_tool_register("system_info",
        "System info. Input: empty or category (os/cpu/ram/storage/network/time/user).",
        tool_system_info);

    ai_tool_register("disk_usage",
        "Disk usage for path. Input: filesystem path.",
        tool_disk_usage);

    ai_tool_register("process_list",
        "Top processes. Input: empty or sort=mem|sort=name.",
        tool_process_list);

    char warmup[2048];
    sysinfo_snapshot(warmup, sizeof(warmup));
    journal_log(JOURNAL_INFO, "sysinfo: initialized, snapshot %d bytes",
                (int)strlen(warmup));
}
