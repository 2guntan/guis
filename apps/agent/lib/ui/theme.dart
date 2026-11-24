import 'package:flutter/material.dart';

/// Couleurs de docs/design/SPECS.md (maquettes V1). Reprises de Fieldproof puis ajustées.
class GuisColors {
  static const forest = Color(0xFF1F4D3A);
  static const forestDark = Color(0xFF163A2C);
  static const sand = Color(0xFFF4EEE1);
  static const sandDeep = Color(0xFFE9DFCB);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1E2420);
  static const muted = Color(0xFF5A635D);
  static const ochre = Color(0xFFC8892B);
  static const ochreSoft = Color(0xFFF5E9D3);
  static const ochreText = Color(0xFF8A5F14);
  static const clay = Color(0xFFB4442F);
  static const claySoft = Color(0xFFF3DED8);
  static const clayText = Color(0xFF8C3320);
  static const sky = Color(0xFF2F6B8E);
  static const skySoft = Color(0xFFDCE7EE);
  static const skyText = Color(0xFF24526D);
  static const forestSoft = Color(0xFFDDE6DF);
}

/// Échelle typographique Android (SPECS.md) : Fraunces 600 pour titres et gros chiffres, Geist pour le reste.
class GuisText {
  static const _display = 'Fraunces';
  static const _body = 'Geist';

  static const screenTitle = TextStyle(
    fontFamily: _display,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );
  static const sectionTitle = TextStyle(
    fontFamily: _display,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
    color: GuisColors.ink,
  );
  static const bigNumber = TextStyle(
    fontFamily: _display,
    fontSize: 26,
    height: 32 / 26,
    fontWeight: FontWeight.w600,
    color: GuisColors.ink,
  );
  static const listName = TextStyle(fontFamily: _body, fontSize: 18, height: 24 / 18, fontWeight: FontWeight.w600, color: GuisColors.ink);
  static const read = TextStyle(fontFamily: _body, fontSize: 16, height: 24 / 16, color: GuisColors.ink);
  static const body = TextStyle(fontFamily: _body, fontSize: 16, height: 24 / 16, color: GuisColors.ink);
  static const button = TextStyle(fontFamily: _body, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w600);
  static const secondary = TextStyle(fontFamily: _body, fontSize: 14, height: 20 / 14, color: GuisColors.muted);
  static const label = TextStyle(fontFamily: _body, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, color: GuisColors.ink);
}

ThemeData guisTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: GuisColors.forest,
    primary: GuisColors.forest,
    onPrimary: Colors.white,
    secondary: GuisColors.ochre,
    onSecondary: GuisColors.ink,
    tertiary: GuisColors.sky,
    error: GuisColors.clay,
    surface: GuisColors.surface,
    onSurface: GuisColors.ink,
  );
  const radius = BorderRadius.all(Radius.circular(12));
  OutlineInputBorder border(Color c, [double w = 1.5]) => OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: c, width: w),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Geist',
    scaffoldBackgroundColor: GuisColors.sand,
    textTheme: const TextTheme(
      bodyLarge: GuisText.body,
      bodyMedium: GuisText.body,
      bodySmall: GuisText.secondary,
      titleMedium: GuisText.listName,
      labelLarge: GuisText.button,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: GuisColors.forest,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 64,
      titleTextStyle: TextStyle(fontFamily: 'Fraunces', fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w600, color: Colors.white),
    ),
    cardTheme: const CardThemeData(
      color: GuisColors.surface,
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      hintStyle: const TextStyle(color: GuisColors.muted),
      border: border(GuisColors.sandDeep),
      enabledBorder: border(GuisColors.sandDeep),
      focusedBorder: border(GuisColors.forest, 2),
      errorBorder: border(GuisColors.clay),
      focusedErrorBorder: border(GuisColors.clay, 2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      floatingLabelBehavior: FloatingLabelBehavior.never,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: GuisColors.forest,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 52),
        textStyle: GuisText.button,
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        foregroundColor: GuisColors.forest,
        backgroundColor: Colors.white,
        side: const BorderSide(color: GuisColors.forest, width: 1.5),
        textStyle: GuisText.button,
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: GuisColors.forest, minimumSize: const Size(48, 48), textStyle: GuisText.button),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: GuisColors.ochre,
      foregroundColor: GuisColors.ink,
      extendedTextStyle: GuisText.button,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? GuisColors.forest : null),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(6))),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? GuisColors.forest : null),
    ),
    dividerTheme: const DividerThemeData(color: GuisColors.sandDeep, space: 1, thickness: 1),
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
  );
}

enum ChipTone { ochre, clay, sky, forest, neutral }

