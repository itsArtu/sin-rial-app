part of 'main.dart';

Widget softDialogTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  if (MediaQuery.disableAnimationsOf(context)) return child;
  final opacity = animation.drive(CurveTween(curve: Curves.easeInOutCubic));
  return FadeTransition(
    opacity: opacity,
    child: ScaleTransition(
      scale: animation.drive(
        Tween<double>(
          begin: .98,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
      ),
      child: child,
    ),
  );
}

Future<DateTime?> appBirthDatePicker(
  BuildContext context,
  RTheme theme,
  DateTime? initial,
) => showGeneralDialog<DateTime>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Cerrar',
  barrierColor: CupertinoColors.black.withValues(alpha: theme.dark ? .5 : .3),
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 260),
  transitionBuilder: softDialogTransition,
  pageBuilder: (_, __, ___) => BirthDateDialog(theme: theme, initial: initial),
);

class BirthDateDialog extends StatefulWidget {
  const BirthDateDialog({super.key, required this.theme, this.initial});
  final RTheme theme;
  final DateTime? initial;
  @override
  State<BirthDateDialog> createState() => _BirthDateDialogState();
}

class _BirthDateDialogState extends State<BirthDateDialog> {
  late final TextEditingController day, year;
  late int month;
  String? error;
  static const months = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];
  @override
  void initState() {
    super.initState();
    final initial = widget.initial ?? DateTime(2000);
    day = TextEditingController(text: initial.day.toString());
    year = TextEditingController(text: initial.year.toString());
    month = initial.month;
  }

  @override
  void dispose() {
    day.dispose();
    year.dispose();
    super.dispose();
  }

  void confirm() {
    final d = int.tryParse(day.text), y = int.tryParse(year.text);
    final now = DateTime.now();
    final date = y != null && d != null ? DateTime(y, month, d) : null;
    if (date == null ||
        y! < 1900 ||
        date.year != y ||
        date.month != month ||
        date.day != d ||
        date.isAfter(DateTime(now.year, now.month, now.day))) {
      setState(() => error = 'Revisa la fecha de nacimiento.');
      return;
    }
    Navigator.pop(context, date);
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
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: t.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Fecha de nacimiento',
                  style: TextStyle(
                    color: t.ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _number(t, 'D\u00eda', 'birth-day', day, 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _number(t, 'A\u00f1o', 'birth-year', year, 4),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                OptionField(
                  theme: t,
                  label: 'Mes',
                  value: months[month - 1],
                  onTap: () => pickValue(
                    context,
                    months,
                    months[month - 1],
                    (value) =>
                        setState(() => month = months.indexOf(value) + 1),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      error!,
                      style: TextStyle(color: t.red, fontSize: 13),
                    ),
                  ),
                PrimaryActionButton(
                  theme: t,
                  label: 'Confirmar fecha',
                  onPressed: confirm,
                ),
                CupertinoButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancelar', style: TextStyle(color: t.muted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _number(
    RTheme t,
    String label,
    String keyName,
    TextEditingController controller,
    int length,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(color: t.muted, fontSize: 13)),
      const SizedBox(height: 6),
      CupertinoTextField(
        key: ValueKey(keyName),
        controller: controller,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => FocusScope.of(context).unfocus(),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(length),
        ],
        padding: const EdgeInsets.all(14),
        style: TextStyle(color: t.ink, fontSize: 18),
        decoration: BoxDecoration(
          color: t.field,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ],
  );
}
