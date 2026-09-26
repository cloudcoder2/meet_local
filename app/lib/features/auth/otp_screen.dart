import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cholo_api.dart';
import '../../widgets/feedback.dart';
import 'auth_controller.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.request});

  final OtpRequestResult request;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _controller = TextEditingController();
  late OtpRequestResult _request = widget.request;
  bool _loading = false;
  int _resendIn = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _resendIn = 30;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendIn <= 1) t.cancel();
      setState(() => _resendIn--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_controller.text.length != 6) return;
    setState(() => _loading = true);
    try {
      // The router moves on once the user is signed in.
      await ref.read(authProvider.notifier).verifyOtp(_request.phone, _controller.text);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        _controller.clear();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    try {
      final r = await ref.read(authProvider.notifier).requestOtp(_request.phone);
      setState(() => _request = r);
      _startTimer();
      if (mounted) showMessage(context, 'Code sent again');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Enter the code', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('Sent to ${_request.phone}', style: theme.textTheme.bodyMedium),
          if (_request.devCode != null) ...[
            const SizedBox(height: 8),
            Text('Development code: ${_request.devCode}',
                key: const Key('dev-code'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary)),
          ],
          const SizedBox(height: 24),
          TextField(
            key: const Key('otp-field'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            autofillHints: const [AutofillHints.oneTimeCode],
            style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 12),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(counterText: '', hintText: '••••••'),
            onChanged: (v) {
              if (v.length == 6) _verify();
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _verify,
            child: _loading ? const ButtonSpinner() : const Text('Verify'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _resendIn > 0 ? null : _resend,
            child: Text(_resendIn > 0 ? 'Resend code in ${_resendIn}s' : 'Resend code'),
          ),
        ],
      ),
    );
  }
}
