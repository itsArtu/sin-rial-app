part of 'main.dart';

List<String> creditCardTiersForNetwork(String network) => [
  'Standard',
  'Gold',
  'Platinum',
  network == 'mastercard' ? 'Black' : 'Signature',
];

String creditTierForNetwork(String network, String tier) {
  if (network == 'visa' && tier == 'Black') return 'Signature';
  if (network == 'mastercard' && tier == 'Signature') return 'Black';
  return tier;
}

String creditTier(Map<String, dynamic> card) => creditTierForNetwork(
  card['cardNetwork']?.toString() ?? 'visa',
  card['cardTier']?.toString() ?? 'Gold',
);

List<Color> creditNetworkColors(String network, String tier) {
  final visa = network == 'visa';
  return switch (tier) {
    'Standard' =>
      visa
          ? const [Color(0xFF244765), Color(0xFF102D48)]
          : const [Color(0xFFF1F0EC), Color(0xFFC9CFD0)],
    'Platinum' =>
      visa
          ? const [Color(0xFFDFE3E6), Color(0xFFA3ADB5)]
          : const [Color(0xFFBFC5C9), Color(0xFF8E989D)],
    'Black' || 'Signature' =>
      visa
          ? const [Color(0xFF262D36), Color(0xFF0C1118)]
          : const [Color(0xFF383634), Color(0xFF121110)],
    _ =>
      visa
          ? const [Color(0xFFD5B97C), Color(0xFFC9A966)]
          : const [Color(0xFFC8BA8C), Color(0xFFAE995F)],
  };
}

bool creditNetworkLight(String network, String tier) =>
    tier != 'Black' &&
    tier != 'Signature' &&
    !(tier == 'Standard' && network == 'visa');

class BankCardDesign {
  const BankCardDesign(
    this.id,
    this.label,
    this.provider,
    this.colors, {
    this.partner = '',
    this.network = '',
    this.light = false,
  });
  final String id, label, provider, partner, network;
  final List<Color> colors;
  final bool light;
}

