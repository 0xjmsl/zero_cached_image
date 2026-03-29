# zero_cached_image

A minimal, high-performance cached network image widget for Flutter. Zero-copy disk reads and only 2 dependencies.

## How it works

| Step | Approach |
|------|----------|
| Cache lookup | In-memory `Map` (~11ns) |
| File loading | `ImmutableBuffer.fromFilePath()` (zero-copy, no Dart heap copy) |
| Widget layer | Flutter's built-in `frameBuilder` |
| Dependencies | 2 (`path_provider`, `crypto`) |

The in-memory index is loaded from a JSON file on startup and flushed to disk on changes (debounced, atomic writes with backup recovery). Cache survives app restarts.

## Install

```yaml
dependencies:
  zero_cached_image: ^1.0.0
```

## Usage

### Basic widget

```dart
ZeroCachedImage(
  imageUrl: 'https://example.com/photo.jpg',
  width: 200,
  height: 200,
  fit: BoxFit.cover,
)
```

### With placeholder and error widget

```dart
ZeroCachedImage(
  imageUrl: 'https://example.com/photo.jpg',
  placeholder: (context, url) => const CircularProgressIndicator(),
  errorWidget: (context, url, error) => const Icon(Icons.error),
)
```

### Fade animation

```dart
ZeroCachedImage(
  imageUrl: 'https://example.com/photo.jpg',
  fadeInDuration: const Duration(milliseconds: 300),  // default: 500ms
  fadeOutDuration: Duration.zero,                      // disable fade out
)
```

### Custom headers

```dart
ZeroCachedImage(
  imageUrl: 'https://example.com/private.jpg',
  httpHeaders: {'Authorization': 'Bearer token'},
)
```

### Image provider (for DecorationImage, precacheImage)

```dart
// In a BoxDecoration
Container(
  decoration: BoxDecoration(
    image: DecorationImage(
      image: ZeroCachedImageProvider('https://example.com/bg.jpg'),
      fit: BoxFit.cover,
    ),
  ),
)

// Precache
precacheImage(ZeroCachedImageProvider('https://example.com/photo.jpg'), context);
```

### Cache management

```dart
// Evict a single image
ZeroCachedImage.evictFromCache('https://example.com/photo.jpg');

// Clear all cached images
ZeroCacheManager.instance.clear();
```

### Custom cache configuration

```dart
// Override max cache size (default: 500MB)
ZeroCacheManager.instance = ZeroCacheManager(
  maxCacheSize: 200 * 1024 * 1024,  // 200MB
);
```

## All widget parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `imageUrl` | `String` | required | The URL to load |
| `width` | `double?` | null | Widget width |
| `height` | `double?` | null | Widget height |
| `fit` | `BoxFit?` | null | How to fit the image |
| `placeholder` | `Widget Function(BuildContext, String)?` | null | Shown while loading |
| `errorWidget` | `Widget Function(BuildContext, String, Object)?` | null | Shown on error |
| `fadeInDuration` | `Duration` | 500ms | Fade-in animation duration |
| `fadeOutDuration` | `Duration` | 200ms | Fade-out animation duration |
| `alignment` | `Alignment` | center | Image alignment |
| `httpHeaders` | `Map<String, String>?` | null | Custom HTTP headers |
| `cacheManager` | `ZeroCacheManager?` | null | Custom cache manager |
| `color` | `Color?` | null | Color tint |
| `colorBlendMode` | `BlendMode?` | null | Blend mode for color tint |
| `filterQuality` | `FilterQuality` | low | Rendering quality |

## Features

- **ETag / If-None-Match**: Conditional requests skip re-download when the server confirms cache is fresh (304 Not Modified).
- **Cache-Control max-age**: Respects server expiry hints.
- **LRU eviction**: Oldest entries evicted when cache exceeds size limit (default 500MB, configurable).
- **Concurrent deduplication**: Multiple requests for the same URL share a single download.
- **Atomic index writes**: Index written to `.tmp`, then renamed. `.bak` backup for corruption recovery.
- **Animated images**: GIF and animated WebP supported.
- **Web**: Falls back to `Image.network()` since `dart:io` is unavailable on web.

## Platforms

Works on all platforms where `dart:io` is available: **Android, iOS, Windows, macOS, Linux**. Web uses a fallback path (`Image.network()`).

## License

MIT
