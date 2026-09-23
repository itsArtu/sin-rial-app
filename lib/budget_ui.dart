part of 'main.dart';

class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key, required this.app});
  final _RialAppState app;
  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage>
    with AutomaticKeepAliveClientMixin {
  String month = currentMonthKey();
  String? selectedType;
  int half = DateTime.now().day <= 15 ? 1 : 2;
  final spendingCache = BudgetSpendingCache();
  String? expandedSection;
  String? expandedPlan;
  bool exporting = false;

  Future<void> exportPlan(Map<String, dynamic> plan) async {
    if (exporting) return;
    exporting = true;
    try {
      final app = widget.app;
      final report = budgetReport(
        plan: plan,
        items: budgetPlanItems(app, plan['id'].toString()),
        movements: app.maps('movements'),
        accounts: app.maps('accounts'),
        usdRate: app.rate,
        eurRate: app.eurRate,
      );
      final saved = await saveBudgetPdf(report);
      if (saved && mounted)
        showModernNotice(
          context,
          title: 'PDF guardado',
          message:
              'El presupuesto se guard\u00f3 en la ubicaci\u00f3n elegida.',
        );
    } catch (error) {
      if (mounted)
        showModernNotice(
          context,
          title: 'No se pudo exportar',
          message: error is FormatException
              ? error.message
              : 'No se pudo guardar el PDF. Intenta de nuevo.',
        );
    } finally {
      exporting = false;
    }
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> editPlan({
    Map<String, dynamic>? plan,
    bool copy = false,
    int step = 0,
  }) async {
    final app = widget.app;
    final type =
        plan?['periodType']?.toString() ??
        (app
                .maps('budgetPlans')
                .any(
                  (p) =>
                      p['period'].toString().startsWith(month) &&
                      p['periodType'] == 'biweekly',
                )
            ? 'biweekly'
            : 'monthly');
    final period = copy
        ? nextBudgetPeriod(plan!['period'].toString(), type)
        : plan?['period']?.toString() ??
              (type == 'biweekly' ? '$month-H$half' : month);
    final result = await app.pushPage<String>(
      context,
      (_) => BudgetPlanEditorPage(
        app: app,
        plan: plan,
        copy: copy,
        initialPeriod: period,
        initialType: type,
        initialStep: step,
      ),
    );
    if (!mounted || result == null) return;
    final saved = findBudgetPlan(app, result);
    if (saved != null)
      setState(() {
        month = saved['period'].toString().substring(0, 7);
        selectedType = saved['periodType'].toString();
        half = saved['period'].toString().endsWith('H2') ? 2 : 1;
      });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = widget.app, t = app.theme;
    final plans = app.maps('budgetPlans');
    final monthPlans = plans
        .where((p) => p['period'].toString().startsWith(month))
        .toList();
    final hasMonthly = monthPlans.any((p) => p['periodType'] == 'monthly');
    final hasBiweekly = monthPlans.any((p) => p['periodType'] == 'biweekly');
    final fortnightly =
        hasBiweekly && (!hasMonthly || selectedType == 'biweekly');
    final period = fortnightly ? '$month-H$half' : month;
    final plan = monthPlans.where((p) => p['period'] == period).firstOrNull;
    final previousMonth = adjacentBudgetMonth(plans, month, -1);
    final canCreate = canCreateBudgetInMonth(month);
    final widgets = <Widget>[];
    if (plans.isNotEmpty) {
      widgets.add(
        Row(
          children: [
            material.Tooltip(
              message: 'Mes anterior',
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: previousMonth == null ? null : () => shiftMonth(-1),
                child: Icon(
                  CupertinoIcons.chevron_left,
                  color: previousMonth == null
                      ? t.muted.withOpacity(.35)
                      : t.accent,
                ),
              ),
            ),
            Expanded(
              child: OptionField(
                theme: t,
                label: 'Mes',
                value: monthLabelForKey(month),
                onTap: pickMonth,
              ),
            ),
            material.Tooltip(
              message: 'Mes siguiente',
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => shiftMonth(1),
                child: Icon(CupertinoIcons.chevron_right, color: t.accent),
              ),
            ),
          ],
        ),
      );
      if (hasMonthly && hasBiweekly)
        widgets.add(
          KindSelector(
            theme: t,
            value: fortnightly ? 'biweekly' : 'monthly',
            items: const [
              KindSelectorItem(
                value: 'monthly',
                label: 'Mensual',
                icon: CupertinoIcons.calendar,
              ),
              KindSelectorItem(
                value: 'biweekly',
                label: 'Quincenal',
                icon: CupertinoIcons.calendar,
              ),
            ],
            onChanged: (value) => setState(() => selectedType = value),
          ),
        );
      if (fortnightly)
        widgets.add(
          KindSelector(
            theme: t,
            value: '$half',
            items: const [
              KindSelectorItem(
                value: '1',
                label: '1ra quincena',
                icon: CupertinoIcons.calendar,
              ),
              KindSelectorItem(
                value: '2',
                label: '2da quincena',
                icon: CupertinoIcons.calendar,
              ),
            ],
            onChanged: (value) => setState(() => half = int.parse(value)),
          ),
        );
    }
    if (plan == null) {
      widgets.addAll([
        const SizedBox(height: 28),
        Icon(CupertinoIcons.chart_pie, size: 48, color: t.accent),
        const SizedBox(height: 18),
        Text(
          canCreate
              ? '\u00bfQuieres crear un plan de presupuestos?'
              : 'No hay un plan guardado para este periodo',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: t.ink,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (plans.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            budgetPeriodLabel(period, fortnightly ? 'biweekly' : 'monthly'),
            textAlign: TextAlign.center,
            style: TextStyle(color: t.muted),
          ),
        ],
        const SizedBox(height: 24),
        if (canCreate)
          PrimaryActionButton(
            theme: t,
            label: 'S\u00ed, crear plan',
            onPressed: () => editPlan(),
          ),
      ]);
    } else {
      widgets.addAll(planWidgets(plan));
    }
    widgets.add(const SizedBox(height: 110));
    return AppScroll(
      title: 'Presupuesto',
      theme: t,
      trailing: plan == null
          ? null
          : material.Tooltip(
              message: 'Opciones del plan',
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                child: Icon(CupertinoIcons.ellipsis, color: t.accent),
                onPressed: () => showModernActionSheet(
                  context,
                  title: 'Plan de presupuestos',
                  actions: [
                    ModernSheetAction(
                      icon: CupertinoIcons.doc_text,
                      title: 'Exportar PDF',
                      onPressed: () => exportPlan(plan),
                    ),
                    ModernSheetAction(
                      icon: CupertinoIcons.pencil,
                      title: 'Editar plan',
                      onPressed: () => editPlan(plan: plan),
                    ),
                    ModernSheetAction(
                      icon: CupertinoIcons.doc_on_doc,
                      title: 'Copiar al siguiente periodo',
                      onPressed: () => editPlan(plan: plan, copy: true),
                    ),
                    ModernSheetAction(
                      icon: CupertinoIcons.trash,
                      title: 'Eliminar plan',
                      destructive: true,
                      onPressed: () => app.confirmDelete(
                        context,
                        'Eliminar plan',
                        'Solo se elimina el plan de este periodo. Los movimientos se conservan.',
                        () => deleteBudgetPlan(app, plan['id'].toString()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      children: widgets,
    );
  }

  List<Widget> planWidgets(Map<String, dynamic> plan) {
    final app = widget.app, t = app.theme;
    final items = budgetPlanItems(app, plan['id'].toString());
    final limits = <String, double>{};
    double salary = 0, savings = 0;
    try {
      for (final item in items) {
        final category = item['category'].toString();
        limits[category] = moneyAdd(
          limits[category] ?? 0,
          budgetItemUsd(app, item),
        );
      }
      salary = budgetUsd(
        numberValue(plan['salary']),
        plan['currency'].toString(),
        app.rate,
        app.eurRate,
      );
      savings = budgetUsd(
        numberValue(plan['savings']),
        plan['currency'].toString(),
        app.rate,
        app.eurRate,
      );
    } on FormatException catch (error) {
      return [EmptyCard(theme: t, text: error.message)];
    }
    final spending = spendingCache.read(
      app,
      plan['period'].toString(),
      plan['periodType'].toString(),
      selectedCategories: limits.keys.toSet(),
    );
    final planned = limits.values.fold<double>(0, moneyAdd);
    final remaining = moneySubtract(planned, spending.total);
    final range = budgetPeriodDateRange(
      plan['period'].toString(),
      plan['periodType'].toString(),
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = range.last.difference(range.first).inDays + 1;
    final day = (today.difference(range.first).inDays + 1).clamp(0, days);
    final id = plan['id'].toString();
    final details = expandedPlan == id && expandedSection == 'details';
    final ranked = limits.keys.toList()
      ..sort(
        (a, b) => (spending.categories[b] ?? 0).compareTo(
          spending.categories[a] ?? 0,
        ),
      );
    return [
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: Text(
              formatDate(range.first) + ' - ' + formatDate(range.last),
              style: TextStyle(color: t.muted, fontSize: 11),
            ),
          ),
          Text(
            'D\u00eda $day de $days',
            style: TextStyle(color: t.muted, fontSize: 11),
          ),
        ],
      ),
      const SizedBox(height: 22),
      BudgetSummaryAmount(
        label: remaining < 0
            ? 'Presupuesto excedido'
            : 'Te queda en este periodo',
        value: app.secureMoney(remaining, 'USD'),
        theme: t,
        color: remaining < 0 ? t.red : t.ink,
        valueKey: const ValueKey('budget-remaining'),
      ),
      const SizedBox(height: 6),
      Text(
        'de ' + app.secureMoney(planned, 'USD'),
        style: TextStyle(color: t.muted, fontSize: 13),
      ),
      const SizedBox(height: 22),
      RatioBar(
        key: const ValueKey('budget-spending-bar'),
        theme: t,
        parts: [
          for (final category in ranked)
            RatioPart(
              color: budgetCategoryColor(category, t),
              value: math.max(0, spending.categories[category] ?? 0),
            ),
          if (remaining > 0) RatioPart(color: t.field, value: remaining),
          if (planned <= 0 && spending.total <= 0)
            RatioPart(color: t.field, value: 1),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: Text(
              'Gastado',
              style: TextStyle(color: t.muted, fontSize: 13),
            ),
          ),
          Text(
            app.secureMoney(spending.total, 'USD'),
            style: TextStyle(
              color: t.ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      if (spending.missingRates > 0)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            'Hay ' +
                spending.missingRates.toString() +
                ' gastos sin tasa; el total es parcial.',
            style: TextStyle(color: t.amber, fontSize: 12),
          ),
        ),
      SectionHeader(
        theme: t,
        title: 'Por categor\u00eda',
        action: 'Gestionar',
        onAction: () => editPlan(plan: plan, step: 2),
      ),
      if (items.isEmpty)
        EmptyCard(theme: t, text: 'No hay categor\u00edas en el plan'),
      for (final category in ranked)
        BudgetCategoryTile(
          app: app,
          category: category,
          limit: limits[category]!,
          spent: spending.categories[category] ?? 0,
          onTap: () => editPlan(plan: plan, step: 2),
        ),
      const SizedBox(height: 18),
      BudgetDisclosure(
        theme: t,
        title: 'Detalles del plan',
        expanded: details,
        onTap: () => setState(() {
          expandedPlan = id;
          expandedSection = details ? null : 'details';
        }),
      ),
      if (details) ...[
        DebtDetailRow(
          theme: t,
          label: 'Ingresos',
          value: plan['incomeMode'] == 'variable'
              ? 'Variables'
              : app.secureMoney(salary, 'USD'),
          fitValue: true,
        ),
        DebtDetailRow(
          theme: t,
          label: 'Ahorro previsto',
          value: app.secureMoney(savings, 'USD'),
          fitValue: true,
        ),
        if (plan['incomeMode'] != 'variable')
          DebtDetailRow(
            theme: t,
            label: 'Sin asignar',
            value: app.secureMoney(
              moneySubtract(moneySubtract(salary, savings), planned),
              'USD',
            ),
            fitValue: true,
          ),
      ],
    ];
  }

  void shiftMonth(int delta) {
    final value = adjacentBudgetMonth(
      widget.app.maps('budgetPlans'),
      month,
      delta,
    );
    if (value != null) setState(() => month = value);
  }

  void pickMonth() {
    final now = DateTime.now();
    final months = <String>{
      month,
      ...widget.app
          .maps('budgetPlans')
          .map((p) => p['period'].toString().substring(0, 7)),
      for (var i = 0; i <= 1; i++)
        budgetPeriodKeyFor(DateTime(now.year, now.month + i), 'monthly'),
    }.toList()..sort((a, b) => b.compareTo(a));
    showModernActionSheet(
      context,
      title: 'Seleccionar mes',
      actions: [
        for (final value in months)
          ModernSheetAction(
            icon: CupertinoIcons.calendar,
            title: monthLabelForKey(value),
            selected: value == month,
            onPressed: () => setState(() => month = value),
          ),
        ModernSheetAction(
          icon: CupertinoIcons.calendar_badge_plus,
          title: 'Elegir otro mes',
          onPressed: () => showModernDatePicker(
            context,
            theme: widget.app.theme,
            initial: DateTime.parse('$month-01'),
            minimumDate: DateTime(now.year, now.month),
            onSelected: (date) =>
                setState(() => month = budgetPeriodKeyFor(date, 'monthly')),
          ),
        ),
      ],
    );
  }
}

class BudgetSummaryAmount extends StatelessWidget {
  const BudgetSummaryAmount({
    super.key,
    required this.label,
    required this.value,
    required this.theme,
    required this.color,
    this.valueKey,
  });
  final String label, value;
  final RTheme theme;
  final Color color;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          color: theme.muted,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 4),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          key: valueKey,
          style: TextStyle(
            color: color,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );
}

class BudgetDisclosure extends StatelessWidget {
  const BudgetDisclosure({
    super.key,
    required this.theme,
    required this.title,
    required this.expanded,
    required this.onTap,
  });
  final RTheme theme;
  final String title;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: theme.border)),
    ),
    child: CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 16),
      onPressed: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: theme.ink,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            expanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
            color: theme.muted,
            size: 16,
          ),
        ],
      ),
    ),
  );
}

