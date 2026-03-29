import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'cache_entry.dart';

class CacheStore {
  final String _indexPath;
  final Map<String, CacheEntry> _entries = {};
  Timer? _flushTimer;
  bool _dirty = false;
  Completer<void>? _initCompleter;

  CacheStore(this._indexPath);

  Map<String, CacheEntry> get entries => _entries;
  int get length => _entries.length;

  Future<void> init() async {
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<void>();
    try {
      await _load();
      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.complete(); // complete even on error — empty cache is fine
    }
  }

  CacheEntry? get(String url) {
    final entry = _entries[url];
    if (entry != null) {
      entry.lastAccessed = DateTime.now();
      _markDirty();
    }
    return entry;
  }

  void put(CacheEntry entry) {
    _entries[entry.url] = entry;
    _markDirty();
  }

  void remove(String url) {
    _entries.remove(url);
    _markDirty();
  }

  void clear() {
    _entries.clear();
    _markDirty();
  }

  /// Evict oldest entries until total size is under [maxBytes].
  /// Returns the file paths of evicted entries (caller deletes them).
  List<String> evictToSize(int maxBytes) {
    final totalSize = _entries.values.fold<int>(0, (sum, e) => sum + e.size);
    if (totalSize <= maxBytes) return [];

    final sorted = _entries.values.toList()
      ..sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));

    var currentSize = totalSize;
    final evictedPaths = <String>[];

    for (final entry in sorted) {
      if (currentSize <= maxBytes) break;
      currentSize -= entry.size;
      evictedPaths.add(entry.path);
      _entries.remove(entry.url);
    }

    if (evictedPaths.isNotEmpty) _markDirty();
    return evictedPaths;
  }

  /// Flush pending writes immediately.
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (!_dirty) return;
    await _save();
    _dirty = false;
  }

  void dispose() {
    _flushTimer?.cancel();
    if (_dirty) {
      // Best-effort sync flush on dispose
      _saveSync();
    }
  }

  void _markDirty() {
    _dirty = true;
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 2), () async {
      await _save();
      _dirty = false;
    });
  }

  Future<void> _load() async {
    final file = File(_indexPath);
    if (!await file.exists()) {
      // Try backup
      final bak = File('$_indexPath.bak');
      if (await bak.exists()) {
        try {
          final content = await bak.readAsString();
          _parseIndex(content);
          return;
        } catch (_) {}
      }
      return;
    }

    try {
      final content = await file.readAsString();
      _parseIndex(content);
    } catch (_) {
      // Corrupted — try backup
      final bak = File('$_indexPath.bak');
      if (await bak.exists()) {
        try {
          final content = await bak.readAsString();
          _parseIndex(content);
        } catch (_) {
          // Both corrupted — start fresh
        }
      }
    }
  }

  void _parseIndex(String content) {
    final list = jsonDecode(content) as List;
    for (final item in list) {
      final entry = CacheEntry.fromJson(item as Map<String, dynamic>);
      _entries[entry.url] = entry;
    }
  }

  Future<void> _save() async {
    final json = jsonEncode(_entries.values.map((e) => e.toJson()).toList());
    final tmpPath = '$_indexPath.tmp';
    final tmpFile = File(tmpPath);

    await tmpFile.writeAsString(json, flush: true);

    // Backup current before replacing
    final indexFile = File(_indexPath);
    if (await indexFile.exists()) {
      try {
        await indexFile.copy('$_indexPath.bak');
      } catch (_) {}
    }

    await tmpFile.rename(_indexPath);
  }

  void _saveSync() {
    try {
      final json = jsonEncode(_entries.values.map((e) => e.toJson()).toList());
      File('$_indexPath.tmp').writeAsStringSync(json, flush: true);
      final indexFile = File(_indexPath);
      if (indexFile.existsSync()) {
        try {
          indexFile.copySync('$_indexPath.bak');
        } catch (_) {}
      }
      File('$_indexPath.tmp').renameSync(_indexPath);
    } catch (_) {}
  }
}
