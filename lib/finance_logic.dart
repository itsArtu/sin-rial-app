part of 'main.dart';

const rateStateKeys = {
  'rate',
  'previousRate',
  'lastRateDate',
  'rateEffectiveDate',
  'rateUpdatedAt',
  'lastRateMillis',
  'eurRate',
  'previousEurRate',
  'eurRateEffectiveDate',
  'eurRateUpdatedAt',
  'eurLastRateMillis',
  'usdtRate',
  'previousUsdtRate',
  'usdtRateUpdatedAt',
  'usdtLastRateMillis',
  'rateLastAttemptMillis',
  'rateFetchStatus',
  'eurRateFetchStatus',
  'usdtRateFetchStatus',
};

Decimal _decimal(num value) {
  if (!value.isFinite) throw const FormatException('Monto no valido');
  return Decimal.parse(value.toString());
}

int moneyCents(num value) =>
    (_decimal(value).round(scale: 2) * Decimal.fromInt(100)).toBigInt().toInt();

double moneyRound(num value) => moneyCents(value) / 100;
double moneyAdd(num a, num b) => (moneyCents(a) + moneyCents(b)) / 100;
double moneySubtract(num a, num b) => (moneyCents(a) - moneyCents(b)) / 100;

double moneyConvert(num amount, num multiplier, [num divisor = 1]) {
  if (!divisor.isFinite || divisor <= 0) {
    throw const FormatException('Tasa no valida');
  }
  return ((_decimal(amount) * _decimal(multiplier)) / _decimal(divisor))
      .toDecimal(scaleOnInfinitePrecision: 12)
      .round(scale: 2)
      .toDouble();
}

List<double> splitInstallments(double amount, int count) {
  if (count < 1 || count > 999) throw ArgumentError.value(count);
  final cents = moneyCents(amount);
  final base = cents ~/ count;
  return List.generate(
    count,
    (index) => (index == count - 1 ? cents - base * (count - 1) : base) / 100,
  );
}

double debtInitialAmount(Map<String, dynamic> debt) {
  final initial = numberValue(debt['initialAmount']);
  return math.min(
    numberValue(debt['amount']),
    initial > 0 || debt['initialPaid'] != true
        ? initial
        : numberValue(debt['paidAmount']),
  );
}

List<double> debtInstallmentAmounts(Map<String, dynamic> debt) {
  final principal = math.max(
    0.0,
    moneySubtract(numberValue(debt['amount']), debtInitialAmount(debt)),
  );
  final count = debtInstallmentCount(debt);
  if (debt['installmentMode'] == 'auto' ||
      numberValue(debt['installmentAmount']) <= 0) {
    return splitInstallments(principal, count);
  }
  var remaining = moneyCents(principal);
  final manual = moneyCents(numberValue(debt['installmentAmount']));
  return List.generate(count, (i) {
    final cents = i == count - 1 ? remaining : math.min(manual, remaining);
    remaining -= cents;
    return cents / 100;
  });
}

class BalancePoint {
  const BalancePoint(this.date, this.amount);
  final DateTime date;
  final double amount;
}

DateTime balancePeriodStart(DateTime now, String period) => switch (period) {
  'week' => DateTime(now.year, now.month, now.day - 6),
  'month' => DateTime(now.year, now.month, 1),
  _ => DateTime(now.year, now.month, now.day),
};

// Reconstruct current accounts at a single valuation rate, not historic FX prices.
List<BalancePoint> buildBalanceTrend({
  required List<Map<String, dynamic>> accounts,
  required List<Map<String, dynamic>> movements,
  List<Map<String, dynamic>> adjustments = const [],
  required double Function(double, String) convertValue,
  required String period,
  required DateTime now,
}) {
  final start = balancePeriodStart(now, period);
  final byId = {for (final a in accounts) a['id']?.toString() ?? '': a};
  var current = 0.0;
  for (final a in accounts) {
    current += convertValue(
      numberValue(a['balance']),
      a['currency']?.toString() ?? 'USD',
    );
  }
  final events = <BalancePoint>[];
  void add(DateTime date, double delta) {
    if (date.millisecondsSinceEpoch == 0) return;
    final effective = date.isAfter(now) ? now : date;
    if (!effective.isBefore(start)) events.add(BalancePoint(effective, delta));
  }

  final accountNet = <String, double>{};
  void accountEvent(String id, double delta, DateTime date) {
    final account = byId[id];
    if (account == null) return;
    accountNet[id] = moneyAdd(accountNet[id] ?? 0, delta);
    add(date, convertValue(delta, account['currency']?.toString() ?? 'USD'));
  }

  for (final m in movements) {
    final date = parseMovementDate(m['date']?.toString());
    final amount = numberValue(m['amount']);
    final fee = numberValue(m['feeAmount']);
    final income = m['type'] == 'income';
    accountEvent(
      m['accountId']?.toString() ?? '',
      income ? moneySubtract(amount, fee) : -moneyAdd(amount, fee),
      date,
    );
    if (m['type'] == 'transfer') {
      accountEvent(
        m['targetAccountId']?.toString() ?? '',
        numberValue(m['targetAmount']),
        date,
      );
    }
  }
  for (final a in adjustments) {
    accountEvent(
      a['accountId']?.toString() ?? '',
      numberValue(a['amount']),
      parseMovementDate(a['date']?.toString()),
    );
  }
  for (final a in accounts) {
    final created = DateTime.tryParse(a['createdAt']?.toString() ?? '');
    if (created == null) continue;
    final opening = moneySubtract(
      numberValue(a['balance']),
      accountNet[a['id']] ?? 0,
    );
    add(created, convertValue(opening, a['currency']?.toString() ?? 'USD'));
  }
  events.sort((a, b) => a.date.compareTo(b.date));
  var balance = current - events.fold<double>(0, (sum, e) => sum + e.amount);
  final points = <BalancePoint>[BalancePoint(start, moneyRound(balance))];
  var eventIndex = 0;
  var end = period == 'day'
      ? start.add(const Duration(hours: 1))
      : DateTime(start.year, start.month, start.day + 1);
  while (true) {
    final boundary = end.isAfter(now) ? now : end;
    while (eventIndex < events.length &&
        !events[eventIndex].date.isAfter(boundary)) {
      balance += events[eventIndex++].amount;
    }
    points.add(BalancePoint(boundary, moneyRound(balance)));
    if (!boundary.isBefore(now)) break;
    end = period == 'day'
        ? end.add(const Duration(hours: 1))
        : DateTime(end.year, end.month, end.day + 1);
  }
  return points;
}

