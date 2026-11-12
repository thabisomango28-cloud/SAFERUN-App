import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/pin_service.dart';

/// Numeric keypad with PIN dots. Calls [onSubmit] when the tick is pressed.
class PinPad extends StatefulWidget {
  final void Function(String pin) onSubmit;
  final String? message;
  const PinPad({super.key, required this.onSubmit, this.message});

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';

  void _tap(String d) {
    if (_pin.length >= 6) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += d);
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _ok() {
    if (_pin.length < 4) return;
    final p = _pin;
    setState(() => _pin = '');
    widget.onSubmit(p);
  }

  Widget _key(Widget child, VoidCallback onTap) => SizedBox(
    width: 68,
    height: 50,
    child: FilledButton.tonal(onPressed: onTap, child: child),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 6; i++)
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? scheme.primary : Colors.transparent,
                  border: Border.all(color: scheme.primary),
                ),
              ),
          ],
        ),
        SizedBox(
          height: 24,
          child: Center(
            child: Text(
              widget.message ?? '',
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ),
        ),
        SizedBox(
          width: 220,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
                _key(
                  Text(d, style: const TextStyle(fontSize: 18)),
                  () => _tap(d),
                ),
              _key(const Icon(Icons.backspace_outlined), _back),
              _key(
                const Text('0', style: TextStyle(fontSize: 18)),
                () => _tap('0'),
              ),
              _key(const Icon(Icons.check), _ok),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bottom sheet that asks for the PIN.
/// Returns true if the normal OR duress PIN was entered (both look the same).
/// [onDuress] runs silently when the duress PIN is used.
Future<bool> showPinSheet(
  BuildContext context, {
  required String title,
  Future<void> Function()? onDuress,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PinSheet(title: title, onDuress: onDuress),
  );
  return ok ?? false;
}

class _PinSheet extends StatefulWidget {
  final String title;
  final Future<void> Function()? onDuress;
  const _PinSheet({required this.title, this.onDuress});

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  String? _msg;

  Future<void> _check(String pin) async {
    final result = await PinService().verify(pin);
    if (!mounted) return;
    switch (result) {
      case PinResult.normal:
        Navigator.pop(context, true);
      case PinResult.duress:
        await widget.onDuress?.call();
        if (!mounted) return;
        Navigator.pop(context, true); // looks exactly like a normal PIN
      case PinResult.wrong:
        setState(() => _msg = 'Wrong PIN');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          PinPad(onSubmit: _check, message: _msg),
        ],
      ),
    );
  }
}