const bankCardDesigns = [
  BankCardDesign('venezuela', 'Venezuela', '0102', [
    Color(0xFFE1E5E7),
    Color(0xFFADB7BD),
  ], light: true),
  BankCardDesign('venezolano', 'Venezolano de Crédito', '0104', [
    Color(0xFF1CA1B5),
    Color(0xFF17869D),
  ]),
  BankCardDesign('mercantil', 'Mercantil', '0105', [
    Color(0xFF0D3458),
    Color(0xFF08243F),
  ]),
  BankCardDesign('provincial', 'BBVA Provincial', '0108', [
    Color(0xFF242343),
    Color(0xFF191935),
  ]),
  BankCardDesign('bancaribe', 'Bancaribe', '0114', [
    Color(0xFF13B3B9),
    Color(0xFF00838D),
  ]),
  BankCardDesign('exterior', 'Exterior Nexo', '0115', [
    Color(0xFF152D4C),
    Color(0xFF0E879C),
  ]),
  BankCardDesign('exterior-usd', 'Exterior Divisas', '0115', [
    Color(0xFFF0F1F3),
    Color(0xFFBFC7D0),
  ], light: true),
  BankCardDesign('caroni', 'Caroní', '0128', [
    Color(0xFF164555),
    Color(0xFF102E3A),
  ]),
  BankCardDesign('banesco', 'Banesco', '0134', [
    Color(0xFF004D3C),
    Color(0xFF00382D),
  ]),
  BankCardDesign('sofitasa', 'Sofitasa', '0137', [
    Color(0xFF333231),
    Color(0xFF111313),
  ]),
  BankCardDesign('plaza', 'Banco Plaza', '0138', [
    Color(0xFF292929),
    Color(0xFF141414),
  ]),
  BankCardDesign('bangente', 'Bangente', '0146', [
    Color(0xFFE6ED6C),
    Color(0xFFD4DD59),
  ], light: true),
  BankCardDesign('bfc', 'BFC', '0151', [
    Color(0xFFF9FAFA),
    Color(0xFFD6E1E9),
  ], light: true),
  BankCardDesign('100banco', '100% Banco', '0156', [
    Color(0xFF224C89),
    Color(0xFF173A76),
  ]),
  BankCardDesign('tesoro', 'Banco del Tesoro', '0163', [
    Color(0xFF42B5D9),
    Color(0xFF1C8FBF),
  ]),
  BankCardDesign('agricola', 'Banco Agrícola', '0166', [
    Color(0xFF246341),
    Color(0xFF123F30),
  ]),
  BankCardDesign('bancrecer', 'Bancrecer', '0168', [
    Color(0xFFF7F7F6),
    Color(0xFFE0E1E6),
  ], light: true),
  BankCardDesign('r4', 'R4 Morada', '0169', [
    Color(0xFF6D28A8),
    Color(0xFF46177B),
  ]),
  BankCardDesign('r4-orange', 'R4 Naranja', '0169', [
    Color(0xFFF26921),
    Color(0xFFD94F13),
  ]),
  BankCardDesign('r4-white', 'R4 Blanca', '0169', [
    Color(0xFFFFFFFF),
    Color(0xFFE9EBEE),
  ], light: true),
  BankCardDesign('activo', 'Banco Activo', '0171', [
    Color(0xFFF7F8F8),
    Color(0xFFDCE2E5),
  ], light: true),
  BankCardDesign('bancamiga', 'Bancamiga Débito', '0172', [
    Color(0xFF005986),
    Color(0xFF003B67),
  ]),
  BankCardDesign('bancamiga-usd', 'Bancamiga USD', '0172', [
    Color(0xFF797C80),
    Color(0xFF484B50),
  ]),
  BankCardDesign('banplus', 'Banplus', '0174', [
    Color(0xFF079BD0),
    Color(0xFF9BC84A),
  ]),
  BankCardDesign('bdt', 'Banco Digital de los Trabajadores', '0175', [
    Color(0xFF202266),
    Color(0xFF10134E),
  ]),
  BankCardDesign('banfanb', 'BANFANB', '0177', [
    Color(0xFFFAFCF9),
    Color(0xFFE1EAE1),
  ], light: true),
  BankCardDesign('bnc', 'BNC', '0191', [Color(0xFF253F6A), Color(0xFF10264E)]),
  BankCardDesign('ubii', 'Ubii', 'UBII', [
    Color(0xFF13BFE9),
    Color(0xFF9D25F4),
  ]),
  BankCardDesign('wally', 'Wally', 'WALLY', [
    Color(0xFF5435B4),
    Color(0xFF33217D),
  ]),
  BankCardDesign('zinli', 'Zinli', 'ZINLI', [
    Color(0xFF8854B8),
    Color(0xFF5A2D91),
  ]),
  BankCardDesign('binance', 'Binance', 'BINANCE', [
    Color(0xFF171717),
    Color(0xFF030303),
  ]),
  BankCardDesign('okx', 'OKX', 'OKX', [Color(0xFF424343), Color(0xFF171919)]),
  BankCardDesign('paypal', 'PayPal', 'PAYPAL', [
    Color(0xFF1268AD),
    Color(0xFF04387B),
  ]),
  BankCardDesign('kontigo', 'Kontigo', 'KONTIGO', [
    Color(0xFF28564A),
    Color(0xFF122C26),
  ]),
  BankCardDesign(
    'bnc-soytechno',
    'SoyTechno',
    '0191',
    [Color(0xFF286BA1), Color(0xFF20264E)],
    partner: 'SoyTechno',
    network: 'visa',
  ),
  BankCardDesign(
    'bancamiga-zona',
    'Zona Tech',
    '0172',
    [Color(0xFF2077B6), Color(0xFF173E77)],
    partner: 'Zona Tech',
    network: 'mastercard',
  ),
  BankCardDesign(
    'bancamiga-rio',
    'Río Supermarket',
    '0172',
    [Color(0xFFD5BB6F), Color(0xFFAC8C39)],
    partner: 'Río Supermarket',
    network: 'mastercard',
    light: true,
  ),
];
List<BankCardDesign> designsForBank(String provider, {required bool credit}) =>
    bankCardDesigns
        .where((d) => d.provider == provider && (credit || d.partner.isEmpty))
        .toList();

