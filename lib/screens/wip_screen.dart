import 'package:flutter/material.dart';

// A placeholder page for screens we have not built yet. When a real screen is
// ready, we swap this out for it in one place (see home_screen.dart).
class WipScreen extends StatelessWidget {
  const WipScreen({super.key, required this.title, required this.plan});

  // The name shown in the app bar, for example "Host a ride".
  final String title;

  // One sentence about what this screen will do.
  final String plan;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            // Only as tall as the content, so Center can put it in the middle.
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction, size: 64, color: colors.tertiary),
              const SizedBox(height: 16),
              Text('Work in progress', style: textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(plan, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
