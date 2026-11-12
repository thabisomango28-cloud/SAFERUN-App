import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Sends SMS straight from the phone using a few lines of native Android code
/// (see MainActivity.kt). No third-party SMS plugin is needed.
class SmsSender {
  static const _channel = MethodChannel('saferun/sms');

  Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Asks for permission if needed. Returns true if SEND_SMS is granted.
  Future<bool> requestPermission() async {
    if (await hasPermission()) return true;
    await Permission.sms.request();
    return hasPermission();
  }

  /// Completes when the phone's radio has accepted the message.
  /// Throws if it could not be sent (no signal, no SIM, no permission, timeout).
  Future<void> send(String phone, String message) async {
    await _channel
        .invokeMethod('sendSms', {'phone': phone, 'message': message})
        .timeout(const Duration(seconds: 25));
  }
}
