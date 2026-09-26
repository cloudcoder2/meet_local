import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/feedback.dart';
import '../auth/auth_controller.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final _name = TextEditingController(text: ref.read(authProvider).value?.name ?? '');
  late final _email = TextEditingController(text: ref.read(authProvider).value?.email ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final email = _email.text.trim();
      await ref.read(authProvider.notifier).updateProfile(name: _name.text.trim(), email: email.isEmpty ? null : email);
      if (mounted) showMessage(context, 'Profile saved');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).value;
    if (user == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: CircleAvatar(
              radius: 40,
              child: Text((user.name ?? '?').characters.first.toUpperCase(), style: theme.textTheme.headlineMedium),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text(user.phone, style: theme.textTheme.bodyLarge)),
          if (user.rating != null)
            Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.star_rounded, size: 18, color: Colors.amber),
                Text(' ${user.rating!.toStringAsFixed(2)} (${user.ratingCount})'),
              ]),
            ),
          const SizedBox(height: 24),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email (optional)'),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _saving ? null : _save, child: _saving ? const ButtonSpinner() : const Text('Save')),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
    );
  }
}
