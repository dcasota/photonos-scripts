#include "ai.h"
#include "local_prompt.h"
#include "autonomy.h"
#include "llama_bridge.h"
#include "embedded_model.h"
#include "../agent/agent.h"
#include "../util/util.h"
#include "../util/journal.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/*
 * llama.cpp provider for SPAGAT-Librarian.
 *
 * Uses the llama_bridge (C++ shim compiled against llama.h) to avoid
 * all struct-by-value ABI issues that arise with dlopen/dlsym casts.
 * The bridge is linked at compile time against libllama.so.
 *
 * All llama.cpp output is redirected to a self-rotating journal log
 * at ~/.spagat/logs/spagat.log via lb_log_set().
 */

/* Non-static: shared with local_prompt.c via extern */
lb_model         *model = NULL;
char              sys_prompt[8192];
bool              sys_prompt_ready = false;
char              cfg_project_prompt[1024];
#ifdef SPAGAT_DEFAULT_N_CTX
int               cfg_n_ctx        = SPAGAT_DEFAULT_N_CTX;
#else
int               cfg_n_ctx        = 2048;
#endif

static lb_context       *ctx   = NULL;
static const lb_vocab   *vocab = NULL;
static bool initialized = false;
static bool available   = false;
static int  embedded_fd = -1;

/* Config */
static char  cfg_model_path[512];
static char  cfg_device[64];
static float cfg_temperature = 0.7f;
static float cfg_top_p       = 0.9f;
static int   cfg_n_gpu_layers = 0;

static int   cfg_max_retries = 2;
static int   cfg_retry_delay_ms = 500;

/* llama.cpp log callback -> journal */
static void llama_to_journal(enum lb_log_level level, const char *text,
                             void *user_data) {
    (void)user_data;
    if (!text || !text[0]) return;

    /* Map lb_log_level to JournalLevel */
    JournalLevel jl;
    switch (level) {
    case LB_LOG_DEBUG: jl = JOURNAL_DEBUG; break;
    case LB_LOG_INFO:  jl = JOURNAL_INFO;  break;
    case LB_LOG_WARN:  jl = JOURNAL_WARN;  break;
    case LB_LOG_ERROR: jl = JOURNAL_ERROR; break;
    default:           jl = JOURNAL_INFO;  break;
    }

    /* llama.cpp provides pre-formatted text, write raw to avoid
     * double-timestamping.  Only add level prefix for warnings/errors. */
    if (jl >= JOURNAL_WARN) {
        journal_log(jl, "%s", text);
    } else {
        journal_write_raw(text);
    }
}

static bool parse_config(const char *config_json) {
    if (!config_json || !config_json[0]) return false;

    cfg_model_path[0] = '\0';
    str_safe_copy(cfg_device, "cpu", sizeof(cfg_device));
    cfg_n_gpu_layers = 0;
#ifdef SPAGAT_DEFAULT_N_CTX
    cfg_n_ctx = SPAGAT_DEFAULT_N_CTX;
#else
    cfg_n_ctx = 2048;
#endif

    const char *p = config_json;
    char line[1024];

    while (*p) {
        const char *eol = strchr(p, '\n');
        size_t len = eol ? (size_t)(eol - p) : strlen(p);
        if (len >= sizeof(line)) len = sizeof(line) - 1;
        memcpy(line, p, len);
        line[len] = '\0';
        p = eol ? eol + 1 : p + len;

        char *trimmed = str_trim(line);
        if (!trimmed[0] || trimmed[0] == '{' || trimmed[0] == '}' ||
            trimmed[0] == '[' || trimmed[0] == ']' || trimmed[0] == '#')
            continue;

        char key[128], value[512];
        key[0] = value[0] = '\0';

        char *sep = strchr(trimmed, '=');
        if (!sep) sep = strchr(trimmed, ':');
        if (!sep) continue;

        size_t klen = (size_t)(sep - trimmed);
        if (klen >= sizeof(key)) klen = sizeof(key) - 1;
        memcpy(key, trimmed, klen);
        key[klen] = '\0';

        char *vstart = sep + 1;
        str_safe_copy(value, str_trim(vstart), sizeof(value));

        char *k = str_trim(key);
        if (k[0] == '"') k++;
        size_t kl = strlen(k);
        if (kl > 0 && k[kl - 1] == '"') k[kl - 1] = '\0';

        char *v = value;
        if (v[0] == '"') v++;
        size_t vl = strlen(v);
        while (vl > 0 && (v[vl - 1] == ',' || v[vl - 1] == '"')) {
            v[vl - 1] = '\0';
            vl--;
        }

        if (str_equals_ignore_case(k, "model_path"))
            str_safe_copy(cfg_model_path, v, sizeof(cfg_model_path));
        else if (str_equals_ignore_case(k, "device"))
            str_safe_copy(cfg_device, v, sizeof(cfg_device));
        else if (str_equals_ignore_case(k, "temperature"))
            cfg_temperature = (float)atof(v);
        else if (str_equals_ignore_case(k, "top_p"))
            cfg_top_p = (float)atof(v);
        else if (str_equals_ignore_case(k, "n_gpu_layers"))
            cfg_n_gpu_layers = atoi(v);
        else if (str_equals_ignore_case(k, "n_ctx"))
            cfg_n_ctx = atoi(v);
    }

    return cfg_model_path[0] != '\0';
}

