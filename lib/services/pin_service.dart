import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Result of checking a PIN entered by the user.
/// The UI must look IDENTICAL for [normal] and [duress]:
/// both "end the session". Only the duress path silently alerts contacts.
enum PinResult { normal, duress, wrong }

class PinService {
  final _storage = const FlutterSecureStorage();

  static const _saltKey = 'pin_salt';
  static const _normalKey = 'pin_normal_hash';
  static const _duressKey = 'pin_duress_hash';
  static const _iterations = 10000;

  Future<bool> hasPins() async =>
      await _storage.read(key: _normalKey) != null &&
      await _storage.read(key: _duressKey) != null;

  /// Returns null on success, or an error message to show the user.
  Future<String?> setPins({
    required String normal,
    required String duress,
  }) async {
    final valid = RegExp(r'^\d{4,6}$');
    if (!valid.hasMatch(normal) || !valid.hasMatch(duress)) {
      return 'PINs must be 4 to 6 digits.';
    }
    if (normal == duress) {
      return 'The duress PIN must be different from your normal PIN.';
    }
    final salt = _newSalt();
    await _storage.write(key: _saltKey, value: salt);
    await _storage.write(key: _normalKey, value: _hash(normal, salt));
    await _storage.write(key: _duressKey, value: _hash(duress, salt));
    return null;
  }

  Future<PinResult> verify(String pin) async {
    final salt = await _storage.read(key: _saltKey);
    final normalHash = await _storage.read(key: _normalKey);
    final duressHash = await _storage.read(key: _duressKey);
    if (salt == null || normalHash == null || duressHash == null) {
      return PinResult.wrong;
    }
    final attempt = _hash(pin, salt);
    if (attempt == duressHash) return PinResult.duress;
    if (attempt == normalHash) return PinResult.normal;
    return PinResult.wrong;
  }

  Future<void> clear() async {
    await _storage.delete(key: _saltKey);
    await _storage.delete(key: _normalKey);
    await _storage.delete(key: _duressKey);
  }

  // ---------- helpers ----------

  String _newSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// Salted SHA-256, repeated to slow down guessing.
  String _hash(String pin, String salt) {
    var digest = sha256.convert(utf8.encode('$salt:$pin')).bytes;
    for (var i = 0; i < _iterations; i++) {
      digest = sha256.convert([...digest, ...utf8.encode(salt)]).bytes;
    }
    return base64UrlEncode(digest);
  }
}