BankCardDesign? resolveCardDesign(Map<String, dynamic> account) {
  final id = account['cardDesign']?.toString() ?? 'auto';
  if (id == 'generic') return null;
  if (id == 'auto' && isCreditCard(account)) return null;
  final options = designsForBank(
    account['provider']?.toString() ?? '',
    credit: isCreditCard(account),
  );
  for (final design in options) {
    if (design.id == id) return design;
  }
  if (id == 'auto' && account['currency'] == 'USD') {
    for (final design in options) {
      if (design.id.endsWith('-usd')) return design;
    }
  }
  return options.isEmpty ? null : options.first;
}

String cardDesignLabel(String id, String provider, bool credit) {
  if (id == 'generic') return credit ? 'Por franquicia' : 'Clásica';
  for (final d in designsForBank(provider, credit: credit)) {
    if (d.id == id) return d.label;
  }
  return 'Automático · ${shortProviderName(provider)}';
}

class CardDesignPicker extends StatelessWidget {
  const CardDesignPicker({
    super.key,
    required this.theme,
    required this.provider,
    required this.value,
    required this.credit,
    required this.onChanged,
  });
  final RTheme theme;
  final String provider, value;
  final bool credit;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => OptionField(
    key: const ValueKey('card-design-picker'),
    theme: theme,
    label: 'Diseño',
    value: cardDesignLabel(value, provider, credit),
    icon: CupertinoIcons.paintbrush,
    onTap: () => showModernActionSheet(
      context,
      title: 'Diseño de tarjeta',
      actions: [
        ModernSheetAction(
          title: 'Automático',
          subtitle: shortProviderName(provider),
          icon: CupertinoIcons.sparkles,
          selected: value == 'auto',
          onPressed: () => onChanged('auto'),
        ),
        for (final d in designsForBank(provider, credit: credit))
          ModernSheetAction(
            title: d.label,
            icon: CupertinoIcons.creditcard,
            logoProvider: provider,
            selected: value == d.id,
            onPressed: () => onChanged(d.id),
          ),
        ModernSheetAction(
          title: credit ? 'Por franquicia' : 'Clásica',
          subtitle: credit ? 'Visa / Mastercard' : null,
          icon: CupertinoIcons.creditcard,
          selected: value == 'generic',
          onPressed: () => onChanged('generic'),
        ),
      ],
    ),
  );
}

class CardNetworkMark extends StatelessWidget {
  const CardNetworkMark({
    super.key,
    required this.network,
    this.onDark = false,
  });
  final String network;
  final bool onDark;
  @override
  Widget build(BuildContext context) {
    final mark = Image.asset(
      network.startsWith('mastercard')
          ? 'assets/logos/card_mastercard_symbol.png'
          : 'assets/logos/card_visa.png',
      fit: BoxFit.contain,
      cacheWidth: 174,
      color: network == 'visa' && onDark ? CupertinoColors.white : null,
      semanticLabel: network.startsWith('mastercard') ? 'Mastercard' : 'Visa',
    );
    return SizedBox(
      width: 58,
      height: 34,
      child: network == 'mastercard-black'
          ? ColorFiltered(
              colorFilter: const ColorFilter.matrix([
                .15945,
                .5364,
                .05415,
                0,
                64,
                .15945,
                .5364,
                .05415,
                0,
                64,
                .15945,
                .5364,
                .05415,
                0,
                64,
                0,
                0,
                0,
                1,
                0,
              ]),
              child: mark,
            )
          : mark,
    );
  }
}

