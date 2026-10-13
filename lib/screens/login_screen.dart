// Login / Sign-up screen — alpha preview, no real auth.
// StatefulWidget because mode (_isLogin) and password visibility can change.

import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLogin = true;        // toggles between Login and Sign Up
  bool _obscurePassword = true; // hides/shows password text

  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();

  void _onContinueTapped() {
    // Alpha: no real auth yet — just acknowledge the tap.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_isLogin ? 'Login' : 'Sign-up'} coming soon 🚀'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(_isLogin ? 'Log In' : 'Sign Up')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.two_wheeler, size: 72, color: colors.primary),
            const SizedBox(height: 12),
            Text(
              _isLogin ? 'Welcome back' : 'Create an account',
              textAlign: TextAlign.center,
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 32),

            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword, // true = show dots
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outlined),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  // Toggle the password visibility with setState.
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 28),

            FilledButton(
              onPressed: _onContinueTapped,
              child: Text(_isLogin ? 'Log In' : 'Sign Up'),
            ),
            const SizedBox(height: 16),

            // Switches between Log In and Sign Up mode.
            TextButton(
              onPressed: () => setState(() => _isLogin = !_isLogin),
              child: Text(
                _isLogin
                    ? "Don't have an account?  Sign up"
                    : 'Already have an account?  Log in',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
