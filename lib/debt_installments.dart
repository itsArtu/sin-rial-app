part of 'main.dart';

List<String> debtScheduleDates(Map<String, dynamic> debt) {
  if (debt['hasDueDate'] == false) return const [];
  final stored = debtInstallmentDates(debt);
  final base = parseDateOnly(debt['dueDate']?.toString());
  return [
    for (var i = 0; i < debtInstallmentCount(debt); i++)
      if (i < stored.length)
        stored[i]
      else if (base.year != 9999)
        formatDate(
          addDebtFrequency(
            base,
            debt['paymentFrequency']?.toString() ?? 'Mensual',
            i,
          ),
        ),
  ];
}

// Explicit payments keep their chosen installment; older/general payments fill
// the oldest outstanding installment without changing recorded ledger amounts.
List<double> debtInstallmentPaidAmounts(Map<String, dynamic> debt) {
  final amounts = debtInstallmentAmounts(debt).map(moneyCents).toList();
  final paid = List<int>.filled(amounts.length, 0);
  var available = math.max(
    0,
    moneyCents(numberValue(debt['paidAmount'])) -
        moneyCents(debtInitialAmount(debt)),
  );
  for (final entry in (debt['installmentPayments'] as Map? ?? {}).values) {
    if (entry is! Map || entry['index'] is! int) continue;
    final index = entry['index'] as int;
    if (index < 0 || index >= amounts.length) continue;
    final value = math.min(
      available,
      math.min(
        amounts[index] - paid[index],
        math.max(0, moneyCents(numberValue(entry['amount']))),
      ),
    );
    paid[index] += value;
    available -= value;
  }
  for (var i = 0; i < amounts.length; i++) {
    final value = math.min(available, amounts[i] - paid[i]);
    paid[i] += value;
    available -= value;
  }
  return paid.map((v) => v / 100).toList();
}

List<double> debtInstallmentRemainingAmounts(Map<String, dynamic> debt) {
  final amounts = debtInstallmentAmounts(debt);
  final paid = debtInstallmentPaidAmounts(debt);
  return [
    for (var i = 0; i < amounts.length; i++) moneySubtract(amounts[i], paid[i]),
  ];
}

double debtMovementValue(
  Map<String, dynamic> movement,
  Map<String, dynamic> debt,
  double fallbackRate,
) {
  final currency = movement['currency']?.toString() ?? 'USD';
  final target = debt['currency']?.toString() ?? 'USD';
  final amount = numberValue(movement['amount']);
  final quote = numberValue(movement['debtExchangeRate']);
  return currency == target
      ? moneyRound(amount)
      : quote > 0
      ? moneyConvert(amount, 1, quote)
      : moneyRound(
          convert(
            amount,
            currency,
            target,
            numberValue(movement['rate']) > 0
                ? numberValue(movement['rate'])
                : fallbackRate,
          ),
        );
}

void validateInstallmentPayment(
  _RialAppState app,
  Map<String, dynamic> movement,
  Map<String, dynamic>? previous,
) {
  final index = movement['debtInstallmentIndex'];
  if (index == null) return;
  final original = app.debtById(movement['debtId']?.toString() ?? '');
  if (original == null ||
      movement['type'] !=
          (original['kind'] == 'receivable' ? 'income' : 'expense') ||
      !debtHasInstallments(original) ||
      index is! int ||
      index < 0 ||
      index >= debtInstallmentCount(original)) {
    throw const FormatException('Selecciona una cuota válida');
  }
  final debt = Map<String, dynamic>.from(original);
  if (previous != null && previous['debtId'] == debt['id']) {
    debt['paidAmount'] = math.max(
      0.0,
      moneySubtract(
        numberValue(debt['paidAmount']),
        previous.containsKey('debtAppliedAmount')
            ? numberValue(previous['debtAppliedAmount'])
            : debtMovementValue(previous, debt, app.rate),
      ),
    );
    debt['installmentPayments'] = Map<String, dynamic>.from(
      debt['installmentPayments'] as Map? ?? {},
    )..remove(previous['id']);
  }
  if (moneyCents(debtMovementValue(movement, debt, app.rate)) >
      moneyCents(debtInstallmentRemainingAmounts(debt)[index])) {
    throw const FormatException(
      'El monto supera el pendiente de esta cuota. Usa Abono general para pagar varias.',
    );
  }
}

bool canReceiveLoan(Map<String, dynamic> debt) =>
    debt['kind'] == 'payable' &&
    normalizeText(
          debt['partyType']?.toString() ?? debt['creditor']?.toString() ?? '',
        ) !=
        'cashea';

bool loanAccountMatches(
  Map<String, dynamic> debt,
  Map<String, dynamic> account,
) =>
    debt['currency'] == account['currency'] ||
    (debt['currency'] == 'USDT' &&
        account['currency'] == 'USD' &&
        (account['kind'] == 'wallet' ||
            isWalletProvider(account['provider']?.toString() ?? '')));

void chooseLoanAccount(
  BuildContext context,
  _RialAppState app,
  Map<String, dynamic> debt,
  ValueChanged<String> onSelect, {
  bool outgoing = false,
}) {
  final accounts = app
      .usableAccounts()
      .where((account) => loanAccountMatches(debt, account))
      .toList();
  if (accounts.isEmpty) {
    showModernNotice(
      context,
      title: 'Cuenta para el préstamo',
      message:
          'Agrega una cuenta en ${displayCurrency(debt['currency']?.toString() ?? 'USD')} para registrar el préstamo.',
    );
    return;
  }
  showModernActionSheet(
    context,
    title: outgoing ? 'Cuenta de origen' : 'Recibir en cuenta',
    actions: [
      for (final account in accounts)
        ModernSheetAction(
          icon: CupertinoIcons.creditcard,
          logoProvider: account['provider']?.toString(),
          title: accountPrimaryName(account),
          subtitle: accountSecondaryName(account),
          onPressed: () => onSelect(account['id'].toString()),
        ),
    ],
  );
}
