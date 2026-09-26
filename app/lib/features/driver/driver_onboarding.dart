import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../widgets/cholo_map.dart';
import '../../widgets/feedback.dart';
import 'driver_controller.dart';

class DriverOnboarding extends ConsumerStatefulWidget {
  const DriverOnboarding({super.key});

  @override
  ConsumerState<DriverOnboarding> createState() => _DriverOnboardingState();
}

class _DriverOnboardingState extends ConsumerState<DriverOnboarding> {
  final _form = GlobalKey<FormState>();
  final _license = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _color = TextEditingController();
  final _plate = TextEditingController();
  VehicleClass _class = VehicleClass.bike;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_license, _make, _model, _color, _plate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(driverProvider.notifier).register(
            licenseNumber: _license.text.trim(),
            vehicleClass: _class,
            make: _make.text.trim(),
            model: _model.text.trim(),
            color: _color.text.trim(),
            plateNumber: _plate.text.trim(),
          );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? v) => (v ?? '').trim().isEmpty ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Earn with Cholo', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Drive on your own schedule. Add your licence and vehicle to get started.'),
          const SizedBox(height: 24),
          Text('Vehicle type', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<VehicleClass>(
            segments: [
              for (final c in VehicleClass.values) ButtonSegment(value: c, label: Text(c.label), icon: Icon(vehicleIcon(c))),
            ],
            selected: {_class},
            onSelectionChanged: (s) => setState(() => _class = s.first),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('license-field'),
            controller: _license,
            decoration: const InputDecoration(labelText: 'Driving licence number'),
            validator: (v) => (v ?? '').trim().length < 4 ? 'Enter your licence number' : null,
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                key: const Key('make-field'),
                controller: _make,
                decoration: const InputDecoration(labelText: 'Make'),
                validator: _required,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                key: const Key('model-field'),
                controller: _model,
                decoration: const InputDecoration(labelText: 'Model'),
                validator: _required,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('color-field'),
            controller: _color,
            decoration: const InputDecoration(labelText: 'Colour'),
            validator: _required,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('plate-field'),
            controller: _plate,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Registration plate', hintText: 'DHAKA METRO-HA 12-3456'),
            validator: (v) => (v ?? '').trim().length < 3 ? 'Enter the plate number' : null,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving ? const ButtonSpinner() : const Text('Submit'),
          ),
        ],
      ),
    );
  }
}
