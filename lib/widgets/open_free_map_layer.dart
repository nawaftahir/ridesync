import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:vector_map_tiles/vector_map_tiles.dart';

// Map background drawn from OpenFreeMap vector tiles.
// Light mode uses "positron", dark mode uses "dark".
// Each mode gets its own theme ID so light and dark disk/memory tile caches
// never collide, and all requests share one keep-alive HTTP client for speed.
class OpenFreeMapLayer extends StatefulWidget {
  const OpenFreeMapLayer({super.key, required this.isDark});

  final bool isDark;

  @visibleForTesting
  static void clearCacheForTest() {
    _OpenFreeMapLayerState.clearCacheForTest();
  }

  @override
  State<OpenFreeMapLayer> createState() => _OpenFreeMapLayerState();
}

class _OpenFreeMapLayerState extends State<OpenFreeMapLayer>
    with WidgetsBindingObserver {
  static const _lightStyleUrl = 'https://tiles.openfreemap.org/styles/positron';
  static const _darkStyleUrl = 'https://tiles.openfreemap.org/styles/dark';
  static const _lightThemeId = 'openfreemap-light';
  static const _darkThemeId = 'openfreemap-dark';
  static const _requestTimeout = Duration(seconds: 10);

  // Shared HTTP client and parsed style cache kept across theme switches and tabs.
  static http.Client? _sharedClient;
  static final Map<String, Style> _styleCache = {};
  static final Map<String, Future<Style?>> _inFlightLoads = {};

  static http.Client get _httpClient => _sharedClient ??= http.Client();

  static void clearCacheForTest() {
    _styleCache.clear();
    _inFlightLoads.clear();
    _sharedClient?.close();
    _sharedClient = null;
  }

  bool _loadFailed = false;

  String get _currentUrl => _urlFor(widget.isDark);

  static String _urlFor(bool isDark) => isDark ? _darkStyleUrl : _lightStyleUrl;

  static String _themeIdFor(bool isDark) =>
      isDark ? _darkThemeId : _lightThemeId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startLoadIfNeeded();
  }

  @override
  void didUpdateWidget(covariant OpenFreeMapLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDark != widget.isDark) {
      _startLoadIfNeeded();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_styleCache.containsKey(_currentUrl)) {
      _startLoadIfNeeded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startLoadIfNeeded() {
    final isDark = widget.isDark;
    final url = _urlFor(isDark);
    if (_styleCache.containsKey(url)) {
      if (_loadFailed) {
        setState(() => _loadFailed = false);
      }
      _prefetchOppositeStyle(isDark);
      return;
    }

    if (_loadFailed) {
      setState(() => _loadFailed = false);
    }

    unawaited(_fetchAndApply(url: url, isDark: isDark));
  }

  Future<void> _fetchAndApply({
    required String url,
    required bool isDark,
  }) async {
    final style = await _loadStyle(url: url, isDark: isDark);
    if (!mounted || url != _currentUrl) return;
    if (style != null) {
      setState(() => _loadFailed = false);
      // Preload the other theme silently so switching Light/Dark is instant.
      _prefetchOppositeStyle(isDark);
    } else {
      setState(() => _loadFailed = true);
    }
  }

  void _prefetchOppositeStyle(bool currentIsDark) {
    final otherIsDark = !currentIsDark;
    final otherUrl = _urlFor(otherIsDark);
    if (_styleCache.containsKey(otherUrl) ||
        _inFlightLoads.containsKey(otherUrl)) {
      return;
    }
    unawaited(_loadStyle(url: otherUrl, isDark: otherIsDark));
  }

  static Future<Style?> _loadStyle({
    required String url,
    required bool isDark,
  }) {
    final cached = _styleCache[url];
    if (cached != null) return Future.value(cached);

    return _inFlightLoads.putIfAbsent(url, () async {
      try {
        // Parse theme & sprites with StyleReader and resolve pooled vector
        // source URLs in parallel so every .pbf tile reuses keep-alive HTTP.
        final styleFuture = StyleReader(uri: url)
            .read()
            .timeout(_requestTimeout);
        final providersFuture = _resolvePooledProviders(url);
        final rawStyle = await styleFuture;
        final pooledProviders = await providersFuture;

        final themedId = rawStyle.theme.copyWith(id: _themeIdFor(isDark));
        final activeSources = themedId.tileSources;

        // Only pass providers used by active layers (skips unused ne2_shaded).
        final filteredProviders = <String, VectorTileProvider>{};
        for (final source in activeSources) {
          final provider =
              pooledProviders[source] ??
              rawStyle.providers.tileProviderBySource[source];
          if (provider != null) {
            filteredProviders[source] = provider;
          }
        }

        final style = Style(
          name: rawStyle.name,
          theme: themedId,
          providers: TileProviders(filteredProviders),
          sprites: rawStyle.sprites,
          center: rawStyle.center,
          zoom: rawStyle.zoom,
        );
        _styleCache[url] = style;
        return style;
      } catch (_) {
        return null;
      } finally {
        unawaited(Future.microtask(() => _inFlightLoads.remove(url)));
      }
    });
  }

  static Future<Map<String, VectorTileProvider>> _resolvePooledProviders(
    String styleUrl,
  ) async {
    final providers = <String, VectorTileProvider>{};
    try {
      final styleJson = await _getJson(styleUrl);
      final sources = styleJson['sources'];
      if (sources is! Map) return providers;

      for (final entry in sources.entries) {
        final value = entry.value;
        if (value is! Map || value['type'] != 'vector') continue;

        Map<String, dynamic> sourceSpec;
        final inlineTiles = value['tiles'];
        final sourceUrl = value['url'];
        if (inlineTiles is List && inlineTiles.isNotEmpty) {
          sourceSpec = Map<String, dynamic>.from(value);
        } else if (sourceUrl is String && sourceUrl.isNotEmpty) {
          final resolved = Uri.parse(styleUrl).resolve(sourceUrl).toString();
          sourceSpec = await _getJson(resolved);
        } else {
          continue;
        }

        final tiles = sourceSpec['tiles'];
        if (tiles is! List || tiles.isEmpty) continue;
        final template = tiles.first;
        if (template is! String || template.isEmpty) continue;

        providers[entry.key.toString()] = _PooledVectorTileProvider(
          client: _httpClient,
          urlTemplate: template,
          minimumZoom: (sourceSpec['minzoom'] as num?)?.toInt() ?? 0,
          maximumZoom: (sourceSpec['maxzoom'] as num?)?.toInt() ?? 14,
        );
      }
    } catch (_) {
      // Fall back cleanly to StyleReader's built-in providers if parsing fails.
    }
    return providers;
  }

  static Future<Map<String, dynamic>> _getJson(String url) async {
    final response = await _httpClient
        .get(Uri.parse(url), headers: const {'User-Agent': 'ridesync'})
        .timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected JSON object');
    }
    return decoded;
  }

  @override
  Widget build(BuildContext context) {
    final style = _styleCache[_currentUrl];

    if (style != null) {
      return VectorTileLayer(
        theme: style.theme,
        sprites: style.sprites,
        tileProviders: style.providers,
        concurrency: 4,
        memoryTileDataCacheMaxSize: 80,
        memoryTileCacheMaxSize: 32 * 1024 * 1024,
        textCacheMaxSize: 300,
        fileCacheMaximumSizeInBytes: 150 * 1024 * 1024,
      );
    }

    if (_loadFailed) {
      return TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.example.ridesync',
        tileBuilder: widget.isDark ? darkModeTileBuilder : null,
      );
    }

    // Match the OpenFreeMap canvas color while the initial style finishes loading.
    return ColoredBox(
      color: widget.isDark ? const Color(0xFF0C0C0C) : const Color(0xFFF2F3F0),
    );
  }
}

