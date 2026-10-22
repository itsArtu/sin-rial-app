part of 'main.dart';

Future<material.TimeOfDay?> pickClockTime(
  BuildContext context,
  RTheme theme,
  DateTime initial,
) => material.showTimePicker(
  context: context,
  initialTime: material.TimeOfDay.fromDateTime(initial),
  helpText: 'Seleccionar hora',
  cancelText: 'Cancelar',
  confirmText: 'Aceptar',
  hourLabelText: 'Hora',
  minuteLabelText: 'Minutos',
  builder: (context, child) => material.Theme(
    data: material.ThemeData(
      useMaterial3: true,
      brightness: theme.dark ? Brightness.dark : Brightness.light,
      fontFamily: 'Manrope',
      colorScheme: material.ColorScheme.fromSeed(
        seedColor: theme.accent,
        brightness: theme.dark ? Brightness.dark : Brightness.light,
        primary: theme.accent,
        onPrimary: foregroundOn(theme.accent),
        surface: theme.card,
        onSurface: theme.ink,
      ),
      timePickerTheme: material.TimePickerThemeData(
        backgroundColor: theme.card,
        dialBackgroundColor: theme.field,
        dialHandColor: theme.accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
    ),
    child: child!,
  ),
);
