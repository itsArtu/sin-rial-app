part of 'main.dart';

String movementDescriptionKey(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

class MovementSuggestion {
  const MovementSuggestion(this.accountId, this.category);
  final String accountId, category;
}

class MovementSuggestionIndex {
  MovementSuggestionIndex(List<Map<String, dynamic>> movements) {
    for (final m in sortedMovements(movements)) {
      final description = movementDescriptionKey(
        m['description']?.toString() ?? '',
      );
      if (description.length < 3 || !['expense', 'income'].contains(m['type']))
        continue;
      _entries.putIfAbsent(
        '${m['type']}:$description',
        () => MovementSuggestion(
          m['accountId']?.toString() ?? '',
          m['category']?.toString() ?? 'Otro',
        ),
      );
    }
  }
  final _entries = <String, MovementSuggestion>{};
  MovementSuggestion? find(String type, String description) =>
      _entries['$type:${movementDescriptionKey(description)}'];
}

Map<String, dynamic>? possibleDuplicateMovement(
  Map<String, dynamic> draft,
  List<Map<String, dynamic>> movements, {
  String? editingId,
}) {
  final date = parseMovementDate(draft['date']?.toString());
  final description = movementDescriptionKey(
    draft['description']?.toString() ?? '',
  );
  for (final m in movements) {
    if ((editingId != null && m['id'] == editingId) ||
        m['type'] != draft['type'] ||
        m['accountId'] != draft['accountId'] ||
        m['currency'] != draft['currency'] ||
        moneyCents(numberValue(m['amount'])) !=
            moneyCents(numberValue(draft['amount'])))
      continue;
    if (draft['type'] == 'transfer' &&
        (m['targetAccountId'] != draft['targetAccountId'] ||
            moneyCents(numberValue(m['targetAmount'])) !=
                moneyCents(numberValue(draft['targetAmount']))))
      continue;
    final previousDate = parseMovementDate(m['date']?.toString());
    if (!isSameDate(date, previousDate) ||
        movementDescriptionKey(m['description']?.toString() ?? '') !=
            description)
      continue;
    if (description.isEmpty &&
        date.difference(previousDate).abs() > const Duration(minutes: 3))
      continue;
    return m;
  }
  return null;
}

Future<bool> confirmPossibleDuplicate(
  BuildContext context,
  RTheme theme,
) async =>
    await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Volver al movimiento',
      barrierColor: CupertinoColors.black.withValues(alpha: .5),
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      transitionBuilder: softDialogTransition,
      pageBuilder: (dialog, _, __) => SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.card,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '¿Ya lo registraste?',
                  style: TextStyle(
                    color: theme.ink,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Hay un movimiento similar en esta cuenta y fecha. Puedes revisarlo o guardar este también.',
                  style: TextStyle(
                    color: theme.muted,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                PrimaryActionButton(
                  theme: theme,
                  label: 'Volver y revisar',
                  onPressed: () => Navigator.pop(dialog, false),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: Text(
                    'Guardar de todos modos',
                    style: TextStyle(color: theme.accent, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ) ??
    false;

extension _LearnedMovement on _MovementEditorState {
  void refreshLearnedSuggestion(String text) {
    if (_suggestionRevision != widget.app.revision.value) {
      _suggestionRevision = widget.app.revision.value;
      _suggestionIndex = MovementSuggestionIndex(widget.app.maps('movements'));
    }
    final candidate = _suggestionIndex?.find(type, text);
    final account = widget.app.accountById(candidate?.accountId ?? '');
    learnedSuggestion =
        account == null ||
            (type == 'income' && isCreditCard(account)) ||
            (type == 'expense' &&
                !categoryChoices(context).contains(candidate?.category)) ||
            widget.movement != null ||
            debtId.isNotEmpty ||
            (widget.lockAccount && candidate!.accountId != accountId)
        ? null
        : candidate;
  }

  Widget learnedSuggestionButton() {
    final suggestion = learnedSuggestion;
    if (suggestion == null ||
        (suggestion.accountId == accountId &&
            (type != 'expense' || suggestion.category == category)))
      return const SizedBox.shrink();
    final t = widget.app.theme;
    final account = widget.app.accountById(suggestion.accountId);
    if (account == null) return const SizedBox.shrink();
    return CupertinoButton(
      key: const ValueKey('movement-learned-suggestion'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      onPressed: () {
        selectComposerAccount(suggestion.accountId);
        _setViewState(() {
          if (type == 'expense') {
            category = suggestion.category;
            categoryTouched = true;
          }
          learnedSuggestion = null;
        });
      },
      child: Row(
        children: [
          Icon(CupertinoIcons.sparkles, size: 18, color: t.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Usar ${accountPrimaryName(account)}${type == 'expense' ? ' · ${suggestion.category}' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