// Reuses one HTTP client across tile requests so each tile avoids a new TLS
// handshake while supporting timeout and a quick retry on transient errors.
class _PooledVectorTileProvider extends VectorTileProvider {
  _PooledVectorTileProvider({
    required this.client,
    required this.urlTemplate,
    required this.minimumZoom,
    required this.maximumZoom,
  });

  final http.Client client;
  final String urlTemplate;

  @override
  final int minimumZoom;

  @override
  final int maximumZoom;

  @override
  TileOffset tileOffset = TileOffset.DEFAULT;

  static const _tileTimeout = Duration(seconds: 10);

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    if (tile.z > maximumZoom || tile.z < minimumZoom || !tile.isValid()) {
      throw ProviderException(
        message: 'Invalid tile coordinates $tile',
        retryable: Retryable.none,
        statusCode: 400,
      );
    }

    final uri = Uri.parse(
      urlTemplate
          .replaceAll('{z}', '${tile.z}')
          .replaceAll('{x}', '${tile.x}')
          .replaceAll('{y}', '${tile.y}'),
    );

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await client
            .get(uri, headers: const {'User-Agent': 'ridesync'})
            .timeout(_tileTimeout);
        if (response.statusCode == 200) {
          return response.bodyBytes;
        }
        final shouldRetry =
            attempt == 0 &&
            (response.statusCode == 408 || response.statusCode == 503);
        if (shouldRetry) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          continue;
        }
        throw ProviderException(
          message: 'HTTP ${response.statusCode} for $uri',
          statusCode: response.statusCode,
          retryable: Retryable.none,
        );
      } on TimeoutException catch (e) {
        if (attempt == 0) continue;
        throw ProviderException(
          message: e.toString(),
          retryable: Retryable.retry,
        );
      } on http.ClientException catch (e) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          continue;
        }
        throw ProviderException(message: e.message, retryable: Retryable.retry);
      }
    }

    throw ProviderException(
      message: 'Failed to load tile $tile',
      retryable: Retryable.retry,
    );
  }
}
