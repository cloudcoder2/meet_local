import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/brand.dart';
import 'auth_controller.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CholoLogo(size: 56),
            const SizedBox(height: 32),
            if (auth.hasError) ...[
              Text(auth.error.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => ref.read(authProvider.notifier).refresh(),
                child: const Text('Try again'),
              ),
            ] else
              const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