class BankCardFace extends StatelessWidget {
  const BankCardFace({super.key, required this.account, required this.app});
  final Map<String, dynamic> account;
  final _RialAppState app;
  @override
  Widget build(BuildContext context) {
    final credit = isCreditCard(account);
    if (!credit) return AccountIdentitySurface(account: account, app: app);
    final design = resolveCardDesign(account);
    final tier = creditTier(account);
    final network = account['cardNetwork']?.toString();
    final franchise = credit && design == null;
    final colors =
        design?.colors ??
        (credit
            ? creditNetworkColors(network ?? 'visa', tier)
            : [app.theme.elevated, app.theme.card]);
    final light =
        design?.light ??
        (credit
            ? creditNetworkLight(network ?? 'visa', tier)
            : !app.theme.dark);
    final ink = light ? const Color(0xFF202629) : const Color(0xFFF8FAFC);
    final currency = account['currency']?.toString() ?? 'VES';
    final last = account['lastFour']?.toString() ?? '';
    final balance = numberValue(account['balance']);
    return Semantics(
      label: credit
          ? '${creditNetwork(account)} $tier'
          : 'Cuenta ${accountPrimaryName(account)}',
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
            ),
            child: CustomPaint(
              painter: franchise
                  ? _CreditNetworkPattern(network ?? 'visa', tier, ink)
                  : _BankCardPattern(design?.id ?? 'generic', ink),
              child: Container(
                key: const ValueKey('bank-card-face'),
                constraints: const BoxConstraints(
                  minHeight: 220,
                  maxWidth: 600,
                ),
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        LogoBadge(
                          provider: account['provider']?.toString() ?? '',
                          kind: account['kind']?.toString(),
                          benefitType: account['benefitType']?.toString(),
                          theme: app.theme,
                          size: 30,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            accountPrimaryName(account),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          credit ? tier : currency,
                          style: TextStyle(
                            color: ink.withValues(alpha: .8),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (design?.partner.isNotEmpty ?? false)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          design!.partner,
                          style: TextStyle(
                            color: ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    SizedBox(height: franchise ? 18 : 24),
                    Text(
                      credit ? 'Disponible' : 'Saldo disponible',
                      style: TextStyle(
                        color: ink.withValues(alpha: .8),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        app.secureMoney(
                          credit ? creditAvailable(account) : balance,
                          currency,
                        ),
                        style: TextStyle(
                          color: ink,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      credit
                          ? (balance > 0
                                ? 'Saldo a favor ${app.secureMoney(balance, currency)}'
                                : 'Deuda ${app.secureMoney(creditDebt(account), currency)}')
                          : currency == 'VES' && app.rate > 0
                          ? '${app.secureMoney(moneyConvert(balance, 1, app.rate), 'USD')} BCV'
                          : accountSecondaryName(account),
                      key: credit ? null : const ValueKey('account-detail-bcv'),
                      style: TextStyle(
                        color: ink.withValues(alpha: .85),
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: franchise ? 14 : 22),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (franchise) ...[
                                Row(
                                  children: [
                                    _CardChip(ink: ink),
                                    const SizedBox(width: 10),
                                    _CardContactless(ink: ink),
                                  ],
                                ),
                                const SizedBox(height: 8),
                              ],
                              Text(
                                last.isNotEmpty
                                    ? '•••• $last'
                                    : credit
                                    ? 'Tarjeta de crédito'
                                    : accountSecondaryName(account),
                                style: TextStyle(
                                  color: ink.withValues(alpha: .8),
                                  fontSize: 12,
                                ),
                              ),
                              if (account['cardholderName']
                                      ?.toString()
                                      .trim()
                                      .isNotEmpty ==
                                  true) ...[
                                const SizedBox(height: 4),
                                Text(
                                  account['cardholderName'].toString().trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: ink,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (franchise && network != 'mastercard')
                          Container(
                            width: 88,
                            height: 74,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: tier == 'Gold'
                                    ? const [
                                        Color(0xFFC9AC68),
                                        Color(0xFF917338),
                                      ]
                                    : const [
                                        Color(0xFF49535F),
                                        Color(0xFF182635),
                                      ],
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CardNetworkMark(
                                  network: 'visa',
                                  onDark: true,
                                ),
                                Container(
                                  width: 58,
                                  height: 1,
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  color: CupertinoColors.white.withValues(
                                    alpha: .65,
                                  ),
                                ),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      tier == 'Standard' ? 'Classic' : tier,
                                      maxLines: 1,
                                      style: const TextStyle(
                                        color: CupertinoColors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (franchise)
                          SizedBox(
                            width: 88,
                            height: 74,
                            child: Center(
                              child: CardNetworkMark(
                                network: tier == 'Black'
                                    ? 'mastercard-black'
                                    : network ?? 'visa',
                                onDark: !light,
                              ),
                            ),
                          )
                        else if (credit || network != null)
                          CardNetworkMark(
                            network: network ?? 'visa',
                            onDark: !light,
                          )
                        else
                          _CardContactless(ink: ink),
                      ],
                    ),
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

class _CardChip extends StatelessWidget {
  const _CardChip({required this.ink});
  final Color ink;
  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('card-chip'),
    width: 36,
    height: 27,
    child: CustomPaint(painter: _CardChipPainter(ink)),
  );
}

class _CardChipPainter extends CustomPainter {
  const _CardChipPainter(this.ink);
  final Color ink;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(
      rect.deflate(.5),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF4E8C8),
            Color(0xFFBCAD88),
            Color(0xFFE7DABB),
            Color(0xFFA39678),
          ],
          stops: [0, .4, .65, 1],
        ).createShader(rect),
    );
    final line = Paint()
      ..color = const Color(0xFF736C5B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .65;
    canvas.save();
    canvas.clipRRect(shape);
    final w = size.width, h = size.height;
    final contacts = Path()
      ..moveTo(w * .31, 0)
      ..lineTo(w * .31, h * .20)
      ..lineTo(w * .23, h * .32)
      ..lineTo(0, h * .32)
      ..moveTo(w * .69, 0)
      ..lineTo(w * .69, h * .20)
      ..lineTo(w * .77, h * .32)
      ..lineTo(w, h * .32)
      ..moveTo(0, h * .68)
      ..lineTo(w * .23, h * .68)
      ..lineTo(w * .31, h * .80)
      ..lineTo(w * .31, h)
      ..moveTo(w, h * .68)
      ..lineTo(w * .77, h * .68)
      ..lineTo(w * .69, h * .80)
      ..lineTo(w * .69, h)
      ..moveTo(0, h * .5)
      ..lineTo(w * .31, h * .5)
      ..moveTo(w * .69, h * .5)
      ..lineTo(w, h * .5);
    canvas.drawPath(contacts, line);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .31, h * .20, w * .38, h * .60),
        const Radius.circular(3),
      ),
      line,
    );
    canvas.restore();
    canvas.drawRRect(
      shape,
      Paint()
        ..color = ink.withValues(alpha: .2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .6,
    );
  }

  @override
  bool shouldRepaint(_CardChipPainter old) => old.ink != ink;
}

class _CardContactless extends StatelessWidget {
  const _CardContactless({required this.ink});
  final Color ink;
  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('card-contactless'),
    width: 24,
    height: 28,
    child: CustomPaint(painter: _CardContactlessPainter(ink)),
  );
}

class _CardContactlessPainter extends CustomPainter {
  const _CardContactlessPainter(this.ink);
  final Color ink;
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = ink.withValues(alpha: .88)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;
    for (final radius in [6.0, 10.0, 14.0, 18.0]) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(1, size.height / 2), radius: radius),
        -.65,
        1.3,
        false,
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_CardContactlessPainter old) => old.ink != ink;
}

class _CreditNetworkPattern extends CustomPainter {
  const _CreditNetworkPattern(this.network, this.tier, this.ink);
  final String network, tier;
  final Color ink;
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = ink.withValues(alpha: .10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7;
    if (network == 'mastercard') {
      final center = Offset(size.width * .57, size.height * .83);
      final radius = size.width * .60;
      final dots = Paint()..color = ink.withValues(alpha: .16);
      for (var y = 4.0; y < size.height; y += 4) {
        for (var x = 4.0; x < size.width; x += 4) {
          if ((Offset(x, y) - center).distance < radius) {
            canvas.drawCircle(Offset(x, y), .65, dots);
          }
        }
      }
      canvas.drawArc(
        Rect.fromCircle(
          center: Offset(size.width * 1.45, size.height),
          radius: size.width * .79,
        ),
        math.pi,
        math.pi,
        false,
        Paint()
          ..color = ink.withValues(alpha: .27)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );
    } else {
      final sheen = Path()
        ..moveTo(size.width * .72, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height * .8)
        ..close();
      canvas.drawPath(
        sheen,
        Paint()..color = CupertinoColors.white.withValues(alpha: .045),
      );
      if (tier == 'Standard' || tier == 'Signature') {
        for (var i = 0; i < 5; i++) {
          canvas.drawLine(
            Offset(size.width * .65 + i * 16, 0),
            Offset(size.width + 10, size.height * .5 + i * 24),
            line,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CreditNetworkPattern old) =>
      old.network != network || old.tier != tier || old.ink != ink;
}

// Fixed brand motifs are cached by RepaintBoundary; they never animate per frame.
class _BankCardPattern extends CustomPainter {
  const _BankCardPattern(this.design, this.ink);
  final String design;
  final Color ink;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    void polygon(List<Offset> points, Color color) {
      final path = Path()..addPolygon(points, true);
      canvas.drawPath(path, Paint()..color = color);
    }

    void word(String text, double x, double y, double fontSize, Color color) {
      final p = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(canvas, Offset(x, y));
    }

    switch (design) {
      case 'bnc':
        for (var y = 35.0; y < h + 35; y += 36) {
          for (var x = -12.0; x < w; x += 45) {
            for (var i = 0; i < 5; i++) {
              final a = -.8 + i * .4;
              polygon([
                Offset(x, y),
                Offset(x + math.cos(a) * 42, y - 26 + math.sin(a) * 15),
                Offset(x + 30, y - 30),
              ], ink.withValues(alpha: .055));
            }
          }
        }
      case 'bancamiga':
        final center = Offset(w * .76, h * .57);
        for (var ring = 1; ring < 12; ring++) {
          final radius = ring * 6.5;
          for (var i = 0; i < ring * 6; i++) {
            final a = i * math.pi * 2 / (ring * 6);
            canvas.drawCircle(
              center + Offset(math.cos(a), math.sin(a)) * radius,
              1.1 + ring * .035,
              Paint()..color = const Color(0xFF09B6F0).withValues(alpha: .55),
            );
          }
        }
      case 'banesco':
        for (final p in [
          Offset(w * .48, h * .07),
          Offset(w * .92, h * .48),
          Offset(w * .56, h * 1.1),
        ]) {
          canvas.drawCircle(
            p,
            h * .40,
            Paint()..color = ink.withValues(alpha: .08),
          );
        }
      case 'bancaribe':
        canvas.save();
        canvas.translate(w * .73, h * .60);
        for (var i = 0; i < 4; i++) {
          canvas.rotate(math.pi / 2);
          final path = Path()
            ..moveTo(6, 6)
            ..lineTo(h * .29, 6)
            ..lineTo(6, h * .36)
            ..close();
          canvas.drawPath(
            path.shift(const Offset(1.5, 1.5)),
            Paint()..color = const Color(0xFF005D6B).withValues(alpha: .35),
          );
          canvas.drawPath(
            path,
            Paint()
              ..color = ink.withValues(alpha: .13)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
        }
        canvas.restore();
      case 'venezolano':
      case 'tesoro':
      case 'banplus':
      case 'sofitasa':
        for (var i = 0; i < 8; i++) {
          final x = w * .35 + i * w / 9;
          polygon([
            Offset(x, 0),
            Offset(x + 50, h * .54),
            Offset(x - 40, h),
          ], ink.withValues(alpha: i.isEven ? .07 : .13));
        }
      case 'mercantil':
      case 'bancamiga-usd':
        for (var i = 0; i < 5; i++) {
          canvas.drawArc(
            Rect.fromCenter(
              center: Offset(w * .85, h * .95),
              width: w * .9 + i * 35,
              height: h * .9 + i * 18,
            ),
            -math.pi,
            math.pi * 1.25,
            false,
            Paint()
              ..color = ink.withValues(alpha: .06)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 12,
          );
        }
      case 'bnc-soytechno':
      case 'exterior':
        final line = Paint()
          ..color =
              (design == 'exterior'
                      ? const Color(0xFFB2E6E8)
                      : const Color(0xFF19B9F0))
                  .withValues(alpha: .65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        for (var i = 0; i < 8; i++) {
          final x = w * .37 + i * 30;
          final y = 60.0 + (i % 3) * 28;
          canvas.drawPath(
            Path()
              ..moveTo(x - 45, h)
              ..lineTo(x - 45, y + 22)
              ..lineTo(x, y - 20)
              ..lineTo(x, y - 46),
            line,
          );
          canvas.drawCircle(Offset(x, y - 46), 3, line);
        }
      case 'bancamiga-zona':
        for (var i = 0; i < 14; i++) {
          canvas.drawPath(
            Path()
              ..moveTo(0, h * .8 + i * 4)
              ..quadraticBezierTo(w * .48, h * .27 + i * 3, w, h * .48 + i * 4),
            Paint()
              ..color = const Color(0xFF8DDAFF).withValues(alpha: .14)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
      case 'venezuela':
        const colors = [
          Color(0xFF1380B3),
          Color(0xFFE4BC28),
          Color(0xFFCE1644),
          Color(0xFF85B54A),
          Color(0xFF804F9D),
        ];
        for (var i = 0; i < colors.length; i++) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(w * i / 5 - 8, h * .42 + (i % 3) * 15, w / 4, 35),
              const Radius.circular(4),
            ),
            Paint()..color = colors[i],
          );
        }
      case 'wally':
        for (var i = 0; i < 2; i++) {
          canvas.save();
          canvas.translate(w * .66 + i * 30, h * .54);
          canvas.rotate(math.pi / 4);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(-26, -26, 52, 52),
              const Radius.circular(8),
            ),
            Paint()..color = const Color(0xFFF3A53B).withValues(alpha: .9),
          );
          canvas.restore();
        }
      case 'okx':
        for (var y = 0.0; y < h; y += 13) {
          for (var x = w * .35; x < w; x += 17) {
            final rect = Rect.fromLTWH(x + (y % 26 == 0 ? 5 : 0), y, 12, 10);
            canvas.drawRect(
              rect.shift(const Offset(1, 1)),
              Paint()..color = const Color(0xFF050606).withValues(alpha: .7),
            );
            canvas.drawRect(rect, Paint()..color = ink.withValues(alpha: .045));
          }
        }
      case 'bfc':
      case 'exterior-usd':
        for (var x = 0.0; x < w; x += 9) {
          for (var y = h * .55; y < h; y += 8) {
            canvas.drawCircle(
              Offset(x, y + math.sin(x / 40) * 10),
              1.2,
              Paint()..color = const Color(0xFF8297A8).withValues(alpha: .2),
            );
          }
        }
      case 'bancrecer':
      case 'bdt':
      case 'caroni':
        const colors = [
          Color(0xFFDB7D23),
          Color(0xFF28A5BB),
          Color(0xFFC44489),
          Color(0xFF9EBB38),
        ];
        for (var i = 0; i < 16; i++) {
          canvas.drawPath(
            Path()
              ..moveTo(w * .5 + i * 7, h + 20)
              ..cubicTo(
                w * .1 + i * 8,
                h * .12,
                w * .9,
                h * .6,
                w + 10,
                -20 + i * 8,
              ),
            Paint()
              ..color = colors[i % 4].withValues(
                alpha: design == 'bdt' ? .55 : .20,
              )
              ..style = PaintingStyle.stroke
              ..strokeWidth = .8,
          );
        }
      case 'plaza':
        word('BANCO', w * .32, h * .28, 52, ink.withValues(alpha: .055));
        word('PLAZA', w * .42, h * .55, 52, ink.withValues(alpha: .055));
      case '100banco':
        word('100%', w * .30, h * .28, 83, ink.withValues(alpha: .12));
        canvas.drawRect(
          Rect.fromLTWH(0, h - 5, w, 2),
          Paint()..color = const Color(0xFFDE7825),
        );
      case 'bangente':
        word(
          'G',
          w * .52,
          h * .1,
          h * .9,
          const Color(0xFF51217F).withValues(alpha: .85),
        );
      case 'r4':
      case 'r4-orange':
      case 'r4-white':
        word('R4', w * .5, h * .24, h * .6, ink.withValues(alpha: .1));
      case 'zinli':
        word(
          'Z',
          w * .64,
          h * .14,
          h * .85,
          const Color(0xFF3A146C).withValues(alpha: .5),
        );
      case 'banfanb':
        canvas.drawRect(
          Rect.fromLTWH(0, 0, 10, h),
          Paint()..color = const Color(0xFF194C35),
        );
        canvas.drawRect(
          Rect.fromLTWH(0, h - 14, w, 14),
          Paint()..color = const Color(0xFF194C35),
        );
      case 'binance':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(.5, .5, w - 1, h - 1),
            const Radius.circular(16),
          ),
          Paint()
            ..color = const Color(0xFFF0B90B)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      case 'bancamiga-rio':
        word(
          'Río',
          w * .55,
          h * .22,
          60,
          const Color(0xFF211F17).withValues(alpha: .14),
        );
      default:
        // Minimal identities (Provincial, Ubii) intentionally have no extra motif.
        break;
    }
  }

  @override
  bool shouldRepaint(_BankCardPattern old) =>
      old.design != design || old.ink != ink;
}
