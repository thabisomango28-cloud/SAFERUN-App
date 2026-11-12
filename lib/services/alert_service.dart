import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'contacts_service.dart';
import 'sms_sender.dart';

class AlertResult {
  final int sent; // contacts the SMS was sent to
  final int failed; // contacts it could not be sent to
  final bool openedComposer; // fell back to the phone's SMS app
  const AlertResult({
    required this.sent,
    required this.failed,
    required this.openedComposer,
  });

  bool get allSent => sent > 0 && failed == 0;
}

/// Alerts the user's trusted contacts by SMS.
///
/// - Normal alert: sends an SMS straight from the phone to every contact,
///   with no screens opening. If that is impossible (no permission, no SIM),
///   it falls back to opening the SMS app with the message filled in.
/// - Silent alert (duress PIN): sends a different message that tells contacts
///   NOT to phone the user, and never opens any screen.
class AlertService {
  final _sms = SmsSender();

  Future<AlertResult> send({
    required String reason,
    Position? position,
    bool silent = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const AlertResult(sent: 0, failed: 0, openedComposer: false);
    }

    // 1. Log the alert on the user's own document.
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'alerts': FieldValue.arrayUnion([
          {
            'reason': reason,
            'at': Timestamp.now(),
            'lat': position?.latitude,
            'lng': position?.longitude,
            'silent': silent,
          },
        ]),
      }, SetOptions(merge: true));
    } catch (_) {
      // Never let logging block the alert itself.
    }

    final contacts = await ContactsService().watch().first;
    if (contacts.isEmpty) {
      return const AlertResult(sent: 0, failed: 0, openedComposer: false);
    }

    final name = user.displayName ?? 'A SafeRun user';
    final where = position == null
        ? 'location unavailable'
        : 'https://maps.google.com/?q=${position.latitude},${position.longitude}';
    // Kept short so it usually fits in a single SMS.
    final body = silent
        ? 'SAFERUN SILENT ALERT: $name may be in danger. Do NOT call them. '
              'Call police 10111. Location: $where'
        : 'SAFERUN: $name may need help ($reason). Location: $where';

    // 2. Send directly, one contact at a time.
    var sent = 0;
    var failed = 0;
    var granted = false;
    try {
      granted = await _sms.requestPermission();
    } catch (_) {}

    if (granted) {
      for (final c in contacts) {
        try {
          await _sms.send(c.phone, body);
          sent++;
        } catch (_) {
          failed++;
        }
      }
    } else {
      failed = contacts.length;
    }

    // 3. Nothing went out: open the SMS app instead (never for silent alerts).
    var composer = false;
    if (sent == 0 && !silent) {
      final numbers = contacts.map((c) => c.phone).join(',');
      try {
        composer = await launchUrl(
          Uri.parse('sms:$numbers?body=${Uri.encodeComponent(body)}'),
        );
      } catch (_) {}
    }

    return AlertResult(sent: sent, failed: failed, openedComposer: composer);
  }
}
