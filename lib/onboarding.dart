part of 'main.dart';

class SinRialLogo extends StatelessWidget {
  const SinRialLogo({
    super.key,
    required this.theme,
    this.full = true,
    this.height = 64,
    this.color,
  });
  final RTheme theme;
  final bool full;
  final double height;
  final Color? color;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Sin Rial',
    image: true,
    child: Image.asset(
      'assets/logos/sinrial_${full ? 'full' : 'mark'}.png',
      height: height,
      cacheHeight: (height * MediaQuery.devicePixelRatioOf(context)).ceil(),
      fit: BoxFit.contain,
      color: color ?? theme.ink,
      colorBlendMode: BlendMode.srcIn,
      excludeFromSemantics: true,
    ),
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
  final surname = TextEditingController();
  DateTime? birthDate;
  bool usePin = true;
  final pin = TextEditingController();
  final pinConfirm = TextEditingController();
  final scroll = ScrollController();
  int step = 0;
  bool biometricsAvailable = false, useBiometrics = false, saving = false;
  bool obscurePin = true;
  static const titles = [
    '¿Cómo te llamas?',
    'Tu apariencia',
    'Tu seguridad',
    'Todo listo',
  ];

  @override
  void initState() {
    super.initState();
    unawaited(loadBiometrics());
  }

  Future<void> loadBiometrics() async {
    final available = await widget.app.canUseBiometrics();
    if (mounted)
      setState(() {
        biometricsAvailable = available;
        useBiometrics = available;
      });
  }

  @override
  void dispose() {
    name.dispose();
    surname.dispose();
    pin.dispose();
    pinConfirm.dispose();
    scroll.dispose();
    super.dispose();
  }

