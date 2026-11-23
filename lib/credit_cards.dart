part of 'main.dart';

extension _CreditPaymentPicker on _MovementEditorState {
  void pickCreditPaymentCard() {
    final app = widget.app;
    showModernActionSheet(
      context,
      title: 'Tarjeta a pagar',
      actions: [
        for (final card in app.maps('accounts').where(isCreditCard))
          ModernSheetAction(
            title: accountPrimaryName(card),
            subtitle:
                '${displayCurrency(card['currency'].toString())} · ${app.secureMoney(creditDebt(card), card['currency'].toString())}',
            logoProvider: card['provider']?.toString(),
            icon: CupertinoIcons.creditcard,
            selected: card['id'] == creditPaymentId,
            onPressed: () =>
                _setViewState(() => creditPaymentId = card['id'].toString()),
          ),
      ],
    );
  }
}

bool isCreditCard(Map<String, dynamic>? account) =>
    account?['kind'] == 'credit';
String creditNetwork(Map<String, dynamic> card) =>
    card['cardNetwork'] == 'mastercard' ? 'Mastercard' : 'Visa';
double creditDebt(Map<String, dynamic> card) =>
    math.max(0.0, -numberValue(card['balance']));

// A card payment moves existing money to a liability, not to a second expense.
void linkCreditCardPayment(
  Map<String, dynamic> movement,
  List<Map<String, dynamic>> accounts,
  String cardId,
) {
  if (movement['type'] != 'expense' || movement['category'] != 'Pago TDC')
    return;
  final source = accounts
      .where((a) => a['id'] == movement['accountId'])
      .firstOrNull;
  if (isCreditCard(source)) {
    throw const FormatException(
      'Selecciona una cuenta bancaria para pagar la tarjeta.',
    );
  }
  final cards = accounts.where(isCreditCard).toList();
  if (cards.isEmpty) return;
  final card = cards.where((a) => a['id'] == cardId).firstOrNull;
  if (card == null)
    throw const FormatException('Selecciona la tarjeta que estás pagando.');
  if (source?['currency'] != card['currency']) {
    throw const FormatException(
      'La cuenta y la tarjeta deben tener la misma moneda.',
    );
  }
  movement.addAll({
    'type': 'transfer',
    'creditPayment': true,
    'category': 'Pago TDC',
    'targetAccountId': cardId,
    'targetAmount': movement['amount'],
    'targetCurrency': card['currency'],
    'debtId': '',
    'feeAmount': 0.0,
    'feeMode': 'none',
    'feeTreatment': 'deducted',
    'rate': 1.0,
    'paymentMethod': '',
  });
  movement.remove('debtInstallmentIndex');
  movement.remove('debtExchangeRate');
}

double creditAvailable(Map<String, dynamic> card) => math.max(
  0.0,
  moneyAdd(numberValue(card['creditLimit']), numberValue(card['balance'])),
);

void updateCreditMinimum(Map<String, dynamic> card) {
  card['creditMinimumDue'] = math.min(
    creditDebt(card),
    math.max(
      0.0,
      numberValue(card['creditMinimumBalance'] ?? card['creditMinimumDue']),
    ),
  );
}

void applyCreditMinimum(
  Map<String, dynamic> card,
  Map<String, dynamic> movement,
  int direction,
) {
  final cycle = card['creditMinimumCycle'] ?? '';
  if (direction > 0 && !movement.containsKey('creditMinimumCycle')) {
    movement['creditMinimumCycle'] = cycle;
  }
  if ((movement['creditMinimumCycle'] ?? '') == cycle) {
    // Keep the excess below zero so deleting an earlier payment is order-independent.
    final applied = direction > 0
        ? numberValue(movement['targetAmount'])
        : numberValue(movement['creditMinimumApplied']);
    final balance = numberValue(
      card['creditMinimumBalance'] ?? card['creditMinimumDue'],
    );
    card['creditMinimumBalance'] = moneySubtract(balance, applied * direction);
    if (direction > 0) movement['creditMinimumApplied'] = applied;
  }
  updateCreditMinimum(card);
}

DateTime nextCardDate(int day, DateTime now) {
  DateTime inMonth(int year, int month) =>
      DateTime(year, month, day.clamp(1, DateTime(year, month + 1, 0).day));
  final date = inMonth(now.year, now.month);
  return date.isBefore(DateTime(now.year, now.month, now.day))
      ? inMonth(now.year, now.month + 1)
      : date;
}

