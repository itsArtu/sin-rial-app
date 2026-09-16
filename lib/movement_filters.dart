part of 'main.dart';

class MovementFilterControls extends StatefulWidget {
  const MovementFilterControls({
    super.key,
    required this.app,
    required this.mode,
    required this.onChanged,
  });
  final _RialAppState app;
  final MovementHistoryMode mode;
  final ValueChanged<MovementFilter> onChanged;
  @override
  State<MovementFilterControls> createState() => _MovementFilterControlsState();
}

class _MovementFilterControlsState extends State<MovementFilterControls> {
  final query = TextEditingController();
  Timer? debounce;
  String account = 'all', type = 'all', category = 'all', currency = 'all';
  DateTime? start, end;
  String dateLabel = 'Fechas';
  @override
  void dispose() {
    debounce?.cancel();
    query.dispose();
    super.dispose();
  }

  void emit() {
    widget.onChanged(
      MovementFilter(
        query: query.text,
        accountId: account,
        type: type,
        category: category,
        currency: currency,
        start: start,
        end: end,
      ),
    );
  }

  void change(VoidCallback action) {
    setState(action);
    emit();
  }

  Future<void> dates(String preset) async {
    final now = DateTime.now();
    DateTime? nextStart, nextEnd;
    if (preset == 'Personalizado') {
      nextStart = await pickModernDate(
        context: context,
        theme: widget.app.theme,
        initial: start ?? now,
      );
      if (!mounted || nextStart == null) return;
      nextEnd = await pickModernDate(
        context: context,
        theme: widget.app.theme,
        initial: end ?? nextStart,
      );
      if (!mounted || nextEnd == null) return;
      if (nextEnd.isBefore(nextStart)) {
        final swap = nextStart;
        nextStart = nextEnd;
        nextEnd = swap;
      }
    } else if (preset != 'Todas las fechas') {
      nextEnd = DateTime(now.year, now.month, now.day);
      nextStart = switch (preset) {
        'Hoy' => nextEnd,
        'Últimos 7 días' => DateTime(now.year, now.month, now.day - 6),
        _ => DateTime(now.year, now.month),
      };
    }
    change(() {
      start = nextStart;
      end = nextEnd;
      dateLabel = nextStart == null
          ? 'Fechas'
          : preset == 'Personalizado'
          ? '${formatDate(nextStart)} - ${formatDate(nextEnd!)}'
          : preset;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.app.theme;
    final accounts = widget.app.maps('accounts');
    final categories =
        widget.app
            .maps('movements')
            .map((m) => m['category']?.toString() ?? '')
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    Widget chip(String label, bool active, VoidCallback action) =>
        FilterChip(theme: t, label: label, selected: active, onTap: action);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CupertinoSearchTextField(
          controller: query,
          placeholder: 'Buscar movimientos',
          style: TextStyle(
            color: t.ink,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
          placeholderStyle: TextStyle(
            color: t.muted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          prefixInsets: const EdgeInsetsDirectional.only(start: 14),
          suffixInsets: const EdgeInsetsDirectional.only(end: 14),
          itemSize: 18,
          itemColor: t.muted,
          decoration: BoxDecoration(
            color: t.field,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.border),
          ),
          onChanged: (_) {
            debounce?.cancel();
            debounce = Timer(const Duration(milliseconds: 220), emit);
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            chip(
              account == 'all'
                  ? 'Cuenta'
                  : accountLabel(
                      accounts.firstWhere(
                        (a) => a['id'] == account,
                        orElse: () => {},
                      ),
                    ),
              account != 'all',
              () => showModernActionSheet(
                context,
                title: 'Cuenta',
                actions: [
                  ModernSheetAction(
                    icon: CupertinoIcons.square_grid_2x2,
                    title: 'Todas las cuentas',
                    onPressed: () => change(() => account = 'all'),
                  ),
                  ...accounts.map(
                    (a) => ModernSheetAction(
                      icon: CupertinoIcons.creditcard,
                      title: accountLabel(a),
                      selected: a['id'] == account,
                      onPressed: () =>
                          change(() => account = a['id'].toString()),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.mode == MovementHistoryMode.all)
              chip(
                switch (type) {
                  'income' => 'Ingresos',
                  'expense' => 'Gastos',
                  'transfer' => 'Transferencias',
                  _ => 'Tipo',
                },
                type != 'all',
                () => pickValue(
                  context,
                  ['Todos', 'Ingresos', 'Gastos', 'Transferencias'],
                  '',
                  (v) => change(
                    () => type = switch (v) {
                      'Ingresos' => 'income',
                      'Gastos' => 'expense',
                      'Transferencias' => 'transfer',
                      _ => 'all',
                    },
                  ),
                ),
              ),
            chip(
              category == 'all' ? 'Categoría' : category,
              category != 'all',
              () => pickValue(
                context,
                ['Todas las categorías', ...categories],
                '',
                (v) => change(
                  () => category = v == 'Todas las categorías' ? 'all' : v,
                ),
              ),
            ),
            chip(
              currency == 'all' ? 'Moneda' : currency,
              currency != 'all',
              () => pickValue(
                context,
                ['Todas las monedas', 'USD', 'VES', 'EUR', 'USDT'],
                '',
                (v) => change(
                  () => currency = v == 'Todas las monedas' ? 'all' : v,
                ),
              ),
            ),
            chip(
              dateLabel,
              start != null,
              () => pickValue(
                context,
                [
                  'Todas las fechas',
                  'Hoy',
                  'Últimos 7 días',
                  'Este mes',
                  'Personalizado',
                ],
                '',
                dates,
              ),
            ),
            if (query.text.isNotEmpty ||
                account != 'all' ||
                type != 'all' ||
                category != 'all' ||
                currency != 'all' ||
                start != null)
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(36, 36),
                onPressed: () {
                  debounce?.cancel();
                  change(() {
                    query.clear();
                    account = type = category = currency = 'all';
                    start = end = null;
                    dateLabel = 'Fechas';
                  });
                },
                child: const Text('Limpiar', style: TextStyle(fontSize: 13)),
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
