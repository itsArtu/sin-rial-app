import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart' as charts;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:local_auth/local_auth.dart';

part 'finance_logic.dart';
part 'balance_trend.dart';
part 'movement_filters.dart';
part 'category_rules.dart';
part 'reminder_settings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RialBootstrap());
}

const _storeChannel = MethodChannel('rial/native_state');
const double _bootstrapBcvRate = 820.1018;
const Duration _lockGracePeriod = Duration(minutes: 2);
const _appVersionName = String.fromEnvironment(
  'FLUTTER_BUILD_NAME',
  defaultValue: '2.2.2',
);
const _appBuildNumber = int.fromEnvironment(
  'FLUTTER_BUILD_NUMBER',
  defaultValue: 66,
);
const _updateFeedUrl = String.fromEnvironment('SIN_RIAL_UPDATE_URL');
const _githubOwner = String.fromEnvironment(
  'SIN_RIAL_GITHUB_OWNER',
  defaultValue: 'itsArtu',
);
const _githubRepo = String.fromEnvironment(
  'SIN_RIAL_GITHUB_REPO',
  defaultValue: 'sin-rial-app',
);
const Duration _dismissedUpdateSnooze = Duration(hours: 12);

const List<List<String>> banks = [
  ['0102', 'Banco de Venezuela'],
  ['0104', 'Banco Venezolano de Crédito'],
  ['0105', 'Banco Mercantil'],
  ['0108', 'Banco Provincial'],
  ['0114', 'Bancaribe'],
  ['0115', 'Banco Exterior'],
  ['0128', 'Banco Caroní'],
  ['0134', 'Banesco'],
  ['0137', 'Sofitasa'],
  ['0138', 'Banco Plaza'],
  ['0146', 'Bangente'],
  ['0151', 'BFC Banco Fondo Común'],
  ['0156', '100% Banco'],
  ['0163', 'Banco del Tesoro'],
  ['0166', 'Banco Agrícola de Venezuela'],
  ['0168', 'Bancrecer'],
  ['0169', 'R4'],
  ['0171', 'Banco Activo'],
  ['0172', 'Bancamiga'],
  ['0174', 'Banplus'],
  ['0175', 'Banco Digital de los Trabajadores'],
  ['0177', 'BANFANB'],
  ['0191', 'Banco Nacional de Crédito'],
];

const List<List<String>> wallets = [
  ['WALLY', 'WallyTech'],
  ['BINANCE', 'Binance'],
  ['OKX', 'OKX'],
  ['ZINLI', 'Zinli'],
  ['KONTIGO', 'Kontigo'],
  ['PAYPAL', 'PayPal'],
  ['OTHER', 'Otra billetera'],
];

const List<String> budgetCategories = [
  'Casa',
  'Comida',
  'Wifi',
  'Barbería',
  'Suscripciones',
  'Pasaje',
  'Transporte',
  'Delivery',
  'Servicios',
  'Salud',
  'Educación',
  'Compras',
  'Recarga saldo',
  'Cuotas',
  'Comisiones bancarias',
  'Pago TDC',
  'La mamalona',
  'Ahorro',
  'Otro',
];

const List<String> payableDebtParties = [
  'Cashea',
  'Krece',
  'Weppa',
  'Alguien',
  'Otro',
];

const List<String> receivableDebtParties = ['Trabajo', 'Alguien', 'Otro'];

const List<String> debtInstallmentCountOptions = [
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '8',
  '10',
  '12',
  '18',
  '24',
];

class ThemeColorOption {
  const ThemeColorOption(this.key, this.label, this.light, this.dark);

  final String key;
  final String label;
  final Color light;
  final Color dark;

  Color colorFor(bool isDark) => isDark ? dark : light;
}

const List<ThemeColorOption> themeColorOptions = [
  ThemeColorOption('amber', 'Amarillo', Color(0xFFB98518), Color(0xFFE0AE55)),
  ThemeColorOption('indigo', 'Azul', Color(0xFF2463D4), Color(0xFF5B9AFF)),
  ThemeColorOption('cyan', 'Cian', Color(0xFF237C9A), Color(0xFF62C4E2)),
  ThemeColorOption('graphite', 'Grafito', Color(0xFF4D5663), Color(0xFF8D99A8)),
  ThemeColorOption('lime', 'Lima', Color(0xFF708D2B), Color(0xFFA7C957)),
  ThemeColorOption('violet', 'Morado', Color(0xFF853DC4), Color(0xFFB676E8)),
  ThemeColorOption('coral', 'Naranja', Color(0xFFC35C3E), Color(0xFFF28A68)),
  ThemeColorOption('wine', 'Rojo', Color(0xFFC41E1E), Color(0xFFE05252)),
  ThemeColorOption('rose', 'Rosa', Color(0xFFB84E68), Color(0xFFE9819A)),
  ThemeColorOption('teal', 'Turquesa', Color(0xFF247B7B), Color(0xFF55BDBD)),
  ThemeColorOption('emerald', 'Verde', Color(0xFF03674A), Color(0xFF03674A)),
];

ThemeColorOption themeColorByKey(String key) {
  final currentKey = switch (key) {
    'navy' || 'sky' => 'indigo',
    'magenta' => 'violet',
    'orange' => 'coral',
    'mint' => 'emerald',
    _ => key,
  };
  for (final option in themeColorOptions) {
    if (option.key == currentKey) return option;
  }
  return themeColorOptions.firstWhere((option) => option.key == 'emerald');
}

TextScaler appTextScaler(MediaQueryData media) {
  final compactWidthFactor = (media.size.shortestSide / 390.0).clamp(.90, 1.0);
  final systemFactor = media.textScaler.scale(1.0).clamp(.86, 1.06);
  final effectiveFactor = (compactWidthFactor * systemFactor).clamp(.86, 1.06);
  return TextScaler.linear(effectiveFactor.toDouble());
}

IconData categoryIcon(String category) {
  switch (normalizeText(category)) {
    case 'casa':
      return CupertinoIcons.house_fill;
    case 'comida':
      return CupertinoIcons.cart_fill;
    case 'wifi':
      return CupertinoIcons.wifi;
    case 'barberia':
      return CupertinoIcons.scissors;
    case 'suscripciones':
      return CupertinoIcons.play_rectangle_fill;
    case 'pasaje':
    case 'transporte':
      return CupertinoIcons.bus;
    case 'delivery':
      return CupertinoIcons.cube_box_fill;
    case 'servicios':
      return CupertinoIcons.lightbulb_fill;
    case 'salud':
      return CupertinoIcons.heart_fill;
    case 'educacion':
      return CupertinoIcons.book_fill;
    case 'compras':
      return CupertinoIcons.bag_fill;
    case 'recarga saldo':
      return CupertinoIcons.device_phone_portrait;
    case 'cuotas':
      return CupertinoIcons.calendar_badge_plus;
    case 'comisiones bancarias':
      return CupertinoIcons.percent;
    case 'pago tdc':
      return CupertinoIcons.creditcard_fill;
    case 'la mamalona':
      return material.Icons.two_wheeler;
    case 'ahorro':
      return CupertinoIcons.money_dollar_circle_fill;
    default:
      return CupertinoIcons.ellipsis_circle_fill;
  }
}

class RialBootstrap extends StatefulWidget {
  const RialBootstrap({super.key});

  @override
  State<RialBootstrap> createState() => _RialBootstrapState();
}

class _RialBootstrapState extends State<RialBootstrap> {
  late Future<Map<String, dynamic>> _state;

  @override
  void initState() {
    super.initState();
    _state = NativeStateStore.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _state,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const CupertinoApp(
            debugShowCheckedModeBanner: false,
            home: CupertinoPageScaffold(
              backgroundColor: Color(0xFF07080C),
              child: Center(child: CupertinoActivityIndicator(radius: 15)),
            ),
          );
        }
        return RialApp(initialState: data);
      },
    );
  }
}

class _SplitStatePayload {
  const _SplitStatePayload({
    required this.mainState,
    required this.changedParts,
    required this.allParts,
  });

  final String mainState;
  final Map<String, String> changedParts;
  final Map<String, String> allParts;
}

class NativeStateStore {
  static const List<String> _splitStateKeys = [
    'accounts',
    'movements',
    'debts',
    'budgets',
    'goals',
    'cards',
    'savingsFunds',
    'balanceAdjustments',
  ];

  static String? _lastMainStateJson;
  static final Map<String, String> _lastPartJson = {};
  static Future<void> _pendingSave = Future<void>.value();

  static Future<Map<String, dynamic>> load() async {
    try {
      final raw = await _storeChannel.invokeMethod<String>('readState');
      if (raw == null || raw.trim().isEmpty) return defaultState();
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final state = withDefaults(decoded.cast<String, dynamic>());
        _rememberMainStateOnly(state);
        return state;
      }
      return defaultState();
    } catch (_) {
      return defaultState();
    }
  }

  static Future<void> save(Map<String, dynamic> state) {
    final splitState = _encodeSplitState(state);
    // Capture now; serialize commits so a quick undo cannot be overwritten.
    _pendingSave = _pendingSave.then((_) => _writeSnapshot(splitState));
    return _pendingSave;
  }

  static Future<void> _writeSnapshot(_SplitStatePayload splitState) async {
    final changedParts = <String, String>{
      for (final entry in splitState.allParts.entries)
        if (_lastPartJson[entry.key] != entry.value) entry.key: entry.value,
    };
    if (splitState.mainState == _lastMainStateJson && changedParts.isEmpty) {
      return;
    }
    try {
      await _storeChannel.invokeMethod<void>('writeSplitState', {
        'state': splitState.mainState,
        'parts': changedParts,
      });
      _lastMainStateJson = splitState.mainState;
      _lastPartJson
        ..clear()
        ..addAll(splitState.allParts);
    } catch (_) {
      try {
        final snapshot = (jsonDecode(splitState.mainState) as Map)
            .cast<String, dynamic>();
        for (final part in splitState.allParts.entries) {
          snapshot[part.key] = jsonDecode(part.value);
        }
        await _storeChannel.invokeMethod<void>('writeState', {
          'state': jsonEncode(snapshot),
        });
        _rememberFullState(snapshot);
      } catch (_) {}
    }
  }

  static _SplitStatePayload _encodeSplitState(Map<String, dynamic> state) {
    final slim = Map<String, dynamic>.from(state);
    final allParts = <String, String>{};
    final changedParts = <String, String>{};
    for (final key in _splitStateKeys) {
      final raw = jsonEncode(slim.remove(key) ?? _emptySplitValue(key));
      allParts[key] = raw;
      if (_lastPartJson[key] != raw) changedParts[key] = raw;
    }
    return _SplitStatePayload(
      mainState: jsonEncode(slim),
      changedParts: changedParts,
      allParts: allParts,
    );
  }

  static Object _emptySplitValue(String key) =>
      key == 'savingsFunds' ? <String, dynamic>{} : <dynamic>[];

  static void _rememberMainStateOnly(Map<String, dynamic> state) {
    final slim = Map<String, dynamic>.from(state);
    for (final key in _splitStateKeys) {
      slim.remove(key);
    }
    _lastMainStateJson = jsonEncode(slim);
    _lastPartJson.clear();
  }

  static void _rememberFullState(Map<String, dynamic> state) {
    final splitState = _encodeSplitState(state);
    _lastMainStateJson = splitState.mainState;
    _lastPartJson
      ..clear()
      ..addAll(splitState.allParts);
  }

  static Future<void> scheduleDailyReminder({
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    try {
      await _pendingSave;
      await _storeChannel.invokeMethod<void>('scheduleDailyReminder', {
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
      });
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> dailyReminderStatus() async {
    try {
      final raw = await _storeChannel.invokeMapMethod<String, dynamic>(
        'dailyReminderStatus',
      );
      return raw ?? {};
    } catch (_) {
      return {};
    }
  }

  static Future<bool> openReminderSettings({required bool exact}) async {
    try {
      return await _storeChannel.invokeMethod<bool>('openReminderSettings', {
            'exact': exact,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> scheduleRateUpdate() async {
    try {
      return await _storeChannel.invokeMethod<bool>('scheduleRateUpdate') ??
          false;
    } catch (_) {}
    return false;
  }

  static Future<Map<String, dynamic>> workManagerStatus() async {
    try {
      final raw = await _storeChannel.invokeMethod<Map<dynamic, dynamic>>(
        'workManagerStatus',
      );
      return raw?.map((key, value) => MapEntry(key.toString(), value)) ??
          <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<bool> consumeScreenOff() async {
    try {
      return await _storeChannel.invokeMethod<bool>('consumeScreenOff') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> consumeLaunchAction() async {
    try {
      final action = await _storeChannel.invokeMethod<String>(
        'consumeLaunchAction',
      );
      final trimmed = action?.trim();
      return trimmed?.isEmpty == true ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setSystemBars({
    required bool dark,
    required int color,
  }) async {
    try {
      await _storeChannel.invokeMethod<void>('setSystemBars', {
        'dark': dark,
        'color': color,
      });
    } catch (_) {}
  }

  static Future<bool> openUrl(String url) async {
    try {
      return await _storeChannel.invokeMethod<bool>('openUrl', {'url': url}) ??
          false;
    } catch (_) {
      return false;
    }
  }
}

Map<String, dynamic> defaultState() {
  return {
    'rate': 0.0,
    'previousRate': 0.0,
    'lastRateDate': '',
    'lastRateMillis': 0,
    'rateUpdatedAt': '',
    'rateEffectiveDate': '',
    'eurRate': 0.0,
    'previousEurRate': 0.0,
    'eurRateUpdatedAt': '',
    'eurRateEffectiveDate': '',
    'usdtRate': 0.0,
    'previousUsdtRate': 0.0,
    'usdtRateUpdatedAt': '',
    'userName': '',
    'darkMode': true,
    'themeColor': 'emerald',
    'hideAmounts': false,
    'homeBalanceCurrency': 'USD',
    'homeBalanceMode': 'total',
    'homeBalanceChangePeriod': 'day',
    'lastUpdateCheckMillis': 0,
    'dismissedUpdateBuild': 0,
    'dismissedUpdateVersion': '',
    'dismissedUpdateMillis': 0,
    'dailyMovementReminderEnabled': true,
    'dailyReminderHour': 19,
    'dailyReminderMinute': 0,
    'lastMovementAccountId': '',
    'homeSections': <dynamic>['metrics', 'accounts', 'upcoming', 'recent'],
    'homeQuickActions': <dynamic>['movement', 'transfer', 'account'],
    'homeShortcutButtons': <dynamic>[
      'calculator',
      'movement',
      'accounts',
      'settings',
    ],
    'securitySetupComplete': false,
    'pinEnabled': false,
    'pinSalt': '',
    'pinHash': '',
    'pinLength': 0,
    'biometricEnabled': false,
    'onboardingComplete': false,
    'accounts': <dynamic>[],
    'movements': <dynamic>[],
    'debts': <dynamic>[],
    'budgets': <dynamic>[],
    'goals': <dynamic>[],
    'cards': <dynamic>[],
    'balanceAdjustments': <dynamic>[],
    'savingsFunds': <String, dynamic>{},
    'budgetSalary': 0.0,
    'budgetCurrency': 'USD',
    'budgetPeriodType': 'monthly',
    'budgetSavingsValue': 0.0,
    'budgetSavingsMode': 'amount',
  };
}

Map<String, dynamic> withDefaults(Map<String, dynamic> source) {
  final state = defaultState();
  state.addAll(source);
  for (final key in [
    'accounts',
    'movements',
    'debts',
    'budgets',
    'goals',
    'cards',
    'homeSections',
    'homeQuickActions',
    'homeShortcutButtons',
    'balanceAdjustments',
  ]) {
    state[key] = state[key] is List
        ? List<dynamic>.from(state[key])
        : <dynamic>[];
  }
  state['homeSections'] = sanitizeHomeSections(state['homeSections']);
  state['homeQuickActions'] = sanitizeHomeQuickActions(
    state['homeQuickActions'],
  );
  state['homeShortcutButtons'] = sanitizeHomeShortcutButtons(
    state['homeShortcutButtons'],
  );
  if (!const ['USD', 'EUR', 'USDT'].contains(state['homeBalanceCurrency'])) {
    state['homeBalanceCurrency'] = 'USD';
  }
  if (!const ['total', 'vesOnly'].contains(state['homeBalanceMode'])) {
    state['homeBalanceMode'] = 'total';
  }
  if (!const [
    'day',
    'week',
    'month',
  ].contains(state['homeBalanceChangePeriod'])) {
    state['homeBalanceChangePeriod'] = 'day';
  }
  if (state['budgetPeriodType'] != 'biweekly') {
    state['budgetPeriodType'] = 'monthly';
  }
  for (final item in state['accounts'] as List) {
    if (item is Map && isWalletProvider(item['provider']?.toString() ?? '')) {
      item['kind'] = 'wallet';
      item['currency'] = 'USD';
      item['initialCurrency'] = 'USD';
    }
  }
  final accounts = state['accounts'] as List;
  final nonZeroAccountPairs = accounts
      .whereType<Map>()
      .map((item) {
        final account = item.cast<String, dynamic>();
        if (numberValue(account['balance']).abs() <= .0001) return '';
        return '${account['provider']}|${account['currency']}';
      })
      .where((pair) => pair.isNotEmpty)
      .toSet();
  final seenAccounts = <String>{};
  accounts.removeWhere((item) {
    if (item is! Map) return true;
    final account = item.cast<String, dynamic>();
    final pair = '${account['provider']}|${account['currency']}';
    final balance = numberValue(account['balance']);
    if (balance.abs() <= .0001 &&
        (seenAccounts.contains(pair) || nonZeroAccountPairs.contains(pair))) {
      return true;
    }
    seenAccounts.add(pair);
    return false;
  });
  assignAccountColors(
    accounts.map((item) => (item as Map).cast<String, dynamic>()),
  );
  if (state['savingsFunds'] is! Map) {
    state['savingsFunds'] = <String, dynamic>{};
  }
  state['darkMode'] = state['darkMode'] == true;
  state['hideAmounts'] = state['hideAmounts'] == true;
  state['dailyMovementReminderEnabled'] =
      state['dailyMovementReminderEnabled'] != false;
  state['dailyReminderHour'] = numberValue(state['dailyReminderHour'])
      .round()
      .clamp(0, 23);
  state['dailyReminderMinute'] = numberValue(state['dailyReminderMinute'])
      .round()
      .clamp(0, 59);
  state['securitySetupComplete'] = state['securitySetupComplete'] == true;
  state['pinEnabled'] =
      state['pinEnabled'] == true &&
      (state['pinHash']?.toString().isNotEmpty ?? false) &&
      (state['pinSalt']?.toString().isNotEmpty ?? false);
  state['biometricEnabled'] = state['biometricEnabled'] == true;
  state['themeColor'] = themeColorByKey(state['themeColor']?.toString() ?? '')
      .key;
  final hasLegacyData =
      source.containsKey('userName') ||
      source.containsKey('accounts') ||
      source.containsKey('movements') ||
      source.containsKey('budgets') ||
      source.containsKey('debts') ||
      source.containsKey('goals');
  final hasUserData =
      (state['userName']?.toString().trim().isNotEmpty ?? false) ||
      (state['accounts'] as List).isNotEmpty ||
      (state['movements'] as List).isNotEmpty ||
      (state['budgets'] as List).isNotEmpty ||
      (state['debts'] as List).isNotEmpty ||
      (state['goals'] as List).isNotEmpty;
  if (!source.containsKey('onboardingComplete') &&
      (hasLegacyData || hasUserData)) {
    state['onboardingComplete'] = true;
  }
  return state;
}

class BcvRateResult {
  const BcvRateResult({
    required this.rate,
    required this.eurRate,
    required this.usdtRate,
    required this.effectiveDate,
    required this.updatedAt,
  });

  final double rate;
  final double eurRate;
  final double usdtRate;
  final String effectiveDate;
  final String updatedAt;
}

class BcvRateService {
  static String lastFailure = 'error';
  static String usdtFailure = 'error';
  static const _endpoint = 'https://bcv.today/api/v1/rate.json';
  static const _alcambioEndpoint = 'https://api.alcambio.app/graphql';

  static Future<BcvRateResult?> fetch() async {
    lastFailure = 'error';
    usdtFailure = 'error';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(_endpoint));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final data = decoded.cast<String, dynamic>();
      final rate = _extractUsdRate(data);
      if (!rate.isFinite || rate <= 0) return null;
      final eurRate = _extractNamedRate(data, 'EUR');
      final usdtRate = await _fetchUsdtRate(client);
      return BcvRateResult(
        rate: rate,
        eurRate: eurRate,
        usdtRate: usdtRate,
        effectiveDate:
            data['effective_date']?.toString().trim().isNotEmpty == true
            ? data['effective_date'].toString()
            : data['date']?.toString() ?? isoDate(DateTime.now()),
        updatedAt: data['updated_at']?.toString() ?? '',
      );
    } on SocketException {
      lastFailure = 'offline';
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<double> _fetchUsdtRate(HttpClient client) async {
    try {
      final request = await client.postUrl(Uri.parse(_alcambioEndpoint));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Sin Rial');
      request.write(
        jsonEncode({
          'query': 'query getBinanceP2PAverages { getBinanceP2PAverages { sellAverage buyAverage updatedAt } }',
          'variables': <String, dynamic>{},
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) return 0;
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      final decoded = jsonDecode(body);
      if (decoded is! Map) return 0;
      final data = decoded['data'];
      if (data is! Map) return 0;
      final averages = data['getBinanceP2PAverages'];
      if (averages is! Map) return 0;
      final sell = numberValue(averages['sellAverage']);
      final buy = numberValue(averages['buyAverage']);
      if (!sell.isFinite || !buy.isFinite) return 0;
      if (sell > 0 && buy > 0) return (sell + buy) / 2;
      return math.max(sell, buy);
    } on SocketException {
      usdtFailure = 'offline';
      return 0;
    } catch (_) {
      return 0;
    }
  }

  static double _extractUsdRate(Map<String, dynamic> data) {
    final named = _extractNamedRate(data, 'USD');
    if (named > 0) return named;
    final dollar = data['dollar'];
    if (dollar is Map) {
      final nested = dollar.cast<String, dynamic>();
      for (final key in ['rate', 'value', 'price']) {
        final value = numberValue(nested[key]);
        if (value > 0) return value;
      }
    }
    return 0;
  }

  static double _extractNamedRate(Map<String, dynamic> data, String code) {
    final direct = numberValue(data['USD']);
    if (code == 'USD' && direct > 0) return direct;
    final upper = numberValue(data[code]);
    if (upper > 0) return upper;
    final lower = numberValue(data[code.toLowerCase()]);
    if (lower > 0) return lower;
    final rates = data['rates'];
    if (rates is Map) {
      final item = rates[code] ?? rates[code.toLowerCase()];
      if (item is num) return item.toDouble();
      if (item is Map) {
        final nested = item.cast<String, dynamic>();
        for (final key in ['rate', 'value', 'price']) {
          final value = numberValue(nested[key]);
          if (value > 0) return value;
        }
      }
    }
    final currencies = data['currencies'];
    if (currencies is Map) {
      final item = currencies[code] ?? currencies[code.toLowerCase()];
      if (item is num) return item.toDouble();
      if (item is Map) {
        final nested = item.cast<String, dynamic>();
        for (final key in ['rate', 'value', 'price']) {
          final value = numberValue(nested[key]);
          if (value > 0) return value;
        }
      }
    }
    return 0;
  }
}

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.build,
    required this.apkUrl,
    this.releaseUrl = '',
    this.notes = '',
    this.title = '',
  });

  final String version;
  final int build;
  final String apkUrl;
  final String releaseUrl;
  final String notes;
  final String title;

  String get identity => build > 0 ? '$build' : version;

  bool get hasDownload =>
      apkUrl.trim().isNotEmpty || releaseUrl.trim().isNotEmpty;

  String get downloadUrl => apkUrl.trim().isNotEmpty ? apkUrl : releaseUrl;

  bool get isNewer {
    if (build > 0 && build != _appBuildNumber) {
      return build > _appBuildNumber;
    }
    return compareVersionNames(version, _appVersionName) > 0;
  }
}

class UpdateService {
  static bool get configured =>
      _updateFeedUrl.trim().isNotEmpty ||
      (_githubOwner.trim().isNotEmpty && _githubRepo.trim().isNotEmpty);

  static Uri? get endpoint {
    if (_updateFeedUrl.trim().isNotEmpty) {
      return Uri.tryParse(_updateFeedUrl.trim());
    }
    if (_githubOwner.trim().isNotEmpty && _githubRepo.trim().isNotEmpty) {
      return Uri.https(
        'api.github.com',
        '/repos/${_githubOwner.trim()}/${_githubRepo.trim()}/releases/latest',
      );
    }
    return null;
  }

  static Future<UpdateInfo?> fetch() async {
    final uri = endpoint;
    if (uri == null) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Sin Rial $_appVersionName',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final data = decoded.cast<String, dynamic>();
      if (data.containsKey('tag_name') || data.containsKey('assets')) {
        return _fromGitHubRelease(data);
      }
      return _fromManifest(data);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static UpdateInfo? _fromManifest(Map<String, dynamic> data) {
    final version = firstText(data, const ['version', 'version_name', 'name']);
    final build = numberValue(
      data['build'] ?? data['build_number'] ?? data['version_code'],
    ).round();
    final apkUrl = firstText(data, const [
      'apk_url',
      'download_url',
      'browser_download_url',
    ]);
    final releaseUrl = firstText(data, const [
      'release_url',
      'html_url',
      'page_url',
    ]);
    if (version.isEmpty && build <= 0) return null;
    if (apkUrl.isEmpty && releaseUrl.isEmpty) return null;
    return UpdateInfo(
      version: version.isEmpty ? _appVersionName : version,
      build: build,
      apkUrl: apkUrl,
      releaseUrl: releaseUrl,
      notes: firstText(data, const ['notes', 'body', 'changelog']),
      title: firstText(data, const ['title', 'release_name']),
    );
  }

  static UpdateInfo? _fromGitHubRelease(Map<String, dynamic> data) {
    final tag = data['tag_name']?.toString().trim() ?? '';
    final parsed = parseReleaseVersion(tag);
    final assets = data['assets'];
    Map<String, dynamic>? apkAsset;
    var apkScore = -1;
    if (assets is List) {
      for (final item in assets) {
        if (item is! Map) continue;
        final asset = item.cast<String, dynamic>();
        final name = asset['name']?.toString().toLowerCase() ?? '';
        final url = asset['browser_download_url']?.toString().trim() ?? '';
        if (name.endsWith('.apk') && url.isNotEmpty) {
          var score = 1;
          if (parsed.version.isNotEmpty &&
              name.contains(parsed.version.toLowerCase())) {
            score += 100;
          }
          if (parsed.build > 0 && name.contains(parsed.build.toString())) {
            score += 80;
          }
          if (name.contains('universal')) score += 10;
          if (name.contains('old') || name.contains('previous')) score -= 20;
          if (score > apkScore) {
            apkScore = score;
            apkAsset = asset;
          }
          if (score >= 181) break;
        }
      }
    }
    final apkUrl = apkAsset == null
        ? ''
        : apkAsset['browser_download_url']?.toString().trim() ?? '';
    final releaseUrl = data['html_url']?.toString().trim() ?? '';
    if (tag.isEmpty && apkUrl.isEmpty && releaseUrl.isEmpty) return null;
    return UpdateInfo(
      version: parsed.version.isEmpty ? tag : parsed.version,
      build: parsed.build,
      apkUrl: apkUrl,
      releaseUrl: releaseUrl,
      notes: data['body']?.toString().trim() ?? '',
      title: data['name']?.toString().trim() ?? tag,
    );
  }
}

bool isWalletProvider(String provider) {
  return wallets.any((wallet) => wallet.first == provider);
}

class RialApp extends StatefulWidget {
  const RialApp({super.key, required this.initialState});

  final Map<String, dynamic> initialState;

  @override
  State<RialApp> createState() => _RialAppState();
}

class _RialAppState extends State<RialApp> with WidgetsBindingObserver {
  late Map<String, dynamic> state;
  int tab = 0;
  late final PageController _pageController;
  final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>();
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  final rand = math.Random();
  final LocalAuthentication localAuth = LocalAuthentication();
  Timer? rateRefreshTimer;
  bool openAccountAfterOnboarding = false;
  bool rateLoading = false;
  bool updateChecking = false;
  bool updatePromptVisible = false;
  bool locked = false;
  DateTime? backgroundedAt;
  String? pendingLaunchAction;
  final List<_UndoEntry> _undoHistory = [];
  Timer? _undoTimer;
  bool _showUndo = false;

  bool get canUndo => _undoHistory.isNotEmpty;

  void undoableMutation(
    String label,
    Map<String, Set<String>> records,
    VoidCallback action,
  ) {
    Map<String, dynamic>? lookup(String key, String id) {
      for (final item in rawList(key)) {
        if (item is Map && item['id'] == id)
          return item.cast<String, dynamic>();
      }
      return null;
    }

    final before = <(String, String), Map<String, dynamic>?>{};
    final positions = <(String, String), int>{};
    for (final entry in records.entries) {
      for (final id in entry.value.where((id) => id.isNotEmpty)) {
        before[(entry.key, id)] = _copyRecord(lookup(entry.key, id));
        positions[(entry.key, id)] = rawList(entry.key)
            .indexWhere((item) => item is Map && item['id'] == id);
      }
    }
    mutate(() {
      action();
      final changes = <_UndoChange>[];
      for (final entry in before.entries) {
        final after = _copyRecord(lookup(entry.key.$1, entry.key.$2));
        if (jsonEncode(entry.value) != jsonEncode(after)) {
          changes.add(
            _UndoChange(
              entry.key.$1,
              entry.key.$2,
              entry.value,
              after,
              positions[entry.key] ?? -1,
            ),
          );
        }
      }
      if (changes.isNotEmpty) {
        _undoHistory.add(_UndoEntry(label, changes));
        if (_undoHistory.length > 20) _undoHistory.removeAt(0);
        _showUndo = true;
      }
    });
    _undoTimer?.cancel();
    _undoTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _showUndo = false);
    });
  }

  bool undoLastOperation() {
    if (!canUndo) return false;
    final entry = _undoHistory.last;
    for (final change in entry.changes) {
      final current = maps(change.collection)
          .where((item) => item['id'] == change.id)
          .firstOrNull;
      if (jsonEncode(current) != jsonEncode(change.after)) {
        _undoHistory.clear();
        setState(() => _showUndo = false);
        return false;
      }
    }
    _undoTimer?.cancel();
    mutate(() {
      _undoHistory.removeLast();
      for (final change in entry.changes) {
        final list = rawList(change.collection);
        final index = list.indexWhere(
          (item) => item is Map && item['id'] == change.id,
        );
        if (change.before == null) {
          if (index >= 0) list.removeAt(index);
        } else if (index >= 0) {
          list[index] = _copyRecord(change.before);
        } else {
          list.insert(
            change.index.clamp(0, list.length),
            _copyRecord(change.before),
          );
        }
      }
      _showUndo = false;
    });
    return true;
  }

  @override
  void initState() {
    super.initState();
    state = withDefaults(widget.initialState);
    locked = stateHasSecurity(state);
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    scheduleDailyReminderFromState();
    unawaited(NativeStateStore.scheduleRateUpdate());
    unawaited(refreshRateIfNeeded());
    unawaited(checkNativeLaunchAction());
    rateRefreshTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => unawaited(refreshRateIfNeeded()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    rateRefreshTimer?.cancel();
    _undoTimer?.cancel();
    _pageController.dispose();
    revision.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (!securityEnabled ||
        state['onboardingComplete'] != true ||
        !securitySetupComplete) {
      if (lifecycleState == AppLifecycleState.resumed) {
        backgroundedAt = null;
        unawaited(NativeStateStore.consumeScreenOff());
        unawaited(checkNativeLaunchAction());
        unawaited(refreshRateIfNeeded());
      }
      return;
    }
    if (lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.hidden) {
      backgroundedAt = DateTime.now();
      return;
    }
    if (lifecycleState == AppLifecycleState.resumed) {
      unawaited(_resumeAfterSecurityCheck());
      unawaited(checkNativeLaunchAction());
    }
  }

  Future<void> _resumeAfterSecurityCheck() async {
    await _lockIfNeededAfterResume();
    if (!mounted || locked) return;
    await refreshRateIfNeeded();
  }

  Future<void> _lockIfNeededAfterResume() async {
    final screenWasOff = await NativeStateStore.consumeScreenOff();
    if (!mounted) return;
    final wentIdleTooLong =
        backgroundedAt != null &&
        DateTime.now().difference(backgroundedAt!) >= _lockGracePeriod;
    backgroundedAt = null;
    if (screenWasOff || wentIdleTooLong) {
      _closeTransientRoutes();
      setState(() => locked = true);
    }
  }

  Future<void> checkNativeLaunchAction() async {
    final action = await NativeStateStore.consumeLaunchAction();
    if (!mounted || action == null) return;
    if (!['expense', 'income', 'transfer', 'account'].contains(action)) return;
    setState(() => pendingLaunchAction = action);
  }

  RTheme get theme => RTheme(dark, themeColorKey);
  bool get dark => state['darkMode'] == true;
  String get themeColorKey => state['themeColor']?.toString() ?? 'emerald';
  double get rate {
    final current = numberValue(state['rate']);
    if (current > 0) return current;
    final previous = numberValue(state['previousRate']);
    if (previous > 0) return previous;
    return _bootstrapBcvRate;
  }

  double get eurRate {
    final current = numberValue(state['eurRate']);
    if (current > 0) return current;
    final previous = numberValue(state['previousEurRate']);
    return previous > 0 ? previous : 0;
  }

  double get usdtRate {
    final current = numberValue(state['usdtRate']);
    if (current > 0) return current;
    final previous = numberValue(state['previousUsdtRate']);
    if (previous > 0) return previous;
    return 0;
  }

  String get homeBalanceCurrency =>
      state['homeBalanceCurrency']?.toString() ?? 'USD';
  String get homeBalanceMode => state['homeBalanceMode']?.toString() ?? 'total';
  String get homeBalanceChangePeriod =>
      state['homeBalanceChangePeriod']?.toString() ?? 'day';

  bool get hideAmounts => state['hideAmounts'] == true;
  bool get dailyMovementReminderEnabled =>
      state['dailyMovementReminderEnabled'] != false;
  int get dailyReminderHour =>
      numberValue(state['dailyReminderHour']).round().clamp(0, 23).toInt();
  int get dailyReminderMinute =>
      numberValue(state['dailyReminderMinute']).round().clamp(0, 59).toInt();
  String get dailyReminderLabel => timeOnlyLabel(
    DateTime(2000, 1, 1, dailyReminderHour, dailyReminderMinute),
  );
  bool get securitySetupComplete => state['securitySetupComplete'] == true;
  bool get pinEnabled =>
      state['pinEnabled'] == true &&
      (state['pinHash']?.toString().isNotEmpty ?? false) &&
      (state['pinSalt']?.toString().isNotEmpty ?? false);
  int get configuredPinLength =>
      numberValue(state['pinLength']).round().clamp(0, 6).toInt();
  bool get biometricEnabled => state['biometricEnabled'] == true;
  bool get securityEnabled => pinEnabled || biometricEnabled;
  bool get securitySetupRequired =>
      state['onboardingComplete'] == true && !securitySetupComplete;

  String secureMoney(double value, String currency) {
    return hideAmounts ? hiddenMoney(currency) : money(value, currency);
  }

  String secureSignedMoney(double value, String currency, String sign) {
    return hideAmounts
        ? hiddenMoney(currency, sign: sign)
        : '$sign${money(value, currency)}';
  }

  List<dynamic> rawList(String key) {
    final value = state[key];
    if (value is List) return value;
    final created = <dynamic>[];
    state[key] = created;
    return created;
  }

  List<Map<String, dynamic>> maps(String key) {
    return rawList(key)
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  Map<String, dynamic>? accountById(String id) {
    for (final item in rawList('accounts')) {
      if (item is Map && item['id'] == id) return item.cast<String, dynamic>();
    }
    return null;
  }

  Map<String, dynamic>? debtById(String id) {
    for (final item in rawList('debts')) {
      if (item is Map && item['id'] == id) return item.cast<String, dynamic>();
    }
    return null;
  }

  Map<String, dynamic>? movementById(String id) {
    for (final item in rawList('movements')) {
      if (item is Map && item['id'] == id) return item.cast<String, dynamic>();
    }
    return null;
  }

  void mutate(VoidCallback action) {
    setState(action);
    revision.value++;
    unawaited(NativeStateStore.save(state));
  }

  void scheduleDailyReminderFromState() {
    unawaited(
      NativeStateStore.scheduleDailyReminder(
        enabled: dailyMovementReminderEnabled,
        hour: dailyReminderHour,
        minute: dailyReminderMinute,
      ),
    );
  }

  Future<void> pickDailyReminderTime(BuildContext context) async {
    final picked = await pickModernTime(
      context: context,
      theme: theme,
      initial: DateTime(2000, 1, 1, dailyReminderHour, dailyReminderMinute),
    );
    if (picked == null) return;
    mutate(() {
      state['dailyReminderHour'] = picked.hour;
      state['dailyReminderMinute'] = picked.minute;
      state['dailyMovementReminderEnabled'] = true;
    });
    scheduleDailyReminderFromState();
  }

  void setTab(int index) {
    if (index == tab) return;
    setState(() => tab = index);
    if (_pageController.hasClients) {
      unawaited(
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  Future<T?> pushPage<T>(BuildContext context, WidgetBuilder builder) {
    return Navigator.of(context, rootNavigator: true).push<T>(
      FluidPageRoute<T>(
        builder: (_) => ReactiveRoutePage(app: this, builder: builder),
      ),
    );
  }

  void resetAllData() {
    _undoHistory.clear();
    _undoTimer?.cancel();
    _showUndo = false;
    final keepDark = dark;
    final keepColor = themeColorKey;
    final keepName = state['userName']?.toString() ?? '';
    final keepHideAmounts = hideAmounts;
    final keepSecuritySetupComplete = securitySetupComplete;
    final keepPinEnabled = state['pinEnabled'] == true;
    final keepPinSalt = state['pinSalt']?.toString() ?? '';
    final keepPinHash = state['pinHash']?.toString() ?? '';
    final keepPinLength = numberValue(state['pinLength']).round();
    final keepBiometricEnabled = biometricEnabled;
    final keepRate = rate;
    final keepPreviousRate = numberValue(state['previousRate']);
    final keepLastRateDate = state['lastRateDate']?.toString() ?? '';
    final keepRateEffectiveDate = state['rateEffectiveDate']?.toString() ?? '';
    final keepRateUpdatedAt = state['rateUpdatedAt']?.toString() ?? '';
    final keepEurRate = eurRate;
    final keepPreviousEurRate = numberValue(state['previousEurRate']);
    final keepEurRateEffectiveDate =
        state['eurRateEffectiveDate']?.toString() ?? '';
    final keepEurRateUpdatedAt = state['eurRateUpdatedAt']?.toString() ?? '';
    final keepUsdtRate = usdtRate;
    final keepPreviousUsdtRate = numberValue(state['previousUsdtRate']);
    final keepUsdtRateUpdatedAt = state['usdtRateUpdatedAt']?.toString() ?? '';
    final keepLastRateMillis = numberValue(state['lastRateMillis']);
    setState(() {
      state = defaultState();
      state['userName'] = keepName;
      state['darkMode'] = keepDark;
      state['themeColor'] = keepColor;
      state['hideAmounts'] = keepHideAmounts;
      state['securitySetupComplete'] = keepSecuritySetupComplete;
      state['pinEnabled'] = keepPinEnabled;
      state['pinSalt'] = keepPinSalt;
      state['pinHash'] = keepPinHash;
      state['pinLength'] = keepPinLength;
      state['biometricEnabled'] = keepBiometricEnabled;
      state['rate'] = keepRate;
      state['previousRate'] = keepPreviousRate > 0
          ? keepPreviousRate
          : keepRate;
      state['lastRateDate'] = keepLastRateDate;
      state['rateEffectiveDate'] = keepRateEffectiveDate;
      state['rateUpdatedAt'] = keepRateUpdatedAt;
      state['eurRate'] = keepEurRate;
      state['previousEurRate'] = keepPreviousEurRate > 0
          ? keepPreviousEurRate
          : keepEurRate;
      state['eurRateEffectiveDate'] = keepEurRateEffectiveDate;
      state['eurRateUpdatedAt'] = keepEurRateUpdatedAt;
      state['usdtRate'] = keepUsdtRate;
      state['previousUsdtRate'] = keepPreviousUsdtRate > 0
          ? keepPreviousUsdtRate
          : keepUsdtRate;
      state['usdtRateUpdatedAt'] = keepUsdtRateUpdatedAt;
      state['lastRateMillis'] = keepLastRateMillis.round();
      state['onboardingComplete'] = true;
      tab = 0;
    });
    revision.value++;
    if (_pageController.hasClients) _pageController.jumpToPage(0);
    unawaited(NativeStateStore.save(state));
    unawaited(refreshRate(manual: false, force: true));
  }

  Future<void> refreshRateIfNeeded({bool checkForUpdates = true}) async {
    try {
      final raw = await _storeChannel.invokeMethod<String>('readState');
      if (raw != null && mounted) {
        final saved = jsonDecode(raw);
        if (saved is Map &&
            numberValue(saved['rateLastAttemptMillis']) >
                numberValue(state['rateLastAttemptMillis'])) {
          setState(() {
            for (final entry in saved.entries) {
              final key = entry.key.toString();
              if (rateStateKeys.contains(key)) state[key] = entry.value;
            }
            revision.value++;
          });
        }
      }
    } catch (_) {}
    final effectiveDate = state['rateEffectiveDate']?.toString();
    final legacyDate = state['lastRateDate']?.toString();
    final expected = expectedRateDateKey(DateTime.now());
    final storedRate = numberValue(state['rate']);
    final shouldRefresh =
        storedRate <= 0 ||
        (storedRate - 36.5).abs() < .0001 ||
        (effectiveDate == null || effectiveDate.isEmpty
            ? legacyDate != expected
            : effectiveDate != expected);
    if (shouldRefresh) {
      await refreshRate(manual: false, checkForUpdates: checkForUpdates);
    }
  }

  Future<void> refreshRate({
    bool manual = false,
    bool force = false,
    bool checkForUpdates = true,
  }) async {
    if (rateLoading) return;
    if (mounted) setState(() => rateLoading = true);
    final result = await BcvRateService.fetch();
    if (!mounted) return;
    if (result != null) {
      mutate(() {
        final oldRate = numberValue(state['rate']);
        if (oldRate > 0 && (oldRate - result.rate).abs() > .0001) {
          state['previousRate'] = oldRate;
        }
        final oldEurRate = numberValue(state['eurRate']);
        if (result.eurRate > 0 &&
            oldEurRate > 0 &&
            (oldEurRate - result.eurRate).abs() > .0001) {
          state['previousEurRate'] = oldEurRate;
        }
        state['rate'] = result.rate;
        state['lastRateDate'] = result.effectiveDate;
        state['rateEffectiveDate'] = result.effectiveDate;
        state['rateUpdatedAt'] = result.updatedAt;
        if (result.eurRate > 0) {
          state['eurRate'] = result.eurRate;
          state['eurRateEffectiveDate'] = result.effectiveDate;
          state['eurRateUpdatedAt'] = result.updatedAt;
        }
        final oldUsdtRate = numberValue(state['usdtRate']);
        if (result.usdtRate > 0 &&
            oldUsdtRate > 0 &&
            (oldUsdtRate - result.usdtRate).abs() > .0001) {
          state['previousUsdtRate'] = oldUsdtRate;
        }
        if (result.usdtRate > 0) {
          state['usdtRate'] = result.usdtRate;
          state['usdtRateUpdatedAt'] = result.updatedAt;
        }
        state['lastRateMillis'] = DateTime.now().millisecondsSinceEpoch;
        state['rateLastAttemptMillis'] = DateTime.now().millisecondsSinceEpoch;
        state['rateFetchStatus'] = 'ok';
        state['eurRateFetchStatus'] = result.eurRate > 0 ? 'ok' : 'error';
        state['usdtRateFetchStatus'] = result.usdtRate > 0
            ? 'ok'
            : BcvRateService.usdtFailure;
        if (result.eurRate > 0)
          state['eurLastRateMillis'] = state['lastRateMillis'];
        if (result.usdtRate > 0)
          state['usdtLastRateMillis'] = state['lastRateMillis'];
      });
    } else {
      mutate(() {
        state['rateLastAttemptMillis'] = DateTime.now().millisecondsSinceEpoch;
        for (final key in [
          'rateFetchStatus',
          'eurRateFetchStatus',
          'usdtRateFetchStatus',
        ]) {
          state[key] = BcvRateService.lastFailure;
        }
      });
    }
    if (mounted) setState(() => rateLoading = false);
    if (result != null && checkForUpdates) queueForegroundUpdateCheck();
  }

  void queueForegroundUpdateCheck() {
    final context = rootNavigatorKey.currentContext;
    if (context == null || locked || updateChecking) return;
    unawaited(checkForReleaseUpdate(context));
  }

  Future<void> openUpdateDownload(
    BuildContext context,
    UpdateInfo update,
  ) async {
    updatePromptVisible = false;
    final opened = await NativeStateStore.openUrl(update.downloadUrl);
    if (!context.mounted) return;
    if (!opened) {
      showModernNotice(
        context,
        title: 'No se pudo abrir',
        message: 'Abre manualmente este enlace: ${update.downloadUrl}',
      );
    }
  }

  Future<void> checkForReleaseUpdate(
    BuildContext context, {
    bool manual = false,
  }) async {
    if (updateChecking) return;
    if (!UpdateService.configured) {
      if (manual && context.mounted) {
        showModernNotice(
          context,
          title: 'Actualizaciones sin configurar',
          message: 'Falta compilar la app con SIN_RIAL_UPDATE_URL o con SIN_RIAL_GITHUB_OWNER y SIN_RIAL_GITHUB_REPO.',
        );
      }
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    state['lastUpdateCheckMillis'] = now;
    unawaited(NativeStateStore.save(state));
    if (mounted) setState(() => updateChecking = true);
    final update = await UpdateService.fetch();
    if (mounted) setState(() => updateChecking = false);
    if (!context.mounted) return;
    if (update == null) {
      if (manual) {
        showModernNotice(
          context,
          title: 'No se pudo revisar',
          message:
              'Verifica tu conexion o que el release de GitHub sea publico.',
        );
      }
      return;
    }
    if (!update.isNewer || !update.hasDownload) {
      if (manual) {
        showModernNotice(
          context,
          title: 'Sin actualizaciones',
          message: 'Ya tienes instalada la version mas reciente.',
        );
      }
      return;
    }
    final dismissedBuild = numberValue(state['dismissedUpdateBuild']).round();
    final dismissedVersion = state['dismissedUpdateVersion']?.toString() ?? '';
    final dismissedAt = numberValue(state['dismissedUpdateMillis']).round();
    final dismissedSameVersion =
        (update.build > 0 && dismissedBuild == update.build) ||
        (update.build <= 0 && dismissedVersion == update.version);
    if (!manual &&
        dismissedSameVersion &&
        now - dismissedAt < _dismissedUpdateSnooze.inMilliseconds) {
      return;
    }
    showReleaseUpdatePrompt(context, update);
  }

  void showReleaseUpdatePrompt(BuildContext context, UpdateInfo update) {
    updatePromptVisible = true;
    final versionText = update.build > 0
        ? '${update.version}+${update.build}'
        : update.version;
    final notes = update.notes.trim();
    final t = theme;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar',
      barrierColor: CupertinoColors.black.withOpacity(t.dark ? .50 : .28),
      transitionDuration: const Duration(milliseconds: 190),
      pageBuilder: (dialogContext, _, __) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: UpdatePromptSheet(
                theme: t,
                versionText: versionText,
                notes: notes,
                onDownload: () {
                  Navigator.of(dialogContext, rootNavigator: true).pop();
                  unawaited(openUpdateDownload(context, update));
                },
                onLater: () {
                  Navigator.of(dialogContext, rootNavigator: true).pop();
                  mutate(() {
                    state['dismissedUpdateBuild'] = update.build;
                    state['dismissedUpdateVersion'] = update.version;
                    state['dismissedUpdateMillis'] =
                        DateTime.now().millisecondsSinceEpoch;
                  });
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, .055),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        );
      },
    ).whenComplete(() => updatePromptVisible = false);
  }

  String id() =>
      '${DateTime.now().microsecondsSinceEpoch}-${rand.nextInt(1 << 32)}';

  Future<bool> canUseBiometrics() async {
    try {
      return await localAuth.isDeviceSupported() &&
          (await localAuth.canCheckBiometrics ||
              (await localAuth.getAvailableBiometrics()).isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    if (!biometricEnabled) return false;
    try {
      return await localAuth.authenticate(
        localizedReason: 'Desbloquea Sin Rial para ver tus finanzas.',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  void configureSecurity({required String pin, required bool useBiometrics}) {
    final salt = id();
    final digest = pinHashFor(pin, salt);
    mutate(() {
      state['pinSalt'] = salt;
      state['pinHash'] = digest;
      state['pinLength'] = pin.length;
      state['pinEnabled'] = true;
      state['biometricEnabled'] = useBiometrics;
      state['securitySetupComplete'] = true;
    });
  }

  bool verifyPin(String pin) {
    final salt = state['pinSalt']?.toString() ?? '';
    final digest = state['pinHash']?.toString() ?? '';
    if (salt.isEmpty || digest.isEmpty) return false;
    return pinHashFor(pin, salt) == digest;
  }

  void lockApp() {
    if (!securityEnabled) return;
    _closeTransientRoutes();
    setState(() => locked = true);
  }

  void _closeTransientRoutes() {
    rootNavigatorKey.currentState?.popUntil((route) => route is! PopupRoute);
  }

  void unlockApp() {
    if (!mounted) return;
    setState(() => locked = false);
    unawaited(refreshRateIfNeeded());
  }

  double toUsd(double amount, String currency) {
    if (currency == 'USD') return amount;
    if (currency == 'USDT')
      return rate > 0 && usdtRate > 0 ? amount * usdtRate / rate : 0;
    if (currency == 'EUR') {
      final eur = eurRate;
      return eur > 0 && rate > 0 ? (amount * eur) / rate : amount;
    }
    return rate > 0 ? amount / rate : 0;
  }

  double toVes(double amount, String currency) {
    if (currency == 'VES') return amount;
    if (currency == 'EUR') {
      final eur = eurRate;
      return amount * (eur > 0 ? eur : rate);
    }
    if (currency == 'USDT') return amount * usdtRate;
    return amount * rate;
  }

  double convertForHome(double amount, String from, String to) {
    if (from == to) return amount;
    final ves = toVes(amount, from);
    if (to == 'VES') return ves;
    if (to == 'EUR') {
      final eur = eurRate;
      return eur > 0 ? ves / eur : (rate > 0 ? ves / rate : 0);
    }
    if (to == 'USDT') {
      final usdt = usdtRate;
      return usdt > 0 ? ves / usdt : 0;
    }
    return rate > 0 ? ves / rate : 0;
  }

  void applyMovement(Map<String, dynamic> movement, int direction) {
    final type = movement['type']?.toString() ?? 'expense';
    final source = accountById(movement['accountId']?.toString() ?? '');
    final amount = numberValue(movement['amount']);
    final fee = numberValue(movement['feeAmount']);
    if (source != null) {
      final balance = numberValue(source['balance']);
      if (type == 'income') {
        source['balance'] = moneyAdd(
          balance,
          moneySubtract(amount, fee) * direction,
        );
      } else if (type == 'transfer') {
        source['balance'] = moneySubtract(
          balance,
          moneyAdd(amount, fee) * direction,
        );
      } else {
        source['balance'] = moneySubtract(
          balance,
          moneyAdd(amount, fee) * direction,
        );
      }
    }
    if (type == 'transfer') {
      final target = accountById(movement['targetAccountId']?.toString() ?? '');
      if (target != null) {
        target['balance'] = moneyAdd(
          numberValue(target['balance']),
          numberValue(movement['targetAmount']) * direction,
        );
      }
    }
  }

  void applyDebtPayment(Map<String, dynamic> movement, int direction) {
    final debtId = movement['debtId']?.toString() ?? '';
    if (debtId.isEmpty) return;
    final debt = debtById(debtId);
    if (debt == null) return;
    final type = movement['type']?.toString() ?? '';
    final kind = debt['kind']?.toString() == 'receivable'
        ? 'receivable'
        : 'payable';
    if (kind == 'payable' && type != 'expense') return;
    if (kind == 'receivable' && type != 'income') return;

    final movementCurrency = movement['currency']?.toString() ?? 'USD';
    final debtCurrency = debt['currency']?.toString() ?? 'USD';
    final movementRate = numberValue(movement['rate']) > 0
        ? numberValue(movement['rate'])
        : rate;
    final converted = moneyRound(
      convert(
        numberValue(movement['amount']),
        movementCurrency,
        debtCurrency,
        movementRate,
      ),
    );
    final total = numberValue(debt['amount']);
    final delta = direction < 0 && movement.containsKey('debtAppliedAmount')
        ? numberValue(movement['debtAppliedAmount'])
        : math.min(
            converted,
            direction > 0
                ? debtRemainingAmount(debt)
                : numberValue(debt['paidAmount']),
          );
    if (direction > 0) movement['debtAppliedAmount'] = delta;
    final paid = math.max(
      0.0,
      math.min(
        total,
        moneyAdd(numberValue(debt['paidAmount']), delta * direction),
      ),
    );
    debt['paidAmount'] = paid;
    debt['status'] = paid + .0001 >= total ? 'paid' : 'pending';
    debt['paidAt'] = paid + .0001 >= total
        ? formatDateTime(DateTime.now())
        : '';
  }

  void markDebtPaid(String id) {
    if (id.isEmpty) return;
    undoableMutation(
      'Registro marcado como pagado',
      {
        'debts': {id},
      },
      () {
        for (final item in rawList('debts')) {
          if (item is! Map || item['id'] != id) continue;
          final debt = item.cast<String, dynamic>();
          debt['paidAmount'] = numberValue(debt['amount']);
          debt['status'] = 'paid';
          debt['paidAt'] = formatDateTime(DateTime.now());
          return;
        }
      },
    );
  }

  void saveDebt(Map<String, dynamic> debt, {String? editingId}) {
    debt = Map<String, dynamic>.from(debt);
    debt['id'] = editingId ?? debt['id'] ?? id();
    for (final key in [
      'amount',
      'paidAmount',
      'initialAmount',
      'installmentAmount',
    ]) {
      final value = numberValue(debt[key]);
      if (!value.isFinite || value < 0 || value > 999999999999) {
        throw const FormatException('Monto fuera de rango');
      }
      debt[key] = moneyRound(value);
    }
    if (numberValue(debt['amount']) <= 0 ||
        numberValue(debt['initialAmount']) > numberValue(debt['amount']) ||
        numberValue(debt['paidAmount']) > numberValue(debt['amount'])) {
      throw const FormatException(
        'Revisa el total, la inicial y el monto pagado',
      );
    }
    undoableMutation(
      editingId == null ? 'Registro creado' : 'Registro editado',
      {
        'debts': {debt['id'].toString()},
      },
      () {
        final list = rawList('debts');
        if (editingId != null && editingId.isNotEmpty) {
          for (var i = 0; i < list.length; i++) {
            final item = list[i];
            if (item is Map && item['id'] == editingId) {
              debt['id'] = editingId;
              list[i] = debt;
              return;
            }
          }
        }
        debt['id'] = debt['id'] ?? id();
        list.add(debt);
      },
    );
  }

  void deleteDebt(String id) {
    if (id.isEmpty) return;
    undoableMutation(
      'Registro eliminado',
      {
        'debts': {id},
      },
      () {
        rawList('debts').removeWhere((item) => item is Map && item['id'] == id);
      },
    );
  }

  void saveMovement(Map<String, dynamic> movement, {String? editingId}) {
    movement = Map<String, dynamic>.from(movement);
    movement['id'] = editingId ?? movement['id'] ?? id();
    if (movement['type'] == 'income') {
      movement['feeAmount'] = 0.0;
      movement['feeMode'] = 'none';
      movement['bankTransferScope'] = '';
    }
    if (movement['type'] == 'expense' &&
        isBankCommissionCategory(movement['category']?.toString() ?? '')) {
      movement['feeAmount'] = 0.0;
      movement['feeMode'] = 'none';
      movement['paymentMethod'] = '';
      movement['bankTransferScope'] = '';
    }
    for (final key in ['amount', 'feeAmount', 'targetAmount']) {
      final value = numberValue(movement[key]);
      if (!value.isFinite || value < 0 || value > 999999999999)
        throw const FormatException('Monto fuera de rango');
      movement[key] = moneyRound(value);
    }
    if (numberValue(movement['amount']) <= 0)
      throw const FormatException('El monto debe ser mayor a cero');
    final previous = editingId == null ? null : movementById(editingId);
    if (editingId == null && movementById(movement['id'].toString()) != null) {
      throw const FormatException('El movimiento ya fue registrado');
    }
    if (editingId != null && previous == null)
      throw const FormatException('El movimiento ya no existe');
    if (accountById(movement['accountId']?.toString() ?? '') == null)
      throw const FormatException('La cuenta ya no existe');
    if (movement['type'] == 'transfer' &&
        (movement['accountId'] == movement['targetAccountId'] ||
            accountById(movement['targetAccountId']?.toString() ?? '') ==
                null ||
            numberValue(movement['targetAmount']) <= 0)) {
      throw const FormatException('Destino o monto de transferencia no válido');
    }
    if (movement['type'] == 'transfer') {
      final source = accountById(movement['accountId'].toString());
      final target = accountById(movement['targetAccountId'].toString());
      movement['feeAmount'] = bankTransferFee(
        source,
        target,
        numberValue(movement['amount']),
      );
      movement['feeMode'] = numberValue(movement['feeAmount']) > 0
          ? 'auto'
          : 'none';
      movement['bankTransferScope'] =
          canConfigureBankFee(source, type: 'transfer', target: target)
          ? bankTransferScopeForAccounts(source, target)
          : '';
    }
    undoableMutation(
      editingId == null ? 'Movimiento registrado' : 'Movimiento editado',
      {
        'movements': {movement['id'].toString()},
        'accounts': {
          movement['accountId']?.toString() ?? '',
          movement['targetAccountId']?.toString() ?? '',
          previous?['accountId']?.toString() ?? '',
          previous?['targetAccountId']?.toString() ?? '',
        },
        'debts': {
          movement['debtId']?.toString() ?? '',
          previous?['debtId']?.toString() ?? '',
        },
      },
      () {
        final list = rawList('movements');
        final type = movement['type']?.toString() ?? '';
        if (type == 'income' || isExpenseType(type)) {
          state['lastMovementAccountId'] =
              movement['accountId']?.toString() ?? '';
        }
        if (editingId != null) {
          for (var i = 0; i < list.length; i++) {
            final item = list[i];
            if (item is Map && item['id'] == editingId) {
              applyMovement(item.cast<String, dynamic>(), -1);
              applyDebtPayment(item.cast<String, dynamic>(), -1);
              movement['id'] = editingId;
              list[i] = movement;
              applyMovement(movement, 1);
              applyDebtPayment(movement, 1);
              return;
            }
          }
        }
        movement['id'] = movement['id'] ?? id();
        list.add(movement);
        applyMovement(movement, 1);
        applyDebtPayment(movement, 1);
      },
    );
  }

  void deleteMovement(Map<String, dynamic> movement) {
    final current = movementById(movement['id']?.toString() ?? '');
    if (current == null) return;
    movement = current;
    undoableMutation(
      'Movimiento eliminado',
      {
        'movements': {movement['id'].toString()},
        'accounts': {
          movement['accountId']?.toString() ?? '',
          movement['targetAccountId']?.toString() ?? '',
        },
        'debts': {movement['debtId']?.toString() ?? ''},
      },
      () {
        applyMovement(movement, -1);
        applyDebtPayment(movement, -1);
        rawList('movements')
            .removeWhere((item) => item is Map && item['id'] == movement['id']);
      },
    );
  }

  void saveAccount(Map<String, dynamic> account, {String? editingId}) {
    mutate(() {
      final list = rawList('accounts');
      if (editingId != null) {
        for (var i = 0; i < list.length; i++) {
          final item = list[i];
          if (item is Map && item['id'] == editingId) {
            account['id'] = editingId;
            account['createdAt'] = item['createdAt'];
            account['chartColor'] = item['chartColor'];
            final delta = moneySubtract(
              numberValue(account['balance']),
              numberValue(item['balance']),
            );
            if (delta != 0)
              rawList('balanceAdjustments').add({
                'id': id(),
                'accountId': editingId,
                'amount': delta,
                'date': DateTime.now().toIso8601String(),
              });
            list[i] = account;
            assignAccountColors(maps('accounts'));
            return;
          }
        }
      }
      account['id'] = account['id'] ?? id();
      account['createdAt'] = DateTime.now().toIso8601String();
      list.add(account);
      assignAccountColors(maps('accounts'));
    });
  }

  void deleteAccount(Map<String, dynamic> account) {
    mutate(() {
      rawList('accounts')
          .removeWhere((item) => item is Map && item['id'] == account['id']);
      rawList('movements').removeWhere(
        (item) => item is Map && item['accountId'] == account['id'],
      );
    });
  }

  bool hasDuplicateAccount(
    String provider,
    String currency, {
    String ignoreId = '',
  }) {
    for (final account in maps('accounts')) {
      if (ignoreId.isNotEmpty && account['id'] == ignoreId) continue;
      if (account['provider'] == provider && account['currency'] == currency) {
        return true;
      }
    }
    return false;
  }

  List<Map<String, dynamic>> usableAccounts() =>
      maps('accounts')
          .where((account) => (account['id']?.toString() ?? '').isNotEmpty)
          .toList();

  bool ensureCanCreateMovement(BuildContext context, String type) {
    final accounts = usableAccounts();
    if (accounts.isEmpty) {
      showModernNotice(
        context,
        title: 'Primero agrega una cuenta',
        message: 'Registra un banco, billetera o efectivo antes de crear movimientos.',
      );
      return false;
    }
    if (type == 'transfer' && accounts.length < 2) {
      showModernNotice(
        context,
        title: 'Falta otra cuenta',
        message: 'Para transferir necesitas al menos dos cuentas. Pueden ser del mismo banco si una es en bolívares y otra en dólares.',
      );
      return false;
    }
    return true;
  }

  void completeOnboarding(String name, {required bool addAccount}) {
    openAccountAfterOnboarding = addAccount;
    mutate(() {
      state['userName'] = name.trim();
      state['onboardingComplete'] = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: t.bg,
      systemNavigationBarColor: t.bg,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
    );
    SystemChrome.setSystemUIOverlayStyle(overlayStyle);
    unawaited(
      NativeStateStore.setSystemBars(dark: dark, color: t.bg.toARGB32()),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: RThemeScope(
        theme: t,
        child: CupertinoApp(
          navigatorKey: rootNavigatorKey,
          title: 'Sin Rial',
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            final shouldShowLockOverlay =
                locked &&
                state['onboardingComplete'] == true &&
                !securitySetupRequired;
            final appContent = Stack(
              fit: StackFit.expand,
              children: [
                child ?? const SizedBox.shrink(),
                if (!locked &&
                    _showUndo &&
                    canUndo &&
                    MediaQuery.of(context).viewInsets.bottom == 0)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: MediaQuery.of(context).padding.bottom + 96,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: t.field,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: t.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _undoHistory.last.label,
                              maxLines: 2,
                              style: TextStyle(color: t.ink, fontSize: 13),
                            ),
                          ),
                          CupertinoButton(
                            onPressed: undoLastOperation,
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(CupertinoIcons.arrow_uturn_left, size: 18),
                                SizedBox(width: 6),
                                Text('Deshacer'),
                              ],
                            ),
                          ),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => setState(() => _showUndo = false),
                            child: Icon(
                              CupertinoIcons.xmark,
                              size: 16,
                              color: t.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (shouldShowLockOverlay)
                  Positioned.fill(
                    child: PopScope(
                      canPop: false,
                      child: _AppEntrance(child: LockScreen(app: this)),
                    ),
                  ),
              ],
            );
            final media = MediaQuery.maybeOf(context);
            if (media == null) return appContent;
            return MediaQuery(
              data: media.copyWith(textScaler: appTextScaler(media)),
              child: appContent,
            );
          },
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('es'), Locale('en')],
          theme: CupertinoThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            primaryColor: t.accent,
            scaffoldBackgroundColor: t.bg,
            textTheme: CupertinoTextThemeData(
              primaryColor: t.ink,
              textStyle: TextStyle(color: t.ink, fontFamily: '.SF Pro Text'),
              navLargeTitleTextStyle: TextStyle(
                color: t.ink,
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
              navTitleTextStyle: TextStyle(
                color: t.ink,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          home: Builder(
            builder: (context) {
              if (state['onboardingComplete'] != true) {
                return _AppEntrance(child: _OnboardingPage(app: this));
              }
              if (securitySetupRequired) {
                return _AppEntrance(
                  child: SecuritySetupPage(
                    app: this,
                    requiredSetup: true,
                    onDone: () {},
                  ),
                );
              }
              if (!locked && openAccountAfterOnboarding) {
                openAccountAfterOnboarding = false;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) openAccountEditor(context);
                });
              }
              if (!locked && pendingLaunchAction != null) {
                final action = pendingLaunchAction!;
                pendingLaunchAction = null;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) {
                    if (action == 'account') {
                      openAccountEditor(context);
                    } else {
                      openMovementEditor(context, defaultType: action);
                    }
                  }
                });
              }
              return _AppEntrance(
                child: CupertinoPageScaffold(
                  backgroundColor: t.bg,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: PageView(
                          controller: _pageController,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            RepaintBoundary(child: HomePage(app: this)),
                            RepaintBoundary(child: BudgetPage(app: this)),
                            RepaintBoundary(child: MenuPage(app: this)),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: BottomChrome(app: this),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void showQuickActions(BuildContext context) {
    final enabled = sanitizeHomeQuickActions(state['homeQuickActions']);
    final allActions = <String, ModernSheetAction>{
      'movement': ModernSheetAction(
        icon: CupertinoIcons.arrow_up_right_circle_fill,
        title: 'Nuevo movimiento',
        subtitle: 'Registra un gasto o ingreso',
        onPressed: () => openMovementEditor(context, defaultType: 'expense'),
      ),
      'transfer': ModernSheetAction(
        icon: CupertinoIcons.arrow_right_arrow_left_circle_fill,
        title: 'Nueva transferencia',
        subtitle: 'Mueve dinero entre cuentas',
        onPressed: () => openMovementEditor(context, defaultType: 'transfer'),
      ),
      'account': ModernSheetAction(
        icon: CupertinoIcons.creditcard_fill,
        title: 'Nueva cuenta',
        subtitle: 'Banco, billetera o efectivo',
        onPressed: () => openAccountEditor(context),
      ),
    };
    showModernActionSheet(
      context,
      title: 'Crear',
      message: 'Acciones principales',
      actions: enabled
          .map((key) => allActions[key])
          .whereType<ModernSheetAction>()
          .toList(),
    );
  }

  void openMovementEditor(
    BuildContext context, {
    Map<String, dynamic>? movement,
    String defaultType = 'expense',
    String? defaultCategory,
    String? defaultAccountId,
    String? defaultDebtId,
    String? defaultDescription,
    double? defaultAmount,
    bool lockAccount = false,
  }) {
    if (movement == null && !ensureCanCreateMovement(context, defaultType)) {
      return;
    }
    Navigator.of(context, rootNavigator: true).push(
      FluidPageRoute<void>(
        builder: (routeContext) => MovementEditor(
          app: this,
          movement: movement,
          defaultType: defaultType,
          defaultCategory: defaultCategory,
          defaultAccountId: defaultAccountId,
          defaultDebtId: defaultDebtId,
          defaultDescription: defaultDescription,
          defaultAmount: defaultAmount,
          lockAccount: lockAccount,
          onSave: (next) {
            try {
              saveMovement(next, editingId: movement?['id']?.toString());
              Navigator.pop(routeContext);
            } on FormatException catch (error) {
              showModernNotice(
                routeContext,
                title: 'Revisa el movimiento',
                message: error.message,
              );
            }
          },
        ),
      ),
    );
  }

  void openDebtMovement(BuildContext context, Map<String, dynamic> debt) {
    final kind = debt['kind']?.toString() == 'receivable'
        ? 'receivable'
        : 'payable';
    openMovementEditor(
      context,
      defaultType: kind == 'receivable' ? 'income' : 'expense',
      defaultCategory:
          categoryFromDescription(debt['title']?.toString() ?? '') ??
          budgetCategories.first,
      defaultDebtId: debt['id']?.toString() ?? '',
      defaultDescription: debt['title']?.toString(),
    );
  }

  void openDebtDetail(BuildContext context, Map<String, dynamic> debt) {
    final id = debt['id']?.toString() ?? '';
    if (id.isEmpty) return;
    pushPage(context, (_) => DebtDetailPage(app: this, debtId: id));
  }

  void openDebtEditor(BuildContext context, {Map<String, dynamic>? debt}) {
    pushPage(context, (_) => DebtEditorPage(app: this, debt: debt));
  }

  void openAccountEditor(
    BuildContext context, {
    Map<String, dynamic>? account,
  }) {
    Navigator.of(context, rootNavigator: true).push(
      FluidPageRoute<void>(
        builder: (routeContext) => AccountEditor(
          app: this,
          account: account,
          onSave: (next) {
            saveAccount(next, editingId: account?['id']?.toString());
            Navigator.pop(routeContext);
          },
        ),
      ),
    );
  }

  void confirmDelete(
    BuildContext context,
    String title,
    String message,
    VoidCallback onDelete, {
    String destructiveText = 'Eliminar',
  }) {
    showModernConfirm(
      context,
      title: title,
      message: message,
      destructiveText: destructiveText,
      onConfirm: onDelete,
    );
  }
}

class _AppEntrance extends StatelessWidget {
  const _AppEntrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => softEntrance(
    child,
    offsetY: 6,
    duration: const Duration(milliseconds: 220),
  );
}

class _OnboardingPage extends StatefulWidget {
  const _OnboardingPage({required this.app});

  final _RialAppState app;

  @override
  State<_OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<_OnboardingPage> {
  final name = TextEditingController();
  final pin = TextEditingController();
  final pinConfirm = TextEditingController();
  int step = 0;
  bool useBiometrics = false;
  bool biometricsAvailable = false;
  static const totalSteps = 5;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBiometrics());
  }

  @override
  void dispose() {
    name.dispose();
    pin.dispose();
    pinConfirm.dispose();
    super.dispose();
  }

  Future<void> _loadBiometrics() async {
    final available = await widget.app.canUseBiometrics();
    if (!mounted) return;
    setState(() {
      biometricsAvailable = available;
      useBiometrics = available;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = app.theme;
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 44, 22, 28),
          children: [
            Text(
              'Sin Rial',
              style: TextStyle(
                color: t.ink,
                fontSize: 42,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vamos a dejar la app lista para usarla sin inventos raros.',
              style: TextStyle(
                color: t.muted,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 34),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(.025, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                );
              },
              child: _currentStep(context, t),
            ),
            const SizedBox(height: 18),
            Row(
              children: List.generate(totalSteps, (index) {
                return Padding(
                  padding: EdgeInsets.only(
                    right: index == totalSteps - 1 ? 0 : 7,
                  ),
                  child: _StepDot(theme: t, active: step == index),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _currentStep(BuildContext context, RTheme t) {
    if (step == 0) return _nameStep(context, t);
    if (step == 1) return _appearanceStep(t);
    if (step == 2) return _colorStep(t);
    if (step == 3) return _securityStep(context, t);
    return _accountsStep(t);
  }

  Widget _nameStep(BuildContext context, RTheme t) {
    return RCard(
      key: const ValueKey('name-step'),
      theme: t,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿Cómo te llamas?',
            style: TextStyle(
              color: t.ink,
              fontSize: 27,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Lo uso solo dentro de la app para personalizar un poco la experiencia.',
            style: TextStyle(
              color: t.muted,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          RField(theme: t, controller: name, placeholder: 'Tu nombre'),
          PrimaryActionButton(
            theme: t,
            label: 'Continuar',
            onPressed: () {
              if (name.text.trim().isEmpty) {
                showModernNotice(
                  context,
                  title: 'Falta tu nombre',
                  message: 'Escribe cómo quieres que te salude la app.',
                );
                return;
              }
              setState(() => step = 1);
            },
          ),
        ],
      ),
    );
  }

  Widget _appearanceStep(RTheme t) {
    final app = widget.app;
    return RCard(
      key: const ValueKey('appearance-step'),
      theme: t,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿Quieres seleccionar modo claro u oscuro?',
            style: TextStyle(
              color: t.ink,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Esto solo cambia la apariencia dentro de Sin Rial.',
            style: TextStyle(
              color: t.muted,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          KindSelector(
            theme: t,
            value: app.dark ? 'dark' : 'light',
            items: const [
              KindSelectorItem(
                value: 'light',
                label: 'Claro',
                icon: CupertinoIcons.sun_max_fill,
              ),
              KindSelectorItem(
                value: 'dark',
                label: 'Oscuro',
                icon: CupertinoIcons.moon_stars_fill,
              ),
            ],
            onChanged: (value) {
              app.mutate(() => app.state['darkMode'] = value == 'dark');
              setState(() {});
            },
          ),
          PrimaryActionButton(
            theme: t,
            label: 'Continuar',
            onPressed: () => setState(() => step = 2),
          ),
          _BackTextButton(
            theme: t,
            label: 'Volver al nombre',
            onTap: () => setState(() => step = 0),
          ),
        ],
      ),
    );
  }

  Widget _colorStep(RTheme t) {
    final app = widget.app;
    return RCard(
      key: const ValueKey('color-step'),
      theme: t,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿Y el color del tema?',
            style: TextStyle(
              color: t.ink,
              fontSize: 27,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Elige el color principal para botones, navegación y detalles.',
            style: TextStyle(
              color: t.muted,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          ThemeColorSelector(
            theme: t,
            value: app.themeColorKey,
            onChanged: (value) {
              app.mutate(() => app.state['themeColor'] = value);
              setState(() {});
            },
          ),
          const SizedBox(height: 6),
          PrimaryActionButton(
            theme: t,
            label: 'Continuar',
            onPressed: () => setState(() => step = 3),
          ),
          _BackTextButton(
            theme: t,
            label: 'Volver al modo',
            onTap: () => setState(() => step = 1),
          ),
        ],
      ),
    );
  }

  Widget _securityStep(BuildContext context, RTheme t) {
    return RCard(
      key: const ValueKey('security-step'),
      theme: t,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Protege tu app',
            style: TextStyle(
              color: t.ink,
              fontSize: 27,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Crea un PIN. Si tu teléfono lo permite, también podrás entrar con biometría.',
            style: TextStyle(
              color: t.muted,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          RField(
            theme: t,
            controller: pin,
            placeholder: 'PIN de 4 a 6 dígitos',
            keyboardType: TextInputType.number,
            obscureText: true,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
          ),
          RField(
            theme: t,
            controller: pinConfirm,
            placeholder: 'Repetir PIN',
            keyboardType: TextInputType.number,
            obscureText: true,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
          ),
          SecurityRecoveryNote(theme: t),
          const SizedBox(height: 12),
          if (biometricsAvailable)
            SettingsSwitchTile(
              theme: t,
              icon: CupertinoIcons.lock_shield_fill,
              title: 'Usar biometría',
              subtitle: 'Desbloquea con huella o rostro cuando esté disponible',
              value: useBiometrics,
              framed: false,
              onTap: () => setState(() => useBiometrics = !useBiometrics),
            ),
          PrimaryActionButton(
            theme: t,
            label: 'Continuar',
            onPressed: () {
              if (!validatePin(context, pin.text, pinConfirm.text)) return;
              widget.app.configureSecurity(
                pin: pin.text,
                useBiometrics: biometricsAvailable && useBiometrics,
              );
              setState(() => step = 4);
            },
          ),
          _BackTextButton(
            theme: t,
            label: 'Volver al color',
            onTap: () => setState(() => step = 2),
          ),
        ],
      ),
    );
  }

  Widget _accountsStep(RTheme t) {
    return RCard(
      key: const ValueKey('accounts-step'),
      theme: t,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿Quieres agregar una o varias cuentas?',
            style: TextStyle(
              color: t.ink,
              fontSize: 27,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Puedes empezar con una cuenta y luego agregar bancos, billeteras o efectivo desde Cuentas.',
            style: TextStyle(
              color: t.muted,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          PrimaryActionButton(
            theme: t,
            label: 'Agregar cuenta ahora',
            onPressed: () =>
                widget.app.completeOnboarding(name.text, addAccount: true),
          ),
          const SizedBox(height: 10),
          SecondaryActionButton(
            theme: t,
            label: 'Empezar sin cuentas',
            onPressed: () =>
                widget.app.completeOnboarding(name.text, addAccount: false),
          ),
          const SizedBox(height: 10),
          _BackTextButton(
            theme: t,
            label: 'Volver a seguridad',
            onTap: () => setState(() => step = 3),
          ),
        ],
      ),
    );
  }
}

class _BackTextButton extends StatelessWidget {
  const _BackTextButton({
    required this.theme,
    required this.label,
    required this.onTap,
  });

  final RTheme theme;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            color: theme.accent,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class SecurityRecoveryNote extends StatelessWidget {
  const SecurityRecoveryNote({super.key, required this.theme});

  final RTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.accent.withOpacity(.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.accent.withOpacity(.20)),
      ),
      child: Text(
        'Si olvidas la contraseña, será necesario borrar los datos de la aplicación.',
        style: TextStyle(
          color: theme.muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      ),
    );
  }
}

Future<bool> requestCurrentPin(BuildContext context, _RialAppState app) async {
  final t = app.theme;
  final controller = TextEditingController();
  final focus = FocusNode();
  var wrong = false;
  var completed = false;

  Future<void> submit(BuildContext dialogContext, StateSetter refresh) async {
    if (completed) return;
    final value = controller.text;
    if (app.verifyPin(value)) {
      completed = true;
      Navigator.of(dialogContext, rootNavigator: true).pop(true);
      return;
    }
    await HapticFeedback.mediumImpact();
    controller.clear();
    refresh(() => wrong = true);
    focus.requestFocus();
  }

  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: CupertinoColors.black.withOpacity(t.dark ? .50 : .28),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, _, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        focus.requestFocus();
        unawaited(
          SystemChannels.textInput.invokeMethod<void>('TextInput.show'),
        );
      });
      return Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (sheetContext, refresh) {
              final expectedLength = app.configuredPinLength;
              return AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.fromLTRB(
                  14,
                  0,
                  14,
                  14 + MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: softEntrance(
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    decoration: BoxDecoration(
                      color: t.card,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: t.border),
                      boxShadow: [
                        BoxShadow(
                          color: CupertinoColors.black.withOpacity(
                            t.dark ? .38 : .10,
                          ),
                          blurRadius: 28,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: t.border,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        Text(
                          'Confirma tu PIN actual',
                          style: TextStyle(
                            color: t.ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Necesitamos confirmar tu identidad antes de cambiar el PIN.',
                          style: TextStyle(
                            color: t.muted,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        CupertinoTextField(
                          controller: controller,
                          focusNode: focus,
                          autofocus: true,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 17,
                          ),
                          style: TextStyle(
                            color: t.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                          placeholder: 'PIN anterior',
                          placeholderStyle: TextStyle(
                            color: t.muted,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: BoxDecoration(
                            color: t.field,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: wrong ? t.red : t.border),
                          ),
                          onChanged: (value) {
                            if (wrong) refresh(() => wrong = false);
                            final canAutoSubmit = expectedLength >= 4
                                ? value.length >= expectedLength
                                : value.length >= 6;
                            if (canAutoSubmit) {
                              unawaited(submit(dialogContext, refresh));
                            }
                          },
                          onSubmitted: (_) =>
                              unawaited(submit(dialogContext, refresh)),
                        ),
                        if (wrong) ...[
                          const SizedBox(height: 9),
                          Text(
                            'PIN incorrecto. Inténtalo otra vez.',
                            style: TextStyle(
                              color: t.red,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: SecondaryActionButton(
                                theme: t,
                                label: 'Cancelar',
                                onPressed: () => Navigator.of(
                                  dialogContext,
                                  rootNavigator: true,
                                ).pop(false),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: PrimaryActionButton(
                                theme: t,
                                label: 'Confirmar',
                                onPressed: () =>
                                    unawaited(submit(dialogContext, refresh)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  offsetY: 8,
                  duration: const Duration(milliseconds: 160),
                ),
              );
            },
          ),
        ),
      );
    },
  );

  controller.dispose();
  focus.dispose();
  return result == true;
}

class SecuritySetupPage extends StatefulWidget {
  const SecuritySetupPage({
    super.key,
    required this.app,
    required this.requiredSetup,
    this.onDone,
  });

  final _RialAppState app;
  final bool requiredSetup;
  final VoidCallback? onDone;

  @override
  State<SecuritySetupPage> createState() => _SecuritySetupPageState();
}

class _SecuritySetupPageState extends State<SecuritySetupPage> {
  final pin = TextEditingController();
  final pinConfirm = TextEditingController();
  bool useBiometrics = false;
  bool biometricsAvailable = false;
  bool confirmedCurrentSecurity = false;

  @override
  void initState() {
    super.initState();
    useBiometrics = widget.app.biometricEnabled;
    unawaited(_loadBiometrics());
  }

  @override
  void dispose() {
    pin.dispose();
    pinConfirm.dispose();
    super.dispose();
  }

  Future<void> _loadBiometrics() async {
    final available = await widget.app.canUseBiometrics();
    if (!mounted) return;
    setState(() {
      biometricsAvailable = available;
      useBiometrics = available && (useBiometrics || widget.requiredSetup);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = app.theme;
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: widget.requiredSetup
          ? null
          : CupertinoNavigationBar(
              transitionBetweenRoutes: false,
              backgroundColor: t.bg.withOpacity(.92),
              border: null,
              middle: const Text('Seguridad'),
            ),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            18,
            widget.requiredSetup ? 44 : 22,
            18,
            34,
          ),
          children: [
            Text(
              widget.requiredSetup ? 'Protege Sin Rial' : 'Seguridad',
              style: TextStyle(
                color: t.ink,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.requiredSetup
                  ? 'Antes de entrar, configura un PIN para mantener tus datos privados.'
                  : 'Cambia tu PIN y decide si quieres desbloquear con biometría.',
              style: TextStyle(
                color: t.muted,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 22),
            RCard(
              theme: t,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RField(
                    theme: t,
                    controller: pin,
                    placeholder: 'PIN de 4 a 6 dígitos',
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                  ),
                  RField(
                    theme: t,
                    controller: pinConfirm,
                    placeholder: 'Repetir PIN',
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                  ),
                  SecurityRecoveryNote(theme: t),
                  const SizedBox(height: 12),
                  if (biometricsAvailable)
                    SettingsSwitchTile(
                      theme: t,
                      icon: CupertinoIcons.lock_shield_fill,
                      title: 'Biometría',
                      subtitle: 'Permite entrar con huella o rostro',
                      value: useBiometrics,
                      framed: false,
                      onTap: () =>
                          setState(() => useBiometrics = !useBiometrics),
                    ),
                  PrimaryActionButton(
                    theme: t,
                    label: widget.requiredSetup
                        ? 'Activar seguridad'
                        : 'Guardar seguridad',
                    onPressed: () => unawaited(save()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> confirmCurrentSecurity() async {
    if (widget.requiredSetup || confirmedCurrentSecurity) return true;
    if (widget.app.biometricEnabled && await widget.app.canUseBiometrics()) {
      final ok = await widget.app.authenticateWithBiometrics();
      if (!mounted) return false;
      if (ok) {
        confirmedCurrentSecurity = true;
        return true;
      }
    }
    if (!widget.app.pinEnabled) {
      confirmedCurrentSecurity = true;
      return true;
    }
    final ok = await requestCurrentPin(context, widget.app);
    if (ok) confirmedCurrentSecurity = true;
    return ok;
  }

  Future<void> save() async {
    if (!validatePin(context, pin.text, pinConfirm.text)) return;
    if (!await confirmCurrentSecurity()) return;
    widget.app.configureSecurity(
      pin: pin.text,
      useBiometrics: biometricsAvailable && useBiometrics,
    );
    widget.app.unlockApp();
    widget.onDone?.call();
    if (!widget.requiredSetup && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}

class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.theme, required this.length});

  final RTheme theme;
  final int length;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        final filled = index < length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 18,
          height: 18,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: filled ? theme.accent : theme.border,
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.app});

  final _RialAppState app;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  final pin = TextEditingController();
  final pinFocus = FocusNode();
  final scroll = ScrollController();
  final enterButtonKey = GlobalKey();
  bool checkingBiometric = false;
  bool showPin = false;
  bool autoUnlocking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    pin.addListener(() {
      if (mounted) setState(() {});
      _tryAutoUnlock();
    });
    pinFocus.addListener(() {
      if (pinFocus.hasFocus) _scrollToPin();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusPinInput();
      Future<void>.delayed(const Duration(milliseconds: 250), _focusPinInput);
      if (widget.app.biometricEnabled) unawaited(unlockWithBiometrics());
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (pinFocus.hasFocus) _scrollToPin();
  }

  void _focusPinInput() {
    if (!mounted) return;
    pinFocus.requestFocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
    _scrollToPin();
  }

  void _scrollToPin() {
    for (final delay in const [
      Duration(milliseconds: 80),
      Duration(milliseconds: 260),
      Duration(milliseconds: 560),
    ]) {
      Future<void>.delayed(delay, _ensureEnterButtonVisible);
    }
  }

  void _ensureEnterButtonVisible() {
    if (!mounted || !scroll.hasClients || !pinFocus.hasFocus) return;
    final enterContext = enterButtonKey.currentContext;
    if (enterContext != null) {
      unawaited(
        Scrollable.ensureVisible(
          enterContext,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: .92,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ),
      );
      return;
    }
    unawaited(
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _tryAutoUnlock() {
    if (autoUnlocking || !mounted) return;
    final typed = pin.text;
    if (typed.length < 4) return;
    final expectedLength = widget.app.configuredPinLength;
    if (expectedLength >= 4 && typed.length < expectedLength) return;
    final shouldReject = expectedLength >= 4
        ? typed.length >= expectedLength
        : typed.length >= 6;
    if (widget.app.verifyPin(typed)) {
      autoUnlocking = true;
      widget.app.unlockApp();
      return;
    }
    if (!shouldReject) return;
    autoUnlocking = true;
    unawaited(HapticFeedback.mediumImpact());
    pin.clear();
    showModernNotice(
      context,
      title: 'PIN incorrecto',
      message: 'Revisa los dígitos e inténtalo otra vez.',
    );
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      autoUnlocking = false;
      _focusPinInput();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pin.dispose();
    pinFocus.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = app.theme;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      resizeToAvoidBottomInset: true,
      child: SafeArea(
        child: ListView(
          controller: scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            22,
            keyboard > 0 ? 18 : 54,
            22,
            42 + keyboard,
          ),
          children: [
            Container(
              width: 68,
              height: 68,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.accent.withOpacity(.16),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: t.accent.withOpacity(.26)),
              ),
              child: Icon(
                CupertinoIcons.lock_shield_fill,
                color: t.accent,
                size: 32,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Sin Rial está bloqueada',
              style: TextStyle(
                color: t.ink,
                fontSize: 31,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ingresa tu PIN o usa la biometría del teléfono.',
              style: TextStyle(
                color: t.muted,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 26),
            RCard(
              theme: t,
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _focusPinInput,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 78,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CupertinoTextField(
                                controller: pin,
                                focusNode: pinFocus,
                                autofocus: true,
                                showCursor: false,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: showPin
                                      ? t.ink
                                      : CupertinoColors.transparent,
                                  fontSize: showPin ? 24 : 1,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: showPin ? 6 : 0,
                                ),
                                cursorColor: CupertinoColors.transparent,
                                decoration: BoxDecoration(
                                  color: t.field,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: t.border),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 24,
                                ),
                                enableInteractiveSelection: false,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(6),
                                ],
                                onSubmitted: (_) => unlockWithPin(),
                              ),
                              if (!showPin)
                                IgnorePointer(
                                  child: PinDots(
                                    theme: t,
                                    length: pin.text.length,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => setState(() => showPin = !showPin),
                          child: Text(
                            showPin ? 'Ocultar PIN' : 'Mostrar PIN',
                            style: TextStyle(
                              color: t.accent,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SecurityRecoveryNote(theme: t),
                  const SizedBox(height: 12),
                  KeyedSubtree(
                    key: enterButtonKey,
                    child: PrimaryActionButton(
                      theme: t,
                      label: 'Entrar',
                      onPressed: unlockWithPin,
                    ),
                  ),
                  if (app.biometricEnabled)
                    SecondaryActionButton(
                      theme: t,
                      label: checkingBiometric
                          ? 'Verificando...'
                          : 'Usar biometría',
                      onPressed: checkingBiometric
                          ? () {}
                          : () => unawaited(unlockWithBiometrics()),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void unlockWithPin() {
    if (widget.app.verifyPin(pin.text)) {
      widget.app.unlockApp();
      return;
    }
    showModernNotice(
      context,
      title: 'PIN incorrecto',
      message: 'Revisa los dígitos e inténtalo otra vez.',
    );
  }

  Future<void> unlockWithBiometrics() async {
    if (checkingBiometric) return;
    setState(() => checkingBiometric = true);
    final ok = await widget.app.authenticateWithBiometrics();
    if (!mounted) return;
    setState(() => checkingBiometric = false);
    if (ok) widget.app.unlockApp();
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.theme, required this.active});

  final RTheme theme;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: active ? 28 : 9,
      height: 9,
      decoration: BoxDecoration(
        color: active ? theme.accent : theme.border,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class FluidPageRoute<T> extends PageRouteBuilder<T> {
  FluidPageRoute({required WidgetBuilder builder})
    : super(
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (MediaQuery.disableAnimationsOf(context)) return child;
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(.025, 0),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
            child: RepaintBoundary(child: child),
          );
        },
      );
}

class ReactiveRoutePage extends StatefulWidget {
  const ReactiveRoutePage({
    super.key,
    required this.app,
    required this.builder,
  });

  final _RialAppState app;
  final WidgetBuilder builder;

  @override
  State<ReactiveRoutePage> createState() => _ReactiveRoutePageState();
}

class _ReactiveRoutePageState extends State<ReactiveRoutePage> {
  @override
  void initState() {
    super.initState();
    widget.app.revision.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant ReactiveRoutePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != widget.app) {
      oldWidget.app.revision.removeListener(_refresh);
      widget.app.revision.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.app.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

class ModernSheetAction {
  const ModernSheetAction({
    required this.title,
    required this.icon,
    required this.onPressed,
    this.subtitle,
    this.logoProvider,
    this.selected = false,
    this.destructive = false,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String? logoProvider;
  final bool selected;
  final VoidCallback onPressed;
  final bool destructive;
}

class RThemeScope extends InheritedWidget {
  const RThemeScope({super.key, required this.theme, required super.child});

  final RTheme theme;

  static RTheme? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<RThemeScope>()?.theme;
  }

  @override
  bool updateShouldNotify(covariant RThemeScope oldWidget) {
    return oldWidget.theme.dark != theme.dark ||
        oldWidget.theme.colorKey != theme.colorKey;
  }
}

RTheme themeFromContext(BuildContext context) {
  final scoped = RThemeScope.maybeOf(context);
  if (scoped != null) return scoped;
  final brightness = CupertinoTheme.of(context).brightness ?? Brightness.light;
  return RTheme(brightness == Brightness.dark, 'emerald');
}

void showModernActionSheet(
  BuildContext context, {
  String? title,
  String? message,
  required List<ModernSheetAction> actions,
}) {
  final t = themeFromContext(context);
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: CupertinoColors.black.withOpacity(t.dark ? .50 : .28),
    transitionDuration: const Duration(milliseconds: 190),
    pageBuilder: (dialogContext, _, __) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          top: false,
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.fromLTRB(
              14,
              0,
              14,
              14 + MediaQuery.of(dialogContext).viewInsets.bottom,
            ),
            child: ModernSheet(
              theme: t,
              title: title,
              message: message,
              actions: actions,
              closeContext: dialogContext,
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .055),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      );
    },
  );
}

class ModernSheet extends StatefulWidget {
  const ModernSheet({
    super.key,
    required this.theme,
    required this.actions,
    required this.closeContext,
    this.title,
    this.message,
  });

  final RTheme theme;
  final String? title;
  final String? message;
  final List<ModernSheetAction> actions;
  final BuildContext closeContext;

  @override
  State<ModernSheet> createState() => _ModernSheetState();
}

class _ModernSheetState extends State<ModernSheet> {
  final query = TextEditingController();

  @override
  void initState() {
    super.initState();
    query.addListener(_refresh);
  }

  @override
  void dispose() {
    query.removeListener(_refresh);
    query.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final normalizedQuery = normalizeText(query.text.trim());
    final showSearch = widget.actions.length > 5;
    final visibleActions = normalizedQuery.isEmpty
        ? widget.actions
        : widget.actions.where((action) {
            final haystack = normalizeText(
              '${action.title} ${action.subtitle ?? ''}',
            );
            return haystack.contains(normalizedQuery);
          }).toList();
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * .76,
      ),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: theme.border),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(theme.dark ? .38 : .10),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: theme.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              if (widget.title != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    widget.title!,
                    style: TextStyle(
                      color: theme.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              if (widget.message != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    widget.message!,
                    style: TextStyle(
                      color: theme.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (showSearch) ...[
                CupertinoTextField(
                  controller: query,
                  placeholder: 'Buscar',
                  prefix: Padding(
                    padding: const EdgeInsets.only(left: 12, right: 6),
                    child: Icon(
                      CupertinoIcons.search,
                      color: theme.muted,
                      size: 18,
                    ),
                  ),
                  placeholderStyle: TextStyle(
                    color: theme.muted,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  style: TextStyle(
                    color: theme.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                  cursorColor: theme.accent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: theme.field,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: theme.border),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Flexible(
                fit: FlexFit.loose,
                child: visibleActions.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        child: Center(
                          child: Text(
                            'Sin resultados',
                            style: TextStyle(
                              color: theme.muted,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: visibleActions.length,
                        itemBuilder: (context, index) => ModernSheetTile(
                          theme: theme,
                          action: visibleActions[index],
                          closeContext: widget.closeContext,
                        ),
                      ),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => Navigator.of(
                  widget.closeContext,
                  rootNavigator: true,
                ).pop(),
                child: Container(
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.field,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: theme.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ModernSheetTile extends StatelessWidget {
  const ModernSheetTile({
    super.key,
    required this.theme,
    required this.action,
    required this.closeContext,
  });

  final RTheme theme;
  final ModernSheetAction action;
  final BuildContext closeContext;

  @override
  Widget build(BuildContext context) {
    final color = action.destructive ? theme.red : theme.accent;
    final hasLogo = action.logoProvider != null;
    return GestureDetector(
      onTap: () {
        Navigator.of(closeContext, rootNavigator: true).pop();
        Future<void>.microtask(action.onPressed);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.symmetric(
          horizontal: hasLogo ? 14 : 12,
          vertical: hasLogo ? 12 : 11,
        ),
        decoration: BoxDecoration(
          color: action.destructive
              ? color.withOpacity(.10)
              : action.selected
              ? theme.accent.withOpacity(.12)
              : theme.field,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: action.destructive
                ? color.withOpacity(.30)
                : action.selected
                ? theme.accent.withOpacity(.34)
                : theme.border,
          ),
        ),
        child: Row(
          children: [
            action.logoProvider == null
                ? Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withOpacity(.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(action.icon, color: color, size: 20),
                  )
                : LogoBadge(
                    provider: action.logoProvider!,
                    theme: theme,
                    size: 48,
                  ),
            SizedBox(width: hasLogo ? 16 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.title,
                    style: TextStyle(
                      color: action.destructive ? color : theme.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (action.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      action.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (action.selected) ...[
              const SizedBox(width: 10),
              Icon(
                CupertinoIcons.check_mark_circled_solid,
                color: theme.accent,
                size: 22,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class UpdatePromptSheet extends StatelessWidget {
  const UpdatePromptSheet({
    super.key,
    required this.theme,
    required this.versionText,
    required this.notes,
    required this.onDownload,
    required this.onLater,
  });

  final RTheme theme;
  final String versionText;
  final String notes;
  final VoidCallback onDownload;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * .76,
      ),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: theme.border),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(theme.dark ? .38 : .10),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: theme.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Text(
                'Actualización disponible',
                style: TextStyle(
                  color: theme.ink,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Sin Rial $versionText',
                style: TextStyle(
                  color: theme.accent,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Text(
                    'Se abrirá GitHub para descargar el APK y Android te pedirá confirmar la instalación.${notes.isEmpty ? '' : '\n\n$notes'}',
                    style: TextStyle(
                      color: theme.muted,
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: onDownload,
                child: Container(
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.accent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text(
                    'Descargar actualización',
                    style: TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: onLater,
                child: Container(
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.field,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: theme.border),
                  ),
                  child: Text(
                    'Actualizar después',
                    style: TextStyle(
                      color: theme.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void showModernConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String destructiveText,
  required VoidCallback onConfirm,
}) {
  final t = themeFromContext(context);
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: CupertinoColors.black.withOpacity(t.dark ? .52 : .30),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, _, __) {
      return Center(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ModernConfirmDialog(
              theme: t,
              title: title,
              message: message,
              destructiveText: destructiveText,
              closeContext: dialogContext,
              onConfirm: onConfirm,
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return ScaleTransition(
        scale: Tween<double>(begin: .96, end: 1).animate(curve),
        child: child,
      );
    },
  );
}

class ModernConfirmDialog extends StatelessWidget {
  const ModernConfirmDialog({
    super.key,
    required this.theme,
    required this.title,
    required this.message,
    required this.destructiveText,
    required this.closeContext,
    required this.onConfirm,
  });

  final RTheme theme;
  final String title;
  final String message;
  final String destructiveText;
  final BuildContext closeContext;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: theme.border),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(theme.dark ? .40 : .12),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: theme.ink,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              color: theme.muted,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () =>
                      Navigator.of(closeContext, rootNavigator: true).pop(),
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.field,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Text(
                      'Cancelar',
                      style: TextStyle(
                        color: theme.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(closeContext, rootNavigator: true).pop();
                    Future<void>.microtask(onConfirm);
                  },
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.red,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Text(
                      destructiveText,
                      style: const TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

void showModernNotice(
  BuildContext context, {
  required String title,
  required String message,
  String buttonText = 'Entendido',
}) {
  final t = themeFromContext(context);
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: CupertinoColors.black.withOpacity(t.dark ? .44 : .24),
    transitionDuration: const Duration(milliseconds: 170),
    pageBuilder: (dialogContext, _, __) {
      return Center(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: t.border),
                boxShadow: [
                  BoxShadow(
                    color: CupertinoColors.black.withOpacity(
                      t.dark ? .34 : .10,
                    ),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: TextStyle(
                      color: t.muted,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  GestureDetector(
                    onTap: () =>
                        Navigator.of(dialogContext, rootNavigator: true).pop(),
                    child: Container(
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.accent,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Text(
                        buttonText,
                        style: const TextStyle(
                          color: CupertinoColors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return ScaleTransition(
        scale: Tween<double>(begin: .975, end: 1).animate(curve),
        child: child,
      );
    },
  );
}

Future<void> showModernDateTimePicker(
  BuildContext context, {
  required RTheme theme,
  required DateTime initial,
  required ValueChanged<DateTime> onSelected,
}) async {
  final pickedDate = await pickModernDate(
    context: context,
    theme: theme,
    initial: initial,
  );
  if (!context.mounted || pickedDate == null) return;
  final pickedTime = await pickModernTime(
    context: context,
    theme: theme,
    initial: initial,
  );
  if (pickedTime == null) return;
  onSelected(
    DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    ),
  );
}

Future<void> showModernDatePicker(
  BuildContext context, {
  required RTheme theme,
  required DateTime initial,
  required ValueChanged<DateTime> onSelected,
}) async {
  final pickedDate = await pickModernDate(
    context: context,
    theme: theme,
    initial: initial,
  );
  if (pickedDate == null) return;
  onSelected(pickedDate);
}

Future<DateTime?> pickModernDate({
  required BuildContext context,
  required RTheme theme,
  required DateTime initial,
}) {
  final firstDate = DateTime(2020);
  final lastDate = DateTime.now().add(const Duration(days: 3650));
  var selected = DateTime(initial.year, initial.month, initial.day);
  if (selected.isBefore(firstDate) || selected.isAfter(lastDate)) {
    selected = DateTime.now();
  }
  var visibleMonth = DateTime(selected.year, selected.month);
  return showGeneralDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: CupertinoColors.black.withOpacity(theme.dark ? .52 : .30),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, _, __) {
      final maxHeight = math
          .min(MediaQuery.of(dialogContext).size.height * .78, 560.0)
          .toDouble();
      return Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              return Container(
                margin: const EdgeInsets.all(12),
                constraints: BoxConstraints(maxHeight: maxHeight),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: BoxDecoration(
                  color: theme.card,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: theme.border),
                  boxShadow: [
                    BoxShadow(
                      color: CupertinoColors.black.withOpacity(
                        theme.dark ? .35 : .10,
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 52,
                      height: 5,
                      decoration: BoxDecoration(
                        color: theme.border,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Seleccionar fecha',
                        style: TextStyle(
                          color: theme.ink,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.field,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: theme.border),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                minSize: 40,
                                onPressed:
                                    monthCanMove(visibleMonth, firstDate, -1)
                                    ? () => setDialogState(
                                        () => visibleMonth = DateTime(
                                          visibleMonth.year,
                                          visibleMonth.month - 1,
                                        ),
                                      )
                                    : null,
                                child: Icon(
                                  CupertinoIcons.chevron_left,
                                  color:
                                      monthCanMove(visibleMonth, firstDate, -1)
                                      ? theme.ink
                                      : theme.muted.withOpacity(.35),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  calendarMonthTitle(visibleMonth),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: theme.ink,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                minSize: 40,
                                onPressed:
                                    monthCanMove(visibleMonth, lastDate, 1)
                                    ? () => setDialogState(
                                        () => visibleMonth = DateTime(
                                          visibleMonth.year,
                                          visibleMonth.month + 1,
                                        ),
                                      )
                                    : null,
                                child: Icon(
                                  CupertinoIcons.chevron_right,
                                  color: monthCanMove(visibleMonth, lastDate, 1)
                                      ? theme.ink
                                      : theme.muted.withOpacity(.35),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: const ['L', 'M', 'M', 'J', 'V', 'S', 'D']
                                .map(
                                  (day) => Expanded(
                                    child: Text(
                                      day,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: CupertinoColors.systemGrey,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 238,
                            child: GridView.builder(
                              padding: EdgeInsets.zero,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: calendarCells(visibleMonth).length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 7,
                                    childAspectRatio: 1.08,
                                  ),
                              itemBuilder: (context, index) {
                                final day = calendarCells(visibleMonth)[index];
                                final disabled =
                                    day == null ||
                                    day.isBefore(firstDate) ||
                                    day.isAfter(lastDate);
                                final isSelected =
                                    day != null && isSameDate(day, selected);
                                final isToday =
                                    day != null &&
                                    isSameDate(day, DateTime.now());
                                return CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  minSize: 0,
                                  onPressed: disabled
                                      ? null
                                      : () => setDialogState(
                                          () => selected = day,
                                        ),
                                  child: Container(
                                    margin: const EdgeInsets.all(3),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? theme.accent
                                          : isToday
                                          ? theme.accent.withOpacity(.12)
                                          : CupertinoColors.transparent,
                                      borderRadius: BorderRadius.circular(13),
                                      border: isToday && !isSelected
                                          ? Border.all(
                                              color: theme.accent.withOpacity(
                                                .28,
                                              ),
                                            )
                                          : null,
                                    ),
                                    child: Text(
                                      day?.day.toString() ?? '',
                                      style: TextStyle(
                                        color: disabled
                                            ? theme.muted.withOpacity(.30)
                                            : isSelected
                                            ? CupertinoColors.white
                                            : theme.ink,
                                        fontSize: 15,
                                        fontWeight: isSelected || isToday
                                            ? FontWeight.w900
                                            : FontWeight.w700,
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
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: Container(
                              height: 54,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: theme.field,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: theme.border),
                              ),
                              child: Text(
                                'Cancelar',
                                style: TextStyle(
                                  color: theme.ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(selected),
                            child: Container(
                              height: 54,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: theme.accent,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Text(
                                'Guardar',
                                style: TextStyle(
                                  color: CupertinoColors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .08),
          end: Offset.zero,
        ).animate(curve),
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );
}

Future<DateTime?> pickModernTime({
  required BuildContext context,
  required RTheme theme,
  required DateTime initial,
}) {
  var hour = initial.hour % 12 == 0 ? 12 : initial.hour % 12;
  var minute = initial.minute;
  var isPm = initial.hour >= 12;
  return showGeneralDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: CupertinoColors.black.withOpacity(theme.dark ? .52 : .30),
    transitionDuration: const Duration(milliseconds: 170),
    pageBuilder: (dialogContext, _, __) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              void setHour(int delta) {
                setDialogState(() {
                  hour = ((hour - 1 + delta) % 12 + 12) % 12 + 1;
                });
              }

              void setMinute(int delta) {
                setDialogState(() {
                  minute = (minute + delta) % 60;
                  if (minute < 0) minute += 60;
                });
              }

              return Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: BoxDecoration(
                  color: theme.card,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: theme.border),
                  boxShadow: [
                    BoxShadow(
                      color: CupertinoColors.black.withOpacity(
                        theme.dark ? .35 : .10,
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 52,
                      height: 5,
                      decoration: BoxDecoration(
                        color: theme.border,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Seleccionar hora',
                        style: TextStyle(
                          color: theme.ink,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TimeAdjuster(
                            theme: theme,
                            label: 'Hora',
                            value: hour.toString().padLeft(2, '0'),
                            onDecrease: () => setHour(-1),
                            onIncrease: () => setHour(1),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TimeAdjuster(
                            theme: theme,
                            label: 'Minutos',
                            value: minute.toString().padLeft(2, '0'),
                            onDecrease: () => setMinute(-1),
                            onIncrease: () => setMinute(1),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TimePeriodButton(
                            theme: theme,
                            label: 'AM',
                            selected: !isPm,
                            onPressed: () => setDialogState(() => isPm = false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TimePeriodButton(
                            theme: theme,
                            label: 'PM',
                            selected: isPm,
                            onPressed: () => setDialogState(() => isPm = true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: Container(
                              height: 54,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: theme.field,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: theme.border),
                              ),
                              child: Text(
                                'Cancelar',
                                style: TextStyle(
                                  color: theme.ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              var hour24 = hour % 12;
                              if (isPm) hour24 += 12;
                              Navigator.of(dialogContext)
                                  .pop(DateTime(2000, 1, 1, hour24, minute));
                            },
                            child: Container(
                              height: 54,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: theme.accent,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Text(
                                'Guardar',
                                style: TextStyle(
                                  color: CupertinoColors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .08),
          end: Offset.zero,
        ).animate(curve),
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );
}

class TimeAdjuster extends StatelessWidget {
  const TimeAdjuster({
    super.key,
    required this.theme,
    required this.label,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
  });

  final RTheme theme;
  final String label;
  final String value;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.field,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: theme.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 42,
                onPressed: onDecrease,
                child: Icon(CupertinoIcons.minus, color: theme.accent),
              ),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.ink,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 42,
                onPressed: onIncrease,
                child: Icon(CupertinoIcons.plus, color: theme.accent),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class TimePeriodButton extends StatelessWidget {
  const TimePeriodButton({
    super.key,
    required this.theme,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final RTheme theme;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onPressed,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? theme.accent : theme.field,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? theme.accent : theme.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? CupertinoColors.white : theme.ink,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class RTheme {
  RTheme(this.dark, this.colorKey);
  final bool dark;
  final String colorKey;

  Color get bg => dark ? const Color(0xFF000000) : const Color(0xFFF7F5F0);
  Color get card => dark ? const Color(0xFF141820) : const Color(0xFFFFFFFF);
  Color get elevated =>
      dark ? const Color(0xFF1B202A) : const Color(0xFFFEFCF7);
  Color get field => dark ? const Color(0xFF202733) : const Color(0xFFEDE9E0);
  Color get nav => dark ? const Color(0xFF000000) : const Color(0xFFF7F5F0);
  Color get navItem => dark ? const Color(0xFF11151C) : const Color(0xFFFFFFFF);
  Color get ink => dark ? const Color(0xFFF8FAFC) : const Color(0xFF14161A);
  Color get muted => dark ? const Color(0xFFA2AAB8) : const Color(0xFF6F6A60);
  Color get border => dark ? const Color(0xFF262D39) : const Color(0xFFE4DFD5);
  Color get heroControl => dark ? const Color(0x22FFFFFF) : card;
  Color get heroControlBorder =>
      dark ? const Color(0x30FFFFFF) : const Color(0xFF8A8D94);
  ThemeColorOption get colorOption => themeColorByKey(colorKey);
  Color get accent => colorOption.colorFor(dark);
  Color get heroStart => dark
      ? Color.lerp(const Color(0xFF101721), accent, .18)!
      : Color.lerp(const Color(0xFF24304E), accent, .20)!;
  Color get heroMiddle => dark
      ? Color.lerp(const Color(0xFF243A66), accent, .45)!
      : Color.lerp(const Color(0xFF4C649E), accent, .48)!;
  Color get heroEnd => dark
      ? Color.lerp(const Color(0xFF1E5A4D), accent, .50)!
      : Color.lerp(const Color(0xFF357A5D), accent, .54)!;
  Color get green => dark ? const Color(0xFF58BE86) : const Color(0xFF2F8B63);
  Color get red => dark ? const Color(0xFFE86A7B) : const Color(0xFFC94F62);
  Color get amber => dark ? const Color(0xFFE0AE55) : const Color(0xFFAA7330);
}

class BottomChrome extends StatelessWidget {
  const BottomChrome({super.key, required this.app});
  final _RialAppState app;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      height: 84 + bottom,
      padding: EdgeInsets.fromLTRB(14, 10, 14, math.max(12, bottom)),
      decoration: BoxDecoration(
        color: t.nav,
        border: Border(top: BorderSide(color: t.border.withOpacity(.65))),
      ),
      child: Row(
        children: [
          Expanded(
            child: tabButton(context, 0, CupertinoIcons.house_fill, 'Inicio'),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: tabButton(
              context,
              1,
              CupertinoIcons.chart_bar_alt_fill,
              'Plan',
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: tabButton(
              context,
              2,
              CupertinoIcons.square_grid_2x2_fill,
              'Menú',
            ),
          ),
          const SizedBox(width: 10),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(56, 56),
            borderRadius: BorderRadius.circular(24),
            color: t.accent,
            onPressed: () => app.showQuickActions(context),
            child: const Icon(
              CupertinoIcons.plus,
              color: CupertinoColors.white,
              size: 25,
            ),
          ),
        ],
      ),
    );
  }

  Widget tabButton(
    BuildContext context,
    int index,
    IconData icon,
    String label,
  ) {
    final t = app.theme;
    final active = app.tab == index;
    return GestureDetector(
      onTap: () => app.setTab(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
        height: 58,
        decoration: BoxDecoration(
          color: active ? t.accent : t.navItem,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? t.accent : t.border.withOpacity(.85),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: active ? CupertinoColors.white : t.muted,
              size: 21,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: active ? CupertinoColors.white : t.ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.app});
  final _RialAppState app;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final accounts = app.maps('accounts');
    final movements = sortedMovements(app.maps('movements'));
    final homeCurrency = app.homeBalanceCurrency;
    final homeBalanceMode = app.homeBalanceMode;
    final balanceAccounts = homeBalanceMode == 'vesOnly'
        ? accounts.where((a) => a['currency'] == 'VES').toList()
        : accounts;
    final usd = accounts
        .where((a) => a['currency'] == 'USD')
        .fold<double>(0, (sum, a) => sum + numberValue(a['balance']));
    final ves = accounts
        .where((a) => a['currency'] == 'VES')
        .fold<double>(0, (sum, a) => sum + numberValue(a['balance']));
    final totalHome = balanceAccounts.fold<double>(
      0,
      (sum, account) =>
          sum +
          app.convertForHome(
            numberValue(account['balance']),
            account['currency']?.toString() ?? 'USD',
            homeCurrency,
          ),
    );
    final totalHomeVes = balanceAccounts.fold<double>(
      0,
      (sum, account) =>
          sum +
          app.toVes(
            numberValue(account['balance']),
            account['currency']?.toString() ?? 'USD',
          ),
    );
    final income = movements
        .where((m) => m['type'] == 'income')
        .fold<double>(
          0,
          (sum, m) =>
              sum +
              app.toUsd(
                math.max(
                  0.0,
                  numberValue(m['amount']) - numberValue(m['feeAmount']),
                ),
                m['currency']?.toString() ?? 'USD',
              ),
        );
    final expenses = movements
        .where((m) => isExpenseType(m['type']?.toString()))
        .fold<double>(0, (sum, m) {
          return sum +
              app.toUsd(
                numberValue(m['amount']) + numberValue(m['feeAmount']),
                m['currency']?.toString() ?? 'USD',
              );
        });
    final userName = app.state['userName']?.toString().trim() ?? '';
    final trend = buildBalanceTrend(
      accounts: balanceAccounts.toList(),
      movements: movements,
      adjustments: app.maps('balanceAdjustments'),
      convertValue: (amount, currency) =>
          app.convertForHome(amount, currency, homeCurrency),
      period: app.homeBalanceChangePeriod,
      now: DateTime.now(),
    );
    final opening = trend.first.amount;
    final changePercent = opening.abs() < .01
        ? 0.0
        : (trend.last.amount - opening) / opening.abs() * 100;
    final sections = <Widget>[];
    for (final section in sanitizeHomeSections(app.state['homeSections'])) {
      if (section == 'metrics') {
        sections.addAll([
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  theme: t,
                  title: 'Ingresos',
                  value: app.secureMoney(income, 'USD'),
                  color: t.green,
                  icon: CupertinoIcons.arrow_down_left_circle_fill,
                  onTap: () => app.pushPage(
                    context,
                    (_) => MovementHistoryPage(
                      app: app,
                      mode: MovementHistoryMode.income,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  theme: t,
                  title: 'Gastos',
                  value: app.secureMoney(expenses, 'USD'),
                  color: t.red,
                  icon: CupertinoIcons.arrow_up_right_circle_fill,
                  onTap: () => app.pushPage(
                    context,
                    (_) => MovementHistoryPage(
                      app: app,
                      mode: MovementHistoryMode.expense,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ]);
      } else if (section == 'accounts') {
        sections.addAll([
          SectionHeader(theme: t, title: 'Mis balances'),
          SizedBox(
            height: 178,
            child: accounts.isEmpty
                ? EmptyCard(theme: t, text: 'Agrega tu primera cuenta')
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 2,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, index) {
                      final currency = index == 0 ? 'VES' : 'USD';
                      return BalanceGroupCard(app: app, currency: currency);
                    },
                  ),
          ),
        ]);
      } else if (section == 'upcoming') {
        sections.add(UpcomingPaymentsSection(app: app));
      } else if (section == 'recent') {
        sections.addAll([
          SectionHeader(
            theme: t,
            title: 'Movimientos recientes',
            action: 'Ver todo',
            onAction: () =>
                app.pushPage(context, (_) => MovementHistoryPage(app: app)),
          ),
          if (movements.isEmpty)
            EmptyCard(theme: t, text: 'Aún no hay movimientos')
          else
            ...movements
                .take(8)
                .map((m) => MovementTile(app: app, movement: m)),
        ]);
      }
    }

    return Stack(
      children: [
        Positioned.fill(
          child: AppScroll(
            title: userName.isEmpty ? 'Bienvenido' : 'Bienvenido $userName',
            subtitle: 'a Sin Rial',
            theme: t,
            trailing: ThemeToggleButton(app: app),
            children: [
              BalanceHero(
                theme: t,
                total: totalHome,
                totalVes: totalHomeVes,
                usdBalance: usd,
                vesBalance: ves,
                currency: homeCurrency,
                rate: app.rate,
                eurRate: app.eurRate,
                usdtRate: app.usdtRate,
                hideAmounts: app.hideAmounts,
                changePercent: changePercent,
                changePeriod: app.homeBalanceChangePeriod,
                trend: trend,
                rateState: app.state,
                loadingRate: app.rateLoading,
                onRefreshRate: () => app.refreshRate(manual: true, force: true),
                onCurrencyChanged: (value) =>
                    app.mutate(() => app.state['homeBalanceCurrency'] = value),
                onCustomize: () =>
                    app.pushPage(context, (_) => HomeCustomizePage(app: app)),
                onTogglePrivacy: () => app.mutate(
                  () => app.state['hideAmounts'] = !app.hideAmounts,
                ),
              ),
              HomeShortcutRow(app: app),
              ...sections,
              const SizedBox(height: 104),
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: MediaQuery.of(context).padding.top + 10,
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              color: t.bg,
            ),
          ),
        ),
      ],
    );
  }
}

class BalanceHero extends StatelessWidget {
  const BalanceHero({
    super.key,
    required this.theme,
    required this.total,
    required this.totalVes,
    required this.usdBalance,
    required this.vesBalance,
    required this.currency,
    required this.rate,
    required this.eurRate,
    required this.usdtRate,
    required this.hideAmounts,
    required this.changePercent,
    required this.changePeriod,
    required this.loadingRate,
    required this.onRefreshRate,
    required this.onCurrencyChanged,
    required this.onCustomize,
    required this.onTogglePrivacy,
    this.trend = const [],
    this.rateState = const {},
  });
  final RTheme theme;
  final double total;
  final double totalVes;
  final double usdBalance;
  final double vesBalance;
  final String currency;
  final double rate;
  final double eurRate;
  final double usdtRate;
  final bool hideAmounts;
  final double changePercent;
  final String changePeriod;
  final bool loadingRate;
  final VoidCallback onRefreshRate;
  final ValueChanged<String> onCurrencyChanged;
  final VoidCallback onCustomize;
  final VoidCallback onTogglePrivacy;
  final List<BalancePoint> trend;
  final Map<String, dynamic> rateState;

  @override
  Widget build(BuildContext context) {
    final periodText = switch (changePeriod) {
      'week' => 'últimos 7 días',
      'month' => 'este mes',
      _ => 'hoy',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.accent.withOpacity(theme.dark ? .42 : .24),
            theme.bg.withOpacity(.10),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Mi balance',
                style: TextStyle(
                  color: theme.muted,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              HeroPrivacyButton(
                theme: theme,
                hidden: hideAmounts,
                onTap: onTogglePrivacy,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    (currency == 'USDT' && usdtRate <= 0) ||
                            (currency == 'EUR' && eurRate <= 0)
                        ? 'Sin tasa'
                        : _money(total, currency),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: theme.ink,
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (hideAmounts)
            const SizedBox(height: 24)
          else if (trend.isNotEmpty &&
              trend.first.amount.abs() < .01 &&
              trend.last.amount.abs() >= .01)
            Text(
              'Sin saldo inicial · $periodText',
              style: TextStyle(color: theme.muted, fontSize: 12),
            )
          else
            BalanceChangeBadge(
              theme: theme,
              percent: changePercent,
              suffix: periodText,
            ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  rateLine(currency),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Semantics(
                label: loadingRate ? 'Actualizando tasas' : 'Actualizar tasas',
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(36, 36),
                  onPressed: loadingRate ? null : onRefreshRate,
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Center(
                      child: loadingRate
                          ? CupertinoActivityIndicator(
                              color: theme.muted,
                              radius: 8,
                            )
                          : Icon(
                              CupertinoIcons.arrow_clockwise,
                              color: theme.muted,
                              size: 18,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (rateState.isNotEmpty)
            RateStatus(
              theme: theme,
              state: rateState,
              currency: currency,
              loading: loadingRate,
            ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              BalanceCurrencyChip(
                theme: theme,
                label: 'USD',
                value: '',
                selected: currency == 'USD',
                onTap: () => onCurrencyChanged('USD'),
              ),
              BalanceCurrencyChip(
                theme: theme,
                label: 'EUR',
                value: '',
                selected: currency == 'EUR',
                onTap: () => onCurrencyChanged('EUR'),
              ),
              BalanceCurrencyChip(
                theme: theme,
                label: 'USDT',
                value: '',
                selected: currency == 'USDT',
                onTap: () => onCurrencyChanged('USDT'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (trend.isNotEmpty)
            BalanceTrend(
              points: trend,
              theme: theme,
              currency: currency,
              hidden: hideAmounts,
              period: changePeriod,
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              material.Tooltip(
                message: 'Personalizar inicio',
                child: CupertinoButton(
                  key: const ValueKey('home-customize'),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(36, 36),
                  onPressed: onCustomize,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.heroControl,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.heroControlBorder),
                    ),
                    child: Icon(
                      CupertinoIcons.paintbrush_fill,
                      color: theme.ink,
                      size: 19,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _money(double value, String currency) {
    return hideAmounts ? hiddenMoney(currency) : money(value, currency);
  }

  String rateLine(String selectedCurrency) {
    if (selectedCurrency == 'EUR') {
      return eurRate > 0 ? 'Bs ${decimal(eurRate)} / EUR' : 'Sin tasa EUR';
    }
    if (selectedCurrency == 'USDT') {
      return usdtRate > 0 ? 'Bs ${decimal(usdtRate)} / USDT' : 'Sin tasa USDT';
    }
    return rate > 0 ? 'Bs ${decimal(rate)} / USD' : 'Sin tasa BCV';
  }
}

class HomeShortcutRow extends StatelessWidget {
  const HomeShortcutRow({super.key, required this.app});

  final _RialAppState app;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final enabled = sanitizeHomeShortcutButtons(
      app.state['homeShortcutButtons'],
    );
    final children = <Widget>[];

    void addShortcut(Widget child) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 10));
      children.add(Expanded(child: child));
    }

    for (final key in enabled) {
      addShortcut(
        HomeShortcutButton(
          key: ValueKey('home-shortcut-$key'),
          theme: t,
          icon: quickActionIcon(key),
          title: switch (key) {
            'accounts' => 'Cuentas',
            'debts' => 'Por cobrar',
            _ => optionLabel(homeShortcutOptions, key),
          },
          subtitle: quickActionSubtitle(key),
          onTap: () => app.pushPage(
            context,
            (_) => switch (key) {
              'calculator' => CalculatorPage(app: app),
              'movement' => MovementHistoryPage(app: app),
              'accounts' => AccountsPage(app: app),
              'debts' => DebtsPage(app: app),
              _ => SettingsPage(app: app),
            },
          ),
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class HomeShortcutButton extends StatelessWidget {
  const HomeShortcutButton({
    super.key,
    required this.theme,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final RTheme theme;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.card,
              shape: BoxShape.circle,
              border: Border.all(color: theme.border),
              boxShadow: [
                BoxShadow(
                  color: CupertinoColors.black.withOpacity(
                    theme.dark ? .16 : .06,
                  ),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: theme.ink, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.ink,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class BalanceChangeBadge extends StatelessWidget {
  const BalanceChangeBadge({
    super.key,
    required this.theme,
    required this.percent,
    this.suffix = '',
  });

  final double percent;
  final RTheme theme;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final positive = percent >= 0;
    final color = theme.dark
        ? (positive ? const Color(0xFF8FE1AA) : const Color(0xFFFF8EA0))
        : (positive ? const Color(0xFF176139) : const Color(0xFF9E253D));
    final icon = positive
        ? CupertinoIcons.arrow_up_right
        : CupertinoIcons.arrow_down_right;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: .12), theme.bg),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            '${positive ? '+' : ''}${percent.toStringAsFixed(1).replaceAll('.', ',')}%${suffix.isEmpty ? '' : ' $suffix'}',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class HeroPrivacyButton extends StatelessWidget {
  const HeroPrivacyButton({
    super.key,
    required this.theme,
    required this.hidden,
    required this.onTap,
  });

  final bool hidden;
  final RTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return material.Tooltip(
      message: hidden ? 'Mostrar montos' : 'Ocultar montos',
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(34, 34),
        onPressed: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: theme.heroControl,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.heroControlBorder),
          ),
          child: Icon(
            hidden ? CupertinoIcons.eye_slash_fill : CupertinoIcons.eye_fill,
            color: theme.ink,
            size: 18,
          ),
        ),
      ),
    );
  }
}

class BalanceCurrencyChip extends StatelessWidget {
  const BalanceCurrencyChip({
    super.key,
    required this.theme,
    required this.label,
    required this.value,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final RTheme theme;
  final String value;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minWidth: 68, minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? (theme.dark ? const Color(0xD8FFFFFF) : theme.ink)
            : theme.heroControl,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? theme.ink : theme.heroControlBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected
                  ? (theme.dark
                        ? const Color(0xFF111418)
                        : CupertinoColors.white)
                  : theme.ink,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (value.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? (theme.dark
                          ? const Color(0xFF111418)
                          : CupertinoColors.white)
                    : theme.ink,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      selected: selected,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(68, 36),
        onPressed: onTap,
        child: child,
      ),
    );
  }
}

class UpcomingPaymentsSection extends StatelessWidget {
  const UpcomingPaymentsSection({super.key, required this.app});

  final _RialAppState app;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final items = upcomingDebtItems(app.maps('debts'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          theme: t,
          title: 'Próximos pagos',
          action: 'Ver todo',
          onAction: () => app.pushPage(context, (_) => DebtsPage(app: app)),
        ),
        if (items.isEmpty)
          EmptyCard(theme: t, text: 'No hay pagos o cobros próximos')
        else
          ...items.take(3).map((item) {
            final kind = item['kind']?.toString() == 'receivable'
                ? 'Por cobrar'
                : 'Por pagar';
            final color = kind == 'Por cobrar' ? t.green : t.amber;
            final currency = item['currency']?.toString() ?? 'USD';
            final amount = debtNextPaymentAmount(item);
            final dueDate =
                item['nextDueDate']?.toString() ?? debtUpcomingDate(item);
            final dueLabel = displayDateOnly(dueDate).isEmpty
                ? 'Sin fecha'
                : displayDateOnly(dueDate);
            return GestureDetector(
              onTap: () => app.openDebtDetail(context, item),
              child: RCard(
                theme: t,
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: color.withOpacity(.14),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        kind == 'Por cobrar'
                            ? CupertinoIcons.arrow_down_left_circle_fill
                            : CupertinoIcons.arrow_up_right_circle_fill,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['title']?.toString().trim().isNotEmpty == true
                                ? item['title'].toString()
                                : kind,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$kind · $dueLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      app.secureMoney(amount, currency),
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

class HomeCustomizePage extends StatefulWidget {
  const HomeCustomizePage({super.key, required this.app});

  final _RialAppState app;

  @override
  State<HomeCustomizePage> createState() => _HomeCustomizePageState();
}

class _HomeCustomizePageState extends State<HomeCustomizePage> {
  late List<String> sections;
  late List<String> actions;
  late List<String> shortcuts;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    sections = sanitizeHomeSections(widget.app.state['homeSections']);
    actions = sanitizeHomeQuickActions(widget.app.state['homeQuickActions']);
    shortcuts = sanitizeHomeShortcutButtons(
      widget.app.state['homeShortcutButtons'],
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = app.theme;
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.92),
        border: null,
        middle: const Text('Personalizar inicio'),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
                children: [
                  CupertinoSlidingSegmentedControl<int>(
                    groupValue: tab,
                    backgroundColor: t.field,
                    thumbColor: t.card,
                    children: {
                      0: segmentedLabel(t, 'Accesos', tab == 0),
                      1: segmentedLabel(t, 'Widgets', tab == 1),
                    },
                    onValueChanged: (value) {
                      if (value == null) return;
                      setState(() => tab = value);
                    },
                  ),
                  const SizedBox(height: 22),
                  if (tab == 0) ...accessTab(t) else ...widgetsTab(t),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              child: PrimaryActionButton(
                theme: t,
                label: 'Guardar personalización',
                onPressed: () {
                  app.mutate(() {
                    app.state['homeSections'] = <String>[...sections];
                    app.state['homeQuickActions'] = actions.isEmpty
                        ? ['movement', 'transfer', 'account']
                        : <String>[...actions];
                    app.state['homeShortcutButtons'] = <String>[...shortcuts];
                  });
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget segmentedLabel(RTheme t, String label, bool selected) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? t.ink : t.muted,
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  List<Widget> accessTab(RTheme t) {
    final hidden = homeShortcutOptions
        .where((option) => !shortcuts.contains(option.first))
        .toList();
    return [
      customizeBlockTitle(
        t,
        CupertinoIcons.eye_fill,
        'Mostrados',
        '${shortcuts.length}/${homeShortcutOptions.length}',
      ),
      const SizedBox(height: 18),
      Wrap(
        spacing: 18,
        runSpacing: 20,
        children: shortcuts.map((key) => shortcutBubble(t, key)).toList(),
      ),
      customizeDivider(t),
      customizeBlockTitle(t, CupertinoIcons.eye_slash_fill, 'Ocultos', ''),
      if (hidden.isEmpty)
        EmptyCard(theme: t, text: 'No tienes accesos ocultos')
      else
        ...hidden.map(
          (option) => hiddenCustomizeRow(
            t,
            keyName: option.first,
            title: option.last,
            subtitle: quickActionSubtitle(option.first),
            onTap: () => setState(() => shortcuts.add(option.first)),
          ),
        ),
      SectionHeader(theme: t, title: 'Botones de crear'),
      ...homeQuickActionOptions.map((option) {
        final key = option.first;
        final enabled = actions.contains(key);
        return SettingsSwitchTile(
          theme: t,
          icon: quickActionIcon(key),
          title: option.last,
          subtitle: quickActionSubtitle(key),
          value: enabled,
          onTap: () => setState(() {
            if (enabled) {
              actions.remove(key);
            } else {
              actions.add(key);
            }
          }),
        );
      }),
    ];
  }

  List<Widget> widgetsTab(RTheme t) {
    final hidden = homeSectionOptions
        .where((option) => !sections.contains(option.first))
        .toList();
    return [
      customizeBlockTitle(
        t,
        CupertinoIcons.eye_fill,
        'Mostrados',
        '${sections.length}/${homeSectionOptions.length}',
      ),
      Text(
        'Usa las flechas para ordenar y toca el interruptor para ocultar.',
        style: TextStyle(
          color: t.muted,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 14),
      ...sections.map((key) {
        final title = optionLabel(homeSectionOptions, key);
        return HomeCustomizeTile(
          theme: t,
          title: title,
          enabled: true,
          canMoveUp: sections.indexOf(key) > 0,
          canMoveDown: sections.indexOf(key) < sections.length - 1,
          onToggle: () => setState(() => sections.remove(key)),
          onUp: () => moveHomeItem(key, -1),
          onDown: () => moveHomeItem(key, 1),
        );
      }),
      customizeDivider(t),
      customizeBlockTitle(t, CupertinoIcons.eye_slash_fill, 'Ocultos', ''),
      if (hidden.isEmpty)
        EmptyCard(theme: t, text: 'No tienes widgets ocultos')
      else
        ...hidden.map(
          (option) => hiddenCustomizeRow(
            t,
            keyName: option.first,
            title: option.last,
            subtitle: 'Toca para mostrar',
            onTap: () => setState(() => sections.add(option.first)),
          ),
        ),
    ];
  }

  Widget customizeBlockTitle(
    RTheme t,
    IconData icon,
    String title,
    String meta,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: t.muted, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: t.muted,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (meta.isNotEmpty)
            Text(
              meta,
              style: TextStyle(
                color: t.muted,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }

  Widget shortcutBubble(RTheme t, String key) {
    final index = shortcuts.indexOf(key);
    return SizedBox(
      key: ValueKey('customize-shortcut-$key'),
      width: 86,
      child: Column(
        children: [
          material.Tooltip(
            message: 'Ocultar ${optionLabel(homeShortcutOptions, key)}',
            child: CupertinoButton(
              key: ValueKey('hide-shortcut-$key'),
              padding: EdgeInsets.zero,
              onPressed: () => setState(() => shortcuts.remove(key)),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: t.elevated,
                      shape: BoxShape.circle,
                      border: Border.all(color: t.border),
                    ),
                    child: Icon(quickActionIcon(key), color: t.ink, size: 30),
                  ),
                  Positioned(
                    right: -2,
                    top: -4,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE84B55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        CupertinoIcons.minus,
                        color: CupertinoColors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: Text(
              optionLabel(homeShortcutOptions, key),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.ink,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              shortcutMoveButton(t, key, -1, index > 0),
              shortcutMoveButton(t, key, 1, index < shortcuts.length - 1),
            ],
          ),
        ],
      ),
    );
  }

  Widget shortcutMoveButton(RTheme t, String key, int delta, bool enabled) {
    return material.Tooltip(
      message: delta < 0 ? 'Mover antes' : 'Mover después',
      child: CupertinoButton(
        key: ValueKey('move-shortcut-$key-$delta'),
        padding: EdgeInsets.zero,
        minimumSize: const Size(40, 40),
        onPressed: enabled
            ? () => setState(() {
                final index = shortcuts.indexOf(key);
                shortcuts.insert(index + delta, shortcuts.removeAt(index));
              })
            : null,
        child: Icon(
          delta < 0
              ? CupertinoIcons.chevron_left
              : CupertinoIcons.chevron_right,
          size: 18,
          color: enabled ? t.ink : t.muted.withValues(alpha: .35),
        ),
      ),
    );
  }

  Widget hiddenCustomizeRow(
    RTheme t, {
    required String keyName,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: RCard(
        theme: t,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: CupertinoColors.black.withOpacity(t.dark ? .32 : .06),
                shape: BoxShape.circle,
              ),
              child: Icon(quickActionIcon(keyName), color: t.ink, size: 22),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: t.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: t.accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.plus,
                color: CupertinoColors.white,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget customizeDivider(RTheme t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: t.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Icon(CupertinoIcons.arrow_up_arrow_down, color: t.muted),
          ),
          Expanded(child: Container(height: 1, color: t.border)),
        ],
      ),
    );
  }

  void moveHomeItem(String key, int delta) {
    final index = sections.indexOf(key);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= sections.length) return;
    setState(() {
      final item = sections.removeAt(index);
      sections.insert(target, item);
    });
  }
}

class HomeCustomizeTile extends StatelessWidget {
  const HomeCustomizeTile({
    super.key,
    required this.theme,
    required this.title,
    required this.enabled,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onToggle,
    required this.onUp,
    required this.onDown,
  });

  final RTheme theme;
  final String title;
  final bool enabled;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onToggle;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    return RCard(
      theme: theme,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onToggle,
              child: Row(
                children: [
                  AppSwitch(
                    theme: theme,
                    value: enabled,
                    onChanged: (_) => onToggle(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: theme.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButtonLite(
            theme: theme,
            icon: CupertinoIcons.chevron_up,
            enabled: canMoveUp,
            onTap: onUp,
          ),
          const SizedBox(width: 6),
          IconButtonLite(
            theme: theme,
            icon: CupertinoIcons.chevron_down,
            enabled: canMoveDown,
            onTap: onDown,
          ),
        ],
      ),
    );
  }
}

class IconButtonLite extends StatelessWidget {
  const IconButtonLite({
    super.key,
    required this.theme,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final RTheme theme;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled ? theme.accent.withOpacity(.13) : theme.field,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: enabled ? theme.accent.withOpacity(.30) : theme.border,
          ),
        ),
        child: Icon(
          icon,
          color: enabled ? theme.accent : theme.muted,
          size: 17,
        ),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.theme,
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    this.onTap,
  });
  final RTheme theme;
  final String title;
  final String value;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: RCard(
        theme: theme,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: theme.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: color,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key, required this.app});
  final _RialAppState app;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    return GestureDetector(
      onTap: () => app.mutate(() => app.state['darkMode'] = !app.dark),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: t.border),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withOpacity(t.dark ? .10 : .04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(
          app.dark ? CupertinoIcons.sun_max_fill : CupertinoIcons.moon_fill,
          color: t.accent,
          size: 21,
        ),
      ),
    );
  }
}

class PrivacyToggleButton extends StatelessWidget {
  const PrivacyToggleButton({super.key, required this.app});
  final _RialAppState app;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    return GestureDetector(
      onTap: () =>
          app.mutate(() => app.state['hideAmounts'] = !app.hideAmounts),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: app.hideAmounts ? t.accent.withOpacity(.16) : t.card,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: app.hideAmounts ? t.accent.withOpacity(.36) : t.border,
          ),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withOpacity(t.dark ? .10 : .04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(
          app.hideAmounts
              ? CupertinoIcons.eye_slash_fill
              : CupertinoIcons.eye_fill,
          color: t.accent,
          size: 21,
        ),
      ),
    );
  }
}

enum MovementHistoryMode { all, income, expense }

class MovementHistoryPage extends StatefulWidget {
  const MovementHistoryPage({
    super.key,
    required this.app,
    this.mode = MovementHistoryMode.all,
  });
  final _RialAppState app;
  final MovementHistoryMode mode;

  @override
  State<MovementHistoryPage> createState() => _MovementHistoryPageState();
}

class _MovementHistoryPageState extends State<MovementHistoryPage> {
  MovementFilter filter = const MovementFilter();
  String selectedMonth = currentMonthKey();
  bool showSummaries = false;
  int _cachedRevision = -1;
  MovementFilter? _cachedFilter;
  String? _cachedMonth;
  List<String> _months = [];
  List<Map<String, dynamic>> _filtered = [];
  double _total = 0;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = app.theme;
    final accounts = app.maps('accounts');
    if (_cachedRevision != app.revision.value ||
        _cachedFilter != filter ||
        _cachedMonth != selectedMonth) {
      final byId = {for (final a in accounts) a['id'].toString(): a};
      final movements = app.maps('movements').where(matchesMode).toList();
      _months = {
        currentMonthKey(),
        selectedMonth,
        ...movements.map((m) => monthKeyFromDate(m['date']?.toString())),
      }.toList()..sort((a, b) => b.compareTo(a));
      _filtered = movements
          .where(
            (m) => monthKeyFromDate(m['date']?.toString()) == selectedMonth,
          )
          .where((m) => filter.matches(m, byId))
          .toList();
      _filtered = sortedMovements(_filtered);
      _total = _filtered.fold<double>(
        0,
        (sum, m) =>
            sum +
            app.toUsd(
              movementListAmount(m),
              m['currency']?.toString() ?? 'USD',
            ),
      );
      _cachedRevision = app.revision.value;
      _cachedFilter = filter;
      _cachedMonth = selectedMonth;
    }
    final summaries = showSummaries
        ? monthlyMovementSummaries(app, accounts, _filtered)
        : <MonthlyMovementSummary>[];
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.92),
        border: null,
        middle: Text(title),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: app.canUndo
              ? () {
                  if (!app.undoLastOperation()) {
                    showModernNotice(
                      context,
                      title: 'No se puede deshacer',
                      message: 'Los registros vinculados cambiaron.',
                    );
                  }
                  setState(() {});
                }
              : null,
          child: Semantics(
            label: 'Deshacer última operación',
            child: Icon(
              CupertinoIcons.arrow_uturn_left,
              color: app.canUndo ? t.accent : t.muted.withOpacity(.35),
              size: 22,
            ),
          ),
        ),
      ),
      child: SafeArea(
        child: CustomScrollView(
          key: const ValueKey('movement-history-scroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OptionField(
                      key: const ValueKey('movement-history-month'),
                      theme: t,
                      label: 'Mes',
                      value: monthLabelForKey(selectedMonth),
                      icon: CupertinoIcons.calendar,
                      onTap: () => showModernActionSheet(
                        context,
                        title: 'Selecciona el mes',
                        actions: [
                          for (final month in _months)
                            ModernSheetAction(
                              icon: CupertinoIcons.calendar,
                              title: monthLabelForKey(month),
                              selected: month == selectedMonth,
                              onPressed: () =>
                                  setState(() => selectedMonth = month),
                            ),
                        ],
                      ),
                    ),
                    MovementFilterControls(
                      app: app,
                      mode: widget.mode,
                      onChanged: (value) => setState(() => filter = value),
                    ),
                    RCard(
                      theme: t,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_filtered.length} operaciones',
                                  style: TextStyle(
                                    color: t.muted,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    app.secureMoney(_total, 'USD'),
                                    key: const ValueKey('filtered-total'),
                                    style: TextStyle(
                                      color: amountColor(t),
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(modeIcon, color: amountColor(t), size: 26),
                        ],
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      onPressed: () =>
                          setState(() => showSummaries = !showSummaries),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Totales del mes',
                              style: TextStyle(color: t.ink, fontSize: 15),
                            ),
                          ),
                          Icon(
                            showSummaries
                                ? CupertinoIcons.chevron_up
                                : CupertinoIcons.chevron_down,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (showSummaries)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                sliver: SliverList.builder(
                  itemCount: summaries.length,
                  itemBuilder: (_, index) => MonthlyMovementSummaryCard(
                    app: app,
                    theme: t,
                    summary: summaries[index],
                    accent: amountColor(t),
                  ),
                ),
              ),
            if (_filtered.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.all(18),
                sliver: SliverToBoxAdapter(
                  child: EmptyCard(
                    theme: t,
                    text: 'No hay operaciones en este mes para estos filtros',
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 110),
                sliver: SliverList.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (_, index) => MovementTile(
                    key: ValueKey(_filtered[index]['id']),
                    app: app,
                    movement: _filtered[index],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool matchesMode(Map<String, dynamic> movement) {
    final type = movement['type']?.toString() ?? 'expense';
    return switch (widget.mode) {
      MovementHistoryMode.all => true,
      MovementHistoryMode.income => type == 'income',
      MovementHistoryMode.expense => isExpenseType(type),
    };
  }

  String get title => switch (widget.mode) {
    MovementHistoryMode.all => 'Movimientos',
    MovementHistoryMode.income => 'Ingresos',
    MovementHistoryMode.expense => 'Gastos',
  };

  IconData get modeIcon => switch (widget.mode) {
    MovementHistoryMode.all => CupertinoIcons.list_bullet,
    MovementHistoryMode.income => CupertinoIcons.arrow_down_left_circle_fill,
    MovementHistoryMode.expense => CupertinoIcons.arrow_up_right_circle_fill,
  };

  Color amountColor(RTheme t) => switch (widget.mode) {
    MovementHistoryMode.all => t.accent,
    MovementHistoryMode.income => t.green,
    MovementHistoryMode.expense => t.red,
  };
}

class AccountDistributionEntry {
  const AccountDistributionEntry({
    required this.account,
    required this.amountUsd,
    required this.color,
  });

  final Map<String, dynamic> account;
  final double amountUsd;
  final Color color;
}

List<AccountDistributionEntry> accountDistribution(
  _RialAppState app,
  List<Map<String, dynamic>> accounts,
  List<Map<String, dynamic>> movements,
) {
  final totals = <String, double>{};
  for (final movement in movements) {
    final id = movement['accountId']?.toString() ?? '';
    if (id.isEmpty) continue;
    final raw = movementListAmount(movement);
    if (raw <= 0) continue;
    totals[id] =
        (totals[id] ?? 0) +
        app.toUsd(raw, movement['currency']?.toString() ?? 'USD');
  }

  final entries = <AccountDistributionEntry>[];
  for (final account in accounts) {
    final id = account['id']?.toString() ?? '';
    final amount = totals[id] ?? 0;
    if (amount <= 0) continue;
    entries.add(
      AccountDistributionEntry(
        account: account,
        amountUsd: amount,
        color: accountColor(account),
      ),
    );
  }
  entries.sort((a, b) => b.amountUsd.compareTo(a.amountUsd));
  return entries;
}

class MonthlyMovementSummary {
  const MonthlyMovementSummary({
    required this.monthKey,
    required this.totalUsd,
    required this.accounts,
  });

  final String monthKey;
  final double totalUsd;
  final List<MonthlyAccountMovementSummary> accounts;
}

class MonthlyAccountMovementSummary {
  const MonthlyAccountMovementSummary({
    required this.label,
    required this.amountUsd,
    required this.color,
  });

  final String label;
  final double amountUsd;
  final Color color;
}

List<MonthlyMovementSummary> monthlyMovementSummaries(
  _RialAppState app,
  List<Map<String, dynamic>> accounts,
  List<Map<String, dynamic>> movements,
) {
  final accountsById = {
    for (final account in accounts) account['id']?.toString() ?? '': account,
  };
  final totalsByMonth = <String, double>{};
  final accountTotalsByMonth = <String, Map<String, double>>{};
  for (final movement in movements) {
    final month = monthKeyFromDate(movement['date']?.toString());
    final raw = movementListAmount(movement);
    if (raw <= 0) continue;
    final amountUsd = app.toUsd(raw, movement['currency']?.toString() ?? 'USD');
    totalsByMonth[month] = (totalsByMonth[month] ?? 0) + amountUsd;
    final accountId = movement['accountId']?.toString() ?? '';
    final bucket = accountTotalsByMonth.putIfAbsent(
      month,
      () => <String, double>{},
    );
    bucket[accountId] = (bucket[accountId] ?? 0) + amountUsd;
  }

  final summaries = <MonthlyMovementSummary>[];
  for (final month in totalsByMonth.keys) {
    final accountEntries =
        (accountTotalsByMonth[month] ?? const <String, double>{}).entries
            .where((entry) => entry.value > 0)
            .map((entry) {
              final account = accountsById[entry.key];
              return MonthlyAccountMovementSummary(
                label: account == null
                    ? 'Sin cuenta'
                    : accountPrimaryName(account),
                amountUsd: entry.value,
                color: account == null
                    ? CupertinoColors.systemGrey
                    : accountColor(account),
              );
            })
            .toList()
          ..sort((a, b) => b.amountUsd.compareTo(a.amountUsd));
    summaries.add(
      MonthlyMovementSummary(
        monthKey: month,
        totalUsd: totalsByMonth[month] ?? 0,
        accounts: accountEntries,
      ),
    );
  }
  summaries.sort((a, b) => b.monthKey.compareTo(a.monthKey));
  return summaries;
}

class MonthlyMovementSummaryCard extends StatelessWidget {
  const MonthlyMovementSummaryCard({
    super.key,
    required this.app,
    required this.theme,
    required this.summary,
    required this.accent,
  });

  final _RialAppState app;
  final RTheme theme;
  final MonthlyMovementSummary summary;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return RCard(
      theme: theme,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  monthLabelForKey(summary.monthKey),
                  style: TextStyle(
                    color: theme.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                app.secureMoney(summary.totalUsd, 'USD'),
                style: TextStyle(
                  color: accent,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (summary.accounts.isNotEmpty) ...[
            const SizedBox(height: 12),
            RatioBar(
              theme: theme,
              separateParts: true,
              parts: summary.accounts
                  .map(
                    (entry) =>
                        RatioPart(color: entry.color, value: entry.amountUsd),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            ...summary.accounts.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: entry.color,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        entry.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      app.secureMoney(entry.amountUsd, 'USD'),
                      style: TextStyle(
                        color: theme.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AccountDistributionCard extends StatelessWidget {
  const AccountDistributionCard({
    super.key,
    required this.app,
    required this.theme,
    required this.entries,
  });

  final _RialAppState app;
  final RTheme theme;
  final List<AccountDistributionEntry> entries;

  @override
  Widget build(BuildContext context) {
    return RCard(
      theme: theme,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Por cuenta',
            style: TextStyle(
              color: theme.muted,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 12),
          RatioBar(
            theme: theme,
            separateParts: true,
            parts: entries
                .map(
                  (entry) =>
                      RatioPart(color: entry.color, value: entry.amountUsd),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          ...entries
              .take(5)
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: entry.color,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          accountPrimaryName(entry.account),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        app.secureMoney(entry.amountUsd, 'USD'),
                        style: TextStyle(
                          color: theme.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class BalanceGroupCard extends StatelessWidget {
  const BalanceGroupCard({
    super.key,
    required this.app,
    required this.currency,
  });

  final _RialAppState app;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final accounts = app
        .maps('accounts')
        .where((account) => account['currency']?.toString() == currency)
        .toList();
    final total = accounts.fold<double>(
      0,
      (sum, account) => sum + numberValue(account['balance']),
    );
    final secondary = currency == 'VES'
        ? '≈ ${app.secureMoney(app.convertForHome(total, 'VES', 'USD'), 'USD')}'
        : '${accounts.length} cuenta${accounts.length == 1 ? '' : 's'}';
    return GestureDetector(
      onTap: () => app.pushPage(
        context,
        (_) => CurrencyAccountsPage(app: app, currency: currency),
      ),
      child: Container(
        width: 264,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: t.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CurrencyBadgeCircle(theme: t, currency: currency),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${displayCurrency(currency)} ${currency == 'VES' ? '\u{1F1FB}\u{1F1EA}' : '\u{1F1FA}\u{1F1F8}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              app.secureMoney(total, currency),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.ink,
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              secondary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.muted,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Container(height: 1, color: t.border),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Detalles',
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(CupertinoIcons.chevron_right, color: t.muted, size: 17),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CurrencyAccountsPage extends StatelessWidget {
  const CurrencyAccountsPage({
    super.key,
    required this.app,
    required this.currency,
  });

  final _RialAppState app;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final accounts =
        app
            .maps('accounts')
            .where((account) => account['currency']?.toString() == currency)
            .toList()
          ..sort(
            (a, b) =>
                numberValue(b['balance']).compareTo(numberValue(a['balance'])),
          );
    final total = accounts.fold<double>(
      0,
      (sum, account) => sum + numberValue(account['balance']),
    );
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.92),
        border: null,
        middle: Text('Cuentas en ${displayCurrency(currency)}'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 34),
          children: [
            RCard(
              theme: t,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Balance por cuenta',
                          style: TextStyle(
                            color: t.ink,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        app.secureMoney(total, currency),
                        style: TextStyle(
                          color: t.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  if (currency == 'VES') ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: CurrencyConversionPill(
                            theme: t,
                            label: 'USD',
                            value: app.secureMoney(
                              app.convertForHome(total, 'VES', 'USD'),
                              'USD',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CurrencyConversionPill(
                            theme: t,
                            label: 'EUR',
                            value: app.secureMoney(
                              app.convertForHome(total, 'VES', 'EUR'),
                              'EUR',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CurrencyConversionPill(
                            theme: t,
                            label: 'USDT',
                            value: app.secureMoney(
                              app.convertForHome(total, 'VES', 'USDT'),
                              'USDT',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  RatioBar(
                    theme: t,
                    separateParts: true,
                    parts: accounts
                        .map(
                          (account) => RatioPart(
                            color: accountColor(account),
                            value: numberValue(account['balance']),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  ...accounts.map(
                    (account) => CurrencyAccountSummaryLine(
                      app: app,
                      account: account,
                      total: total,
                      compact: true,
                    ),
                  ),
                ],
              ),
            ),
            SectionHeader(theme: t, title: 'Cuentas'),
            if (accounts.isEmpty)
              EmptyCard(theme: t, text: 'No hay cuentas en esta moneda')
            else
              ...accounts.map(
                (account) => CurrencyAccountSummaryLine(
                  app: app,
                  account: account,
                  total: total,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CurrencyConversionPill extends StatelessWidget {
  const CurrencyConversionPill({
    super.key,
    required this.theme,
    required this.label,
    required this.value,
  });

  final RTheme theme;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: theme.field,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.muted,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.accent,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class CurrencyAccountSummaryLine extends StatelessWidget {
  const CurrencyAccountSummaryLine({
    super.key,
    required this.app,
    required this.account,
    required this.total,
    this.compact = false,
  });

  final _RialAppState app;
  final Map<String, dynamic> account;
  final double total;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final currency = account['currency']?.toString() ?? 'USD';
    final balance = numberValue(account['balance']);
    final pct = total > 0 ? (balance / total * 100).clamp(0, 999) : 0;
    final content = Row(
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: accountColor(account),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 10),
        LogoBadge(
          provider: account['provider']?.toString() ?? '',
          theme: t,
          size: compact ? 34 : 44,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                accountPrimaryName(account),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.ink,
                  fontSize: compact ? 14 : 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 3),
                Text(
                  app.secureMoney(balance, currency),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (compact)
          Text(
            app.secureMoney(balance, currency),
            style: TextStyle(
              color: t.ink,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: t.accent.withOpacity(.18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${pct.round()}%',
              style: TextStyle(
                color: t.accent,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        if (!compact) ...[
          const SizedBox(width: 8),
          Icon(CupertinoIcons.chevron_right, color: t.muted, size: 17),
        ],
      ],
    );
    if (compact) {
      return Padding(padding: const EdgeInsets.only(bottom: 9), child: content);
    }
    return GestureDetector(
      onTap: () => app.pushPage(
        context,
        (_) => AccountDetailPage(app: app, account: account),
      ),
      child: RCard(theme: t, child: content),
    );
  }
}

class CurrencyBadgeCircle extends StatelessWidget {
  const CurrencyBadgeCircle({
    super.key,
    required this.theme,
    required this.currency,
  });

  final RTheme theme;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: theme.accent.withOpacity(.16),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        currencyBadge(currency),
        style: TextStyle(
          color: theme.accent,
          fontSize: currency == 'USDT' ? 10 : 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class FilterChip extends StatelessWidget {
  const FilterChip({
    super.key,
    required this.theme,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final RTheme theme;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? theme.accent : theme.field,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? theme.accent : theme.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 190),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? CupertinoColors.white : theme.ink,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class AccountMiniCard extends StatelessWidget {
  const AccountMiniCard({super.key, required this.app, required this.account});
  final _RialAppState app;
  final Map<String, dynamic> account;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final currency = account['currency']?.toString() ?? 'USD';
    return GestureDetector(
      onTap: () => app.pushPage(
        context,
        (_) => AccountDetailPage(app: app, account: account),
      ),
      child: Container(
        width: 172,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LogoBadge(
              provider: account['provider']?.toString() ?? '',
              theme: t,
              size: 42,
            ),
            const Spacer(),
            Text(
              accountPrimaryName(account),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              accountSecondaryName(account),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              app.secureMoney(numberValue(account['balance']), currency),
              style: TextStyle(
                color: t.muted,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void accountActions(BuildContext context) {
    showModernActionSheet(
      context,
      title: accountPrimaryName(account),
      actions: [
        ModernSheetAction(
          icon: CupertinoIcons.pencil,
          title: 'Editar cuenta',
          onPressed: () => app.openAccountEditor(context, account: account),
        ),
        ModernSheetAction(
          icon: CupertinoIcons.trash_fill,
          title: 'Eliminar cuenta',
          subtitle: 'También elimina sus movimientos',
          destructive: true,
          onPressed: () => app.confirmDelete(
            context,
            'Eliminar cuenta',
            'Se eliminará esta cuenta y sus movimientos.',
            () => app.deleteAccount(account),
          ),
        ),
      ],
    );
  }
}

class MovementTile extends StatelessWidget {
  const MovementTile({super.key, required this.app, required this.movement});
  final _RialAppState app;
  final Map<String, dynamic> movement;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final type = movement['type']?.toString() ?? 'expense';
    final currency = movement['currency']?.toString() ?? 'USD';
    final sign = type == 'income'
        ? '+'
        : type == 'transfer'
        ? ''
        : '-';
    final color = type == 'income'
        ? t.green
        : type == 'transfer'
        ? t.accent
        : t.red;
    final account = app.accountById(movement['accountId']?.toString() ?? '');
    return GestureDetector(
      onTap: () => app.pushPage(
        context,
        (_) => MovementDetailPage(
          app: app,
          movementId: movement['id']?.toString() ?? '',
        ),
      ),
      child: RCard(
        theme: t,
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                type == 'transfer'
                    ? CupertinoIcons.arrow_right_arrow_left
                    : type == 'income'
                    ? CupertinoIcons.arrow_down_circle
                    : categoryIcon(movement['category']?.toString() ?? ''),
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movementTitle(movement),
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    account == null
                        ? movement['date']?.toString() ?? ''
                        : '${accountPrimaryName(account)} · ${movement['date']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              app.secureSignedMoney(
                numberValue(movement['amount']),
                currency,
                sign,
              ),
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MovementDetailPage extends StatelessWidget {
  const MovementDetailPage({
    super.key,
    required this.app,
    required this.movementId,
  });

  final _RialAppState app;
  final String movementId;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final movement = app.movementById(movementId);
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.92),
        border: null,
        middle: const Text('Detalle del movimiento'),
      ),
      child: SafeArea(
        child: movement == null
            ? Center(
                child: Text(
                  'Este movimiento ya no existe',
                  style: TextStyle(color: t.muted),
                ),
              )
            : details(context, movement),
      ),
    );
  }

  Widget details(BuildContext context, Map<String, dynamic> movement) {
    final t = app.theme;
    final type = movement['type']?.toString() ?? 'expense';
    final income = type == 'income';
    final transfer = type == 'transfer';
    final typeLabel = income
        ? 'Ingreso'
        : transfer
        ? 'Transferencia'
        : 'Gasto';
    final currency = movement['currency']?.toString() ?? 'USD';
    final amount = numberValue(movement['amount']);
    final fee = numberValue(movement['feeAmount']);
    final source = app.accountById(movement['accountId']?.toString() ?? '');
    final target = app.accountById(
      movement['targetAccountId']?.toString() ?? '',
    );
    final debtId = movement['debtId']?.toString() ?? '';
    final debt = app.debtById(debtId);
    final date = parseMovementDate(movement['date']?.toString());
    final method = movement['paymentMethod']?.toString() ?? '';
    final feeMode = movement['feeMode']?.toString() ?? '';
    final scope = movement['bankTransferScope']?.toString() ?? '';
    final category = movement['category']?.toString().trim() ?? '';
    final color = income
        ? t.green
        : transfer
        ? t.accent
        : t.red;
    final sign = income
        ? '+'
        : transfer
        ? ''
        : '-';

    Widget row(String label, String value) =>
        DebtDetailRow(theme: t, label: label, value: value);

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
      children: [
        Text(
          typeLabel,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          movementTitle(movement),
          style: TextStyle(
            color: t.ink,
            fontSize: 23,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              app.secureSignedMoney(amount, currency, sign),
              style: TextStyle(
                color: color,
                fontSize: 32,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: CupertinoButton(
                key: const ValueKey('edit-movement'),
                padding: const EdgeInsets.symmetric(vertical: 12),
                color: t.accent,
                onPressed: () =>
                    app.openMovementEditor(context, movement: movement),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.pencil,
                      size: 18,
                      color: CupertinoColors.white,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Editar',
                      style: TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CupertinoButton(
                key: const ValueKey('delete-movement'),
                padding: const EdgeInsets.symmetric(vertical: 12),
                color: t.red.withOpacity(.12),
                onPressed: () => app.confirmDelete(
                  context,
                  'Eliminar movimiento',
                  transfer
                      ? 'Se revertirán los importes en ambas cuentas y la comisión.'
                      : income
                      ? 'Se revertirá el total recibido en la cuenta, junto con cualquier cobro vinculado.'
                      : 'Se revertirá el importe y la comisión en la cuenta, junto con cualquier pago o cobro vinculado.',
                  () {
                    final current = app.movementById(movementId);
                    if (current != null) app.deleteMovement(current);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.trash, size: 18, color: t.red),
                    const SizedBox(width: 8),
                    Text(
                      'Eliminar',
                      style: TextStyle(
                        color: t.red,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        row(
          'Fecha',
          date.millisecondsSinceEpoch == 0 ? 'Sin fecha' : formatDate(date),
        ),
        row(
          'Hora',
          date.millisecondsSinceEpoch == 0 ? 'Sin hora' : timeOnlyLabel(date),
        ),
        row(
          transfer ? 'Cuenta de origen' : 'Cuenta',
          source == null ? 'Cuenta no disponible' : accountPrimaryName(source),
        ),
        row('Moneda', displayCurrency(currency)),
        row('Categoría', category.isEmpty ? 'Otro' : category),
        if (method.isNotEmpty) row('Método', paymentMethodLabel(method)),
        if (scope.isNotEmpty)
          row('Transferencia bancaria', bankTransferScopeLabel(scope)),
        if (!income) ...[
          row('Comisión', app.secureMoney(fee, currency)),
          if (feeMode.isNotEmpty)
            row('Cálculo de comisión', feeModeLabel(feeMode)),
        ],
        row(
          income ? 'Total recibido' : 'Total debitado',
          app.secureMoney(income ? amount - fee : amount + fee, currency),
        ),
        if (transfer) ...[
          row(
            'Cuenta de destino',
            target == null
                ? 'Cuenta no disponible'
                : accountPrimaryName(target),
          ),
          row(
            'Monto recibido en destino',
            app.secureMoney(
              numberValue(movement['targetAmount']),
              movement['targetCurrency']?.toString() ??
                  target?['currency']?.toString() ??
                  currency,
            ),
          ),
        ],
        if (numberValue(movement['rate']) > 0)
          row('Tasa registrada', decimal(numberValue(movement['rate']))),
        if (debtId.isNotEmpty) ...[
          row(
            income ? 'Cobro vinculado' : 'Deuda vinculada',
            debt == null ? 'Registro no disponible' : selectedDebtLabel(debt),
          ),
          if (debt != null)
            CupertinoButton(
              onPressed: () => app.openDebtDetail(context, debt),
              child: const Text('Ver registro vinculado'),
            ),
        ],
      ],
    );
  }
}

class BudgetPage extends StatelessWidget {
  const BudgetPage({super.key, required this.app});
  final _RialAppState app;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    const currency = 'USD';
    final salary = numberValue(app.state['budgetSalary']);
    final savings = budgetSavings(app.state);
    final periodType = currentBudgetPeriodType(app.state);
    final period = currentBudgetPeriodKey(type: periodType);
    final budgets = app
        .maps('budgets')
        .where((b) => budgetItemPeriod(b, periodType) == period)
        .toList();
    final budgetCategoriesSet = budgets
        .map((b) => b['category']?.toString() ?? '')
        .where((category) => category.isNotEmpty)
        .toSet();
    final planned = budgets.fold<double>(
      0,
      (sum, b) =>
          sum +
          convert(
            numberValue(b['limit']),
            b['currency']?.toString() ?? currency,
            currency,
            app.rate,
          ),
    );
    final spent = budgets.fold<double>(
      0,
      (sum, b) =>
          sum +
          spentForCategory(
            app.maps('movements'),
            b['category']?.toString() ?? '',
            currency,
            app.rate,
            period: period,
            periodType: periodType,
          ),
    );
    final unbudgeted = app
        .maps('movements')
        .where((movement) {
          if (!isExpenseType(movement['type']?.toString())) return false;
          if (!movementInBudgetPeriod(movement, period, periodType))
            return false;
          return !budgetCategoriesSet.contains(
            movement['category']?.toString() ?? '',
          );
        })
        .fold<double>(
          0,
          (sum, movement) =>
              sum +
              convert(
                numberValue(movement['amount']) +
                    numberValue(movement['feeAmount']),
                movement['currency']?.toString() ?? currency,
                currency,
                app.rate,
              ),
        );
    final free = salary - savings - planned;
    return AppScroll(
      title: 'Presupuesto',
      theme: t,
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        child: Icon(CupertinoIcons.pencil, color: t.accent),
        onPressed: () => showPlanActions(context, period, periodType),
      ),
      children: [
        RCard(
          theme: t,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                budgetPeriodLabel(period, periodType),
                style: TextStyle(
                  color: t.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                app.secureMoney(salary, currency),
                style: TextStyle(
                  color: t.ink,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              RatioBar(
                theme: t,
                parts: [
                  RatioPart(color: t.green, value: math.max(0, free)),
                  RatioPart(color: t.accent, value: savings),
                  RatioPart(color: t.red, value: planned),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Libre ${app.secureMoney(free, currency)} · Planeado ${app.secureMoney(planned, currency)} · Gastado ${app.secureMoney(spent, currency)}',
                style: TextStyle(
                  color: t.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () =>
              app.pushPage(context, (_) => BudgetItemEditorPage(app: app)),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 17),
            decoration: BoxDecoration(
              color: t.accent,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Center(
              child: Text(
                'Agregar gasto planeado',
                style: TextStyle(
                  color: CupertinoColors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SecondaryActionButton(
          theme: t,
          label: 'Copiar periodo anterior',
          onPressed: () => copyPreviousBudget(context, period, periodType),
        ),
        SectionHeader(theme: t, title: 'Gastos planeados'),
        if (budgets.isEmpty)
          EmptyCard(
            theme: t,
            text: 'Agrega wifi, comida, suscripciones y otros gastos del plan',
          )
        else
          ...budgets.map((b) => BudgetTile(app: app, budget: b)),
        SectionHeader(theme: t, title: 'Gastos no presupuestados'),
        RCard(
          theme: t,
          child: Row(
            children: [
              Icon(CupertinoIcons.exclamationmark_circle_fill, color: t.amber),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Fuera del plan',
                  style: TextStyle(
                    color: t.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                app.secureMoney(unbudgeted, currency),
                style: TextStyle(
                  color: unbudgeted > 0 ? t.amber : t.muted,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 104),
      ],
    );
  }

  void copyPreviousBudget(BuildContext context, String period, String type) {
    final previous = previousBudgetPeriodKey(period, type);
    final currentBudgets = app
        .maps('budgets')
        .where((item) => budgetItemPeriod(item, type) == period)
        .toList();
    if (currentBudgets.isNotEmpty) {
      showModernNotice(
        context,
        title: 'Este periodo ya tiene plan',
        message:
            'Elimina o edita los gastos actuales antes de copiar otro periodo.',
      );
      return;
    }
    final source = app
        .maps('budgets')
        .where((item) => budgetItemPeriod(item, type) == previous)
        .toList();
    if (source.isEmpty) {
      showModernNotice(
        context,
        title: 'Sin periodo anterior',
        message: 'No hay gastos planeados para copiar.',
      );
      return;
    }
    app.mutate(() {
      for (final item in source) {
        final copy = Map<String, dynamic>.from(item);
        copy['id'] = app.id();
        copy['period'] = period;
        copy['periodType'] = type;
        copy['month'] = period.split('-').take(2).join('-');
        app.rawList('budgets').add(copy);
      }
    });
  }

  void showPlanActions(BuildContext context, String period, String type) {
    showModernActionSheet(
      context,
      title: 'Presupuesto',
      actions: [
        ModernSheetAction(
          icon: CupertinoIcons.pencil,
          title: 'Editar presupuesto',
          subtitle: 'Modifica ingreso, ahorro y periodo',
          onPressed: () =>
              app.pushPage(context, (_) => BudgetPlanEditorPage(app: app)),
        ),
        ModernSheetAction(
          icon: CupertinoIcons.trash_fill,
          title: 'Eliminar presupuesto',
          subtitle: 'Borra el plan y sus gastos planeados',
          destructive: true,
          onPressed: () => app.confirmDelete(context, 'Eliminar presupuesto', 'Se borrará el presupuesto actual y los gastos planeados de este periodo.', () {
            app.mutate(() {
              app.state['budgetSalary'] = 0.0;
              app.state['budgetSavingsValue'] = 0.0;
              app.state['budgetSavingsMode'] = 'amount';
              app
                  .rawList('budgets')
                  .removeWhere(
                    (item) =>
                        item is Map &&
                        budgetItemPeriod(item.cast<String, dynamic>(), type) ==
                            period,
                  );
            });
          }),
        ),
      ],
    );
  }
}

class BudgetPlanEditorPage extends StatefulWidget {
  const BudgetPlanEditorPage({super.key, required this.app});

  final _RialAppState app;

  @override
  State<BudgetPlanEditorPage> createState() => _BudgetPlanEditorPageState();
}

class _BudgetPlanEditorPageState extends State<BudgetPlanEditorPage> {
  late final TextEditingController salary;
  late final TextEditingController savings;
  late String periodType;

  @override
  void initState() {
    super.initState();
    final app = widget.app;
    salary = TextEditingController(
      text: numberValue(app.state['budgetSalary']) == 0
          ? ''
          : plain(numberValue(app.state['budgetSalary'])),
    );
    savings = TextEditingController(
      text: numberValue(app.state['budgetSavingsValue']) == 0
          ? ''
          : plain(numberValue(app.state['budgetSavingsValue'])),
    );
    periodType = currentBudgetPeriodType(app.state);
  }

  @override
  void dispose() {
    salary.dispose();
    savings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = app.theme;
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.92),
        border: null,
        middle: const Text('Plan de gastos'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 34),
          children: [
            RField(
              theme: t,
              controller: salary,
              placeholder: periodType == 'biweekly'
                  ? 'Ingreso de la quincena'
                  : 'Ingreso del mes',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            RField(
              theme: t,
              controller: savings,
              placeholder: 'Ahorro fijo',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            KindSelector(
              theme: t,
              value: periodType,
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
              onChanged: (value) => setState(() => periodType = value),
            ),
            PrimaryActionButton(
              theme: t,
              label: 'Guardar plan',
              onPressed: () {
                app.mutate(() {
                  app.state['budgetSalary'] = parseAmount(salary.text);
                  app.state['budgetSavingsValue'] = parseAmount(savings.text);
                  app.state['budgetSavingsMode'] = 'amount';
                  app.state['budgetCurrency'] = 'USD';
                  app.state['budgetPeriodType'] = periodType;
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class BudgetItemEditorPage extends StatefulWidget {
  const BudgetItemEditorPage({super.key, required this.app, this.budget});

  final _RialAppState app;
  final Map<String, dynamic>? budget;

  @override
  State<BudgetItemEditorPage> createState() => _BudgetItemEditorPageState();
}

class _BudgetItemEditorPageState extends State<BudgetItemEditorPage> {
  late final TextEditingController amount;
  late String category;

  @override
  void initState() {
    super.initState();
    final budget = widget.budget;
    final budgetLimit = numberValue(budget?['limit']);
    final budgetCurrency = budget?['currency']?.toString() ?? 'USD';
    amount = TextEditingController(
      text: budget == null
          ? ''
          : plain(
              budgetCurrency == 'USD'
                  ? budgetLimit
                  : widget.app.toUsd(budgetLimit, budgetCurrency),
            ),
    );
    category = budget?['category']?.toString() ?? budgetCategories.first;
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = app.theme;
    final editing = widget.budget != null;
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.92),
        border: null,
        middle: Text(editing ? 'Editar gasto' : 'Nuevo gasto'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 34),
          children: [
            OptionField(
              theme: t,
              label: 'Categoría',
              value: category,
              icon: categoryIcon(category),
              onTap: () => pickCategory(
                context,
                category,
                (value) => setState(() => category = value),
              ),
            ),
            RField(
              theme: t,
              controller: amount,
              placeholder: 'Monto del periodo',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            PrimaryActionButton(
              theme: t,
              label: editing ? 'Guardar cambios' : 'Agregar gasto',
              onPressed: save,
            ),
          ],
        ),
      ),
    );
  }

  void save() {
    final app = widget.app;
    final periodType = currentBudgetPeriodType(app.state);
    final period = currentBudgetPeriodKey(type: periodType);
    app.mutate(() {
      final item = {
        'id': widget.budget?['id'] ?? app.id(),
        'category': category,
        'limit': parseAmount(amount.text),
        'currency': 'USD',
        'month': period.split('-').take(2).join('-'),
        'period': period,
        'periodType': periodType,
      };
      final list = app.rawList('budgets');
      final index = list.indexWhere((e) => e is Map && e['id'] == item['id']);
      if (index >= 0) {
        list[index] = item;
      } else {
        list.add(item);
      }
    });
    Navigator.pop(context);
  }
}

class BudgetTile extends StatelessWidget {
  const BudgetTile({super.key, required this.app, required this.budget});
  final _RialAppState app;
  final Map<String, dynamic> budget;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    const currency = 'USD';
    final periodType = budget['periodType']?.toString() == 'biweekly'
        ? 'biweekly'
        : currentBudgetPeriodType(app.state);
    final period = budgetItemPeriod(budget, periodType);
    final spent = spentForCategory(
      app.maps('movements'),
      budget['category']?.toString() ?? '',
      currency,
      app.rate,
      period: period,
      periodType: periodType,
    );
    final limit = numberValue(budget['limit']);
    return GestureDetector(
      onTap: () => actions(context),
      child: RCard(
        theme: t,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: t.accent.withOpacity(.14),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    categoryIcon(budget['category']?.toString() ?? ''),
                    color: t.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    budget['category']?.toString() ?? 'Gasto',
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${app.secureMoney(spent, currency)} / ${app.secureMoney(limit, currency)}',
                  style: TextStyle(
                    color: t.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            RatioBar(
              theme: t,
              parts: [
                RatioPart(
                  color: spent > limit ? t.red : t.accent,
                  value: math.min(spent, limit),
                ),
                RatioPart(color: t.field, value: math.max(0, limit - spent)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void actions(BuildContext context) {
    showModernActionSheet(
      context,
      title: budget['category']?.toString() ?? 'Gasto',
      actions: [
        ModernSheetAction(
          icon: CupertinoIcons.arrow_up_right_circle_fill,
          title: 'Registrar gasto',
          subtitle: 'Usa esta categoría en Nuevo movimiento',
          onPressed: () => app.openMovementEditor(
            context,
            defaultType: 'expense',
            defaultCategory: budget['category']?.toString(),
          ),
        ),
        ModernSheetAction(
          icon: CupertinoIcons.pencil,
          title: 'Editar',
          onPressed: () => app.pushPage(
            context,
            (_) => BudgetItemEditorPage(app: app, budget: budget),
          ),
        ),
        ModernSheetAction(
          icon: CupertinoIcons.trash_fill,
          title: 'Eliminar',
          subtitle: 'Se quitará del plan',
          destructive: true,
          onPressed: () => app.confirmDelete(
            context,
            'Eliminar gasto',
            'Se quitará del plan.',
            () {
              app.mutate(
                () => app
                    .rawList('budgets')
                    .removeWhere((e) => e is Map && e['id'] == budget['id']),
              );
            },
          ),
        ),
      ],
    );
  }
}

class MenuPage extends StatelessWidget {
  const MenuPage({super.key, required this.app});
  final _RialAppState app;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    return AppScroll(
      title: 'Menú',
      theme: t,
      children: [
        MenuTile(
          theme: t,
          icon: CupertinoIcons.creditcard_fill,
          title: 'Cuentas',
          subtitle: 'Bancos y billeteras',
          onTap: () => app.pushPage(context, (_) => AccountsPage(app: app)),
        ),
        MenuTile(
          theme: t,
          icon: CupertinoIcons.flag_fill,
          title: 'Metas y ahorros',
          subtitle: 'Fondo, ahorro general y objetivos',
          onTap: () => app.pushPage(context, (_) => SavingsPage(app: app)),
        ),
        MenuTile(
          theme: t,
          icon: CupertinoIcons.calendar_badge_plus,
          title: 'Por cobrar / pagar',
          subtitle: 'Deudas, cobros y vencimientos',
          onTap: () => app.pushPage(context, (_) => DebtsPage(app: app)),
        ),
        MenuTile(
          theme: t,
          icon: material.Icons.calculate_rounded,
          title: 'Calculadora',
          subtitle: 'Tasas BCV y tasa personalizada',
          onTap: () => app.pushPage(context, (_) => CalculatorPage(app: app)),
        ),
        MenuTile(
          theme: t,
          icon: CupertinoIcons.gear_alt_fill,
          title: 'Ajustes',
          subtitle: 'Tema y datos',
          onTap: () => app.pushPage(context, (_) => SettingsPage(app: app)),
        ),
        const SizedBox(height: 104),
      ],
    );
  }
}

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key, required this.app});

  final _RialAppState app;

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  final amount = TextEditingController();
  final customRate = TextEditingController();
  String from = 'USD';
  String to = 'VES';
  bool useCustomRate = false;

  @override
  void initState() {
    super.initState();
    customRate.text = plain(widget.app.rate);
    amount.addListener(_refresh);
    customRate.addListener(_refresh);
  }

  @override
  void dispose() {
    amount.removeListener(_refresh);
    customRate.removeListener(_refresh);
    amount.dispose();
    customRate.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = app.theme;
    final amountValue = parseAmount(amount.text);
    final directUsdVes =
        (from == 'USD' && to == 'VES') || (from == 'VES' && to == 'USD');
    final directEurVes =
        (from == 'EUR' && to == 'VES') || (from == 'VES' && to == 'EUR');
    final directUsdtVes =
        (from == 'USDT' && to == 'VES') || (from == 'VES' && to == 'USDT');
    final canCustomizeRate = directUsdVes || directEurVes || directUsdtVes;
    final rateCurrency = directEurVes
        ? 'EUR'
        : directUsdtVes
        ? 'USDT'
        : 'USD';
    final currentUsdtRate = numberValue(app.state['usdtRate']);
    final marketUsdtRate = currentUsdtRate > 0
        ? currentUsdtRate
        : numberValue(app.state['previousUsdtRate']);
    final baseRate = directEurVes
        ? app.eurRate
        : directUsdtVes
        ? marketUsdtRate
        : app.rate;
    final customValue = parseAmount(customRate.text);
    final usdVes = useCustomRate && directUsdVes && customValue > 0
        ? customValue
        : app.rate;
    final eurVes = useCustomRate && directEurVes && customValue > 0
        ? customValue
        : app.eurRate;
    final usdtVes = useCustomRate && directUsdtVes && customValue > 0
        ? customValue
        : marketUsdtRate;
    final result = convertCurrencyAmount(
      amountValue,
      from,
      to,
      usdVes: usdVes,
      eurVes: eurVes,
      usdtVes: usdtVes,
    );
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.92),
        border: null,
        middle: const Text('Calculadora'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 34),
          children: [
            RCard(
              theme: t,
              child: Column(
                children: [
                  CurrencySelectorPill(
                    theme: t,
                    label: 'Desde',
                    currency: from,
                    onTap: () => pickValue(
                      context,
                      currencyPickerLabels(except: to),
                      displayCurrency(from),
                      (value) => setState(() {
                        from = currencyCodeFromLabel(value);
                        if (from == to) to = firstDifferentCurrency(from);
                        useCustomRate = false;
                        customRate.clear();
                      }),
                    ),
                  ),
                  const SizedBox(height: 12),
                  RField(
                    theme: t,
                    controller: amount,
                    placeholder: 'Monto',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => setState(() {
                        final currentFrom = from;
                        from = to;
                        to = currentFrom;
                      }),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: t.accent,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          CupertinoIcons.arrow_up_arrow_down,
                          color: CupertinoColors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  CurrencySelectorPill(
                    theme: t,
                    label: 'Hacia',
                    currency: to,
                    onTap: () => pickValue(
                      context,
                      currencyPickerLabels(except: from),
                      displayCurrency(to),
                      (value) => setState(() {
                        to = currencyCodeFromLabel(value);
                        if (from == to) from = firstDifferentCurrency(to);
                        useCustomRate = false;
                        customRate.clear();
                      }),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Resultado',
                      style: TextStyle(
                        color: t.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      result == null
                          ? 'Falta una tasa válida'
                          : app.secureMoney(result, to),
                      style: TextStyle(
                        color: t.ink,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (canCustomizeRate && !useCustomRate) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OfficialRateNote(
                        theme: t,
                        line: directUsdtVes
                            ? marketUsdtRate > 0
                                  ? '1₮ = Bs. ${decimal(marketUsdtRate)}'
                                  : 'Tasa USDT no disponible'
                            : officialRateLine(rateCurrency, baseRate),
                        updated: directUsdtVes
                            ? 'Al Cambio · USDT/VES'
                            : rateUpdatedLabel(app.state),
                      ),
                    ),
                    RateStatus(
                      theme: t,
                      state: app.state,
                      currency: rateCurrency,
                      loading: app.rateLoading,
                    ),
                  ],
                ],
              ),
            ),
            if (canCustomizeRate)
              SettingsSwitchTile(
                theme: t,
                title: 'Usar tasa personalizada',
                subtitle: 'Solo para esta conversión $rateCurrency/VES',
                icon: CupertinoIcons.checkmark_circle_fill,
                value: useCustomRate,
                onTap: () => setState(() {
                  if (!useCustomRate &&
                      customRate.text.isEmpty &&
                      baseRate > 0) {
                    customRate.text = plain(baseRate);
                  }
                  useCustomRate = !useCustomRate;
                }),
                framed: true,
              ),
            if (canCustomizeRate && useCustomRate)
              RField(
                theme: t,
                controller: customRate,
                placeholder: 'Tasa $rateCurrency/VES personalizada',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class OfficialRateNote extends StatelessWidget {
  const OfficialRateNote({
    super.key,
    required this.theme,
    required this.line,
    required this.updated,
  });

  final RTheme theme;
  final String line;
  final String updated;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          line,
          style: TextStyle(
            color: theme.ink,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          updated,
          style: TextStyle(
            color: theme.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class CurrencySelectorPill extends StatelessWidget {
  const CurrencySelectorPill({
    super.key,
    required this.theme,
    required this.label,
    required this.currency,
    required this.onTap,
  });

  final RTheme theme;
  final String label;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.field,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: theme.accent.withOpacity(.14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Center(
                child: Text(
                  currency == 'USDT' ? '₮' : currencyBadge(currency),
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: theme.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    displayCurrency(currency),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_down, color: theme.muted, size: 18),
          ],
        ),
      ),
    );
  }
}

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key, required this.app});
  final _RialAppState app;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final accounts = app.maps('accounts');
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.85),
        border: null,
        middle: const Text('Cuentas'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          child: const Icon(CupertinoIcons.plus),
          onPressed: () => app.openAccountEditor(context),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            if (accounts.isEmpty)
              EmptyCard(theme: t, text: 'Aún no hay cuentas'),
            ...accounts.map((a) => AccountRow(app: app, account: a)),
          ],
        ),
      ),
    );
  }
}

class AccountRow extends StatelessWidget {
  const AccountRow({super.key, required this.app, required this.account});
  final _RialAppState app;
  final Map<String, dynamic> account;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    return GestureDetector(
      onTap: () => app.pushPage(
        context,
        (_) => AccountDetailPage(app: app, account: account),
      ),
      child: RCard(
        theme: t,
        child: Row(
          children: [
            LogoBadge(
              provider: account['provider']?.toString() ?? '',
              theme: t,
              size: 48,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    accountPrimaryName(account),
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    accountSecondaryName(account),
                    style: TextStyle(
                      color: t.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              app.secureMoney(
                numberValue(account['balance']),
                account['currency']?.toString() ?? 'USD',
              ),
              style: TextStyle(
                color: t.ink,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AccountDetailPage extends StatelessWidget {
  const AccountDetailPage({
    super.key,
    required this.app,
    required this.account,
  });
  final _RialAppState app;
  final Map<String, dynamic> account;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final current = app.accountById(account['id']?.toString() ?? '') ?? account;
    final currency = current['currency']?.toString() ?? 'USD';
    final movements = sortedMovements(app.maps('movements')).where((movement) {
      final id = current['id']?.toString() ?? '';
      return movement['accountId']?.toString() == id ||
          movement['targetAccountId']?.toString() == id;
    }).toList();
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.92),
        border: null,
        middle: Text(accountPrimaryName(current)),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          child: Icon(CupertinoIcons.ellipsis_circle, color: t.accent),
          onPressed: () => options(context, current),
        ),
      ),
      child: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 34),
          children: [
            RCard(
              theme: t,
              child: Row(
                children: [
                  LogoBadge(
                    provider: current['provider']?.toString() ?? '',
                    theme: t,
                    size: 58,
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          accountPrimaryName(current),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.ink,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          accountSecondaryName(current),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          app.secureMoney(
                            numberValue(current['balance']),
                            currency,
                          ),
                          style: TextStyle(
                            color: t.accent,
                            fontSize: 27,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: AccountQuickActionButton(
                    theme: t,
                    label: 'Gasto',
                    icon: CupertinoIcons.arrow_up_right_circle_fill,
                    color: t.red,
                    onTap: () => app.openMovementEditor(
                      context,
                      defaultType: 'expense',
                      defaultAccountId: current['id']?.toString(),
                      lockAccount: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AccountQuickActionButton(
                    theme: t,
                    label: 'Ingreso',
                    icon: CupertinoIcons.arrow_down_left_circle_fill,
                    color: t.green,
                    onTap: () => app.openMovementEditor(
                      context,
                      defaultType: 'income',
                      defaultAccountId: current['id']?.toString(),
                      lockAccount: true,
                    ),
                  ),
                ),
              ],
            ),
            AccountQuickActionButton(
              theme: t,
              label: 'Transferir desde esta cuenta',
              icon: CupertinoIcons.arrow_right_arrow_left_circle_fill,
              color: t.accent,
              fullWidth: true,
              onTap: () => app.openMovementEditor(
                context,
                defaultType: 'transfer',
                defaultAccountId: current['id']?.toString(),
                lockAccount: true,
              ),
            ),
            SectionHeader(theme: t, title: 'Movimientos de esta cuenta'),
            if (movements.isEmpty)
              EmptyCard(theme: t, text: 'Aún no hay movimientos en esta cuenta')
            else
              ...movements.map(
                (movement) => MovementTile(app: app, movement: movement),
              ),
          ],
        ),
      ),
    );
  }

  void options(BuildContext context, Map<String, dynamic> current) {
    showModernActionSheet(
      context,
      title: accountPrimaryName(current),
      actions: [
        ModernSheetAction(
          icon: CupertinoIcons.pencil,
          title: 'Editar cuenta',
          onPressed: () => app.openAccountEditor(context, account: current),
        ),
        ModernSheetAction(
          icon: CupertinoIcons.trash_fill,
          title: 'Eliminar cuenta',
          subtitle: 'También elimina sus movimientos',
          destructive: true,
          onPressed: () => app.confirmDelete(
            context,
            'Eliminar cuenta',
            'Se eliminará esta cuenta y sus movimientos.',
            () {
              app.deleteAccount(current);
              Navigator.of(context).pop();
            },
          ),
        ),
      ],
    );
  }
}

class AccountQuickActionButton extends StatelessWidget {
  const AccountQuickActionButton({
    super.key,
    required this.theme,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.fullWidth = false,
  });

  final RTheme theme;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 58,
        margin: EdgeInsets.only(bottom: 12, top: fullWidth ? 0 : 0),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(theme.dark ? .18 : .12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(.34)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SavingsPage extends StatelessWidget {
  const SavingsPage({super.key, required this.app});
  final _RialAppState app;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final funds = savingsFunds(app.state);
    final goals = app.maps('goals');
    final activeGoals = goals
        .where(
          (goal) => numberValue(goal['saved']) < numberValue(goal['target']),
        )
        .toList();
    final completedGoals = goals
        .where(
          (goal) =>
              numberValue(goal['target']) > 0 &&
              numberValue(goal['saved']) >= numberValue(goal['target']),
        )
        .toList();
    final totalTarget = goals.fold<double>(
      0,
      (sum, goal) => sum + numberValue(goal['target']),
    );
    final totalSaved = goals.fold<double>(
      0,
      (sum, goal) => sum + numberValue(goal['saved']),
    );
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.85),
        border: null,
        middle: const Text('Metas y ahorros'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: SavingFundCard(
                    app: app,
                    fundKey: 'emergency',
                    title: 'Fondo de emergencia',
                    icon: CupertinoIcons.shield_fill,
                    fund: funds['emergency'] as Map<String, dynamic>,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SavingFundCard(
                    app: app,
                    fundKey: 'general',
                    title: 'Ahorros generales',
                    icon: CupertinoIcons.money_dollar_circle_fill,
                    fund: funds['general'] as Map<String, dynamic>,
                  ),
                ),
              ],
            ),
            PrimaryActionButton(
              theme: t,
              label: 'Nueva meta',
              onPressed: () =>
                  app.pushPage(context, (_) => GoalEditorPage(app: app)),
            ),
            RCard(
              theme: t,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Progreso de metas',
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    totalTarget <= 0
                        ? 'Define una meta para empezar'
                        : '${((totalSaved / totalTarget) * 100).clamp(0, 100).round()}% · ${app.secureMoney(totalSaved, 'USD')} de ${app.secureMoney(totalTarget, 'USD')}',
                    style: TextStyle(
                      color: t.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  RatioBar(
                    theme: t,
                    parts: [
                      RatioPart(
                        color: t.accent,
                        value: math.min(totalSaved, totalTarget),
                      ),
                      RatioPart(
                        color: t.field,
                        value: math.max(0, totalTarget - totalSaved),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SectionHeader(theme: t, title: 'Metas activas'),
            if (goals.isEmpty)
              EmptyCard(theme: t, text: 'Crea metas para objetivos concretos'),
            if (goals.isNotEmpty && activeGoals.isEmpty)
              EmptyCard(theme: t, text: 'No hay metas activas'),
            ...activeGoals.map((g) => GoalTile(app: app, goal: g)),
            SectionHeader(theme: t, title: 'Completadas y cumplidas'),
            if (completedGoals.isEmpty)
              EmptyCard(theme: t, text: 'Las metas cumplidas aparecerán aquí')
            else
              ...completedGoals.map((g) => GoalTile(app: app, goal: g)),
          ],
        ),
      ),
    );
  }
}

class SavingFundCard extends StatelessWidget {
  const SavingFundCard({
    super.key,
    required this.app,
    required this.fundKey,
    required this.title,
    required this.icon,
    required this.fund,
  });
  final _RialAppState app;
  final String fundKey;
  final String title;
  final IconData icon;
  final Map<String, dynamic> fund;

  @override
  Widget build(BuildContext context) {
    final theme = app.theme;
    final saved = numberValue(fund['saved']);
    final target = numberValue(fund['target']);
    return GestureDetector(
      onTap: () => app.pushPage(
        context,
        (_) => SavingFundDetailsPage(
          app: app,
          fundKey: fundKey,
          title: title,
          icon: icon,
        ),
      ),
      child: RCard(
        theme: theme,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.accent),
            const SizedBox(height: 18),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              target <= 0
                  ? app.secureMoney(saved, 'USD')
                  : '${app.secureMoney(saved, 'USD')} / ${app.secureMoney(target, 'USD')}',
              style: TextStyle(
                color: theme.muted,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            RatioBar(
              theme: theme,
              parts: [
                RatioPart(color: theme.accent, value: math.min(saved, target)),
                RatioPart(
                  color: theme.field,
                  value: math.max(0, target - saved),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SavingFundDetailsPage extends StatelessWidget {
  const SavingFundDetailsPage({
    super.key,
    required this.app,
    required this.fundKey,
    required this.title,
    required this.icon,
  });

  final _RialAppState app;
  final String fundKey;
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final fund = savingsFunds(app.state)[fundKey] as Map<String, dynamic>;
    final saved = numberValue(fund['saved']);
    final target = numberValue(fund['target']);
    final history = (fund['history'] is List ? fund['history'] as List : [])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList()
        .reversed
        .toList();
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.92),
        border: null,
        middle: Text(title),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 34),
          children: [
            RCard(
              theme: t,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: t.accent, size: 28),
                  const SizedBox(height: 12),
                  Text(
                    app.secureMoney(saved, 'USD'),
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    target <= 0
                        ? 'Sin objetivo definido'
                        : 'Objetivo ${app.secureMoney(target, 'USD')}',
                    style: TextStyle(
                      color: t.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  RatioBar(
                    theme: t,
                    parts: [
                      RatioPart(
                        color: t.accent,
                        value: math.min(saved, target),
                      ),
                      RatioPart(
                        color: t.field,
                        value: math.max(0, target - saved),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: SecondaryActionButton(
                    theme: t,
                    label: 'Retirar',
                    onPressed: () => openTransaction(context, withdraw: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryActionButton(
                    theme: t,
                    label: 'Agregar',
                    onPressed: () => openTransaction(context, withdraw: false),
                  ),
                ),
              ],
            ),
            SecondaryActionButton(
              theme: t,
              label: 'Editar objetivo',
              onPressed: () => app.pushPage(
                context,
                (_) => SavingsTargetEditorPage(
                  app: app,
                  fundKey: fundKey,
                  title: title,
                ),
              ),
            ),
            SectionHeader(theme: t, title: 'Historial'),
            if (history.isEmpty)
              EmptyCard(theme: t, text: 'Todavía no hay movimientos aquí')
            else
              ...history.map(
                (item) => SavingsHistoryTile(app: app, item: item),
              ),
          ],
        ),
      ),
    );
  }

  void openTransaction(BuildContext context, {required bool withdraw}) {
    if (app.usableAccounts().isEmpty) {
      showModernNotice(
        context,
        title: 'Primero agrega una cuenta',
        message:
            'Necesitas una cuenta para mover dinero desde o hacia ahorros.',
      );
      return;
    }
    app.pushPage(
      context,
      (_) => SavingsTransactionPage(
        app: app,
        targetType: 'fund',
        targetId: fundKey,
        title: title,
        withdraw: withdraw,
      ),
    );
  }
}

class GoalTile extends StatelessWidget {
  const GoalTile({super.key, required this.app, required this.goal});
  final _RialAppState app;
  final Map<String, dynamic> goal;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final saved = numberValue(goal['saved']);
    final target = numberValue(goal['target']);
    return GestureDetector(
      onTap: () => actions(context),
      child: RCard(
        theme: t,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(CupertinoIcons.flag_fill, color: t.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    goal['title']?.toString() ?? 'Meta',
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${((target <= 0 ? 0 : saved / target) * 100).clamp(0, 100).round()}%',
                  style: TextStyle(
                    color: t.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${app.secureMoney(saved, 'USD')} / ${app.secureMoney(target, 'USD')}',
              style: TextStyle(
                color: t.muted,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            RatioBar(
              theme: t,
              parts: [
                RatioPart(color: t.accent, value: math.min(saved, target)),
                RatioPart(color: t.field, value: math.max(0, target - saved)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void actions(BuildContext context) {
    final title = goal['title']?.toString() ?? 'Meta';
    showModernActionSheet(
      context,
      title: title,
      actions: [
        ModernSheetAction(
          icon: CupertinoIcons.plus_circle_fill,
          title: 'Agregar ahorro',
          onPressed: () => openTransaction(context, withdraw: false),
        ),
        ModernSheetAction(
          icon: CupertinoIcons.minus_circle_fill,
          title: 'Retirar',
          onPressed: () => openTransaction(context, withdraw: true),
        ),
        ModernSheetAction(
          icon: CupertinoIcons.pencil,
          title: 'Editar meta',
          onPressed: () => app.pushPage(
            context,
            (_) => GoalEditorPage(app: app, goal: goal),
          ),
        ),
        ModernSheetAction(
          icon: CupertinoIcons.trash_fill,
          title: 'Eliminar meta',
          destructive: true,
          onPressed: () => app.confirmDelete(
            context,
            'Eliminar meta',
            'Se eliminará esta meta y su historial.',
            () => app.mutate(
              () => app
                  .rawList('goals')
                  .removeWhere(
                    (item) => item is Map && item['id'] == goal['id'],
                  ),
            ),
          ),
        ),
      ],
    );
  }

  void openTransaction(BuildContext context, {required bool withdraw}) {
    if (app.usableAccounts().isEmpty) {
      showModernNotice(
        context,
        title: 'Primero agrega una cuenta',
        message: 'Necesitas una cuenta para mover dinero desde o hacia metas.',
      );
      return;
    }
    app.pushPage(
      context,
      (_) => SavingsTransactionPage(
        app: app,
        targetType: 'goal',
        targetId: goal['id']?.toString() ?? '',
        title: goal['title']?.toString() ?? 'Meta',
        withdraw: withdraw,
      ),
    );
  }
}

class GoalEditorPage extends StatefulWidget {
  const GoalEditorPage({super.key, required this.app, this.goal});

  final _RialAppState app;
  final Map<String, dynamic>? goal;

  @override
  State<GoalEditorPage> createState() => _GoalEditorPageState();
}

class _GoalEditorPageState extends State<GoalEditorPage> {
  late final TextEditingController title;
  late final TextEditingController target;

  @override
  void initState() {
    super.initState();
    final goal = widget.goal;
    title = TextEditingController(text: goal?['title']?.toString() ?? '');
    target = TextEditingController(
      text: goal == null ? '' : plain(numberValue(goal['target'])),
    );
  }

  @override
  void dispose() {
    title.dispose();
    target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.app.theme;
    final editing = widget.goal != null;
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.92),
        border: null,
        middle: Text(editing ? 'Editar meta' : 'Nueva meta'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 34),
          children: [
            RField(
              theme: t,
              controller: title,
              placeholder: 'Nombre de la meta',
            ),
            RField(
              theme: t,
              controller: target,
              placeholder: 'Objetivo en dólares',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            PrimaryActionButton(
              theme: t,
              label: editing ? 'Guardar cambios' : 'Crear meta',
              onPressed: save,
            ),
          ],
        ),
      ),
    );
  }

  void save() {
    final app = widget.app;
    final name = title.text.trim();
    final targetValue = parseAmount(target.text);
    if (name.isEmpty || targetValue <= 0) {
      showModernNotice(
        context,
        title: 'Meta incompleta',
        message: 'Coloca un nombre y un objetivo mayor a cero.',
      );
      return;
    }
    app.mutate(() {
      final list = app.rawList('goals');
      final item = {
        'id': widget.goal?['id'] ?? app.id(),
        'title': name,
        'target': targetValue,
        'saved': numberValue(widget.goal?['saved']),
        'currency': 'USD',
        'history': widget.goal?['history'] is List
            ? widget.goal!['history']
            : <dynamic>[],
      };
      final index = list.indexWhere(
        (entry) => entry is Map && entry['id'] == item['id'],
      );
      if (index >= 0) {
        list[index] = item;
      } else {
        list.add(item);
      }
    });
    Navigator.pop(context);
  }
}

class SavingsTargetEditorPage extends StatefulWidget {
  const SavingsTargetEditorPage({
    super.key,
    required this.app,
    required this.fundKey,
    required this.title,
  });

  final _RialAppState app;
  final String fundKey;
  final String title;

  @override
  State<SavingsTargetEditorPage> createState() =>
      _SavingsTargetEditorPageState();
}

class _SavingsTargetEditorPageState extends State<SavingsTargetEditorPage> {
  late final TextEditingController target;

  @override
  void initState() {
    super.initState();
    final fund =
        savingsFunds(widget.app.state)[widget.fundKey] as Map<String, dynamic>;
    target = TextEditingController(
      text: numberValue(fund['target']) <= 0
          ? ''
          : plain(numberValue(fund['target'])),
    );
  }

  @override
  void dispose() {
    target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.app.theme;
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.92),
        border: null,
        middle: const Text('Editar objetivo'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 34),
          children: [
            RField(
              theme: t,
              controller: target,
              placeholder: 'Objetivo en dólares',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            PrimaryActionButton(
              theme: t,
              label: 'Guardar objetivo',
              onPressed: () {
                widget.app.mutate(() {
                  final fund =
                      savingsFunds(widget.app.state)[widget.fundKey]
                          as Map<String, dynamic>;
                  fund['target'] = parseAmount(target.text);
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class SavingsTransactionPage extends StatefulWidget {
  const SavingsTransactionPage({
    super.key,
    required this.app,
    required this.targetType,
    required this.targetId,
    required this.title,
    required this.withdraw,
  });

  final _RialAppState app;
  final String targetType;
  final String targetId;
  final String title;
  final bool withdraw;

  @override
  State<SavingsTransactionPage> createState() => _SavingsTransactionPageState();
}

class _SavingsTransactionPageState extends State<SavingsTransactionPage> {
  final amount = TextEditingController();
  late String accountId;

  @override
  void initState() {
    super.initState();
    final accounts = widget.app.usableAccounts();
    accountId = accounts.isEmpty ? '' : accounts.first['id']?.toString() ?? '';
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = app.theme;
    final account = app.accountById(accountId);
    final currency = account?['currency']?.toString() ?? 'USD';
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.92),
        border: null,
        middle: Text(widget.withdraw ? 'Retirar' : 'Agregar ahorro'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 34),
          children: [
            RCard(
              theme: t,
              child: Text(
                widget.title,
                style: TextStyle(
                  color: t.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            OptionField(
              theme: t,
              label: 'Cuenta',
              value: accountLabel(account),
              logoProvider: account?['provider']?.toString(),
              onTap: () => pickSavingsAccount(context),
            ),
            RField(
              theme: t,
              controller: amount,
              placeholder: 'Monto en ${displayCurrency(currency)}',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            PrimaryActionButton(
              theme: t,
              label: widget.withdraw ? 'Retirar ahorro' : 'Agregar ahorro',
              onPressed: save,
            ),
          ],
        ),
      ),
    );
  }

  void pickSavingsAccount(BuildContext context) {
    final accounts = widget.app.usableAccounts();
    showModernActionSheet(
      context,
      title: 'Selecciona cuenta',
      actions: accounts
          .map(
            (account) => ModernSheetAction(
              icon: CupertinoIcons.creditcard_fill,
              logoProvider: account['provider']?.toString(),
              selected: account['id']?.toString() == accountId,
              title: accountPrimaryName(account),
              subtitle: accountSecondaryName(account),
              onPressed: () =>
                  setState(() => accountId = account['id']?.toString() ?? ''),
            ),
          )
          .toList(),
    );
  }

  void save() {
    final app = widget.app;
    final account = app.accountById(accountId);
    final rawAmount = parseAmount(amount.text);
    if (account == null || rawAmount <= 0) {
      showModernNotice(
        context,
        title: 'Monto pendiente',
        message: 'Selecciona una cuenta y coloca un monto mayor a cero.',
      );
      return;
    }
    final currency = account['currency']?.toString() ?? 'USD';
    final deltaUsd = app.toUsd(rawAmount, currency);
    final target = savingsTargetMap(app, widget.targetType, widget.targetId);
    if (target == null) return;
    final saved = numberValue(target['saved']);
    if (widget.withdraw && deltaUsd > saved + .0001) {
      showModernNotice(
        context,
        title: 'Ahorro insuficiente',
        message: 'No puedes retirar más de lo que tienes guardado.',
      );
      return;
    }
    app.mutate(() {
      account['balance'] =
          numberValue(account['balance']) +
          (widget.withdraw ? rawAmount : -rawAmount);
      target['saved'] = math.max(
        0.0,
        saved + (widget.withdraw ? -deltaUsd : deltaUsd),
      );
      final history = target['history'] is List
          ? target['history'] as List
          : <dynamic>[];
      history.add({
        'id': app.id(),
        'type': widget.withdraw ? 'withdraw' : 'deposit',
        'amount': rawAmount,
        'currency': currency,
        'deltaUsd': deltaUsd,
        'accountId': accountId,
        'date': formatDateTime(DateTime.now()),
      });
      target['history'] = history;
    });
    Navigator.pop(context);
  }
}

class SavingsHistoryTile extends StatelessWidget {
  const SavingsHistoryTile({super.key, required this.app, required this.item});
  final _RialAppState app;
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final withdraw = item['type'] == 'withdraw';
    final account = app.accountById(item['accountId']?.toString() ?? '');
    return RCard(
      theme: t,
      child: Row(
        children: [
          Icon(
            withdraw
                ? CupertinoIcons.arrow_up_circle
                : CupertinoIcons.arrow_down_circle,
            color: withdraw ? t.red : t.green,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  withdraw ? 'Retiro' : 'Ahorro agregado',
                  style: TextStyle(
                    color: t.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (account != null) accountPrimaryName(account),
                    item['date']?.toString() ?? '',
                  ].where((value) => value.isNotEmpty).join(' · '),
                  style: TextStyle(
                    color: t.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            app.secureMoney(
              numberValue(item['amount']),
              item['currency']?.toString() ?? 'USD',
            ),
            style: TextStyle(
              color: withdraw ? t.red : t.green,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class DebtsPage extends StatelessWidget {
  const DebtsPage({super.key, required this.app});
  final _RialAppState app;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final debts = app.maps('debts');
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.85),
        border: null,
        middle: const Text('Por cobrar / pagar'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => app.openDebtEditor(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Center(
                  child: Text(
                    'Nuevo registro',
                    style: TextStyle(
                      color: CupertinoColors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (debts.isEmpty)
              EmptyCard(theme: t, text: 'Tus pagos y cobros aparecerán aquí'),
            ...debts.map((d) => DebtTile(app: app, debt: d)),
          ],
        ),
      ),
    );
  }
}

class DebtDetailPage extends StatelessWidget {
  const DebtDetailPage({super.key, required this.app, required this.debtId});

  final _RialAppState app;
  final String debtId;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final debt = app.debtById(debtId);
    if (debt == null) {
      return CupertinoPageScaffold(
        backgroundColor: t.bg,
        navigationBar: CupertinoNavigationBar(
          transitionBetweenRoutes: false,
          backgroundColor: t.bg.withOpacity(.92),
          border: null,
          middle: const Text('Registro'),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 34),
            children: [EmptyCard(theme: t, text: 'Este registro ya no existe')],
          ),
        ),
      );
    }

    final kind = debt['kind']?.toString() == 'receivable'
        ? 'receivable'
        : 'payable';
    final currency = debt['currency']?.toString() ?? 'USD';
    final title = selectedDebtLabel(debt);
    final creditor = debt['creditor']?.toString().trim() ?? '';
    final partyType = debt['partyType']?.toString() ?? creditor;
    final partyLogo = debt['partyLogo']?.toString().trim().isNotEmpty == true
        ? debt['partyLogo'].toString()
        : debtPartyLogoCode(partyType);
    final color = kind == 'receivable' ? t.green : t.amber;
    final total = numberValue(debt['amount']);
    final paid = numberValue(debt['paidAmount']);
    final remaining = debtRemainingAmount(debt);
    final completed = remaining <= .0001;
    final hasInstallments = debtHasInstallments(debt);
    final installmentCount = debtInstallmentCount(debt);
    final installment = numberValue(debt['installmentAmount']);
    final frequency = debt['paymentFrequency']?.toString().trim() ?? '';
    final nextDate = debtUpcomingDate(debt);
    final dates = debtInstallmentDates(debt);
    final linkedMovements =
        app
            .maps('movements')
            .where((movement) => movement['debtId']?.toString() == debtId)
            .toList()
          ..sort(
            (a, b) =>
                parseMovementDate(b['date']?.toString())
                    .compareTo(parseMovementDate(a['date']?.toString())),
          );

    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.92),
        border: null,
        middle: Text(kind == 'receivable' ? 'Por cobrar' : 'Por pagar'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 34),
          children: [
            RCard(
              theme: t,
              child: Row(
                children: [
                  if (partyLogo != null)
                    LogoBadge(provider: partyLogo, theme: t, size: 54)
                  else
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: color.withOpacity(.14),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        debtPartyIcon(partyType, kind),
                        color: color,
                        size: 25,
                      ),
                    ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: t.ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          [
                            if (creditor.isNotEmpty) creditor,
                            kind == 'receivable' ? 'Por cobrar' : 'Por pagar',
                            completed ? 'Completamente pagado' : 'Pendiente',
                          ].join(' · '),
                          style: TextStyle(
                            color: completed ? t.green : t.muted,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            RCard(
              theme: t,
              child: Column(
                children: [
                  DebtDetailRow(
                    theme: t,
                    label: 'Monto total',
                    value: app.secureMoney(total, currency),
                  ),
                  DebtDetailRow(
                    theme: t,
                    label: kind == 'receivable' ? 'Cobrado' : 'Pagado',
                    value: app.secureMoney(math.min(total, paid), currency),
                  ),
                  DebtDetailRow(
                    theme: t,
                    label: 'Pendiente',
                    value: completed
                        ? 'Completamente pagado'
                        : app.secureMoney(remaining, currency),
                    valueColor: completed ? t.green : color,
                    bottom: false,
                  ),
                ],
              ),
            ),
            if (hasInstallments || displayDateOnly(nextDate).isNotEmpty)
              RCard(
                theme: t,
                child: Column(
                  children: [
                    if (hasInstallments)
                      DebtDetailRow(
                        theme: t,
                        label: 'Cuotas',
                        value: '$installmentCount cuotas',
                      ),
                    if (hasInstallments && installment > 0)
                      DebtDetailRow(
                        theme: t,
                        label: 'Monto por cuota',
                        value: app.secureMoney(installment, currency),
                      ),
                    if (hasInstallments && frequency.isNotEmpty)
                      DebtDetailRow(
                        theme: t,
                        label: 'Frecuencia',
                        value: frequency,
                      ),
                    if (displayDateOnly(nextDate).isNotEmpty)
                      DebtDetailRow(
                        theme: t,
                        label: completed ? 'Última fecha' : 'Próxima fecha',
                        value: displayDateOnly(nextDate),
                        bottom: dates.isNotEmpty,
                      ),
                    if (dates.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (var i = 0; i < dates.length; i++)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: t.field,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: t.border),
                                ),
                                child: Text(
                                  'Cuota ${i + 1}: ${dates[i]}',
                                  style: TextStyle(
                                    color: t.ink,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            if (linkedMovements.isNotEmpty)
              RCard(
                theme: t,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Movimientos vinculados',
                      style: TextStyle(
                        color: t.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...linkedMovements.take(6).map((movement) {
                      final movementCurrency =
                          movement['currency']?.toString() ?? 'USD';
                      final movementType =
                          movement['type']?.toString() ?? 'expense';
                      final sign = movementType == 'income' ? '+' : '-';
                      return DebtDetailRow(
                        theme: t,
                        label: movement['date']?.toString() ?? '',
                        value:
                            '$sign${app.secureMoney(numberValue(movement['amount']), movementCurrency)}',
                        valueColor: movementType == 'income' ? t.green : t.red,
                      );
                    }),
                  ],
                ),
              ),
            if (!completed)
              PrimaryActionButton(
                theme: t,
                label: kind == 'receivable'
                    ? 'Registrar cobro'
                    : 'Registrar pago',
                onPressed: () => app.openDebtMovement(context, debt),
              ),
            SecondaryActionButton(
              theme: t,
              label: 'Editar registro',
              onPressed: () => app.openDebtEditor(context, debt: debt),
            ),
            const SizedBox(height: 12),
            if (!completed)
              SecondaryActionButton(
                theme: t,
                label: 'Marcar como pagado',
                onPressed: () => app.markDebtPaid(debtId),
              ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => app.confirmDelete(
                context,
                'Eliminar registro',
                'Se eliminará este pago o cobro pendiente.',
                () {
                  app.deleteDebt(debtId);
                  Navigator.of(context, rootNavigator: true).maybePop();
                },
              ),
              child: Container(
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.red.withOpacity(.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: t.red.withOpacity(.35)),
                ),
                child: Text(
                  'Eliminar registro',
                  style: TextStyle(
                    color: t.red,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DebtDetailRow extends StatelessWidget {
  const DebtDetailRow({
    super.key,
    required this.theme,
    required this.label,
    required this.value,
    this.valueColor,
    this.bottom = true,
  });

  final RTheme theme;
  final String label;
  final String value;
  final Color? valueColor;
  final bool bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom ? 12 : 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: theme.muted,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor ?? theme.ink,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DebtEditorPage extends StatefulWidget {
  const DebtEditorPage({super.key, required this.app, this.debt});

  final _RialAppState app;
  final Map<String, dynamic>? debt;

  @override
  State<DebtEditorPage> createState() => _DebtEditorPageState();
}

class _DebtEditorPageState extends State<DebtEditorPage> {
  final creditor = TextEditingController();
  final title = TextEditingController();
  final total = TextEditingController();
  final initial = TextEditingController();
  final installmentAmount = TextEditingController();
  final installmentDates = <TextEditingController>[];
  final dueDate = TextEditingController(
    text: formatDate(DateTime.now().add(const Duration(days: 30))),
  );
  String currency = 'USD';
  String installments = '3';
  String frequency = 'Mensual';
  String kind = 'payable';
  String payableParty = 'Cashea';
  String receivableParty = 'Trabajo';
  bool hasInitial = false;
  bool hasInstallments = false;
  bool hasDueDate = true;
  bool notifyDueDate = true;
  bool automaticInstallments = true;

  @override
  void initState() {
    super.initState();
    final debt = widget.debt;
    if (debt == null) return;
    kind = debt['kind']?.toString() == 'receivable' ? 'receivable' : 'payable';
    final partyType = debt['partyType']?.toString().trim() ?? '';
    final options = partyOptions;
    if (kind == 'payable') {
      payableParty = options.contains(partyType) ? partyType : 'Alguien';
    } else {
      receivableParty = options.contains(partyType) ? partyType : 'Alguien';
    }
    final creditorText = debt['creditor']?.toString().trim() ?? '';
    if (needsCustomParty) creditor.text = creditorText;
    title.text = debt['title']?.toString() ?? '';
    total.text = plain(numberValue(debt['amount']));
    final initialAmount = numberValue(debt['initialAmount']);
    hasInitial = debt['initialPaid'] == true || initialAmount > 0;
    if (hasInitial) initial.text = plain(initialAmount);
    currency = debt['currency']?.toString() == 'VES' ? 'VES' : 'USD';
    hasInstallments = debtHasInstallments(debt);
    hasDueDate = debt['hasDueDate'] != false;
    notifyDueDate = debt['notifyDueDate'] != false;
    automaticInstallments = debt['installmentMode'] != 'manual';
    installments = debtInstallmentCount(debt).toString();
    frequency = debt['paymentFrequency']?.toString().trim().isNotEmpty == true
        ? debt['paymentFrequency'].toString()
        : 'Mensual';
    final installment = numberValue(debt['installmentAmount']);
    if (installment > 0) installmentAmount.text = plain(installment);
    dueDate.text = displayDateOnly(debt['dueDate']?.toString()).isEmpty
        ? formatDate(DateTime.now().add(const Duration(days: 30)))
        : displayDateOnly(debt['dueDate']?.toString());
    final dates = debtInstallmentDates(debt);
    for (final value in dates) {
      installmentDates.add(TextEditingController(text: value));
    }
  }

  @override
  void dispose() {
    creditor.dispose();
    title.dispose();
    total.dispose();
    initial.dispose();
    installmentAmount.dispose();
    for (final controller in installmentDates) {
      controller.dispose();
    }
    dueDate.dispose();
    super.dispose();
  }

  List<String> get partyOptions =>
      kind == 'payable' ? payableDebtParties : receivableDebtParties;

  String get selectedParty =>
      kind == 'payable' ? payableParty : receivableParty;

  bool get needsCustomParty =>
      selectedParty == 'Alguien' || selectedParty == 'Otro';

  String get partyLabel =>
      kind == 'payable' ? 'A quien se le debe' : 'Origen del cobro';

  String get customPartyPlaceholder =>
      selectedParty == 'Alguien' ? 'Nombre de la persona' : 'Nombre';

  void setDebtKind(String value) {
    setState(() {
      kind = value;
      if (!partyOptions.contains(selectedParty)) {
        if (kind == 'payable') {
          payableParty = payableDebtParties.first;
        } else {
          receivableParty = receivableDebtParties.first;
        }
        creditor.clear();
      }
    });
  }

  void setParty(String value) {
    setState(() {
      if (kind == 'payable') {
        payableParty = value;
      } else {
        receivableParty = value;
      }
      if (!needsCustomParty) creditor.clear();
    });
  }

  void syncInstallmentDates(int count) {
    final target = hasInstallments && hasDueDate ? count.clamp(1, 24) : 0;
    while (installmentDates.length < target) {
      installmentDates.add(
        TextEditingController(
          text: formatDate(suggestedInstallmentDate(installmentDates.length)),
        ),
      );
    }
    while (installmentDates.length > target) {
      installmentDates.removeLast().dispose();
    }
  }

  DateTime suggestedInstallmentDate(int index) {
    final parsed = parseDateOnly(dueDate.text);
    final base = parsed.year == 9999
        ? DateTime.now().add(const Duration(days: 30))
        : parsed;
    return addDebtFrequency(base, frequency, index);
  }

  void refreshInstallmentDates() {
    for (var i = 0; i < installmentDates.length; i++) {
      installmentDates[i].text = formatDate(suggestedInstallmentDate(i));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = app.theme;
    final totalValue = parseAmount(total.text);
    final initialValue = hasInitial ? parseAmount(initial.text) : 0.0;
    final rawCount = int.tryParse(installments) ?? 1;
    final count = hasInstallments && rawCount > 0 ? rawCount : 1;
    final remaining = math.max(0.0, totalValue - initialValue);
    final suggestedInstallment = splitInstallments(remaining, count).first;
    final lastInstallment = splitInstallments(remaining, count).last;
    final customInstallment = hasInstallments
        ? parseAmount(installmentAmount.text)
        : 0.0;
    final finalInstallment =
        hasInstallments && !automaticInstallments && customInstallment > 0
        ? customInstallment
        : suggestedInstallment;
    const dueLabel = 'Fecha límite';
    final selectedPartyLogo = debtPartyLogoCode(selectedParty);
    syncInstallmentDates(count);

    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.92),
        border: null,
        middle: Text(
          widget.debt == null ? 'Nuevo registro' : 'Editar registro',
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 34),
          children: [
            KindSelector(
              theme: t,
              value: kind,
              items: const [
                KindSelectorItem(
                  value: 'payable',
                  label: 'Por pagar',
                  icon: CupertinoIcons.arrow_up_right_circle_fill,
                ),
                KindSelectorItem(
                  value: 'receivable',
                  label: 'Por cobrar',
                  icon: CupertinoIcons.arrow_down_left_circle_fill,
                ),
              ],
              onChanged: setDebtKind,
            ),
            OptionField(
              theme: t,
              label: partyLabel,
              value: selectedParty,
              logoProvider: selectedPartyLogo,
              icon: selectedPartyLogo == null
                  ? debtPartyIcon(selectedParty, kind)
                  : null,
              onTap: () =>
                  pickValue(context, partyOptions, selectedParty, setParty),
            ),
            if (needsCustomParty)
              RField(
                theme: t,
                controller: creditor,
                placeholder: customPartyPlaceholder,
              ),
            RField(
              theme: t,
              controller: title,
              placeholder: kind == 'payable' ? 'Qué se debe' : 'Qué te deben',
            ),
            RField(
              theme: t,
              controller: total,
              placeholder: 'Monto total',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            OptionField(
              theme: t,
              label: 'Moneda',
              value: displayCurrency(currency),
              onTap: () => pickValue(
                context,
                const ['Dólares', 'Bolívares'],
                displayCurrency(currency),
                (value) => setState(
                  () => currency = value.startsWith('Bol') ? 'VES' : 'USD',
                ),
              ),
            ),
            KindSelector(
              theme: t,
              value: hasInitial ? 'yes' : 'no',
              items: const [
                KindSelectorItem(
                  value: 'no',
                  label: 'Sin inicial',
                  icon: CupertinoIcons.xmark_circle_fill,
                ),
                KindSelectorItem(
                  value: 'yes',
                  label: 'Con inicial',
                  icon: CupertinoIcons.check_mark_circled_solid,
                ),
              ],
              onChanged: (value) => setState(() => hasInitial = value == 'yes'),
            ),
            if (hasInitial)
              RField(
                theme: t,
                controller: initial,
                placeholder: 'Inicial pagada',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            SettingsSwitchTile(
              theme: t,
              icon: CupertinoIcons.calendar_badge_plus,
              title: 'Tiene cuotas',
              subtitle: 'Activa si se pagará por partes',
              value: hasInstallments,
              onTap: () => setState(() {
                hasInstallments = !hasInstallments;
                if (hasInstallments) {
                  hasDueDate = true;
                  automaticInstallments = true;
                }
              }),
            ),
            SettingsSwitchTile(
              theme: t,
              icon: CupertinoIcons.calendar,
              title: 'Tiene fecha',
              subtitle: 'Activa si hay vencimiento o fecha de cobro',
              value: hasDueDate,
              onTap: () => setState(() {
                hasDueDate = !hasDueDate;
                if (hasDueDate) refreshInstallmentDates();
              }),
            ),
            if (hasInstallments) ...[
              OptionField(
                theme: t,
                label: 'Cantidad de cuotas',
                value: '$installments cuotas',
                onTap: () => pickValue(
                  context,
                  debtInstallmentCountOptions,
                  installments,
                  (value) => setState(() {
                    installments = value;
                    syncInstallmentDates(int.tryParse(value) ?? count);
                  }),
                ),
              ),
              KindSelector(
                theme: t,
                value: automaticInstallments ? 'auto' : 'manual',
                items: const [
                  KindSelectorItem(
                    value: 'auto',
                    label: 'Automático',
                    icon: CupertinoIcons.wand_stars,
                  ),
                  KindSelectorItem(
                    value: 'manual',
                    label: 'Manual',
                    icon: CupertinoIcons.pencil_circle_fill,
                  ),
                ],
                onChanged: (value) =>
                    setState(() => automaticInstallments = value == 'auto'),
              ),
              if (!automaticInstallments)
                RField(
                  theme: t,
                  controller: installmentAmount,
                  placeholder: 'Monto por cuota',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              OptionField(
                theme: t,
                label: 'Frecuencia de pago',
                value: frequency,
                onTap: () => pickValue(
                  context,
                  const ['Semanal', 'Quincenal', 'Mensual', 'Personalizada'],
                  frequency,
                  (value) => setState(() {
                    frequency = value;
                    refreshInstallmentDates();
                  }),
                ),
              ),
            ],
            if (hasDueDate && !hasInstallments) ...[
              OptionField(
                theme: t,
                label: dueLabel,
                value: displayDateOnly(dueDate.text).isEmpty
                    ? 'Seleccionar fecha'
                    : displayDateOnly(dueDate.text),
                icon: CupertinoIcons.calendar,
                onTap: pickDueDate,
              ),
            ],
            if (hasDueDate && hasInstallments)
              ...List.generate(installmentDates.length, (index) {
                final controller = installmentDates[index];
                return OptionField(
                  theme: t,
                  label: 'Fecha cuota ${index + 1}',
                  value: displayDateOnly(controller.text).isEmpty
                      ? 'Seleccionar fecha'
                      : displayDateOnly(controller.text),
                  icon: CupertinoIcons.calendar,
                  onTap: () => pickInstallmentDate(index),
                );
              }),
            if (hasDueDate)
              SettingsSwitchTile(
                theme: t,
                icon: CupertinoIcons.bell_fill,
                title: 'Recordatorios',
                subtitle: 'Avisos a 7, 5, 3, 1 día, el día y si se atrasa',
                value: notifyDueDate,
                onTap: () => setState(() => notifyDueDate = !notifyDueDate),
              ),
            RCard(
              theme: t,
              child: Row(
                children: [
                  Icon(CupertinoIcons.calendar_badge_plus, color: t.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hasInstallments
                          ? 'Restan ${app.secureMoney(remaining, currency)} · $count cuotas de ${app.secureMoney(finalInstallment, currency)}${automaticInstallments && lastInstallment != finalInstallment ? ' (última: ${app.secureMoney(lastInstallment, currency)})' : ''} · $frequency'
                          : hasDueDate
                          ? 'Pendiente ${app.secureMoney(remaining, currency)} · $dueLabel ${displayDateOnly(dueDate.text)}'
                          : 'Pendiente ${app.secureMoney(remaining, currency)} · Sin fecha',
                      style: TextStyle(
                        color: t.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            PrimaryActionButton(
              theme: t,
              label: widget.debt == null
                  ? 'Guardar registro'
                  : 'Guardar cambios',
              onPressed: save,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> pickDueDate() async {
    final parsed = parseDateOnly(dueDate.text);
    final initialDate = parsed.year == 9999 ? DateTime.now() : parsed;
    await showModernDatePicker(
      context,
      theme: widget.app.theme,
      initial: initialDate,
      onSelected: (value) {
        if (!mounted) return;
        setState(() => dueDate.text = formatDate(value));
      },
    );
  }

  Future<void> pickInstallmentDate(int index) async {
    if (index < 0 || index >= installmentDates.length) return;
    final controller = installmentDates[index];
    final parsed = parseDateOnly(controller.text);
    final initialDate = parsed.year == 9999
        ? suggestedInstallmentDate(index)
        : parsed;
    await showModernDatePicker(
      context,
      theme: widget.app.theme,
      initial: initialDate,
      onSelected: (value) {
        if (!mounted) return;
        setState(() {
          controller.text = formatDate(value);
          if (index == 0) dueDate.text = controller.text;
        });
      },
    );
  }

  void save() {
    final app = widget.app;
    final amount = parseAmount(total.text);
    final customParty = creditor.text.trim();
    final creditorText = needsCustomParty ? customParty : selectedParty;
    final titleText = title.text.trim();
    if (needsCustomParty && customParty.isEmpty) {
      showModernNotice(
        context,
        title: 'Falta el nombre',
        message: kind == 'payable'
            ? 'Escribe a quien debes pagar.'
            : 'Escribe quien te debe pagar.',
      );
      return;
    }
    if (titleText.isEmpty) {
      showModernNotice(
        context,
        title: 'Falta qué se debe',
        message: kind == 'payable'
            ? 'Describe qué estás pagando.'
            : 'Describe qué te deben pagar.',
      );
      return;
    }
    if (amount <= 0) {
      showModernNotice(
        context,
        title: 'Monto pendiente',
        message: 'Coloca el monto total de la deuda.',
      );
      return;
    }
    final rawCount = int.tryParse(installments) ?? 1;
    final count = hasInstallments && rawCount > 0 ? rawCount : 1;
    final initialValue = hasInitial ? parseAmount(initial.text) : 0.0;
    if (initialValue < 0 || initialValue > amount) {
      showModernNotice(
        context,
        title: 'Inicial mayor al monto',
        message: 'La inicial debe estar entre cero y el monto total.',
      );
      return;
    }
    final remaining = math.max(0.0, moneySubtract(amount, initialValue));
    final customInstallment = hasInstallments
        ? parseAmount(installmentAmount.text)
        : 0.0;
    final calculatedInstallment = splitInstallments(remaining, count).first;
    if (hasInstallments && !automaticInstallments && customInstallment <= 0) {
      showModernNotice(
        context,
        title: 'Monto por cuota',
        message:
            'Coloca el monto manual de cada cuota o usa el modo automático.',
      );
      return;
    }
    syncInstallmentDates(count);
    final savedInstallmentDates = hasInstallments && hasDueDate
        ? installmentDates
              .take(count)
              .map((controller) => displayDateOnly(controller.text))
              .where((value) => value.isNotEmpty)
              .toList()
        : <String>[];
    final firstDueDate = savedInstallmentDates.isNotEmpty
        ? savedInstallmentDates.first
        : displayDateOnly(dueDate.text);
    final installmentValue =
        hasInstallments && !automaticInstallments && customInstallment > 0
        ? customInstallment
        : calculatedInstallment;
    final editingDebt = widget.debt;
    final editingId = editingDebt?['id']?.toString() ?? '';
    final previousPaid = editingDebt == null
        ? initialValue
        : numberValue(editingDebt['paidAmount']);
    final paidAmount = math.min(amount, math.max(initialValue, previousPaid));
    final isPaid = paidAmount + .0001 >= amount;
    try {
      app.saveDebt({
        'id': editingId.isEmpty ? app.id() : editingId,
        'kind': kind,
        'title': titleText,
        'partyType': selectedParty,
        'partyLogo': debtPartyLogoCode(selectedParty) ?? '',
        'creditor': creditorText,
        'amount': amount,
        'paidAmount': paidAmount,
        'initialAmount': initialValue,
        'initialPaid': hasInitial,
        'hasInstallments': hasInstallments,
        'hasDueDate': hasDueDate,
        'notifyDueDate': hasDueDate && notifyDueDate,
        'installments': count,
        'installmentMode': automaticInstallments ? 'auto' : 'manual',
        'installmentAmount': hasInstallments ? installmentValue : 0.0,
        'installmentDates': savedInstallmentDates,
        'currency': currency,
        'dueDate': hasDueDate ? firstDueDate : '',
        'paymentFrequency': hasInstallments ? frequency : '',
        'status': isPaid ? 'paid' : 'pending',
        'paidAt': isPaid
            ? (editingDebt?['paidAt']?.toString().isNotEmpty == true
                  ? editingDebt!['paidAt'].toString()
                  : formatDateTime(DateTime.now()))
            : '',
        'createdAt':
            editingDebt?['createdAt']?.toString() ??
            formatDateTime(DateTime.now()),
        'updatedAt': formatDateTime(DateTime.now()),
      }, editingId: editingId.isEmpty ? null : editingId);
    } on FormatException catch (error) {
      showModernNotice(
        context,
        title: 'Revisa el registro',
        message: error.message,
      );
      return;
    }
    Navigator.pop(context);
  }
}

class DebtTile extends StatelessWidget {
  const DebtTile({super.key, required this.app, required this.debt});
  final _RialAppState app;
  final Map<String, dynamic> debt;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final currency = debt['currency']?.toString() ?? 'USD';
    final kind = debt['kind']?.toString() == 'receivable'
        ? 'receivable'
        : 'payable';
    final remaining = debtRemainingAmount(debt);
    final paid = remaining <= .0001;
    final color = paid ? t.green : (kind == 'receivable' ? t.green : t.amber);
    final creditor = debt['creditor']?.toString().trim() ?? '';
    final partyType = debt['partyType']?.toString() ?? creditor;
    final partyLogo = debt['partyLogo']?.toString().trim().isNotEmpty == true
        ? debt['partyLogo'].toString()
        : debtPartyLogoCode(partyType);
    final dueDate = debtUpcomingDate(debt);
    final frequency = debt['paymentFrequency']?.toString().trim() ?? '';
    final installments = (numberValue(
      debt['installments'],
    ).round()).clamp(1, 999);
    final installment = numberValue(debt['installmentAmount']);
    final hasInstallments =
        debt['hasInstallments'] == true ||
        installments > 1 ||
        installment > 0 ||
        frequency.isNotEmpty;
    return GestureDetector(
      onTap: () => app.openDebtDetail(context, debt),
      child: RCard(
        theme: t,
        child: Row(
          children: [
            if (partyLogo != null)
              LogoBadge(provider: partyLogo, theme: t, size: 42)
            else
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(.14),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(debtPartyIcon(partyType, kind), color: color),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    debt['title']?.toString() ?? 'Cuota',
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (paid) 'Pagado',
                      if (creditor.isNotEmpty) creditor,
                      kind == 'receivable' ? 'Por cobrar' : 'Por pagar',
                      if (hasInstallments) '$installments cuotas',
                      if (hasInstallments && installment > 0)
                        app.secureMoney(installment, currency),
                      if (hasInstallments && frequency.isNotEmpty) frequency,
                      if (displayDateOnly(dueDate).isNotEmpty)
                        displayDateOnly(dueDate),
                    ].join(' · '),
                    style: TextStyle(
                      color: t.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              paid ? 'Pagado' : app.secureMoney(remaining, currency),
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void actions(BuildContext context) {
    final kind = debt['kind']?.toString() == 'receivable'
        ? 'receivable'
        : 'payable';
    showModernActionSheet(
      context,
      title: selectedDebtLabel(debt),
      actions: [
        ModernSheetAction(
          icon: kind == 'receivable'
              ? CupertinoIcons.arrow_down_left_circle_fill
              : CupertinoIcons.arrow_up_right_circle_fill,
          title: kind == 'receivable' ? 'Registrar cobro' : 'Registrar pago',
          subtitle: 'Crea un movimiento vinculado',
          onPressed: () => app.openDebtMovement(context, debt),
        ),
        ModernSheetAction(
          icon: CupertinoIcons.check_mark_circled_solid,
          title: 'Marcar como pagado',
          subtitle: 'No cambia el saldo de una cuenta',
          onPressed: () => app.markDebtPaid(debt['id']?.toString() ?? ''),
        ),
        ModernSheetAction(
          icon: CupertinoIcons.trash_fill,
          title: 'Eliminar registro',
          destructive: true,
          onPressed: () => app.confirmDelete(
            context,
            'Eliminar registro',
            'Se eliminará este pago o cobro pendiente.',
            () => app.deleteDebt(debt['id']?.toString() ?? ''),
          ),
        ),
      ],
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.app});
  final _RialAppState app;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _RialAppState get app => widget.app;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.92),
        border: null,
        middle: const Text('Ajustes'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 28, 18, 34),
          children: [
            RCard(
              theme: t,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sin Rial - versión $_appVersionName',
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'App en progreso - Hecha por Arturo el mejor xd',
                    style: TextStyle(
                      color: t.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SectionHeader(theme: t, title: 'Actualizaciones'),
            GestureDetector(
              onTap: app.updateChecking
                  ? null
                  : () => unawaited(
                      app.checkForReleaseUpdate(context, manual: true),
                    ),
              child: RCard(
                theme: t,
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: t.accent.withOpacity(.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        CupertinoIcons.cloud_download_fill,
                        color: t.accent,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.updateChecking
                                ? 'Buscando actualización'
                                : 'Buscar actualización',
                            style: TextStyle(
                              color: t.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Instalada $_appVersionName+$_appBuildNumber · automático al actualizar BCV',
                            style: TextStyle(
                              color: t.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      color: t.muted,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            SectionHeader(theme: t, title: 'Inicio'),
            GestureDetector(
              onTap: () => pickValue(
                context,
                const ['Todo el balance', 'Solo bolívares al cambio'],
                homeBalanceModeLabel(app.homeBalanceMode),
                (value) {
                  app.mutate(
                    () => app.state['homeBalanceMode'] =
                        homeBalanceModeFromLabel(value),
                  );
                  setState(() {});
                },
              ),
              child: RCard(
                theme: t,
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: t.accent.withOpacity(.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(CupertinoIcons.money_dollar, color: t.accent),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Balance principal',
                            style: TextStyle(
                              color: t.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            homeBalanceModeLabel(app.homeBalanceMode),
                            style: TextStyle(
                              color: t.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      color: t.muted,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () => pickValue(
                context,
                const ['Día', 'Semana', 'Mes'],
                homeBalancePeriodLabel(app.homeBalanceChangePeriod),
                (value) {
                  app.mutate(
                    () => app.state['homeBalanceChangePeriod'] =
                        homeBalancePeriodFromLabel(value),
                  );
                  setState(() {});
                },
              ),
              child: RCard(
                theme: t,
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: t.accent.withOpacity(.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        CupertinoIcons.chart_bar_fill,
                        color: t.accent,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Comparación del balance',
                            style: TextStyle(
                              color: t.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            homeBalancePeriodLabel(app.homeBalanceChangePeriod),
                            style: TextStyle(
                              color: t.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      color: t.muted,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            SectionHeader(theme: t, title: 'Recordatorios'),
            ReminderPermissions(theme: t),
            SettingsSwitchTile(
              theme: t,
              icon: CupertinoIcons.bell_fill,
              title: 'Registrar movimientos',
              subtitle: app.dailyMovementReminderEnabled
                  ? 'Aviso diario a las ${app.dailyReminderLabel}'
                  : 'Aviso diario desactivado',
              value: app.dailyMovementReminderEnabled,
              onTap: () {
                app.mutate(
                  () => app.state['dailyMovementReminderEnabled'] =
                      !app.dailyMovementReminderEnabled,
                );
                app.scheduleDailyReminderFromState();
                setState(() {});
              },
            ),
            GestureDetector(
              onTap: () => unawaited(
                app.pickDailyReminderTime(context).then((_) {
                  if (mounted) setState(() {});
                }),
              ),
              child: RCard(
                theme: t,
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: t.accent.withOpacity(.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(CupertinoIcons.clock_fill, color: t.accent),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hora del aviso',
                            style: TextStyle(
                              color: t.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Todos los días a las ${app.dailyReminderLabel}',
                            style: TextStyle(
                              color: t.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      color: t.muted,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            SectionHeader(theme: t, title: 'Perfil'),
            GestureDetector(
              onTap: () =>
                  app.pushPage(context, (_) => NameEditorPage(app: app)),
              child: RCard(
                theme: t,
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: t.accent.withOpacity(.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(CupertinoIcons.person_fill, color: t.accent),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nombre',
                            style: TextStyle(
                              color: t.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            app.state['userName']?.toString().trim().isEmpty ==
                                    false
                                ? app.state['userName'].toString()
                                : 'Sin nombre configurado',
                            style: TextStyle(
                              color: t.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      color: t.muted,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            SectionHeader(theme: t, title: 'Apariencia'),
            GestureDetector(
              onTap: () {
                app.mutate(() => app.state['darkMode'] = !app.dark);
                setState(() {});
              },
              child: RCard(
                theme: t,
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: t.accent.withOpacity(.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        app.dark
                            ? CupertinoIcons.moon_stars_fill
                            : CupertinoIcons.sun_max_fill,
                        color: t.accent,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.dark ? 'Modo oscuro' : 'Modo claro',
                            style: TextStyle(
                              color: t.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Solo cambia la apariencia dentro de la app',
                            style: TextStyle(
                              color: t.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    IgnorePointer(
                      child: AppSwitch(
                        theme: t,
                        value: app.dark,
                        onChanged: (_) {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SectionHeader(theme: t, title: 'Color del tema'),
            RCard(
              theme: t,
              child: ThemeColorSelector(
                theme: t,
                value: app.themeColorKey,
                onChanged: (value) {
                  app.mutate(() => app.state['themeColor'] = value);
                  setState(() {});
                },
              ),
            ),
            SectionHeader(theme: t, title: 'Seguridad'),
            SettingsSwitchTile(
              theme: t,
              icon: app.hideAmounts
                  ? CupertinoIcons.eye_slash_fill
                  : CupertinoIcons.eye_fill,
              title: app.hideAmounts ? 'Montos ocultos' : 'Mostrar montos',
              subtitle:
                  'Oculta o muestra saldos y movimientos dentro de la app',
              value: app.hideAmounts,
              onTap: () {
                app.mutate(() => app.state['hideAmounts'] = !app.hideAmounts);
                setState(() {});
              },
            ),
            GestureDetector(
              onTap: () => app.pushPage(
                context,
                (_) => SecuritySetupPage(app: app, requiredSetup: false),
              ),
              child: RCard(
                theme: t,
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: t.accent.withOpacity(.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        CupertinoIcons.lock_shield_fill,
                        color: t.accent,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PIN y biometría',
                            style: TextStyle(
                              color: t.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            app.biometricEnabled
                                ? 'PIN activo · biometría activa'
                                : 'PIN activo',
                            style: TextStyle(
                              color: t.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      color: t.muted,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                Navigator.of(
                  context,
                  rootNavigator: true,
                ).popUntil((route) => route.isFirst);
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => app.lockApp(),
                );
              },
              child: RCard(
                theme: t,
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: t.accent.withOpacity(.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(CupertinoIcons.lock_fill, color: t.accent),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        'Bloquear ahora',
                        style: TextStyle(
                          color: t.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SectionHeader(theme: t, title: 'Datos'),
            GestureDetector(
              onTap: () => confirmReset(context),
              child: RCard(
                theme: t,
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: t.red.withOpacity(.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(CupertinoIcons.trash_fill, color: t.red),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Limpiar datos',
                            style: TextStyle(
                              color: t.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Deja cuentas, movimientos, presupuestos, metas y cuotas en cero',
                            style: TextStyle(
                              color: t.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      color: t.muted,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void confirmReset(BuildContext context) {
    app.confirmDelete(
      context,
      'Limpiar datos',
      'Esto dejará la app en cero y conservará el tema actual.',
      app.resetAllData,
      destructiveText: 'Limpiar',
    );
  }
}

class NameEditorPage extends StatefulWidget {
  const NameEditorPage({super.key, required this.app});

  final _RialAppState app;

  @override
  State<NameEditorPage> createState() => _NameEditorPageState();
}

class _NameEditorPageState extends State<NameEditorPage> {
  late final TextEditingController name;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(
      text: widget.app.state['userName']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = app.theme;
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.92),
        border: null,
        middle: const Text('Editar nombre'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 34),
          children: [
            RCard(
              theme: t,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¿Cómo quieres que te salude la app?',
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  RField(theme: t, controller: name, placeholder: 'Tu nombre'),
                  PrimaryActionButton(
                    theme: t,
                    label: 'Guardar nombre',
                    onPressed: save,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void save() {
    final value = name.text.trim();
    if (value.isEmpty) {
      showModernNotice(
        context,
        title: 'Falta tu nombre',
        message: 'Escribe el nombre que quieres ver en el inicio.',
      );
      return;
    }
    widget.app.mutate(() => widget.app.state['userName'] = value);
    Navigator.of(context, rootNavigator: true).pop();
  }
}

class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.theme,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onTap,
    this.framed = true,
  });

  final RTheme theme;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final VoidCallback onTap;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      padding: EdgeInsets.all(framed ? 0 : 14),
      decoration: framed
          ? null
          : BoxDecoration(
              color: theme.field,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.border),
            ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.accent.withOpacity(.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: theme.accent),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          IgnorePointer(
            child: AppSwitch(theme: theme, value: value, onChanged: (_) {}),
          ),
        ],
      ),
    );
    return GestureDetector(
      onTap: onTap,
      child: framed
          ? RCard(theme: theme, child: tile)
          : Padding(padding: const EdgeInsets.only(bottom: 12), child: tile),
    );
  }
}

class MovementEditor extends StatefulWidget {
  const MovementEditor({
    super.key,
    required this.app,
    required this.onSave,
    this.movement,
    this.defaultType = 'expense',
    this.defaultCategory,
    this.defaultAccountId,
    this.defaultDebtId,
    this.defaultDescription,
    this.defaultAmount,
    this.lockAccount = false,
  });
  final _RialAppState app;
  final Map<String, dynamic>? movement;
  final String defaultType;
  final String? defaultCategory;
  final String? defaultAccountId;
  final String? defaultDebtId;
  final String? defaultDescription;
  final double? defaultAmount;
  final bool lockAccount;
  final ValueChanged<Map<String, dynamic>> onSave;

  @override
  State<MovementEditor> createState() => _MovementEditorState();
}

class _MovementEditorState extends State<MovementEditor> {
  late String type;
  late String accountId;
  late String targetId;
  late String category;
  late String date;
  final amount = TextEditingController();
  final desc = TextEditingController();
  final fee = TextEditingController();
  final rate = TextEditingController();
  String paymentMethod = 'payment_mobile_p2p';
  String debtId = '';
  String feeMode = 'auto';
  String bankTransferScope = 'other_bank';
  bool categoryTouched = false;

  @override
  void initState() {
    super.initState();
    final m = widget.movement;
    type = m?['type']?.toString() ?? widget.defaultType;
    accountId =
        m?['accountId']?.toString() ??
        widget.defaultAccountId ??
        preferredAccountId();
    targetId =
        m?['targetAccountId']?.toString() ?? firstAccountId(except: accountId);
    category = m?['category']?.toString().isEmpty == false
        ? m!['category'].toString()
        : widget.defaultCategory ?? 'Otro';
    categoryTouched = m != null || widget.defaultCategory != null;
    date = m?['date']?.toString() ?? formatDateTime(DateTime.now());
    debtId = m?['debtId']?.toString() ?? widget.defaultDebtId ?? '';
    if (m != null) {
      amount.text = plain(numberValue(m['amount']));
      desc.text = m['description']?.toString() ?? '';
      if (numberValue(m['feeAmount']) > 0)
        fee.text = plain(numberValue(m['feeAmount']));
      if (numberValue(m['rate']) > 0) rate.text = plain(numberValue(m['rate']));
      paymentMethod = m['paymentMethod']?.toString().isNotEmpty == true
          ? m['paymentMethod'].toString()
          : paymentMethod;
      if (paymentMethod == 'payment_mobile_p2c') {
        paymentMethod = 'payment_mobile_c2p';
      }
      final storedFeeMode = m['feeMode']?.toString() ?? '';
      feeMode = storedFeeMode.isNotEmpty
          ? storedFeeMode
          : numberValue(m['feeAmount']) > 0
          ? 'manual'
          : feeMode;
      bankTransferScope = m['bankTransferScope']?.toString().isNotEmpty == true
          ? m['bankTransferScope'].toString()
          : bankTransferScope;
    } else {
      if (widget.defaultDescription?.trim().isNotEmpty == true) {
        desc.text = widget.defaultDescription!.trim();
      }
      if ((widget.defaultAmount ?? 0) > 0) {
        amount.text = plain(widget.defaultAmount!);
      }
      if (debtId.isNotEmpty) {
        applyDebtDefaults(debtId, overwriteAmount: amount.text.isEmpty);
      }
      if (type == 'expense' && !categoryTouched) {
        category = categoryFromDescription(desc.text) ?? 'Otro';
      }
    }
  }

  @override
  void dispose() {
    amount.dispose();
    desc.dispose();
    fee.dispose();
    rate.dispose();
    super.dispose();
  }

  String firstAccountId({String except = ''}) {
    final accounts = widget.app.usableAccounts();
    for (final a in accounts) {
      final id = a['id']?.toString() ?? '';
      if (id.isNotEmpty && id != except) return id;
    }
    return '';
  }

  String preferredAccountId({String except = ''}) {
    final last = widget.app.state['lastMovementAccountId']?.toString() ?? '';
    if (last.isNotEmpty &&
        last != except &&
        widget.app.accountById(last) != null) {
      return last;
    }
    return firstAccountId(except: except);
  }

  void applyDebtDefaults(String id, {bool overwriteAmount = true}) {
    final debt = widget.app.debtById(id);
    final account = widget.app.accountById(accountId);
    if (debt == null || account == null) return;
    final debtCurrency = debt['currency']?.toString() ?? 'USD';
    final accountCurrency = account['currency']?.toString() ?? 'USD';
    final dueAmount = debtNextPaymentAmount(debt);
    final converted = convert(
      dueAmount,
      debtCurrency,
      accountCurrency,
      widget.app.rate,
    );
    if (overwriteAmount && converted > 0) {
      amount.text = plain(converted);
    }
    final debtTitle = debt['title']?.toString().trim() ?? '';
    if (debtTitle.isNotEmpty && desc.text.trim().isEmpty) {
      desc.text = debtTitle;
    }
    if (type == 'expense' && !categoryTouched) {
      category = categoryFromDescription(debtTitle) ?? category;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = app.theme;
    final source = app.accountById(accountId);
    final target = app.accountById(targetId);
    final exchange =
        type == 'transfer' &&
        source != null &&
        target != null &&
        source['currency'] != target['currency'];
    final sourceCurrency = source?['currency']?.toString() ?? 'USD';
    final targetCurrency = target?['currency']?.toString() ?? sourceCurrency;
    final enteredRate = parseAmount(rate.text);
    final targetAmount = exchange && enteredRate > 0
        ? sourceCurrency == 'USD'
              ? moneyConvert(parseAmount(amount.text), enteredRate)
              : moneyConvert(parseAmount(amount.text), 1, enteredRate)
        : parseAmount(amount.text);
    final canOperationFee =
        type == 'expense' &&
        canConfigureBankFee(
          source,
          type: type,
          category: type == 'expense' ? category : '',
          method: type == 'expense' ? paymentMethod : 'bank_transfer',
        );
    final effectiveFeeMode = canOperationFee ? feeMode : 'none';
    final canTransferFee =
        type == 'transfer' &&
        canConfigureBankFee(source, type: type, target: target);
    final autoOperationFee = canOperationFee && effectiveFeeMode == 'auto'
        ? estimatedBankFee(
            method: type == 'income' ? 'bank_transfer' : paymentMethod,
            amount: parseAmount(amount.text),
            type: type,
            category: type == 'expense' ? category : '',
            bankTransferScope: bankTransferScope,
          )
        : 0.0;
    final autoTransferFee = type == 'transfer'
        ? bankTransferFee(source, target, moneyRound(parseAmount(amount.text)))
        : 0.0;
    final selectedDebt = app.debtById(debtId);
    final debtSelectorKind = type == 'income' ? 'receivable' : 'payable';
    final hasLinkableDebt = type == 'expense' || type == 'income'
        ? app.maps('debts').any((debt) {
            final kind = debt['kind']?.toString() == 'receivable'
                ? 'receivable'
                : 'payable';
            return kind == debtSelectorKind &&
                debtRemainingAmount(debt) > .0001;
          })
        : false;
    final showDebtSelector =
        (type == 'expense' || type == 'income') &&
        (hasLinkableDebt || selectedDebt != null);
    final previewAmount = moneyRound(parseAmount(amount.text));
    final previewFee = type == 'transfer'
        ? autoTransferFee
        : effectiveFeeMode == 'manual'
        ? moneyRound(parseAmount(fee.text))
        : autoOperationFee;
    final previewTotal = type == 'income'
        ? moneySubtract(previewAmount, previewFee)
        : moneyAdd(previewAmount, previewFee);

    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.85),
        border: null,
        middle: Text(
          widget.movement == null ? 'Nuevo movimiento' : 'Editar movimiento',
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: KindSelector(
                key: const ValueKey('movement-editor-type'),
                theme: t,
                value: type,
                items: const [
                  KindSelectorItem(
                    value: 'expense',
                    label: 'Gasto',
                    icon: CupertinoIcons.arrow_up_right_circle_fill,
                  ),
                  KindSelectorItem(
                    value: 'income',
                    label: 'Ingreso',
                    icon: CupertinoIcons.arrow_down_left_circle_fill,
                  ),
                  KindSelectorItem(
                    value: 'transfer',
                    label: 'Transferir',
                    icon: CupertinoIcons.arrow_right_arrow_left_circle_fill,
                  ),
                ],
                onChanged: (v) {
                  if (v == 'transfer' &&
                      !widget.app.ensureCanCreateMovement(context, v)) {
                    return;
                  }
                  setState(() {
                    type = v;
                    if (type == 'income') {
                      fee.clear();
                      feeMode = 'auto';
                    }
                    if (!widget.lockAccount) {
                      accountId = v == 'transfer'
                          ? firstAccountId()
                          : preferredAccountId();
                    }
                    targetId = firstAccountId(except: accountId);
                    if (type == 'expense' && !categoryTouched) {
                      category = categoryFromDescription(desc.text) ?? 'Otro';
                    }
                    if (type != 'expense' && type != 'income') {
                      debtId = '';
                    } else if (debtId.isNotEmpty) {
                      final selected = widget.app.debtById(debtId);
                      final selectedKind =
                          selected?['kind']?.toString() == 'receivable'
                          ? 'receivable'
                          : 'payable';
                      final wantedKind = type == 'income'
                          ? 'receivable'
                          : 'payable';
                      if (selected == null || selectedKind != wantedKind) {
                        debtId = '';
                      }
                    }
                  });
                },
              ),
            ),
            Expanded(
              child: ListView(
                key: const ValueKey('movement-editor-fields'),
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  RField(
                    theme: t,
                    controller: amount,
                    placeholder: 'Monto',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  RField(
                    theme: t,
                    controller: desc,
                    placeholder: 'Descripción',
                    onChanged: inferCategory,
                  ),
                  if (showDebtSelector)
                    OptionField(
                      theme: t,
                      label: type == 'expense'
                          ? 'Deuda a pagar'
                          : 'Cobro vinculado',
                      value: selectedDebtLabel(selectedDebt),
                      icon: CupertinoIcons.checkmark_seal_fill,
                      onTap: () => pickDebt(context),
                    ),
                  if (type == 'expense')
                    OptionField(
                      theme: t,
                      label: 'Categoría',
                      value: category,
                      icon: categoryIcon(category),
                      onTap: () => pickCategory(
                        context,
                        category,
                        (v) => setState(() {
                          category = v;
                          categoryTouched = true;
                        }),
                      ),
                    ),
                  widget.lockAccount
                      ? LockedAccountField(
                          theme: t,
                          label: type == 'transfer'
                              ? 'Cuenta origen'
                              : 'Cuenta',
                          account: source,
                        )
                      : OptionField(
                          theme: t,
                          label: type == 'transfer'
                              ? 'Cuenta origen'
                              : 'Cuenta',
                          value: accountLabel(source),
                          logoProvider: source?['provider']?.toString(),
                          onTap: () => pickAccount(
                            context,
                            selected: accountId,
                            onSelect: (id) => setState(() {
                              accountId = id;
                              if (targetId == accountId) {
                                targetId = firstAccountId(except: accountId);
                              }
                              if (debtId.isNotEmpty) {
                                applyDebtDefaults(
                                  debtId,
                                  overwriteAmount: true,
                                );
                              }
                            }),
                          ),
                        ),
                  if (type == 'transfer')
                    OptionField(
                      theme: t,
                      label: 'Cuenta destino',
                      value: accountLabel(target),
                      logoProvider: target?['provider']?.toString(),
                      onTap: () => pickAccount(
                        context,
                        selected: targetId,
                        except: accountId,
                        onSelect: (id) => setState(() => targetId = id),
                      ),
                    ),
                  if (exchange)
                    RField(
                      theme: t,
                      controller: rate,
                      placeholder: 'Tasa personalizada',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  if (type == 'expense' &&
                      !isBankCommissionCategory(category) &&
                      isNationalBankAccount(source) &&
                      sourceCurrency == 'VES')
                    OptionField(
                      theme: t,
                      label: 'Forma de pago',
                      value: paymentMethodLabel(paymentMethod),
                      icon: CupertinoIcons.creditcard_fill,
                      onTap: () => pickValue(
                        context,
                        const [
                          'Pago móvil',
                          'Pago móvil C2P',
                          'Transferencia bancaria',
                          'Tarjeta',
                        ],
                        paymentMethodLabel(paymentMethod),
                        (value) => setState(() {
                          paymentMethod = paymentMethodFromLabel(value);
                          if (isFeeExemptPaymentMethod(paymentMethod)) {
                            fee.clear();
                            feeMode = 'auto';
                          }
                        }),
                      ),
                    ),
                  if (canOperationFee)
                    OptionField(
                      theme: t,
                      label: 'Comisión',
                      value: feeModeLabel(effectiveFeeMode),
                      icon: CupertinoIcons.percent,
                      onTap: () => pickValue(
                        context,
                        const ['Automática', 'Manual', 'Sin comisión'],
                        feeModeLabel(effectiveFeeMode),
                        (value) => setState(() {
                          feeMode = feeModeFromLabel(value);
                          if (feeMode != 'manual') fee.clear();
                        }),
                      ),
                    ),
                  if (type == 'expense' &&
                      canOperationFee &&
                      effectiveFeeMode != 'none' &&
                      paymentMethod == 'bank_transfer')
                    OptionField(
                      theme: t,
                      label: 'Transferencia bancaria',
                      value: bankTransferScopeLabel(bankTransferScope),
                      icon: CupertinoIcons.building_2_fill,
                      onTap: () => pickValue(
                        context,
                        const ['Otro banco', 'Mismo banco'],
                        bankTransferScopeLabel(bankTransferScope),
                        (value) => setState(() {
                          bankTransferScope = bankTransferScopeFromLabel(value);
                        }),
                      ),
                    ),
                  if (canTransferFee)
                    DebtDetailRow(
                      theme: t,
                      label: 'Transferencia bancaria',
                      value: bankTransferScopeLabel(
                        bankTransferScopeForAccounts(source, target),
                      ),
                    ),
                  if (canOperationFee && effectiveFeeMode == 'manual')
                    RField(
                      theme: t,
                      controller: fee,
                      placeholder: 'Comisión manual',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  if (autoOperationFee > 0 || autoTransferFee > 0)
                    RCard(
                      theme: t,
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.percent, color: t.accent),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Comisión estimada',
                              style: TextStyle(
                                color: t.ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            app.secureMoney(
                              type == 'transfer'
                                  ? autoTransferFee
                                  : autoOperationFee,
                              sourceCurrency,
                            ),
                            style: TextStyle(
                              color: t.accent,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  OptionField(
                    theme: t,
                    label: 'Fecha',
                    value: date,
                    icon: CupertinoIcons.calendar,
                    onTap: () => pickDateTime(context),
                  ),
                  if (previewAmount > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 12,
                      ),
                      child: Column(
                        children: [
                          DebtDetailRow(
                            theme: t,
                            label: 'Monto',
                            value: app.secureMoney(
                              previewAmount,
                              sourceCurrency,
                            ),
                          ),
                          if (type != 'income' &&
                              (type != 'expense' ||
                                  !isBankCommissionCategory(category)))
                            DebtDetailRow(
                              theme: t,
                              label: 'Comisión aplicada',
                              value: app.secureMoney(
                                previewFee,
                                sourceCurrency,
                              ),
                            ),
                          DebtDetailRow(
                            theme: t,
                            label: type == 'income'
                                ? 'Ingreso neto'
                                : 'Total a debitar',
                            value: app.secureMoney(
                              previewTotal,
                              sourceCurrency,
                            ),
                            valueColor: t.accent,
                          ),
                          if (type == 'transfer')
                            DebtDetailRow(
                              theme: t,
                              label: 'Llega a destino',
                              value: app.secureMoney(
                                targetAmount,
                                targetCurrency,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: PrimaryActionButton(
                key: const ValueKey('movement-editor-save'),
                theme: t,
                label: widget.movement == null
                    ? 'Guardar movimiento'
                    : 'Guardar cambios',
                onPressed: save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void inferCategory(String value) {
    if (type != 'expense' || categoryTouched) return;
    final inferred = categoryFromDescription(value) ?? 'Otro';
    if (inferred != category) {
      setState(() => category = inferred);
    }
  }

  void pickDateTime(BuildContext context) {
    final parsed = parseMovementDate(date);
    final initial = parsed.millisecondsSinceEpoch == 0
        ? DateTime.now()
        : parsed;
    showModernDateTimePicker(
      context,
      theme: widget.app.theme,
      initial: initial,
      onSelected: (value) => setState(() => date = formatDateTime(value)),
    );
  }

  void pickAccount(
    BuildContext context, {
    required String selected,
    required ValueChanged<String> onSelect,
    String except = '',
  }) {
    final accounts = widget.app.usableAccounts().where((a) {
      final id = a['id']?.toString() ?? '';
      if (id == except) return false;
      return true;
    }).toList();
    showModernActionSheet(
      context,
      title: 'Selecciona cuenta',
      actions: accounts
          .map(
            (a) => ModernSheetAction(
              icon: CupertinoIcons.creditcard_fill,
              logoProvider: a['provider']?.toString(),
              selected: a['id']?.toString() == selected,
              title: accountPrimaryName(a),
              subtitle: accountSecondaryName(a),
              onPressed: () => onSelect(a['id']?.toString() ?? ''),
            ),
          )
          .toList(),
    );
  }

  void pickDebt(BuildContext context) {
    final wantedKind = type == 'income' ? 'receivable' : 'payable';
    final debts = widget.app.maps('debts').where((debt) {
      final kind = debt['kind']?.toString() == 'receivable'
          ? 'receivable'
          : 'payable';
      return kind == wantedKind && debtRemainingAmount(debt) > .0001;
    }).toList();
    showModernActionSheet(
      context,
      title: wantedKind == 'receivable'
          ? 'Selecciona cobro'
          : 'Selecciona deuda',
      actions: [
        ModernSheetAction(
          icon: debtId.isEmpty
              ? CupertinoIcons.check_mark_circled_solid
              : CupertinoIcons.circle,
          title: 'Sin vincular',
          selected: debtId.isEmpty,
          onPressed: () => setState(() => debtId = ''),
        ),
        ...debts.map((debt) {
          final id = debt['id']?.toString() ?? '';
          final currency = debt['currency']?.toString() ?? 'USD';
          return ModernSheetAction(
            icon: id == debtId
                ? CupertinoIcons.check_mark_circled_solid
                : CupertinoIcons.circle,
            title: debt['title']?.toString().trim().isNotEmpty == true
                ? debt['title'].toString()
                : (wantedKind == 'receivable' ? 'Por cobrar' : 'Por pagar'),
            subtitle: widget.app.secureMoney(
              debtRemainingAmount(debt),
              currency,
            ),
            selected: id == debtId,
            onPressed: () => setState(() {
              debtId = id;
              applyDebtDefaults(id, overwriteAmount: true);
            }),
          );
        }),
      ],
    );
  }

  double operationFeeForSave(Map<String, dynamic> source) {
    if (!canConfigureBankFee(
      source,
      type: type,
      category: type == 'expense' ? category : '',
      method: type == 'expense' ? paymentMethod : 'bank_transfer',
    )) {
      return 0;
    }
    if (feeMode == 'none') return 0;
    if (feeMode == 'manual') return parseAmount(fee.text);
    return estimatedBankFee(
      method: type == 'income' ? 'bank_transfer' : paymentMethod,
      amount: parseAmount(amount.text),
      type: type,
      category: type == 'expense' ? category : '',
      bankTransferScope: bankTransferScope,
    );
  }

  double estimatedTransferFeeForSave(Map<String, dynamic> source) {
    final target = widget.app.accountById(targetId);
    return bankTransferFee(
      source,
      target,
      moneyRound(parseAmount(amount.text)),
    );
  }

  void save() {
    final app = widget.app;
    final source = app.accountById(accountId);
    if (source == null) {
      showModernNotice(
        context,
        title: 'Sin cuenta',
        message: 'Primero registra o selecciona una cuenta.',
      );
      return;
    }
    if (parseAmount(amount.text) <= 0) {
      showModernNotice(
        context,
        title: 'Monto pendiente',
        message: 'Coloca un monto para guardar el movimiento.',
      );
      return;
    }
    var targetAmount = parseAmount(amount.text);
    var targetCurrency = source['currency']?.toString() ?? 'USD';
    if (type == 'transfer') {
      final target = app.accountById(targetId);
      if (target == null || targetId == accountId) {
        showModernNotice(
          context,
          title: 'Cuenta destino',
          message: 'Elige una cuenta destino distinta.',
        );
        return;
      }
      targetCurrency = target['currency']?.toString() ?? targetCurrency;
      if (targetCurrency != source['currency']) {
        final customRate = parseAmount(rate.text);
        if (customRate <= 0) {
          showModernNotice(
            context,
            title: 'Tasa personalizada',
            message: 'Coloca la tasa de la transferencia.',
          );
          return;
        }
        targetAmount = source['currency'] == 'USD'
            ? moneyConvert(parseAmount(amount.text), customRate)
            : moneyConvert(parseAmount(amount.text), 1, customRate);
      }
    }
    widget.onSave({
      'id': widget.movement?['id'],
      'type': type,
      'paymentMethod': type == 'expense' && !isBankCommissionCategory(category)
          ? paymentMethod
          : '',
      'feeMode': type == 'expense' || type == 'income'
          ? canConfigureBankFee(
                  source,
                  type: type,
                  category: type == 'expense' ? category : '',
                  method: type == 'expense' ? paymentMethod : 'bank_transfer',
                )
                ? feeMode
                : 'none'
          : '',
      'bankTransferScope': type == 'transfer'
          ? bankTransferScopeForAccounts(source, app.accountById(targetId))
          : (type == 'expense' &&
                !isBankCommissionCategory(category) &&
                paymentMethod == 'bank_transfer')
          ? bankTransferScope
          : '',
      'description': desc.text.trim(),
      'category': type == 'expense' ? category : '',
      'amount': parseAmount(amount.text),
      'currency': source['currency'] ?? 'USD',
      'feeAmount': type == 'transfer'
          ? estimatedTransferFeeForSave(source)
          : type == 'expense' || type == 'income'
          ? operationFeeForSave(source)
          : 0.0,
      'feeCurrency': source['currency'] ?? 'USD',
      'accountId': accountId,
      'debtId': type == 'expense' || type == 'income' ? debtId : '',
      'targetAccountId': type == 'transfer' ? targetId : '',
      'targetAmount': targetAmount,
      'targetCurrency': targetCurrency,
      'date': date,
      'rate': parseAmount(rate.text) > 0 ? parseAmount(rate.text) : app.rate,
    });
  }
}

class AccountEditor extends StatefulWidget {
  const AccountEditor({
    super.key,
    required this.app,
    required this.onSave,
    this.account,
  });
  final _RialAppState app;
  final Map<String, dynamic>? account;
  final ValueChanged<Map<String, dynamic>> onSave;

  @override
  State<AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<AccountEditor> {
  late String kind;
  late String provider;
  late String currency;
  final label = TextEditingController();
  final balance = TextEditingController();

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    kind = a?['kind']?.toString() ?? 'national';
    provider = a?['provider']?.toString() ?? '0102';
    currency = a?['currency']?.toString() ?? 'VES';
    if (isWalletProvider(provider)) {
      kind = 'wallet';
      currency = 'USD';
    }
    label.text = a?['label']?.toString() ?? '';
    if (a != null) balance.text = plain(numberValue(a['balance']));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.app.theme;
    final providers = kind == 'wallet' ? wallets : banks;
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg.withOpacity(.85),
        border: null,
        middle: Text(widget.account == null ? 'Nueva cuenta' : 'Editar cuenta'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 34),
          children: [
            KindSelector(
              theme: t,
              value: kind,
              items: const [
                KindSelectorItem(
                  value: 'national',
                  label: 'Banco',
                  icon: CupertinoIcons.building_2_fill,
                ),
                KindSelectorItem(
                  value: 'wallet',
                  label: 'Billetera',
                  icon: CupertinoIcons.globe,
                ),
                KindSelectorItem(
                  value: 'cash',
                  label: 'Efectivo',
                  icon: CupertinoIcons.money_dollar_circle_fill,
                ),
              ],
              onChanged: (v) => setState(() {
                kind = v;
                provider = kind == 'wallet'
                    ? 'OKX'
                    : kind == 'cash'
                    ? 'CASH'
                    : '0102';
                currency = kind == 'wallet'
                    ? 'USD'
                    : kind == 'national'
                    ? 'VES'
                    : currency;
              }),
            ),
            if (kind != 'cash')
              OptionField(
                theme: t,
                label: 'Proveedor',
                value: providerName(provider),
                logoProvider: provider,
                onTap: () => pickProvider(context, providers),
              ),
            RField(
              theme: t,
              controller: label,
              placeholder: 'Etiqueta opcional',
            ),
            RField(
              theme: t,
              controller: balance,
              placeholder: 'Saldo',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            if (kind == 'wallet')
              StaticField(theme: t, label: 'Moneda', value: 'Dólares')
            else
              OptionField(
                theme: t,
                label: 'Moneda',
                value: displayCurrency(currency),
                onTap: () => pickValue(
                  context,
                  const ['Bolívares', 'Dólares'],
                  displayCurrency(currency),
                  (v) => setState(
                    () => currency = v.startsWith('Bol') ? 'VES' : 'USD',
                  ),
                ),
              ),
            PrimaryActionButton(
              theme: t,
              label: widget.account == null
                  ? 'Agregar cuenta'
                  : 'Guardar cambios',
              onPressed: save,
            ),
          ],
        ),
      ),
    );
  }

  void pickProvider(BuildContext context, List<List<String>> providers) {
    showModernActionSheet(
      context,
      title: 'Proveedor',
      actions: providers
          .map(
            (p) => ModernSheetAction(
              icon: kind == 'wallet'
                  ? CupertinoIcons.globe
                  : CupertinoIcons.building_2_fill,
              logoProvider: p.first,
              selected: p.first == provider,
              title: p.last,
              onPressed: () => setState(() {
                provider = p.first;
                if (kind == 'wallet') currency = 'USD';
              }),
            ),
          )
          .toList(),
    );
  }

  void save() {
    final providerCode = kind == 'cash' ? 'CASH' : provider;
    if (kind == 'wallet') currency = 'USD';
    if (widget.app.hasDuplicateAccount(
      providerCode,
      currency,
      ignoreId: widget.account?['id']?.toString() ?? '',
    )) {
      showModernNotice(
        context,
        title: 'Cuenta repetida',
        message:
            'Ya existe una cuenta de ${providerName(providerCode)} en ${displayCurrency(currency)}.',
      );
      return;
    }
    final name = automaticAccountName(providerCode, label.text);
    widget.onSave({
      'id': widget.account?['id'],
      'kind': kind,
      'provider': providerCode,
      'name': name,
      'balance': parseAmount(balance.text),
      'label': label.text.trim(),
      'initialCurrency': currency,
      'currency': currency,
    });
  }
}

Widget elegantEntrance(Widget child, {int index = 0}) {
  return softEntrance(
    child,
    offsetY: index == 0 ? 8 : 4,
    duration: const Duration(milliseconds: 180),
  );
}

Widget softEntrance(
  Widget child, {
  double offsetY = 8,
  Duration duration = const Duration(milliseconds: 180),
}) {
  return Builder(
    builder: (context) {
      // A page route already animates its content as a single layer.
      if (MediaQuery.disableAnimationsOf(context) ||
          ModalRoute.of(context) is FluidPageRoute) {
        return child;
      }
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: duration,
        curve: Curves.easeOutCubic,
        child: RepaintBoundary(child: child),
        builder: (context, value, child) => Transform.translate(
          offset: Offset(0, offsetY * (1 - value)),
          child: child,
        ),
      );
    },
  );
}

class AppScroll extends StatelessWidget {
  const AppScroll({
    super.key,
    required this.title,
    required this.theme,
    required this.children,
    this.subtitle,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final RTheme theme;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverSafeArea(
                bottom: false,
                sliver: SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 28, 18, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.ink,
                                  fontSize: title.length > 14 ? 30 : 34,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0,
                                ),
                              ),
                              if (subtitle?.trim().isNotEmpty == true) ...[
                                const SizedBox(height: 4),
                                Text(
                                  subtitle!.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: theme.muted,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (trailing != null) ...[
                          const SizedBox(width: 10),
                          trailing!,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                sliver: SliverList(delegate: SliverChildListDelegate(children)),
              ),
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: MediaQuery.of(context).padding.top + 10,
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              color: theme.bg,
            ),
          ),
        ),
      ],
    );
  }
}

class RCard extends StatelessWidget {
  const RCard({
    super.key,
    required this.theme,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final RTheme theme;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding,
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.border),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(theme.dark ? .10 : .035),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class RField extends StatelessWidget {
  const RField({
    super.key,
    required this.theme,
    required this.controller,
    required this.placeholder,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.obscureText = false,
  });
  final RTheme theme;
  final TextEditingController controller;
  final String placeholder;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CupertinoTextField(
        controller: controller,
        placeholder: placeholder,
        keyboardType: keyboardType,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        inputFormatters: inputFormatters,
        obscureText: obscureText,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        style: TextStyle(
          color: theme.ink,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        placeholderStyle: TextStyle(
          color: theme.muted,
          fontSize: 17,
          fontWeight: FontWeight.w500,
        ),
        decoration: BoxDecoration(
          color: theme.field,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.border),
        ),
      ),
    );
  }
}

class OptionField extends StatelessWidget {
  const OptionField({
    super.key,
    required this.theme,
    required this.label,
    required this.value,
    required this.onTap,
    this.logoProvider,
    this.icon,
  });
  final RTheme theme;
  final String label;
  final String value;
  final VoidCallback onTap;
  final String? logoProvider;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: theme.field,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.border),
          ),
          child: Row(
            children: [
              if (logoProvider != null) ...[
                LogoBadge(provider: logoProvider!, theme: theme, size: 38),
                const SizedBox(width: 12),
              ] else if (icon != null) ...[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: theme.accent.withOpacity(.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: theme.accent, size: 20),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: theme.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value.isEmpty ? 'Seleccionar' : value,
                      style: TextStyle(
                        color: theme.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(CupertinoIcons.chevron_down, color: theme.muted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class LockedAccountField extends StatelessWidget {
  const LockedAccountField({
    super.key,
    required this.theme,
    required this.label,
    required this.account,
  });

  final RTheme theme;
  final String label;
  final Map<String, dynamic>? account;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: theme.field,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.accent.withOpacity(.32)),
        ),
        child: Row(
          children: [
            if (account != null) ...[
              LogoBadge(
                provider: account!['provider']?.toString() ?? '',
                theme: theme,
                size: 38,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: theme.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    accountLabel(account),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Icon(CupertinoIcons.lock_fill, color: theme.accent, size: 16),
          ],
        ),
      ),
    );
  }
}

class StaticField extends StatelessWidget {
  const StaticField({
    super.key,
    required this.theme,
    required this.label,
    required this.value,
  });
  final RTheme theme;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: theme.field,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: theme.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: theme.ink,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MenuTile extends StatelessWidget {
  const MenuTile({
    super.key,
    required this.theme,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final RTheme theme;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: RCard(
        theme: theme,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.accent.withOpacity(.15),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(icon, color: theme.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: theme.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: theme.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right, color: theme.muted),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.theme,
    required this.title,
    this.action,
    this.onAction,
  });
  final RTheme theme;
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 0, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: theme.muted,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: .6,
              ),
            ),
          ),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                action!,
                style: TextStyle(
                  color: theme.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    super.key,
    required this.theme,
    required this.onPressed,
    required this.label,
  });

  final RTheme theme;
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 58,
        alignment: Alignment.center,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: theme.accent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.accent.withOpacity(.20)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: CupertinoColors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class SecondaryActionButton extends StatelessWidget {
  const SecondaryActionButton({
    super.key,
    required this.theme,
    required this.label,
    required this.onPressed,
  });

  final RTheme theme;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.field,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: theme.ink,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class ThemeColorSelector extends StatelessWidget {
  const ThemeColorSelector({
    super.key,
    required this.theme,
    required this.value,
    required this.onChanged,
  });

  final RTheme theme;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: themeColorOptions.map((option) {
        final selected = option.key == value;
        final color = option.colorFor(theme.dark);
        return GestureDetector(
          onTap: () => onChanged(option.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: selected ? color.withOpacity(.14) : theme.field,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? color.withOpacity(.70) : theme.border,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: theme.card, width: 2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  option.label,
                  style: TextStyle(
                    color: selected ? theme.ink : theme.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.theme,
    required this.value,
    required this.onChanged,
  });

  final RTheme theme;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubic,
        width: 66,
        height: 38,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: value ? theme.accent.withOpacity(.95) : theme.field,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: value ? theme.accent.withOpacity(.35) : theme.border,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: theme.dark
                  ? const Color(0xFFF8FAFC)
                  : CupertinoColors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: CupertinoColors.black.withOpacity(.16),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class KindSelector extends StatelessWidget {
  const KindSelector({
    super.key,
    required this.theme,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final RTheme theme;
  final String value;
  final List<KindSelectorItem> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: theme.field,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.border),
      ),
      child: Row(
        children: items.map((item) {
          final selected = item.value == value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(item.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOutCubic,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? theme.accent.withOpacity(.14)
                      : CupertinoColors.transparent,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                    color: selected
                        ? theme.accent.withOpacity(.42)
                        : CupertinoColors.transparent,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: theme.accent.withOpacity(.10),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      item.icon,
                      size: 17,
                      color: selected ? theme.accent : theme.muted,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? theme.ink : theme.muted,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class KindSelectorItem {
  const KindSelectorItem({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.theme, required this.text});
  final RTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return RCard(
      theme: theme,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.muted,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class LogoBadge extends StatelessWidget {
  const LogoBadge({
    super.key,
    required this.provider,
    required this.theme,
    this.size = 44,
  });
  final String provider;
  final RTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = logoAsset(provider);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFA),
        borderRadius: BorderRadius.circular(size * .30),
        border: Border.all(
          color: theme.dark ? const Color(0xFF2C3340) : const Color(0xFFE6E1D7),
        ),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(theme.dark ? .18 : .06),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: EdgeInsets.all(size * .13),
      child: asset == null
          ? Center(
              child: Text(
                logoText(provider),
                style: TextStyle(
                  color: const Color(0xFF151515),
                  fontSize: size * .24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            )
          : Image.asset(asset, fit: BoxFit.contain),
    );
  }
}

const _accountColorPalette = [
  Color(0xFF58BE86),
  Color(0xFF5CC3DE),
  Color(0xFFE86A7B),
  Color(0xFFE0AE55),
  Color(0xFFA98BDF),
  Color(0xFF55BDBD),
  Color(0xFFF28A68),
  Color(0xFFA7C957),
];

Color? _savedAccountColor(Map<String, dynamic> account) {
  final value = account['chartColor'];
  return value is int && value >= 0xFF000000 && value <= 0xFFFFFFFF
      ? Color(value)
      : null;
}

void assignAccountColors(Iterable<Map<String, dynamic>> accounts) {
  final used = <int>{};
  final pending = <Map<String, dynamic>>[];
  // Reserve existing colors first so adding or removing accounts does not recolor others.
  for (final account in accounts) {
    final saved = _savedAccountColor(account);
    if (saved == null || !used.add(saved.toARGB32())) {
      pending.add(account);
    }
  }
  var extra = 0;
  for (final account in pending) {
    Color? chosen;
    for (final candidate in [accountColor(account), ..._accountColorPalette]) {
      if (used.add(candidate.toARGB32())) {
        chosen = candidate;
        break;
      }
    }
    // Extend the chart palette instead of repeating colors after the eighth account.
    while (chosen == null) {
      final candidate = HSLColor.fromAHSL(
        1,
        (extra++ * 137.508) % 360,
        .65,
        .62,
      ).toColor();
      if (used.add(candidate.toARGB32())) chosen = candidate;
    }
    account['chartColor'] = chosen.toARGB32();
  }
}

Color accountColor(Map<String, dynamic> account) {
  final saved = _savedAccountColor(account);
  if (saved != null) return saved;
  final seed =
      '${account['id'] ?? ''}${account['provider'] ?? ''}${account['currency'] ?? ''}';
  final hash = seed.codeUnits.fold<int>(
    0,
    (value, unit) => ((value * 31) + unit) & 0x7FFFFFFF,
  );
  return _accountColorPalette[hash % _accountColorPalette.length];
}

class RatioPart {
  RatioPart({required this.color, required this.value});
  final Color color;
  final double value;
}

class RatioBar extends StatelessWidget {
  const RatioBar({
    super.key,
    required this.theme,
    required this.parts,
    this.separateParts = false,
  });
  final RTheme theme;
  final List<RatioPart> parts;
  final bool separateParts;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold<double>(0, (sum, p) => sum + math.max(0, p.value));
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 12,
        color: theme.field,
        child: total <= 0
            ? const SizedBox.expand()
            : separateParts
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final positive = parts
                      .where((part) => part.value > 0)
                      .toList();
                  final gap = math.min(
                    2.0,
                    constraints.maxWidth / (positive.length * 2),
                  );
                  final available = math.max(
                    0.0,
                    constraints.maxWidth - gap * (positive.length - 1),
                  );
                  final minimum = math.min(3.0, available / positive.length);
                  final widths = <int, double>{};
                  var remainingWidth = available;
                  var remainingValue = total;
                  // Keep tiny positive balances visible; distribute the rest proportionally.
                  final byValue =
                      List<int>.generate(positive.length, (index) => index)
                        ..sort(
                          (a, b) =>
                              positive[a].value.compareTo(positive[b].value),
                        );
                  for (final index in byValue) {
                    if (remainingWidth *
                            positive[index].value /
                            remainingValue >=
                        minimum) {
                      break;
                    }
                    widths[index] = minimum;
                    remainingWidth -= minimum;
                    remainingValue -= positive[index].value;
                  }
                  return Row(
                    children: [
                      for (var index = 0; index < positive.length; index++) ...[
                        if (index > 0) SizedBox(width: gap),
                        SizedBox(
                          width:
                              widths[index] ??
                              remainingWidth *
                                  positive[index].value /
                                  remainingValue,
                          height: 12,
                          child: ColoredBox(
                            key: ValueKey('ratio-segment-$index'),
                            color: positive[index].color,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              )
            : Row(
                children: parts
                    .where((p) => p.value > 0)
                    .map(
                      (p) => Expanded(
                        flex: math.max(1, (p.value / total * 1000).round()),
                        child: Container(color: p.color),
                      ),
                    )
                    .toList(),
              ),
      ),
    );
  }
}

void pickValue(
  BuildContext context,
  List<String> values,
  String selected,
  ValueChanged<String> onSelect,
) {
  showModernActionSheet(
    context,
    title: 'Seleccionar',
    actions: values
        .map(
          (v) => ModernSheetAction(
            icon: v == selected
                ? CupertinoIcons.check_mark_circled_solid
                : CupertinoIcons.circle,
            title: v,
            selected: v == selected,
            onPressed: () => onSelect(v),
          ),
        )
        .toList(),
  );
}

void pickCategory(
  BuildContext context,
  String selected,
  ValueChanged<String> onSelect,
) {
  showModernActionSheet(
    context,
    title: 'Categoría',
    actions: budgetCategories
        .map(
          (category) => ModernSheetAction(
            icon: categoryIcon(category),
            title: category,
            selected: category == selected,
            onPressed: () => onSelect(category),
          ),
        )
        .toList(),
  );
}

List<Map<String, dynamic>> sortedMovements(
  List<Map<String, dynamic>> movements,
) {
  final dated = [
    for (var i = 0; i < movements.length; i++)
      (
        movement: movements[i],
        date: parseMovementDate(movements[i]['date']?.toString()),
        index: i,
      ),
  ];
  dated.sort((a, b) {
    final order = b.date.compareTo(a.date);
    return order == 0 ? a.index.compareTo(b.index) : order;
  });
  return dated.map((item) => item.movement).toList();
}

double movementListAmount(Map<String, dynamic> movement) {
  final amount = numberValue(movement['amount']);
  final fee = numberValue(movement['feeAmount']);
  final type = movement['type']?.toString() ?? 'expense';
  if (type == 'income') return math.max(0.0, amount - fee);
  if (isExpenseType(type)) return amount + fee;
  return amount;
}

String movementTitle(Map<String, dynamic> movement) {
  final desc = movement['description']?.toString().trim() ?? '';
  if (desc.isNotEmpty) return desc;
  final type = movement['type']?.toString() ?? 'expense';
  if (type == 'income') return 'Ingreso';
  if (type == 'transfer') return 'Transferencia';
  if (type == 'debt-payment') return 'Pago de cuota';
  return movement['category']?.toString().isNotEmpty == true
      ? movement['category'].toString()
      : 'Gasto';
}

bool isExpenseType(String? type) => type == 'expense' || type == 'debt-payment';

String accountLabel(Map<String, dynamic>? account) {
  if (account == null) return 'Seleccionar cuenta';
  return '${accountPrimaryName(account)} - ${displayCurrency(account['currency']?.toString() ?? 'USD')}';
}

String accountPrimaryName(Map<String, dynamic> account) {
  final label = account['label']?.toString().trim() ?? '';
  if (label.isNotEmpty) return label;
  return account['name']?.toString().trim().isNotEmpty == true
      ? account['name'].toString()
      : shortProviderName(account['provider']?.toString() ?? '');
}

String accountSecondaryName(Map<String, dynamic> account) {
  final provider = providerName(account['provider']?.toString() ?? '');
  final currency = displayCurrency(account['currency']?.toString() ?? 'USD');
  final label = account['label']?.toString().trim() ?? '';
  return label.isEmpty ? currency : '$provider · $currency';
}

String automaticAccountName(String provider, String label) {
  final clean = label.trim();
  final base = provider == 'CASH' ? 'Efectivo' : shortProviderName(provider);
  return clean.isEmpty ? base : clean;
}

String displayCurrency(String currency) {
  if (currency == 'VES') return 'Bolívares';
  if (currency == 'EUR') return 'Euros';
  if (currency == 'USDT') return 'USDT';
  return 'Dólares';
}

String currencyBadge(String currency) {
  if (currency == 'VES') return 'Bs';
  if (currency == 'EUR') return 'EUR';
  if (currency == 'USDT') return 'USDT';
  return r'$';
}

List<String> currencyPickerLabels({required String except}) {
  const codes = ['USD', 'VES', 'EUR', 'USDT'];
  return codes
      .where(
        (code) => code != except && isCalculatorPairSupported(code, except),
      )
      .map(displayCurrency)
      .toList(growable: false);
}

String firstDifferentCurrency(String currency) {
  const codes = ['USD', 'VES', 'EUR', 'USDT'];
  return codes.firstWhere(
    (code) => code != currency && isCalculatorPairSupported(code, currency),
    orElse: () => 'USD',
  );
}

bool isCalculatorPairSupported(String from, String to) {
  if (from == to) return true;
  if (from == 'USDT') return to == 'VES';
  if (to == 'USDT') return from == 'VES';
  return true;
}

String currencyCodeFromLabel(String label) {
  if (label.startsWith('Bol')) return 'VES';
  if (label.startsWith('Euro')) return 'EUR';
  if (label == 'USDT') return 'USDT';
  return 'USD';
}

String providerName(String code) {
  if (code == 'CASH') return 'Efectivo';
  for (final b in banks) {
    if (b.first == code) return b.last;
  }
  for (final w in wallets) {
    if (w.first == code) return w.last;
  }
  return code;
}

String shortProviderName(String code) {
  const names = {
    '0102': 'Venezuela',
    '0105': 'Mercantil',
    '0108': 'Provincial',
    '0134': 'Banesco',
    '0172': 'Bancamiga',
    '0191': 'BNC',
  };
  return names[code] ?? providerName(code);
}

String? logoAsset(String code) {
  const assets = {
    '0102': 'logo_bdv',
    '0104': 'logo_venezolanocredito',
    '0105': 'logo_mercantil',
    '0108': 'logo_provincial',
    '0114': 'logo_bancaribe',
    '0115': 'logo_exterior',
    '0128': 'logo_caroni',
    '0134': 'logo_banesco',
    '0137': 'logo_sofitasa',
    '0138': 'logo_plaza',
    '0146': 'logo_bangente',
    '0151': 'logo_bfc',
    '0156': 'logo_100banco',
    '0163': 'logo_tesoro',
    '0166': 'logo_agricola',
    '0168': 'logo_bancrecer',
    '0169': 'logo_r4',
    '0171': 'logo_activo',
    '0172': 'logo_bancamiga',
    '0174': 'logo_banplus',
    '0175': 'logo_bicentenario',
    '0177': 'logo_banfanb',
    '0191': 'logo_bnc',
    'BINANCE': 'logo_binance',
    'OKX': 'logo_okx',
    'PAYPAL': 'logo_paypal',
    'ZINLI': 'logo_zinli',
    'WALLY': 'logo_wally',
    'KONTIGO': 'logo_kontigo',
    'CASHEA': 'logo_cashea',
    'KRECE': 'logo_krece',
    'WEPPA': 'logo_weppa',
  };
  final name = assets[code];
  return name == null ? null : 'assets/logos/$name.png';
}

String? debtPartyLogoCode(String party) {
  switch (normalizeText(party)) {
    case 'cashea':
      return 'CASHEA';
    case 'krece':
      return 'KRECE';
    case 'weppa':
      return 'WEPPA';
    default:
      return null;
  }
}

IconData debtPartyIcon(String party, String kind) {
  final normalized = normalizeText(party);
  if (normalized == 'alguien') return CupertinoIcons.person_2_fill;
  if (normalized == 'trabajo') return CupertinoIcons.briefcase_fill;
  if (kind == 'receivable') return CupertinoIcons.arrow_down_left_circle_fill;
  return CupertinoIcons.arrow_up_right_circle_fill;
}

String logoText(String code) {
  if (code == 'CASH') return r'$';
  if (code == 'CASHEA') return 'C';
  if (code == 'KRECE') return 'K';
  if (code == 'WEPPA') return 'W';
  if (code == 'OKX') return 'OKX';
  if (code.length >= 2)
    return shortProviderName(code)
        .substring(0, math.min(2, shortProviderName(code).length))
        .toUpperCase();
  return 'SR';
}

String normalizeText(String value) {
  return value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');
}

Map<String, dynamic> savingsFunds(Map<String, dynamic> state) {
  final raw = state['savingsFunds'];
  final funds = raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
  funds.putIfAbsent(
    'emergency',
    () => {
      'type': 'emergency',
      'saved': 0.0,
      'target': 0.0,
      'history': <dynamic>[],
    },
  );
  funds.putIfAbsent(
    'general',
    () => {
      'type': 'general',
      'saved': 0.0,
      'target': 0.0,
      'history': <dynamic>[],
    },
  );
  state['savingsFunds'] = funds;
  return funds;
}

Map<String, dynamic>? savingsTargetMap(
  _RialAppState app,
  String targetType,
  String targetId,
) {
  if (targetType == 'fund') {
    final target = savingsFunds(app.state)[targetId];
    return target is Map ? target.cast<String, dynamic>() : null;
  }
  for (final item in app.rawList('goals')) {
    if (item is Map && item['id']?.toString() == targetId) {
      return item.cast<String, dynamic>();
    }
  }
  return null;
}

double budgetSavings(Map<String, dynamic> state) {
  final salary = numberValue(state['budgetSalary']);
  final value = numberValue(state['budgetSavingsValue']);
  return state['budgetSavingsMode'] == 'percent' ? salary * value / 100 : value;
}

double spentForCategory(
  List<Map<String, dynamic>> movements,
  String category,
  String currency,
  double rate, {
  String? month,
  String? period,
  String periodType = 'monthly',
}) {
  var total = 0.0;
  final targetMonth = month ?? currentMonthKey();
  for (final m in movements) {
    if (m['type'] != 'expense' && m['type'] != 'debt-payment') continue;
    if ((m['category']?.toString() ?? '') != category) continue;
    if (period != null) {
      if (!movementInBudgetPeriod(m, period, periodType)) continue;
    } else if (monthKeyFromDate(m['date']?.toString()) != targetMonth) {
      continue;
    }
    total += convert(
      numberValue(m['amount']) + numberValue(m['feeAmount']),
      m['currency']?.toString() ?? currency,
      currency,
      rate,
    );
  }
  return total;
}

double convert(double amount, String from, String to, double rate) {
  if (from == to) return amount;
  if (from == 'USD' && to == 'VES') return moneyConvert(amount, rate);
  if (from == 'VES' && to == 'USD') return moneyConvert(amount, 1, rate);
  return amount;
}

double? convertCurrencyAmount(
  double amount,
  String from,
  String to, {
  required double usdVes,
  required double eurVes,
  double usdtVes = 0,
}) {
  if (!isCalculatorPairSupported(from, to)) return null;
  if (from == to) return amount;
  final rates = {'VES': 1.0, 'USD': usdVes, 'EUR': eurVes, 'USDT': usdtVes};
  final fromRate = rates[from];
  final toRate = rates[to];
  if (fromRate == null ||
      toRate == null ||
      !fromRate.isFinite ||
      !toRate.isFinite ||
      fromRate <= 0 ||
      toRate <= 0)
    return null;
  return amount * fromRate / toRate;
}

double numberValue(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  if (value is String) return parseAmount(value);
  return fallback;
}

double parseAmount(String value) {
  var raw = value.trim().replaceAll(' ', '');
  if (raw.isEmpty) return 0;
  if (raw.contains(',') && raw.contains('.')) {
    raw = raw.replaceAll('.', '').replaceAll(',', '.');
  } else if (raw.contains(',')) {
    raw = raw.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^-?\d{1,3}(\.\d{3}){2,}$').hasMatch(raw)) {
    raw = raw.replaceAll('.', '');
  }
  final parsed = double.tryParse(raw);
  return parsed != null && parsed.isFinite ? parsed : 0;
}

String firstText(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key]?.toString().trim() ?? '';
    if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
  }
  return '';
}

({String version, int build}) parseReleaseVersion(String tag) {
  var raw = tag.trim();
  if (raw.startsWith('v') || raw.startsWith('V')) {
    raw = raw.substring(1);
  }
  final plusIndex = raw.indexOf('+');
  if (plusIndex > 0) {
    return (
      version: raw.substring(0, plusIndex),
      build: int.tryParse(raw.substring(plusIndex + 1)) ?? 0,
    );
  }
  final match = RegExp(r'(\d+(?:\.\d+){1,3})').firstMatch(raw);
  return (version: match?.group(1) ?? raw, build: 0);
}

int compareVersionNames(String left, String right) {
  final a = versionParts(left);
  final b = versionParts(right);
  final length = math.max(a.length, b.length);
  for (var i = 0; i < length; i++) {
    final leftPart = i < a.length ? a[i] : 0;
    final rightPart = i < b.length ? b[i] : 0;
    if (leftPart != rightPart) return leftPart.compareTo(rightPart);
  }
  return 0;
}

List<int> versionParts(String value) {
  final match = RegExp(r'\d+(?:\.\d+)*').firstMatch(value.trim());
  final raw = match?.group(0) ?? '';
  if (raw.isEmpty) return const [0];
  return raw.split('.').map((part) => int.tryParse(part) ?? 0).toList();
}

String plain(double value) {
  final text = value.toStringAsFixed(2);
  return text.endsWith('.00') ? text.substring(0, text.length - 3) : text;
}

bool stateHasSecurity(Map<String, dynamic> state) {
  final hasPin =
      state['pinEnabled'] == true &&
      (state['pinHash']?.toString().isNotEmpty ?? false) &&
      (state['pinSalt']?.toString().isNotEmpty ?? false);
  return state['onboardingComplete'] == true &&
      state['securitySetupComplete'] == true &&
      (hasPin || state['biometricEnabled'] == true);
}

String pinHashFor(String pin, String salt) {
  return sha256.convert(utf8.encode('$salt:$pin')).toString();
}

String hiddenMoney(String currency, {String sign = ''}) {
  if (currency == 'VES') return '${sign}Bs. ••••';
  if (currency == 'EUR') return '${sign}€••••';
  if (currency == 'USDT') return '${sign}₮••••';
  return '${sign}\$••••';
}

bool validatePin(BuildContext context, String pin, String confirmation) {
  if (pin.length < 4 || pin.length > 6) {
    showModernNotice(
      context,
      title: 'PIN inválido',
      message: 'Usa un PIN de 4 a 6 dígitos.',
    );
    return false;
  }
  if (pin != confirmation) {
    showModernNotice(
      context,
      title: 'Los PIN no coinciden',
      message: 'Escribe el mismo PIN en ambos campos.',
    );
    return false;
  }
  return true;
}

String money(double value, String currency) {
  final sign = value < 0 ? '-' : '';
  final body = formatNumber(value.abs());
  if (currency == 'VES') return '${sign}Bs. $body';
  if (currency == 'EUR') return '$sign€$body';
  if (currency == 'USDT') return '$sign₮$body';
  return '$sign\$$body';
}

String decimal(double value) {
  return formatNumberTruncated(value, decimals: 2);
}

String formatNumberTruncated(double value, {int decimals = 2}) {
  final factor = math.pow(10, decimals).toDouble();
  final truncated = value >= 0
      ? (value * factor).floor() / factor
      : (value * factor).ceil() / factor;
  return truncated.toStringAsFixed(decimals).replaceAll('.', ',');
}

String formatNumber(double value) {
  final fixed = value.toStringAsFixed(2);
  final pieces = fixed.split('.');
  final chars = pieces.first.split('').reversed.toList();
  final grouped = <String>[];
  for (var i = 0; i < chars.length; i++) {
    if (i > 0 && i % 3 == 0) grouped.add('.');
    grouped.add(chars[i]);
  }
  return '${grouped.reversed.join()},${pieces.last}';
}

String currentMonthKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
}

const List<List<String>> homeSectionOptions = [
  ['metrics', 'Ingresos y gastos'],
  ['accounts', 'Mis balances'],
  ['upcoming', 'Próximos pagos'],
  ['recent', 'Movimientos recientes'],
];

const List<List<String>> homeQuickActionOptions = [
  ['movement', 'Nuevo movimiento'],
  ['transfer', 'Nueva transferencia'],
  ['account', 'Nueva cuenta'],
];

const List<List<String>> homeShortcutOptions = [
  ['calculator', 'Calculadora'],
  ['movement', 'Movimientos'],
  ['accounts', 'Mis balances'],
  ['debts', 'Por cobrar / pagar'],
  ['settings', 'Ajustes'],
];

String optionLabel(List<List<String>> options, String key) {
  for (final option in options) {
    if (option.first == key) return option.last;
  }
  return key;
}

List<String> sanitizeHomeSections(Object? value) {
  final allowed = homeSectionOptions.map((item) => item.first).toList();
  final raw = value is List ? value.map((e) => e.toString()) : allowed;
  final result = <String>[];
  for (final key in raw) {
    if (allowed.contains(key) && !result.contains(key)) result.add(key);
  }
  return result;
}

List<String> sanitizeHomeQuickActions(Object? value) {
  final allowed = homeQuickActionOptions.map((item) => item.first).toList();
  final raw = value is List ? value.map((e) => e.toString()) : allowed;
  final result = <String>[];
  for (final key in raw) {
    if (allowed.contains(key) && !result.contains(key)) result.add(key);
  }
  return result.isEmpty ? ['movement', 'transfer', 'account'] : result;
}

List<String> sanitizeHomeShortcutButtons(Object? value) {
  final allowed = homeShortcutOptions.map((item) => item.first).toList();
  final raw = value is List ? value.map((e) => e.toString()) : allowed;
  final result = <String>[];
  for (final key in raw) {
    if (allowed.contains(key) && !result.contains(key)) result.add(key);
  }
  return result;
}

IconData quickActionIcon(String key) {
  switch (key) {
    case 'transfer':
      return CupertinoIcons.arrow_right_arrow_left_circle_fill;
    case 'account':
      return CupertinoIcons.creditcard_fill;
    case 'calculator':
      return material.Icons.calculate_rounded;
    case 'movement':
      return CupertinoIcons.arrow_up_arrow_down;
    case 'accounts':
      return CupertinoIcons.creditcard_fill;
    case 'settings':
      return CupertinoIcons.gear_alt_fill;
    case 'savings':
      return CupertinoIcons.flag_fill;
    case 'debts':
      return CupertinoIcons.person_2_fill;
    case 'metrics':
      return CupertinoIcons.chart_bar_alt_fill;
    case 'upcoming':
      return CupertinoIcons.calendar;
    case 'recent':
      return CupertinoIcons.clock_fill;
    default:
      return CupertinoIcons.arrow_up_right_circle_fill;
  }
}

String quickActionSubtitle(String key) {
  switch (key) {
    case 'transfer':
      return 'Mueve dinero entre cuentas';
    case 'account':
      return 'Banco, billetera o efectivo';
    case 'calculator':
      return 'Convierte con tasas actualizadas';
    case 'movement':
      return 'Historial de ingresos y gastos';
    case 'accounts':
      return 'Bancos, billeteras y efectivo';
    case 'settings':
      return 'Tema, seguridad y preferencias';
    case 'savings':
      return 'Crea un objetivo de ahorro';
    case 'debts':
      return 'Registra cobros y pagos';
    default:
      return 'Registra gasto o ingreso';
  }
}

String homeBalanceModeLabel(String value) {
  return value == 'vesOnly' ? 'Solo bolívares al cambio' : 'Todo el balance';
}

String homeBalanceModeFromLabel(String label) {
  return label.startsWith('Solo') ? 'vesOnly' : 'total';
}

String homeBalancePeriodLabel(String value) {
  switch (value) {
    case 'week':
      return 'Semana';
    case 'month':
      return 'Mes';
    default:
      return 'Día';
  }
}

String homeBalancePeriodFromLabel(String label) {
  if (label == 'Semana') return 'week';
  if (label == 'Mes') return 'month';
  return 'day';
}

double balanceChangePercent(
  List<Map<String, dynamic>> movements,
  double currentBalance,
  _RialAppState app, {
  required String currency,
  required String period,
  required String balanceMode,
}) {
  final now = DateTime.now();
  final cutoff = switch (period) {
    'week' => now.subtract(const Duration(days: 7)),
    'month' => DateTime(now.year, now.month),
    _ => DateTime(now.year, now.month, now.day),
  };
  var net = 0.0;
  for (final movement in movements) {
    final date = parseMovementDate(movement['date']?.toString());
    if (date.millisecondsSinceEpoch == 0 || date.isBefore(cutoff)) continue;
    final type = movement['type']?.toString() ?? 'expense';
    if (balanceMode == 'vesOnly' &&
        !movementTouchesCurrency(app, movement, 'VES')) {
      continue;
    }
    final movementCurrency = movement['currency']?.toString() ?? 'USD';
    final amount = app.convertForHome(
      numberValue(movement['amount']),
      movementCurrency,
      currency,
    );
    final fee = app.convertForHome(
      numberValue(movement['feeAmount']),
      movement['feeCurrency']?.toString().isNotEmpty == true
          ? movement['feeCurrency'].toString()
          : movementCurrency,
      currency,
    );
    if (type == 'income') {
      net += amount - fee;
    } else if (isExpenseType(type)) {
      net -= amount + fee;
    } else if (type == 'transfer' && fee > 0) {
      net -= fee;
    }
  }
  final start = currentBalance - net;
  if (start.abs() < .01) return 0;
  return (net / start) * 100;
}

bool movementTouchesCurrency(
  _RialAppState app,
  Map<String, dynamic> movement,
  String currency,
) {
  final source = app.accountById(movement['accountId']?.toString() ?? '');
  final target = app.accountById(movement['targetAccountId']?.toString() ?? '');
  return movement['currency'] == currency ||
      movement['targetCurrency'] == currency ||
      source?['currency'] == currency ||
      target?['currency'] == currency;
}

double debtRemainingAmount(Map<String, dynamic> debt) {
  return math.max(
    0.0,
    moneySubtract(numberValue(debt['amount']), numberValue(debt['paidAmount'])),
  );
}

double debtNextPaymentAmount(Map<String, dynamic> debt) {
  final remaining = debtRemainingAmount(debt);
  if (!debtHasInstallments(debt) || remaining == 0) return remaining;
  final schedule = debtInstallmentAmounts(debt);
  final index = debtNextInstallmentIndex(debt);
  final boundary = schedule
      .take(index + 1)
      .fold<int>(0, (sum, v) => sum + moneyCents(v));
  final paid = math.max(
    0,
    moneyCents(numberValue(debt['paidAmount'])) -
        moneyCents(debtInitialAmount(debt)),
  );
  return math.min(remaining, math.max(0, boundary - paid) / 100);
}

bool debtHasInstallments(Map<String, dynamic> debt) {
  final installments = numberValue(debt['installments']).round();
  return debt['hasInstallments'] == true ||
      installments > 1 ||
      numberValue(debt['installmentAmount']) > 0 ||
      (debt['paymentFrequency']?.toString().trim().isNotEmpty ?? false);
}

int debtInstallmentCount(Map<String, dynamic> debt) {
  return numberValue(debt['installments']).round().clamp(1, 999).toInt();
}

List<String> debtInstallmentDates(Map<String, dynamic> debt) {
  final raw = debt['installmentDates'];
  if (raw is! List) return const [];
  return raw
      .map((value) => displayDateOnly(value?.toString()))
      .where((value) => value.isNotEmpty)
      .toList();
}

int debtNextInstallmentIndex(Map<String, dynamic> debt) {
  if (!debtHasInstallments(debt)) return 0;
  final schedule = debtInstallmentAmounts(debt);
  final paid = math.max(
    0,
    moneyCents(numberValue(debt['paidAmount'])) -
        moneyCents(debtInitialAmount(debt)),
  );
  var boundary = 0;
  for (var i = 0; i < schedule.length; i++) {
    boundary += moneyCents(schedule[i]);
    if (paid < boundary) return i;
  }
  return schedule.length - 1;
}

String debtUpcomingDate(Map<String, dynamic> debt) {
  if (debtRemainingAmount(debt) <= .0001) return '';
  if (debt['hasDueDate'] == false) return '';
  if (debtHasInstallments(debt)) {
    final index = debtNextInstallmentIndex(debt);
    final dates = debtInstallmentDates(debt);
    if (index < dates.length) return dates[index];
    final base = parseDateOnly(debt['dueDate']?.toString());
    if (base.year != 9999) {
      return formatDate(
        addDebtFrequency(
          base,
          debt['paymentFrequency']?.toString() ?? 'Mensual',
          index,
        ),
      );
    }
  }
  return displayDateOnly(debt['dueDate']?.toString());
}

DateTime addDebtFrequency(DateTime base, String frequency, int index) {
  if (index <= 0) return DateTime(base.year, base.month, base.day);
  switch (frequency) {
    case 'Semanal':
      return base.add(Duration(days: 7 * index));
    case 'Quincenal':
      return base.add(Duration(days: 15 * index));
    case 'Mensual':
      return addCalendarMonths(base, index);
    default:
      return addCalendarMonths(base, index);
  }
}

DateTime addCalendarMonths(DateTime base, int months) {
  final target = DateTime(base.year, base.month + months);
  final lastDay = DateTime(target.year, target.month + 1, 0).day;
  return DateTime(target.year, target.month, math.min(base.day, lastDay));
}

String selectedDebtLabel(Map<String, dynamic>? debt) {
  if (debt == null) return 'Sin vincular';
  final title = debt['title']?.toString().trim() ?? '';
  if (title.isNotEmpty) return title;
  return debt['kind']?.toString() == 'receivable' ? 'Por cobrar' : 'Por pagar';
}

List<Map<String, dynamic>> upcomingDebtItems(List<Map<String, dynamic>> debts) {
  final list = debts
      .map((debt) {
        final amount = numberValue(debt['amount']);
        final paid = numberValue(debt['paidAmount']);
        final dueDate = debtUpcomingDate(debt);
        if (amount <= 0 || paid >= amount) return null;
        return Map<String, dynamic>.from(debt)..['nextDueDate'] = dueDate;
      })
      .whereType<Map<String, dynamic>>()
      .toList();
  list.sort((a, b) {
    final left = parseIsoDate(a['nextDueDate']?.toString());
    final right = parseIsoDate(b['nextDueDate']?.toString());
    final leftHasDate = left.year != 9999;
    final rightHasDate = right.year != 9999;
    if (leftHasDate != rightHasDate) return leftHasDate ? -1 : 1;
    return left.compareTo(right);
  });
  return list;
}

DateTime parseIsoDate(String? value) {
  return parseDateOnly(value);
}

String currentBudgetPeriodType(Map<String, dynamic> state) =>
    state['budgetPeriodType'] == 'biweekly' ? 'biweekly' : 'monthly';

String currentBudgetPeriodKey({String type = 'monthly'}) {
  return budgetPeriodKeyFor(DateTime.now(), type);
}

String budgetPeriodKeyFor(DateTime date, String type) {
  final month = '${date.year}-${date.month.toString().padLeft(2, '0')}';
  if (type == 'biweekly') {
    return '$month-${date.day <= 15 ? 'H1' : 'H2'}';
  }
  return month;
}

String previousBudgetPeriodKey(String current, String type) {
  if (type != 'biweekly') {
    final pieces = current.split('-');
    final year = int.tryParse(pieces.first) ?? DateTime.now().year;
    final month =
        int.tryParse(pieces.length > 1 ? pieces[1] : '') ??
        DateTime.now().month;
    return budgetPeriodKeyFor(DateTime(year, month - 1, 1), 'monthly');
  }
  final pieces = current.split('-');
  final year = int.tryParse(pieces.first) ?? DateTime.now().year;
  final month =
      int.tryParse(pieces.length > 1 ? pieces[1] : '') ?? DateTime.now().month;
  final half = pieces.length > 2 ? pieces[2] : 'H1';
  if (half == 'H2') return '$year-${month.toString().padLeft(2, '0')}-H1';
  return budgetPeriodKeyFor(DateTime(year, month - 1, 20), 'biweekly');
}

String budgetPeriodLabel(String key, String type) {
  final range = budgetPeriodDateRange(key, type);
  final dateRange = '${formatDate(range.first)} - ${formatDate(range.last)}';
  if (type != 'biweekly') return '${monthLabelForKey(key)} · $dateRange';
  final pieces = key.split('-');
  final half = pieces.length > 2 && pieces[2] == 'H2'
      ? '2da quincena'
      : '1ra quincena';
  return '$half · $dateRange';
}

List<DateTime> budgetPeriodDateRange(String key, String type) {
  final pieces = key.split('-');
  final year = int.tryParse(pieces.first) ?? DateTime.now().year;
  final month =
      ((int.tryParse(pieces.length > 1 ? pieces[1] : '') ??
                  DateTime.now().month)
              .clamp(1, 12))
          .toInt();
  final lastDay = DateTime(year, month + 1, 0).day;
  if (type == 'biweekly') {
    final secondHalf = pieces.length > 2 && pieces[2] == 'H2';
    return [
      DateTime(year, month, secondHalf ? 16 : 1),
      DateTime(year, month, secondHalf ? lastDay : 15),
    ];
  }
  return [DateTime(year, month, 1), DateTime(year, month, lastDay)];
}

String monthLabelForKey(String key) {
  const months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];
  final pieces = key.split('-');
  final year = int.tryParse(pieces.first) ?? DateTime.now().year;
  final month =
      ((int.tryParse(pieces.length > 1 ? pieces[1] : '') ??
                  DateTime.now().month)
              .clamp(1, 12))
          .toInt();
  return '${months[month - 1]} de $year';
}

bool movementInBudgetPeriod(
  Map<String, dynamic> movement,
  String period,
  String type,
) {
  final date = parseMovementDate(movement['date']?.toString());
  if (date.millisecondsSinceEpoch == 0) return false;
  return budgetPeriodKeyFor(date, type) == period;
}

String budgetItemPeriod(Map<String, dynamic> budget, String type) {
  final period = budget['period']?.toString() ?? '';
  if (period.isNotEmpty) return period;
  final month = budget['month']?.toString() ?? currentMonthKey();
  if (type == 'biweekly') return currentBudgetPeriodKey(type: 'biweekly');
  return month;
}

bool isNationalBankAccount(Map<String, dynamic>? account) =>
    account != null && account['kind'] == 'national';

bool isCashAccount(Map<String, dynamic>? account) =>
    account != null && account['kind'] == 'cash';

bool isFeeExemptPaymentMethod(String method) =>
    method == 'payment_mobile_c2p' ||
    method == 'payment_mobile_p2c' ||
    method == 'debit_card';

bool canConfigureBankFee(
  Map<String, dynamic>? account, {
  required String type,
  Map<String, dynamic>? target,
  String category = '',
  String method = 'bank_transfer',
}) {
  if (type == 'income') return false;
  if (isFeeExemptCategory(category)) return false;
  if (isFeeExemptPaymentMethod(method)) return false;
  if (!isNationalBankAccount(account)) return false;
  if (account?['currency'] != 'VES') return false;
  if (type == 'transfer') {
    return isNationalBankAccount(target) && target?['currency'] == 'VES';
  }
  return type == 'expense' && !isCashAccount(account);
}

String bankTransferScopeForAccounts(
  Map<String, dynamic>? source,
  Map<String, dynamic>? target,
) {
  final provider = source?['provider']?.toString().trim().toUpperCase() ?? '';
  final targetProvider =
      target?['provider']?.toString().trim().toUpperCase() ?? '';
  return provider.isNotEmpty && provider == targetProvider
      ? 'same_bank'
      : 'other_bank';
}

double bankTransferFee(
  Map<String, dynamic>? source,
  Map<String, dynamic>? target,
  double amount,
) {
  if (!canConfigureBankFee(source, type: 'transfer', target: target)) return 0;
  return estimatedBankFee(
    method: 'bank_transfer',
    amount: amount,
    type: 'transfer',
    bankTransferScope: bankTransferScopeForAccounts(source, target),
  );
}

double estimatedBankFee({
  required String method,
  required double amount,
  required String type,
  String category = '',
  String bankTransferScope = 'other_bank',
}) {
  if (type == 'income') return 0;
  if (amount <= 0) return 0;
  if (isFeeExemptCategory(category)) return 0;
  if (isFeeExemptPaymentMethod(method)) return 0;
  if (method == 'bank_transfer' && bankTransferScope == 'same_bank') return 0;
  if (type == 'transfer') return math.max(14, moneyConvert(amount, .003));
  switch (method) {
    case 'bank_transfer':
      return math.max(14, moneyConvert(amount, .003));
    default:
      return math.max(14, moneyConvert(amount, .003));
  }
}

String paymentMethodLabel(String method) {
  switch (method) {
    case 'payment_mobile_c2p':
    case 'payment_mobile_p2c':
      return 'Pago móvil C2P';
    case 'bank_transfer':
      return 'Transferencia bancaria';
    case 'debit_card':
      return 'Tarjeta';
    default:
      return 'Pago móvil';
  }
}

String paymentMethodFromLabel(String label) {
  if (label == 'Pago móvil C2P' || label == 'Pago móvil comercio') {
    return 'payment_mobile_c2p';
  }
  if (label == 'Transferencia bancaria') return 'bank_transfer';
  if (label == 'Tarjeta') return 'debit_card';
  return 'payment_mobile_p2p';
}

String feeModeLabel(String mode) {
  switch (mode) {
    case 'manual':
      return 'Manual';
    case 'none':
      return 'Sin comisión';
    default:
      return 'Automática';
  }
}

String feeModeFromLabel(String label) {
  if (label == 'Manual') return 'manual';
  if (label == 'Sin comisión') return 'none';
  return 'auto';
}

String bankTransferScopeLabel(String value) {
  return value == 'same_bank' ? 'Mismo banco' : 'Otro banco';
}

String bankTransferScopeFromLabel(String label) {
  return label == 'Mismo banco' ? 'same_bank' : 'other_bank';
}

String monthKeyFromDate(String? value) {
  final date = parseMovementDate(value);
  if (date.millisecondsSinceEpoch == 0) return currentMonthKey();
  return '${date.year}-${date.month.toString().padLeft(2, '0')}';
}

String formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String displayDateOnly(String? value) {
  final date = parseDateOnly(value);
  return date.year == 9999 ? '' : formatDate(date);
}

DateTime parseDateOnly(String? value) {
  if (value == null || value.trim().isEmpty) {
    return DateTime(9999, 12, 31);
  }
  final raw = value.trim();
  final displayMatch = RegExp(r'^(\d{2})/(\d{2})/(\d{4})').firstMatch(raw);
  if (displayMatch != null) {
    return DateTime(
      int.parse(displayMatch.group(3)!),
      int.parse(displayMatch.group(2)!),
      int.parse(displayMatch.group(1)!),
    );
  }
  final isoMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
  if (isoMatch != null) {
    return DateTime(
      int.parse(isoMatch.group(1)!),
      int.parse(isoMatch.group(2)!),
      int.parse(isoMatch.group(3)!),
    );
  }
  final parsed = DateTime.tryParse(raw);
  return parsed ?? DateTime(9999, 12, 31);
}

String calendarMonthTitle(DateTime date) {
  const months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

List<DateTime?> calendarCells(DateTime month) {
  final firstDay = DateTime(month.year, month.month);
  final lastDay = DateTime(month.year, month.month + 1, 0).day;
  final cells = <DateTime?>[];
  for (var i = 1; i < firstDay.weekday; i++) {
    cells.add(null);
  }
  for (var day = 1; day <= lastDay; day++) {
    cells.add(DateTime(month.year, month.month, day));
  }
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  while (cells.length < 42) {
    cells.add(null);
  }
  return cells;
}

bool monthCanMove(DateTime current, DateTime limit, int direction) {
  final target = DateTime(current.year, current.month + direction);
  final targetMonth = DateTime(target.year, target.month);
  final limitMonth = DateTime(limit.year, limit.month);
  return direction < 0
      ? !targetMonth.isBefore(limitMonth)
      : !targetMonth.isAfter(limitMonth);
}

bool isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String isoDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String expectedRateDateKey(DateTime now) {
  var effective = DateTime(now.year, now.month, now.day);
  if (now.weekday == DateTime.friday && now.hour >= 18) {
    effective = effective.add(const Duration(days: 3));
  } else if (now.weekday == DateTime.saturday) {
    effective = effective.add(const Duration(days: 2));
  } else if (now.weekday == DateTime.sunday) {
    effective = effective.add(const Duration(days: 1));
  }
  return isoDate(effective);
}

String officialRateLine(String currency, double value) {
  if (value <= 0) return 'Tasa oficial no disponible';
  final unit = currency == 'EUR' ? '1€' : r'1$';
  return '$unit = Bs. ${decimal(value)}';
}

String rateUpdatedLabel(Map<String, dynamic> state) {
  final millis = numberValue(state['lastRateMillis']).round();
  if (millis > 0) {
    return 'Actualizado ${shortDateTime(DateTime.fromMillisecondsSinceEpoch(millis))}';
  }
  final date = state['rateEffectiveDate']?.toString() ?? '';
  if (date.isNotEmpty) return 'Actualizado $date';
  return 'Actualiza la tasa al abrir la app con conexión';
}

String shortDateTime(DateTime date) {
  const months = [
    'ene.',
    'feb.',
    'mar.',
    'abr.',
    'may.',
    'jun.',
    'jul.',
    'ago.',
    'sep.',
    'oct.',
    'nov.',
    'dic.',
  ];
  final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final ampm = date.hour < 12 ? 'AM' : 'PM';
  return '${date.day} ${months[date.month - 1]} a las $hour12:${date.minute.toString().padLeft(2, '0')} $ampm';
}

String monthLabel() {
  const months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];
  final now = DateTime.now();
  return '${months[now.month - 1]} de ${now.year}';
}

String formatDateTime(DateTime date) {
  final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final ampm = date.hour < 12 ? 'AM' : 'PM';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${hour12.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} $ampm';
}

String timeOnlyLabel(DateTime date) {
  final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final ampm = date.hour < 12 ? 'AM' : 'PM';
  return '$hour12:${date.minute.toString().padLeft(2, '0')} $ampm';
}

DateTime parseMovementDate(String? value) {
  if (value == null) return DateTime.fromMillisecondsSinceEpoch(0);
  if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(value)) {
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso.toLocal();
  }
  final match = RegExp(
    r'(\d{2})/(\d{2})/(\d{4})(?:\s+(\d{1,2}):(\d{2})\s*(AM|PM)?)?',
  ).firstMatch(value);
  if (match == null) return DateTime.fromMillisecondsSinceEpoch(0);
  var hour = int.tryParse(match.group(4) ?? '0') ?? 0;
  final minute = int.tryParse(match.group(5) ?? '0') ?? 0;
  final ampm = match.group(6);
  if (ampm == 'PM' && hour < 12) hour += 12;
  if (ampm == 'AM' && hour == 12) hour = 0;
  return DateTime(
    int.parse(match.group(3)!),
    int.parse(match.group(2)!),
    int.parse(match.group(1)!),
    hour,
    minute,
  );
}
