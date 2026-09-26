import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../providers.dart';

final savedPlacesProvider = AsyncNotifierProvider<SavedPlacesController, List<Place>>(SavedPlacesController.new);

class SavedPlacesController extends AsyncNotifier<List<Place>> {
  @override
  Future<List<Place>> build() => ref.read(apiProvider).savedPlaces();

  Future<void> add(String label, Place place) async {
    final saved = await ref.read(apiProvider).addPlace(label, place);
    state = AsyncData([...state.value ?? const [], saved]);
  }

  Future<void> remove(String id) async {
    await ref.read(apiProvider).deletePlace(id);
    state = AsyncData([for (final p in state.value ?? const <Place>[]) if (p.id != id) p]);
  }
}
