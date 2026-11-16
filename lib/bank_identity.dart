part of 'main.dart';

class AccountIdentitySurface extends StatelessWidget {
  const AccountIdentitySurface({
    super.key,
    required this.account,
    required this.app,
  });
  final Map<String, dynamic> account;
  final _RialAppState app;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final cash = isCashAccount(account) || account['provider'] == 'cash';
    final design = resolveCardDesign(account);
    final currency = account['currency']?.toString() ?? 'VES';
    final balance = numberValue(account['balance']);
    final ink = design?.light == true
        ? const Color(0xFF203039)
        : CupertinoColors.white;
    return Column(
      key: ValueKey(cash ? 'cash-account-surface' : 'bank-account-surface'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cash)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 22),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: t.green.withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.money_dollar_circle,
                    color: t.green,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    accountPrimaryName(account),
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          RepaintBoundary(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 1.9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: design?.colors ?? [t.elevated, t.card],
                    ),
                  ),
                  child: CustomPaint(
                    painter: _BankCardPattern(design?.id ?? 'generic', ink),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              LogoBadge(
                                provider: account['provider']?.toString() ?? '',
                                theme: t,
                                size: 30,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  shortProviderName(
                                    account['provider']?.toString() ?? '',
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: ink,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              _CardChip(ink: ink),
                              const SizedBox(width: 12),
                              _CardContactless(ink: ink),
                              const Spacer(),
                              Text(
                                currency,
                                style: TextStyle(
                                  color: ink,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          cash ? 'Efectivo disponible' : 'Saldo disponible',
          style: TextStyle(color: t.muted, fontSize: 13),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            app.secureMoney(balance, currency),
            style: TextStyle(
              color: t.ink,
              fontSize: 34,
              fontWeight: FontWeight.w700,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          currency == 'VES' && app.rate > 0
              ? '${app.secureMoney(moneyConvert(balance, 1, app.rate), 'USD')} BCV'
              : cash
              ? displayCurrency(currency)
              : accountSecondaryName(account),
          key: const ValueKey('account-detail-bcv'),
          style: TextStyle(color: t.muted, fontSize: 14),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
