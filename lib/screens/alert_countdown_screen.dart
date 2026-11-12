import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../services/alert_service.dart';
import '../services/pin_service.dart';
import 'pin_pad.dart';

enum AlertOutcome { cancelled, sent, partial, composer, failed }

/// "Are you OK?" screen. Contacts are alerted when the timer reaches zero
/// unless the PIN is entered. The duress PIN looks like a cancel but
/// silently logs an alert.
class AlertCountdownScreen extends StatefulWidget {
  final String reason;
  final Position? position;
  const AlertCountdownScreen({super.key, required this.reason, this.position});

  @override
  State<AlertCountdownScreen> createState() => _AlertCountdownScreenState();
}

class _AlertCountdownScreenState extends State<AlertCountdownScreen> {
  static const _seconds = 10;
  int _left = _seconds;
  Timer? _timer;
  String? _msg;
  int _fails = 0;
  bool _done = false;
  bool _sendingAlert = false;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_left <= 1) {
        _sendNow();
      } else {
        HapticFeedback.lightImpact();
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sendNow() async {
    if (_done) return;
    _done = true;
    _timer?.cancel();
    if (mounted) setState(() => _sendingAlert = true);
    final result = await AlertService().send(
      reason: widget.reason,
      position: widget.position,
    );
    if (mounted) Navigator.pop(context, _outcomeFor(result));
  }

  AlertOutcome _outcomeFor(AlertResult r) {
    if (r.allSent) return AlertOutcome.sent;
    if (r.sent > 0) return AlertOutcome.partial;
    if (r.openedComposer) return AlertOutcome.composer;
    return AlertOutcome.failed;
  }

  Future<void> _onPin(String pin) async {
    if (_done) return;
    final result = await PinService().verify(pin);
    if (!mounted || _done) return;

    if (result == PinResult.normal) {
      _done = true;
      _timer?.cancel();
      Navigator.pop(context, AlertOutcome.cancelled);
    } else if (result == PinResult.duress) {
      _done = true;
      _timer?.cancel();
      await AlertService().send(
        reason: 'Duress PIN used (${widget.reason})',
        position: widget.position,
        silent: true,
      );
      if (mounted) Navigator.pop(context, AlertOutcome.cancelled);
    } else {
      _fails++;
      if (_fails >= 3) {
        _sendNow(); // too many wrong PINs counts as danger
      } else {
        setState(() => _msg = 'Wrong PIN (${3 - _fails} tries left)');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFFBE0EC),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Text(
                  widget.reason.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF9B2F63),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Are you OK?',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: 130,
                  height: 130,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 130,
                        height: 130,
                        child: CircularProgressIndicator(
                          value: _left / _seconds,
                          strokeWidth: 10,
                          color: const Color(0xFFC2347A),
                          backgroundColor: const Color(0xFFF2C4D9),
                        ),
                      ),
                      Text(
                        '$_left',
                        style: const TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _sendingAlert ? 'Sending alert to your contacts...' : 'Your contacts will be alerted with your location unless you enter your PIN.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                PinPad(onSubmit: _onPin, message: _msg),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.secondary,
                    ),
                    onPressed: _sendNow,
                    child: const Text('Send alert now'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
