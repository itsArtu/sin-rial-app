part of 'main.dart';

DateTime caracasTime(DateTime instant) =>
    instant.toUtc().subtract(const Duration(hours: 4));

DateTime nextBcvBoundary(DateTime now) {
  final local = caracasTime(now);
  var boundary = DateTime.utc(local.year, local.month, local.day + 1);
  if (local.weekday == DateTime.friday && local.hour < 18) {
    boundary = DateTime.utc(local.year, local.month, local.day, 18);
  }
  return boundary.add(const Duration(hours: 4));
}

List<Map<String, dynamic>> bcvSnapshots(Iterable<dynamic> values) {
  final byDate = <String, Map<String, dynamic>>{};
  for (final value in values) {
    if (value is! Map) continue;
    final date = (value['effective_date'] ?? value['date'] ?? '').toString();
    final parsed = DateTime.tryParse(date);
    final usd = numberValue(value['USD']);
    final eur = numberValue(value['EUR']);
    if (parsed == null ||
        isoDate(parsed) != date ||
        !usd.isFinite ||
        usd <= 0 ||
        !eur.isFinite ||
        eur <= 0)
      continue;
    final stamp = value['updated_at']?.toString() ?? '';
    final previous = byDate[date];
    if (previous != null &&
        stamp.compareTo(previous['updated_at'] as String) < 0)
      continue;
    byDate[date] = {
      'USD': usd,
      'EUR': eur,
      'effective_date': date,
      'updated_at': stamp,
    };
  }
  final sorted = byDate.values.toList()
    ..sort(
      (a, b) => (a['effective_date'] as String).compareTo(
        b['effective_date'] as String,
      ),
    );
  return sorted.skip(math.max(0, sorted.length - 40)).toList();
}

List<Map<String, dynamic>> savedBcvSnapshots(Map<String, dynamic> state) =>
    bcvSnapshots([
      {
        'USD': state['rate'],
        'EUR': state['eurRate'],
        'effective_date': state['rateEffectiveDate'],
        'updated_at': state['rateUpdatedAt'],
      },
      ...?state['bcvRateSnapshots'] as List?,
    ]);

Map<String, dynamic>? nextBcvSnapshot(
  Iterable<dynamic> snapshots,
  DateTime now,
) {
  final today = isoDate(caracasTime(now));
  for (final quote in bcvSnapshots(snapshots)) {
    if ((quote['effective_date'] as String).compareTo(today) > 0) return quote;
  }
  return null;
}

Map<String, dynamic>? activeBcvSnapshot(
  Iterable<dynamic> snapshots,
  DateTime now,
) {
  final local = caracasTime(now);
  final today = isoDate(local);
  Map<String, dynamic>? current;
  final sorted = bcvSnapshots(snapshots);
  for (final quote in sorted) {
    if ((quote['effective_date'] as String).compareTo(today) <= 0)
      current = quote;
  }
  var friday = DateTime.utc(
    local.year,
    local.month,
    local.day,
    18,
  ).subtract(Duration(days: (local.weekday - DateTime.friday + 7) % 7));
  if (friday.isAfter(local)) friday = friday.subtract(const Duration(days: 7));
  final next = nextBcvSnapshot(sorted, now);
  // Preserve Friday's advance through weekends/holidays until its actual effective date.
  if (current != null &&
      next != null &&
      (current['effective_date'] as String).compareTo(isoDate(friday)) <= 0) {
    return next;
  }
  return current;
}

bool applyBcvSnapshot(Map<String, dynamic> state, DateTime now) {
  final quote = activeBcvSnapshot(savedBcvSnapshots(state), now);
  if (quote == null) return false;
  final changed =
      state['rate'] != quote['USD'] ||
      state['eurRate'] != quote['EUR'] ||
      state['rateEffectiveDate'] != quote['effective_date'];
  if (!changed) return false;
  for (final currency in ['USD', 'EUR']) {
    final key = currency == 'USD' ? 'rate' : 'eurRate';
    final old = numberValue(state[key]);
    if (old > 0 && old != quote[currency]) {
      state[currency == 'USD' ? 'previousRate' : 'previousEurRate'] = old;
    }
    state[key] = quote[currency];
    state['${key}EffectiveDate'] = quote['effective_date'];
    state['${key}UpdatedAt'] = quote['updated_at'];
  }
  state['lastRateDate'] = quote['effective_date'];
  state['rateLastAttemptMillis'] = now.millisecondsSinceEpoch;
  return true;
}