static void ensure_journal(void) {
    if (journal_is_open()) return;
    WorkspacePaths wp;
    if (workspace_get_paths(&wp))
        journal_open(wp.base_dir);
}

static bool local_init(const char *config_json) {
    if (initialized) return available;
    initialized = true;
    available = false;

    ensure_journal();

    parse_config(config_json);

    if (!cfg_model_path[0] && embedded_model_available()) {
        char memfd_path[64];
        embedded_fd = embedded_model_create_fd(memfd_path,
                                               sizeof(memfd_path));
        if (embedded_fd >= 0) {
            str_safe_copy(cfg_model_path, memfd_path,
                          sizeof(cfg_model_path));
            journal_log(JOURNAL_INFO, "ai: using embedded GGUF model");
        }
    }

    if (!cfg_model_path[0]) {
        fprintf(stderr,
            "ai: no model available.\n"
            "  Run 'spagat-librarian onboard' then edit "
            "~/.spagat/config.json\n"
            "  Set \"model_path\" to your .gguf model file.\n"
            "  Download from: https://huggingface.co/QuantFactory/"
            "gemma-2-2b-it-GGUF\n");
        return false;
    }

    /* Redirect all llama.cpp logging to journal BEFORE backend init */
    lb_log_set(llama_to_journal, NULL);

    lb_backend_init();

    journal_log(JOURNAL_INFO, "ai: loading model: %s", cfg_model_path);

    model = lb_model_load(cfg_model_path, cfg_n_gpu_layers);
    if (!model) {
        journal_log(JOURNAL_ERROR, "ai: failed to load model: %s",
                    cfg_model_path);
        fprintf(stderr, "ai: failed to load model (see ~/.spagat/logs/spagat.log)\n");
        lb_backend_free();
        return false;
    }

    vocab = lb_model_get_vocab(model);

    ctx = lb_context_create(model, (uint32_t)cfg_n_ctx);
    if (!ctx) {
        journal_log(JOURNAL_ERROR, "ai: failed to create llama context");
        fprintf(stderr, "ai: failed to create context (see ~/.spagat/logs/spagat.log)\n");
        lb_model_free(model);
        model = NULL;
        lb_backend_free();
        return false;
    }

    int32_t n_ctx_train = lb_model_n_ctx_train(model);
    journal_log(JOURNAL_INFO, "ai: llama.cpp ready (ctx_train=%d, n_ctx=%d)",
                n_ctx_train, cfg_n_ctx);

    available = true;
    return true;
}

static void local_cleanup(void) {
    if (ctx) { lb_context_free(ctx); ctx = NULL; }
    if (model) { lb_model_free(model); model = NULL; }
    lb_backend_free();
    if (embedded_fd >= 0) { close(embedded_fd); embedded_fd = -1; }
    vocab = NULL;
    initialized = false;
    available = false;
    journal_close();
}

