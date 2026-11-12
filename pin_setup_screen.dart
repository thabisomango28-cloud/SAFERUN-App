import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/pin_service.dart';

/// Lets the user set a normal PIN and a duress PIN.
/// This is the LAST step of onboarding — on save we mark onboarding complete,
/// which flips AuthGate over to the HomeScreen automatically.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final _normal = TextEditingController();
  final _duress = TextEditingController();
  final _pins = PinService();
  bool _saving = false;

  @override
  void dispose() {
    _normal.dispose();
    _duress.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final error = await _pins.setPins(
      normal: _normal.text,
      duress: _duress.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    // Onboarding is done: flip the Firestore flag, then pop everything so
    // AuthGate rebuilds and sends the user to HomeScreen.
    await AuthService().markOnboardingComplete();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Set your PINs')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Normal PIN', 'Ends a session.'),
            TextField(
              controller: _normal,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 24),
            _label(
              'Duress PIN',
              'Looks like it ends the session, but silently alerts your contacts. Use it if someone forces you to turn the app off.',
            ),
            TextField(
              controller: _duress,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                counterText: '',
                prefixIcon: Icon(Icons.visibility_off, color: scheme.secondary),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save PINs'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String title, String help) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(help, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}
