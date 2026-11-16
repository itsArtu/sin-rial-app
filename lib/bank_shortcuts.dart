part of 'main.dart';

const bankAppPackages = <String, String>{
  '0102': 'com.bancodevenezuela.bdvdigital',
  '0104': 'com.venezolano.vol_app',
  '0105': 'com.mercantilbanco.mercantilmovil',
  '0108': 'com.totaltexto.bancamovil',
  '0114': 'bancaribe.miconexion',
  '0128': 'com.click.caroni.normal.app.click',
  '0134': 'com.banesco.samfbancamovilunificada',
  '0172': 'com.bancamiga',
  '0174': 'com.asociadosgerenciales.banpluspay',
  '0191': 'bnc.bncnet.mobile2',
  'UBII': 'ubii.ubiipagos.com.ubiiapp',
  'ZINLI': 'com.zinli.app',
  'WALLY': 'com.kinpos.wallytech',
};

class BankShortcutButton extends StatefulWidget {
  const BankShortcutButton({
    super.key,
    required this.app,
    required this.account,
  });
  final _RialAppState app;
  final Map<String, dynamic> account;
  @override
  State<BankShortcutButton> createState() => _BankShortcutButtonState();
}

class _BankShortcutButtonState extends State<BankShortcutButton> {
  bool busy = false;

  void unavailable() {
    if (mounted)
      showModernNotice(
        context,
        title: 'Acceso al banco',
        message: 'No se pudo abrir la app ni Google Play. Intenta de nuevo.',
      );
  }

  Future<void> open() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final current =
          widget.app.accountById(widget.account['id'].toString()) ??
          widget.account;
      final provider = current['provider']?.toString() ?? '';
      final opened = await _storeChannel.invokeMethod<bool>(
        'openBankAppOrStore',
        {
          // Only verified packages: a backup cannot redirect a bank shortcut.
          'package': bankAppPackages[provider],
          'query': providerName(provider),
        },
      );
      if (opened != true) unavailable();
    } on PlatformException {
      unavailable();
    } on MissingPluginException {
      unavailable();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isCashAccount(widget.account) ||
        widget.account['provider'] == 'cash' ||
        isCestaticketFood(widget.account))
      return const SizedBox.shrink();
    final t = widget.app.theme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: AccountQuickActionButton(
        theme: t,
        label:
            'Abrir app de ${shortProviderName(widget.account['provider'].toString())}',
        icon: CupertinoIcons.arrow_up_right_square,
        color: t.accent,
        onTap: open,
      ),
    );
  }
}
