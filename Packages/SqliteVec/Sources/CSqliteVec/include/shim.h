/*
 * Swift-friendly shim for sqlite-vec
 *
 * Provides inline helper functions for registering sqlite-vec
 * and working with vector data.
 */

#ifndef SQLITE_VEC_SHIM_H
#define SQLITE_VEC_SHIM_H

#include <sqlite3.h>
#include <stdint.h>
#include <string.h>
#include "sqlite-vec.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Register sqlite-vec with a database connection (static linking).
 *
 * Call this after opening the database and before using vec0 tables.
 * Returns SQLITE_OK on success.
 */
static inline int sqlite_vec_register(sqlite3 *db) {
    return sqlite3_vec_init(db, NULL, NULL);
}

/*
 * Get sqlite-vec version string.
 */
static inline const char* sqlite_vec_version(void) {
    return SQLITE_VEC_VERSION;
}

/*
 * Helper: Calculate byte size for a float32 vector.
 */
static inline size_t sqlite_vec_float32_byte_size(int dimensions) {
    return (size_t)dimensions * sizeof(float);
}

/*
 * Helper: Calculate byte size for an int8 vector.
 */
static inline size_t sqlite_vec_int8_byte_size(int dimensions) {
    return (size_t)dimensions * sizeof(int8_t);
}

/*
 * Helper: Calculate byte size for a binary (bit) vector.
 * Rounds up to nearest byte.
 */
static inline size_t sqlite_vec_binary_byte_size(int dimensions) {
    return ((size_t)dimensions + 7) / 8;
}

#ifdef __cplusplus
}
#endif

#endif /* SQLITE_VEC_SHIM_H */
