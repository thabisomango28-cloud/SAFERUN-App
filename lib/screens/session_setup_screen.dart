import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/sms_sender.dart';
import '../services/routing_service.dart';
import 'active_session_screen.dart';

/// Choose activity, planned duration and check-in interval, then start.
class SessionSetupScreen extends StatefulWidget {
  final RouteOption? route;
  final TripType? tripType;
  const SessionSetupScreen({super.key, this.route, this.tripType});

  @override
  State<SessionSetupScreen> createState() => _SessionSetupScreenState();
}

class _SessionSetupScreenState extends State<SessionSetupScreen> {
  String _activity = 'Run';
  double _duration = 30;
  int _checkIn = 10;
  bool _starting = false;
  bool _sound = true;

  @override
  void initState() {
    super.initState();
    if (widget.route != null) _duration = _suggest();
  }

  /// Suggested time: route length at a typical pace, plus 10% buffer.
  double _suggest() {
    final km = widget.route!.km;
    final minPerKm = _activity == 'Run' ? 6.0 : 12.0;
    final mins = (km * minPerKm * 1.1 / 5).ceil() * 5;
    return mins.clamp(10, 120).toDouble();
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    final gpsOn = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;
    setState(() => _starting = false);

    if (!gpsOn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turn on GPS (location) first.')),
      );
      return;
    }
    // Ask for SMS permission now, while it is calm, so an alert never has to.
    try {
      final smsOk = await SmsSender().requestPermission();
      if (!smsOk && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'SMS permission denied: alerts will open your messages app instead.',
            ),
          ),
        );
      }
    } catch (_) {}
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveSessionScreen(
          activity: _activity,
          durationMin: _duration.round(),
          checkInMin: _checkIn,
          route: widget.route,
          soundDetection: _sound,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan your session')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.route != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.route),
                title: Text(
                  '${widget.route!.label} · '
                  '${widget.route!.km.toStringAsFixed(1)} km',
                ),
                subtitle: Text(
                  tripTypeLabel(widget.tripType ?? TripType.oneWay),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text('Activity', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final a in ['Run', 'Walk', 'Commute'])
                ChoiceChip(
                  label: Text(a),
                  selected: _activity == a,
                  onSelected: (_) => setState(() {
                    _activity = a;
                    if (widget.route != null) _duration = _suggest();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Planned duration: ${_duration.round()} min',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Slider(
            min: 10,
            max: 120,
            divisions: 22,
            value: _duration,
            label: '${_duration.round()} min',
            onChanged: (v) => setState(() => _duration = v),
          ),
          const SizedBox(height: 16),
          Text(
            'Check in with me',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final m in [5, 10, 15])
                ChoiceChip(
                  label: Text('Every $m min'),
                  selected: _checkIn == m,
                  onSelected: (_) => setState(() => _checkIn = m),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'If you miss a check-in or the planned time runs out, SafeRun asks '
            'if you are OK. If you do not answer with your PIN, your contacts '
            'are alerted.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _sound,
            onChanged: (v) => setState(() => _sound = v),
            title: const Text('Sound detection'),
            subtitle: const Text(
              'Listens for sudden loud noises. Analysed on your phone, never recorded.',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _starting ? null : _start,
              icon: const Icon(Icons.directions_run),
              label: const Text('Start Safe Session'),
            ),
          ),
        ],
      ),
    );
  }
}
