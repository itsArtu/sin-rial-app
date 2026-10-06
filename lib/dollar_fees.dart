part of 'main.dart';

bool transferFeeMustBeAdded(
  Map<String, dynamic>? source,
  Map<String, dynamic>? target,
) =>
    source?['currency'] == 'VES' &&
    target?['currency'] == 'VES' &&
    isNationalBankAccount(source) &&
    isNationalBankAccount(target);

bool transferFeeIsDeducted(Map<String, dynamic> movement) =>
    movement['type'] == 'transfer' && movement['feeTreatment'] == 'deducted';

double movementDebitAmount(Map<String, dynamic> movement) => moneyAdd(
  numberValue(movement['amount']),
  transferFeeIsDeducted(movement) ? 0 : numberValue(movement['feeAmount']),
);

double transferDestinationAmount({
  required double amount,
  required double fee,
  required String treatment,
  required String sourceCurrency,
  required String targetCurrency,
  required double rate,
}) {
  if (!amount.isFinite || amount <= 0 || !fee.isFinite || fee < 0) {
    throw const FormatException('Monto o comision fuera de rango');
  }
  if (!['deducted', 'added'].contains(treatment)) {
    throw const FormatException('Forma de aplicar comision no valida');
  }
  final net = treatment == 'deducted' ? moneySubtract(amount, fee) : amount;
  if (!net.isFinite || net <= 0) {
    throw const FormatException(
      'La comision debe ser menor que el monto enviado',
    );
  }
  if (sourceCurrency == targetCurrency) return moneyRound(net);
  if (!rate.isFinite || rate <= 0) {
    throw const FormatException('Tasa de transferencia no valida');
  }
  final converted = sourceCurrency == 'USD'
      ? moneyConvert(net, rate)
      : moneyConvert(net, 1, rate);
  if (converted <= 0) {
    throw const FormatException('El monto recibido es demasiado pequeno');
  }
  return converted;
}

bool supportsDollarFees(Map<String, dynamic>? account) =>
    account != null && account['currency'] == 'USD' && !isCashAccount(account);

bool isCestaticketFood(Map<String, dynamic>? account) =>
    account?['provider'] == 'CESTATICKET' &&
    account?['benefitType'] != 'integral';

bool isCestaticketIntegral(Map<String, dynamic>? account) =>
    account?['provider'] == 'CESTATICKET' &&
    account?['benefitType'] == 'integral';

bool supportsTransferFees(Map<String, dynamic>? account) =>
    supportsDollarFees(account) || isCestaticketIntegral(account);

String dollarFeePreferenceKey(String type, String method) =>
    type == 'expense' && method == 'debit_card'
    ? 'cardFeePercent'
    : 'transferFeePercent';

double? dollarFeePercentForAccount(
  Map<String, dynamic>? account,
  String type,
  String method,
) {
  if (account == null) return null;
  final key = dollarFeePreferenceKey(type, method);
  if (account[key] != null) return numberValue(account[key]);
  if (key != 'cardFeePercent') return null;
  // User-confirmed card presets. Variable FX/crypto conversion costs stay manual.
  return switch (account['provider']) {
    'WALLY' => 2.85,
    'OKX' || 'BINANCE' || 'ZINLI' => 0,
    _ => null,
  };
}

double dollarOperationFee({
  required double amount,
  required String mode,
  required String unit,
  required double value,
}) {
  if (mode == 'none') return 0;
  if (!['auto', 'manual'].contains(mode) ||
      !['percent', 'amount'].contains(unit)) {
    throw const FormatException('Tipo de comision no valido');
  }
  if (!value.isFinite || value < 0 || (unit == 'percent' && value > 100)) {
    throw const FormatException('Comision fuera de rango');
  }
  return unit == 'percent'
      ? moneyConvert(amount, value, 100)
      : moneyRound(value);
}
