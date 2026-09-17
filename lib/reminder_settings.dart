part of 'main.dart';

class ReminderPermissions extends StatefulWidget {
  const ReminderPermissions({super.key, required this.theme});

  final RTheme theme;

  @override
  State<ReminderPermissions> createState() => _ReminderPermissionsState();
}

class _ReminderPermissionsState extends State<ReminderPermissions>
    with WidgetsBindingObserver {
  Map<String, dynamic> status = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<void> refresh() async {
    final value = await NativeStateStore.dailyReminderStatus();
    if (mounted) setState(() => status = value);
  }

  Future<void> openSettings(bool exact) async {
    final opened = await NativeStateStore.openReminderSettings(exact: exact);
    if (!mounted) return;
    if (!opened) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Ajustes de Android'),
          content: const Text('No se pudieron abrir los permisos de Sin Rial.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
    }
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (status.isEmpty) return const SizedBox.shrink();
    final notifications = status['notificationsAllowed'] == true;
    final exact = status['exactAllowed'] == true;
    return Column(
      children: [
        permissionRow(
          key: 'reminder-notifications',
          title: 'Notificaciones',
          value: notifications ? 'Permitidas' : 'Bloqueadas en Android',
          icon: CupertinoIcons.bell_fill,
          allowed: notifications,
          onTap: () => openSettings(false),
        ),
        permissionRow(
          key: 'reminder-exact',
          title: 'Hora exacta',
          value: exact
              ? 'Permiso de alarmas y recordatorios activo'
              : 'Permiso pendiente: Android puede retrasar el aviso',
          icon: CupertinoIcons.alarm,
          allowed: exact,
          onTap: () => openSettings(true),
        ),
      ],
    );
  }

  Widget permissionRow({
    required String key,
    required String title,
    required String value,
    required IconData icon,
    required bool allowed,
    required VoidCallback onTap,
  }) {
    final t = widget.theme;
    return CupertinoButton(
      key: ValueKey(key),
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: RCard(
        theme: t,
        child: Row(
          children: [
            Icon(icon, color: allowed ? t.green : t.amber, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(value, style: TextStyle(color: t.muted, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(CupertinoIcons.chevron_right, color: t.muted, size: 16),
          ],
        ),
      ),
    );
  }
}
