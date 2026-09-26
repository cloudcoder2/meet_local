import 'api_client.dart';
import 'models.dart';
import 'token_store.dart';

class OtpRequestResult {
  const OtpRequestResult({required this.phone, required this.expiresIn, this.devCode});
  final String phone;
  final int expiresIn;

  /// Returned by the API outside production so the app works without SMS.
  final String? devCode;
}

class LoginResult {
  const LoginResult({required this.user, required this.isNewUser});
  final User user;
  final bool isNewUser;
}

/// Typed wrapper around every Cholo API endpoint.
class CholoApi {
  CholoApi(this.client);

  final ApiClient client;

  TokenStore get tokens => client.tokens;

  // ---- auth -----------------------------------------------------------------

  Future<OtpRequestResult> requestOtp(String phone) async {
    final j = await client.post('/v1/auth/otp/request', {'phone': phone}, false);
    return OtpRequestResult(
        phone: j['phone'] as String, expiresIn: (j['expires_in'] as num).toInt(), devCode: j['dev_code'] as String?);
  }

  Future<LoginResult> verifyOtp(String phone, String code) async {
    final j = await client.post('/v1/auth/otp/verify', {'phone': phone, 'code': code}, false);
    await _saveTokens(j);
    return LoginResult(user: User.fromJson(j['user'] as Json), isNewUser: j['is_new_user'] as bool? ?? false);
  }

  Future<void> _saveTokens(Json j) =>
      tokens.write(Tokens(access: j['access_token'] as String, refresh: j['refresh_token'] as String));

  Future<void> logout() => tokens.clear();

  // ---- profile ----------------------------------------------------------------

  Future<User> me() async => User.fromJson((await client.get('/v1/me'))['user'] as Json);

  Future<User> updateProfile({String? name, String? email}) async {
    final j = await client.patch('/v1/me', {'name': ?name, 'email': ?email});
    return User.fromJson(j['user'] as Json);
  }

  Future<List<Place>> savedPlaces() async =>
      [for (final p in (await client.get('/v1/me/places'))['places'] as List) Place.fromJson(p as Json)];

  Future<Place> addPlace(String label, Place place) async =>
      Place.fromJson((await client.post('/v1/me/places', {'label': label, ...place.toJson()}))['place'] as Json);

  Future<void> deletePlace(String id) => client.delete('/v1/me/places/$id');

  // ---- fares and rides --------------------------------------------------------

  Future<FareEstimate> estimate(LatLngPoint pickup, LatLngPoint dropoff, {String? promoCode}) async =>
      FareEstimate.fromJson(await client.post('/v1/fares/estimate', {
        'pickup': pickup.toJson(),
        'dropoff': dropoff.toJson(),
        'promo_code': ?promoCode,
      }));

  Future<List<NearbyDriver>> nearbyDrivers(LatLngPoint p) async => [
        for (final d in (await client.get('/v1/drivers/nearby', query: {'lat': p.lat, 'lng': p.lng}))['drivers'] as List)
          NearbyDriver.fromJson(d as Json),
      ];

  Future<Ride> requestRide({
    required Place pickup,
    required Place dropoff,
    required VehicleClass vehicleClass,
    String? promoCode,
  }) async =>
      _ride(await client.post('/v1/rides', {
        'pickup': pickup.toJson(),
        'dropoff': dropoff.toJson(),
        'vehicle_class': vehicleClass.name,
        'promo_code': ?promoCode,
      }));

  Future<Ride?> activeRide() async {
    final j = await client.get('/v1/rides/active');
    return j['ride'] == null ? null : Ride.fromJson(j['ride'] as Json);
  }

  Future<Ride> ride(String id) async => _ride(await client.get('/v1/rides/$id'));

  Future<({List<Ride> rides, int? nextBefore})> rideHistory({bool asDriver = false, int? before}) async {
    final j = await client.get('/v1/rides', query: {'role': asDriver ? 'driver' : 'rider', 'before': ?before});
    return (
      rides: [for (final r in j['rides'] as List) Ride.fromJson(r as Json)],
      nextBefore: (j['next_before'] as num?)?.toInt(),
    );
  }

  Future<Ride> cancelRide(String id, {String? reason}) async =>
      _ride(await client.post('/v1/rides/$id/cancel', {'reason': ?reason}));

  Future<Ride> rateRide(String id, int stars, {String? comment}) async =>
      _ride(await client.post('/v1/rides/$id/rating', {'stars': stars, 'comment': ?comment}));

  // ---- driver -------------------------------------------------------------------

  Future<({User user, DriverProfile driver})> registerDriver({
    required String licenseNumber,
    required VehicleClass vehicleClass,
    required String make,
    required String model,
    required String color,
    required String plateNumber,
  }) async {
    final j = await client.post('/v1/drivers', {
      'license_number': licenseNumber,
      'vehicle': {
        'vehicle_class': vehicleClass.name,
        'make': make,
        'model': model,
        'color': color,
        'plate_number': plateNumber,
      },
    });
    await _saveTokens(j);
    return (user: User.fromJson(j['user'] as Json), driver: DriverProfile.fromJson(j['driver'] as Json));
  }

  Future<DriverProfile?> driverProfile() async {
    try {
      return DriverProfile.fromJson((await client.get('/v1/drivers/me'))['driver'] as Json);
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<void> goOnline(LatLngPoint p) => client.post('/v1/drivers/me/online', p.toJson());

  Future<void> goOffline() => client.post('/v1/drivers/me/offline');

  Future<({bool online, String? rideId})> driverStatus() async {
    final j = await client.get('/v1/drivers/me/status');
    return (online: j['online'] as bool, rideId: j['ride_id'] as String?);
  }

  Future<RideOffer?> currentOffer() async {
    final j = await client.get('/v1/drivers/me/offer');
    return j['offer'] == null ? null : RideOffer.fromJson(j['offer'] as Json);
  }

  Future<Ride> acceptRide(String id) async => _ride(await client.post('/v1/rides/$id/accept'));

  Future<void> declineRide(String id) => client.post('/v1/rides/$id/decline');

  Future<Ride> markArrived(String id) async => _ride(await client.post('/v1/rides/$id/arrived'));

  Future<Ride> startRide(String id, String otp) async => _ride(await client.post('/v1/rides/$id/start', {'otp': otp}));

  Future<Ride> completeRide(String id) async => _ride(await client.post('/v1/rides/$id/complete'));

  Future<Earnings> earnings() async => Earnings.fromJson(await client.get('/v1/drivers/me/earnings'));

  // ---- places -----------------------------------------------------------------

  Future<List<GeoResult>> searchPlaces(String query, {LatLngPoint? near}) async {
    final j = await client.get('/v1/geo/search', query: {'q': query, 'lat': ?near?.lat, 'lng': ?near?.lng});
    return [for (final r in j['results'] as List) GeoResult.fromJson(r as Json)];
  }

  Future<GeoResult> reverseGeocode(LatLngPoint p) async =>
      GeoResult.fromJson((await client.get('/v1/geo/reverse', query: {'lat': p.lat, 'lng': p.lng}))['result'] as Json);

  Ride _ride(Json j) => Ride.fromJson(j['ride'] as Json);
}
