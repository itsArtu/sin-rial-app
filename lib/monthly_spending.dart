part of 'main.dart';

class MonthlySpendingAmounts {
  final Map<String, double> nativeAmounts = {};
  // Attribute only the principal or fee represented by this report group.
  final Map<Map<String, dynamic>, double> movementAmounts = {};
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
      for (final group in [
        report.categories.putIfAbsent(category, MonthlySpendingAmounts.new),
        report.accounts.putIfAbsent(sourceId, MonthlySpendingAmounts.new),
      ]) {
        group._add(value, currency, converted);
        group.movementAmounts[movement] = moneyAdd(
          group.movementAmounts[movement] ?? 0,
          value,
        );
      }
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

class MonthlyDistributionChart extends StatelessWidget {
  const MonthlyDistributionChart({
    super.key,
    required this.theme,
    required this.entries,
    this.onSelected,
  });
  final RTheme theme;
  final List<(String, double, Color)> entries;
  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) {
    final positiveIndices = [
      for (var i = 0; i < entries.length; i++)
        if (entries[i].$2 > 0) i,
    ];
    final positive = [for (final index in positiveIndices) entries[index]];
    final total = positive.fold(0.0, (sum, entry) => sum + entry.$2);
    if (total <= 0) return const SizedBox.shrink();
    String percent(double amount) =>
        '${(amount / total * 100).toStringAsFixed(1).replaceAll('.', ',')}%';
    final legend = positive.take(3).toList();
    if (positive.length > 3) {
      legend.add((
        'Restantes',
        positive.skip(3).fold(0.0, (sum, e) => sum + e.$2),
        theme.muted,
      ));
    }
    return Padding(
      key: const ValueKey('monthly-distribution-chart'),
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            height: 140,
            child: RepaintBoundary(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ExcludeSemantics(
                    child: charts.PieChart(
                      charts.PieChartData(
                        startDegreeOffset: -90,
                        centerSpaceRadius: 48,
                        sectionsSpace: 2,
                        pieTouchData: charts.PieTouchData(
                          enabled: onSelected != null,
                          touchCallback: (event, response) {
                            final index =
                                response?.touchedSection?.touchedSectionIndex ??
                                -1;
                            if (event is charts.FlTapUpEvent &&
                                index >= 0 &&
                                index < positive.length) {
                              onSelected?.call(positiveIndices[index]);
                            }
                          },
                        ),
                        sections: [
                          for (final entry in positive)
                            charts.PieChartSectionData(
                              value: entry.$2,
                              color: entry.$3,
                              radius: 18,
                              showTitle: false,
                            ),
                        ],
                      ),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 380),
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                  Text(
                    'Gastos',
                    style: TextStyle(color: theme.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (
                  var legendIndex = 0;
                  legendIndex < legend.length;
                  legendIndex++
                )
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Semantics(
                      button: legendIndex < 3 && onSelected != null,
                      label:
                          '${legend[legendIndex].$1}: ${percent(legend[legendIndex].$2)} de los gastos',
                      child: PressFeedback(
                        onTap: legendIndex < 3 && onSelected != null
                            ? () => onSelected!(positiveIndices[legendIndex])
                            : null,
                        child: ExcludeSemantics(
                          child: Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: legend[legendIndex].$3,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  legend[legendIndex].$1,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: theme.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                percent(legend[legendIndex].$2),
                                style: TextStyle(
                                  color: theme.ink,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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

  void openGroup(String key, String title) => app.pushPage(
    context,
    (_) => MonthlySpendingMovementsPage(
      app: app,
      month: month,
      accountId: accountId,
      grouping: grouping,
      groupKey: key,
      title: title,
    ),
  );

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
                      compact: true,
                      label: 'Mes',
                      compactLabel: monthLabelForKey(month),
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
                    const SizedBox(height: 8),
                    OptionField(
                      key: const ValueKey('monthly-spending-account'),
                      theme: t,
                      compact: true,
                      logoProvider: accounts[accountId]?['provider']
                          ?.toString(),
                      label: 'Gastos de',
                      compactLabel: accountId == null
                          ? 'Todas las cuentas'
                          : accountName(accountId!),
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
                              logoProvider: accounts[key]?['provider']
                                  ?.toString(),
                              selected: accountId == key,
                              onPressed: () => setState(() => accountId = key),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      accountId == null
                          ? (_report.income.missingRates > 0 ||
                                    _report.expenses.missingRates > 0
                                ? 'Balance con tasas disponibles'
                                : 'Balance del mes')
                          : (_report.expenses.missingRates > 0
                                ? 'Gastos con tasa'
                                : 'Gastos de la cuenta'),
                      style: TextStyle(color: t.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      app.secureMoney(
                        accountId == null
                            ? moneySubtract(
                                _report.income.usd,
                                _report.expenses.usd,
                              )
                            : _report.expenses.usd,
                        'USD',
                      ),
                      key: const ValueKey('monthly-spending-balance'),
                      style: TextStyle(
                        color: t.ink,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DebtDetailRow(
                      theme: t,
                      label: _report.income.missingRates > 0
                          ? 'Ingresos con tasa'
                          : 'Ingresos del mes',
                      key: const ValueKey('monthly-spending-income'),
                      value: app.secureMoney(_report.income.usd, 'USD'),
                      valueColor: t.income,
                      fitValue: true,
                    ),
                    DebtDetailRow(
                      theme: t,
                      label: _report.expenses.missingRates > 0
                          ? 'Gastos con tasa'
                          : 'Total gastado',
                      key: const ValueKey('monthly-spending-total'),
                      value: app.secureMoney(_report.expenses.usd, 'USD'),
                      valueColor: t.expense,
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
                    AppPillSelector(
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
                      MonthlyDistributionChart(
                        theme: t,
                        onSelected: (index) => openGroup(
                          entries[index].key,
                          grouping == 'category'
                              ? entries[index].key
                              : accountName(entries[index].key),
                        ),
                        entries: [
                          for (final entry in entries)
                            (
                              grouping == 'category'
                                  ? entry.key
                                  : accountName(entry.key),
                              entry.value.usd,
                              colorFor(entry.key),
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
                  return Semantics(
                    button: true,
                    child: PressFeedback(
                      onTap: () => openGroup(
                        entry.key,
                        grouping == 'category'
                            ? entry.key
                            : accountName(entry.key),
                      ),
                      child: Container(
                        key: ValueKey(
                          'monthly-spending-$grouping-${entry.key}',
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: t.border)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                if (grouping == 'account' &&
                                    accounts[entry.key] != null)
                                  LogoBadge(
                                    provider:
                                        accounts[entry.key]!['provider']
                                            ?.toString() ??
                                        '',
                                    theme: t,
                                    size: 30,
                                  )
                                else
                                  Icon(
                                    categoryIcon(entry.key, context: context),
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
                                Icon(
                                  CupertinoIcons.chevron_right,
                                  size: 14,
                                  color: t.muted,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              native
                                  .map(
                                    (item) =>
                                        app.secureMoney(item.value, item.key),
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
                      ),
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

class MonthlySpendingMovementsPage extends StatelessWidget {
  const MonthlySpendingMovementsPage({
    super.key,
    required this.app,
    required this.month,
    required this.grouping,
    required this.groupKey,
    required this.title,
    this.accountId,
  });
  final _RialAppState app;
  final String month, grouping, groupKey, title;
  final String? accountId;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final report = summarizeMonthlySpending(
      state: app.state,
      movements: app.maps('movements'),
      month: month,
      accountId: accountId,
    );
    final group = (grouping == 'category'
        ? report.categories
        : report.accounts)[groupKey];
    final movements = sortedMovements(
      group?.movementAmounts.keys.toList() ?? [],
    );
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg,
        border: null,
        middle: Text(
          grouping == 'account'
              ? app.accountById(groupKey) == null
                    ? 'Cuenta no disponible'
                    : accountLabel(app.accountById(groupKey))
              : title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      monthLabelForKey(month),
                      style: TextStyle(color: t.muted, fontSize: 13),
                    ),
                    if (accountId != null && grouping == 'category')
                      Text(
                        accountLabel(app.accountById(accountId!)),
                        style: TextStyle(color: t.muted, fontSize: 12),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      (group?.missingRates ?? 0) == 0
                          ? app.secureMoney(group?.usd ?? 0, 'USD')
                          : 'Equivalente BCV incompleto',
                      key: const ValueKey('monthly-drill-total'),
                      style: TextStyle(
                        color: t.ink,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${movements.length} ${movements.length == 1 ? 'movimiento' : 'movimientos'}',
                      style: TextStyle(color: t.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              sliver: SliverList.builder(
                itemCount: movements.length,
                itemBuilder: (_, index) {
                  final movement = movements[index];
                  final account = app.accountById(
                    movement['accountId']?.toString() ?? '',
                  );
                  final currency = movement['currency']?.toString() ?? 'USD';
                  final amount = group!.movementAmounts[movement]!;
                  final feeOnly =
                      movement['type'] == 'transfer' ||
                      (grouping == 'category' &&
                          groupKey == 'Comisiones bancarias' &&
                          canonicalCategory(
                                movement['category']?.toString() ?? 'Otro',
                              ) !=
                              'Comisiones bancarias');
                  final description =
                      movement['description']?.toString().trim() ?? '';
                  return Semantics(
                    button: true,
                    child: PressFeedback(
                      key: ValueKey('monthly-drill-${movement['id']}'),
                      onTap: () => app.pushPage(
                        context,
                        (_) => MovementDetailPage(
                          app: app,
                          movementId: movement['id']?.toString() ?? '',
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: t.border)),
                        ),
                        child: Row(
                          children: [
                            LogoBadge(
                              provider: account?['provider']?.toString() ?? '',
                              theme: t,
                              size: 34,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    description.isNotEmpty
                                        ? description
                                        : feeOnly
                                        ? 'Comisión bancaria'
                                        : movement['category']?.toString() ??
                                              'Gasto',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: t.ink,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${accountPrimaryName(account ?? {})} · ${formatDate(parseMovementDate(movement['date']?.toString()))}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: t.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    app.secureMoney(amount, currency),
                                    style: TextStyle(
                                      color: t.expense,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (feeOnly)
                                    Text(
                                      'Comisión',
                                      style: TextStyle(
                                        color: t.muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              CupertinoIcons.chevron_right,
                              color: t.muted,
                              size: 13,
                            ),
                          ],
                        ),
                      ),
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
}