static bool local_generate_once(const char *prompt, const ConvHistory *history,
                                char *response, int response_size,
                                ai_stream_callback_t callback,
                                void *user_data) {
    if (!available || !model || !ctx || !vocab) {
        str_safe_copy(response, "[Error: local LLM not available]",
                      response_size);
        return false;
    }

    lb_kv_cache_clear(ctx);

    char formatted[SPAGAT_MAX_PROMPT_LEN];
    int fmt_len = format_prompt(prompt, history, formatted, sizeof(formatted));

    journal_log(JOURNAL_DEBUG, "ai: formatted prompt (%d chars): %.200s...",
                fmt_len, formatted);

    int max_tokens = cfg_n_ctx;
    lb_token *tokens = malloc(max_tokens * sizeof(lb_token));
    if (!tokens) {
        str_safe_copy(response, "[Error: out of memory]", response_size);
        return false;
    }

    int32_t n_tokens = lb_tokenize(
        vocab, formatted, (int32_t)strlen(formatted),
        tokens, max_tokens, 1, 1);

    if (n_tokens < 0) {
        free(tokens);
        str_safe_copy(response, "[Error: tokenization failed]", response_size);
        return false;
    }

    journal_log(JOURNAL_DEBUG, "ai: prompt tokenized: %d tokens", n_tokens);

    int32_t ret = lb_decode_tokens(ctx, tokens, n_tokens);
    free(tokens);

    if (ret != 0) {
        journal_log(JOURNAL_ERROR, "ai: prompt decode failed (ret=%d)", ret);
        str_safe_copy(response, "[Error: prompt decode failed]", response_size);
        return false;
    }

    lb_sampler *sampler = lb_sampler_create(40, cfg_top_p,
                                            cfg_temperature, 0);
    if (!sampler) {
        str_safe_copy(response, "[Error: sampler init failed]", response_size);
        return false;
    }

    lb_token eos = lb_vocab_eos(vocab);
    int max_gen = cfg_n_ctx - n_tokens;
    if (max_gen > SPAGAT_MAX_RESPONSE_LEN / 4)
        max_gen = SPAGAT_MAX_RESPONSE_LEN / 4;
    if (max_gen < 64) max_gen = 64;
    int resp_pos = 0;
    char piece[256];

    for (int i = 0; i < max_gen; i++) {
        lb_token new_token = lb_sampler_sample(sampler, ctx, -1);

        if (new_token == eos || new_token < 0) break;

        int32_t n = lb_token_to_piece(vocab, new_token, piece,
                                       sizeof(piece) - 1, 0, 0);
        if (n <= 0) continue;
        piece[n] = '\0';

        if (callback)
            callback(piece, user_data);

        if (resp_pos + n < response_size - 1) {
            memcpy(response + resp_pos, piece, n);
            resp_pos += n;
        }

        /* Secondary stop: detect EOS strings in generated text */
        response[resp_pos] = '\0';
        if (strstr(response, "<|eot_id|>") ||
            strstr(response, "<|end_of_text|>") ||
            strstr(response, "<end_of_turn>")) {
            /* Strip the EOS marker from the response */
            char *marker = strstr(response, "<|eot_id|>");
            if (!marker) marker = strstr(response, "<|end_of_text|>");
            if (!marker) marker = strstr(response, "<end_of_turn>");
            if (marker) { *marker = '\0'; resp_pos = (int)(marker - response); }
            break;
        }

        ret = lb_decode_tokens(ctx, &new_token, 1);
        if (ret != 0) break;
    }

    response[resp_pos] = '\0';
    lb_sampler_free(sampler);

    journal_log(JOURNAL_DEBUG, "ai: generated %d bytes", resp_pos);

    return resp_pos > 0;
}

