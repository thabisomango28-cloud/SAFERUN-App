import 'package:demo1/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'login_screen.dart';
import 'home_screen.dart';
import 'permissions_screen.dart';

/// Decides what the user sees at launch:
///   signed out              -> LoginScreen
///   signed in, new user     -> PermissionsScreen (POPIA + onboarding flow)
///   signed in, finished     -> BiometricGate -> HomeScreen
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().authState,
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!authSnap.hasData) {
          return const LoginScreen();
        }

        // Signed in — now check whether onboarding is done.
        return StreamBuilder<bool>(
          stream: AuthService().onboardingCompleteStream(),
          builder: (context, onbSnap) {
            if (!onbSnap.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final done = onbSnap.data!;
            if (!done) {
              // First time: walk them through POPIA -> contacts -> PINs.
              return const PermissionsScreen();
            }
            return const BiometricGate(child: HomeScreen());
          },
        );
      },
    );
  }
}

/// Locks the app behind fingerprint/face if the user enabled it.
class BiometricGate extends StatefulWidget {
  final Widget child;
  const BiometricGate({super.key, required this.child});

  @override
  State<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends State<BiometricGate> {
  final _auth = AuthService();
  bool _unlocked = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _unlock();
  }

  Future<void> _unlock() async {
    setState(() => _checking = true);
    if (!await _auth.isBiometricEnabled()) {
      setState(() {
        _unlocked = true;
        _checking = false;
      });
      return;
    }
    final ok = await _auth.authenticateWithBiometrics();
    if (!mounted) return;
    setState(() {
      _unlocked = ok;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    return Scaffold(
      body: Center(
        child: _checking
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.fingerprint, size: 72),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _unlock,
                    child: const Text('Try again'),
                  ),
                  TextButton(
                    onPressed: _auth.logout,
                    child: const Text('Log in with password instead'),
                  ),
                ],
              ),
      ),
    );
  }
}
