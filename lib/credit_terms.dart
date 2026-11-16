part of 'main.dart';

bool isIndexedCredit(Map<String, dynamic>? card) =>
    isCreditCard(card) && card?['creditBasis'] == 'uvc';

bool isCreditWithdrawal(
  Map<String, dynamic>? source,
  Map<String, dynamic>? target,
) =>
    isCreditCard(source) &&
    target != null &&
    !isCreditCard(target) &&
    source!['currency'] == target['currency'];

bool allowsDirectCreditAdvance(Map<String, dynamic> card) =>
    card['cardDesign'] != 'bnc-soytechno' && card['creditCashAdvance'] == true;

// These describe products, not eligibility or a tariff guaranteed for every card.
String creditProductNote(String provider, String design) {
  if (design == 'bnc-soytechno') {
    return 'BNC publica consumos sin comisión y no permite avances de efectivo en SoyTechno. Confirma la modalidad de tu contrato.';
  }
  if (provider == '0172') {
    return 'Bancamiga publica crédito rotativo en UVC. El ajuste por IDI es distinto de los intereses y comisiones.';
  }
  if (provider == '0102') {
    return 'La tarjeta digital BDV y Crédito Digital son productos distintos. Efectivoclave está disponible para tarjetas elegibles; registra el cargo real de la operación.';
  }
  return 'La modalidad, los intereses y los cargos dependen del contrato de esta tarjeta. No se aplican tarifas estimadas automáticamente.';
}

String? creditProductUrl(String provider, String design) => switch (provider) {
  '0172' => 'https://www.bancamiga.com/tarjeta-de-credito/',
  '0102' => 'https://www.bancodevenezuela.com/index.html%40p%3D22210.html',
  '0191' =>
    design == 'bnc-soytechno'
        ? 'https://www.bncenlinea.com/productos-y-servicios/tarjeta-soytechno'
        : 'https://www.bncenlinea.com/productos-y-servicios/Tasas-y-Tarifas-BNC',
  '0105' => 'https://www.mercantilbanco.com/personas/productos/tarjetas/tarjeta-credito-mastercard-mercantil',
  '0114' => 'https://www.bancaribe.com.ve/tarjeta-de-credito-bancaribe',
  _ => null,
};

Decimal creditUnitsFor(num bolivars, num index) {
  if (!index.isFinite || index <= 0 || index > 1000000000) {
    throw const FormatException(
      'Indica el índice IDI confirmado, no la tasa del dólar.',
    );
  }
  return (_decimal(bolivars) / _decimal(index)).toDecimal(
    scaleOnInfinitePrecision: 24,
  );
}

Decimal indexedCreditUnits(Map<String, dynamic> card) =>
    Decimal.tryParse(card['creditUnits']?.toString() ?? '') ??
    creditUnitsFor(
      numberValue(card['balance']),
      numberValue(card['creditIndex']),
    );

void refreshIndexedCreditBalance(Map<String, dynamic> card) {
  if (!isIndexedCredit(card)) return;
  card['balance'] = debtMoney(
    (indexedCreditUnits(card) * _decimal(numberValue(card['creditIndex'])))
        .toDouble(),
  );
  updateCreditMinimum(card);
}

void applyIndexedCreditBalance(
  Map<String, dynamic> card,
  Map<String, dynamic> movement,
  double delta,
  int direction,
  String side,
  double previousBalance,
) {
  if (!isIndexedCredit(card)) return;
  final units =
      Decimal.tryParse(card['creditUnits']?.toString() ?? '') ??
      creditUnitsFor(previousBalance, numberValue(card['creditIndex']));
  final key = 'credit${side}Units';
  var applied =
      Decimal.tryParse(movement[key]?.toString() ?? '') ??
      creditUnitsFor(
        delta,
        numberValue(
          movement['credit${side}Index'] ??
              card['creditBaseIndex'] ??
              card['creditIndex'],
        ),
      );
  // A complete payment clears fractional units, not only the displayed cents.
  if (direction > 0 &&
      side == 'Target' &&
      movement[key] == null &&
      numberValue(movement['creditTargetIndex']) ==
          numberValue(card['creditIndex']) &&
      moneyCents(delta) == moneyCents(-previousBalance)) {
    applied = -units;
  }
  if (direction > 0) movement[key] = applied.toString();
  card['creditUnits'] = (units + applied * Decimal.fromInt(direction))
      .toString();
  refreshIndexedCreditBalance(card);
}

