import 'package:flutter/material.dart';
import 'package:ridesync/screens/wip_screen.dart';

// The first screen of the app. It has three options. Each one opens a
// work-in-progress page until we build the real screen.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  // Opens a WipScreen on top of this screen. The back button comes for free.
  void _openWip(BuildContext context, String title, String plan) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => WipScreen(title: title, plan: plan),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The colors come from our theme, so this works in light and dark mode.
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      // SafeArea keeps everything away from the notch and the bottom bar.
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            // Center the column vertically, and stretch the buttons across.
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.two_wheeler, size: 96, color: colors.primary),
              const SizedBox(height: 16),
              Text(
                'RideSync',
                textAlign: TextAlign.center,
                style: textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Live group ride tracking',
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge,
              ),
              const SizedBox(height: 48),

              // Option 1: start a new ride and get a code to share.
              // Button size and shape come from the theme (app_theme.dart).
              FilledButton.icon(
                onPressed: () => _openWip(
                  context,
                  'Host a ride',
                  'Create a ride and get a code to share with your group.',
                ),
                icon: const Icon(Icons.add_road),
                label: const Text('Host a ride'),
              ),
              const SizedBox(height: 12),

              // Option 2: join someone else's ride with their code.
              OutlinedButton.icon(
                onPressed: () => _openWip(
                  context,
                  'Join with a code',
                  'Enter the code from the host to join their ride.',
                ),
                icon: const Icon(Icons.group_add),
                label: const Text('Join with a code'),
              ),
              const SizedBox(height: 12),

              // Option 3: accounts. This comes later, after the main screens.
              TextButton.icon(
                onPressed: () => _openWip(
                  context,
                  'Sign up',
                  'Create an account and log in. Currently WIP',
                ),
                icon: const Icon(Icons.person_add),
                label: const Text('Sign up or log in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
