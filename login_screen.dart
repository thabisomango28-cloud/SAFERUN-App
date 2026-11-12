import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// One screen for both login and registration (toggled with a button).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _auth = AuthService();

  bool _isRegister = false;
  bool _loading = false;
  bool _hidePassword = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final error = _isRegister
        ? await _auth.register(
            name: _name.text,
            email: _email.text,
            password: _password.text,
          )
        : await _auth.login(email: _email.text, password: _password.text);

    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      _snack(error);
      return;
    }
    // On success, AuthGate reacts to the auth stream and navigates for us.
    await _offerBiometrics();
  }

  Future<void> _google() async {
    setState(() => _loading = true);
    final error = await _auth.signInWithGoogle();
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) {
      _snack(error);
      return;
    }
    await _offerBiometrics();
  }

  /// After a successful sign-in, offer fingerprint/face unlock for next time.
  Future<void> _offerBiometrics() async {
    if (!await _auth.biometricsAvailable()) return;
    if (await _auth.isBiometricEnabled()) return;
    if (!mounted) return;

    final enable = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enable biometric unlock?'),
        content: const Text(
          'Use your fingerprint or face to open SafeRun quickly.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    if (enable == true) await _auth.setBiometricEnabled(true);
  }

  Future<void> _forgotPassword() async {
    if (_email.text.trim().isEmpty) {
      _snack('Enter your email first.');
      return;
    }
    final error = await _auth.sendPasswordReset(_email.text);
    _snack(error ?? 'Password reset email sent.');
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.12),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Icon(
                      Icons.shield,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'SafeRun',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 32),
                    if (_isRegister) ...[
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Enter your name'
                            : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Enter a valid email'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: _hidePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () =>
                              setState(() => _hidePassword = !_hidePassword),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 6)
                          ? 'At least 6 characters'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_isRegister ? 'Create account' : 'Log in'),
                      ),
                    ),
                    if (!_isRegister)
                      TextButton(
                        onPressed: _forgotPassword,
                        child: const Text('Forgot password?'),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: const [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('or'),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _google,
                        icon: const Icon(Icons.g_mobiledata, size: 32),
                        label: const Text('Continue with Google'),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _isRegister = !_isRegister),
                      child: Text(
                        _isRegister
                            ? 'Already have an account? Log in'
                            : 'New here? Create an account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
