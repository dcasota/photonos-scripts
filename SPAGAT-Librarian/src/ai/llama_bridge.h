/*
 * llama_bridge.h - Thin C-linkage wrapper around llama.cpp
 *
 * This bridge eliminates all struct-by-value ABI issues when calling
 * llama.cpp from pure C via dlopen.  The C++ bridge implementation
 * includes llama.h directly and uses proper types, then exposes a
 * simple pointer-and-scalar-only C API.
 */
#ifndef LLAMA_BRIDGE_H
#define LLAMA_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque handles */
typedef struct llama_model   lb_model;
typedef struct llama_context lb_context;
typedef struct llama_vocab   lb_vocab;
typedef struct llama_sampler lb_sampler;

typedef int32_t lb_token;

/* Chat message for template formatting */
typedef struct {
    const char *role;
    const char *content;
} lb_chat_message;

/* Log levels matching ggml_log_level */
enum lb_log_level {
    LB_LOG_NONE  = 0,
    LB_LOG_DEBUG = 1,
    LB_LOG_INFO  = 2,
    LB_LOG_WARN  = 3,
    LB_LOG_ERROR = 4
};

/* Log callback type: receives level, text, and user_data */
typedef void (*lb_log_callback)(enum lb_log_level level, const char *text,
                                void *user_data);

/* Set log callback to redirect all llama.cpp output.
 * Must be called BEFORE lb_backend_init. */
void lb_log_set(lb_log_callback callback, void *user_data);

/* Initialize/shutdown llama backend */
int  lb_backend_init(void);
void lb_backend_free(void);

/* Load model with n_gpu_layers; returns NULL on failure */
lb_model *lb_model_load(const char *path, int32_t n_gpu_layers);
void      lb_model_free(lb_model *m);

/* Create context with n_ctx; returns NULL on failure */
lb_context *lb_context_create(lb_model *m, uint32_t n_ctx);
void        lb_context_free(lb_context *c);

/* Vocab */
const lb_vocab *lb_model_get_vocab(const lb_model *m);
lb_token        lb_vocab_bos(const lb_vocab *v);
lb_token        lb_vocab_eos(const lb_vocab *v);

/* Model info */
int32_t     lb_model_n_ctx_train(const lb_model *m);
const char *lb_model_chat_template(const lb_model *m);
int32_t     lb_model_desc(const lb_model *m, char *buf, int32_t buf_size);

/* Chat template formatting */
int32_t lb_chat_apply_template(const char *tmpl,
                               const lb_chat_message *msgs, size_t n_msgs,
                               int add_ass, char *buf, int32_t buf_size);

/* Same but auto-detects template from model metadata (tmpl may be NULL) */
int32_t lb_chat_apply_template_model(const lb_model *m, const char *tmpl,
                                     const lb_chat_message *msgs, size_t n_msgs,
                                     int add_ass, char *buf, int32_t buf_size);

/* Tokenize text; returns number of tokens or negative on error */
int32_t lb_tokenize(const lb_vocab *v, const char *text, int32_t text_len,
                    lb_token *tokens, int32_t n_tokens_max,
                    int add_special, int parse_special);

/* Convert token to text piece; returns length */
int32_t lb_token_to_piece(const lb_vocab *v, lb_token token,
                          char *buf, int32_t buf_size,
                          int32_t lstrip, int special);

/* Clear the KV cache (must be called between independent generations) */
void lb_kv_cache_clear(lb_context *c);

/* Decode a batch of tokens (prompt or single); returns 0 on success */
int32_t lb_decode_tokens(lb_context *c, lb_token *tokens, int32_t n_tokens);

/* Create sampler chain with top_k, top_p, temperature, and seed */
lb_sampler *lb_sampler_create(int32_t top_k, float top_p,
                              float temperature, uint32_t seed);
void        lb_sampler_free(lb_sampler *s);

/* Sample next token */
lb_token lb_sampler_sample(lb_sampler *s, lb_context *c, int32_t idx);

#ifdef __cplusplus
}
#endif

#endif /* LLAMA_BRIDGE_H */
