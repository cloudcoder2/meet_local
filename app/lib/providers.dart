import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config.dart';
import 'data/api_client.dart';
import 'data/cholo_api.dart';
import 'data/token_store.dart';
import 'features/auth/auth_controller.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final apiProvider = Provider<CholoApi>((ref) {
  final client = ApiClient(
    baseUrl: AppConfig.apiUrl,
    tokens: ref.watch(tokenStoreProvider),
    onSessionExpired: () => ref.read(authProvider.notifier).sessionExpired(),
  );
  return CholoApi(client);
});
