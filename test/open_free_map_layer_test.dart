import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ridesync/main.dart';
import 'package:ridesync/screens/main_screen.dart';
import 'package:ridesync/widgets/open_free_map_layer.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

String _styleJson(String name) =>
    '''
{
  "version": 8,
  "name": "$name",
  "sources": {
    "openmaptiles": {
      "type": "vector",
      "tiles": ["https://tiles.openfreemap.org/planet/{z}/{x}/{y}.pbf"],
      "minzoom": 0,
      "maxzoom": 14
    }
  },
  "layers": [
    {
      "id": "background",
      "type": "background",
      "paint": { "background-color": "#ffffff" }
    },
    {
      "id": "landcover",
      "type": "fill",
      "source": "openmaptiles",
      "source-layer": "landcover",
      "paint": { "fill-color": "#eeeeee" }
    }
  ]
}
''';

class _FakeHttpOverrides extends HttpOverrides {
  _FakeHttpOverrides({required this.shouldFailStyle});

  bool shouldFailStyle;
  final List<String> requestedUrls = [];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _FakeHttpClient(this);
  }
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.owner);

  final _FakeHttpOverrides owner;

  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    owner.requestedUrls.add(url.toString());
    return _FakeHttpClientRequest(url, owner.shouldFailStyle);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this.uri, this.shouldFailStyle);

  @override
  final Uri uri;
  final bool shouldFailStyle;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = -1;

  @override
  Future<HttpClientResponse> close() async {
    if (uri.path.contains('/styles/')) {
      if (shouldFailStyle) {
        return _FakeHttpClientResponse(503, utf8.encode('offline'));
      }
      final styleName = uri.path.endsWith('/dark') ? 'Dark Matter' : 'Positron';
      return _FakeHttpClientResponse(200, utf8.encode(_styleJson(styleName)));
    }
    return _FakeHttpClientResponse(200, Uint8List(0));
  }

  @override
  void add(List<int> data) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void forEach(void Function(String name, List<String> values) action) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(this.statusCode, this.bytes);

  @override
  final int statusCode;
  final List<int> bytes;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => statusCode == 200 ? 'OK' : 'Error';

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget _wrapMap({required bool isDark}) {
  return MaterialApp(
    home: Scaffold(
      body: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(33.7215, 73.0433),
          initialZoom: 14,
        ),
        children: [OpenFreeMapLayer(isDark: isDark)],
      ),
    ),
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    OpenFreeMapLayer.clearCacheForTest();
    tempDir = Directory.systemTemp.createTempSync('ridesync_map_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDown(() {
    OpenFreeMapLayer.clearCacheForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // StorageCache prunes temp files asynchronously after dispose on Windows.
      }
    }
  });

  Finder osmFallbackFinder() => find.byWidgetPredicate(
    (w) =>
        w is TileLayer &&
        w.urlTemplate == 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  Finder vectorThemeFinder(String themeId) => find.byWidgetPredicate(
    (w) => w is VectorTileLayer && w.theme.id == themeId,
  );

  Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (finder.evaluate().isNotEmpty) {
        return;
      }
    }
    expect(
      finder,
      findsAtLeastNWidgets(1),
      reason: 'Timed out waiting for $finder',
    );
  }

  Future<void> drainTileJobs(WidgetTester tester) async {
    // Fire VectorTileLayer's 3s startup timer, then poll real-time delays and
    // frame pumps until all pending tile images complete before switching themes
    // or unmounting.
    await tester.pump(const Duration(seconds: 3));
    var quietPasses = 0;
    for (var i = 0; i < 240; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (PaintingBinding.instance.imageCache.pendingImageCount == 0) {
        quietPasses++;
        if (quietPasses >= 3 && i >= 10) {
          return;
        }
      } else {
        quietPasses = 0;
      }
    }
    expect(
      PaintingBinding.instance.imageCache.pendingImageCount,
      0,
      reason: 'Timed out waiting for tile jobs to drain',
    );
  }

  Future<void> settleIsolatePool(WidgetTester tester) async {
    await drainTileJobs(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
  }

  testWidgets(
    'OpenFreeMapLayer renders vector tiles and switches light/dark styles',
    (tester) async {
      final overrides = _FakeHttpOverrides(shouldFailStyle: false);

      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(_wrapMap(isDark: false));
        await pumpUntilFound(tester, vectorThemeFinder('openfreemap-light'));

        expect(osmFallbackFinder(), findsNothing);
        expect(find.byType(VectorTileLayer), findsOneWidget);
        expect(
          overrides.requestedUrls,
          contains('https://tiles.openfreemap.org/styles/positron'),
        );

        await drainTileJobs(tester);

        await tester.pumpWidget(_wrapMap(isDark: true));
        await pumpUntilFound(tester, vectorThemeFinder('openfreemap-dark'));

        expect(osmFallbackFinder(), findsNothing);
        expect(find.byType(VectorTileLayer), findsOneWidget);
        expect(
          overrides.requestedUrls,
          contains('https://tiles.openfreemap.org/styles/dark'),
        );

        await settleIsolatePool(tester);
      }, createHttpClient: overrides.createHttpClient);
    },
  );

  testWidgets(
    'OpenFreeMapLayer falls back to OSM when offline and recovers on resume',
    (tester) async {
      final overrides = _FakeHttpOverrides(shouldFailStyle: true);

      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(_wrapMap(isDark: false));
        await pumpUntilFound(tester, osmFallbackFinder());

        expect(osmFallbackFinder(), findsOneWidget);
        expect(find.byType(VectorTileLayer), findsNothing);

        // Simulate internet returning and user returning to the app.
        overrides.shouldFailStyle = false;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumpUntilFound(tester, vectorThemeFinder('openfreemap-light'));

        expect(osmFallbackFinder(), findsNothing);
        expect(find.byType(VectorTileLayer), findsOneWidget);

        await settleIsolatePool(tester);
      }, createHttpClient: overrides.createHttpClient);
    },
  );

  testWidgets(
    'RideMapScreen keeps OpenFreeMap attribution chip visible above bottom sheet',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(home: MainScreen(initialServerUrl: '')),
      );
      await tester.pumpAndSettle();

      final chip = find.text('© OpenFreeMap · OSM');
      expect(chip, findsOneWidget);

      final chipRect = tester.getRect(chip);
      final sheetRect = tester.getRect(find.text('Group ride'));
      expect(chipRect.bottom, lessThan(sheetRect.top));
    },
  );

  testWidgets(
    'RideMapScreen zoom buttons clamp zoom to 3..18 and lock map rotation',
    (tester) async {
      await tester.pumpWidget(const RideSyncApp());
      await tester.pumpAndSettle();

      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(
        map.options.interactionOptions.flags & InteractiveFlag.rotate,
        equals(0),
      );
      expect(map.options.minZoom, equals(3));
      expect(map.options.maxZoom, equals(18));

      final controller = map.mapController!;
      expect(controller.camera.zoom, equals(14));

      // Tap zoom in repeatedly; it must stop at maxZoom (18).
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byTooltip('Zoom in'));
      }
      await tester.pumpAndSettle();
      expect(controller.camera.zoom, equals(18));

      // Tap zoom out past minZoom; it must stop at minZoom (3).
      for (var i = 0; i < 18; i++) {
        await tester.tap(find.byTooltip('Zoom out'));
      }
      await tester.pumpAndSettle();
      expect(controller.camera.zoom, equals(3));
    },
  );

  testWidgets(
    'RideMapScreen bottom sheet supports vertical swipe to collapse and expand',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: MainScreen(initialServerUrl: '')),
      );
      await tester.pumpAndSettle();

      expect(find.text('PICKUP'), findsOneWidget);

      await tester.fling(find.text('Group ride'), const Offset(0, 120), 600);
      await tester.pumpAndSettle();
      expect(find.text('PICKUP'), findsNothing);

      await tester.fling(find.text('Group ride'), const Offset(0, -120), 600);
      await tester.pumpAndSettle();
      expect(find.text('PICKUP'), findsOneWidget);
    },
  );
}
