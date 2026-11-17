part of 'main.dart';

const creditIndexUrl =
    'https://www.bcv.org.ve/estadisticas/indice-de-inversion';

// The BCV table also contains exchange rates and the obsolete index. Match the
// current-expression column explicitly so neither can become an IDI by mistake.
List<Map<String, dynamic>> parseCreditIndexTable(String source) {
  final document = html_parser.parse(source);
  final quotes = <Map<String, dynamic>>[];
  for (final row in document.querySelectorAll('.view-id-nuevo_indicador tr')) {
    final dateCell = row.querySelector(
      '.views-field-field-fecha-del-indicador',
    );
    final valueCell = row.querySelector('td.views-field-nothing');
    if (dateCell == null || valueCell == null) continue;
    final parts = dateCell.text.trim().split('-');
    if (parts.length != 3) continue;
    final day = int.tryParse(parts[0]), month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) continue;
    final date = DateTime(year, month, day);
    if (date.day != day || date.month != month || date.year != year) continue;
    final text = valueCell.text.trim().replaceAll('.', '').replaceAll(',', '.');
    final value = Decimal.tryParse(text);
    if (value == null || value <= Decimal.zero || value.toDouble() > 1000000000)
      continue;
    quotes.add({'date': date.toIso8601String(), 'index': value.toString()});
  }
  if (quotes.isEmpty)
    throw const FormatException('El BCV no devolvió un IDI válido.');
  quotes.sort((a, b) => a['date'].toString().compareTo(b['date'].toString()));
  return quotes;
}

Map<String, dynamic>? creditIndexForDate(
  Iterable<dynamic> quotes,
  DateTime date,
) {
  final day = DateTime(date.year, date.month, date.day);
  Map<String, dynamic>? latest;
  DateTime? latestDate;
  for (final raw in quotes.whereType<Map>()) {
    final quoteDate = DateTime.tryParse(raw['date']?.toString() ?? '');
    final value = numberValue(raw['index']);
    if (quoteDate == null ||
        quoteDate.isAfter(day) ||
        !value.isFinite ||
        value <= 0 ||
        value > 1000000000)
      continue;
    if (latestDate == null || !quoteDate.isBefore(latestDate)) {
      latest = Map<String, dynamic>.from(raw);
      latestDate = quoteDate;
    }
  }
  return latest;
}

Future<List<Map<String, dynamic>>> fetchCreditIndex() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client
        .getUrl(Uri.parse(creditIndexUrl))
        .timeout(const Duration(seconds: 10));
    request.headers.set(HttpHeaders.userAgentHeader, 'SinRial/3.6');
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode != HttpStatus.ok)
      throw const HttpException('IDI no disponible');
    final body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 10));
    return await compute(parseCreditIndexTable, body);
  } finally {
    client.close(force: true);
  }
}

bool applyOfficialCreditIndex(
  Map<String, dynamic> card,
  List<Map<String, dynamic>> quotes,
  DateTime now,
) {
  if (!isIndexedCredit(card)) return false;
  final quote = creditIndexForDate(quotes, now);
  if (quote == null) return false;
  final oldDate = DateTime.tryParse(card['creditIndexDate']?.toString() ?? '');
  if (oldDate != null && oldDate.isAfter(DateTime.parse(quote['date'])))
    return false;
  final oldIndex = numberValue(card['creditIndex']);
  if ((!oldIndex.isFinite || oldIndex <= 0) &&
      (Decimal.tryParse(card['creditUnits']?.toString() ?? '') == null ||
          Decimal.tryParse(card['creditLimitUnits']?.toString() ?? '') == null))
    return false;
  // Migrate existing nominal snapshots once, before replacing their index.
  final units = indexedCreditUnits(card).toString();
  final limitUnits =
      card['creditLimitUnits']?.toString() ??
      creditUnitsFor(
        numberValue(card['creditLimit']),
        numberValue(card['creditIndex']),
      ).toString();
  final history = <String, Map<String, dynamic>>{
    for (final raw
        in (card['creditIndexHistory'] as List? ?? []).whereType<Map>())
      raw['date'].toString(): Map<String, dynamic>.from(raw),
    for (final item in quotes.where(
      (q) => !DateTime.parse(q['date']).isAfter(now),
    ))
      item['date'].toString(): item,
  };
  card.addAll({
    'creditUnits': units,
    'creditLimitUnits': limitUnits,
    'creditIndex': quote['index'],
    'creditIndexDate': quote['date'],
    'creditIndexHistory': history.values.toList(),
    'creditIndexSource': 'BCV',
  });
  refreshIndexedCreditBalance(card);
  return true;
}

extension _CreditIndexActions on _RialAppState {
  Map<String, dynamic>? get officialCreditIndex => creditIndexForDate(
    (state['creditIndexQuotes'] as List?) ?? [],
    DateTime.now(),
  );

  Future<void> refreshCreditIndex({
    bool force = false,
    bool forEditor = false,
  }) {
    if (_creditIndexPending != null) return _creditIndexPending!;
    final now = DateTime.now();
    final checked = DateTime.tryParse(
      state['creditIndexCheckedAt']?.toString() ?? '',
    );
    if (!force && checked != null && isSameDate(checked, now))
      return Future.value();
    if (!force &&
        _creditIndexAttempt != null &&
        now.difference(_creditIndexAttempt!) < const Duration(minutes: 5))
      return Future.value();
    if (!force && !forEditor && !maps('accounts').any(isIndexedCredit))
      return Future.value();
    _creditIndexAttempt = now;
    final originalState = state;
    final pending = () async {
      try {
        final quotes = await fetchCreditIndex();
        if (!mounted || _restoringBackup || !identical(state, originalState))
          return;
        if (creditIndexForDate(quotes, now) == null) return;
        mutate(() {
          state['creditIndexQuotes'] = quotes;
          state['creditIndexCheckedAt'] = now.toIso8601String();
          for (final card in maps('accounts')) {
            applyOfficialCreditIndex(card, quotes, now);
          }
        });
      } catch (_) {
        // Offline: retain the last published quote, its date and the UVC ledger.
      }
    }();
    _creditIndexPending = pending.whenComplete(
      () => _creditIndexPending = null,
    );
    return _creditIndexPending!;
  }
}
