import 'dart:async';
import 'dart:convert';

import 'package:cholo/data/api_client.dart';
import 'package:cholo/data/ride_socket.dart';
import 'package:cholo/data/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:async/async.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'support/fake_backend.dart';

String jwt(DateTime exp) {
  String part(Map<String, Object> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

class _FakeChannel extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  final _in = StreamController<dynamic>();
  final _out = StreamController<dynamic>.broadcast();

  @override
  Stream<dynamic> get stream => _in.stream;
  @override
  WebSocketSink get sink => _Sink(_out.sink);
  @override
  Future<void> get ready => Future.value();
  @override
  String? get protocol => null;
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
}

class _Sink extends DelegatingStreamSink<dynamic> implements WebSocketSink {
  _Sink(super.sink);
  @override
  Future<void> close([int? closeCode, String? closeReason]) => super.close();
}

void main() {
  test('reads the expiry from an access token', () {
    final exp = DateTime.fromMillisecondsSinceEpoch(1790000000000);
    expect(accessTokenExpiry(jwt(exp)), exp);
    expect(accessTokenExpiry('not-a-jwt'), isNull);
  });

  test('refreshes an expired token before opening a socket', () async {
    final f = fakeApi();
    final expired = jwt(DateTime.now().subtract(const Duration(minutes: 5)));
    final fresh = jwt(DateTime.now().add(const Duration(hours: 1)));
    f.tokens.tokens = Tokens(access: expired, refresh: 'r1');
    f.backend.on('POST /v1/auth/refresh', (_, _) => {'access_token': fresh, 'refresh_token': 'r2', 'expires_in': 3600});

    Uri? opened;
    final socket = LiveSocket(
      path: '/v1/drivers/me/ws',
      tokens: f.tokens,
      beforeConnect: f.api.client.ensureFreshToken,
      baseUrl: 'ws://test',
      connect: (uri) {
        opened = uri;
        return _FakeChannel();
      },
    );
    await socket.open();
    expect(opened!.queryParameters['token'], fresh);
    await socket.close();
  });

  test('keeps a token that is still valid', () async {
    final f = fakeApi();
    final valid = jwt(DateTime.now().add(const Duration(minutes: 30)));
    f.tokens.tokens = Tokens(access: valid, refresh: 'r1');
    await f.api.client.ensureFreshToken();
    expect(f.backend.calls, isEmpty);
    expect(f.tokens.tokens!.access, valid);
  });
}
