part of 'main.dart';

bool automaticBackupDue(Map<String, dynamic> state, DateTime now) {
  if (state['automaticBackupEnabled'] != true ||
      (state['automaticBackupFolder']?.toString() ?? '').isEmpty ||
      (state['automaticBackupPassword']?.toString() ?? '').length < 10)
    return false;
  final last = DateTime.tryParse(
    state['automaticBackupLast']?.toString() ?? '',
  );
  final interval = state['automaticBackupFrequency'] == 'weekly' ? 7 : 1;
  return last == null || now.difference(last) >= Duration(days: interval);
}

extension _AutomaticBackup on _RialAppState {
  void scheduleAutomaticBackup() {
    if (isQuickAccess ||
        _automaticBackupTimer?.isActive == true ||
        !automaticBackupDue(state, DateTime.now()))
      return;
    _automaticBackupTimer = Timer(const Duration(seconds: 12), () {
      if (mounted) unawaited(runAutomaticBackup());
    });
  }

  Future<bool> runAutomaticBackup({bool force = false}) async {
    final now = DateTime.now();
    if (_automaticBackupBusy ||
        _restoringBackup ||
        _reloadingExternal ||
        _internalDocumentOpen ||
        locked ||
        _privacySuspended ||
        isQuickAccess ||
        state['automaticBackupEnabled'] != true)
      return false;
    if (!force &&
        (!automaticBackupDue(state, now) ||
            (_automaticBackupAttempt != null &&
                now.difference(_automaticBackupAttempt!) <
                    const Duration(hours: 1))))
      return false;
    final folder = state['automaticBackupFolder']?.toString() ?? '';
    final password = state['automaticBackupPassword']?.toString() ?? '';
    if (folder.isEmpty || password.length < 10) return false;
    _automaticBackupBusy = true;
    _automaticBackupAttempt = now;
    try {
      await NativeStateStore.flush();
      final bytes = await compute(encryptPortableBackup, {
        'state': state,
        'password': password,
        'appVersion': '$_appVersionName+$_appBuildNumber',
      }, debugLabel: 'automatic-portable-backup');
      if (!mounted ||
          state['automaticBackupEnabled'] != true ||
          state['automaticBackupFolder'] != folder ||
          state['automaticBackupPassword'] != password)
        return false;
      final saved = await _storeChannel.invokeMethod<bool>(
        'writeScheduledBackup',
        {
          'folder': folder,
          'bytes': bytes,
          'name':
              'Sin-Rial-${isoDate(now)}-${now.millisecondsSinceEpoch}.sinrial.json',
        },
      );
      if (saved != true) throw StateError('Backup not saved');
      if (mounted)
        mutate(() {
          state['automaticBackupLast'] = now.toIso8601String();
          state.remove('automaticBackupError');
        });
      return true;
    } catch (_) {
      if (mounted) mutate(() => state['automaticBackupError'] = true);
      return false;
    } finally {
      _automaticBackupBusy = false;
    }
  }
}
