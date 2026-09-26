import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';
import 'support/fakes.dart';

Map<String, dynamic> _option(String cls, int total) => {
      'vehicle_class': cls,
      'label': 'Cholo ${cls == 'cng' ? 'CNG' : cls[0].toUpperCase() + cls.substring(1)}',
      'seats': cls == 'car' ? 4 : 1,
      'distance_m': 7800,
      'duration_s': 1560,
      'surge': 1,
      'fare': total,
      'discount': 0,
      'total': total,
    };

/// Lets async work (fake HTTP, socket events) finish without waiting for
/// never-ending progress animations like pumpAndSettle would.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('rider searches, books, rides and rates', (tester) async {
    tester.view.physicalSize = const Size(900, 1850);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    final h = TestHarness()..signIn(userJson());
    var status = 'requested';
    Map<String, dynamic>? requestBody;
    Map<String, dynamic>? ratingBody;
    final driver = {'id': 'd1', 'name': 'Karim', 'phone': '+8801800000000', 'rating': 4.9, 'avatar_url': null, 'rating_count': 3};
    Map<String, dynamic> ride() {
      final r = rideJson(status: status, driver: status == 'requested' ? null : driver);
      if (ratingBody != null) r['my_rating'] = ratingBody!['stars'];
      return {'ride': r};
    }

    h.backend
      ..on('GET /v1/geo/search', (_, _) => {
            'results': [
              {'name': 'Dhanmondi 27', 'address': 'Dhanmondi 27, Dhaka', 'lat': 23.7461, 'lng': 90.3742},
            ],
          })
      ..on('POST /v1/fares/estimate', (_, _) => {
            'city': 'dhaka',
            'currency': 'BDT',
            'promo_code': null,
            'options': [_option('bike', 16500), _option('cng', 26000), _option('car', 43500)],
          })
      ..on('POST /v1/rides', (_, b) {
        requestBody = b;
        return const Reply(201, null);
      })
      ..on('GET /v1/rides/r1', (_, _) => ride())
      ..on('POST /v1/rides/r1/rating', (_, b) {
        ratingBody = b;
        return ride();
      });
    // POST /v1/rides returns the new ride.
    h.backend.on('POST /v1/rides', (_, b) {
      requestBody = b;
      return Reply(201, ride());
    });

    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(find.text('Where to?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('where-to')));
    await tester.pumpAndSettle();
    expect(find.text('Current location'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('dropoff-field')), 'Dhanmondi');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dhanmondi 27'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a ride'), findsOneWidget);
    expect(find.text('৳435'), findsOneWidget);
    await tester.tap(find.byKey(const Key('fare-car')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('request-ride')));
    await settle(tester);
    expect(requestBody!['vehicle_class'], 'car');
    expect((requestBody!['pickup'] as Map)['address'], 'Gulshan 1, Dhaka');
    expect((requestBody!['dropoff'] as Map)['address'], 'Dhanmondi 27, Dhaka');
    expect(find.text('Finding your driver'), findsOneWidget);

    // The driver accepts; the ride room tells the app to refetch.
    status = 'accepted';
    h.socket('/v1/rides/r1/ws').emit({'type': 'ride_updated', 'ride_id': 'r1', 'status': 'accepted'});
    await settle(tester);
    expect(find.text('Driver on the way'), findsOneWidget);
    expect(find.text('Karim'), findsOneWidget);
    expect(find.byKey(const Key('ride-otp')), findsOneWidget);
    expect(find.text('4821'), findsOneWidget);

    status = 'completed';
    h.socket('/v1/rides/r1/ws').emit({'type': 'ride_updated', 'ride_id': 'r1', 'status': 'completed'});
    await settle(tester);
    expect(find.byKey(const Key('receipt-total')), findsOneWidget);

    await tester.tap(find.byKey(const Key('star-5')));
    await tester.pump();
    await tester.tap(find.text('Submit rating'));
    await settle(tester);
    expect(ratingBody, {'stars': 5});
    expect(find.textContaining('You rated your driver 5'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Where to?'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