void prepareCreditIndex(
  Map<String, dynamic> card,
  Map<String, dynamic> movement,
  Map<String, dynamic>? previous,
  String side,
) {
  final key = 'credit${side}Index';
  movement.remove('credit${side}Units');
  if (!isIndexedCredit(card)) {
    movement.remove(key);
    return;
  }
  final accountKey = side == 'Source' ? 'accountId' : 'targetAccountId';
  if (previous?[accountKey] == card['id'] &&
      previous?['date'] == movement['date'] &&
      previous?[key] != null) {
    movement[key] = previous![key];
    return;
  }
  final quoteDate = DateTime.tryParse(
    card['creditIndexDate']?.toString() ?? '',
  );
  final date = parseMovementDate(movement['date']?.toString());
  if (quoteDate == null || !isSameDate(quoteDate, date)) {
    throw const FormatException(
      'Confirma el IDI de la fecha del movimiento en la tarjeta antes de guardarlo.',
    );
  }
  movement[key] = card['creditIndex'];
}

Map<String, dynamic> cardWithNewLimit(
  Map<String, dynamic> card,
  double limit,
  DateTime now,
) {
  if (!limit.isFinite || limit <= 0 || limit > 999999999999) {
    throw const FormatException(
      'Indica el nuevo límite aprobado por el banco.',
    );
  }
  final result = Map<String, dynamic>.from(card);
  result['creditLimit'] = moneyRound(limit);
  if (moneyCents(limit) != moneyCents(numberValue(card['creditLimit']))) {
    result['creditLimitHistory'] = [
      ...((card['creditLimitHistory'] as List?) ?? []),
      {
        'from': card['creditLimit'],
        'to': moneyRound(limit),
        'date': now.toIso8601String(),
      },
    ];
  }
  return result;
}

extension _CreditTermsActions on _RialAppState {
  Future<void> changeCreditLimit(BuildContext context, String cardId) async {
    final card = accountById(cardId);
    if (card == null) return;
    final value = await showDecimalInputDialog(
      context,
      theme: theme,
      title: 'Nuevo límite aprobado',
      subtitle: displayCurrency(card['currency'].toString()),
      inputKey: const ValueKey('credit-limit-input'),
      initial: numberValue(card['creditLimit']),
      maximum: 999999999999,
    );
    if (value == null || !context.mounted) return;
    final current = accountById(cardId);
    if (current == null) return;
    try {
      final updated = cardWithNewLimit(current, value, DateTime.now());
      saveAccount(updated, editingId: cardId);
    } on FormatException catch (e) {
      showModernNotice(context, title: 'Revisa el límite', message: e.message);
    }
  }

  void withdrawCredit(BuildContext context, Map<String, dynamic> card) {
    final targets = usableAccounts()
        .where(
          (a) =>
              a['currency'] == card['currency'] &&
              !isCestaticketFood(a) &&
              (allowsDirectCreditAdvance(card) || a['provider'] == 'UBII'),
        )
        .toList();
    if (targets.isEmpty) {
      showModernNotice(
        context,
        title: 'Cuenta de destino',
        message: 'Agrega una cuenta Ubii de la misma moneda. Para registrar un avance directo, confirma su disponibilidad en las condiciones de la tarjeta.',
      );
      return;
    }
    showModernActionSheet(
      context,
      title: 'Registrar dinero recibido',
      actions: [
        for (final target in targets)
          ModernSheetAction(
            title: accountPrimaryName(target),
            icon: CupertinoIcons.arrow_down,
            logoProvider: target['provider']?.toString(),
            subtitle: target['provider'] == 'UBII'
                ? 'Recarga realizada en Ubii'
                : 'Avance realizado',
            onPressed: () => openMovementEditor(
              context,
              defaultType: 'transfer',
              defaultAccountId: card['id'].toString(),
              defaultTargetAccountId: target['id'].toString(),
              lockAccount: true,
              defaultDescription: target['provider'] == 'UBII'
                  ? 'Recarga Ubii'
                  : 'Avance de efectivo',
            ),
          ),
      ],
    );
  }
}
