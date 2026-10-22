part of 'main.dart';

extension _MovementComposer on _MovementEditorState {
  void refreshComposerFocus() {
    if (mounted) _setViewState(() {});
  }

  void selectComposerAccount(String id) {
    _setViewState(() {
      accountId = id;
      resetDollarFee();
      keypadBuffer = null;
      if (targetId == id) targetId = firstAccountId(except: id);
      if (debtId.isNotEmpty) {
        applyDebtDefaults(debtId, overwriteAmount: !amountEdited);
      }
    });
  }

  void enterKey(String key) {
    final controller = receivedFocused && usesReceivedAmount
        ? receivedAmount
        : amount;
    var buffer =
        keypadBuffer ??
        (controller.text.isEmpty
            ? ''
            : parseAmount(controller.text)
                  .toStringAsFixed(2)
                  .replaceFirst(RegExp(r'\.?0+$'), ''));
    if (key == 'clear') {
      buffer = '';
    } else if (key == 'back') {
      if (buffer.isNotEmpty) buffer = buffer.substring(0, buffer.length - 1);
    } else if (key == ',') {
      if (!buffer.contains('.')) buffer = '${buffer.isEmpty ? '0' : buffer}.';
    } else {
      if (buffer == '0') buffer = '';
      final next = buffer + key;
      final parts = next.split('.');
      if (parts.first.length > 12 ||
          (parts.length > 1 && parts.last.length > 2))
        return;
      buffer = next;
    }
    _setViewState(() {
      keypadBuffer = buffer;
      controller.text = buffer.isEmpty
          ? ''
          : (double.tryParse(buffer) ?? 0).toStringAsFixed(2);
      if (controller == amount) amountEdited = true;
    });
  }

