import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TrustedContact {
  final String name;
  final String phone; // stored as +27XXXXXXXXX
  const TrustedContact({required this.name, required this.phone});

  Map<String, dynamic> toMap() => {'name': name, 'phone': phone};
}

/// Trusted contacts live in an array on the user's own document
/// (users/{uid}.contacts), so the existing Firestore rules already cover it.
class ContactsService {
  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _db.collection('users').doc(FirebaseAuth.instance.currentUser!.uid);

  Stream<List<TrustedContact>> watch() => _doc.snapshots().map((snap) {
    final raw = (snap.data()?['contacts'] as List?) ?? [];
    return raw
        .map(
          (e) => TrustedContact(
            name: e['name'] as String,
            phone: e['phone'] as String,
          ),
        )
        .toList();
  });

  Future<void> add(TrustedContact c) => _doc.set({
    'contacts': FieldValue.arrayUnion([c.toMap()]),
  }, SetOptions(merge: true));

  Future<void> remove(TrustedContact c) => _doc.update({
    'contacts': FieldValue.arrayRemove([c.toMap()]),
  });

  /// Accepts 0821234567 or +27821234567 (spaces/dashes allowed).
  /// Returns the +27 form, or null if it isn't a valid SA mobile number.
  static String? normalisePhone(String input) {
    var p = input.replaceAll(RegExp(r'[\s\-()]'), '');
    if (p.startsWith('0')) p = '+27${p.substring(1)}';
    if (p.startsWith('27')) p = '+$p';
    return RegExp(r'^\+27\d{9}$').hasMatch(p) ? p : null;
  }
}
