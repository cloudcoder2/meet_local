import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Tokens {
  const Tokens({required this.access, required this.refresh});
  final String access;
  final String refresh;
}

abstract class TokenStore {
  Future<Tokens?> read();
  Future<void> write(Tokens tokens);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _accessKey = 'cholo.access_token';
  static const _refreshKey = 'cholo.refresh_token';

  @override
  Future<Tokens?> read() async {
    final access = await _storage.read(key: _accessKey);
    final refresh = await _storage.read(key: _refreshKey);
    if (access == null || refresh == null) return null;
    return Tokens(access: access, refresh: refresh);
  }

  @override
  Future<void> write(Tokens tokens) async {
    await _storage.write(key: _accessKey, value: tokens.access);
    await _storage.write(key: _refreshKey, value: tokens.refresh);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}

/// In-memory store for tests.
class MemoryTokenStore implements TokenStore {
  Tokens? tokens;

  @override
  Future<Tokens?> read() async => tokens;

  @override
  Future<void> write(Tokens t) async => tokens = t;

  @override
  Future<void> clear() async => tokens = null;
}
