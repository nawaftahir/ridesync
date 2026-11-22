import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ridesync/services/app_preferences.dart';
import 'package:share_plus/share_plus.dart';

typedef RideShareHandler = Future<void> Function(String text, String subject);

final RegExp _validRideCodePattern = RegExp(r'^[A-Z0-9]{4,10}$');

// Builds a direct clickable HTTPS invite URL when a server URL is configured,
// falling back to ridesync://join/<CODE> only if no server URL is available.
String buildRideJoinUrl({required String code, String? serverBaseUrl}) {
  final cleanCode = code.trim().toUpperCase();
  final rawBase = (serverBaseUrl != null && serverBaseUrl.trim().isNotEmpty)
      ? serverBaseUrl.trim()
      : AppPreferences.buildApiBaseUrl.trim();

  var base = rawBase;
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }

  final parsed = Uri.tryParse(base);
  if (parsed != null &&
      (parsed.scheme == 'http' || parsed.scheme == 'https') &&
      parsed.host.isNotEmpty) {
    var normalizedBase = parsed.toString();
    while (normalizedBase.endsWith('/')) {
      normalizedBase = normalizedBase.substring(0, normalizedBase.length - 1);
    }
    return '$normalizedBase/join/$cleanCode';
  }
  return 'ridesync://join/$cleanCode';
}

// Extracts an uppercase ride code from `ridesync://join/CODE` or `https://.../join/CODE`.
String? parseRideCodeFromUri(Uri uri) {
  String? rawCode;
  final scheme = uri.scheme.toLowerCase();
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

  if (scheme == 'ridesync') {
    if (uri.host.toLowerCase() == 'join') {
      rawCode = segments.isNotEmpty
          ? segments.first
          : uri.queryParameters['code'];
    } else if (segments.length >= 2 && segments.first.toLowerCase() == 'join') {
      rawCode = segments[1];
    }
  } else if (scheme == 'http' || scheme == 'https') {
    if (segments.length >= 2 && segments.first.toLowerCase() == 'join') {
      rawCode = segments[1];
    } else if (segments.length == 1 && segments.first.toLowerCase() == 'join') {
      rawCode = uri.queryParameters['code'];
    }
  }

  if (rawCode == null) return null;
  final normalized = rawCode.trim().toUpperCase();
  return _validRideCodePattern.hasMatch(normalized) ? normalized : null;
}

// Keeps invite text clean by dropping verbose comma-separated map address suffixes.
String _shortInviteDestination(String destination) {
  final trimmed = destination.trim();
  if (trimmed.isEmpty) return '';
  final commaIndex = trimmed.indexOf(',');
  if (commaIndex > 0) {
    return trimmed.substring(0, commaIndex).trim();
  }
  return trimmed;
}

// Builds a clean, WhatsApp-friendly invite message with a direct clickable link.
String buildRideInviteText({
  required String code,
  required String destination,
  String? serverBaseUrl,
}) {
  final cleanCode = code.trim().toUpperCase();
  final shortDest = _shortInviteDestination(destination);
  final joinUrl = buildRideJoinUrl(
    code: cleanCode,
    serverBaseUrl: serverBaseUrl,
  );
  final header = shortDest.isEmpty
      ? 'Join my RideSync convoy!'
      : 'Join my RideSync convoy to $shortDest!';
  return '$header\n$joinUrl\nRide code: $cleanCode';
}

// Copies the join code to the system clipboard and confirms with a SnackBar.
Future<void> copyRideCode(BuildContext context, String code) async {
  final cleanCode = code.trim().toUpperCase();
  await Clipboard.setData(ClipboardData(text: cleanCode));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Copied ride code $cleanCode'),
        duration: const Duration(seconds: 2),
      ),
    );
}

// Opens the native Android/iOS share sheet with the ride invite link and code.
Future<void> shareRideInvite({
  required String code,
  required String destination,
  String? serverBaseUrl,
  RideShareHandler? onShareOverride,
}) async {
  final cleanCode = code.trim().toUpperCase();
  final text = buildRideInviteText(
    code: cleanCode,
    destination: destination,
    serverBaseUrl: serverBaseUrl,
  );
  final subject = 'RideSync convoy code: $cleanCode';
  if (onShareOverride != null) {
    await onShareOverride(text, subject);
    return;
  }
  await SharePlus.instance.share(ShareParams(text: text, subject: subject));
}
