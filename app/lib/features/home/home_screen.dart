import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/location.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/cholo_map.dart';
import '../places/places_controller.dart';
import '../ride/ride_controller.dart';

final nearbyDriversProvider = FutureProvider.autoDispose<List<NearbyDriver>>((ref) async {
  final here = await ref.watch(currentLocationProvider.future);
  try {
    return await ref.read(apiProvider).nearbyDrivers(here);
  } catch (_) {
    return const [];
  }
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(seconds: 15), (_) => ref.invalidate(nearbyDriversProvider));
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Jump straight back into a ride that is still going (e.g. after an app restart).
    ref.listen(rideProvider, (_, next) {
      final ride = next.value?.ride;
      if (ride != null && ride.status.isActive) context.go('/ride');
    });
    final here = ref.watch(currentLocationProvider).value ?? defaultCenter;
    final nearby = ref.watch(nearbyDriversProvider).value ?? const [];
    final places = ref.watch(savedPlacesProvider).value ?? const [];
    final activeRide = ref.watch(rideProvider).value?.ride;
    final theme = Theme.of(context);

    return Scaffold(
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          CholoMap(
            key: ValueKey(here),
            center: here,
            pins: [
              MapPin(here, PinKind.me),
              for (final d in nearby) MapPin(LatLngPoint(d.lat, d.lng), PinKind.nearby, heading: d.heading, vehicleClass: d.vehicleClass),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Builder(
                builder: (context) => FloatingActionButton.small(
                  heroTag: 'menu',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  child: const Icon(Icons.menu),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (activeRide != null && activeRide.status.isActive) ...[
                      FilledButton.tonalIcon(
                        onPressed: () => context.go('/ride'),
                        icon: const Icon(Icons.local_taxi),
                        label: Text(activeRide.status.label),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text('Good to see you', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    InkWell(
                      key: const Key('where-to'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => context.push('/search'),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(children: [
                          const Icon(Icons.search),
                          const SizedBox(width: 12),
                          Text('Where to?', style: theme.textTheme.titleMedium),
                        ]),
                      ),
                    ),
                    if (places.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final p in places)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ActionChip(
                                  avatar: Icon(placeIcon(p.label), size: 18),
                                  label: Text(p.label ?? p.address),
                                  onPressed: () => context.push('/search', extra: p),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      nearby.isEmpty ? 'Looking for drivers nearby…' : '${nearby.length} drivers nearby',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

IconData placeIcon(String? label) => switch (label?.toLowerCase()) {
      'home' => Icons.home_outlined,
      'work' || 'office' => Icons.work_outline,
      _ => Icons.place_outlined,
    };
