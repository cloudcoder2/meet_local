import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../widgets/cholo_map.dart';

/// Incoming ride offer with a countdown until it moves to another driver.
class OfferCard extends StatefulWidget {
  const OfferCard({super.key, required this.offer, required this.onAccept, required this.onDecline, this.busy = false});

  final RideOffer offer;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final bool busy;

  @override
  State<OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<OfferCard> {
  Timer? _tick;
  late int _total = _remainingMs().clamp(1, 1 << 30);

  int _remainingMs() => widget.offer.expiresAt - DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));
  }

  @override
  void didUpdateWidget(OfferCard old) {
    super.didUpdateWidget(old);
    if (old.offer.rideId != widget.offer.rideId) _total = _remainingMs().clamp(1, 1 << 30);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    final theme = Theme.of(context);
    final left = _remainingMs().clamp(0, _total);
    return Card(
      key: const Key('offer-card'),
      margin: const EdgeInsets.all(12),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LinearProgressIndicator(value: left / _total),
          const SizedBox(height: 12),
          Row(children: [
            Icon(vehicleIcon(o.vehicleClass)),
            const SizedBox(width: 8),
            Expanded(child: Text('New ride request', style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
            Text(formatMoney(o.driverEarnings, currency: o.currency),
                key: const Key('offer-earnings'), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          Text('${o.riderName ?? 'Rider'}${o.riderRating != null ? ' · ★ ${o.riderRating!.toStringAsFixed(1)}' : ''}'
              ' · ${formatDistance(o.pickupDistanceM)} away'),
          const Divider(height: 20),
          _Stop(icon: Icons.trip_origin, color: Colors.green, text: o.pickup.address),
          const SizedBox(height: 6),
          _Stop(icon: Icons.flag, text: o.dropoff.address),
          const SizedBox(height: 6),
          Text('${formatDistance(o.distanceM)} trip · ~${formatDuration(o.durationS)} · rider pays ${formatMoney(o.total, currency: o.currency)} cash',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: widget.busy ? null : widget.onDecline, child: const Text('Decline'))),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                key: const Key('accept-offer'),
                onPressed: widget.busy ? null : widget.onAccept,
                child: Text('Accept (${(left / 1000).ceil()}s)'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Stop extends StatelessWidget {
  const _Stop({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis)),
      ]);
}
