import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/location.dart';
import '../../providers.dart';
import '../../widgets/cholo_map.dart';
import '../../widgets/feedback.dart';
import '../ride/ride_controller.dart';
import 'driver_controller.dart';
import 'driver_onboarding.dart';
import 'offer_card.dart';

final todayEarningsProvider = FutureProvider.autoDispose((ref) => ref.read(apiProvider).earnings());

class DriverHomeScreen extends ConsumerWidget {
  const DriverHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(driverProvider);
    ref.listen(driverProvider, (prev, next) {
      final error = next.value?.error;
      if (error != null && error != prev?.value?.error) showError(context, error);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver mode'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.read(driverProvider.notifier).reload()),
        data: (state) {
          final profile = state.profile;
          if (profile == null) return const DriverOnboarding();
          if (!profile.isApproved) {
            return _StatusMessage(
              icon: profile.status == 'pending' ? Icons.hourglass_top : Icons.block,
              title: profile.status == 'pending' ? 'Application under review' : 'Account suspended',
              body: profile.status == 'pending'
                  ? "We're checking your documents. You can go online as soon as you're approved."
                  : 'Contact Cholo support to reactivate your account.',
              onRefresh: () => ref.read(driverProvider.notifier).reload(),
            );
          }
          return _OnlineView(state: state);
        },
      ),
    );
  }
}

class _OnlineView extends ConsumerWidget {
  const _OnlineView({required this.state});
  final DriverState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final here = ref.watch(currentLocationProvider).value ?? defaultCenter;
    final earnings = ref.watch(todayEarningsProvider).value;
    final activeRide = ref.watch(rideProvider).value?.ride;
    final controller = ref.read(driverProvider.notifier);
    final vehicle = state.profile!.activeVehicle;
    final theme = Theme.of(context);

    return Stack(children: [
      CholoMap(key: ValueKey(here), center: here, pins: [MapPin(here, PinKind.me)]),
      Align(
        alignment: Alignment.topCenter,
        child: Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Today', style: theme.textTheme.bodySmall),
                  Text(
                    earnings == null ? '—' : formatMoney(earnings.today.net, currency: earnings.currency),
                    key: const Key('today-earnings'),
                    style: theme.textTheme.titleLarge,
                  ),
                  Text('${earnings?.today.trips ?? 0} trips', style: theme.textTheme.bodySmall),
                ]),
              ),
              TextButton(onPressed: () => context.push('/driver/earnings'), child: const Text('Earnings')),
              TextButton(onPressed: () => context.push('/driver/trips'), child: const Text('Trips')),
            ]),
          ),
        ),
      ),
      Align(
        alignment: Alignment.bottomCenter,
        child: state.offer != null
            ? OfferCard(
                offer: state.offer!,
                busy: state.busy,
                onDecline: controller.decline,
                onAccept: () async {
                  final ok = await controller.accept();
                  if (ok && context.mounted) context.go('/ride');
                },
              )
            : Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (activeRide != null && activeRide.status.isActive) ...[
                      FilledButton.tonalIcon(
                        onPressed: () => context.go('/ride'),
                        icon: const Icon(Icons.local_taxi),
                        label: const Text('Back to current trip'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      state.online ? "You're online" : "You're offline",
                      key: const Key('online-status'),
                      style: theme.textTheme.titleLarge,
                    ),
                    Text(state.online ? 'Waiting for ride requests nearby…' : 'Go online to start receiving rides.'),
                    if (vehicle != null) Text('${vehicle.description} · ${vehicle.plateNumber}', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('toggle-online'),
                      style: state.online ? FilledButton.styleFrom(backgroundColor: theme.colorScheme.error) : null,
                      onPressed: state.busy ? null : (state.online ? controller.goOffline : controller.goOnline),
                      child: state.busy ? const ButtonSpinner() : Text(state.online ? 'Go offline' : 'Go online'),
                    ),
                  ]),
                ),
              ),
      ),
    ]);
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.icon, required this.title, required this.body, required this.onRefresh});

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRefresh, child: const Text('Check again')),
          ]),
        ),
      );
}
