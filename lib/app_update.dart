part of 'main.dart';

bool hasVerifiedUpdateMetadata(UpdateInfo update) =>
    RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(update.sha256) &&
    update.size > 0 &&
    update.size <= 200 * 1024 * 1024 &&
    update.build > 0;

class AppUpdatePage extends StatefulWidget {
  const AppUpdatePage({super.key, required this.update, required this.theme});
  final UpdateInfo update;
  final RTheme theme;
  @override
  State<AppUpdatePage> createState() => _AppUpdatePageState();
}

class _AppUpdatePageState extends State<AppUpdatePage>
    with WidgetsBindingObserver {
  Map<String, dynamic> snapshot = {'status': 'starting'};
  Timer? timer;
  bool busy = false;
  bool foreground = true;
  bool needsPermission = false;
  String? error;
  String get status => snapshot['status']?.toString() ?? 'idle';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(start());
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (foreground && ['downloading', 'paused'].contains(status)) {
        unawaited(invoke('apkUpdateStatus'));
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) unawaited(invoke('apkUpdateStatus'));
  }

  Future<void> start() async {
    if (!hasVerifiedUpdateMetadata(widget.update)) {
      setState(
        () => error = 'La publicacion no incluye los datos de verificacion. No se descargara una APK sin verificar.',
      );
      return;
    }
    final update = widget.update;
    await invoke('startApkUpdate', {
      'url': update.apkUrl,
      'sha256': update.sha256,
      'size': update.size,
      'build': update.build,
      'version': update.version,
    });
  }

  Future<void> invoke(String method, [Map<String, dynamic>? arguments]) async {
    if (busy || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await _storeChannel.invokeMethod<dynamic>(
        method,
        arguments,
      );
      if (!mounted) return;
      setState(() {
        if (response is Map) {
          final next = Map<String, dynamic>.from(response);
          if (next['status'] == 'permission') {
            needsPermission = true;
          } else if (next['status'] != 'install') {
            snapshot = next;
          } else {
            needsPermission = false;
          }
        }
      });
    } on PlatformException catch (failure) {
      if (mounted)
        setState(
          () => error =
              failure.message ?? 'No se pudo completar la actualizacion',
        );
    } catch (_) {
      if (mounted)
        setState(
          () =>
              error = 'El actualizador no esta disponible en este dispositivo',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final total = numberValue(snapshot['total']);
    final received = numberValue(snapshot['received']);
    final active = status == 'downloading' || status == 'paused';
    final progress = total > 0 ? (received / total).clamp(0.0, 1.0) : null;
    final message = error ?? snapshot['message']?.toString();
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg,
        middle: const Text('Actualizar Sin Rial'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Icon(
              status == 'ready'
                  ? material.Icons.verified_outlined
                  : material.Icons.system_update_alt,
              color: t.accent,
              size: 48,
            ),
            const SizedBox(height: 18),
            Text(
              'Sin Rial ${widget.update.version}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.ink,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              switch (status) {
                'ready' => 'Actualizacion verificada',
                'installed' => 'Actualizacion instalada',
                'paused' => 'Descarga en espera',
                'downloading' =>
                  'Descargando${progress == null ? '' : ' ${(progress * 100).floor()}%'}',
                'failed' => 'Descarga interrumpida',
                'idle' => 'Descarga cancelada',
                _ => 'Preparando descarga',
              },
              textAlign: TextAlign.center,
              style: TextStyle(color: t.ink, fontWeight: FontWeight.w600),
            ),
            if (active) ...[
              const SizedBox(height: 18),
              material.LinearProgressIndicator(
                value: progress,
                color: t.accent,
                backgroundColor: t.field,
                minHeight: 6,
              ),
              const SizedBox(height: 12),
              Text(
                '${formatNumber(received / 1048576)} / ${formatNumber(total / 1048576)} MB',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.muted),
              ),
            ],
            if (message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.red),
                ),
              ),
            if (needsPermission) ...[
              const SizedBox(height: 18),
              Text(
                'Android necesita que permitas instalar actualizaciones desde Sin Rial.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.muted),
              ),
              CupertinoButton(
                onPressed: busy ? null : () => invoke('allowApkUpdates'),
                child: const Text(
                  'Abrir permiso de instalacion',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (status == 'ready')
              CupertinoButton(
                color: t.accent,
                onPressed: busy ? null : () => invoke('installApkUpdate'),
                child: Text(
                  'Instalar actualizacion',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.bg),
                ),
              ),
            if (active)
              CupertinoButton(
                onPressed: busy ? null : () => invoke('cancelApkUpdate'),
                child: const Text('Cancelar descarga'),
              ),
            if (error != null || status == 'failed' || status == 'idle')
              CupertinoButton(
                onPressed: busy ? null : start,
                child: const Text('Reintentar'),
              ),
            if (widget.update.notes.isNotEmpty) ...[
              const SizedBox(height: 32),
              Text(
                'Novedades',
                style: TextStyle(
                  color: t.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.update.notes,
                style: TextStyle(color: t.muted, height: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
