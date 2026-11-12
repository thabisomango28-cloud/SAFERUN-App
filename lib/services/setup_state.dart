import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Bump this after any setup step finishes so SetupGate re-checks.
final ValueNotifier<int> setupChanged = ValueNotifier<int>(0);

/// Saves when the user gave POPIA consent (kept on their own user document).
Future<void> recordConsent() async {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  await FirebaseFirestore.instance.collection('users').doc(uid).set({
    'consentAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}
