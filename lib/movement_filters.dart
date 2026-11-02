part of 'main.dart';

class MovementFilterButton extends StatelessWidget {
  const MovementFilterButton({
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
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, maxWidth: 240),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: selected ? theme.accent.withValues(alpha: .16) : theme.card,
        borderRadius: BorderRadius.circular(24),
        onPressed: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: selected ? theme.accent : theme.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.chevron_down,
              size: 14,
              color: selected ? theme.accent : theme.muted,
            ),
          ],
        ),
      ),
    ),
  );
}

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
  int _categoryRevision = -1;
  List<String> _categories = const [];
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
    if (_categoryRevision != widget.app.revision.value) {
      _categoryRevision = widget.app.revision.value;
      _categories =
          widget.app
              .maps('movements')
              .map((m) => m['category']?.toString() ?? '')
              .where((c) => c.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
    }
    final categories = _categories;
    Widget chip(String label, bool active, VoidCallback action) =>
        MovementFilterButton(
          theme: t,
          label: label,
          selected: active,
          onTap: action,
        );
    final hasFilters =
        query.text.isNotEmpty ||
        account != 'all' ||
        type != 'all' ||
        category != 'all' ||
        currency != 'all' ||
        start != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: CupertinoSearchTextField(
                controller: query,
                placeholder: 'Buscar movimientos',
                style: TextStyle(
                  color: t.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                placeholderStyle: TextStyle(
                  color: t.muted,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 18,
                ),
                prefixInsets: const EdgeInsetsDirectional.only(start: 14),
                suffixInsets: const EdgeInsetsDirectional.only(end: 14),
                itemSize: 22,
                itemColor: t.muted,
                decoration: BoxDecoration(
                  color: t.field,
                  borderRadius: BorderRadius.circular(24),
                ),
                onChanged: (_) {
                  debounce?.cancel();
                  setState(() {});
                  debounce = Timer(const Duration(milliseconds: 180), emit);
                },
              ),
            ),
            if (hasFilters)
              CupertinoButton(
                padding: const EdgeInsets.only(left: 10),
                onPressed: () {
                  debounce?.cancel();
                  change(() {
                    query.clear();
                    account = type = category = currency = 'all';
                    start = end = null;
                    dateLabel = 'Fechas';
                  });
                },
                child: Semantics(
                  label: 'Limpiar filtros',
                  child: Icon(
                    CupertinoIcons.clear_circled,
                    color: t.accent,
                    size: 26,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: 8,
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
                      selected: account == 'all',
                      onPressed: () => change(() => account = 'all'),
                    ),
                    ...accounts.map(
                      (a) => ModernSheetAction(
                        icon: CupertinoIcons.creditcard,
                        logoProvider: a['provider']?.toString(),
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
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
