/*
 * linux_sandbox.c - Landlock LSM + Seccomp-BPF sandboxing for shell children.
 *
 * Applies filesystem and syscall restrictions to forked child processes
 * before they exec() into a shell.  Uses raw syscalls so that Photon OS
 * builds work even without glibc wrapper functions.
 */

#ifdef __linux__

#include "linux_sandbox.h"

#include <errno.h>
#include <fcntl.h>

/* O_PATH is Linux-specific; not exposed by _POSIX_C_SOURCE alone */
#ifndef O_PATH
#define O_PATH 010000000
#endif
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <linux/types.h>
#include <sys/prctl.h>
#include <sys/syscall.h>

/* Landlock --------------------------------------------------------------- */

#ifndef LANDLOCK_CREATE_RULESET_VERSION
#define LANDLOCK_CREATE_RULESET_VERSION (1U << 0)
#endif

#ifndef LANDLOCK_ACCESS_FS_EXECUTE
#define LANDLOCK_ACCESS_FS_EXECUTE      (1ULL << 0)
#define LANDLOCK_ACCESS_FS_WRITE_FILE   (1ULL << 1)
#define LANDLOCK_ACCESS_FS_READ_FILE    (1ULL << 2)
#define LANDLOCK_ACCESS_FS_READ_DIR     (1ULL << 3)
#define LANDLOCK_ACCESS_FS_REMOVE_DIR   (1ULL << 4)
#define LANDLOCK_ACCESS_FS_REMOVE_FILE  (1ULL << 5)
#define LANDLOCK_ACCESS_FS_MAKE_CHAR    (1ULL << 6)
#define LANDLOCK_ACCESS_FS_MAKE_DIR     (1ULL << 7)
#define LANDLOCK_ACCESS_FS_MAKE_REG     (1ULL << 8)
#define LANDLOCK_ACCESS_FS_MAKE_SOCK    (1ULL << 9)
#define LANDLOCK_ACCESS_FS_MAKE_FIFO    (1ULL << 10)
#define LANDLOCK_ACCESS_FS_MAKE_BLOCK   (1ULL << 11)
#define LANDLOCK_ACCESS_FS_MAKE_SYM     (1ULL << 12)
#define LANDLOCK_ACCESS_FS_TRUNCATE     (1ULL << 13)
#endif

#ifndef LANDLOCK_RULE_PATH_BENEATH
#define LANDLOCK_RULE_PATH_BENEATH 1
#endif

/* All access bits we care about (ABI v1-v3) */
#define LL_ALL_ACCESS ( \
    LANDLOCK_ACCESS_FS_EXECUTE     | LANDLOCK_ACCESS_FS_WRITE_FILE  | \
    LANDLOCK_ACCESS_FS_READ_FILE   | LANDLOCK_ACCESS_FS_READ_DIR   | \
    LANDLOCK_ACCESS_FS_REMOVE_DIR  | LANDLOCK_ACCESS_FS_REMOVE_FILE| \
    LANDLOCK_ACCESS_FS_MAKE_CHAR   | LANDLOCK_ACCESS_FS_MAKE_DIR   | \
    LANDLOCK_ACCESS_FS_MAKE_REG    | LANDLOCK_ACCESS_FS_MAKE_SOCK  | \
    LANDLOCK_ACCESS_FS_MAKE_FIFO   | LANDLOCK_ACCESS_FS_MAKE_BLOCK | \
    LANDLOCK_ACCESS_FS_MAKE_SYM    | LANDLOCK_ACCESS_FS_TRUNCATE )

/* Read-only: everything except write/truncate/remove/make */
#define LL_READONLY_ACCESS ( \
    LANDLOCK_ACCESS_FS_EXECUTE   | LANDLOCK_ACCESS_FS_READ_FILE | \
    LANDLOCK_ACCESS_FS_READ_DIR )

struct landlock_ruleset_attr {
    __u64 handled_access_fs;
};

struct landlock_path_beneath_attr {
    __u64 allowed_access;
    __s32 parent_fd;
} __attribute__((packed));

static inline int ll_create_ruleset(struct landlock_ruleset_attr *attr,
                                    size_t size, __u32 flags) {
    return (int)syscall(__NR_landlock_create_ruleset, attr, size, flags);
}

static inline int ll_add_rule(int fd, int rule_type, const void *attr,
                              __u32 flags) {
    return (int)syscall(__NR_landlock_add_rule, fd, rule_type, attr, flags);
}

static inline int ll_restrict_self(int fd, __u32 flags) {
    return (int)syscall(__NR_landlock_restrict_self, fd, flags);
}

static int landlock_abi_version(void) {
    int v = ll_create_ruleset(NULL, 0, LANDLOCK_CREATE_RULESET_VERSION);
    return v;
}

static bool add_path_rule(int ruleset_fd, const char *path,
                          __u64 allowed_access) {
    int fd = open(path, O_PATH | O_CLOEXEC);
    if (fd < 0) return false;

    struct landlock_path_beneath_attr attr = {
        .allowed_access = allowed_access,
        .parent_fd      = fd,
    };
    int rc = ll_add_rule(ruleset_fd, LANDLOCK_RULE_PATH_BENEATH, &attr, 0);
    close(fd);
    return rc == 0;
}

bool sandbox_landlock_available(void) {
    return landlock_abi_version() >= 1;
}