class BudgetCategoryTile extends StatelessWidget {
  const BudgetCategoryTile({
    super.key,
    required this.app,
    required this.category,
    required this.limit,
    required this.spent,
    required this.onTap,
  });
  final _RialAppState app;
  final String category;
  final double limit, spent;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = app.theme, color = budgetCategoryColor(category, app.theme);
    final ratio = limit > 0 ? spent / limit : 0.0;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: material.CircularProgressIndicator(
                      value: ratio.clamp(0, 1),
                      strokeWidth: 3,
                      color: spent > limit ? t.red : color,
                      backgroundColor: t.field,
                    ),
                  ),
                  Icon(categoryIcon(category), size: 19, color: color),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category,
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'de ' + app.secureMoney(limit, 'USD'),
                    style: TextStyle(color: t.muted, fontSize: 12),
                  ),
                  if (spent > limit)
                    Text(
                      'Excedido: ' +
                          app.secureMoney(moneySubtract(spent, limit), 'USD'),
                      style: TextStyle(color: t.red, fontSize: 11),
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
                    app.secureMoney(spent, 'USD'),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: spent > limit ? t.red : t.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    app.hideAmounts
                        ? '\u2022\u2022\u2022'
                        : (ratio * 100).round().toString() + '%',
                    style: TextStyle(
                      color: spent > limit ? t.red : color,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BudgetFormScaffold extends StatelessWidget {
  const BudgetFormScaffold({
    super.key,
    required this.app,
    required this.title,
    required this.children,
    required this.action,
  });
  final _RialAppState app;
  final String title;
  final List<Widget> children;
  final Widget action;
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: app.theme.bg,
    navigationBar: CupertinoNavigationBar(
      transitionBetweenRoutes: false,
      backgroundColor: app.theme.bg,
      border: null,
      middle: Text(title),
    ),
    child: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: children,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
            child: action,
          ),
        ],
      ),
    ),
  );
}

