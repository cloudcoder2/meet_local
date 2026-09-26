import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/config.dart';
import 'models.dart';
import 'token_store.dart';

typedef ChannelFactory = WebSocketChannel Function(Uri uri);

/// A JSON WebSocket to the API that reconnects with backoff until closed.
/// Used for the ride room (`/v1/rides/:id/ws`) and the driver dispatch socket
/// (`/v1/drivers/me/ws`).
class LiveSocket {
  LiveSocket({required this.path, required this.tokens, ChannelFactory? connect, String? baseUrl})
      : _connect = connect ?? WebSocketChannel.connect,
        _baseUrl = baseUrl ?? AppConfig.wsUrl;

  final String path;
  final TokenStore tokens;
  final ChannelFactory _connect;
  final String _baseUrl;

  final _messages = StreamController<Json>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _ping;
  Timer? _retry;
  int _attempt = 0;
  bool _closed = false;

  Stream<Json> get messages => _messages.stream;

  Future<void> open() async {
    if (_closed) return;
    final t = await tokens.read();
    if (t == null || _closed) return;
    final uri = Uri.parse('$_baseUrl$path?token=${Uri.encodeQueryComponent(t.access)}');
    try {
      final channel = _connect(uri);
      _channel = channel;
      await channel.ready;
      _attempt = 0;
      _sub = channel.stream.listen(
        (data) {
          try {
            _messages.add(jsonDecode(data as String) as Json);
          } catch (_) {
            // Ignore malformed frames.
          }
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
      );
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 25), (_) => send({'type': 'ping'}));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void send(Json message) {
    try {
      _channel?.sink.add(jsonEncode(message));
    } catch (_) {
      // Dropped; location updates are frequent and chat will surface its own error.
    }
  }

  void _scheduleReconnect() {
    _ping?.cancel();
    _sub?.cancel();
    _channel = null;
    if (_closed) return;
    final delay = Duration(seconds: [1, 2, 4, 8, 15][_attempt.clamp(0, 4)]);
    _attempt++;
    _retry?.cancel();
    _retry = Timer(delay, open);
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    _ping?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    await _messages.close();
  }
}
