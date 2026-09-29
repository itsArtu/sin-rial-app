part of 'main.dart';

Map<String, dynamic> normalizeBcvHistory(Iterable<dynamic> values) {
  final result = <String, dynamic>{};
  for (final raw in values.whereType<Map>()) {
    final date = (raw['date'] ?? raw['effective_date'] ?? '').toString();
    final effective = (raw['effective_date'] ?? date).toString();
    final parsed = DateTime.tryParse(date);
    final effectiveParsed = DateTime.tryParse(effective);
    final usd = numberValue(raw['USD']);
    final eur = numberValue(raw['EUR']);
    if (parsed == null ||
        isoDate(parsed) != date ||
        effectiveParsed == null ||
        isoDate(effectiveParsed) != effective ||
        !usd.isFinite ||
        usd <= 0) {
      continue;
    }
    final stamp = raw['updated_at']?.toString() ?? '';
    final previous = result[date] as Map?;
    if (previous != null &&
        stamp.compareTo(previous['updated_at'].toString()) < 0) {
      continue;
    }
    result[date] = {
      'USD': usd,
      'EUR': eur.isFinite && eur > 0 ? eur : 0.0,
      'effective_date': effective,
      'updated_at': stamp,
    };
  }
  return result;
}

// A movement's wall-clock date is in Caracas, including Friday's early quote.
Map<String, dynamic>? movementBcvQuote(
  Map<String, dynamic> state,
  DateTime date, {
  DateTime? now,
}) {
  final day = isoDate(date);
  final history = state['bcvRateHistory'] is Map
      ? state['bcvRateHistory'] as Map
      : const <String, dynamic>{};
  final snapshots = savedBcvSnapshots(state);
  final exact = history[day];
  Map<String, dynamic>? quote = exact is Map
      ? normalizeBcvHistory([
              {...exact, 'date': day},
            ])[day]
            as Map<String, dynamic>?
      : null;
  if (quote != null && quote['effective_date'].toString().compareTo(day) > 0) {
    quote = null;
  }
  if (quote == null &&
      snapshots.isNotEmpty &&
      day.compareTo(snapshots.last['effective_date'].toString()) <= 0) {
    for (final snapshot in snapshots) {
      if (snapshot['effective_date'].toString().compareTo(day) <= 0) {
        quote = snapshot;
      }
    }
  }
  final local = DateTime.utc(
    date.year,
    date.month,
    date.day,
    date.hour,
    date.minute,
  );
  final instant = local.add(const Duration(hours: 4));
  var friday = DateTime.utc(
    date.year,
    date.month,
    date.day,
    18,
  ).subtract(Duration(days: (date.weekday - DateTime.friday + 7) % 7));
  if (friday.isAfter(local)) friday = friday.subtract(const Duration(days: 7));
  if (quote != null &&
      quote['effective_date'].toString().compareTo(isoDate(friday)) <= 0) {
    Map<String, dynamic>? advance;
    for (final value in [...history.values, ...snapshots].whereType<Map>()) {
      final effective = value['effective_date']?.toString() ?? '';
      final published = DateTime.tryParse(
        value['updated_at']?.toString() ?? '',
      );
      if (effective.compareTo(day) <= 0 ||
          published == null ||
          published.isAfter(instant) ||
          !numberValue(value['USD']).isFinite ||
          numberValue(value['USD']) <= 0) {
        continue;
      }
      if (advance == null ||
          effective.compareTo(advance['effective_date'].toString()) < 0) {
        advance = Map<String, dynamic>.from(value);
      }
    }
    quote = advance ?? quote;
  }
  // Undated current quotes remain usable today, never for a backdated entry.
  if (quote == null && day == isoDate(caracasTime(now ?? DateTime.now()))) {
    final usd = numberValue(state['rate']);
    if (usd.isFinite && usd > 0) {
      quote = {
        'USD': usd,
        'EUR': numberValue(state['eurRate']),
        'effective_date': state['rateEffectiveDate'] ?? day,
      };
    }
  }
  return quote;
}

Map<String, dynamic>? recordedBcvQuote(Map<String, dynamic>? movement) {
  if (movement == null) return null;
  final usd = numberValue(movement['bcvUsdRate']);
  if (!usd.isFinite || usd <= 0) return null;
  return {
    'USD': usd,
    'EUR': numberValue(movement['bcvEurRate']),
    'effective_date': movement['bcvEffectiveDate'] ?? '',
  };
}

Map<String, dynamic> movementBcvFields(Map<String, dynamic>? quote) =>
    quote == null
    ? <String, dynamic>{}
    : {
        'bcvUsdRate': quote['USD'],
        'bcvEurRate': quote['EUR'],
        'bcvEffectiveDate': quote['effective_date'],
      };

double movementBudgetUsd(
  Map<String, dynamic> movement,
  double amount,
  double usdRate,
  double eurRate,
) {
  final quote = recordedBcvQuote(movement);
  return budgetUsd(
    amount,
    movement['currency']?.toString() ?? 'USD',
    quote == null ? usdRate : numberValue(quote['USD']),
    quote == null ? eurRate : numberValue(quote['EUR']),
  );
}

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
