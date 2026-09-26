import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/cholo_api.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/name_screen.dart';
import 'features/auth/otp_screen.dart';
import 'features/auth/phone_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/home/home_screen.dart';
import 'data/models.dart';
import 'features/booking/book_screen.dart';
import 'features/places/map_picker_screen.dart';
import 'features/places/place_search_screen.dart';
import 'features/places/saved_places_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/ride/ride_screen.dart';
import 'features/trips/trips_screen.dart';

/// Decides where a user may go based on their auth state; null means "stay".
@visibleForTesting
String? authRedirect(AsyncValue<Object?> auth, bool hasName, String location) {
  final onLogin = location.startsWith('/login');
  if (auth.isLoading || auth.hasError) return location == '/splash' ? null : '/splash';
  if (auth.value == null) return onLogin ? null : '/login';
  if (!hasName) return location == '/welcome' ? null : '/welcome';
  if (onLogin || location == '/splash' || location == '/welcome') return '/';
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      return authRedirect(auth, auth.value?.hasName ?? false, state.matchedLocation);
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const PhoneScreen()),
      GoRoute(path: '/login/otp', builder: (_, s) => OtpScreen(request: s.extra! as OtpRequestResult)),
      GoRoute(path: '/welcome', builder: (_, _) => const NameScreen()),
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/search', builder: (_, s) => PlaceSearchScreen(initialDropoff: s.extra as Place?)),
      GoRoute(path: '/pick', builder: (_, s) => MapPickerScreen(start: s.extra as LatLngPoint?)),
      GoRoute(path: '/book', builder: (_, s) => BookScreen(trip: s.extra! as Trip)),
      GoRoute(path: '/ride', builder: (_, _) => const RideScreen()),
      GoRoute(path: '/trips', builder: (_, _) => const TripsScreen()),
      GoRoute(path: '/places', builder: (_, _) => const SavedPlacesScreen()),
    ],
  );
});
