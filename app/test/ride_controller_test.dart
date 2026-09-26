import 'package:cholo/data/models.dart';
import 'package:cholo/features/ride/ride_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';
import 'support/fakes.dart';

void main() {
  late TestHarness h;
  late ProviderContainer container;

  setUp(() {
    h = TestHarness();
    container = ProviderContainer(overrides: h.overrides);
  });
  tearDown(() => container.dispose());

  test('resumes the active ride and follows socket events', () async {
    var status = 'accepted';
    h.backend
      ..on('GET /v1/rides/active', (_, _) => {'ride': rideJson(status: status)})
      ..on('GET /v1/rides/r1', (_, _) => {'ride': rideJson(status: status)});

    final session = await container.read(rideProvider.future);
    expect(session!.ride.status, RideStatus.accepted);
    final socket = h.socket('/v1/rides/r1/ws');
    expect(socket.opened, isTrue);

    socket.emit({
      'type': 'hello',
      'role': 'rider',
      'location': {'lat': 23.79, 'lng': 90.41, 'heading': 45, 'at': 0},
      'chat': [
        {'id': 'm1', 'from': 'driver', 'text': 'Coming', 'at': 1},
      ],
    });
    await Future<void>.delayed(Duration.zero);
    var s = container.read(rideProvider).value!;
    expect(s.driverLocation!.heading, 45);
    expect(s.chat.single.text, 'Coming');

    socket.emit({'type': 'driver_location', 'location': {'lat': 23.8, 'lng': 90.42, 'heading': null, 'at': 2}});
    socket.emit({'type': 'chat', 'message': {'id': 'm2', 'from': 'rider', 'text': 'OK', 'at': 3}});
    await Future<void>.delayed(Duration.zero);
    s = container.read(rideProvider).value!;
    expect(s.driverLocation!.lat, 23.8);
    expect(s.chat.map((m) => m.text), ['Coming', 'OK']);

    container.read(rideProvider.notifier).sendChat('  on my way ');
    expect(socket.sent.last, {'type': 'chat', 'text': 'on my way'});

    status = 'completed';
    socket.emit({'type': 'ride_updated', 'ride_id': 'r1', 'status': 'completed'});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(container.read(rideProvider).value!.ride.status, RideStatus.completed);
    expect(socket.closed, isTrue, reason: 'socket closes once the ride ends');

    container.read(rideProvider.notifier).dismiss();
    expect(container.read(rideProvider).value, isNull);
  });

  test('has no session without an active ride', () async {
    h.backend.on('GET /v1/rides/active', (_, _) => {'ride': null});
    expect(await container.read(rideProvider.future), isNull);
    expect(h.sockets, isEmpty);
  });
}
