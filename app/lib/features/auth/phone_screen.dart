import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../widgets/brand.dart';
import '../../widgets/feedback.dart';
import 'auth_controller.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = normalizePhone(_controller.text);
    if (phone == null) {
      setState(() => _error = 'Enter a valid mobile number, e.g. 01712345678');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final result = await ref.read(authProvider.notifier).requestOtp(phone);
      if (!mounted) return;
      context.push('/login/otp', extra: result);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 48),
            const CholoLogo(size: 44),
            const SizedBox(height: 12),
            Text('Rides across the city, in minutes.', style: theme.textTheme.titleMedium),
            const SizedBox(height: 48),
            Text('Enter your mobile number', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              key: const Key('phone-field'),
              controller: _controller,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]'))],
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.phone_iphone),
                hintText: '01XXXXXXXXX',
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading ? const ButtonSpinner() : const Text('Continue'),
            ),
            const SizedBox(height: 16),
            Text(
              "We'll text you a 6-digit code to confirm it's you.",
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
