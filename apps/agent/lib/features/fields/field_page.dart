import 'package:flutter/material.dart';

import '../../core/model/models.dart';
import '../../core/services.dart';
import '../../core/photos.dart';
import '../../ui/photo_box.dart';
import '../../ui/theme.dart';
import 'field_walk_page.dart';

/// Fiche d'un champ : tour GPS, surface déclarée, date de semis, irrigation, source d'eau.
class FieldPage extends StatefulWidget {
  const FieldPage({super.key, required this.services, required this.producer, this.field});

  final AppServices services;
  final Producer producer;

  /// Null : nouveau champ.
  final Field? field;

  @override
  State<FieldPage> createState() => _FieldPageState();
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _FieldPageState extends State<FieldPage> {
  final _form = GlobalKey<FormState>();
  late final String _id = widget.field?.id ?? newId();
  late final _name = TextEditingController(text: widget.field?.name ?? 'Champ ${widget.services.fieldsOf(widget.producer.id).length + 1}');
  late final _declared = TextEditingController(text: _num(widget.field?.areaDeclaredHa));
  late List<GpsPoint> _contour = [...?widget.field?.contour];
  late String? _sownOn = widget.field == null ? isoDate(DateTime.now()) : widget.field!.sownOn;
  late String? _irrigation = widget.field?.irrigation;
  late String? _water = widget.field?.waterSource;
  LocalPhoto? _photo;
  bool _saving = false;

  AppServices get s => widget.services;

  static String _num(double? v) => v == null ? '' : v.toString().replaceAll(RegExp(r'\.0$'), '').replaceAll('.', ',');

  @override
  void dispose() {
    _name.dispose();
    _declared.dispose();
    super.dispose();
  }

  Future<void> _walk() async {
    final r = await Navigator.push<List<GpsPoint>>(
      context,
      MaterialPageRoute(
        builder: (_) => FieldWalkPage(name: _name.text.trim().isEmpty ? 'Champ' : _name.text.trim(), initial: _contour),
      ),
    );
    if (r != null) setState(() => _contour = r);
  }

  Future<void> _pickSowing() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_sownOn ?? '') ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: now.add(const Duration(days: 60)),
      helpText: 'Date de semis',
    );
    if (d != null) setState(() => _sownOn = isoDate(d));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final problem = _contour.isEmpty ? null : contourProblem(_contour);
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Contour à reprendre : $problem.')));
      return;
    }
    setState(() => _saving = true);
    await s.saveField(
      Field(
        id: _id,
        producerId: widget.producer.id,
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        contour: _contour,
        serverAreaHa: widget.field?.serverAreaHa,
        areaDeclaredHa: double.tryParse(_declared.text.replaceAll(',', '.')),
        sownOn: _sownOn,
        irrigation: _irrigation,
        waterSource: _water,
        photoId: widget.field?.photoId,
      ),
      photo: _photo,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_contour.isEmpty ? 'Champ enregistré sans contour : revenez faire le tour.' : 'Champ enregistré sur le téléphone.'),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final problem = _contour.isEmpty ? null : contourProblem(_contour);
    final measured = _contour.length >= 3 ? areaHa(_contour) : widget.field?.serverAreaHa;
    final declared = double.tryParse(_declared.text.replaceAll(',', '.'));
    return Scaffold(
      appBar: AppBar(title: Text(widget.field == null ? 'Nouveau champ' : (widget.field!.name ?? 'Champ'))),
      body: Form(
        key: _form,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.producer.fullName, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('field-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nom du champ'),
              ),
              const _Section('Contour'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _contour.isEmpty
                            ? 'Pas encore de contour.'
                            : '${_contour.length} sommets · surface mesurée ${formatHa(measured)} · ${perimeterM(_contour).toStringAsFixed(0)} m de tour',
                        key: const Key('contour-summary'),
                      ),
                      if (problem != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(problem, style: const TextStyle(color: GuisColors.clay)),
                        ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: const Key('walk'),
                        onPressed: _walk,
                        icon: const Icon(Icons.directions_walk),
                        label: Text(_contour.isEmpty ? 'Faire le tour du champ' : 'Reprendre le tour'),
                      ),
                    ],
                  ),
                ),
              ),
              const _Section('Surface et semis'),
              TextFormField(
                key: const Key('declared'),
                controller: _declared,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Surface emblavée déclarée par le producteur (ha)',
                  helperText: measured != null && declared != null && declared > 0
                      ? 'Écart avec la surface mesurée : ${((measured - declared) / declared * 100).toStringAsFixed(0)} %'
                      : null,
                ),
                validator: (v) {
                  if ((v ?? '').trim().isEmpty) return null;
                  final x = double.tryParse(v!.replaceAll(',', '.'));
                  return x == null || x <= 0 ? 'Surface positive en hectares' : null;
                },
              ),
              const SizedBox(height: 12),
              InkWell(
                key: const Key('sown-on'),
                onTap: _pickSowing,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date de semis', suffixIcon: Icon(Icons.event)),
                  child: Text(_sownOn == null ? '—' : formatDate(_sownOn)),
                ),
              ),
              const _Section('Eau'),
              DropdownButtonFormField<String>(
                key: const Key('irrigation'),
                initialValue: s.lists.irrigation.contains(_irrigation) ? _irrigation : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Irrigation'),
                items: [for (final x in s.lists.irrigation) DropdownMenuItem(value: x, child: Text(x))],
                onChanged: (v) => setState(() => _irrigation = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('water'),
                initialValue: s.lists.waterSources.contains(_water) ? _water : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Source d\'eau'),
                items: [for (final x in s.lists.waterSources) DropdownMenuItem(value: x, child: Text(x))],
                onChanged: (v) => setState(() => _water = v),
              ),
              const _Section('Photo du champ'),
              PhotoBox(
                services: s,
                label: 'field',
                photoId: widget.field?.photoId,
                pending: _photo,
                onTaken: (p) => setState(() => _photo = p),
              ),
              const SizedBox(height: 24),
              FilledButton(key: const Key('save-field'), onPressed: _saving ? null : _save, child: const Text('Enregistrer le champ')),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(
      title,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: GuisColors.forest),
    ),
  );
}
