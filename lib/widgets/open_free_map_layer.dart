import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

// The map background, drawn from OpenFreeMap vector tiles.
// It goes inside FlutterMap(children: [...]) in place of a TileLayer.
//
// Light mode uses the "positron" style, dark mode uses the "dark" style.
// If the style cannot be downloaded (no internet, server down), it falls back
// to the normal OpenStreetMap picture tiles so the map is never empty.
class OpenFreeMapLayer extends StatefulWidget {
  const OpenFreeMapLayer({super.key, required this.isDark});

  final bool isDark;

  @override
  State<OpenFreeMapLayer> createState() => _OpenFreeMapLayerState();
}

class _OpenFreeMapLayerState extends State<OpenFreeMapLayer> {
  static const _lightStyleUrl = 'https://tiles.openfreemap.org/styles/positron';
  static const _darkStyleUrl = 'https://tiles.openfreemap.org/styles/dark';

  // Styles are downloaded once per URL. Switching between light and dark
  // reuses the saved result instead of downloading again.
  final Map<String, Future<Style>> _styles = {};

  Future<Style> _styleFor(String url) {
    return _styles.putIfAbsent(url, () => StyleReader(uri: url).read());
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.isDark ? _darkStyleUrl : _lightStyleUrl;

    return FutureBuilder<Style>(
      future: _styleFor(url),
      builder: (context, snapshot) {
        final style = snapshot.data;
        if (style != null) {
          return VectorTileLayer(
            // The key makes Flutter rebuild the layer when the style changes.
            key: ValueKey(url),
            theme: style.theme,
            sprites: style.sprites,
            tileProviders: style.providers,
          );
        }
        if (snapshot.hasError) {
          return TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.ridesync',
            tileBuilder: widget.isDark ? darkModeTileBuilder : null,
          );
        }
        // Still downloading the style: draw nothing for a moment.
        return const SizedBox.shrink();
      },
    );
  }
}
