import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../widgets/feedback.dart';
import '../ride/chat_sheet.dart';
import '../ride/ride_controller.dart';
import '../ride/ride_screen.dart';

/// Trip controls for the driver: navigate to pickup, arrive, start with the
/// rider's code, complete, then collect cash and rate the rider.
class DriverTripPanel extends ConsumerStatefulWidget {
  const DriverTripPanel({super.key, required this.ride});
  final Ride ride;

  @override
  ConsumerState<DriverTripPanel> createState() => _DriverTripPanelState();
}

class _DriverTripPanelState extends ConsumerState<DriverTripPanel> {
  final _otp = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(RideController c) action) async {
    setState(() => _busy = true);
    try {
      await action(ref.read(rideProvider.notifier));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _navigate(Place to) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${to.lat},${to.lng}&travelmode=driving');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      showMessage(context, 'Could not open maps');
    }
  }

  Future<void> _call(String phone) async {
    if (!await launchUrl(Uri(scheme: 'tel', path: phone))) {
      await Clipboard.setData(ClipboardData(text: phone));
      if (mounted) showMessage(context, 'Phone number copied');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final theme = Theme.of(context);
    final rider = ride.rider;
    final stop = ride.status == RideStatus.inProgress ? ride.dropoff : ride.pickup;

    Widget riderRow() => Row(children: [
          CircleAvatar(child: Text((rider?.name ?? '?').characters.first.toUpperCase())),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rider?.name ?? 'Rider', style: theme.textTheme.titleMedium),
              if (rider?.rating != null) Text('★ ${rider!.rating!.toStringAsFixed(1)}', style: theme.textTheme.bodySmall),
            ]),
          ),
          if (rider?.phone != null) IconButton(onPressed: () => _call(rider!.phone!), icon: const Icon(Icons.phone)),
          IconButton(onPressed: () => showChatSheet(context), icon: const Icon(Icons.chat_bubble_outline)),
        ]);

    Widget stopRow(String label) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(ride.status == RideStatus.inProgress ? Icons.flag : Icons.trip_origin,
              color: ride.status == RideStatus.inProgress ? null : Colors.green),
          title: Text(label, style: theme.textTheme.bodySmall),
          subtitle: Text(stop.address, style: theme.textTheme.bodyLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: IconButton.filledTonal(onPressed: () => _navigate(stop), icon: const Icon(Icons.navigation)),
        );

    final children = <Widget>[
      Text(switch (ride.status) {
        RideStatus.accepted => 'Pick up ${rider?.name ?? 'rider'}',
        RideStatus.arrived => 'Waiting for ${rider?.name ?? 'rider'}',
        RideStatus.inProgress => 'Drop off ${rider?.name ?? 'rider'}',
        RideStatus.completed => 'Trip complete',
        RideStatus.cancelled => 'Ride cancelled',
        _ => ride.status.label,
      }, key: const Key('driver-trip-title'), style: theme.textTheme.titleLarge),
      const SizedBox(height: 8),
    ];

    switch (ride.status) {
      case RideStatus.accepted:
        children.addAll([
          riderRow(),
          stopRow('Pickup'),
          FilledButton(
            key: const Key('arrived'),
            onPressed: _busy ? null : () => _run((c) => c.markArrived()),
            child: const Text("I've arrived"),
          ),
          TextButton(onPressed: _busy ? null : () => _run((c) => c.cancel(reason: 'Driver cancelled')), child: const Text('Cancel ride')),
        ]);
      case RideStatus.arrived:
        children.addAll([
          riderRow(),
          const SizedBox(height: 8),
          TextField(
            key: const Key('otp-input'),
            controller: _otp,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: "Rider's 4-digit code", counterText: ''),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('start-trip'),
            onPressed: _busy ? null : () => _otp.text.length == 4 ? _run((c) => c.start(_otp.text)) : null,
            child: const Text('Start trip'),
          ),
          TextButton(onPressed: _busy ? null : () => _run((c) => c.cancel(reason: 'Rider no-show')), child: const Text('Rider not here')),
        ]);
      case RideStatus.inProgress:
        children.addAll([
          riderRow(),
          stopRow('Drop-off'),
          Text('Collect ${formatMoney(ride.total, currency: ride.currency)} in cash', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('complete-trip'),
            onPressed: _busy ? null : () => _run((c) => c.complete()),
            child: const Text('Complete trip'),
          ),
        ]);
      case RideStatus.completed:
        children.add(RideReceipt(ride: ride));
      default:
        children.addAll([
          Text(ride.cancelledBy == 'rider' ? 'The rider cancelled this ride.' : 'This ride was cancelled.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              ref.read(rideProvider.notifier).dismiss();
              context.go('/driver');
            },
            child: const Text('Back to driver mode'),
          ),
        ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}
