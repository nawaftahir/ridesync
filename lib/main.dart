import 'package:flutter/material.dart';
import 'package:ridesync/screens/home_screen.dart';
import 'package:ridesync/theme/app_theme.dart';

void main() {
  runApp(const RideSyncApp());
}

class RideSyncApp extends StatelessWidget {
  const RideSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RideSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Follow the phone: light when the phone is light, dark when it is dark.
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
