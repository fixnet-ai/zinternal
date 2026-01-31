/*!
 * \file logger.h
 * \brief C logging library header for external C projects.
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

#ifndef ZINTERNAL_LOGGER_H
#define ZINTERNAL_LOGGER_H

#include <stdio.h>

/*!
 * \brief Log levels (compatible with Zig logger.zig)
 */
typedef enum {
    ZLOG_TRACE = 0,
    ZLOG_DEBUG = 1,
    ZLOG_INFO  = 2,
    ZLOG_WARN  = 3,
    ZLOG_ERR   = 4,
    ZLOG_FATAL = 5,
} ZlogLevel;

/*!
 * \brief Initialize logger with output stream and level
 * \param out Output stream (e.g., stdout, stderr, fopen("app.log", "w"))
 * \param level Log level (ZLOG_TRACE to ZLOG_FATAL)
 *
 * Thread-safe: can be called from any thread.
 * Note: logger must be initialized before using any log functions.
 */
void zlog_init(FILE *out, int level);

/*!
 * \brief Shutdown logger and close output stream if not stderr
 *
 * Thread-safe: can be called from any thread.
 */
void zlog_shutdown(void);

/*!
 * \brief Get current log level
 * \return Current log level
 */
int zlog_get_level(void);

/*!
 * \brief Set log level at runtime
 * \param level New log level (ZLOG_TRACE to ZLOG_FATAL)
 *
 * Thread-safe: can be called from any thread.
 */
void zlog_set_level(int level);

/*!
 * \brief TRACE level log
 */
void zlog_trace(const char *fmt, ...);

/*!
 * \brief DEBUG level log
 */
void zlog_debug(const char *fmt, ...);

/*!
 * \brief INFO level log
 */
void zlog_info(const char *fmt, ...);

/*!
 * \brief WARN level log
 */
void zlog_warn(const char *fmt, ...);

/*!
 * \brief ERROR level log
 */
void zlog_err(const char *fmt, ...);

/*!
 * \brief FATAL level log
 */
void zlog_fatal(const char *fmt, ...);

#endif /* ZINTERNAL_LOGGER_H */
