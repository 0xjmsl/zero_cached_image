class CacheEntry {
  final String url;
  final String path;
  final String? etag;
  final DateTime? expiry;
  final int size;
  DateTime lastAccessed;

  CacheEntry({
    required this.url,
    required this.path,
    this.etag,
    this.expiry,
    this.size = 0,
    DateTime? lastAccessed,
  }) : lastAccessed = lastAccessed ?? DateTime.now();

  bool get isExpired =>
      expiry != null && DateTime.now().isAfter(expiry!);

  Map<String, dynamic> toJson() => {
        'url': url,
        'path': path,
        if (etag != null) 'etag': etag,
        if (expiry != null) 'expiry': expiry!.millisecondsSinceEpoch,
        'size': size,
        'lastAccessed': lastAccessed.millisecondsSinceEpoch,
      };

  factory CacheEntry.fromJson(Map<String, dynamic> json) => CacheEntry(
        url: json['url'] as String,
        path: json['path'] as String,
        etag: json['etag'] as String?,
        expiry: json['expiry'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['expiry'] as int)
            : null,
        size: json['size'] as int? ?? 0,
        lastAccessed: json['lastAccessed'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['lastAccessed'] as int)
            : DateTime.now(),
      );
}
