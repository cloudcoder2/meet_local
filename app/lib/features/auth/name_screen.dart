import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/feedback.dart';
import 'auth_controller.dart';

/// Shown once after the first login so drivers see who they're picking up.
class NameScreen extends ConsumerStatefulWidget {
  const NameScreen({super.key});

  @override
  ConsumerState<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends ConsumerState<NameScreen> {
  final _controller = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _loading = true);
    try {
      await ref.read(authProvider.notifier).updateProfile(name: name);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 48),
            Text("What's your name?", style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Your driver will see this when they pick you up.'),
            const SizedBox(height: 24),
            TextField(
              key: const Key('name-field'),
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Full name'),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _save,
              child: _loading ? const ButtonSpinner() : const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