void validateCreditAccount(Map<String, dynamic> card) {
  if (!isCreditCard(card)) return;
  if (const ['bancamiga-rio', 'bancamiga-zona'].contains(card['cardDesign']) &&
      card['cardNetwork'] != 'mastercard') {
    throw const FormatException('Río y Zona Tech utilizan Mastercard.');
  }
  final limit = numberValue(card['creditLimit']);
  final debt = creditDebt(card);
  final minimum = numberValue(card['creditMinimumDue']);
  if (!limit.isFinite ||
      limit <= 0 ||
      limit > 999999999999 ||
      !numberValue(card['balance']).isFinite ||
      !minimum.isFinite ||
      minimum < 0 ||
      minimum > debt ||
      !const ['VES', 'USD'].contains(card['currency']) ||
      !const ['visa', 'mastercard'].contains(card['cardNetwork']) ||
      !creditCardTiersForNetwork(card['cardNetwork'].toString()).contains(
        card['cardNetwork'] == 'visa' && card['cardTier'] == 'Black'
            ? 'Signature'
            : card['cardTier'],
      ) ||
      !RegExp(r'^\d{0,4}$').hasMatch(card['lastFour']?.toString() ?? '') ||
      (card['lastFour']?.toString().isNotEmpty == true &&
          card['lastFour'].toString().length != 4) ||
      numberValue(card['cutDay']) < 1 ||
      numberValue(card['cutDay']) > 31 ||
      numberValue(card['dueDay']) < 1 ||
      numberValue(card['dueDay']) > 31) {
    throw const FormatException(
      'Revisa el límite, la deuda, el mínimo y las fechas de la tarjeta.',
    );
  }
  if (isIndexedCredit(card)) {
    creditUnitsFor(1, numberValue(card['creditIndex']));
    if (card['currency'] != 'VES' ||
        DateTime.tryParse(card['creditIndexDate']?.toString() ?? '') == null) {
      throw const FormatException(
        'Una tarjeta UVC requiere bolívares e IDI con fecha.',
      );
    }
  }
}

void validateCreditMovement(
  _RialAppState app,
  Map<String, dynamic> movement,
  Map<String, dynamic>? previous,
) {
  final source = app.accountById(movement['accountId'].toString());
  final target = app.accountById(movement['targetAccountId']?.toString() ?? '');
  Map<String, dynamic> beforeEdit(Map<String, dynamic> card) {
    if (isIndexedCredit(card) && previous != null) {
      final copy = Map<String, dynamic>.from(card);
      if (previous['accountId'] == card['id']) {
        applyIndexedCreditBalance(
          copy,
          previous,
          -movementDebitAmount(previous),
          -1,
          'Source',
          numberValue(copy['balance']),
        );
      }
      if (previous['type'] == 'transfer' &&
          previous['targetAccountId'] == card['id']) {
        applyIndexedCreditBalance(
          copy,
          previous,
          numberValue(previous['targetAmount']),
          -1,
          'Target',
          numberValue(copy['balance']),
        );
      }
      return copy;
    }
    var balance = numberValue(card['balance']);
    if (previous != null) {
      if (previous['accountId'] == card['id']) {
        balance = moneyAdd(
          balance,
          previous['type'] == 'income'
              ? -moneySubtract(
                  numberValue(previous['amount']),
                  numberValue(previous['feeAmount']),
                )
              : movementDebitAmount(previous),
        );
      }
      if (previous['type'] == 'transfer' &&
          previous['targetAccountId'] == card['id']) {
        balance = moneySubtract(balance, numberValue(previous['targetAmount']));
      }
    }
    return {...card, 'balance': balance};
  }

  if (isCreditCard(source)) {
    final withdrawal =
        movement['type'] == 'transfer' && isCreditWithdrawal(source, target);
    if ((movement['type'] != 'expense' && !withdrawal) ||
        (movement['debtId']?.toString().isNotEmpty ?? false)) {
      throw const FormatException(
        'Registra consumos con la tarjeta. Para abonarle, usa Pagar tarjeta.',
      );
    }
    if (withdrawal &&
        target?['provider'] != 'UBII' &&
        !allowsDirectCreditAdvance(source!)) {
      throw const FormatException(
        'Esta tarjeta no tiene avances directos habilitados.',
      );
    }
    if (withdrawal &&
        (movement['exchangeInput'] != 'received' ||
            movement['feeTreatment'] != 'deducted')) {
      throw const FormatException(
        'Indica cuánto salió de la tarjeta y cuánto recibiste.',
      );
    }
    if (moneyCents(movementDebitAmount(movement)) >
        moneyCents(creditAvailable(beforeEdit(source!)))) {
      throw const FormatException('El consumo supera el crédito disponible.');
    }
    movement['creditWithdrawal'] = withdrawal;
    prepareCreditIndex(source, movement, previous, 'Source');
  } else {
    movement.remove('creditWithdrawal');
    movement.remove('creditSourceUnits');
    movement.remove('creditSourceIndex');
  }
  if (movement['type'] == 'transfer' && isCreditCard(target)) {
    if (isCreditCard(source) || source?['currency'] != target!['currency']) {
      throw const FormatException(
        'Paga desde una cuenta de la misma moneda que la tarjeta.',
      );
    }
    if (moneyCents(numberValue(movement['amount'])) !=
        moneyCents(numberValue(movement['targetAmount']))) {
      throw const FormatException(
        'El abono y el monto enviado deben coincidir.',
      );
    }
    if (moneyCents(numberValue(movement['targetAmount'])) >
        moneyCents(creditDebt(beforeEdit(target)))) {
      throw const FormatException('El abono supera la deuda de la tarjeta.');
    }
    movement['creditPayment'] = true;
    prepareCreditIndex(target, movement, previous, 'Target');
    if (previous?['targetAccountId'] == movement['targetAccountId'] &&
        previous?['creditMinimumCycle'] != null) {
      movement['creditMinimumCycle'] = previous!['creditMinimumCycle'];
    } else {
      movement.remove('creditMinimumCycle');
    }
  } else {
    movement.remove('creditPayment');
    movement.remove('creditMinimumApplied');
    movement.remove('creditMinimumCycle');
    movement.remove('creditTargetUnits');
    movement.remove('creditTargetIndex');
  }
}

