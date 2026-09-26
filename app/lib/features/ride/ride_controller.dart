import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cholo_api.dart';
import '../../data/models.dart';
import '../../data/ride_socket.dart';
import '../../providers.dart';

/// Opens a live socket for an API path; overridden in tests.
final liveSocketFactoryProvider = Provider<LiveSocket Function(String path)>((ref) {
  final tokens = ref.watch(tokenStoreProvider);
  return (path) => LiveSocket(path: path, tokens: tokens);
});

class RideSession {
  const RideSession({required this.ride, this.driverLocation, this.chat = const []});

  final Ride ride;
  final DriverLocation? driverLocation;
  final List<ChatMessage> chat;

  RideSession copyWith({Ride? ride, DriverLocation? driverLocation, List<ChatMessage>? chat}) => RideSession(
        ride: ride ?? this.ride,
        driverLocation: driverLocation ?? this.driverLocation,
        chat: chat ?? this.chat,
      );
}

/// The user's current ride (as rider or driver), kept live over the ride's
/// WebSocket with polling as a fallback. Stays set after the ride ends so the
/// UI can show the receipt and rating until [dismiss] is called.
final rideProvider = AsyncNotifierProvider<RideController, RideSession?>(RideController.new);

class RideController extends AsyncNotifier<RideSession?> {
  static const pollInterval = Duration(seconds: 10);

  LiveSocket? _socket;
  StreamSubscription<Json>? _sub;
  Timer? _poll;

  @override
  Future<RideSession?> build() async {
    ref.onDispose(_disconnect);
    final ride = await ref.read(apiProvider).activeRide();
    if (ride == null) return null;
    _connect(ride);
    return RideSession(ride: ride);
  }

  RideSession? get _session => state.value;

  /// Starts tracking a ride returned by the API (after requesting or accepting it).
  void track(Ride ride) {
    _disconnect();
    state = AsyncData(RideSession(ride: ride));
    if (ride.status.isActive) _connect(ride);
  }

  Future<Ride> request({required Place pickup, required Place dropoff, required VehicleClass vehicleClass, String? promoCode}) async {
    final ride = await ref
        .read(apiProvider)
        .requestRide(pickup: pickup, dropoff: dropoff, vehicleClass: vehicleClass, promoCode: promoCode);
    track(ride);
    return ride;
  }

  Future<void> refresh() async {
    final current = _session;
    if (current == null) return;
    try {
      _apply(await ref.read(apiProvider).ride(current.ride.id));
    } catch (_) {
      // Keep the last known state; the next poll or socket event will retry.
    }
  }

  Future<void> cancel({String? reason}) => _act((api, id) => api.cancelRide(id, reason: reason));
  Future<void> rate(int stars, {String? comment}) => _act((api, id) => api.rateRide(id, stars, comment: comment));
  Future<void> markArrived() => _act((api, id) => api.markArrived(id));
  Future<void> start(String otp) => _act((api, id) => api.startRide(id, otp));
  Future<void> complete() => _act((api, id) => api.completeRide(id));

  void sendChat(String text) {
    if (text.trim().isEmpty) return;
    _socket?.send({'type': 'chat', 'text': text.trim()});
  }

  /// Clears a finished ride from the screen.
  void dismiss() {
    _disconnect();
    state = const AsyncData(null);
  }

  Future<void> _act(Future<Ride> Function(CholoApi api, String rideId) call) async {
    final current = _session;
    if (current == null) return;
    _apply(await call(ref.read(apiProvider), current.ride.id));
  }

  void _apply(Ride ride) {
    final current = _session;
    state = AsyncData(current == null ? RideSession(ride: ride) : current.copyWith(ride: ride));
    if (!ride.status.isActive) _disconnect();
  }

  void _connect(Ride ride) {
    final socket = ref.read(liveSocketFactoryProvider)('/v1/rides/${ride.id}/ws');
    _socket = socket;
    _sub = socket.messages.listen(_onMessage);
    socket.open();
    _poll = Timer.periodic(pollInterval, (_) => refresh());
  }

  void _onMessage(Json msg) {
    final current = _session;
    if (current == null) return;
    switch (msg['type']) {
      case 'hello':
        final loc = msg['location'] as Json?;
        state = AsyncData(current.copyWith(
          driverLocation: loc == null ? null : DriverLocation.fromJson(loc),
          chat: [for (final m in msg['chat'] as List? ?? const []) ChatMessage.fromJson(m as Json)],
        ));
      case 'ride_updated':
        refresh();
      case 'driver_location':
        state = AsyncData(current.copyWith(driverLocation: DriverLocation.fromJson(msg['location'] as Json)));
      case 'chat':
        state = AsyncData(current.copyWith(chat: [...current.chat, ChatMessage.fromJson(msg['message'] as Json)]));
    }
  }

  void _disconnect() {
    _poll?.cancel();
    _poll = null;
    _sub?.cancel();
    _sub = null;
    _socket?.close();
    _socket = null;
  }
}
