import 'package:flutter/material.dart';
import 'package:ridesync/screens/host_ride_screen.dart';
import 'package:ridesync/screens/join_ride_screen.dart';
import 'package:ridesync/screens/login_screen.dart';

// The first screen of the app.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  // A small helper to avoid repeating MaterialPageRoute boilerplate.
  void _go(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
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

              // Option 1: start a new ride → HostRideScreen.
              FilledButton.icon(
                onPressed: () => _go(context, const HostRideScreen()),
                icon: const Icon(Icons.add_road),
                label: const Text('Host a ride'),
              ),
              const SizedBox(height: 12),

              // Option 2: join with a code → JoinRideScreen.
              OutlinedButton.icon(
                onPressed: () => _go(context, const JoinRideScreen()),
                icon: const Icon(Icons.group_add),
                label: const Text('Join with a code'),
              ),
              const SizedBox(height: 12),

              // Option 3: login / sign up → LoginScreen.
              TextButton.icon(
                onPressed: () => _go(context, const LoginScreen()),
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
