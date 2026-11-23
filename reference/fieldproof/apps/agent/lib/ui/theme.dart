import 'package:flutter/material.dart';

import '../core/model/dossier.dart';

/// Identité Fieldproof : vert forêt profond, fond sable chaud, accent ocre.
class FpColors {
  static const forest = Color(0xFF1F4D3A);
  static const forestDark = Color(0xFF15362A);
  static const sand = Color(0xFFF4EEE1);
  static const sandDeep = Color(0xFFE9DFCB);
  static const ochre = Color(0xFFC8892B);
  static const clay = Color(0xFFB4442F);
  static const ink = Color(0xFF1E2420);
  static const sky = Color(0xFF2F6E8E);
}

ThemeData fieldproofTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: FpColors.forest,
    primary: FpColors.forest,
    onPrimary: Colors.white,
    secondary: FpColors.ochre,
    onSecondary: Colors.white,
    tertiary: FpColors.sky,
    error: FpColors.clay,
    surface: const Color(0xFFFBF8F1),
    onSurface: FpColors.ink,
  );
  const radius = BorderRadius.all(Radius.circular(14));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: FpColors.sand,
    appBarTheme: const AppBarTheme(
      backgroundColor: FpColors.forest,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
    ),
    cardTheme: const CardThemeData(
      color: Color(0xFFFFFDF8),
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: FpColors.sandDeep)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: radius),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: FpColors.sandDeep)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: FpColors.forest, width: 2)),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        foregroundColor: FpColors.forest,
        side: const BorderSide(color: FpColors.forest),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: FpColors.ochre, foregroundColor: Colors.white),
    checkboxTheme: CheckboxThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? FpColors.forest : null)),
    chipTheme: const ChipThemeData(shape: StadiumBorder()),
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
  );
}

Color statusColor(String status) => switch (status) {
      statusDraft => FpColors.sky,
      statusSubmitted => FpColors.forest,
      statusReturned => FpColors.clay,
      statusSent => FpColors.ochre,
      _ => Colors.grey,
    };

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.pending = false});

  final String status;

  /// Soumission en attente d'envoi.
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final label = pending ? 'Soumission en attente' : statusLabel(status);
    final color = pending ? FpColors.ochre : statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: color)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}

/// Un encadré de message (motif de renvoi, refus du serveur).
class Notice extends StatelessWidget {
  const Notice({super.key, required this.title, required this.text, this.color = FpColors.clay, this.icon = Icons.report_outlined, this.actions});

  final String title;
  final String text;
  final Color color;
  final IconData icon;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: color, width: 5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15))),
          ]),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(fontSize: 15)),
          if (actions != null) Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 8, runSpacing: 8, children: actions!)),
        ]),
      );
}

String formatDateTime(DateTime? t) {
  if (t == null) return '—';
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

String formatDate(String? iso) {
  final t = DateTime.tryParse(iso ?? '');
  if (t == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}/${t.year}';
}

String formatXof(num? v) {
  if (v == null) return '—';
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '$b FCFA';
}

String formatHa(num? v) => v == null ? '—' : '${v.toStringAsFixed(2).replaceAll('.', ',')} ha';
