import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/auth_service.dart';
import '../services/contacts_service.dart';
import '../services/pin_service.dart';
import 'contacts_screen.dart';
import 'permissions_screen.dart';
import 'pin_setup_screen.dart';
import 'plan_route_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _contacts = ContactsService();
  final _pins = PinService();

  late final AnimationController _hold;
  double _lastHaptic = 0;

  bool _location = false;
  bool _mic = false;
  bool _hasPins = false;

  static const _panicPink = Color(0xFFC2347A);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hold =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..addListener(_hapticSteps)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              HapticFeedback.heavyImpact();
              _hold.reset();
              _lastHaptic = 0;
              _panicTriggered();
            }
          });
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hold.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final loc = await Permission.location.isGranted;
    final mic = await Permission.microphone.isGranted;
    final pins = await _pins.hasPins();
    if (!mounted) return;
    setState(() {
      _location = loc;
      _mic = mic;
      _hasPins = pins;
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _refresh();
  }

  void _hapticSteps() {
    final v = _hold.value;
    if (v >= 0.33 && _lastHaptic < 0.33) {
      HapticFeedback.lightImpact();
      _lastHaptic = 0.33;
    } else if (v >= 0.66 && _lastHaptic < 0.66) {
      HapticFeedback.mediumImpact();
      _lastHaptic = 0.66;
    }
  }

  void _cancelHold() {
    if (_hold.status != AnimationStatus.completed) {
      _hold.reverse();
      _lastHaptic = 0;
    }
  }

  void _panicTriggered() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Panic triggered'),
        content: const Text(
          'In the full app, your contacts now receive your location and audio recording starts. (Demo only for now.)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _soon(String what) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$what is the next feature.')));

  void _helplines() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Helplines'),
        content: const Text(
          'GBV Command Centre: 0800 428 428\nSAPS emergency: 10111',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name =
        FirebaseAuth.instance.currentUser?.displayName?.split(' ').first ??
        'there';

    return Scaffold(
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
          child: StreamBuilder<List<TrustedContact>>(
            stream: _contacts.watch(),
            builder: (context, snap) {
              final contactCount = snap.data?.length ?? 0;
              return Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _header(name),
                        const SizedBox(height: 12),
                        _protectionCard(scheme, contactCount),
                        const SizedBox(height: 12),
                        _startCard(scheme),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _quick(
                                Icons.map_outlined,
                                'Safe places',
                                () => _soon('Safe places'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _quick(
                                Icons.phone_outlined,
                                'Helplines',
                                _helplines,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: scheme.primaryContainer,
                              child: Icon(Icons.group, color: scheme.primary),
                            ),
                            title: Text('$contactCount trusted contacts'),
                            subtitle: Text(
                              contactCount >= 2
                                  ? 'Ready to receive alerts'
                                  : 'Add at least 2',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _open(const ContactsScreen()),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _panic(scheme),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(String name) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hi, $name', style: Theme.of(context).textTheme.titleLarge),
              Text(
                "You're not in a session",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.account_circle, size: 32),
          onSelected: (v) {
            if (v == 'setup') _open(const PermissionsScreen());
            if (v == 'pins') _open(const PinSetupScreen());
            if (v == 'logout') AuthService().logout();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'setup', child: Text('Run setup')),
            PopupMenuItem(value: 'pins', child: Text('Change PINs')),
            PopupMenuItem(value: 'logout', child: Text('Log out')),
          ],
        ),
      ],
    );
  }

  Widget _protectionCard(ColorScheme scheme, int contactCount) {
    final checks = <String, bool>{
      'GPS': _location,
      'Mic': _mic,
      'Contacts': contactCount >= 2,
      'PINs': _hasPins,
    };
    final done = checks.values.where((v) => v).length;
    final progress = done / checks.length;
    final complete = done == checks.length;

    return _card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: complete ? null : () => _open(const PermissionsScreen()),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(72, 72),
                      painter: _RingPainter(
                        progress: progress,
                        track: scheme.primaryContainer,
                        color: scheme.primary,
                      ),
                    ),
                    Icon(
                      complete ? Icons.verified_user : Icons.shield,
                      color: scheme.primary,
                      size: 28,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Protection ${(progress * 100).round()}%',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      complete ? 'Everything is ready' : 'Tap to finish setup',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final e in checks.entries) _chip(e.key, e.value),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool ok) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: ok ? scheme.primaryContainer : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check : Icons.close, size: 12),
          const SizedBox(width: 3),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _startCard(ColorScheme scheme) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _open(const PlanRouteScreen()),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          children: [
            Icon(Icons.directions_run, color: Colors.white, size: 36),
            SizedBox(height: 4),
            Text(
              'Start Safe Session',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Run, walk or commute',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quick(IconData icon, String label, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(height: 6),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Card(
    elevation: 0,
    margin: EdgeInsets.zero,
    color: Colors.white.withValues(alpha: 0.78),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: child,
  );

  Widget _panic(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Listener(
            onPointerDown: (_) => _hold.forward(),
            onPointerUp: (_) => _cancelHold(),
            onPointerCancel: (_) => _cancelHold(),
            child: AnimatedBuilder(
              animation: _hold,
              builder: (_, __) => SizedBox(
                width: 96,
                height: 96,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(96, 96),
                      painter: _RingPainter(
                        progress: _hold.value,
                        track: scheme.secondary.withValues(alpha: 0.25),
                        color: _panicPink,
                      ),
                    ),
                    Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        color: scheme.secondary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Hold for 2 seconds',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color track;
  final Color color;

  _RingPainter({
    required this.progress,
    required this.track,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 4;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = track;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawCircle(center, radius, base);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}
