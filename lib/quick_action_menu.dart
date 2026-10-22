part of 'main.dart';

Future<void> showQuickActionMenu(
  BuildContext context, {
  required _RialAppState app,
  List<ModernSheetAction> actions = const [],
  bool debtsOnly = false,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar acciones',
    barrierColor: CupertinoColors.black.withValues(alpha: .35),
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240),
    transitionBuilder: softSheetTransition,
    pageBuilder: (dialog, _, __) => SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, debtsOnly ? 16 : 88),
          child: QuickActionMenu(
            app: app,
            actions: actions,
            debtsOnly: debtsOnly,
            onOpenDebt: (flow) {
              Navigator.of(dialog).pop();
              app.pushPage(
                context,
                (_) => DebtEditorPage(
                  app: app,
                  initialFlow: flow,
                  initialKind: flow == 'lent' || flow == 'credit_sale'
                      ? 'receivable'
                      : 'payable',
                  initialParty: flow == 'financing' ? 'Cashea' : 'Alguien',
                  initialInstallments: flow == 'financing',
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

class QuickActionMenu extends StatefulWidget {
  const QuickActionMenu({
    super.key,
    required this.app,
    required this.actions,
    required this.debtsOnly,
    required this.onOpenDebt,
  });
  final _RialAppState app;
  final List<ModernSheetAction> actions;
  final bool debtsOnly;
  final ValueChanged<String> onOpenDebt;

  @override
  State<QuickActionMenu> createState() => _QuickActionMenuState();
}

class _QuickActionMenuState extends State<QuickActionMenu> {
  late bool debts = widget.debtsOnly;

  @override
  Widget build(BuildContext context) {
    final t = widget.app.theme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return Container(
      key: const ValueKey('quick-action-popover'),
      width: 308,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .68,
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: .2),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: AnimatedSize(
        duration: duration,
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (debts && !widget.debtsOnly)
                    CupertinoButton(
                      padding: const EdgeInsets.all(10),
                      onPressed: () => setState(() => debts = false),
                      child: Icon(
                        CupertinoIcons.chevron_left,
                        size: 18,
                        color: t.accent,
                        semanticLabel: 'Volver a acciones',
                      ),
                    )
                  else
                    const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      debts ? 'Nuevo Cobrar/Pagar' : 'Crear',
                      style: TextStyle(
                        color: t.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.all(10),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Icon(
                      CupertinoIcons.xmark,
                      color: t.muted,
                      size: 18,
                      semanticLabel: 'Cerrar acciones',
                    ),
                  ),
                ],
              ),
              AnimatedSwitcher(
                duration: duration,
                child: Column(
                  key: ValueKey(debts),
                  mainAxisSize: MainAxisSize.min,
                  children: debts
                      ? [
                          _row(
                            t,
                            CupertinoIcons.person_add,
                            'Presté dinero',
                            'lent',
                          ),
                          _row(
                            t,
                            CupertinoIcons.creditcard,
                            'Fiado',
                            'credit_sale',
                          ),
                          _row(
                            t,
                            CupertinoIcons.person_2,
                            'Me prestaron dinero',
                            'borrowed',
                          ),
                          _row(
                            t,
                            CupertinoIcons.cart,
                            'Financiamiento',
                            'financing',
                          ),
                        ]
                      : [
                          for (final action in widget.actions)
                            _item(t, action.icon, action.title, () {
                              Navigator.of(context).pop();
                              Future<void>.microtask(action.onPressed);
                            }),
                          _item(
                            t,
                            CupertinoIcons.calendar,
                            'Cobrar/Pagar',
                            () => setState(() => debts = true),
                            submenu: true,
                          ),
                        ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(RTheme t, IconData icon, String label, String flow) =>
      _item(t, icon, label, () => widget.onOpenDebt(flow));

  Widget _item(
    RTheme t,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool submenu = false,
  }) => PressFeedback(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: t.accent, size: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: TextStyle(color: t.ink, fontSize: 14)),
          ),
          if (submenu)
            Icon(CupertinoIcons.chevron_right, color: t.muted, size: 14),
        ],
      ),
    ),
  );
}
