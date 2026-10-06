part of 'main.dart';

class MonthlySpendingAmounts {
  final Map<String, double> nativeAmounts = {};
  double usd = 0;
  int missingRates = 0;

  void _add(double amount, String currency, double? converted) {
    nativeAmounts[currency] = moneyAdd(nativeAmounts[currency] ?? 0, amount);
    if (converted == null) {
      missingRates++;
    } else {
      usd = moneyAdd(usd, converted);
    }
  }
}

class MonthlySpendingReport {
  final income = MonthlySpendingAmounts();
  final expenses = MonthlySpendingAmounts();
  final Map<String, MonthlySpendingAmounts> categories = {};
  final Map<String, MonthlySpendingAmounts> accounts = {};

  double? incomePercent(MonthlySpendingAmounts amount) =>
      income.usd <= 0 || income.missingRates > 0 || amount.missingRates > 0
      ? null
      : amount.usd / income.usd * 100;
}

MonthlySpendingReport summarizeMonthlySpending({
  required Map<String, dynamic> state,
  required List<Map<String, dynamic>> movements,
  required String month,
  String? accountId,
}) {
  final report = MonthlySpendingReport();
  final range = budgetPeriodDateRange(month, 'monthly');
  final end = range.last.add(const Duration(days: 1));
  // Cache dated quotes once per instant; do not value old records at today's BCV.
  final datedQuotes = <DateTime, Map<String, dynamic>?>{};
  for (final movement in movements) {
    final date = parseMovementDate(movement['date']?.toString());
    if (date.isBefore(range.first) || !date.isBefore(end)) continue;
    final type = movement['type']?.toString() ?? 'expense';
    if (type != 'income' && type != 'transfer' && !isExpenseType(type))
      continue;
    final currency = movement['currency']?.toString() ?? 'USD';
    final amount = numberValue(movement['amount']);
    final fee = numberValue(movement['feeAmount']);
    if (!amount.isFinite || !fee.isFinite || amount < 0 || fee < 0) continue;
    Map<String, dynamic>? quote;
    if (currency != 'USD' && currency != 'USDT') {
      quote =
          recordedBcvQuote(movement) ??
          datedQuotes.putIfAbsent(date, () => movementBcvQuote(state, date));
    }
    double? convert(double value) {
      try {
        return budgetUsd(
          value,
          currency,
          numberValue(quote?['USD']),
          numberValue(quote?['EUR']),
        );
      } on FormatException {
        return null;
      }
    }

    // The denominator is the month's income across all accounts, even when
    // examining spending from a particular account.
    if (type == 'income') {
      final net = math.max(0.0, moneySubtract(amount, fee));
      if (net > 0) report.income._add(net, currency, convert(net));
      continue;
    }
    final sourceId = movement['accountId']?.toString() ?? '';
    if (accountId != null && accountId != sourceId) continue;
    void addExpense(String category, double value) {
      if (value <= 0) return;
      final converted = convert(value);
      report.expenses._add(value, currency, converted);
      report.categories
          .putIfAbsent(category, MonthlySpendingAmounts.new)
          ._add(value, currency, converted);
      report.accounts
          .putIfAbsent(sourceId, MonthlySpendingAmounts.new)
          ._add(value, currency, converted);
    }

    if (type != 'transfer') {
      final category = movement['category']?.toString().trim() ?? '';
      addExpense(
        canonicalCategory(category.isEmpty ? 'Otro' : category),
        amount,
      );
    }
    // Transfers are not spending; only the bank's fee is an expense.
    addExpense('Comisiones bancarias', fee);
  }
  return report;
}

class MonthlySpendingPage extends StatefulWidget {
  const MonthlySpendingPage({super.key, required this.app, this.initialMonth});
  final _RialAppState app;
  final String? initialMonth;

  @override
  State<MonthlySpendingPage> createState() => _MonthlySpendingPageState();
}

