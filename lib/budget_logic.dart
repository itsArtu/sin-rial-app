part of 'main.dart';

String budgetPlanId(String period, String type) => '$type:$period';

String nextBudgetPeriod(String period, String type) {
  final range = budgetPeriodDateRange(period, type);
  return budgetPeriodKeyFor(range.last.add(const Duration(days: 1)), type);
}

bool validBudgetPeriod(String period, String type) {
  if (type != 'monthly' && type != 'biweekly') return false;
  final pattern = type == 'monthly'
      ? RegExp(r'^\d{4}-(0[1-9]|1[0-2])$')
      : RegExp(r'^\d{4}-(0[1-9]|1[0-2])-H[12]$');
  return pattern.hasMatch(period) && int.parse(period.substring(0, 4)) >= 1900;
}

void migrateBudgetPlans(Map<String, dynamic> state) {
  if (state['budgetPlansMigrated'] == true) return;
  final plans = (state['budgetPlans'] as List)
      .whereType<Map>()
      .map((p) => Map<String, dynamic>.from(p))
      .toList();
  final byId = {for (final p in plans) p['id']: p};
  final items = <Map<String, dynamic>>[];
  void ensurePlan(String period, String type) {
    final id = budgetPlanId(period, type);
    byId.putIfAbsent(
      id,
      () => {
        'id': id,
        'period': period,
        'periodType': type,
        'salary': numberValue(state['budgetSalary']),
        'savings': budgetSavings(state),
        'currency': state['budgetCurrency'] ?? 'USD',
      },
    );
  }

  for (final raw in (state['budgets'] as List).whereType<Map>()) {
    final item = Map<String, dynamic>.from(raw);
    final stored = item['period']?.toString() ?? '';
    final type =
        item['periodType'] == 'biweekly' ||
            stored.endsWith('-H1') ||
            stored.endsWith('-H2')
        ? 'biweekly'
        : 'monthly';
    var period = stored.isNotEmpty ? stored : item['month']?.toString() ?? '';
    if (type == 'biweekly' && RegExp(r'^\d{4}-\d{2}$').hasMatch(period))
      period = '$period-H1';
    if (!validBudgetPeriod(period, type))
      period = currentBudgetPeriodKey(type: type);
    ensurePlan(period, type);
    item.addAll({
      'planId': budgetPlanId(period, type),
      'period': period,
      'periodType': type,
    });
    items.add(item);
  }
  if (plans.isEmpty &&
      items.isEmpty &&
      (numberValue(state['budgetSalary']) > 0 || budgetSavings(state) > 0)) {
    final type = currentBudgetPeriodType(state);
    ensurePlan(currentBudgetPeriodKey(type: type), type);
  }
  state['budgetPlans'] = byId.values.toList();
  state['budgets'] = items;
  state['budgetPlansMigrated'] = true;
}

Map<String, dynamic>? findBudgetPlan(_RialAppState app, String id) =>
    app.maps('budgetPlans').where((p) => p['id'] == id).firstOrNull;

List<Map<String, dynamic>> budgetPlanItems(_RialAppState app, String id) =>
    app.maps('budgets').where((b) => b['planId'] == id).toList();

double budgetUsd(double amount, String currency, double rate, double eurRate) {
  if (currency == 'USD' || currency == 'USDT') return moneyRound(amount);
  if (rate <= 0 || (currency == 'EUR' && eurRate <= 0)) {
    throw const FormatException(
      'Falta una tasa para calcular este presupuesto.',
    );
  }
  if (currency == 'VES') return moneyConvert(amount, 1, rate);
  if (currency == 'EUR') return moneyConvert(amount, eurRate, rate);
  throw const FormatException('Moneda no admitida.');
}

double budgetItemUsd(_RialAppState app, Map<String, dynamic> item) => budgetUsd(
  numberValue(item['limit']),
  item['currency']?.toString() ?? 'USD',
  app.rate,
  app.eurRate,
);