class MovementFilter {
  const MovementFilter({
    this.query = '',
    this.accountId = 'all',
    this.type = 'all',
    this.category = 'all',
    this.currency = 'all',
    this.start,
    this.end,
  });
  final String query, accountId, type, category, currency;
  final DateTime? start, end;

  bool matches(
    Map<String, dynamic> m,
    Map<String, Map<String, dynamic>> accounts,
  ) {
    if (type != 'all' &&
        (type == 'expense'
            ? !isExpenseType(m['type']?.toString())
            : m['type'] != type))
      return false;
    if (accountId != 'all' &&
        m['accountId'] != accountId &&
        m['targetAccountId'] != accountId)
      return false;
    if (category != 'all' && m['category'] != category) return false;
    if (currency != 'all' &&
        m['currency'] != currency &&
        (m['type'] != 'transfer' || m['targetCurrency'] != currency))
      return false;
    final date = parseMovementDate(m['date']?.toString());
    if (start != null && date.isBefore(start!)) return false;
    if (end != null &&
        !date.isBefore(DateTime(end!.year, end!.month, end!.day + 1)))
      return false;
    final tokens = normalizeText(query)
        .trim()
        .split(RegExp(r'\s+'))
        .where((v) => v.isNotEmpty);
    if (tokens.isEmpty) return true;
    final source = accounts[m['accountId']];
    final target = accounts[m['targetAccountId']];
    final text = normalizeText(
      [
        m['description'],
        m['category'],
        m['amount'],
        formatNumber(numberValue(m['amount'])),
        m['currency'],
        if (source != null) accountLabel(source),
        if (target != null) accountLabel(target),
        paymentMethodLabel(m['paymentMethod']?.toString() ?? ''),
      ].join(' '),
    );
    return tokens.every(text.contains);
  }
}

class _UndoChange {
  const _UndoChange(
    this.collection,
    this.id,
    this.before,
    this.after,
    this.index,
  );
  final String collection, id;
  final Map<String, dynamic>? before, after;
  final int index;
}

class _UndoEntry {
  const _UndoEntry(this.label, this.changes);
  final String label;
  final List<_UndoChange> changes;
}

Map<String, dynamic>? _copyRecord(Map<String, dynamic>? value) => value == null
    ? null
    : (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();

String rateStatusText(
  Map<String, dynamic> state,
  String currency, {
  bool loading = false,
  DateTime? now,
}) {
  if (loading) return 'Actualizando';
  now ??= DateTime.now();
  final prefix = currency == 'EUR'
      ? 'eur'
      : currency == 'USDT'
      ? 'usdt'
      : '';
  final key = prefix.isEmpty ? 'rate' : '${prefix}Rate';
  final value = numberValue(state[key]);
  final status = state['${key}FetchStatus']?.toString() ?? '';
  if (status == 'offline')
    return value > 0
        ? 'Sin conexión · Tasa guardada'
        : 'Sin conexión · Sin tasa';
  if (status == 'error')
    return value > 0
        ? 'Error al actualizar · Tasa guardada'
        : 'No se pudo obtener la tasa';
  if (value <= 0) return 'Tasa no disponible';
  final millis = numberValue(
    state[prefix.isEmpty ? 'lastRateMillis' : '${prefix}LastRateMillis'],
  ).round();
  final date = state['${key}EffectiveDate']?.toString() ?? '';
  final fresh = currency == 'USDT'
      ? millis > 0 &&
            now.difference(DateTime.fromMillisecondsSinceEpoch(millis)) <
                const Duration(hours: 24)
      : date == expectedRateDateKey(now);
  return fresh ? 'Actualizada' : 'Última tasa guardada';
}

String rateTimestampText(Map<String, dynamic> state, String currency) {
  final key = currency == 'EUR'
      ? 'eurLastRateMillis'
      : currency == 'USDT'
      ? 'usdtLastRateMillis'
      : 'lastRateMillis';
  final millis = numberValue(state[key]).round();
  if (millis > 0)
    return shortDateTime(DateTime.fromMillisecondsSinceEpoch(millis));
  final dateKey = currency == 'EUR'
      ? 'eurRateEffectiveDate'
      : currency == 'USDT'
      ? 'usdtRateUpdatedAt'
      : 'rateEffectiveDate';
  return state[dateKey]?.toString() ?? '';
}
