part of 'main.dart';

abstract final class RialSurface {
  static const radius = 18.0;
  static const sheetRadius = 30.0;
  static BoxDecoration control(RTheme theme, {bool active = false}) =>
      BoxDecoration(
        color: active ? theme.accent.withValues(alpha: .08) : theme.field,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: active ? theme.accent : theme.border),
      );
}

/// One toolbar geometry for every routed page, including large text and tablets.
class RialNavigationBar extends StatelessWidget
    implements ObstructingPreferredSizeWidget {
  const RialNavigationBar({
    super.key,
    this.middle,
    this.leading,
    this.trailing,
    this.backgroundColor,
    this.border,
    this.automaticallyImplyLeading = true,
    this.transitionBetweenRoutes = false,
  });
  final Widget? middle, leading, trailing;
  final Color? backgroundColor;
  final Border? border;
  final bool automaticallyImplyLeading, transitionBetweenRoutes;

  @override
  Size get preferredSize => const Size.fromHeight(64);
  @override
  bool shouldFullyObstruct(BuildContext context) => true;

  @override
  Widget build(BuildContext context) {
    final t = themeFromContext(context);
    final back =
        automaticallyImplyLeading && (ModalRoute.of(context)?.canPop ?? false);
    return ColoredBox(
      color: t.bg,
      child: SafeArea(
        bottom: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: SizedBox(
              height: 64,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    if (leading != null || back) ...[
                      leading ??
                          Container(
                            width: 56,
                            height: 44,
                            decoration: RialSurface.control(t),
                            child: CupertinoNavigationBarBackButton(
                              color: t.ink,
                              previousPageTitle: '',
                            ),
                          ),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: DefaultTextStyle(
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            color: t.ink,
                            fontSize: 19,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          child: middle ?? const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 10),
                      trailing!,
                    ],
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

class RialDialogSurface extends StatelessWidget {
  const RialDialogSurface({
    super.key,
    required this.theme,
    required this.title,
    required this.message,
    required this.actions,
  });
  final RTheme theme;
  final String title, message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: 480,
      maxHeight: math.max(120, MediaQuery.sizeOf(context).height - 96),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(RialSurface.sheetRadius),
      child: Container(
        decoration: BoxDecoration(
          color: theme.card,
          border: Border.all(color: theme.border),
          borderRadius: BorderRadius.circular(RialSurface.sheetRadius),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: theme.ink,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: TextStyle(color: theme.muted, fontSize: 15, height: 1.5),
              ),
              const SizedBox(height: 24),
              ...actions,
            ],
          ),
        ),
      ),
    ),
  );
}

class RialSearchField extends StatelessWidget {
  const RialSearchField({
    super.key,
    required this.theme,
    this.controller,
    required this.placeholder,
    this.onChanged,
  });
  final RTheme theme;
  final TextEditingController? controller;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: CupertinoTextField(
      controller: controller,
      onChanged: onChanged,
      placeholder: placeholder,
      clearButtonMode: OverlayVisibilityMode.editing,
      textInputAction: TextInputAction.search,
      prefix: Padding(
        padding: const EdgeInsets.only(left: 16, right: 8),
        child: Icon(CupertinoIcons.search, color: theme.muted, size: 20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      style: TextStyle(color: theme.ink, fontSize: 15, fontFamily: 'Manrope'),
      placeholderStyle: TextStyle(
        color: theme.muted,
        fontSize: 15,
        fontFamily: 'Manrope',
      ),
      decoration: RialSurface.control(theme),
    ),
  );
}
