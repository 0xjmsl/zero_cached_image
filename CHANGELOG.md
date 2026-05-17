## 1.3.0

- `ZeroCacheManager` now accepts `cacheRootOverride` constructor param. When set, the cache lives at `<cacheRootOverride>/<cacheDirName>` instead of `<getApplicationSupportDirectory()>/<cacheDirName>`. Enables placing the cache inside an iOS App Group container so a Notification Service Extension running in a separate process can read the same files. Defaults to null (1.2.0 behavior preserved).

## 1.2.0

- `ZeroCacheManager.getCachedFilePath(url)` — cache-only lookup that returns the local file path if already cached, null on miss. Never downloads. Intended for latency-critical paths (background-isolate notification rendering, etc.) where a network round trip is not acceptable.

## 1.1.0

- `ZeroCacheManager` now accepts `cacheDirName` and `extensionAllowlist` constructor params. Defaults preserve 1.0.0 behavior (`zero_cached_image` dir, image-only extension allowlist). Enables sibling packages (e.g., `zero_cached_video`) to reuse the cache machinery with their own directory + media-type allowlist.

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
