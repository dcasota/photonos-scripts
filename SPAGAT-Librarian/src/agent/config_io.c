#include "agent.h"
#include "../util/util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * Configuration save / load logic for SPAGAT-Librarian.
 * Split out of onboard.c to keep file sizes manageable.
 */

/* Simple JSON value extraction (no cJSON dependency) */
static bool json_extract_string(const char *json, const char *key,
                                char *out, size_t out_size) {
    char search[128];
    snprintf(search, sizeof(search), "\"%s\"", key);

    const char *pos = strstr(json, search);
    if (!pos) return false;

    pos += strlen(search);

    /* Skip whitespace and colon */
    while (*pos && (*pos == ' ' || *pos == '\t' || *pos == ':')) pos++;

    if (*pos != '"') return false;
    pos++;

    const char *end = strchr(pos, '"');
    if (!end) return false;

    size_t len = (size_t)(end - pos);
    if (len >= out_size) len = out_size - 1;

    memcpy(out, pos, len);
    out[len] = '\0';
    return true;
}

static bool json_extract_int(const char *json, const char *key, int *out) {
    char search[128];
    snprintf(search, sizeof(search), "\"%s\"", key);

    const char *pos = strstr(json, search);
    if (!pos) return false;

    pos += strlen(search);

    while (*pos && (*pos == ' ' || *pos == '\t' || *pos == ':')) pos++;

    char *endp;
    long val = strtol(pos, &endp, 10);
    if (endp == pos) return false;

    *out = (int)val;
    return true;
}

static bool json_extract_float(const char *json, const char *key, float *out) {
    char search[128];
    snprintf(search, sizeof(search), "\"%s\"", key);

    const char *pos = strstr(json, search);
    if (!pos) return false;

    pos += strlen(search);

    while (*pos && (*pos == ' ' || *pos == '\t' || *pos == ':')) pos++;

    char *endp;
    double val = strtod(pos, &endp);
    if (endp == pos) return false;

    *out = (float)val;
    return true;
}

static bool json_extract_bool(const char *json, const char *key, bool *out) {
    char search[128];
    snprintf(search, sizeof(search), "\"%s\"", key);

    const char *pos = strstr(json, search);
    if (!pos) return false;

    pos += strlen(search);

    while (*pos && (*pos == ' ' || *pos == '\t' || *pos == ':')) pos++;

    if (strncmp(pos, "true", 4) == 0) {
        *out = true;
        return true;
    }
    if (strncmp(pos, "false", 5) == 0) {
        *out = false;
        return true;
    }

    return false;
}

bool config_save(const char *path, const SpagatConfig *config) {
    if (!path || !config) return false;

    FILE *fp = fopen(path, "w");
    if (!fp) {
        fprintf(stderr, "Cannot write config to %s: ", path);
        perror("");
        return false;
    }

    fprintf(fp, "{\n");
    fprintf(fp, "  \"provider\": \"%s\",\n", config->provider);
    fprintf(fp, "  \"max_tokens\": %d,\n", config->max_tokens);
    fprintf(fp, "  \"temperature\": %.1f,\n", (double)config->temperature);
    fprintf(fp, "  \"max_tool_iterations\": %d,\n",
            config->max_tool_iterations);
    fprintf(fp, "  \"restrict_to_workspace\": %s,\n",
            config->restrict_to_workspace ? "true" : "false");
    fprintf(fp, "  \"local\": {\n");
    fprintf(fp, "    \"enabled\": %s,\n",
            config->local_enabled ? "true" : "false");
    fprintf(fp, "    \"engine\": \"%s\",\n", config->local_engine);
    fprintf(fp, "    \"model_path\": \"%s\",\n", config->local_model_path);
    fprintf(fp, "    \"device\": \"%s\",\n", config->local_device);
    fprintf(fp, "    \"n_gpu_layers\": %d,\n", config->local_n_gpu_layers);
    fprintf(fp, "    \"n_ctx\": %d,\n", config->local_n_ctx);
    fprintf(fp, "    \"temperature\": %.1f,\n",
            (double)config->local_temperature);
    fprintf(fp, "    \"top_p\": %.1f\n", (double)config->local_top_p);
    fprintf(fp, "  },\n");
    fprintf(fp, "  \"heartbeat\": {\n");
    fprintf(fp, "    \"enabled\": %s,\n",
            config->heartbeat_enabled ? "true" : "false");
    fprintf(fp, "    \"interval_minutes\": %d\n",
            config->heartbeat_interval);
    fprintf(fp, "  },\n");
    fprintf(fp, "  \"filesystem\": {\n");
    fprintf(fp, "    \"access_mode\": \"%s\"\n", config->fs_access_mode);
    fprintf(fp, "  },\n");
    fprintf(fp, "  \"autonomy\": {\n");
    fprintf(fp, "    \"mode\": \"%s\",\n", config->autonomy_mode);
    fprintf(fp, "    \"confirm_destructive\": %s,\n",
            config->confirm_destructive ? "true" : "false");
    fprintf(fp, "    \"session_write_limit\": %ld,\n",
            config->session_write_limit);
    fprintf(fp, "    \"session_file_limit\": %d,\n",
            config->session_file_limit);
    fprintf(fp, "    \"max_tool_calls_per_prompt\": %d,\n",
            config->max_tool_calls_per_prompt);
    fprintf(fp, "    \"max_tool_calls_per_session\": %d,\n",
            config->max_tool_calls_per_session);
    fprintf(fp, "    \"shell_timeout\": %d\n", config->shell_timeout);
    fprintf(fp, "  },\n");
    fprintf(fp, "  \"retry\": {\n");
    fprintf(fp, "    \"max_retries\": %d,\n", config->max_retries);
    fprintf(fp, "    \"retry_delay_ms\": %d\n", config->retry_delay_ms);
    fprintf(fp, "  }");
    if (config->project_system_prompt[0]) {
        fprintf(fp, ",\n  \"project_system_prompt\": \"%s\"\n",
                config->project_system_prompt);
    } else {
        fprintf(fp, "\n");
    }
    fprintf(fp, "}\n");

    fclose(fp);
    return true;
}

