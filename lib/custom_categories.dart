part of 'main.dart';

const customCategoryIcons = <String, IconData>{
  'Etiqueta': CupertinoIcons.tag,
  'Casa': CupertinoIcons.house_fill,
  'Comida': CupertinoIcons.cart_fill,
  'Transporte': CupertinoIcons.bus,
  'Moto': material.Icons.two_wheeler,
  'Deportes': material.Icons.sports_soccer,
  'Juegos': material.Icons.sports_esports,
  'Música': CupertinoIcons.music_note,
  'Cine': CupertinoIcons.film,
  'Viajes': CupertinoIcons.airplane,
  'Salud': CupertinoIcons.heart_fill,
  'Educación': CupertinoIcons.book_fill,
  'Regalos': CupertinoIcons.gift_fill,
  'Compras': CupertinoIcons.bag_fill,
  'Café': material.Icons.local_cafe,
  'Trabajo': CupertinoIcons.briefcase_fill,
  'Servicios': CupertinoIcons.lightbulb_fill,
  'Internet': CupertinoIcons.wifi,
  'Ahorro': CupertinoIcons.money_dollar_circle_fill,
  'Herramientas': CupertinoIcons.wrench_fill,
  'Fotografía': CupertinoIcons.camera_fill,
  'Naturaleza': material.Icons.park,
  'Mascotas': CupertinoIcons.paw_solid,
  'Otros': CupertinoIcons.ellipsis_circle_fill,
};

List<String> categoryChoices(BuildContext context, {String? selected}) => [
  ...budgetCategories,
  for (final item in RThemeScope.categoriesOf(context))
    if (item['archived'] != true && item['name'] is String)
      item['name'] as String,
  if (selected != null &&
      selected.isNotEmpty &&
      !budgetCategories.contains(selected) &&
      !RThemeScope.categoriesOf(context)
          .any((item) => item['name'] == selected && item['archived'] != true))
    selected,
];

