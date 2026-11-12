import 'package:flutter/material.dart';

import '../services/contacts_service.dart';
import 'pin_setup_screen.dart';

/// Add 2 to 5 trusted contacts who receive alerts.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _service = ContactsService();
  static const _min = 2;
  static const _max = 5;

  Future<void> _addDialog(int currentCount) async {
    if (currentCount >= _max) {
      _snack('You can add up to $_max contacts.');
      return;
    }
    final name = TextEditingController();
    final phone = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add trusted contact'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              TextFormField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Mobile (e.g. 082 123 4567)',
                ),
                validator: (v) =>
                    ContactsService.normalisePhone(v ?? '') == null
                    ? 'Enter a valid SA mobile number'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate())
                Navigator.pop(context, true);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _service.add(
        TrustedContact(
          name: name.text.trim(),
          phone: ContactsService.normalisePhone(phone.text)!,
        ),
      );
    }
    name.dispose();
    phone.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Trusted contacts')),
      body: StreamBuilder<List<TrustedContact>>(
        stream: _service.watch(),
        builder: (context, snap) {
          final contacts = snap.data ?? [];
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Add $_min to $_max people who get your alerts.'),
              const SizedBox(height: 12),
              for (final c in contacts)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.secondary,
                      foregroundColor: Colors.white,
                      child: Text(c.name[0].toUpperCase()),
                    ),
                    title: Text(c.name),
                    subtitle: Text(c.phone),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => _service.remove(c),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => _addDialog(contacts.length),
                icon: const Icon(Icons.add),
                label: const Text('Add contact'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: contacts.length >= _min
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PinSetupScreen(),
                        ),
                      )
                    : null,
                child: Text(
                  contacts.length >= _min
                      ? 'Continue'
                      : 'Add ${_min - contacts.length} more to continue',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
