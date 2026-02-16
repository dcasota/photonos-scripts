#ifndef EMBEDDED_MODEL_H
#define EMBEDDED_MODEL_H

#include <stdbool.h>
#include <stddef.h>

/*
 * Embedded model support via objcopy ELF sections.
 *
 * At build time, objcopy converts a .gguf model file into an object file
 * with these linker symbols:
 *   _binary_model_gguf_start  - start of embedded data
 *   _binary_model_gguf_end    - end of embedded data
 *
 * At runtime, memfd_create() exposes the data as a file descriptor
 * accessible via /proc/self/fd/N, which llama.cpp can open as a path.
 */

#ifdef SPAGAT_EMBED_MODEL

extern const unsigned char _binary_model_gguf_start[];
extern const unsigned char _binary_model_gguf_end[];

bool embedded_model_available(void);
size_t embedded_model_size(void);

/*
 * Create a memfd from the embedded model data and return its
 * /proc/self/fd/N path. The path is written to buf.
 * Returns the file descriptor (>= 0) on success, -1 on failure.
 * Caller must close() the fd when done.
 */
int embedded_model_create_fd(char *path_buf, int path_buf_size);

#else /* !SPAGAT_EMBED_MODEL */

static inline bool embedded_model_available(void) { return false; }
static inline size_t embedded_model_size(void) { return 0; }
static inline int embedded_model_create_fd(char *b, int s) {
    (void)b; (void)s; return -1;
}

#endif /* SPAGAT_EMBED_MODEL */

#endif /* EMBEDDED_MODEL_H */
