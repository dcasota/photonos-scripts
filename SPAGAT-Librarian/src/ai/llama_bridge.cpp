/*
 * llama_bridge.cpp - C++ implementation of the llama.cpp bridge
 *
 * Supports both the new llama.cpp API (ggml-org, 2025+) and the older
 * API used by BitNet's fork (Eddie-Wang1120/llama.cpp).
 *
 * Detection: the old API has llama_new_context_with_model() and uses
 * llama_model* everywhere; the new API splits vocab into llama_vocab*.
 */
#include "llama_bridge.h"
#include "llama.h"

#include <cstdio>
#include <cstring>

/* LLAMA_OLD_API is set by the Makefile (-DLLAMA_OLD_API=1) when building
 * against BitNet's older llama.cpp fork.  When not defined, assume new API. */
#ifndef LLAMA_OLD_API
  #define LLAMA_OLD_API 0
#endif

static lb_log_callback user_log_cb = nullptr;
static void           *user_log_ud = nullptr;

static void llama_log_bridge(enum ggml_log_level level, const char *text,
                             void *user_data) {
    (void)user_data;
    if (user_log_cb)
        user_log_cb(static_cast<enum lb_log_level>(level), text, user_log_ud);
}

extern "C" {

void lb_log_set(lb_log_callback callback, void *user_data) {
    user_log_cb = callback;
    user_log_ud = user_data;
    llama_log_set(llama_log_bridge, nullptr);
}

int lb_backend_init(void) {
    llama_backend_init();
    return 0;
}

void lb_backend_free(void) {
    llama_backend_free();
}

lb_model *lb_model_load(const char *path, int32_t n_gpu_layers) {
    struct llama_model_params params = llama_model_default_params();
    params.n_gpu_layers = n_gpu_layers;
#if LLAMA_OLD_API
    return llama_load_model_from_file(path, params);
#else
    return llama_model_load_from_file(path, params);
#endif
}

void lb_model_free(lb_model *m) {
#if LLAMA_OLD_API
    if (m) llama_free_model(m);
#else
    if (m) llama_model_free(m);
#endif
}

lb_context *lb_context_create(lb_model *m, uint32_t n_ctx) {
    struct llama_context_params params = llama_context_default_params();
    params.n_ctx = n_ctx;
#if LLAMA_OLD_API
    return llama_new_context_with_model(m, params);
#else
    return llama_init_from_model(m, params);
#endif
}

void lb_context_free(lb_context *c) {
    if (c) llama_free(c);
}

/* In old API there is no separate vocab type; we store the model ptr.
 * The bridge header typedefs lb_vocab = llama_vocab (opaque), but in
 * old API we cast the model pointer through it. */
const lb_vocab *lb_model_get_vocab(const lb_model *m) {
#if LLAMA_OLD_API
    /* No vocab object in old API -- return the model pointer cast.
     * lb_tokenize/lb_token_to_piece will cast it back. */
    return reinterpret_cast<const lb_vocab *>(m);
#else
    return llama_model_get_vocab(m);
#endif
}

lb_token lb_vocab_bos(const lb_vocab *v) {
#if LLAMA_OLD_API
    return llama_token_bos(reinterpret_cast<const llama_model *>(v));
#else
    return llama_vocab_bos(v);
#endif
}

lb_token lb_vocab_eos(const lb_vocab *v) {
#if LLAMA_OLD_API
    return llama_token_eos(reinterpret_cast<const llama_model *>(v));
#else
    return llama_vocab_eos(v);
#endif
}

int32_t lb_model_n_ctx_train(const lb_model *m) {
#if LLAMA_OLD_API
    return llama_n_ctx_train(m);
#else
    return llama_model_n_ctx_train(m);
#endif
}

const char *lb_model_chat_template(const lb_model *m) {
#if LLAMA_OLD_API
    (void)m;
    return NULL;
#else
    return llama_model_chat_template(m, NULL);
#endif
}

int32_t lb_model_desc(const lb_model *m, char *buf, int32_t buf_size) {
    return llama_model_desc(m, buf, buf_size);
}

int32_t lb_chat_apply_template(const char *tmpl,
                               const lb_chat_message *msgs, size_t n_msgs,
                               int add_ass, char *buf, int32_t buf_size) {
#if LLAMA_OLD_API
    return llama_chat_apply_template(
        nullptr, tmpl,
        reinterpret_cast<const llama_chat_message *>(msgs),
        n_msgs, add_ass != 0, buf, buf_size);
#else
    return llama_chat_apply_template(
        tmpl,
        reinterpret_cast<const llama_chat_message *>(msgs),
        n_msgs, add_ass != 0, buf, buf_size);
#endif
}

int32_t lb_chat_apply_template_model(const lb_model *m, const char *tmpl,
                                     const lb_chat_message *msgs, size_t n_msgs,
                                     int add_ass, char *buf, int32_t buf_size) {
#if LLAMA_OLD_API
    return llama_chat_apply_template(
        m, tmpl,
        reinterpret_cast<const llama_chat_message *>(msgs),
        n_msgs, add_ass != 0, buf, buf_size);
#else
    (void)m;
    return llama_chat_apply_template(
        tmpl,
        reinterpret_cast<const llama_chat_message *>(msgs),
        n_msgs, add_ass != 0, buf, buf_size);
#endif
}

int32_t lb_tokenize(const lb_vocab *v, const char *text, int32_t text_len,
                    lb_token *tokens, int32_t n_tokens_max,
                    int add_special, int parse_special) {
#if LLAMA_OLD_API
    return llama_tokenize(
        reinterpret_cast<const llama_model *>(v),
        text, text_len, tokens, n_tokens_max,
        add_special != 0, parse_special != 0);
#else
    return llama_tokenize(v, text, text_len,
                          tokens, n_tokens_max,
                          add_special != 0, parse_special != 0);
#endif
}

int32_t lb_token_to_piece(const lb_vocab *v, lb_token token,
                          char *buf, int32_t buf_size,
                          int32_t lstrip, int special) {
#if LLAMA_OLD_API
    return llama_token_to_piece(
        reinterpret_cast<const llama_model *>(v),
        token, buf, buf_size, lstrip, special != 0);
#else
    return llama_token_to_piece(v, token, buf, buf_size, lstrip, special != 0);
#endif
}

void lb_kv_cache_clear(lb_context *c) {
#if LLAMA_OLD_API
    if (c) llama_kv_cache_clear(c);
#else
    if (c) llama_memory_clear(llama_get_memory(c), true);
#endif
}

int32_t lb_decode_tokens(lb_context *c, lb_token *tokens, int32_t n_tokens) {
#if LLAMA_OLD_API
    struct llama_batch batch = llama_batch_get_one(tokens, n_tokens, 0, 0);
#else
    struct llama_batch batch = llama_batch_get_one(tokens, n_tokens);
#endif
    return llama_decode(c, batch);
}

lb_sampler *lb_sampler_create(int32_t top_k, float top_p,
                              float temperature, uint32_t seed) {
    struct llama_sampler_chain_params cparams = llama_sampler_chain_default_params();
    struct llama_sampler *chain = llama_sampler_chain_init(cparams);
    if (!chain) return NULL;

    llama_sampler_chain_add(chain, llama_sampler_init_top_k(top_k));
    llama_sampler_chain_add(chain, llama_sampler_init_top_p(top_p, 1));
    llama_sampler_chain_add(chain, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(chain, llama_sampler_init_dist(seed));

    return chain;
}

void lb_sampler_free(lb_sampler *s) {
    if (s) llama_sampler_free(s);
}

lb_token lb_sampler_sample(lb_sampler *s, lb_context *c, int32_t idx) {
    return llama_sampler_sample(s, c, idx);
}

} /* extern "C" */
