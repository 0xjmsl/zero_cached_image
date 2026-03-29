import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'cache_manager.dart';
import 'multi_image_stream_completer.dart';

@immutable
class ZeroCachedImageProvider
    extends ImageProvider<ZeroCachedImageProvider> {
  final String url;
  final double scale;
  final Map<String, String>? headers;
  final ZeroCacheManager? cacheManager;
  final void Function(Object)? errorListener;

  const ZeroCachedImageProvider(
    this.url, {
    this.scale = 1.0,
    this.headers,
    this.cacheManager,
    this.errorListener,
  });

  ZeroCacheManager get _manager => cacheManager ?? ZeroCacheManager.instance;

  @override
  Future<ZeroCachedImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<ZeroCachedImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    ZeroCachedImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final chunkEvents = StreamController<ImageChunkEvent>();
    final completer = MultiImageStreamCompleter(
      codec: _loadAsync(key, decode, chunkEvents),
      chunkEvents: chunkEvents.stream,
      scale: key.scale,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<ZeroCachedImageProvider>('Image key', key),
      ],
    );

    if (errorListener != null) {
      completer.addListener(ImageStreamListener(
        (_, __) {},
        onError: (error, _) => errorListener?.call(error),
      ));
    }

    return completer;
  }

  Stream<ui.Codec> _loadAsync(
    ZeroCachedImageProvider key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunkEvents,
  ) async* {
    try {
      final filePath = await _manager.getFilePath(
        key.url,
        headers: key.headers,
      );

      // Zero-copy: Flutter engine reads file directly into GPU-accessible memory
      final buffer = await ui.ImmutableBuffer.fromFilePath(filePath);
      final codec = await decode(buffer);
      yield codec;
    } catch (e, st) {
      // Clean up and rethrow so MultiImageStreamCompleter reports the error
      chunkEvents.addError(e, st);
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
    } finally {
      await chunkEvents.close();
    }
  }

  @override
  bool operator ==(Object other) {
    if (other is ZeroCachedImageProvider) {
      return url == other.url && scale == other.scale;
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() => 'ZeroCachedImageProvider("$url", scale: $scale)';
}
