part of 'main.dart';

Map<String, dynamic> budgetReport({
  required Map<String, dynamic> plan,
  required List<Map<String, dynamic>> items,
  required List<Map<String, dynamic>> movements,
  required double usdRate,
  required double eurRate,
  List<Map<String, dynamic>> accounts = const [],
  DateTime? now,
}) {
  final period = plan['period'].toString(),
      type = plan['periodType'].toString();
  final range = budgetPeriodDateRange(period, type);
  final limits = <String, double>{};
  for (final item in items.where((item) => item['planId'] == plan['id'])) {
    final name = item['category'].toString();
    limits[name] = moneyAdd(
      limits[name] ?? 0,
      budgetUsd(
        numberValue(item['limit']),
        item['currency']?.toString() ?? 'USD',
        usdRate,
        eurRate,
      ),
    );
  }
  final spending = summarizeBudgetSpending(
    movements,
    period,
    type,
    usdRate: usdRate,
    eurRate: eurRate,
    selectedCategories: limits.keys.toSet(),
  );
  // A complete report must never present partially converted totals as final.
  if (spending.missingRates > 0) {
    throw const FormatException(
      'Actualiza las tasas antes de exportar el presupuesto.',
    );
  }
  final planned = limits.values.fold<double>(0, moneyAdd);
  final accountsById = {for (final account in accounts) account['id']: account};
  final end = range.last.add(const Duration(days: 1));
  final details = <Map<String, dynamic>>[];
  for (final movement in movements) {
    if (!isExpenseType(movement['type']?.toString())) continue;
    final date = parseMovementDate(movement['date']?.toString());
    final rawCategory = movement['category']?.toString().trim() ?? '';
    final category = rawCategory.isEmpty ? 'Otro' : rawCategory;
    if (date.isBefore(range.first) ||
        !date.isBefore(end) ||
        !limits.containsKey(category)) {
      continue;
    }
    final currency = movement['currency']?.toString() ?? 'USD';
    final amount = numberValue(movement['amount']);
    final fee = numberValue(movement['feeAmount']);
    // Convert amount + fee together, exactly as the budget summary does.
    final total = budgetUsd(moneyAdd(amount, fee), currency, usdRate, eurRate);
    final account = accountsById[movement['accountId']];
    details.add({
      'timestamp': date.millisecondsSinceEpoch,
      'date': formatDateTime(date),
      'category': category,
      'description': movement['description']?.toString().trim() ?? '',
      'account': account == null
          ? 'Cuenta no disponible'
          : accountPrimaryName(account),
      'currency': currency,
      'amount': formatNumber(amount),
      'fee': formatNumber(fee),
      'hasFee': moneyCents(fee) != 0,
      'total': money(total, 'USD'),
      'totalValue': total,
    });
  }
  details.sort(
    (a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int),
  );
  double convert(String key) => budgetUsd(
    numberValue(plan[key]),
    plan['currency']?.toString() ?? 'USD',
    usdRate,
    eurRate,
  );
  final ranked = limits.keys.toList()
    ..sort((a, b) {
      final result = (spending.categories[b] ?? 0).compareTo(
        spending.categories[a] ?? 0,
      );
      return result == 0 ? a.compareTo(b) : result;
    });
  return {
    'period': period,
    'title':
        monthLabelForKey(period.substring(0, 7)) +
        (type == 'biweekly'
            ? (period.endsWith('H1') ? ' - 1ra quincena' : ' - 2da quincena')
            : ''),
    'range': formatDate(range.first) + ' - ' + formatDate(range.last),
    'generated': formatDateTime(now ?? DateTime.now()),
    'income': plan['incomeMode'] == 'variable'
        ? 'Variable'
        : money(convert('salary'), 'USD'),
    'savings': money(convert('savings'), 'USD'),
    'planned': money(planned, 'USD'),
    'spent': money(spending.total, 'USD'),
    'remaining': money(moneySubtract(planned, spending.total), 'USD'),
    'over': spending.total > planned,
    'usage': planned > 0
        ? '${formatNumber(spending.total / planned * 100)}%'
        : '--',
    'exceededCategories': limits.keys
        .where((name) => (spending.categories[name] ?? 0) > limits[name]!)
        .length,
    'details': details,
    'unassigned': plan['incomeMode'] == 'variable'
        ? null
        : money(
            moneySubtract(
              moneySubtract(convert('salary'), convert('savings')),
              planned,
            ),
            'USD',
          ),
    'rateNote':
        'Resumen en USD. Tasas al exportar, no tasas hist\u00f3ricas: USD/VES ' +
        (usdRate > 0 ? formatNumber(usdRate) : 'no disponible') +
        ' | EUR/VES ' +
        (eurRate > 0 ? formatNumber(eurRate) : 'no disponible') +
        '. USD y USDT se contabilizan 1 a 1. Cada movimiento incluye su comisi\u00f3n y se redondea a dos decimales.',
    'rows': [
      for (final name in ranked)
        {
          'name': name,
          'limit': money(limits[name]!, 'USD'),
          'spent': money(spending.categories[name] ?? 0, 'USD'),
          'remaining': money(
            moneySubtract(limits[name]!, spending.categories[name] ?? 0),
            'USD',
          ),
          'over': (spending.categories[name] ?? 0) > limits[name]!,
          'usage': limits[name]! > 0
              ? '${formatNumber((spending.categories[name] ?? 0) / limits[name]! * 100)}%'
              : '--',
          'share': spending.total > 0
              ? '${formatNumber((spending.categories[name] ?? 0) / spending.total * 100)}%'
              : '0,00%',
          'spentCents': moneyCents(spending.categories[name] ?? 0),
          'excess': money(
            math.max(
              0.0,
              moneySubtract(spending.categories[name] ?? 0, limits[name]!),
            ),
            'USD',
          ),
          'fraction': limits[name]! > 0
              ? (spending.categories[name] ?? 0) / limits[name]!
              : 0,
          'color': budgetCategoryColor(name, RTheme(false, 'teal')).toARGB32(),
        },
    ],
  };
}