String budgetItemName(Map<String, dynamic> item) {
  final name = item['name']?.toString().trim() ?? '';
  return name.isEmpty ? item['category']?.toString() ?? 'Otro' : name;
}

String budgetItemLabel(Map<String, dynamic> item) =>
    budgetItemName(item) == item['category']
    ? budgetItemName(item)
    : '${item['category']} / ${budgetItemName(item)}';

bool budgetItemMatchesDate(Map<String, dynamic> item, DateTime date) {
  final period = item['period']?.toString() ?? '';
  final type = item['periodType']?.toString() ?? 'monthly';
  if (!validBudgetPeriod(period, type)) return false;
  final range = budgetPeriodDateRange(period, type);
  return !date.isBefore(range.first) &&
      date.isBefore(range.last.add(const Duration(days: 1)));
}

List<Map<String, dynamic>> movementBudgetItems(
  _RialAppState app,
  String category,
  String date,
) => app
    .maps('budgets')
    .where(
      (item) =>
          item['category'] == category &&
          budgetItemMatchesDate(item, parseMovementDate(date)),
    )
    .toList();

void validateMovementBudgetLink(
  _RialAppState app,
  Map<String, dynamic> movement,
  Map<String, dynamic>? previous,
) {
  final id = movement['budgetItemId']?.toString() ?? '';
  if (id.isEmpty) {
    movement.remove('budgetPlanId');
    movement.remove('budgetItemName');
    return;
  }
  final item =
      movementBudgetItems(
            app,
            movement['category']?.toString() ?? '',
            movement['date']?.toString() ?? '',
          )
          .where(
            (item) =>
                item['id'] == id && item['planId'] == movement['budgetPlanId'],
          )
          .firstOrNull;
  if (!isExpenseType(movement['type']?.toString()) || item == null) {
    final unchanged =
        isExpenseType(movement['type']?.toString()) &&
        previous?['budgetItemId'] == id &&
        previous?['budgetPlanId'] == movement['budgetPlanId'] &&
        previous?['date'] == movement['date'] &&
        previous?['category'] == movement['category'];
    if (!unchanged)
      throw const FormatException(
        'La partida no pertenece a esta categoria o fecha.',
      );
    movement['budgetItemName'] = previous?['budgetItemName'] ?? '';
    return;
  }
  movement['budgetItemName'] = budgetItemName(item);
}

double movementBudgetCurrency(
  Map<String, dynamic> movement,
  double amount,
  String currency,
  double usdRate,
  double eurRate,
) {
  if (movement['currency'] == currency) return moneyRound(amount);
  if (currency == 'USD' || currency == 'USDT') {
    return movementBudgetUsd(movement, amount, usdRate, eurRate);
  }
  final quote = recordedBcvQuote(movement);
  final rates = {
    'VES': 1.0,
    'USD': quote == null ? usdRate : numberValue(quote['USD']),
    'EUR': quote == null ? eurRate : numberValue(quote['EUR']),
  };
  final source = movement['currency']?.toString() ?? 'USD';
  final from = rates[source == 'USDT' ? 'USD' : source] ?? 0;
  final to = rates[currency] ?? 0;
  if (from <= 0 || to <= 0)
    throw const FormatException('Falta la tasa del movimiento.');
  return moneyConvert(amount, from, to);
}

class BudgetSpending {
  const BudgetSpending(
    this.categories,
    this.total,
    this.missingRates, {
    this.items = const {},
    this.itemCurrencies = const {},
    this.unassigned = const {},
  });
  final Map<String, double> categories;
  final double total;
  final int missingRates;
  final Map<String, double> items, itemCurrencies, unassigned;
  List<MapEntry<String, double>> get ranked =>
      categories.entries.toList()..sort((a, b) {
        final amount = b.value.compareTo(a.value);
        return amount != 0 ? amount : a.key.compareTo(b.key);
      });
}