extension _CreditCardActions on _RialAppState {
  void openCreditEditor(BuildContext context, {Map<String, dynamic>? card}) =>
      pushPage(
        context,
        (_) => CreditCardEditor(app: this, cardId: card?['id']?.toString()),
      );

  void payCreditCard(BuildContext context, Map<String, dynamic> card) {
    if (creditDebt(card) <= 0) {
      showModernNotice(
        context,
        title: 'Tarjeta al día',
        message: 'No tienes un saldo pendiente por pagar.',
      );
      return;
    }
    final sources = usableAccounts()
        .where(
          (a) =>
              !isCreditCard(a) &&
              !isCestaticketFood(a) &&
              a['currency'] == card['currency'],
        )
        .toList();
    if (sources.isEmpty) {
      showModernNotice(
        context,
        title: 'Cuenta para el pago',
        message:
            'Agrega una cuenta en ${displayCurrency(card['currency'].toString())} para abonar a esta tarjeta.',
      );
      return;
    }
    showModernActionSheet(
      context,
      title: 'Pagar desde',
      actions: [
        for (final source in sources)
          ModernSheetAction(
            title: accountPrimaryName(source),
            subtitle: secureMoney(
              numberValue(source['balance']),
              source['currency'].toString(),
            ),
            icon: CupertinoIcons.creditcard,
            logoProvider: source['provider']?.toString(),
            onPressed: () => openMovementEditor(
              context,
              defaultType: 'transfer',
              defaultAccountId: source['id'].toString(),
              defaultTargetAccountId: card['id'].toString(),
              defaultDescription: 'Abono a ${accountPrimaryName(card)}',
              defaultAmount: math.min(
                creditDebt(card),
                numberValue(card['creditMinimumDue']) > 0
                    ? numberValue(card['creditMinimumDue'])
                    : creditDebt(card),
              ),
            ),
          ),
      ],
    );
  }
}

class HomeCreditCardsSection extends StatelessWidget {
  const HomeCreditCardsSection({super.key, required this.app});
  final _RialAppState app;

