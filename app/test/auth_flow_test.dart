import 'package:cholo/main.dart';
import 'package:cholo/providers.dart';
import 'package:cholo/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

void main() {
  group('authRedirect', () {
    test('routes by auth state', () {
      expect(authRedirect(const AsyncLoading(), false, '/'), '/splash');
      expect(authRedirect(const AsyncData(null), false, '/'), '/login');
      expect(authRedirect(const AsyncData(null), false, '/login/otp'), isNull);
      expect(authRedirect(const AsyncData('user'), false, '/'), '/welcome');
      expect(authRedirect(const AsyncData('user'), true, '/login'), '/');
      expect(authRedirect(const AsyncData('user'), true, '/profile'), isNull);
    });
  });

  testWidgets('signs up with phone, code and name', (tester) async {
    final f = fakeApi();
    String? name;
    String? code;
    f.backend
      ..on('POST /v1/auth/otp/request', (_, b) => {'phone': '+8801711000001', 'expires_in': 300, 'dev_code': '123456'})
      ..on('POST /v1/auth/otp/verify', (_, b) {
        code = b['code'] as String;
        return {'access_token': 'a', 'refresh_token': 'r', 'is_new_user': true, 'user': userJson(name: null)};
      })
      ..on('PATCH /v1/me', (_, b) {
        name = b['name'] as String;
        return {'user': userJson(name: name)};
      });

    await tester.pumpWidget(ProviderScope(
      overrides: [apiProvider.overrideWithValue(f.api)],
      child: const CholoApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Enter your mobile number'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('phone-field')), '0123');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.textContaining('valid mobile number'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('phone-field')), '01711000001');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Development code: 123456'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('otp-field')), '123456');
    await tester.pumpAndSettle();
    expect(code, '123456');
    expect(find.text("What's your name?"), findsOneWidget);

    await tester.enterText(find.byKey(const Key('name-field')), 'Nadia');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(name, 'Nadia');
    expect(find.text('Where to?'), findsOneWidget);
  });
}
