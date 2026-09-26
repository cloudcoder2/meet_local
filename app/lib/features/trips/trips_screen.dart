import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../widgets/cholo_map.dart';
import '../../widgets/feedback.dart';

/// Trip history, as a rider or (with [asDriver]) as a driver.
class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key, this.asDriver = false});

  final bool asDriver;

  @override
  ConsumerState<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends ConsumerState<TripsScreen> {
  final _rides = <Ride>[];
  int? _nextBefore;
  bool _loading = false;
  bool _done = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading || _done) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(apiProvider).rideHistory(asDriver: widget.asDriver, before: _nextBefore);
      setState(() {
        _rides.addAll(page.rides);
        _nextBefore = page.nextBefore;
        _done = page.nextBefore == null;
      });
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your trips')),
      body: _error != null && _rides.isEmpty
          ? ErrorRetry(error: _error!, onRetry: _load)
          : _rides.isEmpty && !_loading
              ? const Center(child: Text('No trips yet'))
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.extentAfter < 300) _load();
                    return false;
                  },
                  child: ListView.separated(
                    itemCount: _rides.length + (_loading ? 1 : 0),
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      if (i == _rides.length) {
                        return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                      }
                      final r = _rides[i];
                      return ListTile(
                        leading: Icon(vehicleIcon(r.vehicleClass)),
                        title: Text(r.dropoff.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${formatDateTime(r.requestedAt)} · ${r.status.label}'),
                        trailing: Text(
                          r.status == RideStatus.completed
                              ? formatMoney(widget.asDriver ? (r.payment?.driverNet ?? r.total) : r.total, currency: r.currency)
                              : '—',
                        ),
                        onTap: () => _showDetail(r),
                      );
                    },
                  ),
                ),
    );
  }

  void _showDetail(Ride r) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(formatDateTime(r.requestedAt), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.trip_origin, color: Colors.green), title: Text(r.pickup.address)),
            ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.flag), title: Text(r.dropoff.address)),
            Text('${formatDistance(r.distanceM)} · Cholo ${r.vehicleClass.label} · ${r.status.label}'),
            if ((widget.asDriver ? r.rider : r.driver)?.name != null) Text('${widget.asDriver ? 'Rider' : 'Driver'}: ${(widget.asDriver ? r.rider : r.driver)!.name}'),
            const Divider(height: 24),
            _line('Fare', formatMoney(r.fare, currency: r.currency)),
            if (r.discount > 0) _line('Promo', '−${formatMoney(r.discount, currency: r.currency)}'),
            _line('Total (cash)', formatMoney(r.total, currency: r.currency), bold: true),
            if (widget.asDriver && r.payment?.commission != null) ...[
              _line('Cholo commission', '−${formatMoney(r.payment!.commission!, currency: r.currency)}'),
              _line('Your earnings', formatMoney(r.payment!.driverNet!, currency: r.currency), bold: true),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _line(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text(label),
          const Spacer(),
          Text(value, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null),
        ]),
      );
}
