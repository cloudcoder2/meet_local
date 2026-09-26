import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/cholo_api.dart';
import '../../data/models.dart';
import '../../providers.dart';

/// The signed-in user, or null when signed out.
final authProvider = AsyncNotifierProvider<AuthController, User?>(AuthController.new);

class AuthController extends AsyncNotifier<User?> {
  CholoApi get _api => ref.read(apiProvider);

  @override
  Future<User?> build() async {
    if (await _api.tokens.read() == null) return null;
    try {
      return await _api.me();
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _api.logout();
        return null;
      }
      rethrow;
    }
  }

  Future<OtpRequestResult> requestOtp(String phone) => _api.requestOtp(phone);

  Future<LoginResult> verifyOtp(String phone, String code) async {
    final result = await _api.verifyOtp(phone, code);
    state = AsyncData(result.user);
    return result;
  }

  Future<void> updateProfile({String? name, String? email}) async {
    final user = await _api.updateProfile(name: name, email: email);
    state = AsyncData(user);
  }

  /// Replaces the cached user, e.g. after the role changed.
  void setUser(User user) => state = AsyncData(user);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> logout() async {
    await _api.logout();
    state = const AsyncData(null);
  }

  void sessionExpired() {
    if (state.value != null) state = const AsyncData(null);
  }
}
