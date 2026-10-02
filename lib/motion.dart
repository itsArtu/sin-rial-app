part of 'main.dart';

class RialMotionTransition extends StatefulWidget {
  const RialMotionTransition({
    super.key,
    required this.animation,
    required this.child,
    this.offset = const Offset(0, .02),
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
      curve: Curves.easeOutCubic,
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
