// Plain data classes for API payloads. The API uses snake_case JSON and money in
// paisa (1/100 taka).

typedef Json = Map<String, dynamic>;

int _int(Object? v) => (v as num?)?.toInt() ?? 0;
double _double(Object? v) => (v as num?)?.toDouble() ?? 0;

class User {
  const User({
    required this.id,
    required this.phone,
    required this.role,
    this.name,
    this.email,
    this.avatarUrl,
    this.rating,
    this.ratingCount = 0,
  });

  final String id;
  final String phone;
  final String? name;
  final String? email;
  final String? avatarUrl;
  final String role;
  final double? rating;
  final int ratingCount;

  bool get isDriver => role == 'driver';
  bool get hasName => (name ?? '').trim().isNotEmpty;

  factory User.fromJson(Json j) => User(
        id: j['id'] as String,
        phone: j['phone'] as String,
        name: j['name'] as String?,
        email: j['email'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        role: j['role'] as String? ?? 'rider',
        rating: (j['rating'] as num?)?.toDouble(),
        ratingCount: _int(j['rating_count']),
      );
}

class LatLngPoint {
  const LatLngPoint(this.lat, this.lng);
  final double lat;
  final double lng;

  factory LatLngPoint.fromJson(Json j) => LatLngPoint(_double(j['lat']), _double(j['lng']));
  Json toJson() => {'lat': lat, 'lng': lng};
}

class Place {
  const Place({required this.lat, required this.lng, required this.address, this.id, this.label});

  final String? id;
  final String? label;
  final String address;
  final double lat;
  final double lng;

  LatLngPoint get point => LatLngPoint(lat, lng);

  factory Place.fromJson(Json j) => Place(
        id: j['id'] as String?,
        label: j['label'] as String?,
        address: j['address'] as String? ?? '',
        lat: _double(j['lat']),
        lng: _double(j['lng']),
      );

  Json toJson() => {'lat': lat, 'lng': lng, 'address': address};
}

enum VehicleClass {
  bike('Bike'),
  cng('CNG'),
  car('Car');

  const VehicleClass(this.label);
  final String label;

  static VehicleClass parse(String v) => VehicleClass.values.byName(v);
}

class FareOption {
  const FareOption({
    required this.vehicleClass,
    required this.label,
    required this.seats,
    required this.distanceM,
    required this.durationS,
    required this.surge,
    required this.fare,
    required this.discount,
    required this.total,
  });

  final VehicleClass vehicleClass;
  final String label;
  final int seats;
  final int distanceM;
  final int durationS;
  final double surge;
  final int fare;
  final int discount;
  final int total;

  factory FareOption.fromJson(Json j) => FareOption(
        vehicleClass: VehicleClass.parse(j['vehicle_class'] as String),
        label: j['label'] as String? ?? '',
        seats: _int(j['seats']),
        distanceM: _int(j['distance_m']),
        durationS: _int(j['duration_s']),
        surge: _double(j['surge']),
        fare: _int(j['fare']),
        discount: _int(j['discount']),
        total: _int(j['total']),
      );
}

class FareEstimate {
  const FareEstimate({required this.currency, required this.options, this.promoCode});
  final String currency;
  final String? promoCode;
  final List<FareOption> options;

  factory FareEstimate.fromJson(Json j) => FareEstimate(
        currency: j['currency'] as String? ?? 'BDT',
        promoCode: j['promo_code'] as String?,
        options: [for (final o in j['options'] as List) FareOption.fromJson(o as Json)],
      );
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.vehicleClass,
    required this.make,
    required this.model,
    required this.color,
    required this.plateNumber,
    required this.isActive,
  });

  final String id;
  final VehicleClass vehicleClass;
  final String make;
  final String model;
  final String color;
  final String plateNumber;
  final bool isActive;

  String get description => '$color $make $model';

  factory Vehicle.fromJson(Json j) => Vehicle(
        id: j['id'] as String,
        vehicleClass: VehicleClass.parse(j['vehicle_class'] as String),
        make: j['make'] as String,
        model: j['model'] as String,
        color: j['color'] as String,
        plateNumber: j['plate_number'] as String,
        isActive: j['is_active'] as bool? ?? false,
      );
}

class Person {
  const Person({required this.id, this.name, this.phone, this.rating, this.avatarUrl});
  final String id;
  final String? name;
  final String? phone;
  final double? rating;
  final String? avatarUrl;

  factory Person.fromJson(Json j) => Person(
        id: j['id'] as String,
        name: j['name'] as String?,
        phone: j['phone'] as String?,
        rating: (j['rating'] as num?)?.toDouble(),
        avatarUrl: j['avatar_url'] as String?,
      );
}