bool sandbox_apply_landlock(const char **write_paths) {
    if (landlock_abi_version() < 1) {
        fprintf(stderr, "sandbox: landlock not supported\n");
        return false;
    }

    struct landlock_ruleset_attr rs_attr = {
        .handled_access_fs = LL_ALL_ACCESS,
    };
    int ruleset_fd = ll_create_ruleset(&rs_attr, sizeof(rs_attr), 0);
    if (ruleset_fd < 0) {
        fprintf(stderr, "sandbox: landlock_create_ruleset: %s\n",
                strerror(errno));
        return false;
    }

    /* Read-only access for the whole filesystem */
    if (!add_path_rule(ruleset_fd, "/", LL_READONLY_ACCESS)) {
        fprintf(stderr, "sandbox: landlock rule for / failed: %s\n",
                strerror(errno));
        close(ruleset_fd);
        return false;
    }

    /* Write access only for explicitly listed paths */
    if (write_paths) {
        for (int i = 0; write_paths[i]; i++) {
            if (!add_path_rule(ruleset_fd, write_paths[i], LL_ALL_ACCESS)) {
                fprintf(stderr, "sandbox: landlock rule for '%s': %s\n",
                        write_paths[i], strerror(errno));
                /* Non-fatal: path may not exist yet */
            }
        }
    }

    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)) {
        fprintf(stderr, "sandbox: PR_SET_NO_NEW_PRIVS: %s\n",
                strerror(errno));
        close(ruleset_fd);
        return false;
    }

    if (ll_restrict_self(ruleset_fd, 0)) {
        fprintf(stderr, "sandbox: landlock_restrict_self: %s\n",
                strerror(errno));
        close(ruleset_fd);
        return false;
    }

    close(ruleset_fd);
    return true;
}

/* Seccomp ---------------------------------------------------------------- */

#include <linux/seccomp.h>
#include <linux/filter.h>
#include <linux/audit.h>

#if defined(__x86_64__)
#define SECCOMP_AUDIT_ARCH AUDIT_ARCH_X86_64
#elif defined(__aarch64__)
#define SECCOMP_AUDIT_ARCH AUDIT_ARCH_AARCH64
#else
#define SECCOMP_AUDIT_ARCH 0
#endif

/* Offset of nr field in seccomp_data for BPF_ABS load */
#define SECCOMP_NR_OFFSET  offsetof(struct seccomp_data, nr)

bool sandbox_seccomp_available(void) {
    return prctl(PR_GET_SECCOMP) != -1;
}

bool sandbox_apply_seccomp(void) {
    /* Syscalls to block */
    static const int blocked[] = {
        __NR_ptrace,
        __NR_mount,
        __NR_umount2,
        __NR_reboot,
        __NR_sethostname,
        __NR_setdomainname,
        __NR_init_module,
        __NR_delete_module,
        __NR_kexec_load,
        __NR_pivot_root,
        __NR_swapon,
        __NR_swapoff,
    };
    static const int nblocked = sizeof(blocked) / sizeof(blocked[0]);

    /*
     * BPF program layout:
     *   [0]  LD  seccomp_data.nr
     *   [1..N*2]  JEQ blocked[i] -> RET ERRNO(EPERM)   (2 insns each)
     *   [last]    RET ALLOW
     *
     * Total instructions: 1 + nblocked*2 + 1
     */
    int total = 1 + nblocked * 2 + 1;
    struct sock_filter filt[64];  /* 64 > 1+12*2+1 = 26 */
    if (total > (int)(sizeof(filt) / sizeof(filt[0]))) {
        fprintf(stderr, "sandbox: seccomp filter too large\n");
        return false;
    }

    int idx = 0;

    /* Load syscall number */
    filt[idx++] = (struct sock_filter)
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, SECCOMP_NR_OFFSET);

    /* For each blocked syscall: compare + conditional return */
    for (int i = 0; i < nblocked; i++) {
        /* JEQ blocked[i] -> skip 0 (true: next insn), skip 1 (false: after) */
        filt[idx++] = (struct sock_filter)
            BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, (unsigned)blocked[i], 0, 1);
        filt[idx++] = (struct sock_filter)
            BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EPERM & SECCOMP_RET_DATA));
    }

    /* Default: allow */
    filt[idx++] = (struct sock_filter)
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW);

    struct sock_fprog prog = {
        .len    = (unsigned short)idx,
        .filter = filt,
    };

    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)) {
        fprintf(stderr, "sandbox: PR_SET_NO_NEW_PRIVS: %s\n",
                strerror(errno));
        return false;
    }

    if (prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog)) {
        fprintf(stderr, "sandbox: seccomp filter install: %s\n",
                strerror(errno));
        return false;
    }

    return true;
}

/* Combined --------------------------------------------------------------- */

bool sandbox_apply_shell_restrictions(const char **write_paths) {
    bool ok = true;

    if (sandbox_landlock_available()) {
        if (!sandbox_apply_landlock(write_paths)) ok = false;
    }

    if (sandbox_seccomp_available()) {
        if (!sandbox_apply_seccomp()) ok = false;
    }

    return ok;
}

#else /* !__linux__ */

#include "linux_sandbox.h"
#include <stdbool.h>

bool sandbox_landlock_available(void)                   { return false; }
bool sandbox_seccomp_available(void)                    { return false; }
bool sandbox_apply_landlock(const char **write_paths)   { (void)write_paths; return false; }
bool sandbox_apply_seccomp(void)                        { return false; }
bool sandbox_apply_shell_restrictions(const char **wp)  { (void)wp; return false; }

#endif /* __linux__ */
