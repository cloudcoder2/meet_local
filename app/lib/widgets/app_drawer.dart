import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import 'brand.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;
    void go(String path) {
      Navigator.of(context).pop();
      context.push(path);
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.all(20), child: CholoLogo(size: 32)),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(user?.name ?? ''),
              subtitle: Text(user?.phone ?? ''),
              onTap: () => go('/profile'),
            ),
            const Divider(),
            ListTile(leading: const Icon(Icons.history), title: const Text('Your trips'), onTap: () => go('/trips')),
            ListTile(leading: const Icon(Icons.bookmark_outline), title: const Text('Saved places'), onTap: () => go('/places')),
            ListTile(
              leading: const Icon(Icons.local_taxi_outlined),
              title: Text(user?.isDriver == true ? 'Driver mode' : 'Drive with Cholo'),
              onTap: () => go('/driver'),
            ),
            const Spacer(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Log out'),
              onTap: () => ref.read(authProvider.notifier).logout(),
            ),
          ],
        ),
      ),
    );
  }
}
