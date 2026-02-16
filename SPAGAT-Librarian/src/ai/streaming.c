#include "ai.h"
#include "../util/util.h"
#include <ncurses.h>
#include <stdlib.h>
#include <string.h>

/* Streaming context for TUI and buffer output */
typedef struct {
    WINDOW *win;          /* ncurses window for output */
    char *buffer;         /* accumulation buffer */
    int buf_size;
    int buf_pos;
    bool cancelled;       /* set by user pressing Esc */
} AIStreamContext;

/* Initialize a stream context for window output */
void ai_stream_context_init_win(AIStreamContext *ctx, WINDOW *win) {
    if (!ctx) return;
    memset(ctx, 0, sizeof(AIStreamContext));
    ctx->win = win;
}

/* Initialize a stream context for buffer output */
void ai_stream_context_init_buf(AIStreamContext *ctx, char *buffer,
                                 int buf_size) {
    if (!ctx) return;
    memset(ctx, 0, sizeof(AIStreamContext));
    ctx->buffer = buffer;
    ctx->buf_size = buf_size;
    ctx->buf_pos = 0;
    if (buffer && buf_size > 0) {
        buffer[0] = '\0';
    }
}

/*
 * Streaming callback: print tokens to an ncurses WINDOW.
 * user_data must point to an AIStreamContext with win set.
 */
void ai_stream_to_window(const char *token, void *user_data) {
    AIStreamContext *ctx = (AIStreamContext *)user_data;
    if (!ctx || !token) return;
    if (ctx->cancelled) return;

    if (ctx->win) {
        waddstr(ctx->win, token);
        wrefresh(ctx->win);
    }

    /* Also accumulate in buffer if available */
    if (ctx->buffer && ctx->buf_pos < ctx->buf_size - 1) {
        int token_len = (int)strlen(token);
        int space = ctx->buf_size - ctx->buf_pos - 1;
        int copy_len = token_len < space ? token_len : space;
        memcpy(ctx->buffer + ctx->buf_pos, token, copy_len);
        ctx->buf_pos += copy_len;
        ctx->buffer[ctx->buf_pos] = '\0';
    }

    /* Check for Esc key (non-blocking) */
    if (ctx->win) {
        nodelay(ctx->win, TRUE);
        int ch = wgetch(ctx->win);
        if (ch == 27) { /* Escape */
            ctx->cancelled = true;
        }
        nodelay(ctx->win, FALSE);
    }
}

/*
 * Streaming callback: append tokens to a buffer.
 * user_data must point to an AIStreamContext with buffer set.
 */
void ai_stream_to_buffer(const char *token, void *user_data) {
    AIStreamContext *ctx = (AIStreamContext *)user_data;
    if (!ctx || !token) return;
    if (ctx->cancelled) return;

    if (!ctx->buffer || ctx->buf_pos >= ctx->buf_size - 1) return;

    int token_len = (int)strlen(token);
    int space = ctx->buf_size - ctx->buf_pos - 1;
    int copy_len = token_len < space ? token_len : space;
    memcpy(ctx->buffer + ctx->buf_pos, token, copy_len);
    ctx->buf_pos += copy_len;
    ctx->buffer[ctx->buf_pos] = '\0';
}

/* Check if streaming was cancelled */
bool ai_stream_cancelled(const AIStreamContext *ctx) {
    return ctx ? ctx->cancelled : false;
}

/* Get accumulated buffer length */
int ai_stream_buf_len(const AIStreamContext *ctx) {
    return ctx ? ctx->buf_pos : 0;
}

/* Reset stream context for reuse */
void ai_stream_reset(AIStreamContext *ctx) {
    if (!ctx) return;
    ctx->buf_pos = 0;
    ctx->cancelled = false;
    if (ctx->buffer && ctx->buf_size > 0) {
        ctx->buffer[0] = '\0';
    }
}
