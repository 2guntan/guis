import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/theme.dart';

/// Titre de section dans une étape.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.subtitle});

  final String text;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: FpColors.forest)),
          if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, style: const TextStyle(color: Colors.black54))),
        ]),
      );
}

/// Champ texte lié à une valeur ; [onChanged] reçoit le texte brut.
class FpText extends StatelessWidget {
  const FpText({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.keyboard,
    this.hint,
    this.required = false,
    this.digitsOnly = false,
    this.maxLines = 1,
    this.capitalization = TextCapitalization.sentences,
  });

  final String label;
  final String? value;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboard;
  final String? hint;
  final bool required;
  final bool digitsOnly;
  final int maxLines;
  final TextCapitalization capitalization;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          initialValue: value,
          keyboardType: keyboard,
          maxLines: maxLines,
          textCapitalization: capitalization,
          inputFormatters: digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
          decoration: InputDecoration(labelText: required ? '$label *' : label, hintText: hint),
          onChanged: onChanged,
        ),
      );
}

/// Liste déroulante liée à une valeur.
class FpSelect<T> extends StatelessWidget {
  const FpSelect({super.key, required this.label, required this.value, required this.items, required this.onChanged, this.required = false});

  final String label;
  final T? value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;
  final bool required;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<T>(
          key: ValueKey('$label-$value-${items.length}'),
          initialValue: items.containsKey(value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: required ? '$label *' : label),
          items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
          onChanged: onChanged,
        ),
      );
}

/// Choix exclusif en boutons (sexe, oui/non…) : de grandes cibles au doigt.
class FpChoice extends StatelessWidget {
  const FpChoice({super.key, required this.label, required this.value, required this.items, required this.onChanged, this.required = false});

  final String label;
  final String? value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;
  final bool required;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(required ? '$label *' : label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in items.entries)
              ChoiceChip(
                label: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: Text(e.value, style: const TextStyle(fontSize: 15))),
                selected: value == e.key,
                selectedColor: FpColors.forest.withValues(alpha: 0.18),
                onSelected: (_) => onChanged(e.key),
              ),
          ]),
        ]),
      );
}

/// Date (ISO `aaaa-mm-jj`), choisie au calendrier.
class FpDate extends StatelessWidget {
  const FpDate({super.key, required this.label, required this.value, required this.onChanged, this.required = false, this.first, this.last});

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool required;
  final DateTime? first;
  final DateTime? last;

  @override
  Widget build(BuildContext context) {
    final current = DateTime.tryParse(value ?? '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: current ?? DateTime(DateTime.now().year - (last == null ? 30 : 0)),
            firstDate: first ?? DateTime(1920),
            lastDate: last ?? DateTime(2100),
            initialEntryMode: DatePickerEntryMode.input,
            locale: const Locale('fr'),
          );
          if (picked != null) {
            onChanged('${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: required ? '$label *' : label,
            suffixIcon: current == null
                ? const Icon(Icons.calendar_today_outlined)
                : IconButton(icon: const Icon(Icons.clear), tooltip: 'Effacer', onPressed: () => onChanged(null)),
          ),
          child: Text(current == null ? 'Choisir' : formatDate(value), style: TextStyle(color: current == null ? Colors.black45 : null, fontSize: 16)),
        ),
      ),
    );
  }
}

num? parseNumber(String s) {
  final t = s.replaceAll(RegExp(r'[\s ]'), '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  return num.tryParse(t);
}