  @override
  Widget build(BuildContext context) {
    final cards = app.maps('accounts').where(isCreditCard).toList();
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('home-credit-cards'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          theme: app.theme,
          title: 'Tarjetas de crédito',
          action: 'Ver todas',
          onAction: () =>
              app.pushPage(context, (_) => CreditCardsPage(app: app)),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = cards.length == 1
                ? math.min(268.0, constraints.maxWidth)
                : math.min(268.0, constraints.maxWidth * .78);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Semantics(
                      button: true,
                      label: 'Abrir ${accountPrimaryName(cards[i])}',
                      child: PressFeedback(
                        key: ValueKey('home-credit-${cards[i]['id']}'),
                        onTap: () => app.pushPage(
                          context,
                          (_) => CreditCardDetailPage(
                            app: app,
                            cardId: cards[i]['id'].toString(),
                          ),
                        ),
                        child: SizedBox(
                          width: width,
                          child: BankCardFace(
                            account: cards[i],
                            app: app,
                            compact: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class CreditCardFace extends StatelessWidget {
  const CreditCardFace({super.key, required this.card, required this.app});
  final Map<String, dynamic> card;
  final _RialAppState app;
  @override
  Widget build(BuildContext context) => BankCardFace(
    key: const ValueKey('credit-card-face'),
    account: card,
    app: app,
  );
}

class CreditCardsPage extends StatelessWidget {
  const CreditCardsPage({super.key, required this.app});
  final _RialAppState app;
  @override
  Widget build(BuildContext context) {
    final cards = app.maps('accounts').where(isCreditCard).toList();
    return CupertinoPageScaffold(
      backgroundColor: app.theme.bg,
      navigationBar: RialNavigationBar(
        transitionBetweenRoutes: false,
        middle: const Text('Tarjetas de crédito'),
        trailing: CircleTool(
          theme: app.theme,
          icon: CupertinoIcons.plus,
          label: 'Agregar tarjeta',
          onTap: () => app.openCreditEditor(context),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (cards.isEmpty) ...[
              const SizedBox(height: 36),
              Icon(
                CupertinoIcons.creditcard,
                size: 52,
                color: app.theme.accent,
              ),
              const SizedBox(height: 20),
              Text(
                'Tus tarjetas, en un solo lugar',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: app.theme.ink,
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              PrimaryActionButton(
                theme: app.theme,
                label: 'Agregar tarjeta',
                onPressed: () => app.openCreditEditor(context),
              ),
            ],
            for (final card in cards)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: PressFeedback(
                  onTap: () => app.pushPage(
                    context,
                    (_) => CreditCardDetailPage(
                      app: app,
                      cardId: card['id'].toString(),
                    ),
                  ),
                  child: CreditCardFace(card: card, app: app),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CreditCardDetailPage extends StatefulWidget {
  const CreditCardDetailPage({
    super.key,
    required this.app,
    required this.cardId,
  });
  final _RialAppState app;
  final String cardId;
  @override
  State<CreditCardDetailPage> createState() => _CreditCardDetailPageState();
}

class _CreditCardDetailPageState extends State<CreditCardDetailPage> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  bool showDetails = false;
  @override
  Widget build(BuildContext context) {
    final app = widget.app, t = app.theme;
    final card = app.accountById(widget.cardId);
    if (card == null)
      return CupertinoPageScaffold(
        child: Center(
          child: Text('Tarjeta no disponible', style: TextStyle(color: t.ink)),
        ),
      );
    final currency = card['currency'].toString();
    final movements = sortedMovements(app.maps('movements')).where((m) {
      final date = parseMovementDate(m['date']?.toString());
      return (m['accountId'] == widget.cardId ||
              m['targetAccountId'] == widget.cardId) &&
          date.year == month.year &&
          date.month == month.month;
    }).toList();
    double sum(bool payments) => movements
        .where(
          (m) => payments
              ? m['targetAccountId'] == widget.cardId
              : m['accountId'] == widget.cardId,
        )
        .fold(
          0.0,
          (total, m) => moneyAdd(
            total,
            numberValue(m[payments ? 'targetAmount' : 'amount']),
          ),
        );
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: RialNavigationBar(
        transitionBetweenRoutes: false,
        middle: Text(accountPrimaryName(card)),
        trailing: CircleTool(
          theme: t,
          icon: CupertinoIcons.ellipsis,
          label: 'Opciones de tarjeta',
          onTap: () => showModernActionSheet(
            context,
            title: accountPrimaryName(card),
            actions: [
              ModernSheetAction(
                title: 'Editar tarjeta',
                icon: CupertinoIcons.pencil,
                onPressed: () => app.openCreditEditor(context, card: card),
              ),
              ModernSheetAction(
                title: 'Eliminar tarjeta',
                icon: CupertinoIcons.trash,
                destructive: true,
                onPressed: () => app.confirmDelete(
                  context,
                  'Eliminar tarjeta',
                  'También se eliminarán sus consumos y abonos.',
                  () {
                    app.deleteAccount(card);
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
              children: [
                CreditCardFace(card: card, app: app),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: AccountQuickActionButton(
                        theme: t,
                        label: 'Pagar',
                        icon: CupertinoIcons.arrow_down,
                        color: t.income,
                        onTap: () => app.payCreditCard(context, card),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AccountQuickActionButton(
                        theme: t,
                        label: 'Consumo',
                        icon: CupertinoIcons.arrow_up,
                        color: t.expense,
                        onTap: () => app.openMovementEditor(
                          context,
                          defaultAccountId: widget.cardId,
                          lockAccount: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SecondaryActionButton(
                  theme: t,
                  label: showDetails
                      ? 'Ocultar detalles'
                      : 'Detalles de la tarjeta',
                  onPressed: () => setState(() => showDetails = !showDetails),
                ),
                if (showDetails) ...[
                  Row(
                    children: [
                      Expanded(
                        child: AccountQuickActionButton(
                          theme: t,
                          label: 'Actualizar límite',
                          icon: CupertinoIcons.arrow_up_circle,
                          color: t.accent,
                          onTap: () =>
                              app.changeCreditLimit(context, widget.cardId),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AccountQuickActionButton(
                          theme: t,
                          label: 'Recarga / avance',
                          icon: CupertinoIcons.arrow_right_arrow_left,
                          color: t.accent,
                          onTap: () => app.withdrawCredit(context, card),
                        ),
                      ),
                    ],
                  ),
                  if (isIndexedCredit(card)) ...[
                    DebtDetailRow(
                      theme: t,
                      label: 'Deuda en UVC',
                      value: app.hideAmounts
                          ? '••••'
                          : formatNumberTruncated(
                              indexedCreditUnits(card).abs().toDouble(),
                              decimals: 8,
                            ),
                    ),
                    DebtDetailRow(
                      theme: t,
                      label: 'Disponible en UVC',
                      value: app.hideAmounts
                          ? '••••'
                          : formatNumberTruncated(
                              indexedCreditAvailableUnits(card).toDouble(),
                              decimals: 8,
                            ),
                    ),
                    DebtDetailRow(
                      theme: t,
                      label: card['creditIndexSource'] == 'BCV'
                          ? 'IDI BCV'
                          : 'Último IDI guardado',
                      value: compactDecimal(numberValue(card['creditIndex'])),
                    ),
                    Text(
                      'Valoración al ${formatDate(DateTime.parse(card['creditIndexDate'].toString()))}. No incluye intereses no registrados.',
                      style: TextStyle(
                        color: t.muted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    SecondaryActionButton(
                      theme: t,
                      label: 'Actualizar estado de cuenta',
                      onPressed: () =>
                          app.openCreditEditor(context, card: card),
                    ),
                  ],
                  DebtDetailRow(
                    theme: t,
                    label: 'Límite',
                    value: app.secureMoney(
                      numberValue(card['creditLimit']),
                      currency,
                    ),
                  ),
                  DebtDetailRow(
                    theme: t,
                    label: 'Mínimo pendiente',
                    value: app.secureMoney(
                      math.min(
                        creditDebt(card),
                        numberValue(card['creditMinimumDue']),
                      ),
                      currency,
                    ),
                  ),
                  DebtDetailRow(
                    theme: t,
                    label: 'Próximo corte',
                    value: formatDate(
                      nextCardDate(
                        numberValue(card['cutDay']).toInt(),
                        DateTime.now(),
                      ),
                    ),
                  ),
                  DebtDetailRow(
                    theme: t,
                    label: 'Fecha de pago',
                    value: formatDate(
                      nextCardDate(
                        numberValue(card['dueDay']).toInt(),
                        DateTime.now(),
                      ),
                    ),
                  ),
                  BankShortcutButton(app: app, account: card),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    CircleTool(
                      theme: t,
                      icon: CupertinoIcons.chevron_left,
                      label: 'Mes anterior',
                      onTap: () => setState(
                        () => month = DateTime(month.year, month.month - 1),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        calendarMonthTitle(month),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: t.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    CircleTool(
                      theme: t,
                      icon: CupertinoIcons.chevron_right,
                      label: 'Mes siguiente',
                      onTap: () => setState(
                        () => month = DateTime(month.year, month.month + 1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DebtDetailRow(
                  theme: t,
                  label: 'Abonos',
                  value: app.secureMoney(sum(true), currency),
                ),
                DebtDetailRow(
                  theme: t,
                  label: 'Consumos',
                  value: app.secureMoney(sum(false), currency),
                ),
                SectionHeader(theme: t, title: 'Movimientos'),
                if (movements.isEmpty)
                  EmptyCard(theme: t, text: 'Sin movimientos este mes'),
                for (final movement in movements)
                  MovementTile(app: app, movement: movement, showBcv: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CreditCardEditor extends StatefulWidget {
  const CreditCardEditor({super.key, required this.app, this.cardId});
  final _RialAppState app;
  final String? cardId;
  @override
  State<CreditCardEditor> createState() => _CreditCardEditorState();
}

class _CreditCardEditorState extends State<CreditCardEditor> {
  final label = TextEditingController(), lastFour = TextEditingController();
  final holder = TextEditingController();
  final limit = MoneyEditingController(),
      debt = MoneyEditingController(),
      minimum = MoneyEditingController();
  String provider = '0102', currency = 'VES', network = 'visa', tier = 'Gold';
  String design = 'auto';
  String basis = 'nominal';
  bool cashAdvance = false;
  final index = TextEditingController();
  final uvcDebt = TextEditingController(),
      uvcAvailable = TextEditingController();
  bool indexLoading = false;
  bool _uvcAmountsEdited = false;
  bool _minimumEdited = false;
  DateTime indexDate = DateTime.now();
  int cutDay = 15, dueDay = 30;
  @override
  void initState() {
    super.initState();
    final card = widget.app.accountById(widget.cardId ?? '');
    if (card != null) {
      label.text = card['label']?.toString() ?? '';
      lastFour.text = card['lastFour']?.toString() ?? '';
      holder.text = card['cardholderName']?.toString() ?? '';
      provider = card['provider'].toString();
      currency = card['currency'].toString();
      network = card['cardNetwork'].toString();
      tier = creditTier(card);
      design = card['cardDesign']?.toString() ?? 'auto';
      basis = card['creditBasis']?.toString() ?? 'nominal';
      cashAdvance = card['creditCashAdvance'] == true;
      index.text = card['creditIndex']?.toString() ?? '';
      indexDate =
          DateTime.tryParse(card['creditIndexDate']?.toString() ?? '') ??
          DateTime.now();
      cutDay = numberValue(card['cutDay']).toInt();
      dueDay = numberValue(card['dueDay']).toInt();
      limit.text = plain(numberValue(card['creditLimit']));
      debt.text = plain(creditDebt(card));
      minimum.text = plain(numberValue(card['creditMinimumDue']));
      if (isIndexedCredit(card)) {
        syncIndexedCard(card);
      }
    }
    if (basis == 'uvc') unawaited(loadIndex());
  }

  void syncIndexedCard(Map<String, dynamic> card) {
    index.text = card['creditIndex'].toString();
    indexDate =
        DateTime.tryParse(card['creditIndexDate']?.toString() ?? '') ??
        indexDate;
    final owed = -indexedCreditUnits(card);
    uvcDebt.text = (owed < Decimal.zero ? Decimal.zero : owed).toString();
    uvcAvailable.text = indexedCreditAvailableUnits(card).toString();
  }

  Future<void> loadIndex({bool force = false}) async {
    if (indexLoading) return;
    setState(() => indexLoading = true);
    await widget.app.refreshCreditIndex(force: force, forEditor: true);
    if (!mounted) return;
    final quote = widget.app.officialCreditIndex;
    final current = widget.app.accountById(widget.cardId ?? '');
    setState(() {
      indexLoading = false;
      if (!_uvcAmountsEdited && isIndexedCredit(current)) {
        syncIndexedCard(current!);
      } else if (quote != null &&
          (!_uvcAmountsEdited || parseAmount(index.text) <= 0)) {
        index.text = quote['index'].toString();
        indexDate = DateTime.parse(quote['date']);
      }
    });
  }

  @override
  void dispose() {
    for (final c in [
      label,
      lastFour,
      holder,
      limit,
      debt,
      minimum,
      index,
      uvcDebt,
      uvcAvailable,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.app.theme;
    final current = widget.app.accountById(widget.cardId ?? '');
    final preserveIndexedAmounts =
        basis == 'uvc' && !_uvcAmountsEdited && isIndexedCredit(current);
    Widget input(String title, TextEditingController controller) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: t.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          RField(
            key: ValueKey('credit-input-$title'),
            theme: t,
            controller: controller,
            placeholder:
                controller == label ||
                    controller == lastFour ||
                    controller == holder
                ? 'Opcional'
                : '0,00',
            onChanged: (_) => setState(() {
              if (controller == uvcDebt || controller == uvcAvailable) {
                _uvcAmountsEdited = true;
              }
              if (controller == minimum) _minimumEdited = true;
            }),
            inputFormatters: controller == lastFour
                ? [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ]
                : null,
            keyboardType: controller == label || controller == holder
                ? TextInputType.text
                : controller == lastFour
                ? TextInputType.number
                : const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
      ),
    );
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: RialNavigationBar(
        transitionBetweenRoutes: false,
        middle: Text(
          widget.cardId == null ? 'Nueva tarjeta' : 'Editar tarjeta',
        ),
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                CreditCardFace(
                  app: widget.app,
                  card: {
                    'kind': 'credit',
                    'provider': provider,
                    'label': label.text,
                    'cardNetwork': network,
                    'cardTier': tier,
                    'cardDesign': design,
                    'currency': currency,
                    'creditLimit': preserveIndexedAmounts
                        ? current!['creditLimit']
                        : basis == 'uvc'
                        ? (parseAmount(uvcDebt.text) +
                                  parseAmount(uvcAvailable.text)) *
                              parseAmount(index.text)
                        : parseAmount(limit.text),
                    'balance': preserveIndexedAmounts
                        ? current!['balance']
                        : basis == 'uvc'
                        ? -parseAmount(uvcDebt.text) * parseAmount(index.text)
                        : -parseAmount(debt.text),
                    'lastFour': lastFour.text,
                    'cardholderName': holder.text,
                  },
                ),
                const SizedBox(height: 20),
                OptionField(
                  theme: t,
                  label: 'Banco',
                  value: providerName(provider),
                  logoProvider: provider,
                  onTap: () => showModernActionSheet(
                    context,
                    title: 'Banco',
                    actions: [
                      for (final bank in banks)
                        ModernSheetAction(
                          title: bank.last,
                          icon: CupertinoIcons.building_2_fill,
                          logoProvider: bank.first,
                          selected: bank.first == provider,
                          onPressed: () => setState(() {
                            provider = bank.first;
                            design = 'auto';
                          }),
                        ),
                    ],
                  ),
                ),
                CardDesignPicker(
                  theme: t,
                  provider: provider,
                  value: design,
                  credit: true,
                  onChanged: (value) => setState(() {
                    design = value;
                    if (value == 'bnc-soytechno') cashAdvance = false;
                    for (final option in designsForBank(
                      provider,
                      credit: true,
                    )) {
                      if (option.id == value && option.network.isNotEmpty) {
                        network = option.network;
                        tier = creditTierForNetwork(network, tier);
                      }
                    }
                  }),
                ),
                AppPillSelector(
                  theme: t,
                  value: network,
                  items: [
                    if (design != 'bancamiga-rio' && design != 'bancamiga-zona')
                      const KindSelectorItem(
                        value: 'visa',
                        label: 'Visa',
                        icon: CupertinoIcons.creditcard,
                      ),
                    KindSelectorItem(
                      value: 'mastercard',
                      label: 'Mastercard',
                      icon: CupertinoIcons.creditcard,
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    network = v;
                    tier = creditTierForNetwork(network, tier);
                    for (final option in designsForBank(
                      provider,
                      credit: true,
                    )) {
                      if (option.id == design &&
                          option.network.isNotEmpty &&
                          option.network != v) {
                        design = 'auto';
                      }
                    }
                  }),
                ),
                const SizedBox(height: 12),
                OptionField(
                  key: const ValueKey('credit-tier-picker'),
                  theme: t,
                  label: 'Categoría de tarjeta',
                  value: tier,
                  icon: CupertinoIcons.creditcard,
                  onTap: () => pickValue(
                    context,
                    creditCardTiersForNetwork(network),
                    tier,
                    (v) => setState(() {
                      tier = v;
                      if (design == 'auto') design = 'generic';
                    }),
                  ),
                ),
                input('Nombre personalizado (opcional)', label),
                input('Titular de la tarjeta (opcional)', holder),
                input('Últimos 4 dígitos (opcional)', lastFour),
                OptionField(
                  theme: t,
                  label: 'Moneda',
                  value: displayCurrency(currency),
                  onTap: () => pickValue(
                    context,
                    ['Bolívares', 'Dólares'],
                    displayCurrency(currency),
                    (v) => setState(() {
                      currency = v == 'Bolívares' ? 'VES' : 'USD';
                      if (currency != 'VES') basis = 'nominal';
                    }),
                  ),
                ),
                OptionField(
                  theme: t,
                  label: 'Modalidad de la deuda',
                  value: basis == 'uvc'
                      ? 'Indexada en UVC'
                      : 'Nominal, sin indexación',
                  onTap: () => pickValue(
                    context,
                    ['Nominal, sin indexación', 'Indexada en UVC'],
                    basis == 'uvc'
                        ? 'Indexada en UVC'
                        : 'Nominal, sin indexación',
                    (value) {
                      setState(() {
                        basis = value == 'Indexada en UVC' ? 'uvc' : 'nominal';
                        if (basis == 'uvc') currency = 'VES';
                      });
                      if (basis == 'uvc') unawaited(loadIndex());
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    creditProductNote(provider, design),
                    style: TextStyle(
                      color: t.muted,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
                if (creditProductUrl(provider, design) != null)
                  SecondaryActionButton(
                    theme: t,
                    label: 'Consultar condiciones del banco',
                    onPressed: () => NativeStateStore.openUrl(
                      creditProductUrl(provider, design)!,
                    ),
                  ),
                if (basis == 'uvc') ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            indexLoading
                                ? 'Consultando IDI del BCV…'
                                : parseAmount(index.text) > 0
                                ? '${widget.app.officialCreditIndex != null ? 'IDI BCV' : 'Último IDI guardado'} · ${index.text.replaceAll('.', ',')}\n${formatDate(indexDate)}'
                                : 'IDI no disponible. Conéctate para actualizar.',
                            style: TextStyle(
                              color: t.muted,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ),
                        CircleTool(
                          theme: t,
                          icon: CupertinoIcons.refresh,
                          label: 'Actualizar IDI',
                          onTap: () => unawaited(loadIndex(force: true)),
                        ),
                      ],
                    ),
                  ),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Avances directos habilitados por el banco',
                        style: TextStyle(color: t.ink, fontSize: 14),
                      ),
                    ),
                    Semantics(
                      enabled: design != 'bnc-soytechno',
                      toggled: cashAdvance,
                      child: IgnorePointer(
                        ignoring: design == 'bnc-soytechno',
                        child: Opacity(
                          opacity: design == 'bnc-soytechno' ? .45 : 1,
                          child: AppSwitch(
                            theme: t,
                            value: cashAdvance,
                            onChanged: (v) => setState(() => cashAdvance = v),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (basis == 'uvc') ...[
                  input('Deuda actual en UVC', uvcDebt),
                  input('Disponible en UVC', uvcAvailable),
                ] else ...[
                  input('Límite de crédito', limit),
                  input('Deuda actual', debt),
                ],
                input('Mínimo pendiente del estado de cuenta', minimum),
                OptionField(
                  theme: t,
                  label: 'Día de corte',
                  value: '$cutDay',
                  icon: CupertinoIcons.calendar,
                  onTap: () => pickValue(
                    context,
                    [for (var i = 1; i <= 31; i++) '$i'],
                    '$cutDay',
                    (v) => setState(() => cutDay = int.parse(v)),
                  ),
                ),
                OptionField(
                  theme: t,
                  label: 'Día de pago',
                  value: '$dueDay',
                  icon: CupertinoIcons.calendar,
                  onTap: () => pickValue(
                    context,
                    [for (var i = 1; i <= 31; i++) '$i'],
                    '$dueDay',
                    (v) => setState(() => dueDay = int.parse(v)),
                  ),
                ),
                const SizedBox(height: 18),
                PrimaryActionButton(
                  theme: t,
                  label: 'Guardar tarjeta',
                  onPressed: save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void save() {
    final old = widget.app.accountById(widget.cardId ?? '');
    final card = <String, dynamic>{
      ...?old,
      'kind': 'credit',
      'provider': provider,
      'name': '${shortProviderName(provider)} $tier',
      'label': label.text.trim(),
      'cardNetwork': network,
      'cardTier': tier,
      'cardDesign': design,
      'creditBasis': basis,
      'creditCashAdvance': design != 'bnc-soytechno' && cashAdvance,
      if (basis == 'uvc') ...{
        'creditIndex': index.text,
        'creditIndexDate': DateTime(
          indexDate.year,
          indexDate.month,
          indexDate.day,
        ).toIso8601String(),
      },
      'lastFour': lastFour.text.trim(),
      'cardholderName': holder.text.trim(),
      'creditLimit': moneyRound(parseAmount(limit.text)),
      'balance': numberValue(old?['balance']) > 0 && parseAmount(debt.text) == 0
          ? numberValue(old?['balance'])
          : -moneyRound(parseAmount(debt.text)),
      'creditMinimumDue': moneyRound(parseAmount(minimum.text)),
      'currency': currency,
      'cutDay': cutDay,
      'dueDay': dueDay,
      'maintenanceEnabled': false,
      'bankAccountType': '',
    };
    try {
      if (basis == 'uvc') {
        if (indexLoading)
          throw const FormatException(
            'Espera a que termine la consulta del IDI.',
          );
        if (!_minimumEdited && isIndexedCredit(old)) {
          card['creditMinimumDue'] = old!['creditMinimumDue'];
        }
        if (!_uvcAmountsEdited && isIndexedCredit(old)) {
          // Cosmetic edits must preserve the live ledger, including refreshes
          // or payments that occurred while this editor was open.
          for (final key in [
            'creditLimit',
            'balance',
            'creditIndex',
            'creditIndexDate',
          ]) {
            card[key] = old![key];
          }
          refreshIndexedCreditBalance(card);
        } else {
          setCreditUvcAmounts(card, uvcDebt.text, uvcAvailable.text);
        }
        if (widget.app.officialCreditIndex != null) {
          applyOfficialCreditIndex(
            card,
            ((widget.app.state['creditIndexQuotes'] as List?) ?? [])
                .whereType<Map>()
                .map((q) => Map<String, dynamic>.from(q))
                .toList(),
            DateTime.now(),
          );
        }
      }
      if (parseAmount(debt.text) < 0)
        throw const FormatException('La deuda no puede ser negativa.');
      validateCreditAccount(card);
      if (old != null &&
          old['currency'] != currency &&
          widget.app
              .maps('movements')
              .any(
                (m) =>
                    m['accountId'] == old['id'] ||
                    m['targetAccountId'] == old['id'],
              )) {
        throw const FormatException(
          'Una tarjeta con movimientos conserva su moneda.',
        );
      }
      widget.app.saveAccount(
        card,
        editingId: widget.cardId,
        unitsProvided: basis == 'uvc',
      );
      Navigator.pop(context);
    } on FormatException catch (e) {
      showModernNotice(context, title: 'Revisa la tarjeta', message: e.message);
    }
  }
}
