part of 'main.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.app});
  final _RialAppState app;
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool importing = false, busy = false;
  String? status;
  bool failed = false;
  Map<String, dynamic>? preview;

  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      status = null;
      failed = false;
    });
    try {
      await action();
    } catch (_) {
      failed = true;
      status = importing
          ? 'No se pudo importar. Revisa la contraseña y que la copia esté completa. Tus datos actuales se conservan.'
          : 'No se pudo guardar la copia. Revisa el espacio disponible y vuelve a intentarlo.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool validatePassword() {
    final valid =
        password.text.length >= 10 &&
        password.text.length <= 256 &&
        (importing || password.text == confirmation.text);
    if (!valid)
      setState(() {
        failed = true;
        status =
            'Usa entre 10 y 256 caracteres${importing ? '.' : ' y confirma la misma contraseña.'}';
      });
    return valid;
  }

  void export() {
    if (!validatePassword()) return;
    run(() async {
      await NativeStateStore.flush();
      final bytes = await compute(encryptPortableBackup, {
        'state': widget.app.state,
        'password': password.text,
        'appVersion': '$_appVersionName+$_appBuildNumber',
      }, debugLabel: 'encrypt-portable-backup');
      if (!mounted) return;
      final saved = await widget.app._backupDocument<bool>(
        'exportBackupBytes',
        {
          'name': 'Sin-Rial-${isoDate(DateTime.now())}.sinrial.json',
          'bytes': bytes,
        },
      );
      if (saved == true) {
        status = 'Copia guardada. Conserva su contraseña en un lugar seguro.';
        password.clear();
        confirmation.clear();
      }
    });
  }

  void import() {
    if (!validatePassword()) return;
    run(() async {
      final bytes = await widget.app._backupDocument<Uint8List>(
        'pickBackupBytes',
      );
      if (bytes == null || !mounted) return;
      final decoded = await compute(decryptPortableBackup, {
        'bytes': bytes,
        'password': password.text,
      }, debugLabel: 'decrypt-portable-backup');
      if (!mounted) return;
      preview = decoded;
      password.clear();
      confirmation.clear();
    });
  }

  void restore() {
    if (preview == null || busy) return;
    showModernConfirm(
      context,
      title: 'Reemplazar los datos',
      message: 'Se reemplazarán tus datos por los de esta copia. No se combinarán. Tu PIN y la seguridad de este dispositivo no cambiarán. Exporta antes una copia de tus datos actuales si deseas conservarlos.',
      destructiveText: 'Restaurar copia',
      onConfirm: () => run(() async {
        await widget.app.restoreBackup(
          preview!['state'] as Map<String, dynamic>,
        );
        preview = null;
        status =
            'Copia restaurada. Tus cuentas y movimientos ya están disponibles.';
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.app.theme;
    final data = preview?['state'] as Map<String, dynamic>?;
    return PopScope(
      canPop: !busy,
      child: CupertinoPageScaffold(
        backgroundColor: t.bg,
        navigationBar: CupertinoNavigationBar(
          transitionBetweenRoutes: false,
          backgroundColor: t.bg,
          border: null,
          middle: const Text('Copias de seguridad'),
          automaticallyImplyLeading: !busy,
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  for (final mode in [false, true])
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: mode ? 0 : 10),
                        child: Semantics(
                          selected: importing == mode,
                          child: CupertinoButton(
                            borderRadius: BorderRadius.circular(28),
                            color: importing == mode
                                ? t.accent.withValues(alpha: .16)
                                : t.card,
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                    importing = mode;
                                    preview = null;
                                    status = null;
                                    password.clear();
                                    confirmation.clear();
                                  }),
                            child: Text(
                              mode ? 'Importar' : 'Exportar',
                              style: TextStyle(
                                color: importing == mode ? t.accent : t.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 28),
              Align(
                alignment: Alignment.centerLeft,
                child: Icon(
                  importing
                      ? CupertinoIcons.square_arrow_down
                      : CupertinoIcons.lock_shield,
                  color: t.accent,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                importing ? 'Recuperar tus datos' : 'Tu copia protegida',
                style: TextStyle(
                  color: t.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                importing
                    ? 'Necesitas el archivo de copia y su contraseña. La importación reemplaza los datos actuales.'
                    : 'La contraseña de esta copia es independiente de tu PIN. Sin ella no podrás recuperar el archivo en otro dispositivo.',
                style: TextStyle(color: t.muted, fontSize: 15, height: 1.5),
              ),
              const SizedBox(height: 24),
              if (data == null) ...[
                AbsorbPointer(
                  absorbing: busy,
                  child: Column(
                    children: [
                      RField(
                        theme: t,
                        controller: password,
                        placeholder: 'Contraseña de la copia',
                        obscureText: true,
                        keyboardType: TextInputType.visiblePassword,
                      ),
                      if (!importing)
                        RField(
                          theme: t,
                          controller: confirmation,
                          placeholder: 'Repite la contraseña',
                          obscureText: true,
                          keyboardType: TextInputType.visiblePassword,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (!busy)
                  PrimaryActionButton(
                    theme: t,
                    onPressed: importing ? import : export,
                    label: importing ? 'Seleccionar copia' : 'Guardar copia',
                  ),
              ] else ...[
                Text(
                  'Copia del ${formatDate(DateTime.parse(preview!['createdAt'] as String).toLocal())}',
                  style: TextStyle(
                    color: t.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                for (final entry in {
                  'accounts': 'Cuentas',
                  'movements': 'Movimientos',
                  'debts': 'Por cobrar / pagar',
                  'budgetPlans': 'Presupuestos',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.value,
                            style: TextStyle(color: t.muted, fontSize: 16),
                          ),
                        ),
                        Text(
                          '${(data[entry.key] as List?)?.length ?? 0}',
                          style: TextStyle(
                            color: t.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                if (!busy)
                  PrimaryActionButton(
                    theme: t,
                    onPressed: restore,
                    label: 'Restaurar esta copia',
                  ),
              ],
              if (busy)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: RialLoadingIndicator(
                      color: t.accent,
                      semanticsLabel: 'Procesando copia',
                    ),
                  ),
                ),
              if (status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      status!,
                      style: TextStyle(
                        color: failed ? t.red : t.green,
                        fontSize: 15,
                        height: 1.5,
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

extension _PortableRestore on _RialAppState {
  Future<T?> _backupDocument<T>(String method, [Object? arguments]) async {
    _internalDocumentOpen = true;
    try {
      return await _storeChannel.invokeMethod<T>(method, arguments);
    } finally {
      _internalDocumentOpen = false;
    }
  }

  Future<void> _restorePortableState(Map<String, dynamic> imported) async {
    if (_restoringBackup || _reloadingExternal)
      throw StateError('Almacenamiento ocupado');
    _restoringBackup = true;
    try {
      await NativeStateStore.flush();
      final next = defaultState()..addAll(validatePortableState(imported));
      for (final entry in state.entries) {
        if (isDeviceOnlyBackupKey(entry.key)) next[entry.key] = entry.value;
      }
      next['onboardingComplete'] = true;
      await NativeStateStore.save(next);
      await NativeStateStore.flush();
      var committed = next;
      try {
        // Native storage may retain a newer quote or apply a due maintenance fee.
        committed = await NativeStateStore.load();
      } catch (_) {}
      if (!mounted) return;
      _undoHistory.clear();
      _undoTimer?.cancel();
      _setViewState(() {
        state = committed;
        _showUndo = false;
      });
      revision.value++;
      scheduleDailyReminderFromState();
    } catch (_) {
      // A failed transaction must not leave a restorable snapshot in the save cache.
      try {
        final current = await NativeStateStore.load();
        if (mounted) {
          _setViewState(() => state = current);
          revision.value++;
        }
      } catch (_) {}
      rethrow;
    } finally {
      _restoringBackup = false;
    }
  }
}