/// Pastille d'état : un point et un mot, jamais la couleur seule (« À envoyer », « Refusé »…).
class StateChip extends StatelessWidget {
  const StateChip(this.label, {super.key, this.tone = ChipTone.ochre});

  final String label;
  final ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, dot, fg) = switch (tone) {
      ChipTone.ochre => (GuisColors.ochreSoft, GuisColors.ochre, GuisColors.ochreText),
      ChipTone.clay => (GuisColors.claySoft, GuisColors.clay, GuisColors.clayText),
      ChipTone.sky => (GuisColors.skySoft, GuisColors.sky, GuisColors.skyText),
      ChipTone.forest => (GuisColors.forestSoft, GuisColors.forest, GuisColors.forest),
      ChipTone.neutral => (GuisColors.sandDeep, GuisColors.muted, GuisColors.ink),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

/// Encadré de message : « reste à faire » (ocre), refus (argile), information (bleu).
class Notice extends StatelessWidget {
  const Notice({super.key, required this.title, required this.text, this.tone = ChipTone.clay, this.icon, this.actions});

  final String title;
  final String text;
  final ChipTone tone;
  final IconData? icon;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg) = switch (tone) {
      ChipTone.ochre => (GuisColors.ochreSoft, GuisColors.ochre, GuisColors.ochreText),
      ChipTone.sky => (GuisColors.skySoft, GuisColors.sky, GuisColors.skyText),
      _ => (GuisColors.claySoft, GuisColors.clay, GuisColors.clayText),
    };
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(16),
      // Refus et information : barre à gauche ; « reste à faire » (ocre) : cadre complet.
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: tone == ChipTone.ochre ? Border.all(color: border, width: 1.5) : Border(left: BorderSide(color: border, width: 6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[Icon(icon, color: fg, size: 22), const SizedBox(width: 8)],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(fontSize: 16, height: 1.45, color: GuisColors.ink)),
          if (actions != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(spacing: 8, runSpacing: 8, children: actions!),
            ),
        ],
      ),
    );
  }
}

/// Titre de section en Fraunces 18.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Row(
      children: [
        Expanded(child: Text(title, style: GuisText.sectionTitle)),
        ?trailing,
      ],
    ),
  );
}

/// Libellé au-dessus d'un champ (toujours visible).
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: GuisText.label.copyWith(color: color)),
  );
}

/// Bouton principal fixé en bas d'un formulaire, avec sa légende.
class BottomAction extends StatelessWidget {
  const BottomAction({super.key, required this.button, this.caption = 'Gardée sur le téléphone, envoyée avec le réseau'});

  final Widget button;
  final String? caption;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: GuisColors.sand,
      border: Border(top: BorderSide(color: GuisColors.sandDeep)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            button,
            if (caption != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(caption!, textAlign: TextAlign.center, style: GuisText.secondary),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Bloc blanc arrondi qui regroupe des lignes (semences, champs).
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: GuisColors.surface, borderRadius: BorderRadius.circular(20)),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, c) in children.indexed) ...[if (i > 0) const Divider(height: 1), c],
      ],
    ),
  );
}

/// Logo Guis (docs/design/fondations.png) : carré vert forêt, soleil ocre sur l'horizon, sillons.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _LogoPainter()),
  );
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 64;
    canvas.scale(k);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 64, 64), const Radius.circular(14)),
      Paint()..color = GuisColors.forest,
    );
    final stroke = Paint()
      ..color = GuisColors.sand
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dome = Path()
      ..moveTo(11, 34)
      ..cubicTo(17, 23, 25, 19, 32, 19)
      ..cubicTo(39, 19, 47, 23, 53, 34)
      ..close();
    canvas.drawPath(dome, stroke);
    canvas.drawCircle(const Offset(32, 22.5), 6.5, Paint()..color = GuisColors.ochre);
    canvas.drawLine(const Offset(17, 42), const Offset(47, 42), stroke);
    canvas.drawLine(const Offset(24, 49.5), const Offset(40, 49.5), stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String formatDateTime(DateTime? t) {
  if (t == null) return '—';
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} à ${two(l.hour)}:${two(l.minute)}';
}

String formatDate(String? iso) {
  final t = DateTime.tryParse(iso ?? '');
  if (t == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}/${t.year}';
}

String formatNumber(num v, {int decimals = 2}) {
  final s = v.toStringAsFixed(decimals).replaceAll('.', ',');
  return decimals > 0 ? s.replaceAll(RegExp(r',?0+$'), '') : s;
}

String formatHa(num? v) => v == null ? '—' : '${v.toStringAsFixed(2).replaceAll('.', ',')} ha';

String formatKg(num v) => '${formatNumber(v, decimals: 1)} kg';
