import 'package:cholo/data/api_client.dart';
import 'package:cholo/data/models.dart';
import 'package:cholo/data/token_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

void main() {
  test('maps API errors to ApiException', () async {
    final f = fakeApi();
    f.backend.on('POST /v1/auth/otp/request',
        (_, _) => const Reply(400, {'error': {'code': 'invalid_phone', 'message': 'Invalid phone number'}}));
    expect(
      () => f.api.requestOtp('123'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'invalid_phone').having((e) => e.status, 'status', 400)),
    );
  });

  test('stores tokens on login and sends them afterwards', () async {
    final f = fakeApi();
    f.backend.on('POST /v1/auth/otp/verify',
        (_, b) => {'access_token': 'a1', 'refresh_token': 'r1', 'is_new_user': true, 'user': userJson(name: null)});
    String? auth;
    f.backend.on('GET /v1/me', (req, _) {
      auth = req.headers['Authorization'] as String?;
      return {'user': userJson()};
    });

    final result = await f.api.verifyOtp('+8801711000001', '123456');
    expect(result.isNewUser, isTrue);
    expect(f.tokens.tokens!.access, 'a1');
    await f.api.me();
    expect(auth, 'Bearer a1');
  });

  test('refreshes an expired access token once and retries', () async {
    final f = fakeApi();
    f.tokens.tokens = const Tokens(access: 'old', refresh: 'r1');
    f.backend.on('GET /v1/me', (req, _) => req.headers['Authorization'] == 'Bearer new'
        ? {'user': userJson()}
        : const Reply(401, {'error': {'code': 'unauthorized', 'message': 'expired'}}));
    f.backend.on('POST /v1/auth/refresh', (_, b) {
      expect(b['refresh_token'], 'r1');
      return {'access_token': 'new', 'refresh_token': 'r2', 'expires_in': 3600};
    });

    final user = await f.api.me();
    expect(user.name, 'Nadia');
    expect(f.tokens.tokens!.refresh, 'r2');
    expect(f.backend.calls, ['GET /v1/me', 'POST /v1/auth/refresh', 'GET /v1/me']);
  });

  test('clears tokens when the refresh token is rejected', () async {
    final f = fakeApi();
    f.tokens.tokens = const Tokens(access: 'old', refresh: 'bad');
    f.backend.on('GET /v1/me', (_, _) => const Reply(401, {'error': {'code': 'unauthorized', 'message': 'expired'}}));
    f.backend.on('POST /v1/auth/refresh', (_, _) => const Reply(401, {'error': {'code': 'unauthorized', 'message': 'no'}}));

    await expectLater(f.api.me(), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'unauthorized', isTrue)));
    expect(f.tokens.tokens, isNull);
  });

  test('parses rides with driver details', () {
    final ride = Ride.fromJson(rideJson(
      status: 'accepted',
      driver: {'id': 'd1', 'name': 'Karim', 'phone': '+8801800000000', 'rating': 4.8, 'avatar_url': null, 'rating_count': 10},
    ));
    expect(ride.status, RideStatus.accepted);
    expect(ride.status.isActive, isTrue);
    expect(ride.driver!.name, 'Karim');
    expect(ride.vehicle!.description, 'White Toyota Axio');
    expect(ride.otp, '4821');
    expect(RideStatus.parse('in_progress'), RideStatus.inProgress);
    expect(RideStatus.parse('no_driver'), RideStatus.noDriver);
  });
}
