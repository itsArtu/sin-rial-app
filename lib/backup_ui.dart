part of 'main.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.app});
  final _RialAppState app;
  @override
  State<BackupPage> createState() => _BackupPageState();
}

enum _BackupStep { home, protect, unlock, review, automatic, done }

class _BackupPageState extends State<BackupPage> {
  final password = TextEditingController();
  final confirmation = TextEditingController();
  _BackupStep step = _BackupStep.home;
  bool busy = false, failed = false, visiblePassword = false;
  String? status;
  String frequency = 'daily';
  Uint8List? selectedBytes;
  Map<String, dynamic>? preview;

  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  void go(_BackupStep next) {
    if (busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      step = next;
      status = null;
      failed = false;
      password.clear();
      confirmation.clear();
      visiblePassword = false;
      if (next == _BackupStep.home) {
        selectedBytes = null;
        preview = null;
      }
    });
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
      status = step == _BackupStep.unlock
          ? 'No se pudo abrir. Revisa la contraseña y el archivo. Tus datos no han cambiado.'
          : 'No se pudo completar. Revisa el espacio y el acceso al archivo e inténtalo de nuevo.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool validatePassword({bool confirm = true}) {
    final valid =
        password.text.length >= 10 &&
        password.text.length <= 256 &&
        (!confirm || password.text == confirmation.text);
    if (!valid)
      setState(() {
        failed = true;
        status = confirm
            ? 'Usa al menos 10 caracteres y repite la misma contraseña.'
            : 'Introduce la contraseña de la copia (entre 10 y 256 caracteres).';
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
      if (saved == true && mounted) {
        step = _BackupStep.done;
        status = 'Copia guardada. Conserva la contraseña para abrirla en otro dispositivo.';
        password.clear();
        confirmation.clear();
      }
    });
  }

  void chooseFile() {
    run(() async {
      final bytes = await widget.app._backupDocument<Uint8List>(
        'pickBackupBytes',
      );
      if (bytes == null || !mounted) return;
      selectedBytes = bytes;
      preview = null;
      password.clear();
      confirmation.clear();
      step = _BackupStep.unlock;
    });
  }

  void unlock() {
    if (selectedBytes == null || !validatePassword(confirm: false)) return;
    run(() async {
      final decoded = await compute(decryptPortableBackup, {
        'bytes': selectedBytes!,
        'password': password.text,
      }, debugLabel: 'decrypt-portable-backup');
      if (!mounted) return;
      preview = decoded;
      selectedBytes = null;
      password.clear();
      step = _BackupStep.review;
    });
  }

  void restore() {
    if (preview == null || busy) return;
    showModernConfirm(
      context,
      title: 'Reemplazar los datos',
      message: 'Esta copia reemplazará las cuentas y movimientos actuales. No se combinarán. Tu PIN y biometría se conservan. Guarda antes una copia si necesitas conservar los datos de este teléfono.',
      destructiveText: 'Restaurar copia',
      onConfirm: () => run(() async {
        await widget.app.restoreBackup(
          preview!['state'] as Map<String, dynamic>,
        );
        if (!mounted) return;
        preview = null;
        step = _BackupStep.done;
        status = 'Tus cuentas y movimientos ya están disponibles.';
      }),
    );
  }

  void configureAutomatic() {
    if (!validatePassword()) return;
    run(() async {
      final folder = await widget.app._backupDocument<String>(
        'pickBackupFolder',
      );
      if (!mounted || folder == null) return;
      widget.app.mutate(() {
        widget.app.state.addAll({
          'automaticBackupEnabled': true,
          'automaticBackupFolder': folder,
          'automaticBackupPassword': password.text,
          'automaticBackupFrequency': frequency,
        });
        widget.app.state.remove('automaticBackupLast');
        widget.app.state.remove('automaticBackupError');
      });
      password.clear();
      confirmation.clear();
      final saved = await widget.app.runAutomaticBackup(force: true);
      status = saved
          ? 'Copia guardada. Copias periódicas activadas.'
          : 'Copias activadas. La primera se preparará al usar la app.';
    });
  }

  Widget action(
    RTheme t,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: PressFeedback(
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: RialSurface.control(t),
        child: Row(
          children: [
            Icon(icon, size: 26, color: t.accent),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: t.muted, fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(CupertinoIcons.chevron_right, color: t.muted, size: 15),
          ],
        ),
      ),
    ),
  );

  List<Widget> passwordFields(RTheme t, {required bool confirm}) => [
    Text(
      confirm ? 'Contraseña de la copia' : 'Contraseña',
      style: TextStyle(color: t.ink, fontSize: 14, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 8),
    RField(
      theme: t,
      controller: password,
      placeholder: confirm
          ? 'Al menos 10 caracteres'
          : 'Contraseña de esta copia',
      obscureText: !visiblePassword,
      keyboardType: TextInputType.visiblePassword,
    ),
    if (confirm)
      RField(
        theme: t,
        controller: confirmation,
        placeholder: 'Repetir contraseña',
        obscureText: !visiblePassword,
        keyboardType: TextInputType.visiblePassword,
      ),
    Align(
      alignment: Alignment.centerRight,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        onPressed: busy
            ? null
            : () => setState(() => visiblePassword = !visiblePassword),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              visiblePassword ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
              size: 18,
              color: t.accent,
            ),
            const SizedBox(width: 8),
            Text(
              visiblePassword ? 'Ocultar contraseña' : 'Mostrar contraseña',
              style: TextStyle(color: t.accent, fontSize: 13),
            ),
          ],
        ),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = widget.app.theme;
    final automatic = widget.app.state['automaticBackupEnabled'] == true;
    final data = preview?['state'] as Map<String, dynamic>?;
    final title = switch (step) {
      _BackupStep.home => 'Copias de seguridad',
      _BackupStep.protect => 'Guardar copia',
      _BackupStep.unlock => 'Abrir copia',
      _BackupStep.review => 'Revisar copia',
      _BackupStep.automatic => 'Copias periódicas',
      _BackupStep.done => 'Todo listo',
    };
    return PopScope(
      canPop: !busy && step == _BackupStep.home,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !busy) go(_BackupStep.home);
      },
      child: CupertinoPageScaffold(
        backgroundColor: t.bg,
        navigationBar: RialNavigationBar(
          middle: Text(title),
          automaticallyImplyLeading: !busy && step == _BackupStep.home,
          leading: step == _BackupStep.home
              ? null
              : CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: busy ? null : () => go(_BackupStep.home),
                  child: Icon(
                    CupertinoIcons.chevron_left,
                    color: t.ink,
                    size: 22,
                  ),
                ),
        ),
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: AbsorbPointer(
                absorbing: busy,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  children: [
                    if (step == _BackupStep.home) ...[
                      Text(
                        'Tus datos, contigo',
                        style: TextStyle(
                          color: t.ink,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Una copia protegida para conservar tus datos o cambiar de teléfono.',
                        style: TextStyle(
                          color: t.muted,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      action(
                        t,
                        CupertinoIcons.square_arrow_up,
                        'Guardar una copia',
                        'Cuentas, movimientos y preferencias',
                        () => go(_BackupStep.protect),
                      ),
                      action(
                        t,
                        CupertinoIcons.square_arrow_down,
                        'Recuperar una copia',
                        'Seleccionar un archivo de Sin Rial',
                        chooseFile,
                      ),
                      const SizedBox(height: 16),
                      action(
                        t,
                        CupertinoIcons.arrow_2_circlepath,
                        'Copias periódicas',
                        automatic ? 'Activadas' : 'Desactivadas',
                        () => go(_BackupStep.automatic),
                      ),
                    ],
                    if (step == _BackupStep.protect) ...[
                      Text(
                        'Protege tu archivo',
                        style: TextStyle(
                          color: t.ink,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Esta contraseña es distinta de tu PIN. Sin ella no podrás recuperar la copia.',
                        style: TextStyle(
                          color: t.muted,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ...passwordFields(t, confirm: true),
                      const SizedBox(height: 16),
                      PrimaryActionButton(
                        theme: t,
                        label: 'Elegir dónde guardar',
                        onPressed: export,
                      ),
                    ],
                    if (step == _BackupStep.unlock) ...[
                      action(
                        t,
                        CupertinoIcons.doc_checkmark,
                        'Archivo seleccionado',
                        'Cambiar archivo',
                        chooseFile,
                      ),
                      const SizedBox(height: 16),
                      ...passwordFields(t, confirm: false),
                      const SizedBox(height: 16),
                      PrimaryActionButton(
                        theme: t,
                        label: 'Abrir y revisar',
                        onPressed: unlock,
                      ),
                    ],
                    if (step == _BackupStep.review && data != null) ...[
                      Text(
                        'Copia del ${formatDate(DateTime.parse(preview!['createdAt'] as String).toLocal())}',
                        style: TextStyle(
                          color: t.ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 20),
                      for (final entry in {
                        'accounts': 'Cuentas',
                        'movements': 'Movimientos',
                        'debts': 'Por cobrar / pagar',
                        'budgetPlans': 'Presupuestos',
                      }.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry.value,
                                  style: TextStyle(
                                    color: t.muted,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Text(
                                '${(data[entry.key] as List?)?.length ?? 0}',
                                style: TextStyle(
                                  color: t.ink,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),
                      Text(
                        'Los datos actuales se reemplazarán. Tu PIN y biometría no cambian.',
                        style: TextStyle(
                          color: t.muted,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      PrimaryActionButton(
                        theme: t,
                        label: 'Restaurar esta copia',
                        onPressed: restore,
                      ),
                    ],
                    if (step == _BackupStep.automatic) ...[
                      Text(
                        'Se guardan al usar la app, en la carpeta que elijas.',
                        style: TextStyle(
                          color: t.muted,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (!automatic) ...[
                        AppPillSelector(
                          theme: t,
                          value: frequency,
                          showIcons: false,
                          items: const [
                            KindSelectorItem(
                              value: 'daily',
                              label: 'Diarias',
                              icon: CupertinoIcons.calendar,
                            ),
                            KindSelectorItem(
                              value: 'weekly',
                              label: 'Semanales',
                              icon: CupertinoIcons.calendar,
                            ),
                          ],
                          onChanged: (v) => setState(() => frequency = v),
                        ),
                        const SizedBox(height: 24),
                        ...passwordFields(t, confirm: true),
                        Text(
                          'La contraseña se guarda cifrada en este teléfono. Consérvala también en un lugar seguro.',
                          style: TextStyle(
                            color: t.muted,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        PrimaryActionButton(
                          theme: t,
                          label: 'Elegir carpeta y activar',
                          onPressed: configureAutomatic,
                        ),
                      ] else ...[
                        Text(
                          widget.app.state['automaticBackupError'] == true
                              ? 'La última copia falló. Revisa la carpeta y el espacio disponible.'
                              : widget.app.state['automaticBackupLast'] == null
                              ? 'Primera copia pendiente'
                              : 'Última copia: ${formatDate(DateTime.parse(widget.app.state['automaticBackupLast'].toString()))}',
                          style: TextStyle(
                            color: t.muted,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        PrimaryActionButton(
                          theme: t,
                          label: 'Guardar ahora',
                          onPressed: () => run(() async {
                            final saved = await widget.app.runAutomaticBackup(
                              force: true,
                            );
                            failed = !saved;
                            status = saved
                                ? 'Copia guardada.'
                                : 'No se pudo guardar. Revisa la carpeta.';
                          }),
                        ),
                        SecondaryActionButton(
                          theme: t,
                          label: 'Desactivar copias periódicas',
                          onPressed: () {
                            widget.app.mutate(() {
                              widget.app.state['automaticBackupEnabled'] =
                                  false;
                              widget.app.state.remove(
                                'automaticBackupPassword',
                              );
                              widget.app.state.remove('automaticBackupFolder');
                            });
                            go(_BackupStep.home);
                          },
                        ),
                      ],
                    ],
                    if (step == _BackupStep.done) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Icon(
                          CupertinoIcons.checkmark_seal,
                          size: 56,
                          color: t.green,
                        ),
                      ),
                      PrimaryActionButton(
                        theme: t,
                        label: 'Volver a copias',
                        onPressed: () => go(_BackupStep.home),
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
