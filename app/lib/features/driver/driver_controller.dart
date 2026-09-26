import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/location.dart';
import '../../data/models.dart';
import '../../data/ride_socket.dart';
import '../../providers.dart';
import '../auth/auth_controller.dart';
import '../ride/ride_controller.dart';

class DriverState {
  const DriverState({required this.profile, this.online = false, this.offer, this.busy = false, this.error});

  /// Null when the user hasn't registered as a driver.
  final DriverProfile? profile;
  final bool online;
  final RideOffer? offer;

  /// True while a go-online/offline or accept/decline call is in flight.
  final bool busy;
  final String? error;

  DriverState copyWith({DriverProfile? profile, bool? online, RideOffer? offer, bool clearOffer = false, bool? busy, String? error}) =>
      DriverState(
        profile: profile ?? this.profile,
        online: online ?? this.online,
        offer: clearOffer ? null : offer ?? this.offer,
        busy: busy ?? this.busy,
        error: error,
      );
}

final driverProvider = AsyncNotifierProvider<DriverController, DriverState>(DriverController.new);

/// Driver availability: going online and offline, streaming location over the
/// dispatch socket, and handling ride offers.
class DriverController extends AsyncNotifier<DriverState> {
  /// Minimum gap between location updates sent to the server.
  static const locationInterval = Duration(seconds: 4);

  LiveSocket? _socket;
  StreamSubscription<Json>? _socketSub;
  StreamSubscription<({LatLngPoint point, double? heading})>? _locationSub;
  Timer? _offerExpiry;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<DriverState> build() async {
    ref.onDispose(_stopLive);
    final api = ref.read(apiProvider);
    final profile = await api.driverProfile();
    if (profile == null || !profile.isApproved) return DriverState(profile: profile);
    final status = await api.driverStatus();
    if (status.online) _startLive();
    return DriverState(profile: profile, online: status.online);
  }

  DriverState get _state => state.requireValue;

  Future<void> register({
    required String licenseNumber,
    required VehicleClass vehicleClass,
    required String make,
    required String model,
    required String color,
    required String plateNumber,
  }) async {
    final result = await ref.read(apiProvider).registerDriver(
          licenseNumber: licenseNumber,
          vehicleClass: vehicleClass,
          make: make,
          model: model,
          color: color,
          plateNumber: plateNumber,
        );
    // The API issued new tokens carrying the driver role; refresh the cached user too.
    ref.read(authProvider.notifier).setUser(result.user);
    state = AsyncData(DriverState(profile: result.driver));
  }

  Future<void> goOnline() async {
    state = AsyncData(_state.copyWith(busy: true));
    try {
      final here = await ref.read(locationServiceProvider).current();
      await ref.read(apiProvider).goOnline(here);
      _startLive();
      state = AsyncData(_state.copyWith(online: true, busy: false));
    } catch (e) {
      state = AsyncData(_state.copyWith(busy: false, error: e.toString()));
    }
  }

  Future<void> goOffline() async {
    state = AsyncData(_state.copyWith(busy: true));
    try {
      await ref.read(apiProvider).goOffline();
      _stopLive();
      state = AsyncData(_state.copyWith(online: false, busy: false, clearOffer: true));
    } catch (e) {
      state = AsyncData(_state.copyWith(busy: false, error: e.toString()));
    }
  }

  /// Accepts the current offer and hands the ride to [rideProvider]. Returns
  /// false if the offer was gone by the time the driver tapped.
  Future<bool> accept() async {
    final offer = _state.offer;
    if (offer == null) return false;
    state = AsyncData(_state.copyWith(busy: true));
    try {
      final ride = await ref.read(apiProvider).acceptRide(offer.rideId);
      ref.read(rideProvider.notifier).track(ride);
      state = AsyncData(_state.copyWith(busy: false, clearOffer: true));
      return true;
    } catch (e) {
      state = AsyncData(_state.copyWith(busy: false, clearOffer: true, error: e.toString()));
      return false;
    }
  }

  Future<void> decline() async {
    final offer = _state.offer;
    if (offer == null) return;
    state = AsyncData(_state.copyWith(clearOffer: true));
    try {
      await ref.read(apiProvider).declineRide(offer.rideId);
    } catch (_) {
      // The offer may already have expired; nothing to do.
    }
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  void _startLive() {
    _stopLive();
    final socket = ref.read(liveSocketFactoryProvider)('/v1/drivers/me/ws');
    _socket = socket;
    _socketSub = socket.messages.listen(_onMessage);
    socket.open();
    _locationSub = ref.read(locationServiceProvider).watch().listen((update) {
      final now = DateTime.now();
      if (now.difference(_lastSent) < locationInterval) return;
      _lastSent = now;
      socket.send({'type': 'location', 'lat': update.point.lat, 'lng': update.point.lng, 'heading': update.heading});
    }, onError: (_) {});
  }

  void _stopLive() {
    _offerExpiry?.cancel();
    _locationSub?.cancel();
    _locationSub = null;
    _socketSub?.cancel();
    _socketSub = null;
    _socket?.close();
    _socket = null;
  }

  Future<void> _onMessage(Json msg) async {
    switch (msg['type']) {
      case 'offer':
        // The push carries only the ride id; fetch what the driver needs to decide.
        final offer = await ref.read(apiProvider).currentOffer();
        if (offer == null || !state.hasValue) return;
        state = AsyncData(_state.copyWith(offer: offer));
        _offerExpiry?.cancel();
        final left = DateTime.fromMillisecondsSinceEpoch(offer.expiresAt).difference(DateTime.now());
        _offerExpiry = Timer(left.isNegative ? Duration.zero : left, () {
          if (state.value?.offer?.rideId == offer.rideId) state = AsyncData(_state.copyWith(clearOffer: true));
        });
      case 'offer_cancelled':
        if (state.value?.offer?.rideId == msg['rideId']) state = AsyncData(_state.copyWith(clearOffer: true));
    }
  }
}
