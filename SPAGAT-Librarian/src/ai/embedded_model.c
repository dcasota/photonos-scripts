#ifdef SPAGAT_EMBED_MODEL

#include "embedded_model.h"
#include "../util/journal.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <linux/memfd.h>
#include <sys/syscall.h>

extern const unsigned char _binary_model_gguf_start[];
extern const unsigned char _binary_model_gguf_end[];

bool embedded_model_available(void) {
    return embedded_model_size() > 0;
}

size_t embedded_model_size(void) {
    return (size_t)(_binary_model_gguf_end - _binary_model_gguf_start);
}

static int my_memfd_create(const char *name, unsigned int flags) {
    return (int)syscall(SYS_memfd_create, name, flags);
}

int embedded_model_create_fd(char *path_buf, int path_buf_size) {
    if (!path_buf || path_buf_size < 32) return -1;

    size_t model_sz = embedded_model_size();
    if (model_sz == 0) {
        journal_log(JOURNAL_ERROR, "ai: embedded model: no data");
        return -1;
    }

    int fd = my_memfd_create("spagat-model", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (fd < 0) {
        fd = my_memfd_create("spagat-model", 0);
        if (fd < 0) {
            journal_log(JOURNAL_ERROR, "ai: embedded model: memfd_create failed");
            return -1;
        }
    }

    const unsigned char *src = _binary_model_gguf_start;
    size_t remaining = model_sz;

    while (remaining > 0) {
        ssize_t written = write(fd, src, remaining);
        if (written < 0) {
            journal_log(JOURNAL_ERROR, "ai: embedded model: write failed");
            close(fd);
            return -1;
        }
        src += written;
        remaining -= (size_t)written;
    }

    if (lseek(fd, 0, SEEK_SET) != 0) {
        journal_log(JOURNAL_ERROR, "ai: embedded model: lseek failed");
        close(fd);
        return -1;
    }

    snprintf(path_buf, path_buf_size, "/proc/self/fd/%d", fd);

    journal_log(JOURNAL_INFO, "ai: embedded model: %.1f MB loaded via memfd",
                (double)model_sz / (1024.0 * 1024.0));

    return fd;
}

#else /* !SPAGAT_EMBED_MODEL */

typedef int embedded_model_unused_t;

#endif /* SPAGAT_EMBED_MODEL */
