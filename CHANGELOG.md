## 0.0.1-beta.0

* **Initial Beta Release**: Stable API, rigorous test coverage, and complete production verification.

* **Flare Initial Release**: Complete transformation from a raw key-value store to a full-featured Document Database.
* **Firebase-style API**: Familiar `CollectionReference` and `DocumentReference` interfaces.
* **Strong Typing**: Added `withConverter<T>` for seamless mapping between JSON and Dart classes.
* **Advanced Types**: Native support for `Timestamp` (nanosecond precision) and `GeoPoint` (lat/long).
* **Security**: Built-in AES-256 value-level encryption for data at rest.
* **Resilience**: Implemented Write-Ahead Logging (WAL) for automatic crash recovery and CRC32 block checksums for corruption detection.
* **Concurrency**: Native C++ thread safety (mutex-protected) for stable multi-isolate usage.
* **Android 15 Optimized**: Native support for 16KB page sizes and memory-mapped block alignment.
* **Developer Experience**: Path-based document navigation and automatic UUID generation.
