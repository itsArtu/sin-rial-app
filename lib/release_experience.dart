part of 'main.dart';

const currentFeatureTour = '$_appVersionName+$_appBuildNumber';

const bankMaintenanceAmount = 684.0;
const bankMaintenancePolicy = 'ves-current-2026-09';

String nextMaintenanceMonth([DateTime? now]) {
  final date = now ?? DateTime.now();
  final next = DateTime(date.year, date.month + 1);
  return '${next.year}-${next.month.toString().padLeft(2, '0')}';
}

Future<void> showDisablePinDialog(
  BuildContext context,
  _RialAppState app,
) async {
  await showCupertinoDialog<void>(
    context: context,
    builder: (_) => DisablePinDialog(app: app),
  );
}

class DisablePinDialog extends StatefulWidget {
  const DisablePinDialog({super.key, required this.app});
  final _RialAppState app;
  @override
  State<DisablePinDialog> createState() => _DisablePinDialogState();
}

class _DisablePinDialogState extends State<DisablePinDialog> {
  final pin = TextEditingController();
  String? error;
  bool busy = false;
  @override
  void dispose() {
    pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoAlertDialog(
    title: const Text('Desactivar bloqueo'),
    content: Column(
      children: [
        const Text(
          'Confirma tu PIN actual. Tus datos seguir\u00e1n cifrados, pero la app abrir\u00e1 sin pedir desbloqueo.',
        ),
        const SizedBox(height: 16),
        CupertinoTextField(
          controller: pin,
          obscureText: true,
          placeholder: 'PIN actual',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
        ),
        if (error != null)
          Text(error!, style: TextStyle(color: widget.app.theme.red)),
      ],
    ),
    actions: [
      CupertinoDialogAction(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      CupertinoDialogAction(
        isDestructiveAction: true,
        onPressed: busy
            ? null
            : () async {
                setState(() => busy = true);
                final success = await widget.app.disableSecurity(pin: pin.text);
                if (!mounted) return;
                if (success) {
                  Navigator.pop(context);
                } else {
                  setState(() {
                    busy = false;
                    error = widget.app.pinError;
                  });
                }
              },
        child: const Text('Desactivar'),
      ),
    ],
  );
}

class ReleaseTour extends StatefulWidget {
  const ReleaseTour({
    super.key,
    required this.app,
    this.introduction = false,
    this.onDone,
  });
  final _RialAppState app;
  final bool introduction;
  final VoidCallback? onDone;
  @override
  State<ReleaseTour> createState() => _ReleaseTourState();
}

class _ReleaseTourState extends State<ReleaseTour> {
  int step = 0;
  bool leaving = false;
  bool finished = false;
  static const introductionPages = [
    (
      'Tus cuentas y balances',
      'Bol\u00edvares, d\u00f3lares y beneficios, con un saldo separado por cuenta.',
      CupertinoIcons.creditcard,
    ),
    (
      'Ingresos, gastos y transferencias',
      'Fecha, cuenta, monto y categor\u00eda para cada movimiento. Los pagos en bol\u00edvares conservan su equivalente BCV.',
      CupertinoIcons.arrow_right_arrow_left,
    ),
    (
      'Tu plan mensual',
      'Ingresos previstos, ahorro y un l\u00edmite por categor\u00eda. Cada gasto se suma autom\u00e1ticamente a su categor\u00eda.',
      CupertinoIcons.chart_pie,
    ),
    (
      'Por cobrar y por pagar',
      'Abonos y saldos pendientes separados de las deudas ya pagadas.',
      CupertinoIcons.check_mark_circled,
    ),
    (
      'A tu medida',
      'Colores, widgets y privacidad. PIN y biometr\u00eda opcionales; datos guardados localmente y cifrados.',
      CupertinoIcons.slider_horizontal_3,
    ),
  ];
  static const releasePages = [
    (
      'Un plan m\u00e1s simple',
      'Un total y un l\u00edmite por categor\u00eda, sin subcategor\u00edas ni asignaciones adicionales. Tus gastos anteriores siguen incluidos.',
      CupertinoIcons.chart_pie,
    ),
    (
      'Categor\u00edas a tu medida',
      'Crea una categor\u00eda desde el selector, incluso mientras buscas. Chucher\u00edas reconoce dulces y snacks; TDC selecciona Pago TDC.',
      CupertinoIcons.tag,
    ),
    (
      'Cuotas y pr\u00e9stamos',
      'Elige la cuota que pagaste. Al recibir un pr\u00e9stamo puedes ingresar el dinero en una cuenta; no aplica a Cashea.',
      CupertinoIcons.check_mark_circled,
    ),
    (
      'Herramientas desde el inicio',
      'Nuevo widget de tasa USDT. La calculadora abre sin desbloquear, pero tus cuentas y movimientos siguen protegidos al entrar a la app.',
      CupertinoIcons.square_grid_2x2,
    ),
    (
      'Ajustes para el d\u00eda a d\u00eda',
      'Colores de movimientos con muestras de montos, logos m\u00e1s claros y bloqueo sin saltos. Referencias opcionales para ingresos y gastos desde Ajustes. Toca la gr\u00e1fica USDT para consultar cada tasa.',
      CupertinoIcons.paintbrush,
    ),
  ];
  List<(String, String, IconData)> get pages =>
      widget.introduction ? introductionPages : releasePages;
  void finish() {
    if (leaving || finished) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      complete();
    } else {
      setState(() => leaving = true);
    }
  }

  void complete() {
    if (!mounted || finished) return;
    finished = true;
    widget.app.mutate(() {
      if (widget.introduction) widget.app.state['pendingAppTour'] = false;
      widget.app.state['seenFeatureTour'] = currentFeatureTour;
    });
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: leaving ? 0 : 1,
    duration: const Duration(milliseconds: 240),
    curve: Curves.easeInOut,
    onEnd: () {
      if (leaving) complete();
    },
    child: IgnorePointer(ignoring: leaving, child: buildPage(context)),
  );

  Widget buildPage(BuildContext context) {
    final t = widget.app.theme;
    final page = pages[step];
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.introduction
                              ? 'Conoce Sin Rial'
                              : 'Novedades de $_appVersionName',
                          style: TextStyle(color: t.muted),
                        ),
                      ),
                      CupertinoButton(
                        onPressed: finish,
                        child: const Text('Omitir'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: Column(
                        key: ValueKey(step),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TourArtwork(theme: t, icon: page.$3),
                          const SizedBox(height: 24),
                          Text(
                            page.$1,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: t.ink,
                              fontSize: 25,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            page.$2,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: t.muted,
                              fontSize: 16,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(
                        '${step + 1} / ${pages.length}',
                        style: TextStyle(color: t.muted),
                      ),
                      const SizedBox(height: 16),
                      PrimaryActionButton(
                        theme: t,
                        label: step == pages.length - 1
                            ? 'Empezar'
                            : 'Siguiente',
                        onPressed: () => step == pages.length - 1
                            ? finish()
                            : setState(() => step++),
                      ),
                      SizedBox(
                        height: 48,
                        child: step > 0
                            ? CupertinoButton(
                                onPressed: () => setState(() => step--),
                                child: const Text('Anterior'),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BrandEntrance extends StatelessWidget {
  const BrandEntrance({super.key, required this.theme});
  final RTheme theme;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(
      begin: MediaQuery.disableAnimationsOf(context) ? 1 : 0,
      end: 1,
    ),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 420),
    curve: Curves.easeOutCubic,
    child: RepaintBoundary(
      child: SinRialLogo(theme: theme, color: theme.accent, height: 56),
    ),
    builder: (_, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 6 * (1 - value)),
        child: child,
      ),
    ),
  );
}

class TourArtwork extends StatelessWidget {
  const TourArtwork({super.key, required this.theme, required this.icon});
  final RTheme theme;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(height: 56, child: BrandEntrance(theme: theme)),
      const SizedBox(height: 32),
      TourFeatureIcon(theme: theme, icon: icon),
    ],
  );
}

class TourFeatureIcon extends StatefulWidget {
  const TourFeatureIcon({super.key, required this.theme, required this.icon});
  final RTheme theme;
  final IconData icon;