BudgetSpending summarizeBudgetSpending(
  List<Map<String, dynamic>> movements,
  String period,
  String type, {
  required double usdRate,
  required double eurRate,
  Set<String>? selectedCategories,
  List<Map<String, dynamic>> items = const [],
}) {
  final range = budgetPeriodDateRange(period, type);
  final end = range.last.add(const Duration(days: 1));
  final cents = <String, int>{};
  final byId = {for (final item in items) item['id']?.toString() ?? '': item};
  final legacy = <String, List<Map<String, dynamic>>>{};
  for (final item in items) {
    if ((item['name']?.toString().trim() ?? '').isEmpty) {
      legacy.putIfAbsent(item['category'].toString(), () => []).add(item);
    }
  }
  final itemCents = <String, int>{},
      nativeCents = <String, int>{},
      unassigned = <String, int>{};
  var missing = 0;
  // Parse each date and convert each expense once, irrespective of category count.
  for (final movement in movements) {
    if (!isExpenseType(movement['type']?.toString())) continue;
    final date = parseMovementDate(movement['date']?.toString());
    if (date.isBefore(range.first) || !date.isBefore(end)) continue;
    final category = movement['category']?.toString().trim();
    final key = category == null || category.isEmpty ? 'Otro' : category;
    if (selectedCategories != null && !selectedCategories.contains(key))
      continue;
    try {
      final currency = movement['currency']?.toString() ?? 'USD';
      final fee = numberValue(movement['feeAmount']);
      final sourceCents =
          moneyCents(numberValue(movement['amount'])) +
          (fee == 0 ? 0 : moneyCents(fee));
      final valueCents = currency == 'USD' || currency == 'USDT'
          ? sourceCents
          : moneyCents(
              movementBudgetUsd(movement, sourceCents / 100, usdRate, eurRate),
            );
      final linkedId = movement['budgetItemId']?.toString() ?? '';
      final candidates = legacy[key] ?? const <Map<String, dynamic>>[];
      final item = linkedId.isNotEmpty
          ? byId[linkedId]
          : candidates.length == 1
          ? candidates.single
          : null;
      final matched =
          item != null &&
          item['category'] == key &&
          (linkedId.isEmpty || movement['budgetPlanId'] == item['planId']);
      final native = matched
          ? moneyCents(
              movementBudgetCurrency(
                movement,
                sourceCents / 100,
                item['currency']?.toString() ?? 'USD',
                usdRate,
                eurRate,
              ),
            )
          : 0;
      cents[key] = (cents[key] ?? 0) + valueCents;
      if (matched) {
        final id = item['id'].toString();
        itemCents[id] = (itemCents[id] ?? 0) + valueCents;
        nativeCents[id] = (nativeCents[id] ?? 0) + native;
      } else {
        unassigned[key] = (unassigned[key] ?? 0) + valueCents;
      }
    } on FormatException {
      missing++;
    }
  }
  return BudgetSpending(
    {for (final entry in cents.entries) entry.key: entry.value / 100},
    cents.values.fold<int>(0, (a, b) => a + b) / 100,
    missing,
    items: {
      for (final entry in itemCents.entries) entry.key: entry.value / 100,
    },
    itemCurrencies: {
      for (final entry in nativeCents.entries) entry.key: entry.value / 100,
    },
    unassigned: {
      for (final entry in unassigned.entries) entry.key: entry.value / 100,
    },
  );
}

class BudgetSpendingCache {
  int _revision = -1;
  String _period = '', _type = '', _selection = '';
  BudgetSpending? _value;
  BudgetSpending read(
    _RialAppState app,
    String period,
    String type, {
    Set<String>? selectedCategories,
    List<Map<String, dynamic>> items = const [],
  }) {
    final selection =
        (selectedCategories == null
            ? '*'
            : jsonEncode(selectedCategories.toList()..sort())) +
        jsonEncode(items);
    if (_value == null ||
        _revision != app.revision.value ||
        _period != period ||
        _type != type ||
        _selection != selection) {
      _value = summarizeBudgetSpending(
        app.maps('movements'),
        period,
        type,
        usdRate: app.rate,
        eurRate: app.eurRate,
        selectedCategories: selectedCategories,
        items: items,
      );
      _revision = app.revision.value;
      _period = period;
      _type = type;
      _selection = selection;
    }
    return _value!;
  }
}