class BudgetPlanEditorPage extends StatefulWidget {
  const BudgetPlanEditorPage({
    super.key,
    required this.app,
    this.plan,
    this.copy = false,
    required this.initialPeriod,
    required this.initialType,
    this.initialStep = 0,
  });
  final _RialAppState app;
  final Map<String, dynamic>? plan;
  final bool copy;
  final String initialPeriod, initialType;
  final int initialStep;
  @override
  State<BudgetPlanEditorPage> createState() => _BudgetPlanEditorPageState();
}

class _BudgetPlanEditorPageState extends State<BudgetPlanEditorPage> {
  final savings = MoneyEditingController();
  final items = <Map<String, dynamic>>[];
  final incomes = <Map<String, dynamic>>[];
  late int step, half;
  late String month, type;
  String incomeMode = 'fixed';
  String? loadError;
  bool saving = false, created = false;
  bool get editing => widget.plan != null && !widget.copy;
  String get period => type == 'biweekly' ? '$month-H$half' : month;
  double get salary => incomeMode == 'variable'
      ? 0
      : incomes.fold<double>(
          0,
          (sum, item) => moneyAdd(sum, numberValue(item['amount'])),
        );
  @override
  void initState() {
    super.initState();
    step = widget.initialStep.clamp(0, 3);
    month = widget.initialPeriod.substring(0, 7);
    if (!editing && !canCreateBudgetInMonth(month)) month = currentMonthKey();
    half = widget.initialPeriod.endsWith('H2') ? 2 : 1;
    type = widget.initialType;
    final plan = widget.plan, app = widget.app;
    if (plan != null) {
      incomeMode = plan['incomeMode'] == 'variable' ? 'variable' : 'fixed';
      try {
        final currency = plan['currency']?.toString() ?? 'USD';
        savings.text = plain(
          budgetUsd(
            numberValue(plan['savings']),
            currency,
            app.rate,
            app.eurRate,
          ),
        );
        final sources = (plan['incomes'] as List? ?? []).whereType<Map>();
        if (sources.isEmpty && numberValue(plan['salary']) > 0) {
          incomes.add({
            'name': 'Salario',
            'amount': budgetUsd(
              numberValue(plan['salary']),
              currency,
              app.rate,
              app.eurRate,
            ),
          });
        } else {
          for (final source in sources)
            incomes.add({
              'name': source['name'].toString(),
              'amount': numberValue(source['amount']),
            });
        }
        final grouped = <String, double>{};
        for (final item in budgetPlanItems(app, plan['id'].toString())) {
          final category = item['category'].toString();
          grouped[category] = moneyAdd(
            grouped[category] ?? 0,
            budgetItemUsd(app, item),
          );
        }
        items.addAll(
          grouped.entries.map((e) => {'category': e.key, 'limit': e.value}),
        );
      } on FormatException catch (error) {
        loadError = error.message;
      }
    }
  }

