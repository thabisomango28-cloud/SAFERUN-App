import 'dart:async';

import 'package:noise_meter/noise_meter.dart';
import 'package:permission_handler/permission_handler.dart';

/// Listens to the microphone ON THE PHONE and reports sudden loud noises
/// (a scream, a crash). Audio is never recorded or sent anywhere: only the
/// loudness number is looked at.
///
/// Phone microphones are not calibrated, so we do not use a fixed decibel
/// limit. We learn the normal background level and react to a sudden jump
/// above it that lasts for a couple of readings.
class SoundMonitor {
  // ---- tune these while testing on your phone ----
  /// How far above the normal level a peak must be (lower = more sensitive).
  static const double spikeDb = 25;

  /// Consecutive loud readings needed (avoids a single click or bump).
  static const int hitsNeeded = 2;

  /// After a trigger, ignore new ones for this long.
  static const Duration cooldown = Duration(seconds: 30);
  // -------------------------------------------------

  final void Function() onLoudEvent;
  final void Function(double db)? onLevel;

  StreamSubscription<NoiseReading>? _sub;
  double _baseline = 0;
  bool _hasBaseline = false;
  int _hits = 0;
  DateTime? _lastTrigger;

  SoundMonitor({required this.onLoudEvent, this.onLevel});

  /// Returns false if the microphone is not available.
  Future<bool> start() async {
    if (!await Permission.microphone.isGranted) return false;
    try {
      _sub = NoiseMeter().noise.listen(_onReading, onError: (_) {});
      return true;
    } catch (_) {
      return false;
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  void _onReading(NoiseReading r) {
    final level = r.meanDecibel;
    final peak = r.maxDecibel;
    if (!level.isFinite || !peak.isFinite) return;
    onLevel?.call(level);

    if (!_hasBaseline) {
      _baseline = level;
      _hasBaseline = true;
      return;
    }

    if (peak > _baseline + spikeDb) {
      _hits++;
    } else {
      _hits = 0;
      // Only learn the background from normal sound, never from a spike.
      _baseline = _baseline * 0.95 + level * 0.05;
    }

    final now = DateTime.now();
    final coolingDown =
        _lastTrigger != null && now.difference(_lastTrigger!) < cooldown;
    if (_hits >= hitsNeeded && !coolingDown) {
      _hits = 0;
      _lastTrigger = now;
      onLoudEvent();
    }
  }
}
