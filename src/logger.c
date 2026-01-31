/*!
 * \file logger.c
 * \brief C logging library implementation with thread safety.
 *
 * This is a standalone C logging library for use by C code in other projects.
 * It is NOT part of zinternal's build or tests.
 *
 * Features:
 * - Thread-safe with spinlock (no external dependencies)
 * - Multiple log levels (TRACE to FATAL)
 * - Configurable output stream
 *
 * Usage:
 *   #include "zinternal/src/logger.h"
 *
 *   zlog_init(stdout, ZLOG_INFO);
 *   zlog_info("Hello, %s", "world");
 *   zlog_shutdown();
 */

#include "logger.h"
#include <stdlib.h>
#include <string.h>
#include <assert.h>

/* ==================== Platform Detection ==================== */

#if defined(_WIN32) || defined(_WIN64)
    #define PLATFORM_WINDOWS
    #include <windows.h>
#else
    #include <stdint.h>
    #include <sched.h>  /* for sched_yield() */
#endif

/* ==================== Spinlock Implementation ==================== */

/* Spinlock type: 0 = unlocked, 1 = locked */
typedef int volatile spinlock_t;

static inline void spinlock_lock(spinlock_t *lock) {
    while (1) {
#if defined(PLATFORM_WINDOWS)
        /* Windows: use InterlockedCompareExchange */
        LONG result = InterlockedCompareExchange((LONG *)lock, 1, 0);
        if (result == 0) break;
        Sleep(0);  /* Yield to other threads */
#else
        /* POSIX: use GCC atomic builtin */
        if (__sync_bool_compare_and_swap(lock, 0, 1)) break;
        sched_yield();  /* Yield to other threads */
#endif
    }
}

static inline void spinlock_unlock(spinlock_t *lock) {
    *lock = 0;
}

/* ==================== Global State ==================== */

static spinlock_t g_lock = 0;
static FILE *g_output = NULL;
static int g_level = ZLOG_INFO;

/* ==================== Helper Functions ==================== */

static FILE *get_output(void) {
    return g_output ? g_output : stderr;
}

static int validate_level(int level) {
    return (level >= ZLOG_TRACE && level <= ZLOG_FATAL) ? level : ZLOG_INFO;
}

/* ==================== Public API ==================== */

void zlog_init(FILE *out, int level) {
    spinlock_lock(&g_lock);
    g_output = out ? out : stderr;
    g_level = validate_level(level);
    spinlock_unlock(&g_lock);
}

void zlog_shutdown(void) {
    spinlock_lock(&g_lock);
    if (g_output && g_output != stderr) {
        fclose(g_output);
    }
    g_output = NULL;
    spinlock_unlock(&g_lock);
}

int zlog_get_level(void) {
    return g_level;
}

void zlog_set_level(int level) {
    spinlock_lock(&g_lock);
    g_level = validate_level(level);
    spinlock_unlock(&g_lock);
}

/* ==================== Logging Functions ==================== */

static void zlog_write(int level, const char *fmt, va_list args) {
    assert(g_output != NULL && "zlog_init() must be called before logging");
    spinlock_lock(&g_lock);
    if (g_output && level >= g_level) {
        vfprintf(g_output, fmt, args);
        fflush(g_output);  /* Ensure output is written */
    }
    spinlock_unlock(&g_lock);
}

void zlog_trace(const char *fmt, ...) {
    if (ZLOG_TRACE < g_level) return;
    va_list args;
    va_start(args, fmt);
    zlog_write(ZLOG_TRACE, fmt, args);
    va_end(args);
}

void zlog_debug(const char *fmt, ...) {
    if (ZLOG_DEBUG < g_level) return;
    va_list args;
    va_start(args, fmt);
    zlog_write(ZLOG_DEBUG, fmt, args);
    va_end(args);
}

void zlog_info(const char *fmt, ...) {
    if (ZLOG_INFO < g_level) return;
    va_list args;
    va_start(args, fmt);
    zlog_write(ZLOG_INFO, fmt, args);
    va_end(args);
}

void zlog_warn(const char *fmt, ...) {
    if (ZLOG_WARN < g_level) return;
    va_list args;
    va_start(args, fmt);
    zlog_write(ZLOG_WARN, fmt, args);
    va_end(args);
}

void zlog_err(const char *fmt, ...) {
    if (ZLOG_ERR < g_level) return;
    va_list args;
    va_start(args, fmt);
    zlog_write(ZLOG_ERR, fmt, args);
    va_end(args);
}

void zlog_fatal(const char *fmt, ...) {
    if (ZLOG_FATAL < g_level) return;
    va_list args;
    va_start(args, fmt);
    zlog_write(ZLOG_FATAL, fmt, args);
    va_end(args);
}