  void go(int next) {
    if (saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => step = next);
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  Future<void> advance() async {
    if (saving) return;
    if (step == 0 && name.text.trim().isEmpty) {
      showModernNotice(
        context,
        title: 'Tu nombre',
        message: 'Escribe tu nombre para continuar.',
      );
      return;
    }
    if (step == 2 && usePin) {
      if (!validatePin(context, pin.text, pinConfirm.text)) return;
    }
    go(step + 1);
  }

  Future<void> finish(bool addAccount) async {
    if (saving) return;
    setState(() => saving = true);
    final app = widget.app;
    final success = usePin
        ? await app.configureSecurity(
            pin: pin.text,
            useBiometrics: biometricsAvailable && useBiometrics,
          )
        : await app.disableSecurity();
    if (!mounted) return;
    setState(() => saving = false);
    if (!success) {
      showModernNotice(context, title: 'Seguridad', message: app.pinError);
      return;
    }
    app.mutate(() {
      app.state['userLastName'] = surname.text.trim();
      app.state['userBirthDate'] = birthDate == null ? '' : isoDate(birthDate!);
    });
    app.completeOnboarding(name.text, addAccount: addAccount);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = app.theme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && step > 0) go(step - 1);
      },
      child: CupertinoPageScaffold(
        backgroundColor: t.bg,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 22, 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: step == 0
                              ? null
                              : CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: saving ? null : () => go(step - 1),
                                  child: Icon(
                                    CupertinoIcons.arrow_left,
                                    color: t.ink,
                                    semanticLabel: 'Anterior',
                                  ),
                                ),
                        ),
                        Expanded(
                          child: Semantics(
                            label: 'Paso ${step + 1} de 4',
                            child: Row(
                              children: [
                                for (var index = 0; index < 4; index++)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: index <= step
                                              ? t.accent
                                              : t.border,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SinRialLogo(theme: t, height: 62),
                        ),
                        const SizedBox(height: 30),
                        Text(
                          titles[step],
                          style: TextStyle(
                            color: t.ink,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 24),
                        AnimatedSwitcher(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          child: Column(
                            key: ValueKey('setup-$step'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: content(context, t),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                    child: Column(
                      children: [
                        if (step < 3)
                          IgnorePointer(
                            ignoring: saving,
                            child: PrimaryActionButton(
                              theme: t,
                              label: saving
                                  ? 'Guardando seguridad...'
                                  : 'Continuar',
                              onPressed: advance,
                            ),
                          ),
                        if (step == 3) ...[
                          PrimaryActionButton(
                            theme: t,
                            label: 'Agregar mi primera cuenta',
                            onPressed: () => finish(true),
                          ),
                          const SizedBox(height: 10),
                          SecondaryActionButton(
                            theme: t,
                            label: 'Ir al inicio',
                            onPressed: () => finish(false),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> content(BuildContext context, RTheme t) {
    final app = widget.app;
    switch (step) {
      case 0:
        return [
          RField(
            theme: t,
            controller: name,
            placeholder: 'Tu nombre',
            inputFormatters: [LengthLimitingTextInputFormatter(40)],
          ),
          RField(
            theme: t,
            controller: surname,
            placeholder: 'Apellido',
            inputFormatters: [LengthLimitingTextInputFormatter(60)],
          ),
          OptionField(
            theme: t,
            label: 'Fecha de nacimiento',
            value: birthDate == null
                ? 'Sin especificar'
                : formatDate(birthDate!),
            icon: CupertinoIcons.calendar,
            onTap: () async {
              final date = await appBirthDatePicker(context, t, birthDate);
              if (mounted && date != null) setState(() => birthDate = date);
            },
          ),
        ];
      case 1:
        return [
          KindSelector(
            theme: t,
            value: app.dark ? 'dark' : 'light',
            separated: true,
            items: const [
              KindSelectorItem(
                value: 'light',
                label: 'Claro',
                icon: CupertinoIcons.sun_max,
              ),
              KindSelectorItem(
                value: 'dark',
                label: 'Oscuro',
                icon: CupertinoIcons.moon,
              ),
            ],
            onChanged: (value) =>
                app.mutate(() => app.state['darkMode'] = value == 'dark'),
          ),
          const SizedBox(height: 12),
          SectionHeader(theme: t, title: 'Color'),
          ThemeColorSelector(
            theme: t,
            value: app.themeColorKey,
            onChanged: (value) =>
                app.mutate(() => app.state['themeColor'] = value),
          ),
        ];
      case 2:
        return [
          SettingsSwitchTile(
            theme: t,
            icon: CupertinoIcons.lock,
            title: 'Proteger con PIN',
            subtitle: 'Opcional',
            framed: false,
            value: usePin,
            onTap: () => setState(() => usePin = !usePin),
          ),
          if (usePin) ...[
            RField(
              theme: t,
              controller: pin,
              placeholder: 'PIN de 4 a 6 dígitos',
              obscureText: obscurePin,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
            ),
            RField(
              theme: t,
              controller: pinConfirm,
              placeholder: 'Repetir PIN',
              obscureText: obscurePin,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                onPressed: () => setState(() => obscurePin = !obscurePin),
                child: Icon(
                  obscurePin ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                  semanticLabel: obscurePin ? 'Mostrar PIN' : 'Ocultar PIN',
                ),
              ),
            ),
            if (biometricsAvailable)
              SettingsSwitchTile(
                theme: t,
                icon: CupertinoIcons.lock_shield,
                title: 'Biometría',
                subtitle: 'Huella o rostro',
                framed: false,
                value: useBiometrics,
                onTap: () => setState(() => useBiometrics = !useBiometrics),
              ),
            SecurityRecoveryNote(theme: t),
          ],
        ];
      default:
        return [
          Icon(CupertinoIcons.check_mark_circled, color: t.accent, size: 56),
          const SizedBox(height: 22),
          Text(
            'Bienvenido, ${name.text.trim()}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.ink,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 28),
          DebtDetailRow(
            theme: t,
            label: 'Apariencia',
            value: app.dark ? 'Oscura' : 'Clara',
          ),
          DebtDetailRow(
            theme: t,
            label: 'Color',
            value: themeColorByKey(app.themeColorKey).label,
          ),
          DebtDetailRow(
            theme: t,
            label: 'Seguridad',
            value: !usePin
                ? 'Sin PIN'
                : useBiometrics
                ? 'PIN y biometría'
                : 'PIN',
          ),
          const SizedBox(height: 18),
          SettingsSwitchTile(
            theme: t,
            icon: CupertinoIcons.bell,
            title: 'Recordatorio diario',
            subtitle: '7:00 p. m.',
            framed: false,
            value: app.state['dailyMovementReminderEnabled'] == true,
            onTap: () => app.mutate(
              () => app.state['dailyMovementReminderEnabled'] =
                  app.state['dailyMovementReminderEnabled'] != true,
            ),
          ),
        ];
    }
  }
}