  Future<void> pasteComposerAmount() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || data?.text == null) return;
    final value = parseAmount(data!.text!);
    if (!value.isFinite || value <= 0 || value >= 1e12) return;
    _setViewState(() {
      (receivedFocused && usesReceivedAmount ? receivedAmount : amount).text =
          plain(value);
      keypadBuffer = null;
      if (!receivedFocused) amountEdited = true;
    });
  }

  Future<void> pickComposerTime() async {
    final previous = parseMovementDate(date);
    final time = await pickModernTime(
      context: context,
      theme: widget.app.theme,
      initial: previous,
    );
    if (!mounted || time == null) return;
    changeMovementDate(
      DateTime(
        previous.year,
        previous.month,
        previous.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Widget buildComposer(
    BuildContext context, {
    required Map<String, dynamic>? source,
    required Map<String, dynamic>? target,
    required List<Widget> details,
    required bool receivedExchange,
    required double enteredRate,
    required double targetAmount,
  }) {
    final app = widget.app, t = app.theme;
    final transfer = type == 'transfer';
    final currency = source?['currency']?.toString() ?? 'USD';
    final targetCurrency = target?['currency']?.toString() ?? currency;
    final fields = details.whereType<OptionField>().toList();
    final options = [
      ...fields.where((field) => field.label == 'Categoría'),
      ...fields.where((field) => field.label != 'Categoría'),
    ];
    final extra = details.where((child) => child is! OptionField).toList();
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final usableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.paddingOf(context).vertical;
    final compact = usableHeight < (transfer ? 780 : 720);
    final roomy =
        !compact && !transfer && (type == 'income' || usableHeight >= 780);
    final amountColor = type == 'income'
        ? t.income
        : type == 'expense'
        ? t.expense
        : t.accent;
    final parsed = parseMovementDate(date);
    final dateLabel = isSameDate(parsed, DateTime.now())
        ? 'Hoy'
        : formatDate(parsed);

    Widget descriptionInput({bool narrow = false}) => CupertinoTextField(
      controller: desc,
      focusNode: descriptionFocus,
      placeholder: narrow ? 'Nota' : 'Descripción',
      onChanged: inferCategory,
      padding: EdgeInsets.symmetric(
        horizontal: narrow ? 10 : 18,
        vertical: roomy ? 16 : 12,
      ),
      style: TextStyle(
        color: t.ink,
        fontSize: roomy ? 16 : 15,
        fontFamily: 'Manrope',
      ),
      placeholderStyle: TextStyle(
        color: t.muted,
        fontSize: roomy ? 16 : 15,
        fontFamily: 'Manrope',
      ),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(24),
      ),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => descriptionFocus.unfocus(),
    );

    Widget accountPill(
      Map<String, dynamic>? account, {
      bool destination = false,
    }) => Center(
      child: widget.lockAccount && !destination
          ? LockedAccountField(theme: t, label: 'Cuenta', account: account)
          : OptionField(
              key: ValueKey(
                destination ? 'composer-target' : 'composer-account',
              ),
              theme: t,
              icon: CupertinoIcons.creditcard,
              compact: true,
              roomy: roomy,
              logoProvider: account?['provider']?.toString(),
              label: destination
                  ? 'Cuenta destino'
                  : transfer
                  ? 'Cuenta origen'
                  : 'Cuenta',
              value: accountLabel(account),
              compactLabel: account == null
                  ? 'Selecciona una cuenta'
                  : accountLabel(account),
              compactSubtitle: account == null
                  ? null
                  : app.secureMoney(
                      numberValue(account['balance']),
                      account['currency'].toString(),
                    ),
              onTap: () => pickAccount(
                context,
                selected: destination ? targetId : accountId,
                except: destination ? accountId : '',
                onSelect: (id) {
                  if (destination) {
                    _setViewState(() {
                      targetId = id;
                      receivedFocused = false;
                      keypadBuffer = null;
                    });
                  } else {
                    selectComposerAccount(id);
                  }
                },
              ),
            ),
    );

    Widget moneyInput({bool received = false}) => ComposerAmount(
      key: ValueKey(received ? 'transfer-received-amount' : 'composer-amount'),
      theme: t,
      controller: received ? receivedAmount : amount,
      currency: received ? targetCurrency : currency,
      label: received
          ? (targetCurrency == 'USD'
                ? 'Monto que llegó en dólares'
                : 'Monto recibido en bolívares')
          : (currency == 'VES'
                ? 'Monto en bolívares'
                : currency == 'USD'
                ? 'Monto en dólares'
                : 'Monto en ${displayCurrency(currency)}'),
      placeholder: received ? 'Monto recibido' : 'Monto',
      active: !transfer || receivedFocused == received,
      compact: compact,
      roomy: roomy,
      onTap: () {
        descriptionFocus.unfocus();
        _setViewState(() {
          receivedFocused = received;
          keypadBuffer = null;
        });
      },
      onChanged: (_) => _setViewState(() {
        keypadBuffer = null;
        if (!received) amountEdited = true;
      }),
    );

    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              key: const ValueKey('composer-header'),
              padding: EdgeInsets.fromLTRB(12, 12, 16, compact ? 4 : 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    height: 44,
                    child: MediaQuery.withNoTextScaling(
                      child: CupertinoNavigationBarBackButton(
                        color: t.ink,
                        previousPageTitle: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.movement != null
                          ? 'Editar movimiento'
                          : widget.partialDebtPayment
                          ? 'Registrar abono'
                          : transfer
                          ? 'Transferencia'
                          : type == 'income'
                          ? 'Nuevo ingreso'
                          : 'Nuevo gasto',
                      maxLines: 2,
                      style: TextStyle(
                        color: t.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 64,
                    height: 44,
                    key: const ValueKey('movement-editor-type'),
                    child: ComposerModeButton(
                      theme: t,
                      color: amountColor,
                      icon: transfer
                          ? CupertinoIcons.arrow_right_arrow_left
                          : type == 'income'
                          ? CupertinoIcons.arrow_up
                          : CupertinoIcons.arrow_down,
                      label: transfer
                          ? 'Transferir'
                          : type == 'income'
                          ? 'Ingreso'
                          : 'Gasto',
                      onTap: () => showModernActionSheet(
                        context,
                        title: 'Tipo de movimiento',
                        actions: [
                          for (final mode in const [
                            ('expense', 'Gasto', CupertinoIcons.arrow_down),
                            ('income', 'Ingreso', CupertinoIcons.arrow_up),
                            (
                              'transfer',
                              'Transferir',
                              CupertinoIcons.arrow_right_arrow_left,
                            ),
                          ])
                            ModernSheetAction(
                              title: mode.$2,
                              icon: mode.$3,
                              selected: type == mode.$1,
                              onPressed: () {
                                changeType(mode.$1);
                                keypadBuffer = null;
                                receivedFocused = false;
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ComposerBody(
                compact: compact,
                footer: !keyboard && !descriptionFocus.hasFocus
                    ? ComposerKeypad(
                        theme: t,
                        compact: compact,
                        onKey: enterKey,
                        onPaste: pasteComposerAmount,
                        onSave: _saving ? null : save,
                      )
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: PrimaryActionButton(
                          key: const ValueKey('movement-editor-save'),
                          theme: t,
                          label: _saving
                              ? 'Comprobando...'
                              : 'Guardar movimiento',
                          onPressed: _saving ? () {} : save,
                        ),
                      ),
                keypadVisible: !keyboard && !descriptionFocus.hasFocus,
                form: SingleChildScrollView(
                  key: const ValueKey('movement-editor-fields'),
                  primary: false,
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    16,
                    compact ? 0 : 10,
                    16,
                    compact ? 0 : 4,
                  ),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (transfer) ...[accountPill(source)],
                      moneyInput(),
                      if (!transfer) ...[
                        accountPill(source),
                        SizedBox(
                          height: compact
                              ? 4
                              : roomy
                              ? 16
                              : 12,
                        ),
                      ],
                      if (transfer) ...[
                        Row(
                          children: [
                            Expanded(
                              child: accountPill(target, destination: true),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 0,
                              ),
                              child: CircleTool(
                                theme: t,
                                icon: CupertinoIcons.arrow_up_arrow_down,
                                label: 'Intercambiar cuentas',
                                onTap: widget.lockAccount
                                    ? null
                                    : () => _setViewState(() {
                                        final old = accountId;
                                        accountId = targetId;
                                        targetId = old;
                                        if (receivedExchange) {
                                          final sent = amount.text;
                                          amount.text = receivedAmount.text;
                                          receivedAmount.text = sent;
                                        }
                                        resetDollarFee();
                                        keypadBuffer = null;
                                        receivedFocused = false;
                                      }),
                              ),
                            ),
                          ],
                        ),
                        if (receivedExchange)
                          moneyInput(received: true)
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              children: [
                                Text(
                                  'Recibiste',
                                  key: const ValueKey(
                                    'transfer-received-label',
                                  ),
                                  style: TextStyle(
                                    color: t.muted,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    money(targetAmount, targetCurrency),
                                    key: const ValueKey(
                                      'transfer-received-value',
                                    ),
                                    style: TextStyle(
                                      color: t.ink,
                                      fontSize: compact ? 40 : 48,
                                      height: 1.1,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (receivedExchange)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: SizedBox(
                              height: 16,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  enteredRate > 0
                                      ? 'Tasa: Bs. ${formatNumber(enteredRate)} por dólar'
                                      : 'Tasa: --',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: t.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                      if (!transfer || !compact) descriptionInput(),
                      SizedBox(
                        height: compact
                            ? 2
                            : roomy
                            ? 16
                            : 10,
                      ),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final controls = <Widget>[
                            if (compact && transfer)
                              material.Tooltip(
                                message: 'Descripción',
                                child: descriptionInput(narrow: true),
                              ),
                            OptionField(
                              key: const ValueKey('composer-date'),
                              theme: t,
                              dense: true,
                              roomy: roomy,
                              label: 'Fecha',
                              value: date,
                              compactLabel: dateLabel,
                              icon: CupertinoIcons.calendar,
                              onTap: () => pickDateTime(context),
                            ),
                            ComposerOptionButton(
                              key: const ValueKey('composer-time'),
                              theme: t,
                              icon: CupertinoIcons.clock,
                              roomy: roomy,
                              label: timeOnlyLabel(parsed),
                              onTap: pickComposerTime,
                            ),
                            for (final field in options)
                              OptionField(
                                key: field.key,
                                theme: t,
                                dense: true,
                                roomy: roomy,
                                icon: field.icon,
                                label: field.label,
                                value: field.value,
                                compactLabel: switch (field.label) {
                                  'Categoría' => category,
                                  'Forma de pago' => 'Forma de pago',
                                  'Deuda a pagar' ||
                                  'Cobro vinculado' => 'Deuda',
                                  _ => field.label,
                                },
                                onTap: field.onTap,
                              ),
                          ];
                          final columns = compact && controls.length > 6
                              ? 4
                              : math.min(3, controls.length);
                          return Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final control in controls)
                                SizedBox(
                                  width:
                                      (constraints.maxWidth -
                                          6 * (columns - 1)) /
                                      columns,
                                  child: control,
                                ),
                            ],
                          );
                        },
                      ),
                      ComposerFacts(
                        theme: t,
                        compact: compact,
                        facts: extra.whereType<DebtDetailRow>().toList(),
                      ),
                      ...extra.where((child) => child is! DebtDetailRow),
                      if (widget.movement != null)
                        RField(
                          theme: t,
                          controller: operationReference,
                          placeholder: 'Referencia (opcional)',
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(64),
                          ],
                        ),
                    ],
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

class ComposerBody extends StatelessWidget {
  const ComposerBody({
    super.key,
    required this.form,
    required this.footer,
    required this.compact,
    required this.keypadVisible,
  });

  final Widget form, footer;
  final bool compact, keypadVisible;

  @override
  Widget build(BuildContext context) => CustomMultiChildLayout(
    delegate: _ComposerBodyLayout(
      compact: compact,
      keypadVisible: keypadVisible,
    ),
    children: [
      LayoutId(id: 'form', child: form),
      LayoutId(id: 'footer', child: footer),
    ],
  );
}

class _ComposerBodyLayout extends MultiChildLayoutDelegate {
  _ComposerBodyLayout({required this.compact, required this.keypadVisible});
  final bool compact, keypadVisible;

  @override
  void performLayout(Size size) {
    final spacing = compact ? 0.0 : 8.0;
    final minimumFooter = keypadVisible ? (compact ? 194.0 : 218.0) : 60.0;
    // Measure the real form first: extra fees and accessibility text take
    // priority over a taller keypad, without hiding fields or actions.
    final form = layoutChild(
      'form',
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: math.max(0, size.height - minimumFooter - spacing),
      ),
    );
    final available = math.max(0.0, size.height - form.height - spacing);
    final footer = layoutChild(
      'footer',
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: math.min(
          available,
          keypadVisible ? (compact ? 274.0 : 330.0) : 60.0,
        ),
      ),
    );
    final spare = math.max(
      0.0,
      size.height - form.height - footer.height - spacing,
    );
    positionChild('form', Offset(0, math.min(48, spare * .4)));
    positionChild('footer', Offset(0, size.height - footer.height));
  }

  @override
  bool shouldRelayout(_ComposerBodyLayout oldDelegate) =>
      compact != oldDelegate.compact ||
      keypadVisible != oldDelegate.keypadVisible;
}

class ComposerModeButton extends StatelessWidget {
  const ComposerModeButton({
    super.key,
    required this.theme,
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final RTheme theme;
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => material.Tooltip(
    message: 'Tipo de movimiento: $label',
    child: Semantics(
      label: 'Tipo de movimiento: $label',
      button: true,
      child: PressFeedback(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: theme.card,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                child: Icon(icon, key: ValueKey(label), size: 23, color: color),
              ),
              const SizedBox(width: 6),
              Icon(CupertinoIcons.chevron_down, size: 11, color: theme.muted),
            ],
          ),
        ),
      ),
    ),
  );
}

class ComposerOptionButton extends StatelessWidget {
  const ComposerOptionButton({
    super.key,
    required this.theme,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tooltip,
    this.roomy = false,
  });
  final RTheme theme;
  final IconData icon;
  final String label;
  final String? tooltip;
  final bool roomy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => material.Tooltip(
    message: tooltip ?? label,
    child: Semantics(
      button: true,
      label: tooltip ?? label,
      child: PressFeedback(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: roomy ? 56 : 44),
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: roomy ? 7 : 4),
          decoration: BoxDecoration(
            color: theme.card,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: theme.accent, size: roomy ? 20 : 16),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.ink,
                  fontSize: roomy ? 13 : 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ComposerFacts extends StatelessWidget {
  const ComposerFacts({
    super.key,
    required this.theme,
    required this.facts,
    this.compact = false,
  });
  final RTheme theme;
  final List<DebtDetailRow> facts;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('composer-facts'),
    padding: EdgeInsets.only(top: compact ? 2 : 6),
    child: Column(
      children: [
        for (final fact in facts)
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: compact ? 16 : 20),
            child: DebtDetailRow(
              key: fact.key,
              theme: theme,
              label: fact.label,
              value: fact.value,
              valueColor: fact.valueColor,
              bottom: false,
              fitValue: true,
              compact: compact,
            ),
          ),
      ],
    ),
  );
}

class ComposerChip extends StatelessWidget {
  const ComposerChip({
    super.key,
    required this.theme,
    required this.icon,
    required this.label,
    this.onTap,
    this.logo,
    this.subtitle,
    this.color,
    this.tooltip,
    this.iconOnly = false,
    this.showChevron = false,
    this.roomy = false,
  });
  final RTheme theme;
  final IconData icon;
  final String label;
  final String? logo, subtitle, tooltip;
  final Color? color;
  final VoidCallback? onTap;
  final bool iconOnly, showChevron;
  final bool roomy;
  @override
  Widget build(BuildContext context) => material.Tooltip(
    message: tooltip ?? label,
    child: PressFeedback(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(
          minHeight: iconOnly
              ? 40
              : roomy
              ? 56
              : 44,
          maxWidth: roomy ? 320 : 280,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: iconOnly ? 10 : 12,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: theme.card,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: theme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (logo != null)
              LogoBadge(provider: logo!, theme: theme, size: roomy ? 38 : 30)
            else
              Icon(icon, size: 19, color: color ?? theme.accent),
            if (!iconOnly) const SizedBox(width: 7),
            if (!iconOnly)
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.ink,
                        fontSize: roomy ? 15 : 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: theme.muted,
                          fontSize: roomy ? 12 : 11,
                        ),
                      ),
                  ],
                ),
              ),
            if (showChevron) ...[
              const SizedBox(width: 4),
              Icon(CupertinoIcons.chevron_down, size: 10, color: theme.muted),
            ],
          ],
        ),
      ),
    ),
  );
}

