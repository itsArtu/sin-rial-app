part of 'main.dart';

Color homeHeaderColor(RTheme theme) =>
    Color.lerp(theme.bg, theme.accent, theme.dark ? .26 : .10)!;

class HomeWidgetsButton extends StatelessWidget {
  const HomeWidgetsButton({super.key, required this.app});
  final _RialAppState app;

  @override
  Widget build(BuildContext context) => Center(
    child: CupertinoButton(
      key: const ValueKey('home-add-widgets'),
      onPressed: () => app.pushPage(
        context,
        (_) => HomeCustomizePage(app: app, initialTab: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.square_grid_2x2,
            size: 17,
            color: app.theme.accent,
          ),
          const SizedBox(width: 8),
          Text(
            'Agregar widgets',
            style: TextStyle(fontSize: 12, color: app.theme.accent),
          ),
        ],
      ),
    ),
  );
}

class PhoneWidgetsPage extends StatefulWidget {
  const PhoneWidgetsPage({super.key, required this.app});
  final _RialAppState app;
  @override
  State<PhoneWidgetsPage> createState() => _PhoneWidgetsPageState();
}

class _PhoneWidgetsPageState extends State<PhoneWidgetsPage> {
  bool requesting = false;

  Future<void> request(String type) async {
    if (requesting) return;
    setState(() => requesting = true);
    final requested = await NativeStateStore.pinHomeWidget(type);
    if (!mounted) return;
    setState(() => requesting = false);
    if (!requested) {
      showModernNotice(
        context,
        title: 'Agregar widget',
        message: 'El inicio del tel\u00e9fono no permite a\u00f1adirlo desde la app. Puedes buscar Sin Rial en el selector de widgets del tel\u00e9fono.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.app.theme;
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg,
        border: null,
        middle: const Text('Widgets del tel\u00e9fono'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            for (final type in const ['movement', 'USD', 'EUR', 'calculator'])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: CupertinoButton(
                  key: ValueKey('pin-widget-$type'),
                  padding: EdgeInsets.zero,
                  onPressed: requesting ? null : () => request(type),
                  child: RCard(
                    theme: t,
                    child: Row(
                      children: [
                        Icon(
                          type == 'movement'
                              ? CupertinoIcons.arrow_up_arrow_down
                              : type == 'calculator'
                              ? CupertinoIcons.rectangle_grid_2x2
                              : CupertinoIcons.chart_bar,
                          color: t.accent,
                          size: 26,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                type == 'movement'
                                    ? 'Movimientos'
                                    : type == 'USD'
                                    ? 'Tasa del d\u00f3lar'
                                    : type == 'calculator'
                                    ? 'Calculadora'
                                    : 'Tasa del euro',
                                style: TextStyle(
                                  color: t.ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                type == 'movement'
                                    ? 'Ingreso y gasto'
                                    : type == 'calculator'
                                    ? 'USD / EUR / USDT / VES'
                                    : 'BCV - $type / VES',
                                style: TextStyle(color: t.muted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          CupertinoIcons.add_circled,
                          color: t.accent,
                          size: 25,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CircleTool extends StatelessWidget {
  const CircleTool({
    super.key,
    required this.theme,
    required this.icon,
    required this.label,
    this.onTap,
  });
  final RTheme theme;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => material.Tooltip(
    message: label,
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.card,
          border: Border.all(color: theme.border),
        ),
        child: Icon(
          icon,
          size: 21,
          color: onTap == null ? theme.muted : theme.ink,
        ),
      ),
    ),
  );
}

String profileInitials(String name, String surname) {
  final first = name
      .trim()
      .split(RegExp(r'\s+'))
      .first
      .characters
      .take(1)
      .toString();
  final last = surname
      .trim()
      .split(RegExp(r'\s+'))
      .first
      .characters
      .take(1)
      .toString();
  return first.isEmpty && last.isEmpty ? 'SR' : (first + last).toUpperCase();
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.app});
  final _RialAppState app;
  @override
  Widget build(BuildContext context) => material.Tooltip(
    message: 'Editar perfil',
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () => app.pushPage(context, (_) => ProfilePage(app: app)),
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: app.theme.accent.withOpacity(.16),
          border: Border.all(color: app.theme.accent.withOpacity(.35)),
        ),
        child: Text(
          profileInitials(
            app.state['userName']?.toString() ?? '',
            app.state['userLastName']?.toString() ?? '',
          ),
          style: TextStyle(
            color: app.theme.ink,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.app});
  final _RialAppState app;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final TextEditingController name, surname;
  DateTime? birthDate;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(
      text: widget.app.state['userName']?.toString() ?? '',
    );
    surname = TextEditingController(
      text: widget.app.state['userLastName']?.toString() ?? '',
    );
    birthDate = DateTime.tryParse(
      widget.app.state['userBirthDate']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    name.dispose();
    surname.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.app.theme;
    return BudgetFormScaffold(
      app: widget.app,
      title: 'Mi perfil',
      children: [
        Center(
          child: Container(
            width: 76,
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.accent.withOpacity(.14),
            ),
            child: Text(
              profileInitials(name.text, surname.text),
              style: TextStyle(
                color: t.ink,
                fontSize: 26,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        RField(
          theme: t,
          controller: name,
          placeholder: 'Nombre',
          onChanged: (_) => setState(() {}),
        ),
        RField(
          theme: t,
          controller: surname,
          placeholder: 'Apellido',
          onChanged: (_) => setState(() {}),
        ),
        OptionField(
          theme: t,
          label: 'Fecha de nacimiento',
          value: birthDate == null ? 'Sin especificar' : formatDate(birthDate!),
          icon: CupertinoIcons.calendar,
          onTap: () async {
            final date = await appBirthDatePicker(context, t, birthDate);
            if (mounted && date != null) setState(() => birthDate = date);
          },
        ),
        if (birthDate != null)
          CupertinoButton(
            onPressed: () => setState(() => birthDate = null),
            child: Text(
              'Quitar fecha',
              style: TextStyle(color: t.muted, fontSize: 13),
            ),
          ),
      ],
      action: PrimaryActionButton(
        theme: t,
        label: 'Guardar perfil',
        onPressed: () {
          if (name.text.trim().isEmpty) {
            showModernNotice(
              context,
              title: 'Nombre',
              message: 'Escribe tu nombre.',
            );
            return;
          }
          widget.app.mutate(() {
            widget.app.state['userName'] = name.text.trim();
            widget.app.state['userLastName'] = surname.text.trim();
            widget.app.state['userBirthDate'] = birthDate == null
                ? ''
                : isoDate(birthDate!);
          });
          Navigator.pop(context);
        },
      ),
    );
  }
}

class IconGridItem {
  const IconGridItem(this.title, this.icon, this.onTap);
  final String title;
  final IconData icon;
  final VoidCallback onTap;
}

class IconGrid extends StatelessWidget {
  const IconGrid({super.key, required this.theme, required this.items});
  final RTheme theme;
  final List<IconGridItem> items;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final count = box.maxWidth < 340 ? 3 : 4;
      final width = (box.maxWidth - 12 * (count - 1)) / count;
      return Wrap(
        spacing: 12,
        runSpacing: 18,
        children: [
          for (final item in items)
            SizedBox(
              width: width,
              height: 112,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: item.onTap,
                child: Column(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.card,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: theme.border),
                      ),
                      child: Icon(item.icon, color: theme.ink, size: 26),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      item.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        color: theme.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class ModernMenu extends StatelessWidget {
  const ModernMenu({super.key, required this.app});
  final _RialAppState app;
  @override
  Widget build(BuildContext context) {
    void open(Widget page) => app.pushPage(context, (_) => page);
    return AppScroll(
      title: 'Men\u00fa',
      theme: app.theme,
      children: [
        SectionHeader(theme: app.theme, title: 'Gesti\u00f3n financiera'),
        IconGrid(
          theme: app.theme,
          items: [
            IconGridItem(
              'Cuentas',
              CupertinoIcons.creditcard,
              () => open(AccountsPage(app: app)),
            ),
            IconGridItem(
              'Movimientos',
              CupertinoIcons.arrow_up_arrow_down,
              () => open(MovementHistoryPage(app: app)),
            ),
            IconGridItem(
              'Metas y ahorros',
              CupertinoIcons.flag,
              () => open(SavingsPage(app: app)),
            ),
            IconGridItem(
              'Pagar / cobrar',
              CupertinoIcons.person_2,
              () => open(DebtsPage(app: app)),
            ),
          ],
        ),
        SectionHeader(theme: app.theme, title: 'Herramientas'),
        IconGrid(
          theme: app.theme,
          items: [
            IconGridItem(
              'Calculadora',
              CupertinoIcons.plus_slash_minus,
              () => open(CalculatorPage(app: app)),
            ),
            IconGridItem(
              'Tasas de cambio',
              CupertinoIcons.chart_bar,
              () => open(ExchangeRatesPage(app: app)),
            ),
            IconGridItem(
              'Mi perfil',
              CupertinoIcons.person_crop_circle,
              () => open(ProfilePage(app: app)),
            ),
            IconGridItem(
              'Ajustes',
              CupertinoIcons.gear_alt,
              () => open(SettingsPage(app: app)),
            ),
          ],
        ),
        SectionHeader(theme: app.theme, title: 'Personalizaci\u00f3n'),
        IconGrid(
          theme: app.theme,
          items: [
            IconGridItem(
              'Colores',
              CupertinoIcons.paintbrush,
              () => open(SettingsPage(app: app, section: 'Color del tema')),
            ),
            IconGridItem(
              'Apariencia',
              CupertinoIcons.moon,
              () => open(SettingsPage(app: app, section: 'Apariencia')),
            ),
            IconGridItem(
              'Inicio',
              CupertinoIcons.slider_horizontal_3,
              () => open(HomeCustomizePage(app: app)),
            ),
            IconGridItem(
              'Balance',
              CupertinoIcons.chart_pie,
              () => open(SettingsPage(app: app, section: 'Inicio')),
            ),
            IconGridItem(
              'Widgets',
              CupertinoIcons.square_grid_2x2,
              () => open(PhoneWidgetsPage(app: app)),
            ),
          ],
        ),
        const SizedBox(height: 110),
      ],
    );
  }
}

IconData settingsSectionIcon(String section) => switch (section) {
  'Inicio' => CupertinoIcons.house,
  'Recordatorios' => CupertinoIcons.bell,
  'Perfil' => CupertinoIcons.person,
  'Apariencia' => CupertinoIcons.moon,
  'Color del tema' => CupertinoIcons.paintbrush,
  'Seguridad' => CupertinoIcons.lock_shield,
  'Datos' => CupertinoIcons.archivebox,
  _ => CupertinoIcons.gear_alt,
};
List<Widget> settingsPresentation(
  BuildContext context,
  _RialAppState app,
  List<Widget> controls,
  String? selected,
) {
  final groups = <String, List<Widget>>{};
  String group = 'Acerca de';
  for (final control in controls) {
    if (control is SectionHeader) {
      group = control.title;
      continue;
    }
    groups.putIfAbsent(group, () => []).add(control);
  }
  if (selected != null) return groups[selected] ?? [];
  return [
    CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 14),
      onPressed: () => showModernNotice(
        context,
        title: 'Gracias',
        message: 'Gracias a los testers Rams\u00e9s, Gabriel, Kender, Daniel\n\nHecha por Arturo el siuuuu',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sin Rial',
            style: TextStyle(
              color: app.theme.ink,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Versi\u00f3n $_appVersionName',
            key: const ValueKey('app-version'),
            style: TextStyle(color: app.theme.muted, fontSize: 13),
          ),
        ],
      ),
    ),
    SectionHeader(theme: app.theme, title: 'Preferencias'),
    IconGrid(
      theme: app.theme,
      items: [
        for (final key in groups.keys.where(
          (k) => const {'Recordatorios', 'Seguridad', 'Datos'}.contains(k),
        ))
          IconGridItem(
            key == 'Recordatorios' ? 'Avisos' : key,
            settingsSectionIcon(key),
            () => app.pushPage(
              context,
              (_) => SettingsPage(app: app, section: key),
            ),
          ),
      ],
    ),
    SectionHeader(theme: app.theme, title: 'Actualizaciones'),
    ...?groups['Actualizaciones'],
  ];
}

class RingSummary extends StatefulWidget {
  const RingSummary({
    super.key,
    required this.theme,
    required this.parts,
    required this.labels,
    required this.values,
    required this.total,
    this.label = 'Total',
  });
  final RTheme theme;
  final List<RatioPart> parts;
  final List<String> labels, values;
  final String total, label;
  @override
  State<RingSummary> createState() => _RingSummaryState();
}

class _RingSummaryState extends State<RingSummary> {
  int? selected;
  @override
  void didUpdateWidget(covariant RingSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parts != widget.parts) selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final valid = [
      for (var i = 0; i < widget.parts.length; i++)
        if (widget.parts[i].value.isFinite && widget.parts[i].value > 0) i,
    ];
    final t = widget.theme;
    final index = selected != null && selected! < valid.length
        ? valid[selected!]
        : null;
    return LayoutBuilder(
      builder: (context, box) {
        final size = math.min(180.0, box.maxWidth * .48);
        return SizedBox(
          height: size + 22,
          child: Row(
            children: [
              SizedBox(
                width: size,
                height: size,
                child: Semantics(
                  label: 'Distribuci\u00f3n',
                  value: widget.total,
                  child: RepaintBoundary(
                    child: charts.PieChart(
                      charts.PieChartData(
                        centerSpaceRadius: size * .27,
                        sectionsSpace: valid.length > 1 ? 3 : 0,
                        startDegreeOffset: -90,
                        borderData: charts.FlBorderData(show: false),
                        sections: valid.isEmpty
                            ? [
                                charts.PieChartSectionData(
                                  value: 1,
                                  color: t.field,
                                  radius: size * .19,
                                  showTitle: false,
                                ),
                              ]
                            : [
                                for (var p = 0; p < valid.length; p++)
                                  charts.PieChartSectionData(
                                    value: widget.parts[valid[p]].value,
                                    color: widget.parts[valid[p]].color,
                                    radius: size * (selected == p ? .215 : .19),
                                    showTitle: false,
                                  ),
                              ],
                        pieTouchData: charts.PieTouchData(
                          touchCallback: (event, response) {
                            if (!event.isInterestedForInteractions) return;
                            final value =
                                response?.touchedSection?.touchedSectionIndex;
                            setState(
                              () => selected = value != null && value >= 0
                                  ? value
                                  : null,
                            );
                          },
                        ),
                      ),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      index == null ? widget.label : widget.labels[index],
                      style: TextStyle(color: t.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 7),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        index == null ? widget.total : widget.values[index],
                        style: TextStyle(
                          color: t.ink,
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class AccountCurrencyOverview extends StatelessWidget {
  const AccountCurrencyOverview({
    super.key,
    required this.app,
    required this.currency,
  });
  final _RialAppState app;
  final String currency;
  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final accounts =
        app.maps('accounts').where((a) => a['currency'] == currency).toList()
          ..sort(
            (a, b) =>
                numberValue(b['balance']).compareTo(numberValue(a['balance'])),
          );
    final total = accounts.fold<double>(
      0,
      (s, a) => moneyAdd(s, numberValue(a['balance'])),
    );
    final positive = accounts.fold<double>(
      0,
      (s, a) => s + math.max(0, numberValue(a['balance'])),
    );
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg,
        border: null,
        middle: Text('Cuentas en ' + displayCurrency(currency)),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 28),
          children: [
            RingSummary(
              theme: t,
              parts: [
                for (final a in accounts)
                  RatioPart(
                    color: accountColor(a),
                    value: numberValue(a['balance']),
                  ),
              ],
              labels: accounts.map(accountPrimaryName).toList(),
              values: [
                for (final a in accounts)
                  app.secureMoney(numberValue(a['balance']), currency),
              ],
              total: app.secureMoney(total, currency),
            ),
            const SizedBox(height: 20),
            if (currency == 'VES')
              Row(
                children: [
                  for (final code in ['USD', 'EUR', 'USDT'])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: CurrencyConversionPill(
                          theme: t,
                          label: code,
                          value:
                              (code == 'EUR' && app.eurRate <= 0) ||
                                  (code == 'USDT' && app.usdtRate <= 0)
                              ? 'Sin tasa'
                              : app.secureMoney(
                                  app.convertForHome(total, 'VES', code),
                                  code,
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            SectionHeader(theme: t, title: 'Cuentas'),
            if (accounts.isEmpty)
              EmptyCard(theme: t, text: 'No hay cuentas en esta moneda'),
            for (final a in accounts)
              AccountListLine(app: app, account: a, total: positive),
          ],
        ),
      ),
    );
  }
}

class AccountListLine extends StatelessWidget {
  const AccountListLine({
    super.key,
    required this.app,
    required this.account,
    required this.total,
  });
  final _RialAppState app;
  final Map<String, dynamic> account;
  final double total;
  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final color = accountColor(account);
    final balance = numberValue(account['balance']),
        currency = account['currency'].toString();
    final pct = total > 0 && balance >= 0 ? balance / total * 100 : null;
    final value = app.secureMoney(balance, currency);
    final equivalent = currency == 'VES'
        ? ' \u00b7 ' +
              app.secureMoney(app.convertForHome(balance, 'VES', 'USD'), 'USD')
        : '';
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () => app.pushPage(
        context,
        (_) => AccountDetailPage(app: app, account: account),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(
          children: [
            LogoBadge(
              provider: account['provider']?.toString() ?? '',
              theme: t,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    accountPrimaryName(account),
                    maxLines: 2,
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value + equivalent,
                    style: TextStyle(color: t.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: color.withOpacity(.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                pct == null ? '\u2014' : pct.round().toString() + '%',
                style: TextStyle(
                  color: t.dark ? color : Color.lerp(color, t.ink, .35),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(CupertinoIcons.chevron_right, size: 15, color: t.muted),
          ],
        ),
      ),
    );
  }
}

class RateObservation {
  const RateObservation(this.date, this.value);
  final DateTime date;
  final double value;
}

void rememberUsdtQuote(
  Map<String, dynamic> state,
  double value,
  DateTime instant,
) {
  if (!value.isFinite || value <= 0) return;
  final observations = <String, Map<String, dynamic>>{};
  for (final raw
      in (state['usdtRateHistory'] as List? ?? []).whereType<Map>()) {
    final stamp = DateTime.tryParse(raw['date']?.toString() ?? '');
    final amount = numberValue(raw['value']);
    if (stamp != null && amount > 0 && amount.isFinite) {
      observations[isoDate(caracasTime(stamp))] = {
        'date': stamp.toUtc().toIso8601String(),
        'value': amount,
      };
    }
  }
  observations[isoDate(caracasTime(instant))] = {
    'date': instant.toUtc().toIso8601String(),
    'value': value,
  };
  final values = observations.values.toList()
    ..sort((a, b) => a['date'].toString().compareTo(b['date'].toString()));
  state['usdtRateHistory'] = values
      .skip(math.max(0, values.length - 60))
      .toList();
}

List<RateObservation> rateObservations(
  Map<String, dynamic> state,
  String currency,
) {
  if (currency != 'USDT') {
    final currencyEffective =
        state[currency == 'EUR' ? 'eurRateEffectiveDate' : 'rateEffectiveDate']
            ?.toString() ??
        '';
    final effective = currencyEffective.isNotEmpty
        ? currencyEffective
        : state['rateEffectiveDate']?.toString() ?? '';
    return [
      for (final quote in savedBcvSnapshots(state))
        if (quote['effective_date'].toString().compareTo(effective) <= 0)
          RateObservation(
            DateTime.parse(quote['effective_date'] as String),
            numberValue(quote[currency]),
          ),
    ];
  }
  final copy = Map<String, dynamic>.from(state);
  final millis = numberValue(state['usdtLastRateMillis']).toInt();
  if (millis > 0)
    rememberUsdtQuote(
      copy,
      numberValue(state['usdtRate']),
      DateTime.fromMillisecondsSinceEpoch(millis),
    );
  return [
    for (final raw in (copy['usdtRateHistory'] as List? ?? []).whereType<Map>())
      if (DateTime.tryParse(raw['date']?.toString() ?? '') != null &&
          numberValue(raw['value']) > 0)
        RateObservation(
          DateTime.parse(raw['date'].toString()),
          numberValue(raw['value']),
        ),
  ];
}

class RateSparkline extends StatelessWidget {
  const RateSparkline({
    super.key,
    required this.points,
    required this.theme,
    required this.currency,
  });
  final List<RateObservation> points;
  final RTheme theme;
  final String currency;
  @override
  Widget build(BuildContext context) {
    if (points.length < 2)
      return Center(
        child: Text(
          'Sin historial suficiente',
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.muted, fontSize: 10),
        ),
      );
    final line = charts.LineChartBarData(
      spots: [
        for (var i = 0; i < points.length; i++)
          charts.FlSpot(i.toDouble(), points[i].value),
      ],
      color: theme.accent,
      barWidth: 2,
      isCurved: false,
      dotData: const charts.FlDotData(show: false),
      belowBarData: charts.BarAreaData(
        show: true,
        color: theme.accent.withOpacity(.08),
      ),
    );
    return charts.LineChart(
      charts.LineChartData(
        titlesData: const charts.FlTitlesData(show: false),
        gridData: const charts.FlGridData(show: false),
        borderData: charts.FlBorderData(show: false),
        lineBarsData: [line],
        lineTouchData: charts.LineTouchData(
          touchTooltipData: charts.LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => theme.field,
            getTooltipItems: (spots) => [
              for (final spot in spots)
                charts.LineTooltipItem(
                  formatDate(points[spot.spotIndex].date) +
                      '\nBs ' +
                      decimal(spot.y),
                  TextStyle(color: theme.ink, fontSize: 10),
                ),
            ],
          ),
        ),
      ),
      duration: Duration.zero,
    );
  }
}

class ExchangeRatesPage extends StatelessWidget {
  const ExchangeRatesPage({super.key, required this.app});
  final _RialAppState app;
  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final next = nextBcvSnapshot(savedBcvSnapshots(app.state), DateTime.now());
    final difference = app.rate > 0 && app.usdtRate > 0
        ? (app.usdtRate / app.rate - 1) * 100
        : null;
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: t.bg,
        border: null,
        middle: const Text('Tasas de cambio'),
        trailing: CircleTool(
          theme: t,
          icon: CupertinoIcons.refresh,
          label: 'Actualizar tasas',
          onTap: app.rateLoading
              ? null
              : () => app.refreshRate(manual: true, force: true),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            SectionHeader(theme: t, title: 'Evoluci\u00f3n de las tasas'),
            for (final code in ['USD', 'EUR', 'USDT'])
              RateQuoteRow(app: app, currency: code),
            SectionHeader(theme: t, title: 'BCV vs USDT'),
            DebtDetailRow(
              theme: t,
              label: 'BCV (USD)',
              value: app.rate > 0 ? 'Bs ' + decimal(app.rate) : 'Sin tasa',
            ),
            DebtDetailRow(
              theme: t,
              label: 'USDT',
              value: app.usdtRate > 0
                  ? 'Bs ' + decimal(app.usdtRate)
                  : 'Sin tasa',
            ),
            DebtDetailRow(
              theme: t,
              label: 'Diferencia',
              value: difference == null
                  ? 'Sin tasa'
                  : (difference >= 0 ? '+' : '') + decimal(difference) + '%',
              valueColor: t.accent,
            ),
            SectionHeader(theme: t, title: 'Pr\u00f3xima tasa BCV'),
            if (next == null)
              Text('A\u00fan no publicada', style: TextStyle(color: t.muted))
            else ...[
              Text(
                'Vigente desde ' +
                    formatDate(
                      DateTime.parse(next['effective_date'] as String),
                    ),
                style: TextStyle(color: t.muted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              DebtDetailRow(
                theme: t,
                label: 'USD',
                value: 'Bs ' + decimal(numberValue(next['USD'])),
              ),
              DebtDetailRow(
                theme: t,
                label: 'EUR',
                value: 'Bs ' + decimal(numberValue(next['EUR'])),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class RateQuoteRow extends StatelessWidget {
  const RateQuoteRow({super.key, required this.app, required this.currency});
  final _RialAppState app;
  final String currency;
  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final points = rateObservations(app.state, currency);
    final value = currency == 'USD'
        ? app.rate
        : currency == 'EUR'
        ? app.eurRate
        : app.usdtRate;
    final change = points.length > 1
        ? (points.last.value / points[points.length - 2].value - 1) * 100
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                currency == 'USD'
                    ? '\u{1F1FA}\u{1F1F8}'
                    : currency == 'EUR'
                    ? '\u{1F1EA}\u{1F1FA}'
                    : '\u20ae',
                style: TextStyle(fontSize: 25, color: t.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  displayCurrency(currency),
                  style: TextStyle(
                    color: t.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                value > 0 ? 'Bs ' + decimal(value) : 'Sin tasa',
                style: TextStyle(
                  color: t.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 70,
            child: RateSparkline(points: points, theme: t, currency: currency),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$currency / VES',
                style: TextStyle(color: t.muted, fontSize: 11),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      change == null
                          ? 'Sin variaci\u00f3n disponible'
                          : (change >= 0 ? '+' : '') + decimal(change) + '%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: change == null
                            ? t.muted
                            : change >= 0
                            ? t.green
                            : t.red,
                        fontSize: 12,
                      ),
                    ),
                    if (change != null)
                      Text(
                        'vs cotizaci\u00f3n anterior',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: t.muted, fontSize: 10),
                      ),
                  ],
                ),
              ),
            ],
          ),
          RateStatus(
            theme: t,
            state: app.state,
            currency: currency,
            loading: app.rateLoading,
          ),
        ],
      ),
    );
  }
}

class CurrencyEmblem extends StatelessWidget {
  const CurrencyEmblem({super.key, required this.currency, this.size = 24});
  final String currency;
  final double size;
  @override
  Widget build(BuildContext context) {
    final code = {'USD': 'us', 'EUR': 'eu', 'VES': 've'}[currency];
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: code == null
            ? Container(
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF278570),
                ),
                child: Text(
                  '\u20ae',
                  style: TextStyle(
                    color: CupertinoColors.white,
                    fontSize: size * .66,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : ClipOval(
                child: Image.asset(
                  'assets/currencies/$code.png',
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                ),
              ),
      ),
    );
  }
}
