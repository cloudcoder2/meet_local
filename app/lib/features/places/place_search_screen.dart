import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/location.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../home/home_screen.dart';
import 'places_controller.dart';

enum _Field { pickup, dropoff }

/// Picks the pickup (defaults to the current location) and the destination,
/// then continues to fare selection.
class PlaceSearchScreen extends ConsumerStatefulWidget {
  const PlaceSearchScreen({super.key, this.initialDropoff});

  final Place? initialDropoff;

  @override
  ConsumerState<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _PlaceSearchScreenState extends ConsumerState<PlaceSearchScreen> {
  final _pickupText = TextEditingController();
  final _dropoffText = TextEditingController();
  final _dropoffFocus = FocusNode();
  final _pickupFocus = FocusNode();
  Place? _pickup;
  Place? _dropoff;
  _Field _active = _Field.dropoff;
  List<GeoResult> _results = const [];
  bool _searching = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _dropoff = widget.initialDropoff;
    _dropoffText.text = _dropoff?.label ?? _dropoff?.address ?? '';
    _pickupFocus.addListener(() => _pickupFocus.hasFocus ? setState(() => _active = _Field.pickup) : null);
    _dropoffFocus.addListener(() => _dropoffFocus.hasFocus ? setState(() => _active = _Field.dropoff) : null);
    _useCurrentLocation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pickupText.dispose();
    _dropoffText.dispose();
    _pickupFocus.dispose();
    _dropoffFocus.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    _pickupText.text = 'Current location';
    try {
      final here = await ref.read(locationServiceProvider).current();
      final geo = await ref.read(apiProvider).reverseGeocode(here);
      if (!mounted) return;
      _setPlace(_Field.pickup, Place(lat: here.lat, lng: here.lng, address: geo.address.isEmpty ? geo.name : geo.address, label: 'Current location'));
    } catch (e) {
      if (!mounted) return;
      _pickupText.clear();
      setState(() => _error = e is LocationUnavailable ? e.message : 'Enter your pickup point');
    }
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      try {
        final near = _pickup?.point ?? ref.read(currentLocationProvider).value;
        final results = await ref.read(apiProvider).searchPlaces(query, near: near);
        if (mounted) setState(() => _results = results);
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  void _setPlace(_Field field, Place place) {
    setState(() {
      _error = null;
      _results = const [];
      if (field == _Field.pickup) {
        _pickup = place;
        _pickupText.text = place.label ?? place.address;
      } else {
        _dropoff = place;
        _dropoffText.text = place.label ?? place.address;
      }
    });
    if (_pickup != null && _dropoff != null) {
      context.push('/book', extra: (pickup: _pickup!, dropoff: _dropoff!));
    } else if (field == _Field.pickup) {
      _dropoffFocus.requestFocus();
    }
  }

  Future<void> _pickOnMap() async {
    final start = (_active == _Field.pickup ? _pickup : _dropoff)?.point ?? _pickup?.point;
    final place = await context.push<Place>('/pick', extra: start);
    if (place != null) _setPlace(_active, place);
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedPlacesProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Plan your ride')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(children: [
              TextField(
                key: const Key('pickup-field'),
                controller: _pickupText,
                focusNode: _pickupFocus,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.trip_origin, color: Colors.green), hintText: 'Pickup'),
                onChanged: _onChanged,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('dropoff-field'),
                controller: _dropoffText,
                focusNode: _dropoffFocus,
                autofocus: widget.initialDropoff == null,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.flag), hintText: 'Where to?'),
                onChanged: _onChanged,
              ),
            ]),
          ),
          if (_searching) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.map_outlined),
                  title: const Text('Choose on map'),
                  onTap: _pickOnMap,
                ),
                if (_active == _Field.pickup)
                  ListTile(
                    leading: const Icon(Icons.my_location),
                    title: const Text('Use current location'),
                    onTap: _useCurrentLocation,
                  ),
                if (_results.isEmpty)
                  for (final p in saved)
                    ListTile(
                      leading: Icon(placeIcon(p.label)),
                      title: Text(p.label ?? ''),
                      subtitle: Text(p.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _setPlace(_active, p),
                    ),
                for (final r in _results)
                  ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(r.name),
                    subtitle: Text(r.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => _setPlace(_active, r.toPlace()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