  @override
  State<TourFeatureIcon> createState() => _TourFeatureIconState();
}

class _TourFeatureIconState extends State<TourFeatureIcon>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool? reducedMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reducedMotion == reduced) return;
    reducedMotion = reduced;
    if (reduced) {
      controller.value = 1;
    } else {
      controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant TourFeatureIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.icon != widget.icon && reducedMotion == false) {
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 88,
    width: 88,
    child: AnimatedBuilder(
      animation: controller,
      child: RepaintBoundary(
        child: Icon(widget.icon, size: 64, color: widget.theme.accent),
      ),
      builder: (_, child) {
        final progress = controller.value;
        final enter = Curves.easeOutCubic.transform(
          (progress / .65).clamp(0.0, 1.0),
        );
        final settle = math.sin(math.pi * progress);
        return Opacity(
          opacity: enter,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - enter)),
            child: Transform.rotate(
              angle: -.12 * (1 - enter),
              child: Transform.scale(
                scale: .82 + .18 * enter + .035 * settle,
                child: child,
              ),
            ),
          ),
        );
      },
    ),
  );
}

Future<String?> promptMovementReference(
  BuildContext context,
  RTheme theme, {
  required bool income,
}) => showGeneralDialog<String>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Sin referencia',
  barrierColor: CupertinoColors.black.withValues(alpha: .4),
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 220),
  transitionBuilder: softDialogTransition,
  pageBuilder: (_, _, _) =>
      MovementReferenceDialog(theme: theme, income: income),
);

