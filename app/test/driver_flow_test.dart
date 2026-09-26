import 'package:cholo/data/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fake_backend.dart';
import 'support/fakes.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Map<String, dynamic> _profile(String status) => {
      'status': status,
      'city': 'dhaka',
      'license_number': 'DL-1234',
      'total_trips': 0,
      'total_earnings': 0,
      'vehicles': [
        {'id': 'v1', 'vehicle_class': 'car', 'make': 'Toyota', 'model': 'Axio', 'color': 'White', 'plate_number': 'DHAKA-GA-1234', 'is_active': true},
      ],
    };

Map<String, dynamic> _earnings(int net, int trips) => {
      'currency': 'BDT',
      'today': {'trips': trips, 'gross': net, 'commission': 0, 'net': net},
      'week': {'trips': trips, 'gross': net, 'commission': 0, 'net': net},
      'month': {'trips': trips, 'gross': net, 'commission': 0, 'net': net},
      'daily': [
        for (var i = 0; i < 7; i++) {'date': '2026-09-${20 + i}', 'trips': i == 6 ? trips : 0, 'net': i == 6 ? net : 0},
      ],
      'lifetime': {'trips': trips, 'net': net},
    };

void _setUpView(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1850);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

Future<void> _openDriverMode(WidgetTester tester) async {
  await tester.pumpAndSettle();
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/driver');
  await settle(tester);
}

void main() {
  testWidgets('driver goes online, accepts an offer and completes the trip', (tester) async {
    _setUpView(tester);
    final h = TestHarness()..signIn(userJson(id: 'd1', name: 'Karim', role: 'driver'));
    var status = 'accepted';
    Map<String, dynamic>? startBody;
    final rider = {'id': 'u1', 'name': 'Nadia', 'phone': '+8801711000001', 'rating': 4.7, 'avatar_url': null, 'rating_count': 2};
    Map<String, dynamic> ride() {
      final r = rideJson(status: status, viewer: 'driver');
      r['rider'] = rider;
      r['otp'] = null;
      if (status == 'completed') {
        r['payment'] = {'amount': 43500, 'method': 'cash', 'status': 'paid', 'commission': 6525, 'driver_net': 36975};
      }
      return {'ride': r};
    }

    h.backend
      ..on('GET /v1/drivers/me', (_, _) => {'driver': _profile('approved')})
      ..on('GET /v1/drivers/me/status', (_, _) => {'online': false, 'ride_id': null, 'location': null})
      ..on('GET /v1/drivers/me/earnings', (_, _) => _earnings(120000, 3))
      ..on('POST /v1/drivers/me/online', (_, _) => {'online': true})
      ..on('POST /v1/drivers/me/offline', (_, _) => {'online': false})
      ..on('GET /v1/drivers/me/offer', (_, _) => {
            'offer': {
              'ride_id': 'r1',
              'expires_at': DateTime.now().millisecondsSinceEpoch + 15000,
              'pickup_distance_m': 450,
              'vehicle_class': 'car',
              'pickup': {'lat': 23.7925, 'lng': 90.4078, 'address': 'Gulshan 1'},
              'dropoff': {'lat': 23.7461, 'lng': 90.3742, 'address': 'Dhanmondi 27'},
              'distance_m': 7800,
              'duration_s': 1560,
              'total': 43500,
              'driver_earnings': 36975,
              'currency': 'BDT',
              'payment_method': 'cash',
              'rider': {'name': 'Nadia', 'rating': 4.7},
            },
          })
      ..on('POST /v1/rides/r1/accept', (_, _) => ride())
      ..on('GET /v1/rides/r1', (_, _) => ride())
      ..on('POST /v1/rides/r1/arrived', (_, _) {
        status = 'arrived';
        return ride();
      })
      ..on('POST /v1/rides/r1/start', (_, b) {
        startBody = b;
        status = 'in_progress';
        return ride();
      })
      ..on('POST /v1/rides/r1/complete', (_, _) {
        status = 'completed';
        return ride();
      });

    await tester.pumpWidget(h.app());
    await _openDriverMode(tester);
    expect(find.text("You're offline"), findsOneWidget);
    expect(find.text('৳1,200'), findsOneWidget);

    await tester.tap(find.byKey(const Key('toggle-online')));
    await settle(tester);
    expect(find.text("You're online"), findsOneWidget);
    expect(h.backend.calls, contains('POST /v1/drivers/me/online'));
    final dispatch = h.socket('/v1/drivers/me/ws');
    expect(dispatch.opened, isTrue);

    h.location.updates.add((point: h.location.point, heading: 90));
    await settle(tester);
    expect(dispatch.sent.last, {'type': 'location', 'lat': 23.7925, 'lng': 90.4078, 'heading': 90});

    dispatch.emit({'type': 'offer', 'offer': {'rideId': 'r1', 'expiresAt': 0, 'pickupDistanceM': 450}});
    await settle(tester);
    expect(find.byKey(const Key('offer-card')), findsOneWidget);
    expect(find.text('৳369.75'), findsOneWidget);

    await tester.tap(find.byKey(const Key('accept-offer')));
    await settle(tester);
    expect(find.text('Pick up Nadia'), findsOneWidget);

    await tester.tap(find.byKey(const Key('arrived')));
    await settle(tester);
    expect(find.text('Waiting for Nadia'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('otp-input')), '4821');
    await tester.tap(find.byKey(const Key('start-trip')));
    await settle(tester);
    expect(startBody, {'otp': '4821'});
    expect(find.text('Drop off Nadia'), findsOneWidget);
    expect(find.text('Collect ৳435 in cash'), findsOneWidget);

    await tester.tap(find.byKey(const Key('complete-trip')));
    await settle(tester);
    expect(find.text('Trip complete'), findsOneWidget);
    expect(find.text('Collect in cash'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a new driver registers and waits for approval', (tester) async {
    _setUpView(tester);
    final h = TestHarness()..signIn(userJson(id: 'u2', name: 'Selim'));
    Map<String, dynamic>? body;
    h.backend
      ..on('GET /v1/drivers/me', (_, _) => const Reply(404, {'error': {'code': 'not_found', 'message': 'Not a driver'}}))
      ..on('POST /v1/drivers', (_, b) {
        body = b;
        return Reply(201, {
          'user': userJson(id: 'u2', name: 'Selim', role: 'driver'),
          'driver': _profile('pending'),
          'access_token': 'a2',
          'refresh_token': 'r2',
          'expires_in': 3600,
        });
      });

    await tester.pumpWidget(h.app());
    await _openDriverMode(tester);
    expect(find.text('Earn with Cholo'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pump();
    expect(find.text('Required'), findsWidgets);

    await tester.tap(find.text('Car'));
    await tester.enterText(find.byKey(const Key('license-field')), 'DL-5555');
    await tester.enterText(find.byKey(const Key('make-field')), 'Toyota');
    await tester.enterText(find.byKey(const Key('model-field')), 'Premio');
    await tester.enterText(find.byKey(const Key('color-field')), 'Silver');
    await tester.enterText(find.byKey(const Key('plate-field')), 'dhaka-ga-5555');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await settle(tester);

    expect((body!['vehicle'] as Map)['vehicle_class'], 'car');
    expect(h.tokens.tokens!.access, 'a2');
    expect(find.text('Application under review'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('ApiException reads as its message', () {
    expect(const ApiException('x', 'Nope').toString(), 'Nope');
  });
}
