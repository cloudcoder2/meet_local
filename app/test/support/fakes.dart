import 'dart:async';

import 'package:cholo/core/location.dart';
import 'package:cholo/data/cholo_api.dart';
import 'package:cholo/data/models.dart';
import 'package:cholo/data/ride_socket.dart';
import 'package:cholo/data/token_store.dart';
import 'package:cholo/features/ride/ride_controller.dart';
import 'package:cholo/main.dart';
import 'package:cholo/providers.dart';
import 'package:cholo/widgets/cholo_map.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'fake_backend.dart';

class FakeSocket implements LiveSocket {
  FakeSocket(this.path);

  @override
  final String path;
  final _controller = StreamController<Json>.broadcast();
  final sent = <Json>[];
  bool opened = false;
  bool closed = false;

  @override
  TokenStore get tokens => MemoryTokenStore();

  @override
  Future<void> Function()? get beforeConnect => null;

  @override
  Stream<Json> get messages => _controller.stream;

  void emit(Json msg) => _controller.add(msg);

  @override
  Future<void> open() async => opened = true;

  @override
  void send(Json message) => sent.add(message);

  @override
  Future<void> close() async => closed = true;
}

class FakeLocation implements LocationService {
  FakeLocation([this.point = const LatLngPoint(23.7925, 90.4078)]);
  LatLngPoint point;
  final updates = StreamController<({LatLngPoint point, double? heading})>.broadcast();

  @override
  Future<LatLngPoint> current() async => point;

  @override
  Stream<({LatLngPoint point, double? heading})> watch() => updates.stream;
}

/// Everything a widget test needs to run the whole app against fakes.
class TestHarness {
  TestHarness() {
    final f = fakeApi();
    backend = f.backend;
    tokens = f.tokens;
    api = f.api;
  }

  late final FakeBackend backend;
  late final MemoryTokenStore tokens;
  late final CholoApi api;
  final sockets = <FakeSocket>[];
  final location = FakeLocation();

  FakeSocket socket(String pathPrefix) => sockets.lastWhere((s) => s.path.startsWith(pathPrefix));

  List<Override> get overrides => [
        apiProvider.overrideWithValue(api),
        liveSocketFactoryProvider.overrideWithValue((path) {
          final s = FakeSocket(path);
          sockets.add(s);
          return s;
        }),
        locationServiceProvider.overrideWithValue(location),
        mapTilesEnabledProvider.overrideWithValue(false),
      ];

  /// Signs in [user] and stubs the endpoints every screen touches on start.
  void signIn(Map<String, dynamic> user, {Map<String, dynamic>? activeRide}) {
    tokens.tokens = const Tokens(access: 'a', refresh: 'r');
    backend
      ..on('GET /v1/me', (_, _) => {'user': user})
      ..on('GET /v1/rides/active', (_, _) => {'ride': activeRide})
      ..on('GET /v1/me/places', (_, _) => {'places': []})
      ..on('GET /v1/drivers/nearby', (_, _) => {'drivers': []})
      ..on('GET /v1/geo/reverse', (_, _) => {
            'result': {'name': 'Gulshan 1', 'address': 'Gulshan 1, Dhaka', 'lat': 23.7925, 'lng': 90.4078},
          });
  }

  Widget app() => ProviderScope(overrides: overrides, child: const CholoApp());
}
