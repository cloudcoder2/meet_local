import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'router.dart';

void main() {
  runApp(const ProviderScope(child: CholoApp()));
}

class CholoApp extends ConsumerWidget {
  const CholoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Cholo',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
