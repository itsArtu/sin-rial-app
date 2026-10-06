part of 'main.dart';

const recurringFrequencies = {
  'weekly': 'Semanal',
  'fortnightly': 'Cada 15 d\u00edas',
  'monthly': 'Mensual',
};

String recurringDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

DateTime? recurringParseDate(Object? value) {
  final text = value?.toString() ?? '';
  final parsed = DateTime.tryParse(text);
  return parsed != null && recurringDateKey(parsed) == text ? parsed : null;
}

DateTime recurringDateAt(Map<String, dynamic> rule, int index) {
  final start = recurringParseDate(rule['startDate'])!;
  if (rule['frequency'] == 'monthly') {
    final month = DateTime(start.year, start.month + index);
    final last = DateTime(month.year, month.month + 1, 0).day;
    return DateTime(month.year, month.month, math.min(start.day, last));
  }
  return DateTime(
    start.year,
    start.month,
    start.day + index * (rule['frequency'] == 'weekly' ? 7 : 15),
  );
}

Set<String> recurringResolvedDates(
  Map<String, dynamic> rule,
  List<Map<String, dynamic>> movements,
) => {
  ...(rule['skippedDates'] as List? ?? []).whereType<String>(),
  for (final movement in movements)
    if (movement['recurringId'] == rule['id'] &&
        movement['recurringDate'] is String)
      movement['recurringDate'] as String,
};

DateTime? nextRecurringDate(
  Map<String, dynamic> rule,
  List<Map<String, dynamic>> movements,
) {
  if (rule['archived'] == true ||
      rule['paused'] == true ||
      recurringParseDate(rule['startDate']) == null ||
      !recurringFrequencies.containsKey(rule['frequency']))
    return null;
  final resolved = recurringResolvedDates(rule, movements);
  // At most one more candidate than the number of resolved dates is needed.
  for (var i = 0; i <= resolved.length; i++) {
    final date = recurringDateAt(rule, i);
    if (!resolved.contains(recurringDateKey(date))) return date;
  }
  return null;
}

List<Map<String, dynamic>> recurringPendingItems(
  _RialAppState app, {
  DateTime? now,
}) {
  final today = recurringDateKey(now ?? DateTime.now());
  final rules = app
      .maps('recurringMovements')
      .where((r) => r['archived'] != true && r['paused'] != true)
      .toList();
  if (rules.isEmpty) return [];
  final movements = app.maps('movements');
  final items = <Map<String, dynamic>>[];
  for (final rule in rules) {
    final due = nextRecurringDate(rule, movements);
    if (due != null && recurringDateKey(due).compareTo(today) <= 0) {
      items.add({...rule, 'pendingDate': recurringDateKey(due)});
    }
  }
  items.sort(
    (a, b) =>
        a['pendingDate'].toString().compareTo(b['pendingDate'].toString()),
  );
  return items;
}

void validateRecurringMovement(
  _RialAppState app,
  Map<String, dynamic> movement,
  Map<String, dynamic>? previous,
) {
  // Editing a registered movement must retain its occurrence identity.
  if (previous?['recurringId'] != null) {
    movement['recurringId'] = previous!['recurringId'];
    movement['recurringDate'] = previous['recurringDate'];
    if (movement['type'] != previous['type']) {
      throw const FormatException(
        'Un recurrente registrado conserva su tipo de movimiento',
      );
    }
  }
  final id = movement['recurringId']?.toString() ?? '';
  if (id.isEmpty) return;
  final key = movement['recurringDate']?.toString() ?? '';
  if (app
      .maps('movements')
      .any(
        (item) =>
            item['id'] != previous?['id'] &&
            item['recurringId'] == id &&
            item['recurringDate'] == key,
      )) {
    throw const FormatException('Esta fecha ya fue registrada');
  }
  if (previous?['recurringId'] == id) return;
  final rule = app
      .maps('recurringMovements')
      .where((r) => r['id'] == id)
      .firstOrNull;
  final due = rule == null
      ? null
      : nextRecurringDate(rule, app.maps('movements'));
  if (due == null ||
      recurringDateKey(due) != key ||
      key.compareTo(recurringDateKey(DateTime.now())) > 0) {
    throw const FormatException('Esta fecha ya no est\u00e1 pendiente');
  }
  if (movement['type'] != rule!['type'] ||
      movement['currency'] != rule['currency']) {
    throw const FormatException('Conserva el tipo y la moneda del recurrente');
  }
}

