import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/alert_service.dart';
import '../services/route_math.dart';
import '../services/routing_service.dart';
import '../services/sound_monitor.dart';
import 'alert_countdown_screen.dart';
import 'pin_pad.dart';

class ActiveSessionScreen extends StatefulWidget {
  final String activity;
  final int durationMin;
  final int checkInMin;
  final RouteOption? route;
  final bool soundDetection;
  const ActiveSessionScreen({
    super.key,
    required this.activity,
    required this.durationMin,
    required this.checkInMin,
    this.route,
    this.soundDetection = true,
  });

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  final _alerts = AlertService();
  final _map = MapController();
  SoundMonitor? _sound;
  double? _db;
  bool _soundOn = false;
  Timer? _ticker;
  StreamSubscription<Position>? _posSub;

  Position? _last;
  double _meters = 0;
  late final DateTime _start;
  late DateTime _checkInDue;
  bool _alertOpen = false;
  bool _overrunHandled = false;

  // ---- escalation rules (tune while testing) ----
  static const double _offRouteMeters = 150; // how far from the route
  static const Duration _offRouteFor = Duration(seconds: 30); // for how long
  static const double _stillMeters = 25; // moved less than this...
  static const Duration _stillFor = Duration(minutes: 3); // ...for this long
  static const Duration _quietAfterAlert = Duration(minutes: 2);
  // ------------------------------------------------

  DateTime? _offRouteSince;
  double? _offRouteM;
  Position? _anchor; // last place we counted as "moved to"
  DateTime _anchorAt = DateTime.now();
  DateTime _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _start = DateTime.now();
    _checkInDue = _start.add(Duration(minutes: widget.checkInMin));
    WakelockPlus.enable(); // keep the screen on during the session
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _startLocation();
    if (widget.soundDetection) _startSound();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _posSub?.cancel();
    _sound?.stop();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _startSound() async {
    _sound = SoundMonitor(
      onLevel: (db) => _db = db,
      onLoudEvent: () {
        if (mounted && !_alertOpen) _escalate('Loud noise detected');
      },
    );
    final ok = await _sound!.start();
    if (mounted) setState(() => _soundOn = ok);
  }

  Future<void> _startLocation() async {
    try {
      final first = await Geolocator.getCurrentPosition().timeout(
        const Duration(seconds: 10),
      );
      if (mounted) {
        setState(() => _last = first);
        _follow(first);
        _checkMovement(first);
      }
    } catch (_) {
      // The live stream below will fill the position in.
    }
    _posSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((p) {
          final prev = _last;
          if (prev != null) {
            _meters += Geolocator.distanceBetween(
              prev.latitude,
              prev.longitude,
              p.latitude,
              p.longitude,
            );
          }
          if (mounted) {
            setState(() => _last = p);
            _follow(p);
            _checkMovement(p);
          }
        });
  }

  /// Called for every GPS update: tracks standing still and leaving the route.
  void _checkMovement(Position p) {
    final here = LatLng(p.latitude, p.longitude);

    // Standing still: restart the timer whenever we move far enough.
    final a = _anchor;
    if (a == null ||
        Geolocator.distanceBetween(
              a.latitude,
              a.longitude,
              p.latitude,
              p.longitude,
            ) >
            _stillMeters) {
      _anchor = p;
      _anchorAt = DateTime.now();
    }

    // Off route: only when a route was chosen and the GPS fix is decent.
    final route = widget.route;
    if (route == null || p.accuracy > 50) return;
    final d = distanceToRouteM(here, route.points);
    _offRouteM = d;
    if (d > _offRouteMeters) {
      _offRouteSince ??= DateTime.now();
    } else {
      _offRouteSince = null;
    }
  }

  void _follow(Position p) {
    try {
      _map.move(LatLng(p.latitude, p.longitude), _map.camera.zoom);
    } catch (_) {}
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
    if (_alertOpen) return;

    final now = DateTime.now();
    if (now.isAfter(_checkInDue)) {
      _escalate('Missed check-in');
    } else if (_offRouteSince != null &&
        now.difference(_offRouteSince!) > _offRouteFor &&
        now.isAfter(_quietUntil)) {
      _escalate('Off your planned route');
    } else if (now.difference(_anchorAt) > _stillFor &&
        now.isAfter(_quietUntil)) {
      _escalate('Stopped moving for a while');
    } else if (!_overrunHandled &&
        now.difference(_start) > Duration(minutes: widget.durationMin)) {
      _overrunHandled = true;
      _escalate('Session ran past its planned time');
    }
  }