Color budgetCategoryColor(String category, RTheme theme) {
  const hues = [
    210.0,
    34.0,
    285.0,
    325.0,
    235.0,
    18.0,
    55.0,
    145.0,
    195.0,
    350.0,
    295.0,
    255.0,
    0.0,
    310.0,
    90.0,
    158.0,
    220.0,
  ];
  final index = budgetCategories.indexOf(category);
  final hue = index >= 0 && index < hues.length
      ? hues[index]
      : (category.codeUnits.fold<int>(0, (a, b) => a + b) * 137.508) % 360;
  return HSVColor.fromAHSV(1, hue, .64, theme.dark ? .91 : .68).toColor();
}

bool canCreateBudgetInMonth(String month, {DateTime? now}) =>
    month.compareTo(budgetPeriodKeyFor(now ?? DateTime.now(), 'monthly')) >= 0;

String? adjacentBudgetMonth(
  List<Map<String, dynamic>> plans,
  String month,
  int direction, {
  DateTime? now,
}) {
  final current = budgetPeriodKeyFor(now ?? DateTime.now(), 'monthly');
  final date = DateTime.parse('$month-01');
  final adjacent = budgetPeriodKeyFor(
    DateTime(date.year, date.month + direction),
    'monthly',
  );
  if (adjacent.compareTo(current) >= 0) return adjacent;
  final history =
      <String>{
            current,
            ...plans.map((p) => p['period'].toString().substring(0, 7)),
          }
          .where(
            (m) =>
                direction < 0 ? m.compareTo(month) < 0 : m.compareTo(month) > 0,
          )
          .toList()
        ..sort();
  return history.isEmpty
      ? null
      : (direction < 0 ? history.last : history.first);
}

String validateBudgetPlanPeriod(
  _RialAppState app,
  String period,
  String type, {
  String? editingId,
  DateTime? now,
}) {
  if (!validBudgetPeriod(period, type))
    throw const FormatException('Selecciona un periodo valido.');
  final id = budgetPlanId(period, type);
  if (editingId != null) {
    if (editingId != id || findBudgetPlan(app, editingId) == null) {
      throw const FormatException(
        'El plan cambio. Vuelve a abrirlo antes de editar.',
      );
    }
    return id;
  }
  if (!canCreateBudgetInMonth(period.substring(0, 7), now: now)) {
    throw const FormatException(
      'No puedes crear planes en meses anteriores al actual.',
    );
  }
  final range = budgetPeriodDateRange(period, type);
  for (final other in app.maps('budgetPlans')) {
    final otherRange = budgetPeriodDateRange(
      other['period'].toString(),
      other['periodType'].toString(),
    );
    if (!range.last.isBefore(otherRange.first) &&
        !range.first.isAfter(otherRange.last)) {
      throw const FormatException(
        'Estas fechas ya tienen un presupuesto. Edita ese plan o elige otro periodo.',
      );
    }
  }
  return id;
}