Future<bool> saveBudgetPdf(Map<String, dynamic> report) async {
  final font = await rootBundle.load('assets/fonts/Manrope-Medium.ttf');
  final bytes = await compute(renderBudgetPdf, {...report, 'font': font});
  return await _storeChannel.invokeMethod<bool>('exportBudgetPdf', {
        'bytes': bytes,
        'name': 'Sin-Rial-presupuesto-' + report['period'].toString() + '.pdf',
      }) ??
      false;
}

Future<Uint8List> renderBudgetPdf(Map<String, dynamic> report) async {
  final fontData = report['font'] as ByteData?;
  final font = fontData == null ? pw.Font.helvetica() : pw.Font.ttf(fontData);
  final pdf = pw.Document(
    title: 'Presupuesto - ' + report['title'].toString(),
    author: 'Sin Rial',
  );
  const ink = PdfColor.fromInt(0xff202428),
      muted = PdfColor.fromInt(0xff616971),
      accent = PdfColor.fromInt(0xff247b7b),
      red = PdfColor.fromInt(0xffb83452);
  pw.Widget text(String value, {double size = 10, PdfColor color = ink}) =>
      pw.Text(
        value,
        style: pw.TextStyle(fontSize: size, color: color),
      );
  pw.Widget amount(String value, {PdfColor color = ink, double size = 11}) =>
      pw.FittedBox(
        fit: pw.BoxFit.scaleDown,
        alignment: pw.Alignment.centerRight,
        child: text(value, size: size, color: color),
      );
  pw.Widget cell(pw.Widget child) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 6),
    child: child,
  );
  final rows = (report['rows'] as List).cast<Map>();
  final details = (report['details'] as List? ?? const []).cast<Map>();
  final distribution = rows
      .where((row) => numberValue(row['spentCents']) > 0)
      .toList();
  pw.Widget section(String title, {String? subtitle}) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 22, bottom: 10),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        text(title, size: 14, color: accent),
        if (subtitle != null) ...[
          pw.SizedBox(height: 4),
          text(subtitle, size: 9, color: muted),
        ],
      ],
    ),
  );
  pw.Widget tableHeading(String title, {bool right = false}) => cell(
    pw.Align(
      alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      child: text(title, size: 8, color: muted),
    ),
  );
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      maxPages: 200,
      margin: const pw.EdgeInsets.all(40),
      theme: pw.ThemeData.withFont(base: font, bold: font),
      header: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 18),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            text('SIN RIAL', size: 10, color: accent),
            text(report['title'].toString(), size: 9, color: muted),
          ],
        ),
      ),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 10),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            text(
              'Sin Rial | ' + report['generated'].toString(),
              size: 9,
              color: muted,
            ),
            text(
              context.pageNumber.toString() +
                  ' / ' +
                  context.pagesCount.toString(),
              size: 9,
              color: muted,
            ),
          ],
        ),
      ),
      build: (_) => [
        text('Informe de presupuesto', size: 25),
        pw.SizedBox(height: 6),
        text(report['range'].toString(), color: muted),
        pw.SizedBox(height: 24),
        pw.Row(
          children: [
            for (final entry in {
              'Planificado': 'planned',
              'Gastado': 'spent',
              'Restante del plan': 'remaining',
            }.entries)
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(right: 12),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      text(entry.key, size: 10, color: muted),
                      pw.SizedBox(height: 6),
                      pw.FittedBox(
                        fit: pw.BoxFit.scaleDown,
                        child: text(
                          report[entry.value].toString(),
                          size: 21,
                          color:
                              entry.value == 'remaining' &&
                                  report['over'] == true
                              ? red
                              : ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        pw.SizedBox(height: 12),
        text(
          '${report['usage']} del l\u00edmite utilizado  |  Movimientos: ${details.length}  |  Categor\u00edas excedidas: ${report['exceededCategories']}',
          size: 9,
          color: muted,
        ),
        section('Planificaci\u00f3n'),
        pw.Row(
          children: [
            pw.Expanded(
              child: text('Ingreso previsto: ' + report['income'].toString()),
            ),
            pw.Expanded(
              child: amount('Ahorro previsto: ' + report['savings'].toString()),
            ),
          ],
        ),
        if (report['unassigned'] != null) ...[
          pw.SizedBox(height: 8),
          text(
            'Sin asignar del ingreso previsto: ${report['unassigned']}',
            size: 10,
            color: muted,
          ),
        ],
        pw.SizedBox(height: 8),
        text(
          'El ingreso y el ahorro son objetivos del plan, no montos efectivamente recibidos o ahorrados. El restante compara los l\u00edmites con los gastos incluidos; no es el saldo de tus cuentas.',
          size: 9,
          color: muted,
        ),
        section(
          'Consumo por categor\u00eda',
          subtitle: 'Solo las categor\u00edas elegidas en este plan. Las comisiones est\u00e1n incluidas.',
        ),
        if (distribution.isNotEmpty) ...[
          pw.SizedBox(
            height: 8,
            child: pw.Row(
              children: [
                for (final row in distribution)
                  pw.Expanded(
                    flex: (row['spentCents'] as num).toInt(),
                    child: pw.Container(
                      color: PdfColor.fromInt((row['color'] as num).toInt()),
                    ),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 5),
          text(
            'Distribuci\u00f3n del gasto total por color; participaci\u00f3n indicada bajo cada categor\u00eda.',
            size: 8,
            color: muted,
          ),
        ],
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(2.1),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(1),
            3: pw.FlexColumnWidth(1.25),
          },
          border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(color: PdfColors.grey200),
          ),
          children: [
            pw.TableRow(
              repeat: true,
              children: [
                tableHeading('CATEGOR\u00cdA'),
                tableHeading('L\u00cdMITE', right: true),
                tableHeading('GASTADO', right: true),
                tableHeading('RESTANTE', right: true),
              ],
            ),
            for (final row in rows)
              pw.TableRow(
                verticalAlignment: pw.TableCellVerticalAlignment.middle,
                children: [
                  cell(
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        text(row['name'].toString(), size: 10),
                        pw.SizedBox(height: 5),
                        pw.LinearProgressIndicator(
                          value: numberValue(row['fraction']).clamp(0, 1),
                          minHeight: 4,
                          backgroundColor: PdfColors.grey200,
                          valueColor: PdfColor.fromInt(
                            (row['color'] as num).toInt(),
                          ),
                        ),
                        pw.SizedBox(height: 5),
                        text(
                          '${row['usage'] ?? '--'} del l\u00edmite | ${row['share'] ?? '--'} del gasto',
                          size: 7,
                          color: row['over'] == true ? red : muted,
                        ),
                      ],
                    ),
                  ),
                  cell(amount(row['limit'].toString())),
                  cell(amount(row['spent'].toString())),
                  cell(
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        amount(
                          row['remaining'].toString(),
                          color: row['over'] == true ? red : ink,
                        ),
                        if (row['over'] == true && row['excess'] != null) ...[
                          pw.SizedBox(height: 5),
                          amount(
                            'Exceso: ${row['excess']}',
                            size: 8,
                            color: red,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (rows.isEmpty)
          text('Este plan no tiene categor\u00edas asignadas.', color: muted),
        pw.SizedBox(height: 18),
        text(report['rateNote'].toString(), size: 9, color: muted),
        if (details.isEmpty)
          section(
            'Sin movimientos en este plan',
            subtitle:
                'No hay gastos registrados para sus categor\u00edas y fechas.',
          )
        else ...[
          pw.NewPage(),
          section(
            'Detalle de movimientos',
            subtitle:
                '${details.length} registros | Orden cronol\u00f3gico | Total incluido: ${report['spent']}',
          ),
          text(
            'El total USD incluye la comisi\u00f3n. Solo gastos del periodo y de las categor\u00edas del plan; no incluye ingresos ni transferencias.',
            size: 9,
            color: muted,
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(1.15),
              1: pw.FlexColumnWidth(2.3),
              2: pw.FlexColumnWidth(1.4),
              3: pw.FlexColumnWidth(1.1),
            },
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: PdfColors.grey200),
            ),
            children: [
              pw.TableRow(
                repeat: true,
                children: [
                  tableHeading('FECHA / HORA'),
                  tableHeading('CONCEPTO / CUENTA'),
                  tableHeading('MONTO ORIGINAL', right: true),
                  tableHeading('TOTAL USD', right: true),
                ],
              ),
              for (final row in details)
                pw.TableRow(
                  children: [
                    cell(text(row['date'].toString(), size: 8)),
                    cell(
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          text(row['category'].toString(), size: 9),
                          if (row['description'].toString().isNotEmpty) ...[
                            pw.SizedBox(height: 3),
                            text(
                              row['description'].toString(),
                              size: 8,
                              color: muted,
                            ),
                          ],
                          pw.SizedBox(height: 3),
                          text(
                            row['account'].toString(),
                            size: 8,
                            color: muted,
                          ),
                        ],
                      ),
                    ),
                    cell(
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          amount(
                            '${row['amount']} ${row['currency']}',
                            size: 9,
                          ),
                          if (row['hasFee'] == true) ...[
                            pw.SizedBox(height: 4),
                            text('Comisi\u00f3n', size: 7, color: muted),
                            amount(
                              '${row['fee']} ${row['currency']}',
                              size: 8,
                              color: muted,
                            ),
                          ],
                        ],
                      ),
                    ),
                    cell(amount(row['total'].toString(), size: 10)),
                  ],
                ),
            ],
          ),
        ],
      ],
    ),
  );
  return pdf.save();
}
