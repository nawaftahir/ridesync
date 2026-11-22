import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

typedef RideShareHandler = Future<void> Function(String text, String subject);

// Builds a short, WhatsApp-friendly invite message for a convoy ride.
String buildRideInviteText({
  required String code,
  required String destination,
}) {
  final cleanCode = code.trim().toUpperCase();
  final cleanDest = destination.trim();
  if (cleanDest.isEmpty) {
    return 'Join my RideSync convoy!\nRide code: $cleanCode';
  }
  return 'Join my RideSync convoy to $cleanDest!\nRide code: $cleanCode';
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

// Opens the native Android/iOS share sheet with the ride invite text.
Future<void> shareRideInvite({
  required String code,
  required String destination,
  RideShareHandler? onShareOverride,
}) async {
  final cleanCode = code.trim().toUpperCase();
  final text = buildRideInviteText(code: cleanCode, destination: destination);
  final subject = 'RideSync convoy code: $cleanCode';
  if (onShareOverride != null) {
    await onShareOverride(text, subject);
    return;
  }
  await SharePlus.instance.share(ShareParams(text: text, subject: subject));
}
