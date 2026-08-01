import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'cache_manager.dart';
import 'zero_cached_image_provider.dart';

class ZeroCachedImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext context, String url)? placeholder;
  final Widget Function(BuildContext context, String url, Object error)?
      errorWidget;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;
  final Alignment alignment;
  final Map<String, String>? httpHeaders;
  final ZeroCacheManager? cacheManager;
  final Color? color;
  final BlendMode? colorBlendMode;
  final FilterQuality filterQuality;

  /// Decode the image at (at most) this width/height in **physical pixels**
  /// instead of its native resolution. Pair with a small display box to render
  /// crisp thumbnails/avatars — the decoder area-resamples down once (sharper
  /// than GPU minification) and only the small bitmap is kept in memory. Null
  /// (the default) decodes at native resolution. Aspect ratio is preserved.
  final int? memCacheWidth;
  final int? memCacheHeight;

  /// Send the app's `ZeroFetchHooks.requestAuth` body on the first attempt —
  /// for URLs the caller already knows are gated (skips the server's 401
  /// challenge round trip). Gated URLs work without it too: the server
  /// challenges, the fetch retries authenticated. No effect when no
  /// `requestAuth` hook is installed.
  final bool preAuth;

  const ZeroCachedImage({
    super.key,
    required this.imageUrl,
    this.fit,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.fadeInDuration = const Duration(milliseconds: 500),
    this.fadeOutDuration = const Duration(milliseconds: 200),
    this.alignment = Alignment.center,
    this.httpHeaders,
    this.cacheManager,
    this.color,
    this.colorBlendMode,
    this.filterQuality = FilterQuality.low,
    this.memCacheWidth,
    this.memCacheHeight,
    this.preAuth = false,
  });

  /// Evict a single URL from the cache.
  static Future<void> evictFromCache(
    String url, {
    ZeroCacheManager? cacheManager,
  }) {
    return (cacheManager ?? ZeroCacheManager.instance).evict(url);
  }

  @override
  State<ZeroCachedImage> createState() => _ZeroCachedImageState();
}

class _ZeroCachedImageState extends State<ZeroCachedImage>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _hasAnimation = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final needsAnimation = widget.fadeInDuration > Duration.zero ||
        widget.fadeOutDuration > Duration.zero;
    if (needsAnimation) {
      _hasAnimation = true;
      _controller = AnimationController(
        vsync: this,
        duration: widget.fadeInDuration,
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(
        widget.imageUrl,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        alignment: widget.alignment,
        color: widget.color,
        colorBlendMode: widget.colorBlendMode,
        filterQuality: widget.filterQuality,
        cacheWidth: widget.memCacheWidth,
        cacheHeight: widget.memCacheHeight,
        errorBuilder: widget.errorWidget != null
            ? (context, error, _) =>
                widget.errorWidget!(context, widget.imageUrl, error)
            : null,
      );
    }

    return Image(
      image: ResizeImage.resizeIfNeeded(
        widget.memCacheWidth,
        widget.memCacheHeight,
        ZeroCachedImageProvider(
          widget.imageUrl,
          headers: widget.httpHeaders,
          cacheManager: widget.cacheManager,
          preAuth: widget.preAuth,
        ),
      ),
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      alignment: widget.alignment,
      color: widget.color,
      colorBlendMode: widget.colorBlendMode,
      filterQuality: widget.filterQuality,
      frameBuilder: _hasAnimation ? _frameBuilder : null,
      errorBuilder: widget.errorWidget != null
          ? (context, error, _) =>
              widget.errorWidget!(context, widget.imageUrl, error)
          : null,
    );
  }

  Widget _frameBuilder(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    // Already shown — return image directly on all subsequent rebuilds
    if (wasSynchronouslyLoaded || _loaded) return child;

    // Still loading — show placeholder
    if (frame == null) {
      return widget.placeholder?.call(context, widget.imageUrl) ??
          const SizedBox.shrink();
    }

    // First async load completed — fade in once, never again
    _loaded = true;
    _controller!.forward(from: 0.0);
    return FadeTransition(opacity: _controller!, child: child);
  }
}
