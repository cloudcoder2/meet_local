import 'dart:convert';
import 'dart:typed_data';

import 'package:cholo/data/api_client.dart';
import 'package:cholo/data/cholo_api.dart';
import 'package:cholo/data/token_store.dart';
import 'package:dio/dio.dart';

typedef Handler = Object? Function(RequestOptions req, Map<String, dynamic> body);

/// A canned HTTP response with a status code.
class Reply {
  const Reply(this.status, this.body);
  final int status;
  final Object? body;
}

/// In-memory stand-in for the Cholo API. Register handlers by "METHOD /path";
/// a handler returns a JSON body (status 200) or a [Reply].
class FakeBackend implements HttpClientAdapter {
  final handlers = <String, Handler>{};
  final calls = <String>[];

  void on(String route, Handler handler) => handlers[route] = handler;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final route = '${options.method} ${options.uri.path}';
    calls.add(route);
    final body = options.data is Map ? Map<String, dynamic>.from(options.data as Map) : <String, dynamic>{};
    final handler = handlers[route];
    if (handler == null) return _json(404, {'error': {'code': 'not_found', 'message': 'No handler for $route'}});
    final Object? result;
    try {
      result = handler(options, body);
    } catch (e) {
      // Surface assertion failures from handlers instead of an opaque network error.
      // ignore: avoid_print
      print('FakeBackend handler for $route threw: $e');
      rethrow;
    }
    return result is Reply ? _json(result.status, result.body) : _json(200, result);
  }

  ResponseBody _json(int status, Object? body) => ResponseBody.fromString(
        body == null ? '' : jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

({CholoApi api, FakeBackend backend, MemoryTokenStore tokens}) fakeApi() {
  final backend = FakeBackend();
  final tokens = MemoryTokenStore();
  final dio = Dio()..httpClientAdapter = backend;
  return (api: CholoApi(ApiClient(baseUrl: 'http://test', tokens: tokens, dio: dio)), backend: backend, tokens: tokens);
}

Map<String, dynamic> userJson({String id = 'u1', String? name = 'Nadia', String role = 'rider'}) => {
      'id': id,
      'phone': '+8801711000001',
      'name': name,
      'email': null,
      'avatar_url': null,
      'role': role,
      'rating': null,
      'rating_count': 0,
      'created_at': 0,
    };

Map<String, dynamic> rideJson({String status = 'requested', String viewer = 'rider', Map<String, dynamic>? driver}) => {
      'id': 'r1',
      'status': status,
      'city': 'dhaka',
      'vehicle_class': 'car',
      'pickup': {'lat': 23.7925, 'lng': 90.4078, 'address': 'Gulshan 1'},
      'dropoff': {'lat': 23.7461, 'lng': 90.3742, 'address': 'Dhanmondi 27'},
      'distance_m': 7800,
      'duration_s': 1560,
      'surge': 1,
      'fare': 43500,
      'discount': 0,
      'total': 43500,
      'currency': 'BDT',
      'promo_code': null,
      'payment_method': 'cash',
      'requested_at': 1790000000000,
      'otp': status == 'accepted' || status == 'arrived' ? '4821' : null,
      'viewer': viewer,
      'driver': driver,
      'rider': null,
      'vehicle': driver == null
          ? null
          : {
              'id': 'v1',
              'vehicle_class': 'car',
              'make': 'Toyota',
              'model': 'Axio',
              'color': 'White',
              'plate_number': 'DHAKA-GA-1234',
              'is_active': true,
            },
      'payment': null,
      'my_rating': null,
    };
