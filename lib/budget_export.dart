part of 'main.dart';

Map<String, dynamic> budgetReport({
  required Map<String, dynamic> plan,
  required List<Map<String, dynamic>> items,
  required List<Map<String, dynamic>> movements,
  required double usdRate,
  required double eurRate,
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
  double convert(String key) => budgetUsd(
    numberValue(plan[key]),
    plan['currency']?.toString() ?? 'USD',
    usdRate,
    eurRate,
  );
  final ranked = limits.keys.toList()
    ..sort(
      (a, b) =>
          (spending.categories[b] ?? 0).compareTo(spending.categories[a] ?? 0),
    );
  return {
    'period': period,
    'title':
        monthLabelForKey(period.substring(0, 7)) +
        (type == 'biweekly'
            ? (period.endsWith('H1') ? ' - 1ra quincena' : ' - 2da quincena')
            : ''),
    'range': formatDate(range.first) + ' - ' + formatDate(range.last),
    'generated': formatDate(now ?? DateTime.now()),
    'income': plan['incomeMode'] == 'variable'
        ? 'Variable'
        : money(convert('salary'), 'USD'),
    'savings': money(convert('savings'), 'USD'),
    'planned': money(planned, 'USD'),
    'spent': money(spending.total, 'USD'),
    'remaining': money(moneySubtract(planned, spending.total), 'USD'),
    'over': spending.total > planned,
    'rateNote':
        'Montos en USD. Conversi\u00f3n al exportar: USD/VES ' +
        usdRate.toStringAsFixed(2) +
        ' | EUR/VES ' +
        eurRate.toStringAsFixed(2),
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
  pw.Widget text(String value, {double size = 11, PdfColor color = ink}) =>
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
    padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 7),
    child: child,
  );
  final rows = (report['rows'] as List).cast<Map>();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      maxPages: 200,
      margin: const pw.EdgeInsets.all(40),
      theme: pw.ThemeData.withFont(base: font, bold: font),
      header: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 22),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            text('SIN RIAL', size: 10, color: accent),
            pw.SizedBox(height: 10),
            text('Presupuesto', size: 26),
            pw.SizedBox(height: 6),
            text(report['title'].toString(), size: 13),
            pw.SizedBox(height: 4),
            text(report['range'].toString(), size: 10, color: muted),
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
        pw.Row(
          children: [
            for (final entry in {
              'Planificado': 'planned',
              'Gastado': 'spent',
              'Disponible': 'remaining',
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
        pw.SizedBox(height: 25),
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
        pw.SizedBox(height: 24),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(2),
            1: pw.FlexColumnWidth(1.1),
            2: pw.FlexColumnWidth(1.1),
            3: pw.FlexColumnWidth(1.1),
          },
          border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(color: PdfColors.grey200),
          ),
          children: [
            pw.TableRow(
              repeat: true,
              children: [
                for (final title in [
                  'CATEGORIA',
                  'LIMITE',
                  'GASTADO',
                  'DISPONIBLE',
                ])
                  cell(
                    pw.Align(
                      alignment: title == 'CATEGORIA'
                          ? pw.Alignment.centerLeft
                          : pw.Alignment.centerRight,
                      child: text(title, size: 9, color: muted),
                    ),
                  ),
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
                        text(row['name'].toString()),
                        pw.SizedBox(height: 8),
                        pw.LinearProgressIndicator(
                          value: numberValue(row['fraction']).clamp(0, 1),
                          minHeight: 4,
                          backgroundColor: PdfColors.grey200,
                          valueColor: row['over'] == true
                              ? red
                              : PdfColor.fromInt((row['color'] as num).toInt()),
                        ),
                      ],
                    ),
                  ),
                  cell(amount(row['limit'].toString())),
                  cell(amount(row['spent'].toString())),
                  cell(
                    amount(
                      row['remaining'].toString(),
                      color: row['over'] == true ? red : ink,
                    ),
                  ),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 18),
        text(
          'Solo categor\u00edas incluidas en este plan.',
          size: 10,
          color: muted,
        ),
        pw.SizedBox(height: 6),
        text(report['rateNote'].toString(), size: 9, color: muted),
      ],
    ),
  );
  return pdf.save();
}
