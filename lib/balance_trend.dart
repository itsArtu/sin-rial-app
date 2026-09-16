part of 'main.dart';

class BalanceTrend extends StatefulWidget {
  const BalanceTrend({
    super.key,
    required this.points,
    required this.theme,
    required this.currency,
    required this.hidden,
    required this.period,
  });
  final List<BalancePoint> points;
  final RTheme theme;
  final String currency, period;
  final bool hidden;
  @override
  State<BalanceTrend> createState() => _BalanceTrendState();
}

class _BalanceTrendState extends State<BalanceTrend> {
  int? selected;
  @override
  void didUpdateWidget(covariant BalanceTrend oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points ||
        oldWidget.currency != widget.currency ||
        oldWidget.period != widget.period ||
        widget.hidden)
      selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final points = widget.points;
    final index = (selected ?? points.length - 1)
        .clamp(0, math.max(0, points.length - 1))
        .toInt();
    final point = points.isEmpty ? null : points[index];
    String describe(BalancePoint p) =>
        '${widget.period == 'day' ? timeOnlyLabel(p.date) : formatDate(p.date)} · ${widget.hidden ? hiddenMoney(widget.currency) : money(p.amount, widget.currency)}';
    final label = point == null ? 'Sin movimientos' : describe(point);
    final values = points.map((p) => p.amount);
    final low = values.isEmpty ? 0.0 : values.reduce(math.min);
    final high = values.isEmpty ? 0.0 : values.reduce(math.max);
    final margin = math.max(.01, (high - low) * .15);
    final line = charts.LineChartBarData(
      spots: [
        for (var i = 0; i < points.length; i++)
          charts.FlSpot(i.toDouble(), points[i].amount),
      ],
      color: t.accent,
      barWidth: 2,
      isCurved: false,
      dotData: const charts.FlDotData(show: false),
      showingIndicators: [if (selected != null) index],
      belowBarData: charts.BarAreaData(
        show: true,
        color: t.accent.withOpacity(.08),
      ),
    );
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: widget.hidden || points.length < 2
          ? Center(
              child: Text(
                widget.hidden ? 'Balance oculto' : 'Sin historial',
                style: TextStyle(color: t.muted, fontSize: 12),
              ),
            )
          : Semantics(
              label: 'Evolución del balance',
              value: label,
              hint: 'Cuentas actuales. Tasa actual.',
              increasedValue: describe(
                points[(index + 1).clamp(0, points.length - 1)],
              ),
              decreasedValue: describe(
                points[(index - 1).clamp(0, points.length - 1)],
              ),
              onIncrease: () => setState(
                () => selected = (index + 1).clamp(0, points.length - 1),
              ),
              onDecrease: () => setState(
                () => selected = (index - 1).clamp(0, points.length - 1),
              ),
              child: RepaintBoundary(
                child: charts.LineChart(
                  charts.LineChartData(
                    minY: low - margin,
                    maxY: high + margin,
                    minX: 0,
                    maxX: math.max(1, points.length - 1).toDouble(),
                    titlesData: const charts.FlTitlesData(show: false),
                    gridData: const charts.FlGridData(show: false),
                    borderData: charts.FlBorderData(show: false),
                    lineBarsData: [line],
                    showingTooltipIndicators: [
                      if (selected != null)
                        charts.ShowingTooltipIndicators([
                          charts.LineBarSpot(line, 0, line.spots[index]),
                        ]),
                    ],
                    lineTouchData: charts.LineTouchData(
                      handleBuiltInTouches: false,
                      touchSpotThreshold: 36,
                      touchTooltipData: charts.LineTouchTooltipData(
                        fitInsideHorizontally: true,
                        fitInsideVertically: true,
                        maxContentWidth: 220,
                        tooltipPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        tooltipMargin: 4,
                        tooltipBorder: BorderSide(color: t.border),
                        getTooltipColor: (_) => t.card,
                        getTooltipItems: (spots) => spots
                            .map(
                              (spot) => charts.LineTooltipItem(
                                describe(points[spot.spotIndex]),
                                TextStyle(color: t.ink, fontSize: 12),
                              ),
                            )
                            .toList(),
                      ),
                      touchCallback: (event, response) {
                        final spots = response?.lineBarSpots;
                        if (event.isInterestedForInteractions &&
                            spots != null &&
                            spots.isNotEmpty) {
                          final next = spots.first.spotIndex;
                          if (next != selected) setState(() => selected = next);
                        }
                      },
                    ),
                  ),
                  duration: Duration.zero,
                ),
              ),
            ),
    );
  }
}

class RateStatus extends StatelessWidget {
  const RateStatus({
    super.key,
    required this.theme,
    required this.state,
    required this.currency,
    this.loading = false,
  });
  final RTheme theme;
  final Map<String, dynamic> state;
  final String currency;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    final status = rateStatusText(state, currency, loading: loading);
    final timestamp = rateTimestampText(state, currency);
    return Column(
      children: [
        Text(
          status,
          key: const ValueKey('rate-status'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: status == 'Actualizada' ? theme.green : theme.muted,
            fontSize: 11,
          ),
        ),
        if (timestamp.isNotEmpty)
          Text(
            timestamp,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.muted, fontSize: 10),
          ),
      ],
    );
  }
}
