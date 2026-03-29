import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:zero_cached_image/zero_cached_image.dart';
import 'package:fast_cached_network_image/fast_cached_network_image.dart' as fcn;
import 'package:path_provider/path_provider.dart';

const testImages = [
  'https://pbs.twimg.com/profile_images/2008094233266376705/gypmfWbU_200x200.jpg',
  'https://pbs.twimg.com/profile_images/1874553021688123393/F1qTyZj5_400x400.jpg',
  'https://pbs.twimg.com/profile_images/1945608199500910592/rnk6ixxH_200x200.jpg',
  'https://pbs.twimg.com/profile_images/1808921860781821952/CmtvkzWo_200x200.png',
  'https://pbs.twimg.com/profile_images/1395420331922231301/lEFdJlvQ_200x200.jpg',
];

void main() {
  runApp(const BenchmarkApp());
}

class BenchmarkApp extends StatelessWidget {
  const BenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Image Cache Benchmark',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const BenchmarkHome(),
    );
  }
}

enum PackageId { ours, fcn }

class BenchmarkResult {
  final PackageId package;
  final String phase;
  final List<Duration> perImage;

  BenchmarkResult({
    required this.package,
    required this.phase,
    required this.perImage,
  });

  Duration get totalTime =>
      perImage.fold<Duration>(Duration.zero, (sum, d) => sum + d);

  double get avgMs =>
      perImage.map((d) => d.inMicroseconds).reduce((a, b) => a + b) /
      perImage.length /
      1000.0;

  double get medianMs {
    final sorted = perImage.map((d) => d.inMicroseconds).toList()..sort();
    final mid = sorted.length ~/ 2;
    return (sorted.length.isOdd
            ? sorted[mid]
            : (sorted[mid - 1] + sorted[mid]) / 2) /
        1000.0;
  }
}

class BenchmarkHome extends StatefulWidget {
  const BenchmarkHome({super.key});

  @override
  State<BenchmarkHome> createState() => _BenchmarkHomeState();
}

class _BenchmarkHomeState extends State<BenchmarkHome> {
  List<String> _urls = [];
  bool _running = false;
  bool _initialized = false;
  String _status = 'Validating URLs...';

  // Results
  BenchmarkResult? _oursCold, _oursHot, _fcnCold, _fcnHot;

  // Key to force widget rebuilds (visual reload) — both columns at once
  int _reloadKey = 0;
  bool _oursOnLeft = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final dir = await getApplicationSupportDirectory();
    await fcn.FastCachedImageConfig.init(
      subDir: '${dir.path}/fcn_bench',
      clearCacheAfter: const Duration(days: 7),
    );

