import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Handles registration, login, logout, password reset and biometric unlock.
/// Every method that can fail returns a String? error message (null = success),
/// so screens never deal with Firebase exceptions directly.
class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _localAuth = LocalAuthentication();
  final _storage = const FlutterSecureStorage();

  static const _bioKey = 'biometric_enabled';

  /// Emits the signed-in user, or null when signed out.
  Stream<User?> get authState => _auth.authStateChanges();

  Future<String?> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await cred.user!.updateDisplayName(name.trim());
      // Profile document; contacts and PIN hashes are added in later screens.
      await _db.collection('users').doc(cred.user!.uid).set({
        'name': name.trim(),
        'email': email.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'onboardingComplete':
            false, // NEW: new users must go through onboarding
      });
      return null;
    } on FirebaseAuthException catch (e) {
      return _message(e.code);
    }
  }

  Future<String?> login({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return null;
    } on FirebaseAuthException catch (e) {
      return _message(e.code);
    }
  }

  /// Google sign-in using Firebase's built-in provider flow
  /// (no extra google_sign_in package needed).
  Future<String?> signInWithGoogle() async {
    try {
      final cred = await _auth.signInWithProvider(GoogleAuthProvider());
      // First time with Google: create the profile document.
      if (cred.additionalUserInfo?.isNewUser ?? false) {
        final user = cred.user!;
        await _db.collection('users').doc(user.uid).set({
          'name': user.displayName ?? '',
          'email': user.email ?? '',
          'createdAt': FieldValue.serverTimestamp(),
          'onboardingComplete': false, // NEW
        });
      }
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'canceled' || e.code == 'web-context-canceled') {
        return 'Google sign-in was cancelled.';
      }
      return _message(e.code);
    }
  }

  Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return _message(e.code);
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: _bioKey);
    await _auth.signOut();
  }

  // ---------- Onboarding ----------

  /// Streams whether the current user has finished the onboarding flow
  /// (POPIA + permissions + trusted contacts + PINs).
  Stream<bool> onboardingCompleteStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(false);
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((snap) => (snap.data()?['onboardingComplete'] as bool?) ?? false);
  }

  /// Call this when the user finishes the last onboarding step (PIN setup).
  Future<void> markOnboardingComplete() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set({
      'onboardingComplete': true,
    }, SetOptions(merge: true));
  }

  // ---------- Biometrics ----------

  Future<bool> biometricsAvailable() async {
    final canCheck = await _localAuth.canCheckBiometrics;
    final supported = await _localAuth.isDeviceSupported();
    return canCheck && supported;
  }

  Future<bool> isBiometricEnabled() async =>
      await _storage.read(key: _bioKey) == 'true';

  Future<void> setBiometricEnabled(bool value) =>
      _storage.write(key: _bioKey, value: value.toString());

  /// Shows the fingerprint / face prompt. Returns true only if it succeeds.
  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Unlock SafeRun',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  // ---------- Error messages ----------

  String _message(String code) {
    switch (code) {
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'network-request-failed':
        return 'No internet connection. Please try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
