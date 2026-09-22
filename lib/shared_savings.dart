part of 'main.dart';

Map<String, dynamic> newCoupleSavings() => {
  'id': 'couple',
  'target': 0.0,
  'members': [
    {'id': 'self', 'name': 'Yo'},
    {'id': 'partner', 'name': 'Mi pareja'},
  ],
  'history': <dynamic>[],
};

List<Map<String, dynamic>> savingsEntries(Map<String, dynamic> record) =>
    (record['history'] is List ? record['history'] as List : const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

List<Map<String, dynamic>> savingsMembers(Map<String, dynamic> record) =>
    (record['members'] as List)
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

Map<String, dynamic> coupleSavings(_RialAppState app) =>
    app.maps('sharedSavings').firstWhere((f) => f['id'] == 'couple');

Map<String, dynamic>? savingsCircle(_RialAppState app, String id) =>
    app.maps('savingsCircles').where((f) => f['id'] == id).firstOrNull;

String savingsMemberName(Map<String, dynamic> record, String id) =>
    savingsMembers(record)
        .where((m) => m['id'] == id)
        .firstOrNull?['name']
        ?.toString() ??
    'Persona';

double coupleSaved(Map<String, dynamic> record) => savingsEntries(record).fold(
  0.0,
  (sum, entry) => moneyAdd(
    sum,
    numberValue(entry['amountUsd']) * (entry['type'] == 'withdraw' ? -1 : 1),
  ),
);

double checkedSavingsAmount(double amount) {
  if (!amount.isFinite ||
      amount <= 0 ||
      amount > 999999999999 ||
      moneyRound(amount) <= 0) {
    throw const FormatException(
      'Coloca un monto mayor a cero y dentro del rango permitido.',
    );
  }
  return moneyRound(amount);
}

double savingsConversion(
  _RialAppState app,
  double amount,
  String from,
  String to,
) {
  const currencies = {'USD', 'VES', 'EUR', 'USDT'};
  if (!currencies.contains(from) || !currencies.contains(to)) {
    throw const FormatException('Moneda no admitida.');
  }
  if (from == to || ({from, to}.difference({'USD', 'USDT'}).isEmpty))
    return moneyRound(amount);
  final rates = {
    'VES': 1.0,
    'USD': app.rate,
    'EUR': app.eurRate,
    'USDT': app.usdtRate,
  };
  final source = rates[from] ?? 0;
  final target = rates[to] ?? 0;
  if (!source.isFinite || !target.isFinite || source <= 0 || target <= 0) {
    throw const FormatException(
      'No hay una tasa disponible para esta moneda. Actualiza las tasas.',
    );
  }
  return checkedSavingsAmount(moneyConvert(amount, source, target));
}

DateTime circleRoundDate(Map<String, dynamic> circle, int round) {
  final start = DateTime.parse(circle['startDate'] as String);
  if (circle['frequency'] == 'monthly') {
    final month = DateTime(start.year, start.month + round);
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    return DateTime(month.year, month.month, math.min(start.day, lastDay));
  }
  return start.add(
    Duration(days: round * (circle['frequency'] == 'fortnightly' ? 14 : 7)),
  );
}

Map<String, dynamic>? circleEntry(
  Map<String, dynamic> circle,
  int round,
  String memberId,
  String type,
) => savingsEntries(circle)
    .where(
      (entry) =>
          entry['round'] == round &&
          entry['memberId'] == memberId &&
          entry['type'] == type,
    )
    .firstOrNull;

bool circleRoundFunded(Map<String, dynamic> circle, int round) =>
    savingsMembers(circle).every(
      (member) =>
          circleEntry(circle, round, member['id'].toString(), 'contribution') !=
          null,
    );

int circlePaidRounds(Map<String, dynamic> circle) =>
    savingsEntries(circle).where((entry) => entry['type'] == 'payout').length;

void saveSavingsCircle(_RialAppState app, Map<String, dynamic> input) {
  final members = savingsMembers(input);
  if ((input['name']?.toString().trim() ?? '').isEmpty ||
      members.length < 2 ||
      members.length > 60 ||
      members.any(
        (m) =>
            (m['name']?.toString().trim() ?? '').isEmpty ||
            (m['id']?.toString().trim() ?? '').isEmpty,
      ) ||
      members.map((m) => m['id']).toSet().length != members.length ||
      !members.any((m) => m['id'] == input['selfMemberId'])) {
    throw const FormatException(
      'Completa el nombre, los participantes y tu turno.',
    );
  }
  final quota = checkedSavingsAmount(numberValue(input['quota']));
  checkedSavingsAmount(quota * members.length);
  final start = DateTime.tryParse(input['startDate'].toString());
  if (!['USD', 'VES', 'EUR', 'USDT'].contains(input['currency']) ||
      !['weekly', 'fortnightly', 'monthly'].contains(input['frequency']) ||
      start == null ||
      isoDate(start) != input['startDate']) {
    throw const FormatException('Revisa la moneda, la frecuencia y la fecha.');
  }
  final id = input['id']?.toString() ?? app.id();
  final old = savingsCircle(app, id);
  if (old != null && savingsEntries(old).isNotEmpty) {
    for (final field in [
      'quota',
      'currency',
      'frequency',
      'startDate',
      'selfMemberId',
    ]) {
      if (old[field] != input[field])
        throw const FormatException(
          'El bolso ya tiene registros. Sus condiciones no se pueden cambiar.',
        );
    }
    if (jsonEncode(savingsMembers(old)) != jsonEncode(members)) {
      throw const FormatException(
        'El bolso ya tiene registros. Sus turnos no se pueden cambiar.',
      );
    }
  }
  app.undoableMutation(
    'Bolso guardado',
    {
      'savingsCircles': {id},
    },
    () {
      final circles = app.rawList('savingsCircles');
      final record = {
        ...input,
        'id': id,
        'quota': quota,
        'history': old?['history'] ?? <dynamic>[],
      };
      final index = circles.indexWhere(
        (item) => item is Map && item['id'] == id,
      );
      if (index < 0) {
        circles.add(record);
      } else {
        circles[index] = record;
      }
    },
  );
}

void recordSharedSaving(
  _RialAppState app, {
  required String collection,
  required String recordId,
  required String memberId,
  required String type,
  required String currency,
  required double amount,
  String accountId = '',
  int? round,
  required String date,
}) {
  final isCouple = collection == 'sharedSavings';
  if (!isCouple && collection != 'savingsCircles')
    throw const FormatException('Registro no valido.');
  final record = isCouple ? coupleSavings(app) : savingsCircle(app, recordId);
  if (record == null ||
      record['id'] != recordId ||
      !savingsMembers(record).any((m) => m['id'] == memberId))
    throw const FormatException('El registro ya no existe.');
  final raw = checkedSavingsAmount(amount);
  final incoming = type == 'withdraw' || type == 'payout';
  final usd = isCouple ? savingsConversion(app, raw, currency, 'USD') : 0.0;
  if (isCouple) {
    if (!['deposit', 'withdraw'].contains(type))
      throw const FormatException('Operacion no valida.');
    if (incoming && usd > coupleSaved(record))
      throw const FormatException(
        'No puedes retirar mas del saldo compartido.',
      );
  } else {
    final members = savingsMembers(record);
    if (round == null ||
        round < 0 ||
        round >= members.length ||
        !['contribution', 'payout'].contains(type) ||
        currency != record['currency']) {
      throw const FormatException('Turno no valido.');
    }
    if (circleEntry(record, round, memberId, type) != null)
      throw const FormatException('Este registro ya existe.');
    if (incoming &&
        (members[round]['id'] != memberId ||
            !circleRoundFunded(record, round))) {
      throw const FormatException(
        'Primero registra todas las cuotas de esta ronda.',
      );
    }
    if (accountId.isNotEmpty && memberId != record['selfMemberId']) {
      throw const FormatException(
        'Los aportes y cobros de otras personas no afectan tus cuentas.',
      );
    }
    final expected = moneyRound(
      numberValue(record['quota']) * (incoming ? members.length : 1),
    );
    if (moneyCents(raw) != moneyCents(expected))
      throw const FormatException(
        'El monto no coincide con la cuota del bolso.',
      );
  }
  final account = accountId.isEmpty ? null : app.accountById(accountId);
  if (accountId.isNotEmpty && account == null)
    throw const FormatException('La cuenta ya no existe.');
  final accountCurrency = account?['currency']?.toString() ?? currency;
  final accountAmount = account == null
      ? 0.0
      : savingsConversion(app, raw, currency, accountCurrency);
  if (!incoming &&
      account != null &&
      accountAmount > numberValue(account['balance'])) {
    throw const FormatException('La cuenta no tiene saldo suficiente.');
  }
  final id = app.id();
  final delta = incoming ? accountAmount : -accountAmount;
  app.undoableMutation(
    type == 'payout'
        ? 'Cobro registrado'
        : incoming
        ? 'Retiro registrado'
        : 'Aporte registrado',
    {
      collection: {recordId},
      'accounts': {accountId},
      'balanceAdjustments': {if (account != null) id},
    },
    () {
      final history = savingsEntries(record);
      history.add({
        'id': id,
        'memberId': memberId,
        'type': type,
        'amount': raw,
        'amountUsd': usd,
        'currency': currency,
        'accountId': accountId,
        'accountAmount': accountAmount,
        'accountCurrency': accountCurrency,
        'date': date,
        if (round != null) 'round': round,
      });
      record['history'] = history;
      if (account != null) {
        account['balance'] = moneyAdd(numberValue(account['balance']), delta);
        app.rawList('balanceAdjustments').add({
          'id': id,
          'accountId': accountId,
          'amount': delta,
          'date': date,
        });
      }
    },
  );
}

void deleteSharedSaving(
  _RialAppState app,
  String collection,
  String recordId,
  String entryId,
) {
  if (collection != 'sharedSavings' && collection != 'savingsCircles') {
    throw const FormatException('Registro no valido.');
  }
  final record = collection == 'sharedSavings'
      ? coupleSavings(app)
      : savingsCircle(app, recordId);
  if (record == null) return;
  final history = savingsEntries(record);
  final entry = history.where((e) => e['id'] == entryId).firstOrNull;
  if (entry == null) return;
  final incoming = entry['type'] == 'withdraw' || entry['type'] == 'payout';
  if (collection == 'sharedSavings' &&
      !incoming &&
      numberValue(entry['amountUsd']) > coupleSaved(record)) {
    throw const FormatException(
      'Ese aporte ya se uso. Revierte primero los retiros correspondientes.',
    );
  }
  if (collection == 'savingsCircles' &&
      !incoming &&
      history.any(
        (e) => e['round'] == entry['round'] && e['type'] == 'payout',
      )) {
    throw const FormatException('Revierte primero el cobro de esa ronda.');
  }
  final accountId = entry['accountId']?.toString() ?? '';
  final account = accountId.isEmpty ? null : app.accountById(accountId);
  if (accountId.isNotEmpty && account == null)
    throw const FormatException('La cuenta vinculada ya no existe.');
  if (account != null && account['currency'] != entry['accountCurrency']) {
    throw const FormatException(
      'La cuenta cambio de moneda. Restaura la moneda original antes de revertir el registro.',
    );
  }
  final delta = numberValue(entry['accountAmount']) * (incoming ? -1 : 1);
  if (account != null && moneyAdd(numberValue(account['balance']), delta) < 0) {
    throw const FormatException(
      'No hay saldo suficiente en la cuenta para revertir ese cobro.',
    );
  }
  app.undoableMutation(
    'Registro eliminado',
    {
      collection: {recordId},
      'accounts': {accountId},
      'balanceAdjustments': {entryId},
    },
    () {
      record['history'] = history.where((e) => e['id'] != entryId).toList();
      if (account != null)
        account['balance'] = moneyAdd(numberValue(account['balance']), delta);
      app
          .rawList('balanceAdjustments')
          .removeWhere((e) => e is Map && e['id'] == entryId);
    },
  );
}

void savingsNotice(BuildContext context, FormatException error) =>
    showModernNotice(
      context,
      title: 'Revisa el registro',
      message: error.message,
    );

class SharedSavingsScaffold extends StatelessWidget {
  const SharedSavingsScaffold({
    super.key,
    required this.app,
    required this.title,
    required this.children,
    this.action,
    this.trailing,
  });
  final _RialAppState app;
  final String title;
  final List<Widget> children;
  final Widget? action, trailing;
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: app.theme.bg,
    navigationBar: CupertinoNavigationBar(
      transitionBetweenRoutes: false,
      backgroundColor: app.theme.bg,
      border: null,
      middle: Text(title),
      trailing: trailing,
    ),
    child: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              children: children,
            ),
          ),
          if (action != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: action,
            ),
        ],
      ),
    ),
  );
}

