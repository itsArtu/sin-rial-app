part of 'main.dart';

String movementColorKey(Object? value) {
  final key = value?.toString();
  return themeColorOptions.any((option) => option.key == key)
      ? key!
      : 'default';
}

class _MovementColorPreferences extends StatelessWidget {
  const _MovementColorPreferences({required this.app, required this.onChanged});
  final _RialAppState app;
  final VoidCallback onChanged;

  Future<void> _choose(BuildContext context, bool income) async {
    final key = income ? 'incomeColor' : 'expenseColor';
    final result = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cancelar',
      barrierColor: CupertinoColors.black.withValues(alpha: .4),
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      transitionBuilder: softDialogTransition,
      pageBuilder: (_, _, _) => MovementColorPicker(
        theme: app.theme,
        income: income,
        value: movementColorKey(app.state[key]),
      ),
    );
    if (result == null || !context.mounted || !app.mounted) return;
    app.mutate(() => app.state[key] = movementColorKey(result));
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    return Column(
      children: [
        for (final income in [true, false])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CupertinoButton(
              key: ValueKey(income ? 'income-color' : 'expense-color'),
              padding: const EdgeInsets.symmetric(vertical: 14),
              onPressed: () => _choose(context, income),
              child: Row(
                children: [
                  Icon(
                    income
                        ? CupertinoIcons.arrow_down_left
                        : CupertinoIcons.arrow_up_right,
                    color: income ? t.income : t.expense,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      income ? 'Ingresos' : 'Gastos',
                      style: TextStyle(color: t.ink, fontSize: 16),
                    ),
                  ),
                  Text(
                    income ? '+100,00' : '-100,00',
                    style: TextStyle(
                      color: income ? t.income : t.expense,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(CupertinoIcons.chevron_right, color: t.muted, size: 16),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class MovementColorPicker extends StatelessWidget {
  const MovementColorPicker({
    super.key,
    required this.theme,
    required this.income,
    required this.value,
  });
  final RTheme theme;
  final bool income;
  final String value;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 640),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.card,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    income
                        ? CupertinoIcons.arrow_down_left
                        : CupertinoIcons.arrow_up_right,
                    color: income ? theme.income : theme.expense,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      income ? 'Color de ingresos' : 'Color de gastos',
                      style: TextStyle(
                        color: theme.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  material.Tooltip(
                    message: 'Cerrar',
                    child: CupertinoButton(
                      padding: const EdgeInsets.all(8),
                      onPressed: () => Navigator.pop(context),
                      child: Icon(
                        CupertinoIcons.xmark,
                        color: theme.muted,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  key: const ValueKey('movement-color-options'),
                  child: Column(
                    children: [
                      for (final option in themeColorOptions)
                        Semantics(
                          selected: option.key == value,
                          child: CupertinoButton(
                            key: ValueKey('movement-swatch-${option.key}'),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            onPressed: () => Navigator.pop(context, option.key),
                            child: Row(
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: option.colorFor(theme.dark),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    option.label,
                                    style: TextStyle(
                                      color: theme.ink,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      income ? '+100,00' : '-100,00',
                                      style: TextStyle(
                                        color: option.colorFor(theme.dark),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 20,
                                  child: option.key == value
                                      ? Icon(
                                          CupertinoIcons.check_mark,
                                          size: 18,
                                          color: option.colorFor(theme.dark),
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(height: 1, color: theme.border),
              CupertinoButton(
                key: const ValueKey('movement-color-default'),
                onPressed: () => Navigator.pop(context, 'default'),
                child: Text(
                  'Restablecer color',
                  style: TextStyle(color: theme.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