enum RideStatus {
  requested,
  accepted,
  arrived,
  inProgress,
  completed,
  cancelled,
  noDriver;

  static RideStatus parse(String v) => switch (v) {
        'in_progress' => RideStatus.inProgress,
        'no_driver' => RideStatus.noDriver,
        _ => RideStatus.values.byName(v),
      };

  bool get isActive => const [requested, accepted, arrived, inProgress].contains(this);
  bool get hasDriver => const [accepted, arrived, inProgress, completed].contains(this);

  String get label => switch (this) {
        requested => 'Finding your driver',
        accepted => 'Driver on the way',
        arrived => 'Driver has arrived',
        inProgress => 'On trip',
        completed => 'Completed',
        cancelled => 'Cancelled',
        noDriver => 'No drivers available',
      };
}

class Payment {
  const Payment({required this.amount, required this.method, required this.status, this.driverNet, this.commission});
  final int amount;
  final String method;
  final String status;
  final int? driverNet;
  final int? commission;

  factory Payment.fromJson(Json j) => Payment(
        amount: _int(j['amount']),
        method: j['method'] as String,
        status: j['status'] as String,
        driverNet: (j['driver_net'] as num?)?.toInt(),
        commission: (j['commission'] as num?)?.toInt(),
      );
}

class Ride {
  const Ride({
    required this.id,
    required this.status,
    required this.vehicleClass,
    required this.pickup,
    required this.dropoff,
    required this.distanceM,
    required this.durationS,
    required this.fare,
    required this.discount,
    required this.total,
    required this.currency,
    required this.paymentMethod,
    required this.viewer,
    required this.requestedAt,
    this.otp,
    this.driver,
    this.rider,
    this.vehicle,
    this.payment,
    this.myRating,
    this.cancelledBy,
    this.completedAt,
  });

  final String id;
  final RideStatus status;
  final VehicleClass vehicleClass;
  final Place pickup;
  final Place dropoff;
  final int distanceM;
  final int durationS;
  final int fare;
  final int discount;
  final int total;
  final String currency;
  final String paymentMethod;
  final String viewer;
  final int requestedAt;
  final String? otp;
  final Person? driver;
  final Person? rider;
  final Vehicle? vehicle;
  final Payment? payment;
  final int? myRating;
  final String? cancelledBy;
  final int? completedAt;

  bool get isDriverView => viewer == 'driver';

  factory Ride.fromJson(Json j) => Ride(
        id: j['id'] as String,
        status: RideStatus.parse(j['status'] as String),
        vehicleClass: VehicleClass.parse(j['vehicle_class'] as String),
        pickup: Place.fromJson(j['pickup'] as Json),
        dropoff: Place.fromJson(j['dropoff'] as Json),
        distanceM: _int(j['distance_m']),
        durationS: _int(j['duration_s']),
        fare: _int(j['fare']),
        discount: _int(j['discount']),
        total: _int(j['total']),
        currency: j['currency'] as String? ?? 'BDT',
        paymentMethod: j['payment_method'] as String? ?? 'cash',
        viewer: j['viewer'] as String? ?? 'rider',
        requestedAt: _int(j['requested_at']),
        otp: j['otp'] as String?,
        driver: j['driver'] == null ? null : Person.fromJson(j['driver'] as Json),
        rider: j['rider'] == null ? null : Person.fromJson(j['rider'] as Json),
        vehicle: j['vehicle'] == null ? null : Vehicle.fromJson(j['vehicle'] as Json),
        payment: j['payment'] == null ? null : Payment.fromJson(j['payment'] as Json),
        myRating: (j['my_rating'] as num?)?.toInt(),
        cancelledBy: j['cancelled_by'] as String?,
        completedAt: (j['completed_at'] as num?)?.toInt(),
      );
}

class DriverProfile {
  const DriverProfile({
    required this.status,
    required this.city,
    required this.totalTrips,
    required this.totalEarnings,
    required this.vehicles,
  });

  final String status;
  final String city;
  final int totalTrips;
  final int totalEarnings;
  final List<Vehicle> vehicles;

  bool get isApproved => status == 'approved';
  Vehicle? get activeVehicle => vehicles.where((v) => v.isActive).firstOrNull;

  factory DriverProfile.fromJson(Json j) => DriverProfile(
        status: j['status'] as String,
        city: j['city'] as String,
        totalTrips: _int(j['total_trips']),
        totalEarnings: _int(j['total_earnings']),
        vehicles: [for (final v in j['vehicles'] as List) Vehicle.fromJson(v as Json)],
      );
}

class RideOffer {
  const RideOffer({
    required this.rideId,
    required this.expiresAt,
    required this.pickupDistanceM,
    required this.vehicleClass,
    required this.pickup,
    required this.dropoff,
    required this.distanceM,
    required this.durationS,
    required this.total,
    required this.driverEarnings,
    required this.currency,
    this.riderName,
    this.riderRating,
  });