class _MonthlySpendingPageState extends State<MonthlySpendingPage> {
  late String month = widget.initialMonth ?? currentMonthKey();
  String? accountId;
  String grouping = 'category';
  int _revision = -1;
  String? _cachedMonth, _cachedAccount;
  late MonthlySpendingReport _report;
  List<String> _months = [];
  _RialAppState get app => widget.app;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    if (_revision != app.revision.value ||
        _cachedMonth != month ||
        _cachedAccount != accountId) {
      final movements = app.maps('movements');
      _months = {
        currentMonthKey(),
        month,
        ...movements
            .where((m) => parseMovementDate(m['date']?.toString()).year >= 1900)
            .map((m) => monthKeyFromDate(m['date']?.toString())),
      }.toList()..sort((a, b) => b.compareTo(a));
      _report = summarizeMonthlySpending(
        state: app.state,
        movements: movements,
        month: month,
        accountId: accountId,
      );
      _revision = app.revision.value;
      _cachedMonth = month;
      _cachedAccount = accountId;
    }
    final accounts = {
      for (final a in app.maps('accounts')) a['id'].toString(): a,
    };
    String accountName(String id) => accounts[id] == null
        ? 'Cuenta no disponible'
        : accountLabel(accounts[id]);
    final entries =
        (grouping == 'category' ? _report.categories : _report.accounts).entries
            .toList()
          ..sort((a, b) {
            final amount = b.value.usd.compareTo(a.value.usd);
            return amount != 0 ? amount : a.key.compareTo(b.key);
          });
    Color colorFor(String key) => grouping == 'category'
        ? budgetCategoryColor(key, t)
        : accounts[key] == null
        ? t.muted
        : accountColor(accounts[key]!);
    final percent = _report.incomePercent(_report.expenses);
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.92),
        border: null,
        middle: const Text('Resumen mensual'),
      ),
      child: SafeArea(
        child: CustomScrollView(
          key: const ValueKey('monthly-spending-scroll'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OptionField(
                      key: const ValueKey('monthly-spending-month'),
                      theme: t,
                      label: 'Mes',
                      value: monthLabelForKey(month),
                      icon: CupertinoIcons.calendar,
                      onTap: () => showModernActionSheet(
                        context,
                        title: 'Selecciona el mes',
                        actions: [
                          for (final key in _months)
                            ModernSheetAction(
                              title: monthLabelForKey(key),
                              icon: CupertinoIcons.calendar,
                              selected: key == month,
                              onPressed: () => setState(() => month = key),
                            ),
                        ],
                      ),
                    ),
                    OptionField(
                      key: const ValueKey('monthly-spending-account'),
                      theme: t,
                      label: 'Gastos de',
                      value: accountId == null
                          ? 'Todas las cuentas'
                          : accountName(accountId!),
                      icon: CupertinoIcons.creditcard,
                      onTap: () => showModernActionSheet(
                        context,
                        title: 'Cuenta',
                        actions: [
                          ModernSheetAction(
                            title: 'Todas las cuentas',
                            icon: CupertinoIcons.square_grid_2x2,
                            selected: accountId == null,
                            onPressed: () => setState(() => accountId = null),
                          ),
                          for (final key in {
                            ...accounts.keys,
                            ..._report.accounts.keys,
                          })
                            ModernSheetAction(
                              title: accountName(key),
                              icon: CupertinoIcons.creditcard,
                              selected: accountId == key,
                              onPressed: () => setState(() => accountId = key),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    DebtDetailRow(
                      theme: t,
                      label: _report.income.missingRates > 0
                          ? 'Ingresos con tasa'
                          : 'Ingresos del mes',
                      key: const ValueKey('monthly-spending-income'),
                      value: app.secureMoney(_report.income.usd, 'USD'),
                      valueColor: t.green,
                      fitValue: true,
                    ),
                    DebtDetailRow(
                      theme: t,
                      label: _report.expenses.missingRates > 0
                          ? 'Gastos con tasa'
                          : 'Total gastado',
                      key: const ValueKey('monthly-spending-total'),
                      value: app.secureMoney(_report.expenses.usd, 'USD'),
                      valueColor: t.red,
                      fitValue: true,
                    ),
                    Text(
                      app.hideAmounts
                          ? 'Porcentaje oculto'
                          : percent == null
                          ? _report.income.usd <= 0 &&
                                    _report.income.missingRates == 0
                                ? 'Sin ingresos registrados este mes'
                                : 'Porcentaje no disponible'
                          : '${_percent(percent)} de los ingresos del mes',
                      key: const ValueKey('monthly-spending-percent'),
                      style: TextStyle(color: t.muted, fontSize: 13),
                    ),
                    if (_report.income.missingRates > 0 ||
                        _report.expenses.missingRates > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Resumen incompleto: faltan tasas históricas. Los montos originales se conservan.',
                          style: TextStyle(color: t.amber, fontSize: 13),
                        ),
                      ),
                    const SizedBox(height: 22),
                    KindSelector(
                      theme: t,
                      value: grouping,
                      items: const [
                        KindSelectorItem(
                          value: 'category',
                          label: 'Categorías',
                          icon: CupertinoIcons.tag,
                        ),
                        KindSelectorItem(
                          value: 'account',
                          label: 'Cuentas',
                          icon: CupertinoIcons.creditcard,
                        ),
                      ],
                      onChanged: (value) => setState(() => grouping = value),
                    ),
                    if (entries.isNotEmpty &&
                        !app.hideAmounts &&
                        _report.expenses.missingRates == 0) ...[
                      RatioBar(
                        theme: t,
                        separateParts: true,
                        parts: [
                          for (final entry in entries)
                            RatioPart(
                              color: colorFor(entry.key),
                              value: entry.value.usd,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (entries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'Sin gastos en este mes para esta cuenta',
                          style: TextStyle(color: t.muted),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
              sliver: SliverList.builder(
                itemCount: entries.length,
                itemBuilder: (_, index) {
                  final entry = entries[index];
                  final color = colorFor(entry.key);
                  final share = _report.incomePercent(entry.value);
                  final native = entry.value.nativeAmounts.entries.toList()
                    ..sort((a, b) => a.key.compareTo(b.key));
                  return Container(
                    key: ValueKey('monthly-spending-$grouping-${entry.key}'),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: t.border)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              grouping == 'category'
                                  ? categoryIcon(entry.key, context: context)
                                  : CupertinoIcons.creditcard,
                              color: color,
                              size: 21,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                grouping == 'category'
                                    ? entry.key
                                    : accountName(entry.key),
                                style: TextStyle(
                                  color: t.ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          native
                              .map(
                                (item) => app.secureMoney(item.value, item.key),
                              )
                              .join(' + '),
                          style: TextStyle(
                            color: t.ink,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        if (native.length != 1 ||
                            native.first.key != 'USD') ...[
                          const SizedBox(height: 4),
                          Text(
                            entry.value.missingRates > 0
                                ? 'Equivalente BCV incompleto'
                                : '${app.secureMoney(entry.value.usd, 'USD')} ${native.any((n) => n.key == 'VES' || n.key == 'EUR') ? 'al BCV de cada movimiento' : 'equivalentes (1 a 1)'}',
                            style: TextStyle(color: t.muted, fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          app.hideAmounts
                              ? 'Porcentaje oculto'
                              : share == null
                              ? 'Sin porcentaje de ingresos'
                              : '${_percent(share)} de tus ingresos',
                          style: TextStyle(color: t.muted, fontSize: 12),
                        ),
                        if (!app.hideAmounts && share != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: material.LinearProgressIndicator(
                                value: (share / 100).clamp(0.0, 1.0),
                                minHeight: 4,
                                color: color,
                                backgroundColor: t.field,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _percent(double value) =>
      '${value.toStringAsFixed(1).replaceAll('.', ',')}%';
}
