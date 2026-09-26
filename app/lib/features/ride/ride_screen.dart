import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../widgets/cholo_map.dart';
import '../../widgets/feedback.dart';
import '../driver/driver_trip_panel.dart';
import 'chat_sheet.dart';
import 'ride_controller.dart';

/// Live view of the current ride for the rider: searching, driver en route,
/// on trip, then receipt and rating.
class RideScreen extends ConsumerWidget {
  const RideScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rideProvider);
    final session = async.value;
    if (session == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(child: TextButton(onPressed: () => context.go('/'), child: const Text('No active ride. Go home'))),
      );
    }
    final ride = session.ride;
    final driverAt = session.driverLocation == null ? null : LatLngPoint(session.driverLocation!.lat, session.driverLocation!.lng);
    final fit = switch (ride.status) {
      RideStatus.accepted || RideStatus.arrived when driverAt != null => [driverAt, ride.pickup.point],
      RideStatus.inProgress when driverAt != null => [driverAt, ride.dropoff.point],
      _ => [ride.pickup.point, ride.dropoff.point],
    };

    return Scaffold(
      body: Stack(children: [
        CholoMap(
          center: ride.pickup.point,
          pins: [
            MapPin(ride.pickup.point, PinKind.pickup),
            MapPin(ride.dropoff.point, PinKind.dropoff),
            if (driverAt != null)
              MapPin(driverAt, PinKind.driver, heading: session.driverLocation!.heading, vehicleClass: ride.vehicleClass),
          ],
          fitPoints: fit,
          route: ride.status == RideStatus.inProgress && driverAt != null ? [driverAt, ride.dropoff.point] : const [],
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: ride.isDriverView ? DriverTripPanel(ride: ride) : _RiderPanel(ride: ride),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _RiderPanel extends ConsumerWidget {
  const _RiderPanel({required this.ride});
  final Ride ride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(rideProvider.notifier);
    final children = <Widget>[
      Text(ride.status.label, key: const Key('ride-status'), style: theme.textTheme.titleLarge),
      const SizedBox(height: 8),
    ];

    switch (ride.status) {
      case RideStatus.requested:
        children.addAll([
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Text('Matching you with a nearby Cholo ${ride.vehicleClass.label}…'),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: () => _confirmCancel(context, ref), child: const Text('Cancel request')),
        ]);
      case RideStatus.accepted || RideStatus.arrived:
        children.addAll([
          if (ride.driver != null) DriverCard(driver: ride.driver!, vehicle: ride.vehicle),
          const SizedBox(height: 12),
          if (ride.otp != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.pin_outlined),
                const SizedBox(width: 8),
                const Expanded(child: Text('Tell your driver this code to start the trip')),
                Text(ride.otp!, key: const Key('ride-otp'), style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 4)),
              ]),
            ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => showChatSheet(context), icon: const Icon(Icons.chat_bubble_outline), label: const Text('Chat'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () => _confirmCancel(context, ref), child: const Text('Cancel'))),
          ]),
        ]);
      case RideStatus.inProgress:
        children.addAll([
          Text('Heading to ${ride.dropoff.label ?? ride.dropoff.address}'),
          const SizedBox(height: 4),
          Text('${formatMoney(ride.total, currency: ride.currency)} · pay in cash', style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          if (ride.driver != null) DriverCard(driver: ride.driver!, vehicle: ride.vehicle),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: () => showChatSheet(context), icon: const Icon(Icons.chat_bubble_outline), label: const Text('Chat')),
        ]);
      case RideStatus.completed:
        children.add(RideReceipt(ride: ride));
      case RideStatus.cancelled || RideStatus.noDriver:
        children.addAll([
          Text(ride.status == RideStatus.noDriver
              ? "We couldn't find a driver nearby. Please try again in a few minutes."
              : ride.cancelledBy == 'driver'
                  ? 'Your driver cancelled. You were not charged.'
                  : 'You cancelled this ride.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              controller.dismiss();
              context.go('/');
            },
            child: const Text('Back to home'),
          ),
        ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    const reasons = ['Driver is taking too long', 'Changed my plans', 'Booked by mistake', 'Other'];
    final reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(8), child: Text('Why are you cancelling?')),
          for (final r in reasons) ListTile(title: Text(r), onTap: () => Navigator.pop(context, r)),
        ]),
      ),
    );
    if (reason == null) return;
    try {
      await ref.read(rideProvider.notifier).cancel(reason: reason);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

class DriverCard extends StatelessWidget {
  const DriverCard({super.key, required this.driver, this.vehicle});

  final Person driver;
  final Vehicle? vehicle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        CircleAvatar(radius: 26, child: Text((driver.name ?? '?').characters.first.toUpperCase())),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(driver.name ?? 'Your driver', style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (driver.rating != null)
              Text.rich(TextSpan(children: [
                const WidgetSpan(child: Icon(Icons.star_rounded, size: 16, color: Colors.amber)),
                TextSpan(text: ' ${driver.rating!.toStringAsFixed(1)}'),
              ])),
            if (vehicle != null)
              Text(vehicle!.description, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        if (vehicle != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(border: Border.all(color: theme.dividerColor), borderRadius: BorderRadius.circular(6)),
            child: Text(vehicle!.plateNumber, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
      ]),
      if (driver.phone != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: driver.phone!));
              showMessage(context, 'Phone number copied');
            },
            icon: const Icon(Icons.phone, size: 16),
            label: Text(driver.phone!),
          ),
        ),
    ]);
  }
}

class RideReceipt extends ConsumerStatefulWidget {
  const RideReceipt({super.key, required this.ride});
  final Ride ride;

  @override
  ConsumerState<RideReceipt> createState() => _RideReceiptState();
}

class _RideReceiptState extends ConsumerState<RideReceipt> {
  int _stars = 0;
  final _comment = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _sending = true);
    try {
      await ref.read(rideProvider.notifier).rate(_stars, comment: _comment.text.trim().isEmpty ? null : _comment.text.trim());
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final theme = Theme.of(context);
    final rated = ride.myRating != null;
    final other = ride.isDriverView ? 'rider' : 'driver';
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(formatMoney(ride.total, currency: ride.currency), key: const Key('receipt-total'), style: theme.textTheme.displaySmall),
      Text(ride.isDriverView ? 'Collect in cash' : 'Paid in cash', style: theme.textTheme.bodyMedium),
      if (ride.discount > 0) Text('Includes ${formatMoney(ride.discount, currency: ride.currency)} promo discount'),
      const Divider(height: 24),
      if (rated)
        Text('Thanks! You rated your $other ${ride.myRating} ★')
      else ...[
        Text('How was your $other?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                key: Key('star-$i'),
                iconSize: 36,
                onPressed: () => setState(() => _stars = i),
                icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded, color: Colors.amber),
              ),
          ],
        ),
        TextField(controller: _comment, decoration: const InputDecoration(hintText: 'Add a comment (optional)')),
        const SizedBox(height: 12),
        FilledButton(onPressed: _stars == 0 || _sending ? null : _submit, child: const Text('Submit rating')),
      ],
      const SizedBox(height: 8),
      TextButton(
        onPressed: () {
          ref.read(rideProvider.notifier).dismiss();
          context.go(ride.isDriverView ? '/driver' : '/');
        },
        child: const Text('Done'),
      ),
    ]);
  }
}