  Future<void> _escalate(String reason) async {
    _alertOpen = true;
    final outcome = await Navigator.push<AlertOutcome>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AlertCountdownScreen(reason: reason, position: _last),
      ),
    );
    if (!mounted) return;
    _alertOpen = false;
    _offRouteSince = null;
    _anchor = _last;
    _anchorAt = DateTime.now();
    _quietUntil = DateTime.now().add(_quietAfterAlert);
    _checkInDue = DateTime.now().add(Duration(minutes: widget.checkInMin));
    final msg = switch (outcome) {
      AlertOutcome.sent => 'Alert sent to your contacts.',
      AlertOutcome.partial => 'Alert sent to some of your contacts only.',
      AlertOutcome.composer =>
        'Tap Send in your messages app to alert your contacts.',
      AlertOutcome.failed =>
        'Alert could not be sent. Call 10111 or your contacts now.',
      _ => null,
    };
    if (msg != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _imOk() {
    HapticFeedback.mediumImpact();
    setState(
      () => _checkInDue = DateTime.now().add(
        Duration(minutes: widget.checkInMin),
      ),
    );
  }

  Future<void> _end() async {
    final ok = await showPinSheet(
      context,
      title: 'Enter your PIN to end the session',
      // Duress PIN: ends the session normally but silently logs an alert.
      onDuress: () async {
        await _alerts.send(
          reason: 'Duress PIN used',
          position: _last,
          silent: true,
        );
      },
    );
    if (ok && mounted) Navigator.pop(context);
  }

  String _fmt(Duration d) {
    if (d.isNegative) d = Duration.zero;
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final elapsed = now.difference(_start);
    final planned = Duration(minutes: widget.durationMin);
    final progress = (elapsed.inSeconds / planned.inSeconds)
        .clamp(0.0, 1.0)
        .toDouble();
    final nextCheckIn = _checkInDue.difference(now);

    return PopScope(
      canPop: false, // back gesture asks for the PIN instead of leaving
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _end();
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.primaryContainer,
                scheme.secondary.withValues(alpha: 0.12),
              ],
            ),
          ),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Session active',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Chip(label: Text(widget.activity)),
                  ],
                ),
                const SizedBox(height: 8),
                _card(
                  child: Column(
                    children: [
                      Text(
                        _fmt(elapsed),
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'of ${widget.durationMin} min planned',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _statusCard(scheme),
                const SizedBox(height: 12),
                _mapCard(scheme),
                const SizedBox(height: 12),
                _card(
                  child: Row(
                    children: [
                      Icon(Icons.my_location, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _last == null
                                  ? 'Finding GPS...'
                                  : '${_last!.latitude.toStringAsFixed(5)}, '
                                        '${_last!.longitude.toStringAsFixed(5)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              _last == null
                                  ? 'Make sure you are outside or near a window'
                                  : 'Accuracy ${_last!.accuracy.round()} m · '
                                        '${(_meters / 1000).toStringAsFixed(2)} km covered',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _card(
                  child: Row(
                    children: [
                      Icon(Icons.timer_outlined, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Next check-in',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'in ${_fmt(nextCheckIn)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _imOk,
                        child: const Text("I'm OK"),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _soundCard(scheme),
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2B2233),
                    ),
                    onPressed: _end,
                    child: const Text('End session (enter PIN)'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusCard(ColorScheme scheme) {
    final stillFor = DateTime.now().difference(_anchorAt);
    final still = stillFor > const Duration(seconds: 30);
    final off = _offRouteSince != null;
    final route = widget.route;
    final warn = Colors.orange.shade800;

    final routeText = route == null
        ? 'No route selected'
        : _offRouteM == null
        ? 'Checking your route...'
        : off
        ? 'Off your route by ${_offRouteM!.round()} m'
        : 'On your planned route';
    final routeIcon = route == null
        ? Icons.route
        : off
        ? Icons.warning_amber_rounded
        : Icons.check_circle;

    return _card(
      child: Column(
        children: [
          Row(
            children: [
              Icon(routeIcon, color: off ? warn : scheme.primary),
              const SizedBox(width: 12),
              Expanded(child: Text(routeText)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                still ? Icons.pause_circle_outline : Icons.directions_run,
                color: still ? warn : scheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  still ? 'Not moving for ${_fmt(stillFor)}' : 'Moving',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _soundCard(ColorScheme scheme) {
    final db = _db;
    return _card(
      child: Row(
        children: [
          Icon(
            _soundOn ? Icons.mic : Icons.mic_off,
            color: _soundOn ? scheme.secondary : Colors.grey,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _soundOn
                      ? 'Listening on this device'
                      : 'Sound detection is off',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  _soundOn
                      ? (db == null
                            ? 'Starting...'
                            : 'Level ${db.round()} dB. A sudden loud noise starts the countdown.')
                      : 'Switch it on when planning a session.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Audio is analysed on your phone and never recorded or sent.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapCard(ColorScheme scheme) {
    final route = widget.route;
    final here = _last == null
        ? null
        : LatLng(_last!.latitude, _last!.longitude);
    return SizedBox(
      height: 230,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter:
                here ?? route?.points.first ?? const LatLng(-29.0, 24.0),
            initialZoom: here != null || route != null ? 15 : 5,
            initialCameraFit: route != null && here == null
                ? CameraFit.coordinates(
                    coordinates: route.points,
                    padding: const EdgeInsets.all(32),
                  )
                : null,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.demo1',
            ),
            if (route != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: route.points,
                    strokeWidth: 5,
                    color: scheme.secondary,
                  ),
                ],
              ),
            if (here != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: here,
                    width: 24,
                    height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
                ],
              ),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Card(
    elevation: 0,
    margin: EdgeInsets.zero,
    color: Colors.white.withValues(alpha: 0.78),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(padding: const EdgeInsets.all(14), child: child),
  );
}
