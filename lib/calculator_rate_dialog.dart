part of 'main.dart';

Future<double?> showRateInputDialog(
  BuildContext context,
  RTheme theme,
  String currency,
  double initial,
) => showDecimalInputDialog(
  context,
  theme: theme,
  title: 'Tasa personalizada',
  subtitle: '$currency/VES',
  initial: initial,
  inputKey: const ValueKey('custom-rate-input'),
);

String compactDecimal(double value) =>
    Decimal.parse(value.toString()).toString();

Future<double?> showDecimalInputDialog(
  BuildContext context, {
  required RTheme theme,
  required String title,
  required String subtitle,
  required double initial,
  required Key inputKey,
  bool allowZero = false,
  double maximum = 999999999,
}) => showGeneralDialog<double>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Cancelar',
  barrierColor: CupertinoColors.black.withValues(alpha: .5),
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 220),
  transitionBuilder: softDialogTransition,
  pageBuilder: (context, animation, secondary) => KeyboardDismissScope(
    child: _DecimalInputDialog(
      theme: theme,
      title: title,
      subtitle: subtitle,
      initial: initial,
      inputKey: inputKey,
      allowZero: allowZero,
      maximum: maximum,
    ),
  ),
);

class _DecimalInputDialog extends StatefulWidget {
  const _DecimalInputDialog({
    required this.theme,
    required this.title,
    required this.subtitle,
    required this.initial,
    required this.inputKey,
    required this.allowZero,
    required this.maximum,
  });
  final RTheme theme;
  final String title, subtitle;
  final double initial;
  final Key inputKey;
  final bool allowZero;
  final double maximum;
  @override
  State<_DecimalInputDialog> createState() => _DecimalInputDialogState();
}

class _DecimalInputDialogState extends State<_DecimalInputDialog> {
  late final controller = TextEditingController(
    text: widget.initial > 0 || widget.allowZero
        ? compactDecimal(widget.initial)
        : '',
  );
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final value = parseAmount(controller.text);
    if (controller.text.trim().isEmpty ||
        !RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(controller.text.trim()) ||
        !value.isFinite ||
        value < 0 ||
        (!widget.allowZero && value == 0) ||
        value > widget.maximum) {
      setState(
        () => error = widget.allowZero
            ? 'Ingresa un valor entre 0 y ${compactDecimal(widget.maximum)}'
            : 'Ingresa una tasa mayor a cero',
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(22),
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
                    widget.title,
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(widget.subtitle, style: TextStyle(color: t.muted)),
                  const SizedBox(height: 18),
                  CupertinoTextField(
                    key: widget.inputKey,
                    controller: controller,
                    autofocus: true,
                    placeholder: '0',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => submit(),
                    padding: const EdgeInsets.all(16),
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: BoxDecoration(
                      color: t.field,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!, style: TextStyle(color: t.red)),
                    ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      Expanded(
                        child: CupertinoButton(
                          color: t.accent,
                          onPressed: submit,
                          child: Text('Aplicar', style: TextStyle(color: t.bg)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