/* Retry wrapper (#8): retries on failure up to cfg_max_retries times */
static bool local_generate(const char *prompt, const ConvHistory *history,
                            char *response, int response_size,
                            ai_stream_callback_t callback, void *user_data) {
    for (int attempt = 0; attempt <= cfg_max_retries; attempt++) {
        if (attempt > 0) {
            journal_log(JOURNAL_INFO, "ai: retry attempt %d/%d",
                        attempt, cfg_max_retries);
            if (cfg_retry_delay_ms > 0) {
                struct timespec ts;
                ts.tv_sec = cfg_retry_delay_ms / 1000;
                ts.tv_nsec = (cfg_retry_delay_ms % 1000) * 1000000L;
                nanosleep(&ts, NULL);
            }
        }

        if (local_generate_once(prompt, history, response, response_size,
                                callback, user_data)) {
            return true;
        }

        /* On last attempt, don't clear the error message in response */
        if (attempt < cfg_max_retries) {
            journal_log(JOURNAL_WARN, "ai: generation failed, will retry");
        }
    }
    return false;
}

static bool local_is_available(void) {
    return available;
}

static const char *local_get_name(void) {
    static char name_buf[256];
    char desc[128] = {0};
    if (model)
        lb_model_desc(model, desc, sizeof(desc));

    if (desc[0]) {
        snprintf(name_buf, sizeof(name_buf), "local (llama.cpp, %s%s)",
                 desc, embedded_fd >= 0 ? ", embedded" : "");
    } else if (embedded_fd >= 0) {
        snprintf(name_buf, sizeof(name_buf), "local (llama.cpp, embedded GGUF)");
    } else {
        snprintf(name_buf, sizeof(name_buf), "local (llama.cpp)");
    }
    return name_buf;
}

static AIProvider local_provider = {
    .init = local_init,
    .cleanup = local_cleanup,
    .generate = local_generate,
    .is_available = local_is_available,
    .get_name = local_get_name
};

AIProvider *ai_get_local_provider(void) {
    return &local_provider;
}

static AIProvider *active_provider = NULL;

bool ai_init(void) {
    active_provider = &local_provider;

    WorkspacePaths wp;
    if (workspace_get_paths(&wp)) {
        SpagatConfig cfg;
        config_set_defaults(&cfg);
        config_load(wp.config_path, &cfg);

        /* Retry config (#8) */
        cfg_max_retries = cfg.max_retries;
        cfg_retry_delay_ms = cfg.retry_delay_ms;

        /* Per-project system prompt (#28) */
        str_safe_copy(cfg_project_prompt, cfg.project_system_prompt,
                      sizeof(cfg_project_prompt));

        /* Migration (#86): persist updated autonomy if migrated */
        if (cfg.autonomy_mode[0] && !cfg.fs_access_mode[0]) {
            /* Already has autonomy, no migration needed */
        }

        char config_buf[2048];
        snprintf(config_buf, sizeof(config_buf),
                 "model_path=%s\n"
                 "device=%s\n"
                 "temperature=%.2f\n"
                 "top_p=%.2f\n"
                 "n_gpu_layers=%d\n"
                 "n_ctx=%d\n",
                 cfg.local_model_path,
                 cfg.local_device,
                 (double)cfg.local_temperature,
                 (double)cfg.local_top_p,
                 cfg.local_n_gpu_layers,
                 cfg.local_n_ctx);

        active_provider->init(config_buf);

        /* Initialize tools with autonomy gating */
        AutonomyConfig acfg;
        autonomy_defaults(&acfg);
        acfg.level = autonomy_level_from_string(cfg.autonomy_mode);
        acfg.confirm_destructive = cfg.confirm_destructive;
        acfg.session_write_limit = cfg.session_write_limit;
        acfg.session_file_limit = cfg.session_file_limit;
        acfg.max_calls_per_prompt = cfg.max_tool_calls_per_prompt;
        acfg.max_calls_per_session = cfg.max_tool_calls_per_session;
        acfg.shell_timeout = cfg.shell_timeout;
        ai_tools_init_with_autonomy(&acfg);

        /* Log session start (#128) */
        ensure_journal();
        journal_log(JOURNAL_INFO,
                    "SESSION START autonomy=%s retries=%d project_prompt=%s",
                    cfg.autonomy_mode, cfg.max_retries,
                    cfg.project_system_prompt[0] ? "yes" : "no");
    } else {
        ai_tools_init();
    }

    return true;
}

void ai_cleanup(void) {
    if (active_provider && active_provider->cleanup)
        active_provider->cleanup();
    active_provider = NULL;
}

AIProvider *ai_get_provider(void) {
    return active_provider;
}