class ComposerAmount extends StatelessWidget {
  const ComposerAmount({
    super.key,
    required this.theme,
    required this.controller,
    required this.currency,
    required this.label,
    required this.placeholder,
    required this.active,
    required this.onTap,
    required this.onChanged,
    this.compact = false,
    this.roomy = false,
  });
  final RTheme theme;
  final MoneyEditingController controller;
  final String currency, label, placeholder;
  final bool active;
  final bool compact;
  final bool roomy;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: compact ? 2 : 8),
    child: Column(
      children: [
        Text(
          label,
          key: placeholder == 'Monto'
              ? const ValueKey('movement-amount-currency')
              : null,
          style: TextStyle(color: theme.muted, fontSize: roomy ? 13 : 11),
        ),
        const SizedBox(height: 2),
        AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: compact ? 0 : 4,
          ),
          decoration: BoxDecoration(
            color: active ? theme.accent.withValues(alpha: .06) : theme.bg,
            borderRadius: BorderRadius.circular(28),
          ),
          child: SizedBox(
            height: compact
                ? 44
                : roomy
                ? 88
                : 64,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final prefix = currency == 'VES'
                    ? 'Bs.'
                    : currency == 'EUR'
                    ? '€'
                    : '\$';
                final base = TextStyle(
                  color: theme.ink,
                  fontSize: compact ? 40 : 48,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Manrope',
                );
                final painter = TextPainter(
                  text: TextSpan(
                    text: controller.text.isEmpty ? '0,00' : controller.text,
                    style: base,
                  ),
                  textDirection: TextDirection.ltr,
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout();
                final prefixBase = base.copyWith(
                  color: theme.muted,
                  fontSize: compact ? 30 : 36,
                );
                final prefixPainter = TextPainter(
                  text: TextSpan(text: prefix, style: prefixBase),
                  textDirection: TextDirection.ltr,
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout();
                final factor = math.min(
                  1.0,
                  (constraints.maxWidth - 12) /
                      math.max(1, painter.width + prefixPainter.width + 6),
                );
                final style = base.copyWith(fontSize: base.fontSize! * factor);
                final inputWidth = painter.width * factor + 6;
                painter.dispose();
                prefixPainter.dispose();
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      prefix,
                      key: ValueKey('amount-prefix-$placeholder'),
                      style: prefixBase.copyWith(
                        fontSize: prefixBase.fontSize! * factor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: inputWidth,
                      height: constraints.maxHeight,
                      child: CupertinoTextField(
                        key: ValueKey('amount-input-$placeholder'),
                        controller: controller,
                        placeholder: '0,00',
                        keyboardType: TextInputType.none,
                        showCursor: active,
                        cursorHeight: math.min(
                          constraints.maxHeight,
                          style.fontSize! * 1.05,
                        ),
                        inputFormatters: [controller.formatter],
                        onTap: onTap,
                        onChanged: onChanged,
                        padding: EdgeInsets.zero,
                        scrollPadding: EdgeInsets.zero,
                        textAlign: TextAlign.left,
                        style: style,
                        placeholderStyle: style.copyWith(color: theme.muted),
                        decoration: const BoxDecoration(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    ),
  );
}

class ComposerKeypad extends StatelessWidget {
  const ComposerKeypad({
    super.key,
    required this.theme,
    required this.onKey,
    required this.onPaste,
    this.onSave,
    this.compact = false,
  });
  final RTheme theme;
  final ValueChanged<String> onKey;
  final VoidCallback onPaste;
  final VoidCallback? onSave;
  final bool compact;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final rowPadding = compact ? 2.0 : 8.0;
      final keyHeight = constraints.hasBoundedHeight
          ? ((constraints.maxHeight - 10) / 4 - rowPadding).clamp(44.0, 72.0)
          : 44.0;
      Widget key(
        String value, {
        IconData? icon,
        String? label,
        Color? color,
        VoidCallback? action,
        Key? widgetKey,
      }) => Expanded(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 4,
            vertical: compact ? 1 : 4,
          ),
          child: material.Tooltip(
            message: label ?? value,
            child: PressFeedback(
              key: widgetKey ?? ValueKey('keypad-$value'),
              onTap: action ?? () => onKey(value),
              child: Container(
                height: keyHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color ?? theme.card,
                  borderRadius: BorderRadius.circular(keyHeight / 2),
                ),
                child: icon != null
                    ? Icon(
                        icon,
                        color: color == theme.accent
                            ? foregroundOn(theme.accent)
                            : theme.ink,
                        size: keyHeight >= 56 ? 28 : 24,
                      )
                    : Text(
                        value,
                        style: TextStyle(
                          color: theme.ink,
                          fontSize: keyHeight >= 56 ? 27 : 23,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ),
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                key('1'),
                key('2'),
                key('3'),
                key(
                  'back',
                  icon: CupertinoIcons.delete_left,
                  label: 'Borrar dígito',
                ),
              ],
            ),
            Row(
              children: [
                key('4'),
                key('5'),
                key('6'),
                key(
                  'save',
                  icon: onSave == null
                      ? CupertinoIcons.clock
                      : CupertinoIcons.check_mark,
                  label: 'Guardar movimiento',
                  color: theme.accent,
                  action: onSave ?? () {},
                  widgetKey: const ValueKey('movement-editor-save'),
                ),
              ],
            ),
            Row(
              children: [
                key('7'),
                key('8'),
                key('9'),
                key(
                  'paste',
                  icon: CupertinoIcons.doc_on_clipboard,
                  label: 'Pegar monto',
                  action: onPaste,
                ),
              ],
            ),
            Row(
              children: [
                key(','),
                key('0'),
                key('00'),
                key('clear', icon: CupertinoIcons.clear, label: 'Borrar todo'),
              ],
            ),
          ],
        ),
      );
    },
  );
}
