import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../data/models.dart';

/// Whether to load map tiles; tests turn this off to avoid network access.
final mapTilesEnabledProvider = Provider<bool>((ref) => true);

enum PinKind { pickup, dropoff, driver, nearby, me }

class MapPin {
  const MapPin(this.point, this.kind, {this.heading, this.vehicleClass});
  final LatLngPoint point;
  final PinKind kind;
  final double? heading;
  final VehicleClass? vehicleClass;
}

LatLng toLatLng(LatLngPoint p) => LatLng(p.lat, p.lng);

/// OpenStreetMap view with Cholo's markers. When [fitPoints] has two or more
/// points the camera keeps them all in view; otherwise it centres on [center].
class CholoMap extends ConsumerStatefulWidget {
  const CholoMap({
    super.key,
    required this.center,
    this.pins = const [],
    this.fitPoints = const [],
    this.route = const [],
    this.zoom = 15,
    this.onCameraIdle,
    this.padding = const EdgeInsets.fromLTRB(48, 96, 48, 320),
    this.controller,
  });

  final LatLngPoint center;
  final List<MapPin> pins;
  final List<LatLngPoint> fitPoints;
  final List<LatLngPoint> route;
  final double zoom;
  final EdgeInsets padding;
  final MapController? controller;

  /// Called with the map centre when the user stops moving the map.
  final ValueChanged<LatLngPoint>? onCameraIdle;

  @override
  ConsumerState<CholoMap> createState() => _CholoMapState();
}

class _CholoMapState extends ConsumerState<CholoMap> {
  late final MapController _controller = widget.controller ?? MapController();
  bool _ready = false;

  @override
  void didUpdateWidget(CholoMap old) {
    super.didUpdateWidget(old);
    if (_ready && !_sameFit(old.fitPoints, widget.fitPoints)) _fit();
  }

  bool _sameFit(List<LatLngPoint> a, List<LatLngPoint> b) =>
      a.length == b.length && [for (var i = 0; i < a.length; i++) a[i].lat == b[i].lat && a[i].lng == b[i].lng].every((x) => x);

  void _fit() {
    if (widget.fitPoints.length < 2) return;
    _controller.fitCamera(CameraFit.coordinates(
      coordinates: widget.fitPoints.map(toLatLng).toList(),
      padding: widget.padding,
      maxZoom: 17,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tiles = ref.watch(mapTilesEnabledProvider);
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: toLatLng(widget.center),
        initialZoom: widget.zoom,
        onMapReady: () {
          _ready = true;
          _fit();
        },
        onMapEvent: (event) {
          if (widget.onCameraIdle != null && (event is MapEventMoveEnd || event is MapEventFlingAnimationEnd)) {
            final c = event.camera.center;
            widget.onCameraIdle!(LatLngPoint(c.latitude, c.longitude));
          }
        },
      ),
      children: [
        if (tiles) TileLayer(urlTemplate: AppConfig.tileUrl, userAgentPackageName: AppConfig.userAgentPackage),
        if (widget.route.length >= 2)
          PolylineLayer(polylines: [
            Polyline(points: widget.route.map(toLatLng).toList(), strokeWidth: 5, color: CholoColors.green),
          ]),
        MarkerLayer(markers: [for (final pin in widget.pins) _marker(pin)]),
        // Top-right keeps the required OSM credit clear of the bottom sheets.
        if (tiles)
          const SafeArea(
            child: SimpleAttributionWidget(source: Text('OpenStreetMap contributors'), alignment: Alignment.topRight),
          ),
      ],
    );
  }

  Marker _marker(MapPin pin) {
    final child = switch (pin.kind) {
      PinKind.pickup => const _Dot(color: CholoColors.green, icon: Icons.person_pin_circle),
      PinKind.dropoff => const _Dot(color: CholoColors.ink, icon: Icons.flag),
      PinKind.me => const _Dot(color: Colors.blue, icon: Icons.my_location, size: 28),
      PinKind.driver || PinKind.nearby => Transform.rotate(
          angle: (pin.heading ?? 0) * 3.14159 / 180,
          child: _Dot(
            color: pin.kind == PinKind.driver ? CholoColors.sun : Colors.white,
            icon: vehicleIcon(pin.vehicleClass ?? VehicleClass.car),
            iconColor: CholoColors.ink,
            size: pin.kind == PinKind.driver ? 40 : 30,
          ),
        ),
    };
    return Marker(point: toLatLng(pin.point), width: 44, height: 44, child: child);
  }
}

IconData vehicleIcon(VehicleClass c) => switch (c) {
      VehicleClass.bike => Icons.two_wheeler,
      VehicleClass.cng => Icons.electric_rickshaw,
      VehicleClass.car => Icons.directions_car,
    };

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.icon, this.iconColor = Colors.white, this.size = 36});

  final Color color;
  final IconData icon;
  final Color iconColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
        ),
        child: Icon(icon, color: iconColor, size: size * 0.55),
      ),
    );
  }
}
