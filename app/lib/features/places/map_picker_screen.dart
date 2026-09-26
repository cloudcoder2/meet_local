import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/location.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../widgets/cholo_map.dart';

/// Drag the map under a fixed pin to choose a point; returns a [Place].
class MapPickerScreen extends ConsumerStatefulWidget {
  const MapPickerScreen({super.key, this.start});

  final LatLngPoint? start;

  @override
  ConsumerState<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends ConsumerState<MapPickerScreen> {
  late LatLngPoint _center = widget.start ?? ref.read(currentLocationProvider).value ?? defaultCenter;
  GeoResult? _result;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _lookup(_center);
  }

  Future<void> _lookup(LatLngPoint p) async {
    setState(() {
      _center = p;
      _loading = true;
    });
    try {
      final r = await ref.read(apiProvider).reverseGeocode(p);
      if (mounted && _center == p) setState(() => _result = r);
    } catch (_) {
      if (mounted) setState(() => _result = GeoResult(name: 'Pinned location', address: '', lat: p.lat, lng: p.lng));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose on map')),
      body: Stack(
        children: [
          CholoMap(center: _center, zoom: 17, onCameraIdle: _lookup),
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 40),
                child: Icon(Icons.location_on, size: 48, color: CholoColors.green),
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
                    Text(_result?.name ?? 'Finding address…', style: Theme.of(context).textTheme.titleMedium),
                    if ((_result?.address ?? '').isNotEmpty) Text(_result!.address),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loading || _result == null
                          ? null
                          : () => context.pop(Place(
                                lat: _center.lat,
                                lng: _center.lng,
                                address: _result!.address.isEmpty ? _result!.name : _result!.address,
                                label: _result!.name,
                              )),
                      child: const Text('Confirm location'),
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
