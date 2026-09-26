import 'package:flutter/foundation.dart';

/// Build-time configuration. Override with
/// `flutter run --dart-define=API_URL=https://cholo-api.example.workers.dev`.
class AppConfig {
  static const _apiUrl = String.fromEnvironment('API_URL');

  /// Base URL of the Cholo API. Defaults to a local `wrangler dev` server
  /// (10.0.2.2 is the host machine from the Android emulator).
  static String get apiUrl {
    if (_apiUrl.isNotEmpty) return _apiUrl;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8787';
    }
    return 'http://localhost:8787';
  }

  /// WebSocket base derived from [apiUrl].
  static String get wsUrl => apiUrl.replaceFirst(RegExp('^http'), 'ws');

  static const tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const userAgentPackage = 'com.cholo.app';
}