class MovementReferenceDialog extends StatefulWidget {
  const MovementReferenceDialog({
    super.key,
    required this.theme,
    this.income = false,
  });
  final RTheme theme;
  final bool income;
  @override
  State<MovementReferenceDialog> createState() =>
      _MovementReferenceDialogState();
}

class _MovementReferenceDialogState extends State<MovementReferenceDialog> {
  final reference = TextEditingController();
  bool editing = false;

  @override
  void dispose() {
    reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(CupertinoIcons.doc_text, color: t.accent, size: 32),
                const SizedBox(height: 16),
                Text(
                  editing
                      ? 'Referencia de la operaci\u00f3n'
                      : '\u00bfAgregar referencia?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                if (editing) ...[
                  RField(
                    theme: t,
                    controller: reference,
                    placeholder: 'N\u00famero de referencia',
                    inputFormatters: [LengthLimitingTextInputFormatter(64)],
                  ),
                  const SizedBox(height: 12),
                  PrimaryActionButton(
                    theme: t,
                    label: widget.income ? 'Guardar ingreso' : 'Guardar gasto',
                    onPressed: () =>
                        Navigator.pop(context, reference.text.trim()),
                  ),
                  const SizedBox(height: 8),
                  CupertinoButton(
                    onPressed: () => Navigator.pop(context, ''),
                    child: const Text('Sin referencia'),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoButton(
                          onPressed: () => Navigator.pop(context, ''),
                          child: const Text('No'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: CupertinoButton(
                          color: t.accent,
                          onPressed: () {
                            setState(() => editing = true);
                          },
                          child: Text('S\u00ed', style: TextStyle(color: t.bg)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SmoothDownloadProgress extends StatelessWidget {
  const SmoothDownloadProgress({super.key, required this.theme, this.value});
  final RTheme theme;
  final double? value;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value ?? 0),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 450),
    curve: Curves.easeOutCubic,
    builder: (_, progress, __) => ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: material.LinearProgressIndicator(
        value: value == null
            ? (MediaQuery.disableAnimationsOf(context) ? 0 : null)
            : progress,
        color: theme.accent,
        backgroundColor: theme.field,
        minHeight: 10,
      ),
    ),
  );
}
