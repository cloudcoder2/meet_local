import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../widgets/cholo_map.dart';
import '../../widgets/feedback.dart';
import '../ride/ride_controller.dart';

typedef Trip = ({Place pickup, Place dropoff});

final _estimateProvider = FutureProvider.autoDispose.family<FareEstimate, (Trip, String?)>((ref, args) {
  final (trip, promo) = args;
  return ref.read(apiProvider).estimate(trip.pickup.point, trip.dropoff.point, promoCode: promo);
});

/// Shows fares for each vehicle class and requests the ride.
class BookScreen extends ConsumerStatefulWidget {
  const BookScreen({super.key, required this.trip});

  final Trip trip;

  @override
  ConsumerState<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends ConsumerState<BookScreen> {
  VehicleClass _selected = VehicleClass.bike;
  String? _promo;
  bool _requesting = false;

  Future<void> _enterPromo() async {
    final controller = TextEditingController(text: _promo);
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Promo code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'e.g. CHOLO50'),
        ),
        actions: [
          if (_promo != null) TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Remove')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Apply')),
        ],
      ),
    );
    controller.dispose();
    if (code != null) setState(() => _promo = code.isEmpty ? null : code.toUpperCase());
  }

  Future<void> _request() async {
    setState(() => _requesting = true);
    try {
      await ref.read(rideProvider.notifier).request(
            pickup: widget.trip.pickup,
            dropoff: widget.trip.dropoff,
            vehicleClass: _selected,
            promoCode: _promo,
          );
      if (mounted) context.go('/ride');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final estimate = ref.watch(_estimateProvider((trip, _promo)));
    final theme = Theme.of(context);

    // A rejected promo shouldn't block booking: show the error and drop it.
    ref.listen(_estimateProvider((trip, _promo)), (_, next) {
      if (next.hasError && _promo != null) {
        showError(context, next.error!);
        setState(() => _promo = null);
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Choose a ride')),
      body: Column(
        children: [
          Expanded(
            child: CholoMap(
              center: trip.pickup.point,
              pins: [MapPin(trip.pickup.point, PinKind.pickup), MapPin(trip.dropoff.point, PinKind.dropoff)],
              fitPoints: [trip.pickup.point, trip.dropoff.point],
              route: [trip.pickup.point, trip.dropoff.point],
              padding: const EdgeInsets.all(48),
            ),
          ),
          Material(
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TripSummary(trip: trip),
                    const Divider(height: 24),
                    estimate.when(
                      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                      error: (e, _) => _promo != null
                          ? const SizedBox(height: 80)
                          : ErrorRetry(error: e, onRetry: () => ref.invalidate(_estimateProvider((trip, _promo)))),
                      data: (est) => Column(children: [
                        for (final o in est.options)
                          _FareTile(
                            option: o,
                            currency: est.currency,
                            selected: o.vehicleClass == _selected,
                            onTap: () => setState(() => _selected = o.vehicleClass),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.payments_outlined, size: 20),
                      const SizedBox(width: 8),
                      Text('Cash', style: theme.textTheme.bodyMedium),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _enterPromo,
                        icon: const Icon(Icons.local_offer_outlined, size: 18),
                        label: Text(_promo ?? 'Promo code'),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    FilledButton(
                      key: const Key('request-ride'),
                      onPressed: _requesting || !estimate.hasValue ? null : _request,
                      child: _requesting ? const ButtonSpinner() : Text('Request Cholo ${_selected.label}'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripSummary extends StatelessWidget {
  const _TripSummary({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, Color? color, Place p) => Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(p.label ?? p.address, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]);
    return Column(children: [
      row(Icons.trip_origin, Colors.green, trip.pickup),
      const SizedBox(height: 6),
      row(Icons.flag, null, trip.dropoff),
    ]);
  }
}

class _FareTile extends StatelessWidget {
  const _FareTile({required this.option, required this.currency, required this.selected, required this.onTap});

  final FareOption option;
  final String currency;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: Key('fare-${option.vehicleClass.name}'),
      elevation: 0,
      color: selected ? theme.colorScheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? theme.colorScheme.primary : theme.dividerColor),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(vehicleIcon(option.vehicleClass), size: 32),
        title: Text(option.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${formatDuration(option.durationS)} · ${formatDistance(option.distanceM)} · ${option.seats} seat${option.seats > 1 ? 's' : ''}'
            '${option.surge > 1 ? ' · ${option.surge}× busy' : ''}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatMoney(option.total, currency: currency), style: theme.textTheme.titleMedium),
            if (option.discount > 0)
              Text(
                formatMoney(option.fare, currency: currency),
                style: theme.textTheme.bodySmall?.copyWith(decoration: TextDecoration.lineThrough),
              ),
          ],
        ),
      ),
    );
  }
}