void saveRecurringRule(
  _RialAppState app,
  Map<String, dynamic> input, {
  String? editingId,
}) {
  final old = app
      .maps('recurringMovements')
      .where((r) => r['id'] == editingId)
      .firstOrNull;
  if (editingId != null && old == null)
    throw const FormatException('El recurrente ya no existe');
  final name = input['name']?.toString().trim() ?? '';
  final amount = numberValue(input['amount']);
  final account = app.accountById(input['accountId']?.toString() ?? '');
  if (name.isEmpty ||
      name.length > 80 ||
      !amount.isFinite ||
      moneyRound(amount) <= 0 ||
      amount > 999999999999 ||
      account == null ||
      !['income', 'expense'].contains(input['type']) ||
      !recurringFrequencies.containsKey(input['frequency']) ||
      recurringParseDate(input['startDate']) == null) {
    throw const FormatException(
      'Revisa el nombre, monto, cuenta, fecha y frecuencia',
    );
  }
  if (old != null &&
      recurringResolvedDates(old, app.maps('movements')).isNotEmpty &&
      (old['startDate'] != input['startDate'] ||
          old['frequency'] != input['frequency'] ||
          old['type'] != input['type'] ||
          old['currency'] != account['currency'])) {
    throw const FormatException(
      'Crea otro recurrente para cambiar el calendario, tipo o moneda de uno con historial',
    );
  }
  if (app
      .maps('recurringMovements')
      .any(
        (r) =>
            r['id'] != editingId &&
            r['archived'] != true &&
            _categorySearchText(r['name'].toString()) ==
                _categorySearchText(name) &&
            r['accountId'] == input['accountId'] &&
            r['type'] == input['type'],
      )) {
    throw const FormatException('Ya existe este recurrente en esa cuenta');
  }
  final entry = <String, dynamic>{
    ...?old,
    ...input,
    'id': editingId ?? app.id(),
    'name': name,
    'currency': account['currency'],
    'amount': moneyRound(amount),
    'category': input['type'] == 'expense'
        ? canonicalCategory(input['category']?.toString() ?? 'Otro')
        : '',
    'skippedDates': old?['skippedDates'] ?? <String>[],
  };
  app.undoableMutation(
    'Recurrente guardado',
    {
      'recurringMovements': {entry['id'].toString()},
    },
    () {
      final list = app.rawList('recurringMovements');
      final index = list.indexWhere((r) => r is Map && r['id'] == editingId);
      if (index < 0) {
        list.add(entry);
      } else {
        list[index] = entry;
      }
    },
  );
}

void skipRecurringDate(_RialAppState app, String id, String date) {
  final rule = app
      .maps('recurringMovements')
      .where((r) => r['id'] == id)
      .firstOrNull;
  final due = rule == null
      ? null
      : nextRecurringDate(rule, app.maps('movements'));
  if (due == null ||
      recurringDateKey(due) != date ||
      date.compareTo(recurringDateKey(DateTime.now())) > 0)
    return;
  app.undoableMutation(
    'Fecha omitida',
    {
      'recurringMovements': {id},
    },
    () {
      rule!['skippedDates'] = [...(rule['skippedDates'] as List? ?? []), date];
    },
  );
}

void openRecurringMovement(
  BuildContext context,
  _RialAppState app,
  Map<String, dynamic> rule,
  String date,
) {
  if (app.accountById(rule['accountId'].toString()) == null) {
    showModernNotice(
      context,
      title: 'Cuenta no disponible',
      message:
          'Edita el recurrente y selecciona otra cuenta antes de registrarlo.',
    );
    return;
  }
  final due = recurringParseDate(date)!;
  final now = DateTime.now();
  app.openMovementEditor(
    context,
    defaultType: rule['type'].toString(),
    defaultAccountId: rule['accountId'].toString(),
    defaultCategory: rule['category']?.toString(),
    defaultDescription: rule['name'].toString(),
    defaultAmount: numberValue(rule['amount']),
    defaultDate: formatDateTime(
      DateTime(due.year, due.month, due.day, now.hour, now.minute),
    ),
    recurringId: rule['id'].toString(),
    recurringDate: date,
  );
}

