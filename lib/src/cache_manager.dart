import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

import 'cache_entry.dart';
import 'cache_store.dart';
import 'http_downloader.dart';

class ZeroCacheManager {
  static const Set<String> defaultImageExtensions = {
    '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg',
  };

  static ZeroCacheManager? _instance;
  static ZeroCacheManager get instance => _instance ??= ZeroCacheManager();

  /// Override the singleton (useful for testing or custom config).
  static set instance(ZeroCacheManager manager) => _instance = manager;

  final int maxCacheSize;
  final String cacheDirName;
  final Set<String> extensionAllowlist;
  final int _evictionCheckInterval;

  CacheStore? _store;
  HttpDownloader? _downloader;
  String? _cacheDir;
  Completer<void>? _initCompleter;
  int _downloadCount = 0;

  ZeroCacheManager({
    this.maxCacheSize = 500 * 1024 * 1024, // 500 MB
    this.cacheDirName = 'zero_cached_image',
    this.extensionAllowlist = defaultImageExtensions,
    int evictionCheckInterval = 100,
  }) : _evictionCheckInterval = evictionCheckInterval;

  Future<void> init() async {
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<void>();

    try {
      final appDir = await getApplicationSupportDirectory();
      _cacheDir = '${appDir.path}${Platform.pathSeparator}$cacheDirName';
      await Directory(_cacheDir!).create(recursive: true);

      _store = CacheStore('$_cacheDir${Platform.pathSeparator}index.json');
      await _store!.init();
      _downloader = HttpDownloader();

      // Evict on startup if over budget
      _runEviction();

      _initCompleter!.complete();
    } catch (e, st) {
      _initCompleter!.completeError(e, st);
    }
  }

  /// Returns the local file path for [url], downloading if necessary.
  /// The returned path can be used with ImmutableBuffer.fromFilePath().
  Future<String> getFilePath(
    String url, {
    Map<String, String>? headers,
  }) async {
    await init();

    final entry = _store!.get(url);

    if (entry != null) {
      // Cache hit — check if file still exists
      if (File(entry.path).existsSync()) {
        // If not expired, return immediately
        if (!entry.isExpired) return entry.path;

        // Expired — try conditional request
        try {
          final result = await _downloader!.download(
            url,
            entry.path,
            etag: entry.etag,
            headers: headers,
          );
          if (result.notModified) {
            // Server confirmed still valid — update expiry
            _store!.put(CacheEntry(
              url: url,
              path: entry.path,
              etag: entry.etag,
              expiry: result.maxAge != null
                  ? DateTime.now().add(result.maxAge!)
                  : null,
              size: entry.size,
            ));
            return entry.path;
          }
          // Downloaded fresh copy
          _onDownloaded(url, result);
          return result.filePath;
        } catch (_) {
          // Network error — serve stale
          return entry.path;
        }
      }
      // File missing — remove stale entry
      _store!.remove(url);
    }

    // Cache miss — download
    final destPath = _filePathForUrl(url);
    final result = await _downloader!.download(
      url,
      destPath,
      headers: headers,
    );
    _onDownloaded(url, result);
    return result.filePath;
  }

  /// Returns the local file path for [url] **only if it is already cached on
  /// disk**, never downloads. Returns null on cache miss or if the entry's
  /// file has been deleted out-of-band. Ignores expiry — callers that need a
  /// fresh copy should use [getFilePath] instead.
  ///
  /// Intended for latency-critical paths that cannot afford a network round
  /// trip (notification rendering in a background isolate, synchronous-feel
  /// UI affordances, etc.).
  Future<String?> getCachedFilePath(String url) async {
    await init();
    final entry = _store!.get(url);
    if (entry == null) return null;
    if (!File(entry.path).existsSync()) {
      _store!.remove(url);
      return null;
    }
    return entry.path;
  }

  /// Evict a single URL from cache. Deletes file + index entry.
  Future<void> evict(String url) async {
    await init();
    final entry = _store!.get(url);
    if (entry != null) {
      _store!.remove(url);
      try {
        await File(entry.path).delete();
      } catch (_) {}
    }
  }

  /// Clear all cached files and the index.
  Future<void> clear() async {
    await init();
    for (final entry in _store!.entries.values.toList()) {
      try {
        await File(entry.path).delete();
      } catch (_) {}
    }
    _store!.clear();
    await _store!.flush();
  }

  void dispose() {
    _store?.dispose();
    _downloader?.dispose();
  }

  void _onDownloaded(String url, DownloadResult result) {
    _store!.put(CacheEntry(
      url: url,
      path: result.filePath,
      etag: result.etag,
      expiry: result.maxAge != null
          ? DateTime.now().add(result.maxAge!)
          : null,
      size: result.size,
    ));

    _downloadCount++;
    if (_downloadCount % _evictionCheckInterval == 0) {
      _runEviction();
    }
  }

  void _runEviction() {
    final evictedPaths = _store!.evictToSize(maxCacheSize);
    for (final path in evictedPaths) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
  }

  String _filePathForUrl(String url) {
    final hash = sha256.convert(utf8.encode(url)).toString();
    final ext = _extensionFromUrl(url);
    return '$_cacheDir${Platform.pathSeparator}$hash$ext';
  }

  String _extensionFromUrl(String url) {
    try {
      final path = Uri.parse(url).path;
      final dot = path.lastIndexOf('.');
      if (dot == -1) return '';
      final ext = path.substring(dot).toLowerCase();
      if (extensionAllowlist.contains(ext)) return ext;
    } catch (_) {}
    return '';
  }
}