void saveCustomCategory(
  _RialAppState app,
  Map<String, dynamic> entry, {
  String? editingId,
}) {
  final name = entry['name']?.toString().trim() ?? '';
  final key = _categorySearchText(name);
  final current = app.maps('customCategories');
  if (key.isEmpty ||
      name.length > 40 ||
      canonicalCategory(name) != name ||
      budgetCategories.any((value) => _categorySearchText(value) == key) ||
      current.any(
        (item) =>
            item['id'] != editingId &&
            _categorySearchText(item['name'].toString()) == key,
      )) {
    throw const FormatException('Usa un nombre único de hasta 40 caracteres');
  }
  if (!customCategoryIcons.containsKey(entry['icon'])) {
    throw const FormatException('Selecciona un icono');
  }
  final previous = current.where((item) => item['id'] == editingId).firstOrNull;
  if (editingId != null && previous == null)
    throw const FormatException('La categoría ya no existe');
  final words = (entry['keywords'] as List? ?? [])
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();
  if (words.length > 20 || words.any((value) => value.length > 60)) {
    throw const FormatException(
      'Máximo 20 palabras o frases de hasta 60 caracteres',
    );
  }
  app.mutate(() {
    final list = app.rawList('customCategories');
    final saved = {
      ...entry,
      'id': editingId ?? app.id(),
      'name': name,
      'keywords': words,
    };
    if (previous == null) {
      list.add(saved);
    } else {
      list[list.indexWhere((item) => item is Map && item['id'] == editingId)] =
          saved;
      // Category names are the existing relation key in movements and budgets.
      for (final collection in ['movements', 'budgets', 'recurringMovements']) {
        for (final item in app.rawList(collection).whereType<Map>()) {
          if (item['category'] == previous['name']) item['category'] = name;
        }
      }
    }
  });
}

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key, required this.app});
  final _RialAppState app;

  @override
  Widget build(BuildContext context) {
    final t = app.theme;
    final entries = app.maps('customCategories');
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        middle: const Text('Categorías'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () =>
              app.pushPage(context, (_) => CustomCategoryEditor(app: app)),
          child: const Icon(
            CupertinoIcons.add,
            semanticLabel: 'Nueva categoría',
          ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            SectionHeader(theme: t, title: 'Personalizadas'),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Sin categorías personalizadas',
                  style: TextStyle(color: t.muted),
                ),
              ),
            for (final entry in entries)
              OptionField(
                theme: t,
                label: entry['archived'] == true
                    ? 'Archivada'
                    : 'Personalizada',
                value: entry['name'].toString(),
                icon: customCategoryIcons[entry['icon']] ?? CupertinoIcons.tag,
                onTap: () => app.pushPage(
                  context,
                  (_) => CustomCategoryEditor(app: app, entry: entry),
                ),
              ),
            SectionHeader(theme: t, title: 'Generales'),
            for (final category in budgetCategories)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(categoryIcon(category), color: t.accent, size: 22),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(category, style: TextStyle(color: t.ink)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CustomCategoryEditor extends StatefulWidget {
  const CustomCategoryEditor({super.key, required this.app, this.entry});
  final _RialAppState app;
  final Map<String, dynamic>? entry;
  @override
  State<CustomCategoryEditor> createState() => _CustomCategoryEditorState();
}

class _CustomCategoryEditorState extends State<CustomCategoryEditor> {
  late final name = TextEditingController(
    text: widget.entry?['name']?.toString(),
  );
  late final keywords = TextEditingController(
    text: (widget.entry?['keywords'] as List? ?? []).join(', '),
  );
  late String selectedIcon = widget.entry?['icon']?.toString() ?? 'Etiqueta';
  @override
  void dispose() {
    name.dispose();
    keywords.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.app.theme;
    return CupertinoPageScaffold(
      backgroundColor: t.bg,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        middle: Text(
          widget.entry == null ? 'Nueva categoría' : 'Editar categoría',
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            RField(theme: t, controller: name, placeholder: 'Nombre'),
            RField(
              theme: t,
              controller: keywords,
              placeholder: 'Palabras clave, separadas por comas',
            ),
            SectionHeader(theme: t, title: 'Icono'),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final entry in customCategoryIcons.entries)
                  material.Tooltip(
                    message: entry.key,
                    child: Semantics(
                      label: entry.key,
                      selected: selectedIcon == entry.key,
                      child: CupertinoButton(
                        key: ValueKey('category-icon-${entry.key}'),
                        color: selectedIcon == entry.key
                            ? t.accent.withOpacity(.2)
                            : t.card,
                        borderRadius: BorderRadius.circular(8),
                        padding: EdgeInsets.zero,
                        onPressed: () =>
                            setState(() => selectedIcon = entry.key),
                        child: Icon(
                          entry.value,
                          color: selectedIcon == entry.key ? t.accent : t.muted,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            PrimaryActionButton(
              theme: t,
              label: 'Guardar categoría',
              onPressed: () {
                try {
                  saveCustomCategory(widget.app, {
                    ...?widget.entry,
                    'name': name.text,
                    'icon': selectedIcon,
                    'keywords': keywords.text.split(','),
                  }, editingId: widget.entry?['id']?.toString());
                  Navigator.pop(context);
                } on FormatException catch (error) {
                  showModernNotice(
                    context,
                    title: 'Categoría',
                    message: error.message,
                  );
                }
              },
            ),
            if (widget.entry != null) ...[
              const SizedBox(height: 12),
              SecondaryActionButton(
                theme: t,
                label: widget.entry!['archived'] == true
                    ? 'Restaurar categoría'
                    : 'Archivar categoría',
                onPressed: () {
                  saveCustomCategory(widget.app, {
                    ...widget.entry!,
                    'archived': widget.entry!['archived'] != true,
                  }, editingId: widget.entry!['id'].toString());
                  Navigator.pop(context);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