class CoupleSavingsPage extends StatelessWidget {
  const CoupleSavingsPage({super.key, required this.app});
  final _RialAppState app;
  @override
  Widget build(BuildContext context) {
    final record = coupleSavings(app);
    final t = app.theme;
    final total = coupleSaved(record);
    final target = numberValue(record['target']);
    final history = savingsEntries(record);
    return SharedSavingsScaffold(
      app: app,
      title: 'Ahorros de Pareja',
      trailing: material.Tooltip(
        message: 'Editar pareja y objetivo',
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () =>
              app.pushPage(context, (_) => CoupleSavingsSettingsPage(app: app)),
          child: Icon(CupertinoIcons.pencil, color: t.accent),
        ),
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              app.secureMoney(total, 'USD'),
              style: TextStyle(
                color: t.ink,
                fontSize: 32,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        if (target > 0) ...[
          const SizedBox(height: 8),
          Text(
            'Objetivo ${app.secureMoney(target, 'USD')}',
            style: TextStyle(color: t.muted),
          ),
          const SizedBox(height: 12),
          RatioBar(
            theme: t,
            parts: [
              RatioPart(color: t.accent, value: math.min(total, target)),
              RatioPart(color: t.field, value: math.max(0, target - total)),
            ],
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: SecondaryActionButton(
                theme: t,
                label: 'Retirar',
                onPressed: () => _open(context, true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PrimaryActionButton(
                theme: t,
                label: 'Aportar',
                onPressed: () => _open(context, false),
              ),
            ),
          ],
        ),
        for (final member in savingsMembers(record)) ...[
          SectionHeader(theme: t, title: member['name'].toString()),
          for (final type in ['deposit', 'withdraw'])
            DebtDetailRow(
              theme: t,
              label: type == 'deposit' ? 'Aportes' : 'Retiros',
              fitValue: true,
              value: app.secureMoney(
                history
                    .where(
                      (e) => e['memberId'] == member['id'] && e['type'] == type,
                    )
                    .fold<double>(
                      0,
                      (sum, e) => moneyAdd(sum, numberValue(e['amountUsd'])),
                    ),
                'USD',
              ),
            ),
        ],
        SectionHeader(theme: t, title: 'Historial'),
        if (history.isEmpty)
          EmptyCard(theme: t, text: 'Sin aportes ni retiros'),
        for (final entry in history.reversed)
          SharedSavingHistoryTile(
            app: app,
            record: record,
            collection: 'sharedSavings',
            entry: entry,
          ),
      ],
    );
  }

  void _open(BuildContext context, bool withdraw) => app.pushPage(
    context,
    (_) => SharedSavingEntryPage(
      app: app,
      collection: 'sharedSavings',
      recordId: 'couple',
      type: withdraw ? 'withdraw' : 'deposit',
    ),
  );
}

class CoupleSavingsSettingsPage extends StatefulWidget {
  const CoupleSavingsSettingsPage({super.key, required this.app});
  final _RialAppState app;
  @override
  State<CoupleSavingsSettingsPage> createState() =>
      _CoupleSavingsSettingsPageState();
}

class _CoupleSavingsSettingsPageState extends State<CoupleSavingsSettingsPage> {
  late final List<TextEditingController> names;
  late final MoneyEditingController target;
  @override
  void initState() {
    super.initState();
    final record = coupleSavings(widget.app);
    names = savingsMembers(record)
        .map((m) => TextEditingController(text: m['name'].toString()))
        .toList();
    target = MoneyEditingController(
      text: numberValue(record['target']).toString(),
    );
  }

