import 'package:flutter/material.dart';
import 'package:ridesync/models/auth_session.dart';
import 'package:ridesync/services/app_preferences.dart';
import 'package:ridesync/services/ride_api_service.dart';

// Real Log In / Sign Up screen wired to FastAPI (/auth/login, /auth/register).
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.apiService,
    this.initialIsLogin = true,
    this.preferences,
  });

  final RideApiService? apiService;
  final bool initialIsLogin;
  final AppPreferences? preferences;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late bool _isLogin = widget.initialIsLogin;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  late final AppPreferences _prefs = widget.preferences ?? AppPreferences();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  Future<RideApiService> _resolveApiService() async {
    if (widget.apiService != null) {
      return widget.apiService!;
    }
    final savedUrl = await _prefs.loadServerUrl();
    final url = (savedUrl != null && savedUrl.trim().isNotEmpty)
        ? savedUrl.trim()
        : AppPreferences.buildApiBaseUrl;
    return RideApiService(baseUrl: url);
  }

  Future<void> _onContinueTapped() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (!_isLogin && name.isEmpty) {
      setState(() => _errorMessage = 'Enter your rider display name.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _errorMessage = 'Enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final ownedApi = widget.apiService == null;
    RideApiService? api;
    try {
      api = await _resolveApiService();
      if (!api.isEnabled) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Set a Backend Server URL in Profile first.';
          _isSubmitting = false;
        });
        return;
      }

      final AuthSession session = _isLogin
          ? await api.login(email: email, password: password)
          : await api.register(name: name, email: email, password: password);
      await _prefs.saveAuthSession(session);
      if (!mounted) return;
      Navigator.of(context).pop(session);
    } on RideApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _isSubmitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not sign in right now. Please try again.';
        _isSubmitting = false;
      });
    } finally {
      if (ownedApi) {
        api?.dispose();
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
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
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  Icons.two_wheeler_rounded,
                  size: 40,
                  color: colors.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _isLogin ? 'Welcome back' : 'Create your rider account',
              textAlign: TextAlign.center,
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              _isLogin
                  ? 'Sign in to sync your rider identity across convoys.'
                  : 'Keep one rider profile across every group ride.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 28),

            if (!_isLogin) ...[
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: 'Rider name',
                  prefixIcon: Icon(Icons.person_outline),
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
            ],

            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_isSubmitting) _onContinueTapped();
              },
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: _isLogin ? null : 'At least 6 characters',
                prefixIcon: const Icon(Icons.lock_outlined),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 18,
                      color: colors.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: colors.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            FilledButton(
              onPressed: _isSubmitting ? null : _onContinueTapped,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isLogin ? 'Log In' : 'Create Account'),
            ),
            const SizedBox(height: 14),

            TextButton(
              onPressed: _isSubmitting
                  ? null
                  : () {
                      setState(() {
                        _isLogin = !_isLogin;
                        _errorMessage = null;
                      });
                    },
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
