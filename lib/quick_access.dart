part of 'main.dart';

@pragma('vm:entry-point')
Future<void> quickMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final action = await _storeChannel.invokeMethod<String>('quickAction');
  runApp(RialBootstrap(quickAction: action ?? 'calculator'));
}

Future<void> closeQuickAccess() async {
  await _storeChannel.invokeMethod<void>('closeQuickAccess');
}

class QuickAccessFrame extends StatelessWidget {
  const QuickAccessFrame({
    super.key,
    required this.child,
    this.maxHeight = 600,
  });
  final Widget child;
  final double maxHeight;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
          child: Container(
            foregroundDecoration: BoxDecoration(
              border: Border.all(
                color: CupertinoColors.separator.resolveFrom(context),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              key: const ValueKey('quick-access-window'),
              borderRadius: BorderRadius.circular(8),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

extension _QuickAccessApp on _RialAppState {
  bool get isQuickAccess => widget.quickAction != null;

  Future<void> reloadExternalChanges() async {
    if (_reloadingExternal) return;
    _reloadingExternal = true;
    try {
      await NativeStateStore.flush();
      final changed = await _storeChannel.invokeMethod<bool>('stateChanged');
      if (changed == true) {
        final fresh = await NativeStateStore.load();
        if (!mounted) return;
        _setViewState(() => state = fresh);
        _undoHistory.clear();
        _showUndo = false;
        revision.value++;
      }
    } catch (_) {
      // A pending failed write stays visible; never replace an unsaved draft.
    } finally {
      _reloadingExternal = false;
    }
  }

  Future<void> reloadExternalChangesAfterConflict() async {
    try {
      final fresh = await NativeStateStore.load();
      if (!mounted) return;
      _closeTransientRoutes();
      _setViewState(() {
        state = fresh;
        locked = stateHasSecurity(fresh);
        _showUndo = false;
      });
      _undoHistory.clear();
      revision.value++;
    } catch (_) {
      NativeStateStore.persistenceError.value = 'No se pudo volver a cargar.';
    }
  }

  Future<void> commitQuickMovement(Map<String, dynamic> movement) async {
    final before = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
    try {
      // Same validations and ledger mutation as the full editor; persist once.
      _deferPersistence = true;
      try {
        saveMovement(movement);
      } finally {
        _deferPersistence = false;
      }
      await NativeStateStore.save(state);
      await NativeStateStore.flush();
    } catch (_) {
      final conflict = NativeStateStore.persistenceConflict;
      Map<String, dynamic> restored = before;
      try {
        restored = await NativeStateStore.load();
      } catch (_) {}
      if (mounted) {
        _setViewState(() => state = restored);
        _undoHistory.clear();
        _showUndo = false;
        revision.value++;
      }
      final savedId = movement['id']?.toString();
      if (savedId != null && movementById(savedId) != null) {
        await closeQuickAccess();
        return;
      }
      if (conflict) {
        throw const FormatException(
          'Las cuentas cambiaron en otra ventana. Revisa la cuenta y vuelve a guardar.',
        );
      }
      rethrow;
    }
    await closeQuickAccess();
  }

  Widget quickAccessHome() {
    if (state['onboardingComplete'] != true || securitySetupRequired) {
      return QuickAccessUnavailable(
        theme: theme,
        message: 'Completa la configuraci\u00f3n de Sin Rial primero.',
      );
    }
    if (locked)
      return CupertinoPageScaffold(
        backgroundColor: theme.bg,
        child: const SizedBox.expand(),
      );
    if (widget.quickAction == 'calculator') {
      return CalculatorPage(app: this, onClose: closeQuickAccess);
    }
    if (usableAccounts().isEmpty) {
      return QuickAccessUnavailable(
        theme: theme,
        message: 'Agrega una cuenta antes de registrar movimientos.',
      );
    }
    return MovementEditor(
      app: this,
      quick: true,
      defaultType: widget.quickAction == 'income' ? 'income' : 'expense',
      onSave: commitQuickMovement,
    );
  }
}

class QuickAccessUnavailable extends StatelessWidget {
  const QuickAccessUnavailable({
    super.key,
    required this.theme,
    required this.message,
  });
  final RTheme theme;
  final String message;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: theme.bg,
    navigationBar: CupertinoNavigationBar(
      middle: const Text('Sin Rial'),
      trailing: CircleTool(
        theme: theme,
        icon: CupertinoIcons.xmark,
        label: 'Cerrar',
        onTap: closeQuickAccess,
      ),
    ),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.ink),
            ),
            const SizedBox(height: 24),
            PrimaryActionButton(
              theme: theme,
              label: 'Abrir Sin Rial',
              onPressed: () => _storeChannel.invokeMethod<void>('openFullApp'),
            ),
          ],
        ),
      ),
    ),
  );
}

class StateConflictPage extends StatelessWidget {
  const StateConflictPage({super.key, required this.onReload});
  final VoidCallback onReload;
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.arrow_clockwise, size: 32),
            const SizedBox(height: 16),
            const Text(
              'Hay cambios de otra ventana',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Los \u00faltimos cambios de esta ventana no se guardaron. Recarga las cuentas antes de repetirlos.',
              textAlign: TextAlign.center,
            ),
            CupertinoButton(
              onPressed: onReload,
              child: const Text('Recargar datos'),
            ),
          ],
        ),
      ),
    ),
  );
}

