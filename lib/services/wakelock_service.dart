import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// Keeps the screen awake during active rides on mobile handlebars, and releases
// cleanly when idle or backgrounded.
class WakelockService {
  const WakelockService();

  Future<void> setEnabled(bool enabled) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      await WakelockPlus.toggle(enable: enabled);
    } on MissingPluginException {
      // Ignore in headless tests.
    } on UnsupportedError {
      // Ignore on unsupported platforms.
    } on Exception {
      // Ignore platform errors.
    }
  }
}