bool config_load(const char *path, SpagatConfig *config) {
    if (!path || !config) return false;

    /* Start with defaults */
    config_set_defaults(config);

    FILE *fp = fopen(path, "r");
    if (!fp) return false;

    /* Read entire file */
    fseek(fp, 0, SEEK_END);
    long size = ftell(fp);
    fseek(fp, 0, SEEK_SET);

    if (size <= 0 || size > 16384) {
        fclose(fp);
        return false;
    }

    char *json = malloc((size_t)size + 1);
    if (!json) {
        fclose(fp);
        return false;
    }

    size_t read_bytes = fread(json, 1, (size_t)size, fp);
    fclose(fp);
    json[read_bytes] = '\0';

    /* Parse top-level fields */
    json_extract_string(json, "provider", config->provider,
                        sizeof(config->provider));
    json_extract_int(json, "max_tokens", &config->max_tokens);
    json_extract_float(json, "temperature", &config->temperature);
    json_extract_int(json, "max_tool_iterations",
                     &config->max_tool_iterations);
    json_extract_bool(json, "restrict_to_workspace",
                      &config->restrict_to_workspace);

    /* Parse local section */
    json_extract_bool(json, "enabled", &config->local_enabled);
    json_extract_string(json, "engine", config->local_engine,
                        sizeof(config->local_engine));
    json_extract_string(json, "model_path", config->local_model_path,
                        sizeof(config->local_model_path));
    json_extract_string(json, "device", config->local_device,
                        sizeof(config->local_device));

    /* Parse local section fields */
    const char *local_section = strstr(json, "\"local\"");
    if (local_section) {
        json_extract_int(local_section, "n_gpu_layers",
                         &config->local_n_gpu_layers);
        json_extract_int(local_section, "n_ctx", &config->local_n_ctx);
        json_extract_float(local_section, "temperature",
                           &config->local_temperature);
        json_extract_float(local_section, "top_p", &config->local_top_p);
    }

    /* Parse heartbeat section */
    const char *hb_section = strstr(json, "\"heartbeat\"");
    if (hb_section) {
        json_extract_bool(hb_section, "enabled", &config->heartbeat_enabled);
        json_extract_int(hb_section, "interval_minutes",
                         &config->heartbeat_interval);
    }

    /* Parse filesystem section */
    const char *fs_section = strstr(json, "\"filesystem\"");
    if (fs_section) {
        json_extract_string(fs_section, "access_mode",
                            config->fs_access_mode,
                            sizeof(config->fs_access_mode));
    }

    /* Parse autonomy section */
    const char *auto_section = strstr(json, "\"autonomy\"");
    if (auto_section) {
        json_extract_string(auto_section, "mode",
                            config->autonomy_mode,
                            sizeof(config->autonomy_mode));
        json_extract_bool(auto_section, "confirm_destructive",
                          &config->confirm_destructive);
        int swl = 0;
        if (json_extract_int(auto_section, "session_write_limit", &swl))
            config->session_write_limit = (long)swl;
        json_extract_int(auto_section, "session_file_limit",
                         &config->session_file_limit);
        json_extract_int(auto_section, "max_tool_calls_per_prompt",
                         &config->max_tool_calls_per_prompt);
        json_extract_int(auto_section, "max_tool_calls_per_session",
                         &config->max_tool_calls_per_session);
        json_extract_int(auto_section, "shell_timeout",
                         &config->shell_timeout);
    }

    /* Parse retry section (#8) */
    const char *retry_section = strstr(json, "\"retry\"");
    if (retry_section) {
        json_extract_int(retry_section, "max_retries",
                         &config->max_retries);
        json_extract_int(retry_section, "retry_delay_ms",
                         &config->retry_delay_ms);
    }

    /* Per-project system prompt (#28) */
    json_extract_string(json, "project_system_prompt",
                        config->project_system_prompt,
                        sizeof(config->project_system_prompt));

    /* Migration (#86): if autonomy mode is still default but
       fs_access_mode was explicitly set, migrate it */
    if (!auto_section && config->fs_access_mode[0]) {
        if (str_equals_ignore_case(config->fs_access_mode, "full")) {
            str_safe_copy(config->autonomy_mode, "full",
                          sizeof(config->autonomy_mode));
        } else if (str_equals_ignore_case(config->fs_access_mode, "home")) {
            str_safe_copy(config->autonomy_mode, "home",
                          sizeof(config->autonomy_mode));
        } else if (str_equals_ignore_case(config->fs_access_mode, "workspace")) {
            str_safe_copy(config->autonomy_mode, "workspace",
                          sizeof(config->autonomy_mode));
        }
    }

    free(json);
    return true;
}