extension _QuickMovementForm on _MovementEditorState {
  Widget buildQuickMovement(
    Map<String, dynamic>? source,
    double appliedFee,
    double total,
  ) {
    final t = widget.app.theme;
    final currency = source?['currency']?.toString() ?? 'USD';
    final hasPaymentMethod =
        type == 'expense' &&
        !isBankCommissionCategory(category) &&
        isNationalBankAccount(source) &&
        currency == 'VES';
    Widget choice(
      String label,
      String value,
      IconData icon,
      VoidCallback onTap,
    ) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: t.card,
        borderRadius: BorderRadius.circular(8),
        onPressed: onTap,
        child: Row(
          children: [
            Icon(icon, size: 21, color: t.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: t.muted, fontSize: 11)),
                  Text(
                    value,
                    style: TextStyle(color: t.ink, fontSize: 14),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(CupertinoIcons.chevron_down, size: 14, color: t.muted),
          ],
        ),
      ),
    );

    return PopScope(
      canPop: !_saving,
      child: CupertinoPageScaffold(
        backgroundColor: t.bg,
        navigationBar: CupertinoNavigationBar(
          transitionBetweenRoutes: false,
          backgroundColor: t.bg,
          border: null,
          middle: Text(type == 'income' ? 'Nuevo ingreso' : 'Nuevo gasto'),
          trailing: CircleTool(
            theme: t,
            icon: CupertinoIcons.xmark,
            label: 'Cancelar',
            onTap: _saving ? null : closeQuickAccess,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: IgnorePointer(
                  ignoring: _saving,
                  child: ListView(
                    key: const ValueKey('quick-movement-fields'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    children: [
                      Text(
                        currency,
                        style: TextStyle(color: t.muted, fontSize: 12),
                      ),
                      CupertinoTextField(
                        key: const ValueKey('quick-amount'),
                        controller: amount,
                        placeholder: '0,00',
                        placeholderStyle: TextStyle(
                          color: t.muted,
                          fontFamily: 'Manrope',
                          fontSize: 30,
                          fontWeight: FontWeight.w600,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: null,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        style: TextStyle(
                          color: t.ink,
                          fontFamily: 'Manrope',
                          fontSize: 30,
                          fontWeight: FontWeight.w600,
                        ),
                        onChanged: (_) => _setViewState(() {}),
                      ),
                      CupertinoTextField(
                        key: const ValueKey('quick-description'),
                        controller: desc,
                        placeholder: 'Descripci\u00f3n',
                        placeholderStyle: TextStyle(
                          color: t.muted,
                          fontFamily: 'Manrope',
                          fontSize: 14,
                        ),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: t.card,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        style: TextStyle(
                          color: t.ink,
                          fontFamily: 'Manrope',
                          fontSize: 14,
                        ),
                        onChanged: inferCategory,
                      ),
                      choice(
                        'Cuenta',
                        accountLabel(source),
                        CupertinoIcons.creditcard,
                        () => pickAccount(
                          context,
                          selected: accountId,
                          onSelect: (id) => _setViewState(() => accountId = id),
                        ),
                      ),
                      if (type == 'expense')
                        choice(
                          'Categor\u00eda',
                          category,
                          categoryIcon(category),
                          () => pickCategory(
                            context,
                            category,
                            (value) => _setViewState(() {
                              category = value;
                              categoryTouched = true;
                            }),
                          ),
                        ),
                      if (hasPaymentMethod)
                        choice(
                          'Forma de pago',
                          paymentMethodLabel(paymentMethod),
                          CupertinoIcons.money_dollar_circle,
                          () => pickValue(
                            context,
                            const [
                              'Pago m\u00f3vil',
                              'Pago m\u00f3vil C2P',
                              'Transferencia bancaria',
                              'Tarjeta',
                            ],
                            paymentMethodLabel(paymentMethod),
                            (value) => _setViewState(() {
                              paymentMethod = paymentMethodFromLabel(value);
                            }),
                          ),
                        ),
                      if (hasPaymentMethod && paymentMethod == 'bank_transfer')
                        choice(
                          'Transferencia bancaria',
                          bankTransferScopeLabel(bankTransferScope),
                          CupertinoIcons.building_2_fill,
                          () => pickValue(
                            context,
                            const ['Otro banco', 'Mismo banco'],
                            bankTransferScopeLabel(bankTransferScope),
                            (value) => _setViewState(
                              () => bankTransferScope =
                                  bankTransferScopeFromLabel(value),
                            ),
                          ),
                        ),
                      if (appliedFee > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'Comisi\u00f3n: ${money(appliedFee, currency)}',
                            style: TextStyle(color: t.muted, fontSize: 12),
                          ),
                        ),
                      if (parseAmount(amount.text) > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            '${type == 'income' ? 'Ingreso neto' : 'Total'}: ${money(total, currency)}',
                            style: TextStyle(
                              color: t.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    key: const ValueKey('quick-save'),
                    color: t.accent,
                    borderRadius: BorderRadius.circular(8),
                    onPressed: _saving ? null : save,
                    child: Text(
                      _saving ? 'Guardando...' : 'Guardar',
                      style: TextStyle(
                        color: t.onAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
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