void recurringActions(
  BuildContext context,
  _RialAppState app,
  Map<String, dynamic> rule,
  String date,
) {
  showModernActionSheet(
    context,
    title: rule['name'].toString(),
    actions: [
      ModernSheetAction(
        title: 'Revisar y registrar',
        icon: CupertinoIcons.check_mark_circled,
        onPressed: () => openRecurringMovement(context, app, rule, date),
      ),
      ModernSheetAction(
        title: 'Ya lo registr\u00e9',
        icon: CupertinoIcons.link,
        onPressed: () => linkRecurringMovement(context, app, rule, date),
      ),
      ModernSheetAction(
        title: 'Saltar esta fecha',
        icon: CupertinoIcons.forward,
        onPressed: () => showModernConfirm(
          context,
          title: 'Saltar ${displayDateOnly(date)}',
          message: rule['name'].toString(),
          destructiveText: 'Saltar fecha',
          onConfirm: () => skipRecurringDate(app, rule['id'].toString(), date),
        ),
      ),
    ],
  );
}

void linkRecurringMovement(
  BuildContext context,
  _RialAppState app,
  Map<String, dynamic> rule,
  String date,
) {
  final start = recurringParseDate(date)!;
  final candidates = sortedMovements(app.maps('movements'))
      .where(
        (m) =>
            m['type'] == rule['type'] &&
            m['currency'] == rule['currency'] &&
            (m['recurringId']?.toString() ?? '').isEmpty &&
            recurringDateKey(parseMovementDate(m['date']?.toString()))
                    .compareTo(recurringDateKey(start)) >=
                0,
      )
      .toList();
  if (candidates.isEmpty) {
    showModernNotice(
      context,
      title: 'Sin movimientos compatibles',
      message: 'No hay movimientos sin vincular de este tipo y moneda desde esa fecha.',
    );
    return;
  }
  showModernActionSheet(
    context,
    title: 'Movimiento ya registrado',
    actions: [
      for (final m in candidates)
        ModernSheetAction(
          title: m['description']?.toString().isNotEmpty == true
              ? m['description'].toString()
              : 'Movimiento',
          subtitle:
              '${displayDateOnly(m['date']?.toString())} · ${app.secureMoney(numberValue(m['amount']), m['currency'].toString())}',
          icon: CupertinoIcons.link,
          onPressed: () => showModernConfirm(
            context,
            title: 'Vincular movimiento',
            message: '${rule['name']} · ${displayDateOnly(date)}',
            destructiveText: 'Vincular',
            onConfirm: () {
              try {
                final current = app.movementById(m['id'].toString());
                if (current == null ||
                    (current['recurringId']?.toString() ?? '').isNotEmpty)
                  return;
                app.saveMovement({
                  ...current,
                  'recurringId': rule['id'],
                  'recurringDate': date,
                }, editingId: m['id'].toString());
              } on FormatException catch (e) {
                showModernNotice(
                  context,
                  title: 'Recurrente',
                  message: e.message,
                );
              }
            },
          ),
        ),
    ],
  );
}

class RecurringPendingSection extends StatelessWidget {
  const RecurringPendingSection({super.key, required this.app});
  final _RialAppState app;
  @override
  Widget build(BuildContext context) {
    final items = recurringPendingItems(app);
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          theme: app.theme,
          title: 'Por confirmar',
          action: 'Ver todo',
          onAction: () =>
              app.pushPage(context, (_) => RecurringMovementsPage(app: app)),
        ),
        for (final item in items.take(3))
          RecurringTile(
            app: app,
            rule: item,
            date: item['pendingDate'].toString(),
            onTap: () => recurringActions(
              context,
              app,
              item,
              item['pendingDate'].toString(),
            ),
          ),
      ],
    );
  }
}

class RecurringTile extends StatelessWidget {
  const RecurringTile({
    super.key,
    required this.app,
    required this.rule,
    required this.date,
    required this.onTap,
  });
  final _RialAppState app;
  final Map<String, dynamic> rule;
  final String date;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final income = rule['type'] == 'income';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CupertinoButton(
        padding: const EdgeInsets.all(14),
        color: t.card,
        borderRadius: BorderRadius.circular(8),
        onPressed: onTap,
        child: Row(
          children: [
            Icon(
              income
                  ? CupertinoIcons.arrow_down_left
                  : CupertinoIcons.arrow_up_right,
              color: income ? t.green : t.red,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule['name'].toString(),
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${income ? 'Ingreso' : 'Gasto'} · ${displayDateOnly(date)}',
                    style: TextStyle(color: t.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    app.secureMoney(
                      numberValue(rule['amount']),
                      rule['currency'].toString(),
                    ),
                    style: TextStyle(
                      color: income ? t.green : t.red,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right, color: t.muted, size: 16),
          ],
        ),
      ),
    );
  }
}