    final valid = await _validateUrls(testImages);
    setState(() {
      _urls = valid;
      _initialized = true;
      _status = '${valid.length}/${testImages.length} URLs valid. Ready.';
    });
  }

  Future<List<String>> _validateUrls(List<String> urls) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    final valid = <String>[];
    for (final url in urls) {
      try {
        final req = await client.headUrl(Uri.parse(url));
        final res = await req.close();
        await res.drain<void>();
        if (res.statusCode == 200) valid.add(url);
      } catch (_) {}
    }
    client.close();
    return valid;
  }

  // ─── Benchmark logic ─────────────────────────────────────────────

  Future<List<Duration>> _benchOurs(List<String> urls) async {
    final durations = <Duration>[];
    for (final url in urls) {
      final sw = Stopwatch()..start();
      await ZeroCacheManager.instance.getFilePath(url);
      sw.stop();
      durations.add(sw.elapsed);
    }
    return durations;
  }

  Future<List<Duration>> _benchFcn(List<String> urls) async {
    final durations = <Duration>[];
    for (final url in urls) {
      final sw = Stopwatch()..start();
      final provider = fcn.FastCachedImageProvider(url);
      final stream = provider.resolve(ImageConfiguration.empty);
      final completer = Completer<void>();
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, sync) {
          if (!completer.isCompleted) completer.complete();
          stream.removeListener(listener);
        },
        onError: (error, stack) {
          if (!completer.isCompleted) completer.complete();
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {},
      );
      sw.stop();
      durations.add(sw.elapsed);
    }
    return durations;
  }

  Future<void> _runBenchmark() async {
    setState(() {
      _running = true;
      _oursCold = _oursHot = _fcnCold = _fcnHot = null;
      _status = 'Clearing caches...';
    });

    try {
      // Cold: ours
      await ZeroCacheManager.instance.clear();
      setState(() => _status = 'zero_cached_image — cold...');
      final oursCold = await _benchOurs(_urls);
      setState(() {
        _oursCold = BenchmarkResult(
            package: PackageId.ours, phase: 'cold', perImage: oursCold);
      });

      // Cold: fcn
      await fcn.FastCachedImageConfig.clearAllCachedImages();
      setState(() => _status = 'fast_cached_network_image — cold...');
      final fcnCold = await _benchFcn(_urls);
      setState(() {
        _fcnCold = BenchmarkResult(
            package: PackageId.fcn, phase: 'cold', perImage: fcnCold);
      });

      // Hot: ours (repopulate then measure)
      await ZeroCacheManager.instance.clear();
      await _benchOurs(_urls);
      setState(() => _status = 'zero_cached_image — hot...');
      final oursHot = await _benchOurs(_urls);
      setState(() {
        _oursHot = BenchmarkResult(
            package: PackageId.ours, phase: 'hot', perImage: oursHot);
      });

      // Hot: fcn (repopulate then measure)
      await fcn.FastCachedImageConfig.clearAllCachedImages();
      await _benchFcn(_urls);
      setState(() => _status = 'fast_cached_network_image — hot...');
      final fcnHot = await _benchFcn(_urls);
      setState(() {
        _fcnHot = BenchmarkResult(
            package: PackageId.fcn, phase: 'hot', perImage: fcnHot);
        _status = 'Done!';
        _running = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _running = false;
      });
    }
  }

  // ─── UI ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Cache Benchmark'),
        actions: [
          if (_initialized && !_running)
            TextButton.icon(
              onPressed: _runBenchmark,
              icon: const Icon(Icons.speed, size: 18),
              label: const Text('RUN BENCH'),
            ),
        ],
      ),
      body: !_initialized
          ? Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(_status),
              ],
            ))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status
                  if (_running)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(children: [
                        const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(_status),
                      ]),
                    ),

                  // Results table
                  if (_oursCold != null) _buildResultsTable(),

                  const SizedBox(height: 16),

                  // ── Reload both button ──
                  ElevatedButton.icon(
                    onPressed: () async {
                      // Clear both caches, then rebuild all images
                      await ZeroCacheManager.instance.clear();
                      await fcn.FastCachedImageConfig.clearAllCachedImages();
                      // Also evict from Flutter's in-memory ImageCache
                      PaintingBinding.instance.imageCache.clear();
                      PaintingBinding.instance.imageCache.clearLiveImages();
                      setState(() => _reloadKey++);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('CLEAR CACHES & RELOAD ALL'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // ── Reload only (keep caches) ──
                  ElevatedButton.icon(
                    onPressed: () {
                      PaintingBinding.instance.imageCache.clear();
                      PaintingBinding.instance.imageCache.clearLiveImages();
                      setState(() => _reloadKey++);
                    },
                    icon: const Icon(Icons.replay),
                    label: const Text('RELOAD (cached)'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // ── Swap sides ──
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _oursOnLeft = !_oursOnLeft),
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: Text(_oursOnLeft
                        ? 'SWAP (ours is LEFT)'
                        : 'SWAP (ours is RIGHT)'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Visual comparison: side by side ──
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _oursOnLeft ? _oursColumn() : _fcnColumn(),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _oursOnLeft ? _fcnColumn() : _oursColumn(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _oursColumn() => _buildImageColumn(
    title: 'zero_cached_image (ours)',
    color: Colors.greenAccent,
    reloadKey: _reloadKey,
    buildImage: (url, key) => ZeroCachedImage(
      key: ValueKey('ours_${key}_$url'),
      imageUrl: url,
      width: double.infinity,
      height: 80,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 300),
      placeholder: (_, __) => _placeholder(),
      errorWidget: (_, __, ___) => _errorWidget(),
    ),
  );

  Widget _fcnColumn() => _buildImageColumn(
    title: 'fast_cached_network_image',
    color: Colors.orangeAccent,
    reloadKey: _reloadKey,
    buildImage: (url, key) => fcn.FastCachedImage(
      key: ValueKey('fcn_${key}_$url'),
      url: url,
      width: double.infinity,
      height: 80,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 300),
      loadingBuilder: (context, progress) => _placeholder(),
      errorBuilder: (context, error, stack) => _errorWidget(),
    ),
  );

  Widget _buildImageColumn({
    required String title,
    required Color color,
    required int reloadKey,
    required Widget Function(String url, int key) buildImage,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(width: 10, height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _urls.length; i++) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: buildImage(_urls[i], reloadKey),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildResultsTable() {
    final allResults = [_oursCold, _fcnCold, _oursHot, _fcnHot]
        .whereType<BenchmarkResult>()
        .toList();
    final cold = allResults.where((r) => r.phase == 'cold').toList();
    final hot = allResults.where((r) => r.phase == 'hot').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cold.isNotEmpty) _phaseTable('COLD (network download)', cold),
        if (hot.isNotEmpty) ...[
          const SizedBox(height: 12),
          _phaseTable('HOT (cache hit)', hot),
        ],
        if (hot.length == 2) ...[
          const SizedBox(height: 12),
          _summaryCard(hot),
        ],
      ],
    );
  }

  Widget _phaseTable(String title, List<BenchmarkResult> results) {
    final fastest =
        results.reduce((a, b) => a.totalTime < b.totalTime ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2.5),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1),
              },
              children: [
                TableRow(children: [
                  _cell('Package', header: true),
                  _cell('Total', header: true),
                  _cell('Avg/img', header: true),
                  _cell('Median', header: true),
                ]),
                for (final r in results)
                  TableRow(
                    decoration: r == fastest
                        ? BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.12))
                        : null,
                    children: [
                      _cell(_shortName(r.package), win: r == fastest),
                      _cell(_fmtDuration(r.totalTime), win: r == fastest),
                      _cell(_fmtMs(r.avgMs), win: r == fastest),
                      _cell(_fmtMs(r.medianMs), win: r == fastest),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(List<BenchmarkResult> hot) {
    final ours = hot.firstWhere((r) => r.package == PackageId.ours);
    final other = hot.firstWhere((r) => r.package == PackageId.fcn);

    // Use microseconds for hot loads — milliseconds are too coarse
    final oursUs = ours.perImage.map((d) => d.inMicroseconds).reduce((a, b) => a + b) / ours.perImage.length;
    final otherUs = other.perImage.map((d) => d.inMicroseconds).reduce((a, b) => a + b) / other.perImage.length;

    String hotLine;
    if (oursUs < 1 && otherUs < 1) {
      hotLine = 'Hot: Both sub-microsecond (too fast to measure)';
    } else if (oursUs == 0) {
      hotLine = 'Hot: zero_cached_image < 1us, fast_cached_network_image ${otherUs.toStringAsFixed(0)}us';
    } else {
      final ratio = otherUs / oursUs;
      hotLine = ratio >= 1
          ? 'Hot: zero_cached_image is ${ratio.toStringAsFixed(1)}x faster (${oursUs.toStringAsFixed(0)}us vs ${otherUs.toStringAsFixed(0)}us avg)'
          : 'Hot: zero_cached_image is ${(1 / ratio).toStringAsFixed(1)}x slower (${oursUs.toStringAsFixed(0)}us vs ${otherUs.toStringAsFixed(0)}us avg)';
    }

    // Cold comparison
    String coldLine = '';
    if (_oursCold != null && _fcnCold != null) {
      final coldRatio = _fcnCold!.avgMs / _oursCold!.avgMs;
      coldLine = 'Cold: zero_cached_image is ${coldRatio.toStringAsFixed(1)}x faster '
          '(${_oursCold!.avgMs.toStringAsFixed(0)}ms vs ${_fcnCold!.avgMs.toStringAsFixed(0)}ms avg)';
    }

    return Card(
      color: Colors.blueGrey.shade900,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (coldLine.isNotEmpty)
              Text(coldLine,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            if (coldLine.isNotEmpty) const SizedBox(height: 6),
            Text(hotLine,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  /// Format milliseconds — show microseconds when < 1ms
  String _fmtMs(double ms) {
    if (ms >= 1) return '${ms.toStringAsFixed(1)}ms';
    return '${(ms * 1000).toStringAsFixed(0)}us';
  }

  /// Format Duration — use ms or us depending on magnitude
  String _fmtDuration(Duration d) {
    if (d.inMilliseconds >= 1) return '${d.inMilliseconds}ms';
    return '${d.inMicroseconds}us';
  }

  String _shortName(PackageId id) =>
      id == PackageId.ours ? 'zero_cached_image' : 'fast_cached_network_image';

  Widget _cell(String text, {bool header = false, bool win = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: Text(text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: (header || win) ? FontWeight.bold : FontWeight.normal,
            color: header
                ? Colors.grey.shade400
                : win
                    ? Colors.greenAccent
                    : null,
          )),
    );
  }

  Widget _placeholder() => Container(
      color: Colors.red.shade900,
      child: const Center(
          child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))));

  Widget _errorWidget() => Container(
      color: Colors.red.shade900,
      child: const Center(child: Icon(Icons.broken_image, size: 20)));
}