  @override
  void dispose() {
    for (final name in names) {
      name.dispose();
    }
    target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SharedSavingsScaffold(
    app: widget.app,
    title: 'Pareja y objetivo',
    children: [
      for (var i = 0; i < names.length; i++)
        RField(
          theme: widget.app.theme,
          controller: names[i],
          placeholder: 'Nombre ${i + 1}',
        ),
      RField(
        theme: widget.app.theme,
        controller: target,
        placeholder: 'Objetivo en d\u00f3lares',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      ),
    ],
    action: PrimaryActionButton(
      theme: widget.app.theme,
      label: 'Guardar',
      onPressed: () {
        final value = parseAmount(target.text);
        if (names.any((n) => n.text.trim().isEmpty) ||
            !value.isFinite ||
            value < 0 ||
            value > 999999999999) {
          savingsNotice(
            context,
            const FormatException(
              'Completa ambos nombres y un objetivo valido.',
            ),
          );
          return;
        }
        widget.app.undoableMutation(
          'Ahorro de pareja editado',
          {
            'sharedSavings': {'couple'},
          },
          () {
            final record = coupleSavings(widget.app);
            record['target'] = moneyRound(value);
            final members = savingsMembers(record);
            for (var i = 0; i < members.length; i++) {
              members[i]['name'] = names[i].text.trim();
            }
          },
        );
        Navigator.pop(context);
      },
    ),
  );
}

class SharedSavingHistoryTile extends StatelessWidget {
  const SharedSavingHistoryTile({
    super.key,
    required this.app,
    required this.record,
    required this.collection,
    required this.entry,
  });
  final _RialAppState app;
  final Map<String, dynamic> record, entry;
  final String collection;
  @override
  Widget build(BuildContext context) {
    final incoming = entry['type'] == 'withdraw' || entry['type'] == 'payout';
    final name = savingsMemberName(record, entry['memberId'].toString());
    return MenuTile(
      theme: app.theme,
      icon: incoming
          ? CupertinoIcons.arrow_up_circle
          : CupertinoIcons.arrow_down_circle,
      title:
          '${entry['type'] == 'payout'
              ? 'Cobro'
              : incoming
              ? 'Retiro'
              : 'Aporte'}: $name',
      subtitle:
          '${app.secureMoney(numberValue(entry['amount']), entry['currency'].toString())} · ${entry['date']}',
      onTap: () => showModernActionSheet(
        context,
        title: name,
        actions: [
          ModernSheetAction(
            icon: CupertinoIcons.trash,
            title: 'Eliminar registro',
            destructive: true,
            subtitle: (entry['accountId']?.toString() ?? '').isEmpty
                ? 'Registro fuera de tus cuentas'
                : 'Revierte el importe en la cuenta',
            onPressed: () => app.confirmDelete(context, 'Eliminar registro', 'Se revertira este registro y su importe en la cuenta, si corresponde.', () {
              try {
                deleteSharedSaving(
                  app,
                  collection,
                  record['id'].toString(),
                  entry['id'].toString(),
                );
              } on FormatException catch (error) {
                savingsNotice(context, error);
              }
            }),
          ),
        ],
      ),
    );
  }
}

class SharedSavingEntryPage extends StatefulWidget {
  const SharedSavingEntryPage({
    super.key,
    required this.app,
    required this.collection,
    required this.recordId,
    required this.type,
    this.memberId,
    this.round,
  });
  final _RialAppState app;
  final String collection, recordId, type;
  final String? memberId;
  final int? round;
  @override
  State<SharedSavingEntryPage> createState() => _SharedSavingEntryPageState();
}

String circleFrequencyLabel(String value) => switch (value) {
  'monthly' => 'Mensual',
  'fortnightly' => 'Cada 14 dias',
  _ => 'Semanal',
};

class SavingsCirclesPage extends StatelessWidget {
  const SavingsCirclesPage({super.key, required this.app});
  final _RialAppState app;
  @override
  Widget build(BuildContext context) {
    final circles = app.maps('savingsCircles');
    return SharedSavingsScaffold(
      app: app,
      title: 'Bolso / San',
      children: [
        if (circles.isEmpty)
          EmptyCard(theme: app.theme, text: 'Sin bolsos registrados'),
        for (final circle in circles)
          MenuTile(
            theme: app.theme,
            icon: CupertinoIcons.arrow_2_circlepath,
            title: circle['name'].toString(),
            subtitle:
                '${app.secureMoney(numberValue(circle['quota']), circle['currency'].toString())} · ${circlePaidRounds(circle)}/${savingsMembers(circle).length} turnos cobrados',
            onTap: () => app.pushPage(
              context,
              (_) => SavingsCircleDetailsPage(
                app: app,
                circleId: circle['id'].toString(),
              ),
            ),
          ),
      ],
      action: PrimaryActionButton(
        theme: app.theme,
        label: 'Nuevo bolso',
        onPressed: () =>
            app.pushPage(context, (_) => SavingsCircleEditorPage(app: app)),
      ),
    );
  }
}

class SavingsCircleDetailsPage extends StatefulWidget {
  const SavingsCircleDetailsPage({
    super.key,
    required this.app,
    required this.circleId,
  });
  final _RialAppState app;
  final String circleId;
  @override
  State<SavingsCircleDetailsPage> createState() =>
      _SavingsCircleDetailsPageState();
}

class _SavingsCircleDetailsPageState extends State<SavingsCircleDetailsPage> {
  int round = 0;
  @override
  void initState() {
    super.initState();
    final circle = savingsCircle(widget.app, widget.circleId);
    if (circle != null) {
      final members = savingsMembers(circle);
      round = members.indexWhere(
        (m) =>
            circleEntry(
              circle,
              members.indexOf(m),
              m['id'].toString(),
              'payout',
            ) ==
            null,
      );
      if (round < 0) round = members.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app, t = app.theme;
    final circle = savingsCircle(app, widget.circleId);
    if (circle == null)
      return SharedSavingsScaffold(
        app: app,
        title: 'Bolso / San',
        children: [EmptyCard(theme: t, text: 'Registro no disponible')],
      );
    final members = savingsMembers(circle);
    round = round.clamp(0, members.length - 1);
    final recipient = members[round];
    final history = savingsEntries(circle);
    final paid = circlePaidRounds(circle);
    final ownEntries = history.where(
      (entry) => entry['memberId'] == circle['selfMemberId'],
    );
    final received = ownEntries
        .where((entry) => entry['type'] == 'payout')
        .firstOrNull;
    final paidIn = ownEntries
        .where((entry) => entry['type'] == 'contribution')
        .fold<double>(0, (sum, e) => moneyAdd(sum, numberValue(e['amount'])));
    final ownTurn = members.indexWhere(
      (m) => m['id'] == circle['selfMemberId'],
    );
    final pot = moneyRound(numberValue(circle['quota']) * members.length);
    final payout = circleEntry(
      circle,
      round,
      recipient['id'].toString(),
      'payout',
    );
    final funded = circleRoundFunded(circle, round);
    final missing = members
        .where(
          (m) =>
              circleEntry(circle, round, m['id'].toString(), 'contribution') ==
              null,
        )
        .length;
    return SharedSavingsScaffold(
      app: app,
      title: circle['name'].toString(),
      trailing: material.Tooltip(
        message: 'Opciones del bolso',
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => showModernActionSheet(
            context,
            title: 'Bolso / San',
            actions: [
              ModernSheetAction(
                icon: CupertinoIcons.pencil,
                title: 'Editar bolso',
                onPressed: () => app.pushPage(
                  context,
                  (_) => SavingsCircleEditorPage(
                    app: app,
                    circleId: widget.circleId,
                  ),
                ),
              ),
              ModernSheetAction(
                icon: CupertinoIcons.trash,
                title: 'Eliminar bolso',
                destructive: true,
                onPressed: () {
                  if (history.isNotEmpty) {
                    savingsNotice(
                      context,
                      const FormatException(
                        'Primero elimina los aportes y cobros del historial para no perder sus saldos.',
                      ),
                    );
                    return;
                  }
                  app.confirmDelete(
                    context,
                    'Eliminar bolso',
                    'Se eliminara este bolso vacio.',
                    () {
                      app.undoableMutation(
                        'Bolso eliminado',
                        {
                          'savingsCircles': {widget.circleId},
                        },
                        () => app
                            .rawList('savingsCircles')
                            .removeWhere(
                              (c) => c is Map && c['id'] == widget.circleId,
                            ),
                      );
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ],
          ),
          child: Icon(CupertinoIcons.ellipsis, color: t.accent),
        ),
      ),
      children: [
        Text(
          paid == members.length
              ? 'Bolso completado'
              : '$paid de ${members.length} turnos cobrados',
          style: TextStyle(
            color: t.ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        DebtDetailRow(
          theme: t,
          label:
              'Cuota ${circleFrequencyLabel(circle['frequency'].toString()).toLowerCase()}',
          fitValue: true,
          value: app.secureMoney(
            numberValue(circle['quota']),
            circle['currency'].toString(),
          ),
        ),
        DebtDetailRow(
          theme: t,
          label: 'Mis aportes',
          fitValue: true,
          value: app.secureMoney(paidIn, circle['currency'].toString()),
        ),
        DebtDetailRow(
          theme: t,
          label: received == null ? 'Por recibir' : 'Recibido',
          fitValue: true,
          value: app.secureMoney(pot, circle['currency'].toString()),
        ),
        DebtDetailRow(
          theme: t,
          label: 'Mi turno',
          value:
              '${ownTurn + 1} · ${formatDate(circleRoundDate(circle, ownTurn))}',
        ),
        const SizedBox(height: 18),
        OptionField(
          theme: t,
          label: 'Turno',
          value: '${round + 1} · ${recipient['name']}',
          icon: CupertinoIcons.calendar,
          onTap: () => showModernActionSheet(
            context,
            title: 'Seleccionar turno',
            actions: [
              for (var i = 0; i < members.length; i++)
                ModernSheetAction(
                  icon: CupertinoIcons.person_fill,
                  title: '${i + 1} · ${members[i]['name']}',
                  subtitle: formatDate(circleRoundDate(circle, i)),
                  selected: round == i,
                  onPressed: () => setState(() => round = i),
                ),
            ],
          ),
        ),
        Text(
          formatDate(circleRoundDate(circle, round)),
          style: TextStyle(color: t.muted),
        ),
        SectionHeader(theme: t, title: 'Aportes de la ronda'),
        for (final member in members)
          Builder(
            builder: (context) {
              final entry = circleEntry(
                circle,
                round,
                member['id'].toString(),
                'contribution',
              );
              return MenuTile(
                theme: t,
                icon: entry == null
                    ? CupertinoIcons.circle
                    : CupertinoIcons.checkmark_circle_fill,
                title: member['name'].toString(),
                subtitle: entry == null
                    ? 'Cuota pendiente'
                    : 'Pagada · ${entry['date']}',
                onTap: () => entry == null
                    ? _open(context, member['id'].toString(), 'contribution')
                    : _entryActions(context, circle, entry),
              );
            },
          ),
        if (payout != null)
          SharedSavingHistoryTile(
            app: app,
            record: circle,
            collection: 'savingsCircles',
            entry: payout,
          )
        else if (funded)
          PrimaryActionButton(
            theme: t,
            label: 'Registrar cobro del turno',
            onPressed: () =>
                _open(context, recipient['id'].toString(), 'payout'),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Cuotas pendientes: $missing',
              style: TextStyle(color: t.muted, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }

  void _open(BuildContext context, String memberId, String type) =>
      widget.app.pushPage(
        context,
        (_) => SharedSavingEntryPage(
          app: widget.app,
          collection: 'savingsCircles',
          recordId: widget.circleId,
          memberId: memberId,
          type: type,
          round: round,
        ),
      );
  void _entryActions(
    BuildContext context,
    Map<String, dynamic> circle,
    Map<String, dynamic> entry,
  ) {
    showModernActionSheet(
      context,
      title: savingsMemberName(circle, entry['memberId'].toString()),
      actions: [
        ModernSheetAction(
          icon: CupertinoIcons.trash,
          title: 'Eliminar aporte',
          destructive: true,
          onPressed: () => widget.app.confirmDelete(
            context,
            'Eliminar aporte',
            'Se revertira la cuota y su importe en la cuenta, si corresponde.',
            () {
              try {
                deleteSharedSaving(
                  widget.app,
                  'savingsCircles',
                  widget.circleId,
                  entry['id'].toString(),
                );
              } on FormatException catch (error) {
                savingsNotice(context, error);
              }
            },
          ),
        ),
      ],
    );
  }
}

class SavingsCircleEditorPage extends StatefulWidget {
  const SavingsCircleEditorPage({super.key, required this.app, this.circleId});
  final _RialAppState app;
  final String? circleId;
  @override
  State<SavingsCircleEditorPage> createState() =>
      _SavingsCircleEditorPageState();
}

class _SavingsCircleEditorPageState extends State<SavingsCircleEditorPage> {
  final name = TextEditingController();
  final quota = MoneyEditingController();
  final names = <TextEditingController>[];
  final retiredNames = <TextEditingController>[];
  final ids = <String>[];
  String currency = 'USD', frequency = 'weekly', selfId = '', startDate = '';
  bool locked = false;
  @override
  void initState() {
    super.initState();
    final existing = widget.circleId == null
        ? null
        : savingsCircle(widget.app, widget.circleId!);
    startDate = existing?['startDate']?.toString() ?? isoDate(DateTime.now());
    name.text = existing?['name']?.toString() ?? '';
    currency = existing?['currency']?.toString() ?? 'USD';
    frequency = existing?['frequency']?.toString() ?? 'weekly';
    if (existing != null)
      quota.text = numberValue(existing['quota']).toString();
    final members = existing == null
        ? [
            {'id': widget.app.id(), 'name': 'Yo'},
            {'id': widget.app.id(), 'name': 'Persona 2'},
          ]
        : savingsMembers(existing);
    for (final m in members) {
      ids.add(m['id'].toString());
      names.add(TextEditingController(text: m['name'].toString()));
    }
    selfId = existing?['selfMemberId']?.toString() ?? ids.first;
    locked = existing != null && savingsEntries(existing).isNotEmpty;
  }

  @override
  void dispose() {
    name.dispose();
    quota.dispose();
    for (final c in [...names, ...retiredNames]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app, t = app.theme;
    return SharedSavingsScaffold(
      app: app,
      title: widget.circleId == null ? 'Nuevo bolso' : 'Editar bolso',
      children: [
        RField(theme: t, controller: name, placeholder: 'Nombre del bolso'),
        if (locked) ...[
          DebtDetailRow(
            theme: t,
            label: 'Cuota',
            fitValue: true,
            value: app.secureMoney(parseAmount(quota.text), currency),
          ),
          DebtDetailRow(
            theme: t,
            label: 'Frecuencia',
            value: circleFrequencyLabel(frequency),
          ),
          DebtDetailRow(
            theme: t,
            label: 'Primer turno',
            value: formatDate(DateTime.parse(startDate)),
          ),
          for (var i = 0; i < names.length; i++)
            DebtDetailRow(
              theme: t,
              label: 'Turno ${i + 1}',
              value: names[i].text,
            ),
        ] else ...[
          RField(
            theme: t,
            controller: quota,
            placeholder: 'Cuota por persona',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          OptionField(
            theme: t,
            label: 'Moneda',
            value: displayCurrency(currency),
            onTap: () => pickValue(
              context,
              ['USD', 'VES', 'EUR', 'USDT'].map(displayCurrency).toList(),
              displayCurrency(currency),
              (value) =>
                  setState(() => currency = currencyCodeFromLabel(value)),
            ),
          ),
          OptionField(
            theme: t,
            label: 'Frecuencia',
            value: circleFrequencyLabel(frequency),
            onTap: () => pickValue(
              context,
              [
                'weekly',
                'fortnightly',
                'monthly',
              ].map(circleFrequencyLabel).toList(),
              circleFrequencyLabel(frequency),
              (value) => setState(
                () => frequency = [
                  'weekly',
                  'fortnightly',
                  'monthly',
                ].firstWhere((f) => circleFrequencyLabel(f) == value),
              ),
            ),
          ),
          OptionField(
            theme: t,
            label: 'Primer turno',
            value: formatDate(DateTime.parse(startDate)),
            icon: CupertinoIcons.calendar,
            onTap: () => showModernDatePicker(
              context,
              theme: t,
              initial: DateTime.parse(startDate),
              onSelected: (value) => setState(() => startDate = isoDate(value)),
            ),
          ),
          SectionHeader(theme: t, title: 'Participantes y turnos'),
          for (var i = 0; i < names.length; i++)
            Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      color: t.muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  child: RField(
                    key: ValueKey(ids[i]),
                    theme: t,
                    controller: names[i],
                    placeholder: 'Turno ${i + 1}',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                material.Tooltip(
                  message: 'Quitar participante',
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: names.length <= 2
                        ? null
                        : () => setState(() {
                            retiredNames.add(names.removeAt(i));
                            final id = ids.removeAt(i);
                            if (selfId == id) selfId = ids.first;
                          }),
                    child: Icon(
                      CupertinoIcons.minus_circle,
                      color: names.length <= 2 ? t.muted : t.red,
                    ),
                  ),
                ),
              ],
            ),
          if (names.length < 60)
            SecondaryActionButton(
              theme: t,
              label: 'Agregar participante',
              onPressed: () => setState(() {
                names.add(TextEditingController());
                ids.add(app.id());
              }),
            ),
          const SizedBox(height: 12),
          OptionField(
            theme: t,
            label: 'Mi turno',
            value:
                '${ids.indexOf(selfId) + 1} · ${names[ids.indexOf(selfId)].text}',
            onTap: () => showModernActionSheet(
              context,
              title: 'Mi turno',
              actions: [
                for (var i = 0; i < ids.length; i++)
                  ModernSheetAction(
                    icon: CupertinoIcons.person,
                    title: '${i + 1} · ${names[i].text}',
                    selected: ids[i] == selfId,
                    onPressed: () => setState(() => selfId = ids[i]),
                  ),
              ],
            ),
          ),
        ],
      ],
      action: PrimaryActionButton(
        theme: t,
        label: 'Guardar bolso',
        onPressed: () {
          try {
            saveSavingsCircle(app, {
              if (widget.circleId != null) 'id': widget.circleId,
              'name': name.text.trim(),
              'quota': parseAmount(quota.text),
              'currency': currency,
              'frequency': frequency,
              'startDate': startDate,
              'selfMemberId': selfId,
              'members': [
                for (var i = 0; i < names.length; i++)
                  {'id': ids[i], 'name': names[i].text.trim()},
              ],
            });
            Navigator.pop(context);
          } on FormatException catch (error) {
            savingsNotice(context, error);
          }
        },
      ),
    );
  }
}

class _SharedSavingEntryPageState extends State<SharedSavingEntryPage> {
  final amount = MoneyEditingController();
  String accountId = '', currency = 'USD';
  late String memberId, date;
  bool get isCouple => widget.collection == 'sharedSavings';
  bool get incoming => widget.type == 'withdraw' || widget.type == 'payout';
  Map<String, dynamic>? get record => isCouple
      ? coupleSavings(widget.app)
      : savingsCircle(widget.app, widget.recordId);
  @override
  void initState() {
    super.initState();
    memberId = widget.memberId ?? 'self';
    date = formatDateTime(DateTime.now());
    if (!isCouple) currency = record?['currency']?.toString() ?? 'USD';
    if (memberId == (isCouple ? 'self' : record?['selfMemberId'])) {
      final accounts = widget.app.usableAccounts();
      final selected =
          accounts.where((a) => a['currency'] == currency).firstOrNull ??
          accounts.firstOrNull;
      accountId = selected?['id']?.toString() ?? '';
      if (isCouple) currency = selected?['currency']?.toString() ?? 'USD';
    }
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  double get rawAmount => isCouple
      ? parseAmount(amount.text)
      : moneyRound(
          numberValue(record?['quota']) *
              (incoming ? savingsMembers(record!).length : 1),
        );
  @override
  Widget build(BuildContext context) {
    final app = widget.app, t = app.theme;
    final data = record;
    if (data == null)
      return SharedSavingsScaffold(
        app: app,
        title: 'Registro no disponible',
        children: const [],
      );
    final own = isCouple || memberId == data['selfMemberId'];
    final account = app.accountById(accountId);
    String? converted;
    if (account != null && !isCouple) {
      try {
        converted = app.secureMoney(
          savingsConversion(
            app,
            rawAmount,
            currency,
            account['currency'].toString(),
          ),
          account['currency'].toString(),
        );
      } on FormatException {
        converted = 'Sin tasa';
      }
    }
    return SharedSavingsScaffold(
      app: app,
      title: widget.type == 'payout'
          ? 'Registrar cobro'
          : incoming
          ? 'Registrar retiro'
          : 'Registrar aporte',
      children: [
        if (isCouple)
          OptionField(
            theme: t,
            label: 'Persona',
            value: savingsMemberName(data, memberId),
            icon: CupertinoIcons.person_2_fill,
            onTap: () => showModernActionSheet(
              context,
              title: 'Persona',
              actions: savingsMembers(data)
                  .map(
                    (m) => ModernSheetAction(
                      icon: CupertinoIcons.person_fill,
                      title: m['name'].toString(),
                      selected: m['id'] == memberId,
                      onPressed: () => setState(() {
                        memberId = m['id'].toString();
                        accountId = '';
                        currency = 'USD';
                      }),
                    ),
                  )
                  .toList(),
            ),
          )
        else ...[
          DebtDetailRow(
            theme: t,
            label: 'Persona',
            value: savingsMemberName(data, memberId),
          ),
          DebtDetailRow(
            theme: t,
            label: incoming ? 'Monto del turno' : 'Cuota',
            fitValue: true,
            value: app.secureMoney(rawAmount, currency),
          ),
        ],
        if (own)
          OptionField(
            theme: t,
            label: incoming ? 'Cuenta destino' : 'Cuenta origen',
            value: account == null
                ? 'Fuera de mis cuentas'
                : accountLabel(account),
            logoProvider: account?['provider']?.toString(),
            onTap: () => showModernActionSheet(
              context,
              title: 'Cuenta',
              actions: [
                ModernSheetAction(
                  icon: CupertinoIcons.person_2,
                  title: 'Fuera de mis cuentas',
                  selected: accountId.isEmpty,
                  onPressed: () => setState(() => accountId = ''),
                ),
                ...app.usableAccounts().map(
                  (a) => ModernSheetAction(
                    icon: CupertinoIcons.creditcard,
                    title: accountLabel(a),
                    logoProvider: a['provider']?.toString(),
                    selected: a['id'] == accountId,
                    onPressed: () => setState(() {
                      accountId = a['id'].toString();
                      if (isCouple) currency = a['currency'].toString();
                    }),
                  ),
                ),
              ],
            ),
          ),
        if (isCouple && accountId.isEmpty)
          OptionField(
            theme: t,
            label: 'Moneda',
            value: displayCurrency(currency),
            onTap: () => pickValue(
              context,
              ['USD', 'VES', 'EUR', 'USDT'].map(displayCurrency).toList(),
              displayCurrency(currency),
              (value) =>
                  setState(() => currency = currencyCodeFromLabel(value)),
            ),
          ),
        if (isCouple)
          RField(
            theme: t,
            controller: amount,
            placeholder: 'Monto en ${displayCurrency(currency)}',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        if (converted != null)
          DebtDetailRow(
            theme: t,
            label: incoming ? 'Total a recibir' : 'Total a debitar',
            fitValue: true,
            value: converted,
          ),
        OptionField(
          theme: t,
          label: 'Fecha',
          value: date,
          icon: CupertinoIcons.calendar,
          onTap: () => showModernDateTimePicker(
            context,
            theme: t,
            initial: parseMovementDate(date),
            onSelected: (value) => setState(() => date = formatDateTime(value)),
          ),
        ),
      ],
      action: PrimaryActionButton(
        theme: t,
        label: 'Guardar registro',
        onPressed: () {
          try {
            recordSharedSaving(
              app,
              collection: widget.collection,
              recordId: widget.recordId,
              memberId: memberId,
              type: widget.type,
              currency: currency,
              amount: rawAmount,
              accountId: own ? accountId : '',
              round: widget.round,
              date: date,
            );
            Navigator.pop(context);
          } on FormatException catch (error) {
            savingsNotice(context, error);
          }
        },
      ),
    );
  }
}
