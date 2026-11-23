import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Reads the phone's live battery percentage on mobile devices (returns null
// safely on desktop/web/headless tests where mobile battery channels are absent).
class BatteryService {
  const BatteryService();

  Future<int?> getBatteryPercent() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return null;
    }
    try {
      final level = await Battery().batteryLevel;
      if (level < 0 || level > 100) return null;
      return level;
    } on MissingPluginException {
      return null;
    } on UnsupportedError {
      return null;
    } on Exception {
      return null;
    }
  }
}
