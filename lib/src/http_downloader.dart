import 'dart:async';
import 'dart:io';

class DownloadResult {
  final String filePath;
  final String? etag;
  final Duration? maxAge;
  final int size;
  final bool notModified;

  DownloadResult({
    required this.filePath,
    this.etag,
    this.maxAge,
    this.size = 0,
    this.notModified = false,
  });
}

class HttpDownloader {
  final HttpClient _client = HttpClient();
  final Map<String, Completer<DownloadResult>> _inFlight = {};

  HttpDownloader() {
    _client.idleTimeout = const Duration(seconds: 15);
  }

  /// Download [url] to [destPath]. Deduplicates concurrent requests for the same URL.
  /// If [etag] is provided, sends If-None-Match for conditional requests.
  Future<DownloadResult> download(
    String url,
    String destPath, {
    String? etag,
    Map<String, String>? headers,
  }) {
    if (_inFlight.containsKey(url)) {
      return _inFlight[url]!.future;
    }

    final completer = Completer<DownloadResult>();
    _inFlight[url] = completer;

    _doDownload(url, destPath, etag: etag, headers: headers).then(
      (result) {
        _inFlight.remove(url);
        completer.complete(result);
      },
      onError: (Object e, StackTrace st) {
        _inFlight.remove(url);
        completer.completeError(e, st);
      },
    );

    return completer.future;
  }

  Future<DownloadResult> _doDownload(
    String url,
    String destPath, {
    String? etag,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse(url);
    final request = await _client.getUrl(uri);

    if (etag != null) {
      request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
    }
    if (headers != null) {
      headers.forEach((k, v) => request.headers.set(k, v));
    }

    final response = await request.close();

    if (response.statusCode == HttpStatus.notModified) {
      await response.drain<void>();
      return DownloadResult(
        filePath: destPath,
        etag: etag,
        notModified: true,
      );
    }

    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException(
        'HTTP ${response.statusCode} for $url',
        uri: uri,
      );
    }

    final file = File(destPath);
    final sink = file.openWrite();
    var size = 0;

    try {
      await for (final chunk in response) {
        sink.add(chunk);
        size += chunk.length;
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    final responseEtag = response.headers.value(HttpHeaders.etagHeader);
    final maxAge = _parseMaxAge(response.headers);

    return DownloadResult(
      filePath: destPath,
      etag: responseEtag,
      maxAge: maxAge,
      size: size,
    );
  }

  Duration? _parseMaxAge(HttpHeaders headers) {
    final cacheControl = headers.value(HttpHeaders.cacheControlHeader);
    if (cacheControl == null) return null;

    final match = RegExp(r'max-age=(\d+)').firstMatch(cacheControl);
    if (match == null) return null;

    final seconds = int.tryParse(match.group(1)!);
    if (seconds == null || seconds <= 0) return null;

    return Duration(seconds: seconds);
  }

  void dispose() {
    _client.close(force: true);
    for (final completer in _inFlight.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('HttpDownloader disposed'));
      }
    }
    _inFlight.clear();
  }
}
