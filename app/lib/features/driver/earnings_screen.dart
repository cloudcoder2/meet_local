import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../widgets/feedback.dart';

final earningsProvider = FutureProvider.autoDispose<Earnings>((ref) => ref.read(apiProvider).earnings());

class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(earningsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(earningsProvider)),
        data: (e) => RefreshIndicator(
          onRefresh: () => ref.refresh(earningsProvider.future),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(child: _PeriodCard(label: 'Today', period: e.today, currency: e.currency)),
              const SizedBox(width: 8),
              Expanded(child: _PeriodCard(label: '7 days', period: e.week, currency: e.currency)),
              const SizedBox(width: 8),
              Expanded(child: _PeriodCard(label: '30 days', period: e.month, currency: e.currency)),
            ]),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Last 7 days', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  SizedBox(height: 160, child: _DailyBars(days: e.daily, currency: e.currency)),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                title: const Text('Lifetime'),
                subtitle: Text('${e.lifetimeTrips} trips'),
                trailing: Text(formatMoney(e.lifetimeNet, currency: e.currency), style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Earnings are after Cholo commission. Cash fares are collected by you at drop-off.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),
        ),
      ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.label, required this.period, required this.currency});
  final String label;
  final EarningsPeriod period;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: theme.textTheme.bodySmall),
          FittedBox(child: Text(formatMoney(period.net, currency: currency), style: theme.textTheme.titleLarge)),
          Text('${period.trips} trips', style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.days, required this.currency});
  final List<DailyEarnings> days;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = days.fold<int>(0, (m, d) => d.net > m ? d.net : m);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final d in days)
          Expanded(
            child: Tooltip(
              message: '${formatMoney(d.net, currency: currency)} · ${d.trips} trips',
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: max == 0 ? 0.02 : (d.net / max).clamp(0.02, 1.0),
                      widthFactor: 0.6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(DateFormat('E').format(DateTime.parse(d.date)), style: theme.textTheme.labelSmall),
              ]),
            ),
          ),
      ],
    );
  }
}
