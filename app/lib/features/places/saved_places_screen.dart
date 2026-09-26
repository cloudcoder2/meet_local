import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../widgets/feedback.dart';
import '../home/home_screen.dart';
import 'places_controller.dart';

class SavedPlacesScreen extends ConsumerWidget {
  const SavedPlacesScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final place = await context.push<Place>('/pick');
    if (place == null || !context.mounted) return;
    final controller = TextEditingController(text: place.label == 'Pinned location' ? '' : 'Home');
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name this place'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(place.address),
          const SizedBox(height: 12),
          TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'Home, Work, Gym…')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (label == null || label.isEmpty) return;
    try {
      await ref.read(savedPlacesProvider.notifier).add(label, place);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(savedPlacesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Saved places')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add place'),
      ),
      body: places.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(savedPlacesProvider)),
        data: (list) => list.isEmpty
            ? const Center(child: Text('Save Home and Work for one-tap booking'))
            : ListView(children: [
                for (final p in list)
                  ListTile(
                    leading: Icon(placeIcon(p.label)),
                    title: Text(p.label ?? ''),
                    subtitle: Text(p.address),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => ref.read(savedPlacesProvider.notifier).remove(p.id!),
                    ),
                  ),
              ]),
      ),
    );
  }
}