  @override
  void dispose() {
    savings.dispose();
    super.dispose();
  }

  void notice(String message) =>
      showModernNotice(context, title: 'Revisa el plan', message: message);
  Future<void> selectIncomes() async {
    final result = await showGeneralDialog<List<Map<String, dynamic>>>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar ingresos',
      barrierColor: CupertinoColors.black.withOpacity(.5),
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      transitionBuilder: (context, a, _, child) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, .08),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
      pageBuilder: (context, _, __) =>
          BudgetIncomeSheet(theme: widget.app.theme, sources: incomes),
    );
    if (mounted && result != null)
      setState(() {
        incomes
          ..clear()
          ..addAll(result);
      });
  }

  Future<void> advance() async {
    if (saving || created) return;
    if (loadError != null) {
      notice(loadError!);
      return;
    }
    if (step == 0) {
      try {
        validateBudgetPlanPeriod(
          widget.app,
          period,
          type,
          editingId: editing ? widget.plan!['id'].toString() : null,
        );
      } on FormatException catch (error) {
        notice(error.message);
        return;
      }
      if (incomeMode == 'fixed' && (salary <= 0 || salary > 999999999999)) {
        notice('Agrega al menos un ingreso fijo mayor a cero.');
        return;
      }
    }
    final reserve = parseAmount(savings.text);
    if (step == 1 &&
        (!reserve.isFinite ||
            reserve < 0 ||
            reserve > 999999999999 ||
            (incomeMode == 'fixed' && reserve > salary))) {
      notice(
        'Revisa el ahorro. Con ingresos fijos no puede superar tus ingresos.',
      );
      return;
    }
    if (step == 2 && items.isEmpty) {
      notice('Selecciona al menos una categor\u00eda y su l\u00edmite.');
      return;
    }
    if (step < 3) {
      FocusScope.of(context).unfocus();
      setState(() => step++);
      return;
    }
    setState(() => saving = true);
    try {
      saveBudgetPlan(
        widget.app,
        period: period,
        type: type,
        salary: salary,
        savings: reserve,
        items: items,
        incomeMode: incomeMode,
        incomes: incomes,
        editingId: editing ? widget.plan!['id'].toString() : null,
      );
      await NativeStateStore.save(widget.app.state);
      if (!mounted) return;
      if (!MediaQuery.disableAnimationsOf(context))
        await Future<void>.delayed(const Duration(milliseconds: 450));
      if (mounted)
        setState(() {
          saving = false;
          created = true;
        });
    } on FormatException catch (error) {
      if (mounted) {
        setState(() => saving = false);
        notice(error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => saving = false);
        notice('No se pudo guardar el plan. Intenta nuevamente.');
      }
    }
  }

  Future<void> editCategory([int? index]) async {
    final result = await widget.app.pushPage<Map<String, dynamic>>(
      context,
      (_) => BudgetCategoryEditorPage(
        app: widget.app,
        item: index == null ? null : items[index],
        excluded: {
          for (var i = 0; i < items.length; i++)
            if (i != index) items[i]['category'].toString(),
        },
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (index == null) {
        items.add(result);
      } else {
        items[index] = result;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app, t = app.theme;
    if (saving || created) {
      return BudgetCreationStatus(
        theme: t,
        saving: saving,
        periodLabel: budgetPeriodLabel(period, type),
        onDone: () => Navigator.pop(context, budgetPlanId(period, type)),
      );
    }
    final planned = items.fold<double>(
      0,
      (sum, item) => moneyAdd(sum, numberValue(item['limit'])),
    );
    final free = moneySubtract(
      moneySubtract(salary, parseAmount(savings.text)),
      planned,
    );
    final spending = step == 2
        ? summarizeBudgetSpending(
            app.maps('movements'),
            period,
            type,
            usdRate: app.rate,
            eurRate: app.eurRate,
            selectedCategories: items
                .map((i) => i['category'].toString())
                .toSet(),
          )
        : null;
    return BudgetFormScaffold(
      app: app,
      title: editing ? 'Editar presupuesto' : 'Crear presupuesto',
      action: Row(
        children: [
          if (step > 0) ...[
            CircleTool(
              theme: t,
              icon: CupertinoIcons.arrow_left,
              label: 'Paso anterior',
              onTap: () => setState(() => step--),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: PrimaryActionButton(
              theme: t,
              label: step == 3 ? 'Confirmar presupuesto' : 'Continuar',
              onPressed: advance,
            ),
          ),
        ],
      ),
      children: [
        Semantics(
          label: 'Paso ' + (step + 1).toString() + ' de 4',
          child: Row(
            children: [
              for (var i = 0; i < 4; i++)
                Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i <= step ? t.accent : t.field,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          child: Align(
            key: ValueKey(step),
            alignment: Alignment.centerLeft,
            child: Text(
              [
                'Periodo e ingresos',
                '\u00bfCu\u00e1nto deseas ahorrar?',
                '\u00bfEn qu\u00e9 gastar\u00e1s?',
                'Resumen del presupuesto',
              ][step],
              style: TextStyle(
                color: t.ink,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (loadError != null) Text(loadError!, style: TextStyle(color: t.red)),
        if (step == 0) ...[
          if (editing)
            StaticField(
              theme: t,
              label: 'Periodo',
              value: type == 'monthly' ? 'Mensual' : 'Quincenal',
            )
          else ...[
            KindSelector(
              theme: t,
              value: type,
              items: const [
                KindSelectorItem(
                  value: 'monthly',
                  label: 'Mensual',
                  icon: CupertinoIcons.calendar,
                ),
                KindSelectorItem(
                  value: 'biweekly',
                  label: 'Quincenal',
                  icon: CupertinoIcons.calendar_badge_plus,
                ),
              ],
              onChanged: (v) => setState(() => type = v),
            ),
            OptionField(
              theme: t,
              label: 'Mes del plan',
              value: monthLabelForKey(month),
              icon: CupertinoIcons.calendar,
              onTap: () => showModernDatePicker(
                context,
                theme: t,
                initial: DateTime.parse('$month-01'),
                minimumDate: DateTime.parse(currentMonthKey() + '-01'),
                onSelected: (d) =>
                    setState(() => month = budgetPeriodKeyFor(d, 'monthly')),
              ),
            ),
            if (type == 'biweekly')
              KindSelector(
                theme: t,
                value: '$half',
                items: const [
                  KindSelectorItem(
                    value: '1',
                    label: '1 al 15',
                    icon: CupertinoIcons.calendar,
                  ),
                  KindSelectorItem(
                    value: '2',
                    label: '16 a fin de mes',
                    icon: CupertinoIcons.calendar,
                  ),
                ],
                onChanged: (v) => setState(() => half = int.parse(v)),
              ),
          ],
          Text(
            budgetPeriodLabel(period, type),
            key: const ValueKey('budget-plan-dates'),
            style: TextStyle(color: t.muted, fontSize: 12),
          ),
          const SizedBox(height: 26),
          Text(
            '\u00bfC\u00f3mo son tus ingresos?',
            style: TextStyle(
              color: t.ink,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          KindSelector(
            theme: t,
            value: incomeMode,
            items: const [
              KindSelectorItem(
                value: 'fixed',
                label: 'Fijos',
                icon: CupertinoIcons.creditcard,
              ),
              KindSelectorItem(
                value: 'variable',
                label: 'Variables',
                icon: CupertinoIcons.chart_bar,
              ),
            ],
            onChanged: (v) => setState(() => incomeMode = v),
          ),
          if (incomeMode == 'fixed')
            OptionField(
              theme: t,
              label: 'Ingresos del periodo',
              value: salary > 0
                  ? app.secureMoney(salary, 'USD')
                  : 'Seleccionar ingresos',
              icon: CupertinoIcons.money_dollar_circle,
              onTap: selectIncomes,
            ),
        ],
        if (step == 1) ...[
          RField(
            theme: t,
            controller: savings,
            placeholder: 'Ahorro previsto en USD',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          if (incomeMode == 'fixed')
            DebtDetailRow(
              theme: t,
              label: 'Ingresos',
              value: app.secureMoney(salary, 'USD'),
              fitValue: true,
            ),
        ],
        if (step == 2) ...[
          if (items.isNotEmpty)
            RingSummary(
              theme: t,
              parts: [
                for (final item in items)
                  RatioPart(
                    color: budgetCategoryColor(item['category'].toString(), t),
                    value: numberValue(item['limit']),
                  ),
              ],
              labels: [for (final item in items) item['category'].toString()],
              values: [
                for (final item in items)
                  app.secureMoney(numberValue(item['limit']), 'USD'),
              ],
              total: app.secureMoney(planned, 'USD'),
              label: 'Gastos planeados',
            ),
          if (incomeMode == 'fixed' && free < 0)
            Text(
              'Sobreasignado: ' + app.secureMoney(free.abs(), 'USD'),
              style: TextStyle(color: t.red, fontSize: 13),
            ),
          for (var i = 0; i < items.length; i++)
            Row(
              children: [
                Expanded(
                  child: BudgetCategoryTile(
                    app: app,
                    category: items[i]['category'].toString(),
                    limit: numberValue(items[i]['limit']),
                    spent: spending?.categories[items[i]['category']] ?? 0,
                    onTap: () => editCategory(i),
                  ),
                ),
                CircleTool(
                  theme: t,
                  icon: CupertinoIcons.xmark,
                  label: 'Quitar categor\u00eda',
                  onTap: () => setState(() => items.removeAt(i)),
                ),
              ],
            ),
          const SizedBox(height: 18),
          SecondaryActionButton(
            theme: t,
            label: items.isEmpty
                ? 'Seleccionar egresos'
                : 'Agregar categor\u00eda',
            onPressed: () => editCategory(),
          ),
        ],
        if (step == 3) ...[
          Text(
            budgetPeriodLabel(period, type),
            style: TextStyle(color: t.muted, fontSize: 12),
          ),
          const SizedBox(height: 18),
          BudgetSummaryAmount(
            label: 'Egresos planificados',
            value: app.secureMoney(planned, 'USD'),
            theme: t,
            color: t.ink,
          ),
          SectionHeader(theme: t, title: 'Distribuci\u00f3n de egresos'),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    categoryIcon(item['category'].toString()),
                    color: budgetCategoryColor(item['category'].toString(), t),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item['category'].toString(),
                      style: TextStyle(color: t.ink, fontSize: 14),
                    ),
                  ),
                  Text(
                    app.secureMoney(numberValue(item['limit']), 'USD'),
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          SectionHeader(theme: t, title: 'Balance'),
          DebtDetailRow(
            theme: t,
            label: 'Ingresos',
            value: incomeMode == 'variable'
                ? 'Variables'
                : app.secureMoney(salary, 'USD'),
            fitValue: true,
          ),
          DebtDetailRow(
            theme: t,
            label: 'Ahorro',
            value: app.secureMoney(parseAmount(savings.text), 'USD'),
            fitValue: true,
          ),
          DebtDetailRow(
            theme: t,
            label: 'Egresos',
            value: app.secureMoney(planned, 'USD'),
            fitValue: true,
          ),
          if (incomeMode == 'fixed')
            DebtDetailRow(
              theme: t,
              label: 'Saldo libre',
              value: app.secureMoney(free, 'USD'),
              valueColor: free < 0 ? t.red : t.green,
              fitValue: true,
            ),
        ],
      ],
    );
  }
}

class BudgetIncomeSheet extends StatefulWidget {
  const BudgetIncomeSheet({
    super.key,
    required this.theme,
    required this.sources,
  });
  final RTheme theme;
  final List<Map<String, dynamic>> sources;
  @override
  State<BudgetIncomeSheet> createState() => _BudgetIncomeSheetState();
}

class _BudgetIncomeSheetState extends State<BudgetIncomeSheet> {
  final names = <TextEditingController>[], amounts = <MoneyEditingController>[];
  @override
  void initState() {
    super.initState();
    for (final item in widget.sources)
      add(item['name'].toString(), numberValue(item['amount']));
    if (names.isEmpty) {
      add('Salario', 0);
      add('Otros ingresos', 0);
    }
  }

  void add(String name, double amount) {
    names.add(TextEditingController(text: name));
    amounts.add(
      MoneyEditingController()..text = amount > 0 ? plain(amount) : '',
    );
  }

  @override
  void dispose() {
    for (final c in names) c.dispose();
    for (final c in amounts) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme, media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: math.max(
                160,
                media.size.height * .78 - media.viewInsets.bottom,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(color: t.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    CircleTool(
                      theme: t,
                      icon: CupertinoIcons.xmark,
                      label: 'Cancelar',
                      onTap: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        'Ingresos',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: t.ink,
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    CircleTool(
                      theme: t,
                      icon: CupertinoIcons.checkmark,
                      label: 'Confirmar ingresos',
                      onTap: () {
                        final result = <Map<String, dynamic>>[];
                        for (var i = 0; i < names.length; i++) {
                          final amount = parseAmount(amounts[i].text);
                          if (amounts[i].text.trim().isEmpty || amount == 0)
                            continue;
                          if (!amount.isFinite ||
                              amount < 0 ||
                              amount > 999999999999 ||
                              names[i].text.trim().isEmpty) {
                            showModernNotice(
                              context,
                              title: 'Revisa el ingreso',
                              message:
                                  'Escribe un nombre y un monto v\u00e1lido.',
                            );
                            return;
                          }
                          result.add({
                            'name': names[i].text.trim(),
                            'amount': moneyRound(amount),
                          });
                        }
                        Navigator.pop(context, result);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (var i = 0; i < names.length; i++) ...[
                        RField(
                          theme: t,
                          controller: names[i],
                          placeholder: 'Nombre del ingreso',
                        ),
                        RField(
                          theme: t,
                          controller: amounts[i],
                          placeholder: 'Monto en USD',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SecondaryActionButton(
                        theme: t,
                        label: 'Agregar ingreso',
                        onPressed: () => setState(() => add('', 0)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BudgetCategoryEditorPage extends StatefulWidget {
  const BudgetCategoryEditorPage({
    super.key,
    required this.app,
    required this.excluded,
    this.item,
  });
  final _RialAppState app;
  final Set<String> excluded;
  final Map<String, dynamic>? item;
  @override
  State<BudgetCategoryEditorPage> createState() =>
      _BudgetCategoryEditorPageState();
}

class _BudgetCategoryEditorPageState extends State<BudgetCategoryEditorPage> {
  final amount = MoneyEditingController();
  late String category;
  @override
  void initState() {
    super.initState();
    category = widget.item?['category']?.toString() ?? 'Otro';
    if (widget.excluded.contains(category))
      category =
          budgetCategories
              .where((c) => !widget.excluded.contains(c))
              .firstOrNull ??
          '';
    if (widget.item != null)
      amount.text = plain(numberValue(widget.item!['limit']));
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BudgetFormScaffold(
    app: widget.app,
    title: 'Categor\u00eda del plan',
    children: [
      OptionField(
        theme: widget.app.theme,
        label: 'Categor\u00eda',
        value: category.isEmpty ? 'Sin categor\u00edas disponibles' : category,
        icon: categoryIcon(category),
        onTap: () => showModernActionSheet(
          context,
          title: 'Categor\u00eda',
          actions: [
            for (final value in budgetCategories.where(
              (c) => !widget.excluded.contains(c),
            ))
              ModernSheetAction(
                icon: categoryIcon(value),
                title: value,
                selected: value == category,
                onPressed: () => setState(() => category = value),
              ),
          ],
        ),
      ),
      RField(
        theme: widget.app.theme,
        controller: amount,
        placeholder: 'L\u00edmite del periodo en USD',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      ),
    ],
    action: PrimaryActionButton(
      theme: widget.app.theme,
      label: 'Guardar categor\u00eda',
      onPressed: () {
        final value = parseAmount(amount.text);
        if (category.isEmpty ||
            widget.excluded.contains(category) ||
            !value.isFinite ||
            value <= 0 ||
            value > 999999999999) {
          showModernNotice(
            context,
            title: 'Revisa la categor\u00eda',
            message:
                'Selecciona una categoria disponible y un monto mayor a cero.',
          );
          return;
        }
        Navigator.pop(context, <String, dynamic>{
          'category': category,
          'limit': moneyRound(value),
        });
      },
    ),
  );
}

class BudgetCreationStatus extends StatelessWidget {
  const BudgetCreationStatus({
    super.key,
    required this.theme,
    required this.saving,
    required this.periodLabel,
    required this.onDone,
  });

  final RTheme theme;
  final bool saving;
  final String periodLabel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: CupertinoPageScaffold(
      backgroundColor: theme.bg,
      child: SafeArea(
        child: SizedBox.expand(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: SizedBox(
                            key: const ValueKey('budget-status-symbol'),
                            width: 90,
                            height: 90,
                            child: AnimatedSwitcher(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 250),
                              child: saving
                                  ? Center(
                                      key: const ValueKey(
                                        'budget-creating-spinner',
                                      ),
                                      child: RialLoadingIndicator(
                                        size: 50,
                                        color: theme.accent,
                                        semanticsLabel: 'Creando presupuesto',
                                      ),
                                    )
                                  : Container(
                                      key: const ValueKey(
                                        'budget-created-icon',
                                      ),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: theme.accent.withValues(
                                          alpha: .14,
                                        ),
                                      ),
                                      child: Icon(
                                        CupertinoIcons.checkmark,
                                        size: 42,
                                        color: theme.accent,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          height: 76,
                          child: Center(
                            child: Text(
                              saving
                                  ? 'Creando presupuesto...'
                                  : '\u00a1Presupuesto creado!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: theme.ink,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 44,
                          child: Center(
                            child: Text(
                              saving ? '' : periodLabel,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: theme.muted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: 60,
                  child: saving
                      ? const SizedBox.shrink()
                      : PrimaryActionButton(
                          theme: theme,
                          label: 'Ir a presupuestos',
                          onPressed: onDone,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
