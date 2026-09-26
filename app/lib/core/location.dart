import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../data/models.dart';

/// Dhaka city centre, used when location is unavailable.
const defaultCenter = LatLngPoint(23.8103, 90.4125);

class LocationUnavailable implements Exception {
  const LocationUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class LocationService {
  /// Current position; throws [LocationUnavailable] if permission is denied or GPS is off.
  Future<LatLngPoint> current();

  /// Position updates while the app is in use.
  Stream<({LatLngPoint point, double? heading})> watch();
}

class GeolocatorLocationService implements LocationService {
  Future<void> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable('Turn on location services to use your current location.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw const LocationUnavailable('Allow location access to use your current location.');
    }
  }

  @override
  Future<LatLngPoint> current() async {
    await _ensurePermission();
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
    );
    return LatLngPoint(p.latitude, p.longitude);
  }

  @override
  Stream<({LatLngPoint point, double? heading})> watch() async* {
    await _ensurePermission();
    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).map((p) => (point: LatLngPoint(p.latitude, p.longitude), heading: p.heading >= 0 ? p.heading : null));
  }
}

final locationServiceProvider = Provider<LocationService>((ref) => GeolocatorLocationService());

/// Best-effort current location; falls back to [defaultCenter].
final currentLocationProvider = FutureProvider<LatLngPoint>((ref) async {
  try {
    return await ref.read(locationServiceProvider).current();
  } catch (_) {
    return defaultCenter;
  }
});
