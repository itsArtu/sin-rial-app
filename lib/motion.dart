part of 'main.dart';

Color foregroundOn(Color color) => color.computeLuminance() > .42
    ? CupertinoColors.black
    : CupertinoColors.white;

class ChartReveal extends StatelessWidget {
  const ChartReveal({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 650),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (_, value, child) =>
        ClipRect(clipper: _ChartClip(value), child: child),
  );
}

class _ChartClip extends CustomClipper<Rect> {
  const _ChartClip(this.progress);
  final double progress;
  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * progress, size.height);
  @override
  bool shouldReclip(_ChartClip oldClipper) => progress != oldClipper.progress;
}

class RevealMotion extends StatelessWidget {
  const RevealMotion({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (_, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}

class RialMotionTransition extends StatefulWidget {
  const RialMotionTransition({
    super.key,
    required this.animation,
    required this.child,
    this.offset = const Offset(0, .045),
  });

  final Animation<double> animation;
  final Widget child;
  final Offset offset;

  @override
  State<RialMotionTransition> createState() => _RialMotionTransitionState();
}

class _RialMotionTransitionState extends State<RialMotionTransition> {
  late CurvedAnimation _curve;
  late Animation<Offset> _position;

  void _attach() {
    _curve = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOutQuart,
      reverseCurve: Curves.easeInOutCubic,
    );
    _position = Tween(begin: widget.offset, end: Offset.zero).animate(_curve);
  }

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(covariant RialMotionTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation ||
        oldWidget.offset != widget.offset) {
      _curve.dispose();
      _attach();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: _position,
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}

Widget softSheetTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) => RialMotionTransition(animation: animation, child: child);

class PressFeedback extends StatefulWidget {
  const PressFeedback({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  bool pressed = false;

  void setPressed(bool value) {
    if (pressed != value) setState(() => pressed = value);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: widget.onTap != null,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: widget.onTap == null ? null : (_) => setPressed(true),
      onTapUp: widget.onTap == null ? null : (_) => setPressed(false),
      onTapCancel: () => setPressed(false),
      child: AnimatedScale(
        scale: pressed && !MediaQuery.disableAnimationsOf(context) ? .985 : 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    ),
  );
}