  final String rideId;
  final int expiresAt;
  final int pickupDistanceM;
  final VehicleClass vehicleClass;
  final Place pickup;
  final Place dropoff;
  final int distanceM;
  final int durationS;
  final int total;
  final int driverEarnings;
  final String currency;
  final String? riderName;
  final double? riderRating;

  factory RideOffer.fromJson(Json j) {
    final rider = j['rider'] as Json? ?? const {};
    return RideOffer(
      rideId: j['ride_id'] as String,
      expiresAt: _int(j['expires_at']),
      pickupDistanceM: _int(j['pickup_distance_m']),
      vehicleClass: VehicleClass.parse(j['vehicle_class'] as String),
      pickup: Place.fromJson(j['pickup'] as Json),
      dropoff: Place.fromJson(j['dropoff'] as Json),
      distanceM: _int(j['distance_m']),
      durationS: _int(j['duration_s']),
      total: _int(j['total']),
      driverEarnings: _int(j['driver_earnings']),
      currency: j['currency'] as String? ?? 'BDT',
      riderName: rider['name'] as String?,
      riderRating: (rider['rating'] as num?)?.toDouble(),
    );
  }
}

class EarningsPeriod {
  const EarningsPeriod({required this.trips, required this.gross, required this.net});
  final int trips;
  final int gross;
  final int net;

  factory EarningsPeriod.fromJson(Json j) =>
      EarningsPeriod(trips: _int(j['trips']), gross: _int(j['gross']), net: _int(j['net']));
}

class DailyEarnings {
  const DailyEarnings({required this.date, required this.trips, required this.net});
  final String date;
  final int trips;
  final int net;

  factory DailyEarnings.fromJson(Json j) =>
      DailyEarnings(date: j['date'] as String, trips: _int(j['trips']), net: _int(j['net']));
}

class Earnings {
  const Earnings({
    required this.currency,
    required this.today,
    required this.week,
    required this.month,
    required this.daily,
    required this.lifetimeTrips,
    required this.lifetimeNet,
  });

  final String currency;
  final EarningsPeriod today;
  final EarningsPeriod week;
  final EarningsPeriod month;
  final List<DailyEarnings> daily;
  final int lifetimeTrips;
  final int lifetimeNet;

  factory Earnings.fromJson(Json j) => Earnings(
        currency: j['currency'] as String? ?? 'BDT',
        today: EarningsPeriod.fromJson(j['today'] as Json),
        week: EarningsPeriod.fromJson(j['week'] as Json),
        month: EarningsPeriod.fromJson(j['month'] as Json),
        daily: [for (final d in j['daily'] as List) DailyEarnings.fromJson(d as Json)],
        lifetimeTrips: _int((j['lifetime'] as Json)['trips']),
        lifetimeNet: _int((j['lifetime'] as Json)['net']),
      );
}

class NearbyDriver {
  const NearbyDriver({required this.lat, required this.lng, required this.vehicleClass, this.heading});
  final double lat;
  final double lng;
  final double? heading;
  final VehicleClass vehicleClass;

  factory NearbyDriver.fromJson(Json j) => NearbyDriver(
        lat: _double(j['lat']),
        lng: _double(j['lng']),
        heading: (j['heading'] as num?)?.toDouble(),
        vehicleClass: VehicleClass.parse(j['vehicle_class'] as String),
      );
}

class GeoResult {
  const GeoResult({required this.name, required this.address, required this.lat, required this.lng});
  final String name;
  final String address;
  final double lat;
  final double lng;

  Place toPlace() => Place(lat: lat, lng: lng, address: address.isEmpty ? name : address, label: name);

  factory GeoResult.fromJson(Json j) => GeoResult(
        name: j['name'] as String? ?? '',
        address: j['address'] as String? ?? '',
        lat: _double(j['lat']),
        lng: _double(j['lng']),
      );
}

class ChatMessage {
  const ChatMessage({required this.id, required this.from, required this.text, required this.at});
  final String id;
  final String from;
  final String text;
  final int at;

  factory ChatMessage.fromJson(Json j) =>
      ChatMessage(id: j['id'] as String, from: j['from'] as String, text: j['text'] as String, at: _int(j['at']));
}

class DriverLocation {
  const DriverLocation({required this.lat, required this.lng, this.heading});
  final double lat;
  final double lng;
  final double? heading;

  factory DriverLocation.fromJson(Json j) =>
      DriverLocation(lat: _double(j['lat']), lng: _double(j['lng']), heading: (j['heading'] as num?)?.toDouble());
}
