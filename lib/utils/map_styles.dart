import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

// OpenFreeMap vector map styles rendered natively on the GPU by MapLibre.
// - Light mode ("liberty"): crisp roads, parks, landmarks, and 3D buildings when tilted.
// - Dark mode ("dark"): high-contrast night theme for evening rides.
class OpenFreeMapStyles {
  static const String lightStyleUrl =
      'https://tiles.openfreemap.org/styles/liberty';
  static const String darkStyleUrl =
      'https://tiles.openfreemap.org/styles/dark';

  static const Color lightCanvasColor = Color(0xFFF2F3F0);
  static const Color darkCanvasColor = Color(0xFF0C0C0C);

  static MapStyle forBrightness({required bool isDark}) =>
      MapStyle.url(isDark ? darkStyleUrl : lightStyleUrl);

  static Color canvasColor({required bool isDark}) =>
      isDark ? darkCanvasColor : lightCanvasColor;
}
