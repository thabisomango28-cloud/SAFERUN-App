import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/pin_service.dart';
import '../services/setup_state.dart';
import 'home_screen.dart';
import 'permissions_screen.dart';

/// Sits between login and the home screen.
/// If setup isn't finished, the user starts at the consent/permissions page.
/// Once consent, permissions, 2+ contacts and PINs are all done, it shows Home.
class SetupGate extends StatelessWidget {
  const SetupGate({super.key});

  Future<bool> _isComplete() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = doc.data() ?? {};

      final consented = data['consentAt'] != null;
      final contacts = (data['contacts'] as List?)?.length ?? 0;
      final pins = await PinService().hasPins();
      final location = await Permission.location.isGranted;
      final mic = await Permission.microphone.isGranted;

      return consented && contacts >= 2 && pins && location && mic;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: setupChanged,
      builder: (_, __, ___) => FutureBuilder<bool>(
        future: _isComplete(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return (snap.data ?? false)
              ? const HomeScreen()
              : const PermissionsScreen();
        },
      ),
    );
  }
}
