## 1.0.0

- Initial release.
- `ZeroCachedImage` widget with fade animations and placeholder/error support.
- `ZeroCachedImageProvider` for use with `DecorationImage` and `precacheImage`.
- `ZeroCacheManager` with LRU eviction, ETag conditional requests, and Cache-Control max-age.
- Zero-copy image loading via `ImmutableBuffer.fromFilePath()`.
- In-memory index with JSON persistence (survives restarts).
- Concurrent request deduplication.
- Atomic index writes with backup recovery.
- Web fallback via `Image.network()`.
