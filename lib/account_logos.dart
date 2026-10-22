part of 'main.dart';

class LogoBadge extends StatelessWidget {
  const LogoBadge({
    super.key,
    required this.provider,
    required this.theme,
    this.size = 44,
    this.benefitType,
    this.kind,
  });
  final String provider;
  final RTheme theme;
  final double size;
  final String? benefitType;
  final String? kind;

  @override
  Widget build(BuildContext context) {
    final code = provider.trim().toUpperCase();
    final asset = logoAsset(code);
    final benefit = code == 'CESTATICKET' || kind == 'benefit';
    final cash = code == 'CASH' || kind == 'cash';
    final bank = kind == 'national' || banks.any((bank) => bank.first == code);
    final icon = cash
        ? material.Icons.payments_outlined
        : benefit
        ? material.Icons.card_giftcard
        : bank
        ? material.Icons.account_balance_outlined
        : material.Icons.account_balance_wallet_outlined;
    final color = benefit ? theme.amber : theme.accent;
    final fullBleed = const {
      'CASHEA',
      'KRECE',
      'OKX',
      'ZINLI',
      'UBII',
    }.contains(code);
    final inset = fullBleed
        ? 0.0
        : benefit
        ? .06
        : .14;
    final label = benefit && benefitType != null
        ? 'Cestaticket ${benefitType == 'integral' ? 'Integral' : 'Alimentaci\u00f3n'}'
        : cash
        ? 'Efectivo'
        : shortProviderName(code);
    // Decode to a bounded physical size; never cache full bank artwork for a badge.
    final decodeSize = (size * MediaQuery.devicePixelRatioOf(context))
        .ceil()
        .clamp(32, 256);
    final fallback = Icon(icon, size: size * .58, color: color);
    return Semantics(
      label: label,
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                key: ValueKey('account-logo-$code'),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: asset == null
                      ? color.withValues(alpha: theme.dark ? .15 : .09)
                      : CupertinoColors.white,
                  shape: BoxShape.circle,
                  border: fullBleed
                      ? null
                      : Border.all(color: theme.border, width: .5),
                ),
                padding: EdgeInsets.all(size * inset),
                child: asset == null
                    ? fallback
                    : Image.asset(
                        asset,
                        fit: BoxFit.contain,
                        cacheWidth: decodeSize,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, _, _) => fallback,
                      ),
              ),
            ),
            if (benefit && benefitType != null)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: theme.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.border, width: .7),
                  ),
                  child: Icon(
                    benefitType == 'integral'
                        ? material.Icons.swap_horiz
                        : material.Icons.restaurant_outlined,
                    color: theme.ink,
                    size: size * .30,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
