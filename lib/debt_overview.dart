part of 'main.dart';

List<DateTime> debtCalendarDates(Map<String, dynamic> debt) {
  if (debt['hasDueDate'] == false) return const [];
  final remaining = debtInstallmentRemainingAmounts(debt);
  final installments = debtHasInstallments(debt);
  final dates = installments
      ? debtScheduleDates(debt)
      : [displayDateOnly(debt['dueDate']?.toString())];
  return [
    for (var i = 0; i < dates.length; i++)
      if (dates[i].isNotEmpty &&
          (!installments ||
              debtIsPaid(debt) ||
              (i < remaining.length && remaining[i] > 0)))
        parseDateOnly(dates[i]),
  ].where((date) => date.year != 9999).toList();
}

class DebtProgressCard extends StatelessWidget {
  const DebtProgressCard({
    super.key,
    required this.app,
    required this.debt,
    this.interactive = true,
  });
  final _RialAppState app;
  final Map<String, dynamic> debt;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final total = numberValue(debt['amount']);
    final remaining = debtRemainingAmount(debt);
    final paid = moneySubtract(
      total,
      remaining,
    ).clamp(0.0, math.max(0.0, total));
    final complete = debtIsPaid(debt);
    final receivable = debt['kind'] == 'receivable';
    final currency = debt['currency']?.toString() ?? 'USD';
    final creditor = debt['creditor']?.toString().trim() ?? '';
    final party = debt['partyType']?.toString() ?? creditor;
    final logo = debt['partyLogo']?.toString() ?? debtPartyLogoCode(party);
    final date = displayDateOnly(debtUpcomingDate(debt));
    final progress = total > 0 ? (paid / total).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PressFeedback(
        onTap: interactive ? () => app.openDebtDetail(context, debt) : null,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (logo != null && logo.isNotEmpty)
                    LogoBadge(provider: logo, theme: t, size: 32)
                  else
                    Icon(
                      debtPartyIcon(
                        party,
                        receivable ? 'receivable' : 'payable',
                      ),
                      color: t.accent,
                      size: 26,
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedDebtLabel(debt),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          [
                            if (creditor.isNotEmpty) creditor,
                            receivable ? 'Por cobrar' : 'Por pagar',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: t.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (interactive) ...[
                    const SizedBox(width: 8),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 13,
                      color: t.muted,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${receivable ? 'Cobrado' : 'Pagado'} ${app.secureMoney(paid.toDouble(), currency)} de ${app.secureMoney(total, currency)}',
                      key: ValueKey('debt-progress-label-${debt['id']}'),
                      style: TextStyle(color: t.muted, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    app.hideAmounts ? '•••' : '${(progress * 100).round()}%',
                    style: TextStyle(
                      color: t.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TweenAnimationBuilder<double>(
                tween: Tween(end: app.hideAmounts ? 0 : progress),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                builder: (_, value, __) => ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: ExcludeSemantics(
                    excluding: app.hideAmounts,
                    child: material.LinearProgressIndicator(
                      key: ValueKey('debt-progress-${debt['id']}'),
                      value: app.hideAmounts ? 0 : value,
                      minHeight: 4,
                      color: t.accent,
                      backgroundColor: t.field,
                      semanticsLabel: receivable
                          ? 'Avance del cobro'
                          : 'Avance del pago',
                      semanticsValue: app.hideAmounts
                          ? null
                          : '${(progress * 100).round()}%',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Text(
                    complete
                        ? 'Pagado'
                        : 'Pendiente ${app.secureMoney(remaining, currency)}',
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!complete)
                    Text(
                      date.isEmpty
                          ? 'Sin fecha'
                          : '${debtHasInstallments(debt) ? 'Cuota' : 'Vence'} $date${debtHasInstallments(debt) ? ' · ${app.secureMoney(debtNextPaymentAmount(debt), currency)}' : ''}',
                      style: TextStyle(color: t.muted, fontSize: 11),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DebtSettlementChart extends StatelessWidget {
  const DebtSettlementChart({super.key, required this.app, required this.debt});
  final _RialAppState app;
  final Map<String, dynamic> debt;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final total = numberValue(debt['amount']);
    final remaining = debtRemainingAmount(debt);
    final paid = moneySubtract(
      total,
      remaining,
    ).clamp(0.0, math.max(0.0, total)).toDouble();
    final progress = total > 0 ? (paid / total).clamp(0.0, 1.0) : 0.0;
    final currency = debt['currency']?.toString() ?? 'USD';
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final chartSize = largeText ? 160.0 : 120.0;
    final chart = SizedBox(
      width: chartSize,
      height: chartSize,
      child: Semantics(
        label: 'Progreso de la deuda',
        value: app.hideAmounts
            ? 'Oculto'
            : '${(progress * 100).round()}% completado',
        child: Stack(
          alignment: Alignment.center,
          children: [
            ExcludeSemantics(
              child: charts.PieChart(
                charts.PieChartData(
                  startDegreeOffset: -90,
                  centerSpaceRadius: (chartSize - 28) / 2,
                  sectionsSpace: 2,
                  pieTouchData: charts.PieTouchData(enabled: false),
                  sections: [
                    if (!app.hideAmounts && paid > 0)
                      charts.PieChartSectionData(
                        value: paid,
                        color: t.accent,
                        radius: 12,
                        showTitle: false,
                      ),
                    if (app.hideAmounts || remaining > 0 || total <= 0)
                      charts.PieChartSectionData(
                        value: app.hideAmounts || total <= 0 ? 1 : remaining,
                        color: t.field,
                        radius: 12,
                        showTitle: false,
                      ),
                  ],
                ),
                key: ValueKey(app.hideAmounts),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  app.hideAmounts ? '•••' : '${(progress * 100).round()}%',
                  key: const ValueKey('debt-percentage'),
                  style: TextStyle(
                    color: t.ink,
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Completado',
                  style: TextStyle(color: t.muted, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final amounts = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _amount(
          t,
          debt['kind'] == 'receivable' ? 'Cobrado' : 'Pagado',
          paid,
          currency,
          t.accent,
        ),
        const SizedBox(height: 8),
        _amount(t, 'Pendiente', remaining, currency, t.ink),
        const SizedBox(height: 8),
        _amount(t, 'Total', total, currency, t.muted),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: LayoutBuilder(
        builder: (_, size) => size.maxWidth < 260 || largeText
            ? Column(children: [chart, const SizedBox(height: 16), amounts])
            : Row(
                children: [
                  chart,
                  const SizedBox(width: 20),
                  Expanded(child: amounts),
                ],
              ),
      ),
    );
  }

  Widget _amount(
    RTheme t,
    String label,
    double amount,
    String currency,
    Color color,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(color: t.muted, fontSize: 11)),
      Text(
        app.secureMoney(amount, currency),
        style: TextStyle(
          color: color,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class DebtOverview extends StatefulWidget {
  const DebtOverview({super.key, required this.app});
  final _RialAppState app;
  @override
  State<DebtOverview> createState() => _DebtOverviewState();
}

class _DebtOverviewState extends State<DebtOverview> {
  bool paid = false;
  bool calendar = true;
  String kind = 'all';
  bool undated = false;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  int? day;

  void createDebt() =>
      showQuickActionMenu(context, app: widget.app, debtsOnly: true);

  List<Map<String, dynamic>> get filtered =>
      widget.app
          .maps('debts')
          .where(
            (debt) =>
                debtIsPaid(debt) == paid &&
                (kind == 'all' || debt['kind'] == kind) &&
                (!undated || debtUpcomingDate(debt).isEmpty),
          )
          .toList()
        ..sort((a, b) {
          final ad = debtUpcomingDate(a), bd = debtUpcomingDate(b);
          if (ad.isEmpty != bd.isEmpty) return ad.isEmpty ? 1 : -1;
          return parseMovementDate(ad).compareTo(parseMovementDate(bd));
        });

  bool inMonth(Map<String, dynamic> debt, {int? selectedDay}) =>
      debtCalendarDates(debt).any(
        (parsed) =>
            parsed.year == month.year &&
            parsed.month == month.month &&
            (selectedDay == null || parsed.day == selectedDay),
      );

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = app.theme;
    final debts = filtered;
    // Browsing the calendar must not hide overdue or undated debts.
    final visible = calendar && day != null
        ? debts.where((debt) => inMonth(debt, selectedDay: day)).toList()
        : debts;
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        border: null,
        backgroundColor: t.bg,
        middle: const Text('Por cobrar / pagar'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: createDebt,
          child: Icon(
            CupertinoIcons.add,
            color: t.accent,
            semanticLabel: 'Nuevo registro',
          ),
        ),
      ),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppPillSelector(
                      key: const ValueKey('debt-status-selector'),
                      theme: t,
                      value: paid ? 'paid' : 'pending',
                      items: const [
                        KindSelectorItem(
                          value: 'pending',
                          label: 'No pagados',
                          icon: CupertinoIcons.clock,
                        ),
                        KindSelectorItem(
                          value: 'paid',
                          label: 'Pagados',
                          icon: CupertinoIcons.check_mark,
                        ),
                      ],
                      onChanged: (value) => setState(() {
                        paid = value == 'paid';
                        day = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _summary(
                              t,
                              'payable',
                              'Por pagar',
                              CupertinoIcons.arrow_down,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _summary(
                              t,
                              'receivable',
                              'Por cobrar',
                              CupertinoIcons.arrow_up,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          onPressed: () => setState(() {
                            undated = !undated;
                            day = null;
                            if (undated) calendar = false;
                          }),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                undated
                                    ? CupertinoIcons.checkmark_circle_fill
                                    : CupertinoIcons.circle,
                                size: 17,
                                color: t.accent,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Sin fecha',
                                style: TextStyle(color: t.muted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (kind != 'all')
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            onPressed: () => setState(() => kind = 'all'),
                            child: Text(
                              'Todos',
                              style: TextStyle(color: t.accent, fontSize: 12),
                            ),
                          ),
                        CupertinoButton(
                          key: const ValueKey('debt-calendar-toggle'),
                          padding: const EdgeInsets.all(10),
                          onPressed: () => setState(() {
                            calendar = !calendar;
                            day = null;
                            undated = false;
                          }),
                          child: Icon(
                            calendar
                                ? CupertinoIcons.list_bullet
                                : CupertinoIcons.calendar,
                            size: 20,
                            color: t.accent,
                            semanticLabel: calendar
                                ? 'Ver lista'
                                : 'Ver calendario',
                          ),
                        ),
                      ],
                    ),
                    AnimatedSize(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: calendar
                          ? _calendar(t, debts)
                          : const SizedBox.shrink(),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        '${visible.length} ${visible.length == 1 ? 'registro' : 'registros'}${day == null ? '' : ' · $day/${month.month}'}',
                        style: TextStyle(color: t.muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (visible.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: EmptyCard(
                    theme: t,
                    text: day != null
                        ? 'No hay vencimientos este día'
                        : paid
                        ? 'Aún no hay pagos o cobros completados'
                        : 'No tienes pagos ni cobros pendientes',
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (_, index) => DebtProgressCard(
                    key: ValueKey(visible[index]['id']),
                    app: app,
                    debt: visible[index],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summary(RTheme t, String value, String label, IconData icon) {
    final debts = widget.app
        .maps('debts')
        .where((d) => debtIsPaid(d) == paid && d['kind'] == value)
        .toList();
    final currencies = [
      'VES',
      'USD',
      'EUR',
      'USDT',
    ].where((c) => debts.any((d) => d['currency'] == c)).toList();
    return PressFeedback(
      onTap: () => setState(() {
        kind = kind == value ? 'all' : value;
        day = null;
      }),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kind == value ? t.accent.withValues(alpha: .13) : t.card,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.accent.withValues(alpha: .14),
                  ),
                  child: Icon(icon, color: t.accent, size: 15),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(color: t.muted, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (currencies.isEmpty)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.app.secureMoney(0, 'USD'),
                  style: TextStyle(
                    color: t.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            for (final currency in currencies)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.app.secureMoney(
                    debts
                        .where((d) => d['currency'] == currency)
                        .fold<double>(
                          0,
                          (sum, d) => moneyAdd(
                            sum,
                            paid
                                ? numberValue(d['amount'])
                                : debtRemainingAmount(d),
                          ),
                        ),
                    currency,
                  ),
                  style: TextStyle(
                    color: t.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _calendar(RTheme t, List<Map<String, dynamic>> debts) {
    const months = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    final offset = month.weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final today = DateTime.now();
    final byDay = <int, List<String>>{};
    for (final debt in debts) {
      for (final date in debtCalendarDates(debt)) {
        if (date.year == month.year && date.month == month.month) {
          (byDay[date.day] ??= []).add(debt['kind']?.toString() ?? 'payable');
        }
      }
    }
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            children: [
              CupertinoButton(
                padding: const EdgeInsets.all(10),
                onPressed: () => setState(() {
                  month = DateTime(month.year, month.month - 1);
                  day = null;
                }),
                child: Icon(
                  CupertinoIcons.chevron_left,
                  color: t.accent,
                  semanticLabel: 'Mes anterior',
                ),
              ),
              Expanded(
                child: Text(
                  '${months[month.month - 1]} ${month.year}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.all(10),
                onPressed: () => setState(() {
                  month = DateTime(month.year, month.month + 1);
                  day = null;
                }),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  color: t.accent,
                  semanticLabel: 'Mes siguiente',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final label in ['L', 'M', 'M', 'J', 'V', 'S', 'D'])
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.muted, fontSize: 12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var row = 0; row < ((days + offset) / 7).ceil(); row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: _calendarDay(
                    t,
                    byDay,
                    row * 7 + col - offset + 1,
                    days,
                    today,
                  ),
                ),
            ],
          ),
        if (day != null)
          CupertinoButton(
            onPressed: () => setState(() => day = null),
            child: const Text('Todos los registros'),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _calendarDay(
    RTheme t,
    Map<int, List<String>> byDay,
    int number,
    int days,
    DateTime today,
  ) {
    if (number < 1 || number > days) return const SizedBox(height: 44);
    final matches = byDay[number] ?? const <String>[];
    final isToday =
        today.year == month.year &&
        today.month == month.month &&
        today.day == number;
    return Semantics(
      label:
          '$number/${month.month}/${month.year}, ${matches.length} vencimientos',
      selected: day == number,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => setState(() => day = day == number ? null : number),
        child: Container(
          height: 40,
          width: 40,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: day == number ? t.accent.withValues(alpha: .18) : null,
            shape: BoxShape.circle,
            border: isToday ? Border.all(color: t.accent) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$number',
                style: TextStyle(
                  color: t.ink,
                  fontSize: 14,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final kind in ['payable', 'receivable'])
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: matches.contains(kind)
                            ? (kind == 'payable' ? t.accent : t.income)
                            : const Color(0x00000000),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