void saveBudgetPlan(
  _RialAppState app, {
  required String period,
  required String type,
  required double salary,
  required double savings,
  required List<Map<String, dynamic>> items,
  String incomeMode = 'fixed',
  List<Map<String, dynamic>>? incomes,
  String? editingId,
  DateTime? now,
}) {
  final id = validateBudgetPlanPeriod(
    app,
    period,
    type,
    editingId: editingId,
    now: now,
  );
  if (incomeMode != 'fixed' && incomeMode != 'variable') {
    throw const FormatException('Selecciona ingresos fijos o variables.');
  }
  final sources = <Map<String, dynamic>>[];
  if (incomeMode == 'fixed' && incomes != null) {
    for (final source in incomes) {
      final name = source['name']?.toString().trim() ?? '';
      final amount = numberValue(source['amount']);
      if (name.isEmpty ||
          !amount.isFinite ||
          amount <= 0 ||
          amount > 999999999999 ||
          moneyCents(amount) <= 0) {
        throw const FormatException(
          'Cada ingreso necesita un nombre y un monto mayor a cero.',
        );
      }
      sources.add({'name': name, 'amount': moneyRound(amount)});
    }
    salary = sources.fold<double>(
      0,
      (total, source) => moneyAdd(total, numberValue(source['amount'])),
    );
  }
  if (incomeMode == 'variable') salary = 0;
  if (!salary.isFinite ||
      salary < 0 ||
      salary > 999999999999 ||
      !savings.isFinite ||
      savings < 0 ||
      savings > 999999999999 ||
      (incomeMode == 'fixed' &&
          (moneyCents(salary) <= 0 || savings > salary))) {
    throw const FormatException(
      'Revisa el ingreso y el ahorro. Con ingresos fijos, el ahorro no puede superar al ingreso.',
    );
  }
  if (incomeMode == 'fixed' && sources.isEmpty) {
    sources.add({'name': 'Salario', 'amount': moneyRound(salary)});
  }
  final oldItems = budgetPlanItems(app, id);
  final oldIds = oldItems.map((item) => item['id'].toString()).toSet();
  final seen = <String>{}, seenIds = <String>{};
  final savedItems = <Map<String, dynamic>>[];
  for (final item in items) {
    final category = item['category']?.toString().trim() ?? '';
    final name = item['name']?.toString().trim() ?? '';
    final currency = item['currency']?.toString() ?? 'USD';
    final limit = numberValue(item['limit']);
    if (category.isEmpty ||
        !seen.add(jsonEncode([category, name.toLowerCase()])) ||
        !const ['USD', 'VES', 'EUR', 'USDT'].contains(currency) ||
        !limit.isFinite ||
        limit <= 0 ||
        limit > 999999999999) {
      throw const FormatException(
        'Cada partida necesita un nombre distinto dentro de su categoria y un monto mayor a cero.',
      );
    }
    if (moneyCents(limit) <= 0)
      throw const FormatException('El limite debe ser al menos 0,01.');
    budgetItemUsd(app, item);
    final existingId = item['id']?.toString() ?? '';
    final itemId = oldIds.contains(existingId) ? existingId : app.id();
    if (!seenIds.add(itemId)) throw const FormatException('Partida repetida.');
    savedItems.add({
      'id': itemId,
      'planId': id,
      'period': period,
      'periodType': type,
      'month': period.substring(0, 7),
      'category': category,
      'name': name,
      'limit': moneyRound(limit),
      'currency': currency,
    });
  }
  app.undoableMutation(
    'Plan guardado',
    {
      'budgetPlans': {id},
      'budgets': {
        ...oldItems.map((b) => b['id'].toString()),
        ...savedItems.map((b) => b['id'].toString()),
      },
    },
    () {
      final plans = app.rawList('budgetPlans');
      plans.removeWhere((p) => p is Map && p['id'] == id);
      plans.add({
        'id': id,
        'period': period,
        'periodType': type,
        'salary': moneyRound(salary),
        'incomeMode': incomeMode,
        'incomes': sources,
        'savings': moneyRound(savings),
        'currency': 'USD',
      });
      app.rawList('budgets')
        ..removeWhere((b) => b is Map && b['planId'] == id)
        ..addAll(savedItems);
    },
  );
}

void deleteBudgetPlan(_RialAppState app, String id) {
  final items = budgetPlanItems(app, id);
  app.undoableMutation(
    'Plan eliminado',
    {
      'budgetPlans': {id},
      'budgets': items.map((b) => b['id'].toString()).toSet(),
    },
    () {
      app.rawList('budgetPlans').removeWhere((p) => p is Map && p['id'] == id);
      app.rawList('budgets').removeWhere((b) => b is Map && b['planId'] == id);
    },
  );
}
