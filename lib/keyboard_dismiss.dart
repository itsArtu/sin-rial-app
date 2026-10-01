part of 'main.dart';

// Keep Android's predictive back inside the current route while the IME is open.
class KeyboardDismissScope extends StatefulWidget {
  const KeyboardDismissScope({super.key, required this.child});
  final Widget child;
  @override
  State<KeyboardDismissScope> createState() => _KeyboardDismissScopeState();
}

class _KeyboardDismissScopeState extends State<KeyboardDismissScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final visible = View.of(context).viewInsets.bottom > 0;
    return PopScope(
      canPop: !visible,
      onPopInvokedWithResult: (popped, result) {
        if (!popped && visible) {
          FocusManager.instance.primaryFocus?.unfocus();
          unawaited(
            SystemChannels.textInput.invokeMethod<void>('TextInput.hide'),
          );
        }
      },
      child: widget.child,
    );
  }
}
