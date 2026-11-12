import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'contacts_screen.dart';

/// Explains each permission, asks for POPIA consent, then requests them.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _consent = false;
  Map<Permission, PermissionStatus> _status = {};

  static const _items = <_Item>[
    _Item(
      Permission.location,
      Icons.location_on,
      'Location',
      'Live tracking during sessions',
      true,
    ),
    _Item(
      Permission.microphone,
      Icons.mic,
      'Microphone',
      'Sound detection, only while a session is active',
      true,
    ),
    _Item(
      Permission.notification,
      Icons.notifications,
      'Notifications',
      'Check-ins and alerts',
      false,
    ),
    _Item(
      Permission.sms,
      Icons.sms,
      'SMS',
      'Backup alerts when there is no data',
      false,
    ),
  ];

  Future<void> _request() async {
    final result = await _items.map((i) => i.permission).toList().request();
    if (!mounted) return;
    setState(() => _status = result);
  }

  bool get _requiredGranted => _items
      .where((i) => i.required)
      .every((i) => _status[i.permission]?.isGranted ?? false);

  bool get _anyPermanentlyDenied =>
      _status.values.any((s) => s.isPermanentlyDenied);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text("Let's get you set up")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'SafeRun needs these to protect you during sessions.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          for (final i in _items)
            Card(
              child: ListTile(
                leading: Icon(i.icon, color: scheme.primary),
                title: Text(i.title + (i.required ? '' : ' (recommended)')),
                subtitle: Text(i.reason),
                trailing: Icon(
                  _status[i.permission]?.isGranted ?? false
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  color: _status[i.permission]?.isGranted ?? false
                      ? scheme.primary
                      : null,
                ),
              ),
            ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'I consent to SafeRun processing my location and audio as '
              'described, under POPIA. I can delete my data at any time.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          if (_status.isEmpty || !_requiredGranted)
            FilledButton(
              onPressed: _consent ? _request : null,
              child: const Text('Allow permissions'),
            ),
          if (_anyPermanentlyDenied)
            TextButton(
              onPressed: openAppSettings,
              child: const Text('Some are blocked. Open app settings'),
            ),
          if (_requiredGranted)
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ContactsScreen()),
              ),
              child: const Text('Continue'),
            ),
        ],
      ),
    );
  }
}

class _Item {
  final Permission permission;
  final IconData icon;
  final String title;
  final String reason;
  final bool required;
  const _Item(
    this.permission,
    this.icon,
    this.title,
    this.reason,
    this.required,
  );
}
