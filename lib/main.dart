import 'package:flutter/material.dart';
import 'package:ridesync/screens/home_screen.dart';
import 'package:ridesync/theme/app_theme.dart';

void main() {
  runApp(const RideSyncApp());
}

class RideSyncApp extends StatefulWidget {
  const RideSyncApp({super.key, this.initialThemeMode = ThemeMode.system});

  final ThemeMode initialThemeMode;

  @override
  State<RideSyncApp> createState() => _RideSyncAppState();
}

class _RideSyncAppState extends State<RideSyncApp> {
  late ThemeMode _themeMode = widget.initialThemeMode;

  void _setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RideSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      home: HomeScreen(
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
      ),
    );
  }
}