class RecurringMovementsPage extends StatelessWidget {
  const RecurringMovementsPage({super.key, required this.app});
  final _RialAppState app;
  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final rules = app
        .maps('recurringMovements')
        .where((r) => r['archived'] != true)
        .toList();
    final pending = recurringPendingItems(app);
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        middle: const Text('Recurrentes'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            if (app.ensureCanCreateMovement(context, 'expense'))
              app.pushPage(context, (_) => RecurringEditor(app: app));
          },
          child: const Icon(
            CupertinoIcons.add,
            semanticLabel: 'Nuevo recurrente',
          ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (rules.isEmpty)
              EmptyCard(theme: t, text: 'Sin movimientos recurrentes'),
            if (pending.isNotEmpty)
              SectionHeader(theme: t, title: 'Por confirmar'),
            for (final rule in pending)
              RecurringTile(
                app: app,
                rule: rule,
                date: rule['pendingDate'].toString(),
                onTap: () => recurringActions(
                  context,
                  app,
                  rule,
                  rule['pendingDate'].toString(),
                ),
              ),
            if (rules.isNotEmpty) SectionHeader(theme: t, title: 'Programados'),
            for (final rule in rules)
              OptionField(
                theme: t,
                label: rule['paused'] == true
                    ? 'Pausado'
                    : '${recurringFrequencies[rule['frequency']]} · ${displayDateOnly(nextRecurringDate(rule, app.maps('movements'))?.toIso8601String().split('T').first)}',
                value: rule['name'].toString(),
                icon: CupertinoIcons.repeat,
                onTap: () => app.pushPage(
                  context,
                  (_) =>
                      RecurringEditor(app: app, ruleId: rule['id'].toString()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class RecurringEditor extends StatefulWidget {
  const RecurringEditor({super.key, required this.app, this.ruleId});
  final _RialAppState app;
  final String? ruleId;
  @override
  State<RecurringEditor> createState() => _RecurringEditorState();
}

class _RecurringEditorState extends State<RecurringEditor> {
  final name = TextEditingController();
  final amount = MoneyEditingController();
  String type = 'expense',
      accountId = '',
      category = 'Otro',
      frequency = 'monthly';
  late DateTime start;
  bool paused = false, notify = true;
  Map<String, dynamic>? get rule => widget.app
      .maps('recurringMovements')
      .where((r) => r['id'] == widget.ruleId)
      .firstOrNull;
  bool get calendarLocked =>
      rule != null &&
      recurringResolvedDates(rule!, widget.app.maps('movements')).isNotEmpty;
  @override
  void initState() {
    super.initState();
    final old = rule;
    name.text = old?['name']?.toString() ?? '';
    if (old != null) amount.text = plain(numberValue(old['amount']));
    type = old?['type']?.toString() ?? type;
    accountId =
        old?['accountId']?.toString() ??
        widget.app.usableAccounts().firstOrNull?['id']?.toString() ??
        '';
    category = old?['category']?.toString() ?? category;
    frequency = old?['frequency']?.toString() ?? frequency;
    start = recurringParseDate(old?['startDate']) ?? DateTime.now();
    paused = old?['paused'] == true;
    notify = old?['notify'] != false;
  }

  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = app.theme;
    final account = app.accountById(accountId);
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        middle: Text(
          widget.ruleId == null ? 'Nuevo recurrente' : 'Editar recurrente',
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (!calendarLocked)
              KindSelector(
                theme: t,
                value: type,
                separated: true,
                items: const [
                  KindSelectorItem(
                    value: 'expense',
                    label: 'Gasto',
                    icon: CupertinoIcons.arrow_up_right,
                  ),
                  KindSelectorItem(
                    value: 'income',
                    label: 'Ingreso',
                    icon: CupertinoIcons.arrow_down_left,
                  ),
                ],
                onChanged: (v) => setState(() => type = v),
              )
            else
              StaticField(
                theme: t,
                label: 'Tipo',
                value: type == 'income' ? 'Ingreso' : 'Gasto',
              ),
            RField(
              theme: t,
              controller: name,
              placeholder: 'Nombre',
              inputFormatters: [LengthLimitingTextInputFormatter(80)],
            ),
            OptionField(
              theme: t,
              label: 'Cuenta',
              value: accountLabel(account),
              icon: CupertinoIcons.creditcard,
              onTap: () => showModernActionSheet(
                context,
                title: 'Cuenta',
                actions: [
                  for (final a in app.usableAccounts().where(
                    (a) =>
                        !calendarLocked || a['currency'] == rule?['currency'],
                  ))
                    ModernSheetAction(
                      title: accountPrimaryName(a),
                      subtitle: displayCurrency(a['currency'].toString()),
                      icon: CupertinoIcons.creditcard,
                      logoProvider: a['provider']?.toString(),
                      selected: a['id'] == accountId,
                      onPressed: () =>
                          setState(() => accountId = a['id'].toString()),
                    ),
                ],
              ),
            ),
            RField(
              theme: t,
              controller: amount,
              placeholder:
                  'Monto en ${account?['currency'] == 'VES' ? 'Bs.' : account?['currency'] ?? 'USD'}',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            if (type == 'expense')
              OptionField(
                theme: t,
                label: 'Categor\u00eda',
                value: category,
                icon: categoryIcon(category, context: context),
                onTap: () => pickCategory(
                  context,
                  category,
                  (v) => setState(() => category = v),
                ),
              ),
            if (calendarLocked) ...[
              StaticField(
                theme: t,
                label: 'Frecuencia',
                value: recurringFrequencies[frequency] ?? '',
              ),
              StaticField(
                theme: t,
                label: 'Primera fecha',
                value: formatDate(start),
              ),
            ] else ...[
              OptionField(
                theme: t,
                label: 'Frecuencia',
                value: recurringFrequencies[frequency]!,
                icon: CupertinoIcons.repeat,
                onTap: () => pickValue(
                  context,
                  recurringFrequencies.values.toList(),
                  recurringFrequencies[frequency]!,
                  (v) => setState(
                    () => frequency = recurringFrequencies.entries
                        .firstWhere((e) => e.value == v)
                        .key,
                  ),
                ),
              ),
              OptionField(
                theme: t,
                label: 'Primera fecha',
                value: formatDate(start),
                icon: CupertinoIcons.calendar,
                onTap: () async {
                  final picked = await pickModernDate(
                    context: context,
                    theme: t,
                    initial: start,
                  );
                  if (mounted && picked != null) setState(() => start = picked);
                },
              ),
            ],
            SettingsSwitchTile(
              theme: t,
              icon: CupertinoIcons.bell,
              title: 'Avisarme',
              subtitle: app.dailyReminderLabel,
              framed: false,
              value: notify,
              onTap: () => setState(() => notify = !notify),
            ),
            SettingsSwitchTile(
              theme: t,
              icon: CupertinoIcons.pause,
              title: 'Pausado',
              subtitle: '',
              framed: false,
              value: paused,
              onTap: () => setState(() => paused = !paused),
            ),
            const SizedBox(height: 20),
            PrimaryActionButton(
              theme: t,
              label: 'Guardar recurrente',
              onPressed: () {
                try {
                  saveRecurringRule(app, {
                    'name': name.text,
                    'amount': parseAmount(amount.text),
                    'type': type,
                    'accountId': accountId,
                    'category': category,
                    'frequency': frequency,
                    'startDate': recurringDateKey(start),
                    'paused': paused,
                    'notify': notify,
                  }, editingId: widget.ruleId);
                  Navigator.pop(context);
                } on FormatException catch (e) {
                  showModernNotice(
                    context,
                    title: 'Recurrente',
                    message: e.message,
                  );
                }
              },
            ),
            if (widget.ruleId != null) ...[
              const SizedBox(height: 14),
              SecondaryActionButton(
                theme: t,
                label: 'Eliminar recurrente',
                onPressed: () => showModernConfirm(
                  context,
                  title: 'Eliminar recurrente',
                  message: 'Los movimientos registrados se conservar\u00e1n.',
                  destructiveText: 'Eliminar',
                  onConfirm: () {
                    app.undoableMutation(
                      'Recurrente eliminado',
                      {
                        'recurringMovements': {widget.ruleId!},
                      },
                      () {
                        rule?['archived'] = true;
                      },
                    );
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
