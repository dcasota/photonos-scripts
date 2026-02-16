#ifndef AI_H
#define AI_H

#include "spagat.h"
#include <stdbool.h>
#include <stdint.h>

#define SPAGAT_MAX_PROMPT_LEN 16384
#define SPAGAT_MAX_RESPONSE_LEN 8192
#define SPAGAT_MAX_SESSION_ID_LEN 64
#define SPAGAT_MAX_ROLE_LEN 16

/* Conversation message */
typedef struct {
    int64_t id;
    int64_t item_id;       /* 0 for global conversations */
    char session_id[SPAGAT_MAX_SESSION_ID_LEN];
    char role[SPAGAT_MAX_ROLE_LEN];  /* "user", "assistant", "system" */
    char *content;         /* dynamically allocated */
    int tokens_used;
    time_t created_at;
} ConvMessage;

typedef struct {
    ConvMessage *messages;
    int count;
    int capacity;
} ConvHistory;

/* Checkpoint */
typedef struct {
    int64_t id;
    int64_t item_id;
    char name[SPAGAT_MAX_TITLE_LEN];
    char *state_json;      /* dynamically allocated */
    time_t created_at;
} Checkpoint;

/* Streaming callback: called for each token generated */
typedef void (*ai_stream_callback_t)(const char *token, void *user_data);

/* AI provider interface */
typedef struct {
    bool (*init)(const char *config_json);
    void (*cleanup)(void);
    bool (*generate)(const char *prompt, const ConvHistory *history,
                     char *response, int response_size,
                     ai_stream_callback_t callback, void *user_data);
    bool (*is_available)(void);
    const char *(*get_name)(void);
} AIProvider;

/* Provider management */
bool ai_init(void);
void ai_cleanup(void);
AIProvider *ai_get_provider(void);

/* Conversation database operations */
bool ai_conv_add(int64_t item_id, const char *session_id, const char *role,
                 const char *content, int tokens, int64_t *out_id);
bool ai_conv_get_history(int64_t item_id, const char *session_id,
                         ConvHistory *history);
void ai_conv_free_history(ConvHistory *history);
void ai_conv_free_message(ConvMessage *msg);

/* Checkpoint operations */
bool ai_checkpoint_save(int64_t item_id, const char *name, int64_t *out_id);
bool ai_checkpoint_load(int64_t checkpoint_id, ConvHistory *history);
bool ai_checkpoint_list(int64_t item_id, Checkpoint **checkpoints, int *count);
void ai_checkpoint_free(Checkpoint *checkpoints, int count);

/* Memory operations */
bool ai_memory_init(void);
bool ai_memory_set(int64_t project_id, const char *scope, const char *key,
                   const char *value);
bool ai_memory_get(int64_t project_id, const char *scope, const char *key,
                   char *value_buf, int buf_size);
bool ai_memory_print_all(int64_t project_id, const char *scope);
bool ai_memory_delete(int64_t project_id, const char *scope, const char *key);
bool ai_memory_clear(int64_t project_id, const char *scope);
bool ai_memory_load_file(const char *path);
bool ai_memory_save_file(const char *path);

/* Autonomy config (defined in autonomy.h) */
#include "autonomy.h"

/* Tool operations */
void ai_tools_init(void);
void ai_tools_init_with_autonomy(const AutonomyConfig *acfg);
void ai_tools_cleanup(void);
typedef bool (*ai_tool_handler_fn)(const char *input, char *output,
                                   int output_size);
bool ai_tool_register(const char *name, const char *description,
                      ai_tool_handler_fn handler);
bool ai_tool_execute(const char *name, const char *input, char *output,
                     int output_size);
int ai_tools_list(char *output, int output_size);
int ai_tools_count(void);

/* Session ID generation */
void ai_generate_session_id(char *buf, int buf_size);

/* System info (tools_sysinfo.c) */
void tools_sysinfo_init(void);
int  sysinfo_snapshot(char *buf, int buf_size);
int  sysinfo_category(const char *category, char *buf, int buf_size);

/* Git tools (git_tools.c) */
void git_tools_init(void);

/* Sysaware (sysaware.c) - declared in sysaware.h */

#endif
