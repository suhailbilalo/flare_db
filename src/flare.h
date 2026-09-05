#ifndef FLARE_H
#define FLARE_H

#include <stdint.h>
#include <stdbool.h>

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DB DB;
typedef struct DBIterator DBIterator;

// Open or create a database file
FFI_PLUGIN_EXPORT DB* db_open(const char* path, const unsigned char* encryption_key);

// Close the database
FFI_PLUGIN_EXPORT void db_close(DB* db);

// Insert or update a document with a specific key
FFI_PLUGIN_EXPORT int64_t db_put(DB* db, const char* key, const char* json);

// Get a document by key
FFI_PLUGIN_EXPORT const char* db_get_by_key(DB* db, const char* key);

// Delete a document by key
FFI_PLUGIN_EXPORT bool db_delete(DB* db, const char* key);

// Get a document by ID (internal offset)
FFI_PLUGIN_EXPORT const char* db_get(DB* db, int64_t id);

// Flush changes to disk
FFI_PLUGIN_EXPORT void db_sync(DB* db);

// Encryption
FFI_PLUGIN_EXPORT void db_set_key(DB* db, const unsigned char* key);

// Secondary Index
FFI_PLUGIN_EXPORT int32_t db_create_index(DB* db, const char* name);
FFI_PLUGIN_EXPORT const char* db_get_index_name(DB* db, int32_t indexIdx);
FFI_PLUGIN_EXPORT void db_put_secondary(DB* db, int32_t indexIdx, const char* secKey, const char* primKey);
FFI_PLUGIN_EXPORT void db_remove_secondary(DB* db, int32_t indexIdx, const char* secKey, const char* primKey);
FFI_PLUGIN_EXPORT uint64_t db_get_root(DB* db, int32_t indexIdx);

// Free a string returned by db_get, db_get_by_key, etc.
FFI_PLUGIN_EXPORT void db_free_string(const char* s);

// Iterator
FFI_PLUGIN_EXPORT DBIterator* db_iterator_open(DB* db, uint64_t rootOffset, const char* startKey, const char* endKey);
FFI_PLUGIN_EXPORT bool db_iterator_next(DBIterator* it, const char** key, const char** json);
FFI_PLUGIN_EXPORT void db_iterator_close(DBIterator* it);

#ifdef __cplusplus
}
#endif

#endif // FLARE_H
