import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'fetch_hooks.dart';

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
  ///
  /// [preAuth] sends the [ZeroFetchHooks.requestAuth] body on the FIRST
  /// attempt instead of waiting for a 401 challenge — for callers that
  /// already know the URL is gated.
  Future<DownloadResult> download(
    String url,
    String destPath, {
    String? etag,
    Map<String, String>? headers,
    bool preAuth = false,
  }) {
    if (_inFlight.containsKey(url)) {
      return _inFlight[url]!.future;
    }

    final completer = Completer<DownloadResult>();
    _inFlight[url] = completer;

    _doDownload(url, destPath, etag: etag, headers: headers, preAuth: preAuth)
        .then(
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
    bool preAuth = false,
  }) async {
    final uri = Uri.parse(url);
    final auth = ZeroFetchHooks.requestAuth;

    // Attempt 1: plain — unless the caller pre-authenticates a known-gated
    // URL, skipping the challenge round trip.
    String? authBody;
    if (preAuth && auth != null) {
      authBody = await auth(url);
    }
    var response = await _send(uri, etag: etag, headers: headers, body: authBody);

    // RFC 7235 challenge: 401 + WWW-Authenticate. Ask the app for
    // credentials and retry ONCE. The hook decides whether (and how) to
    // answer — the package knows nothing about the auth scheme. Invoked per
    // attempt, never cached: credentials may be single-use or time-bound.
    if (response.statusCode == HttpStatus.unauthorized &&
        authBody == null &&
        auth != null &&
        response.headers.value(HttpHeaders.wwwAuthenticateHeader) != null) {
      await response.drain<void>();
      authBody = await auth(url);
      if (authBody != null) {
        response = await _send(uri, etag: etag, headers: headers, body: authBody);
      }
    }

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

    final transform = ZeroFetchHooks.responseTransform;
    final file = File(destPath);
    var size = 0;

    if (transform != null) {
      // Transform path: buffer the body, hand it to the app with the response
      // headers, cache what comes back. The cache stores POST-transform bytes
      // so decode reads them zero-copy like any other file.
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = values.join(', ');
      });
      final transformed = await transform(builder.takeBytes(), responseHeaders);
      await file.writeAsBytes(transformed, flush: true);
      size = transformed.length;
    } else {
      final sink = file.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          size += chunk.length;
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
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

  /// One GET. When [body] is set it is sent as a JSON request body (some auth
  /// schemes carry request-scoped credentials in the body of a GET).
  Future<HttpClientResponse> _send(
    Uri uri, {
    String? etag,
    Map<String, String>? headers,
    String? body,
  }) async {
    final request = await _client.openUrl('GET', uri);
    if (etag != null) {
      request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
    }
    if (headers != null) {
      headers.forEach((k, v) => request.headers.set(k, v));
    }
    if (body != null) {
      // Explicit Content-Length, never chunked: dart:io writes on a GET go
      // out as Transfer-Encoding: chunked (or get dropped), and proxies/
      // servers commonly discard chunked GET bodies — the request then
      // arrives body-less and the auth silently fails. package:http avoids
      // this the same way (it always sets the length).
      final bytes = utf8.encode(body);
      request.headers.contentType = ContentType.json;
      request.headers.contentLength = bytes.length;
      request.add(bytes);
    }
    return request.close();
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
