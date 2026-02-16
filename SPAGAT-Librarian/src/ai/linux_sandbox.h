#ifndef LINUX_SANDBOX_H
#define LINUX_SANDBOX_H

#include <stdbool.h>

/* Check if Landlock is supported on this kernel */
bool sandbox_landlock_available(void);

/* Check if Seccomp is supported */
bool sandbox_seccomp_available(void);

/* Apply Landlock filesystem restrictions to the current process.
   This is meant to be called AFTER fork(), BEFORE exec() in shell children.
   write_paths: NULL-terminated array of paths allowed for writing.
   If write_paths is NULL, the process is read-only. */
bool sandbox_apply_landlock(const char **write_paths);

/* Apply Seccomp-BPF syscall filter to the current process.
   Blocks: ptrace, mount, umount2, reboot, sethostname, setdomainname,
           init_module, delete_module, kexec_load, pivot_root, swapon, swapoff.
   Must be called AFTER fork(), BEFORE exec(). */
bool sandbox_apply_seccomp(void);

/* Combined: apply both Landlock + Seccomp in shell child */
bool sandbox_apply_shell_restrictions(const char **write_paths);

#endif
