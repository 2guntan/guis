import 'package:flutter/material.dart';

import '../../core/model/models.dart';
import '../../core/services.dart';
import '../../core/photos.dart';
import '../../ui/photo_box.dart';
import '../../ui/theme.dart';
import '../fields/field_page.dart';

/// Phrase lue au producteur avant de cocher le consentement (NOTE-CADRAGE.md §7, point 7).
const consentText =
    'Vos nom, téléphone, semences reçues et le contour de vos champs sont enregistrés par la coopérative. '
    'Ils servent au suivi de vos champs par la coopérative et IBRIZ, y compris par images satellite. '
    'Ils ne sont pas vendus ni publiés.';

/// Fiche d'un producteur : identité, consentement, semences reçues et champs.
class ProducerPage extends StatefulWidget {
  const ProducerPage({super.key, required this.services, this.producer});

  final AppServices services;

  /// Null : nouveau producteur.
  final Producer? producer;

  @override
  State<ProducerPage> createState() => _ProducerPageState();
}

class _ProducerPageState extends State<ProducerPage> {
  final _form = GlobalKey<FormState>();
  late final String _id = widget.producer?.id ?? newId();
  late final _lastName = TextEditingController(text: widget.producer?.lastName);
  late final _firstName = TextEditingController(text: widget.producer?.firstName);
  late final _phone = TextEditingController(text: widget.producer?.phone);
  late final _card = TextEditingController(text: widget.producer?.memberCard);
  late String _village = widget.producer?.village ?? '';
  late String? _sex = widget.producer?.sex;
  late DateTime? _consentAt = widget.producer?.consentAt;
  late List<Seed> _seeds = [...?widget.producer?.seeds];
  final List<String> _deletedSeeds = [];
  LocalPhoto? _photo;
  bool _saving = false;

  AppServices get s => widget.services;

  @override
  void dispose() {
    for (final c in [_lastName, _firstName, _phone, _card]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  /// Enregistre le producteur sur le téléphone ; null si le formulaire est incomplet.
  Future<Producer?> _store() async {
    if (!_form.currentState!.validate()) return null;
    if (_consentAt == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cochez le consentement du producteur avant d\'enregistrer.')));
      return null;
    }
    setState(() => _saving = true);
    final p = Producer(
      id: _id,
      lastName: _lastName.text.trim(),
      firstName: _firstName.text.trim(),
      phone: _opt(_phone),
      memberCard: _opt(_card),
      sex: _sex,
      village: _village.trim().isEmpty ? null : _village.trim(),
      photoId: s.producers[_id]?.photoId ?? widget.producer?.photoId,
      consentAt: _consentAt,
      source: widget.producer?.source ?? 'app',
      seeds: _seeds,
    );
    await s.saveProducer(p, deletedSeedIds: [..._deletedSeeds], photo: _photo);
    _deletedSeeds.clear();
    _photo = null;
    if (mounted) setState(() => _saving = false);
    return p;
  }

  Future<void> _save() async {
    if (await _store() == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producteur enregistré sur le téléphone.')));
    Navigator.pop(context);
  }

  /// Ouvre un champ ; un nouveau producteur est d'abord enregistré (le champ part derrière lui).
  Future<void> _openField([Field? field]) async {
    // Le producteur n'est enregistré d'abord que s'il est nouveau ou n'a pas encore donné son consentement
    // (producteur importé) : un producteur déjà enregistré n'est pas renvoyé à chaque champ.
    final saved = s.producers[_id];
    final p = saved != null && saved.consentAt != null ? saved : await _store();
    if (p == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FieldPage(services: s, producer: p, field: field),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _editSeed([Seed? seed]) async {
    final r = await showDialog<Seed>(
      context: context,
      builder: (_) => _SeedDialog(varieties: s.lists.varieties, seed: seed),
    );
    if (r == null) return;
    setState(() {
      final i = _seeds.indexWhere((x) => x.id == r.id);
      if (i >= 0) {
        _seeds[i] = r;
      } else {
        _seeds = [..._seeds, r];
      }
    });
  }

  void _removeSeed(Seed seed) => setState(() {
    _seeds = _seeds.where((x) => x.id != seed.id).toList();
    if (widget.producer?.seeds.any((x) => x.id == seed.id) ?? false) _deletedSeeds.add(seed.id);
  });

  @override
  Widget build(BuildContext context) {
    final rejection = s.rejectionFor(_id);
    return Scaffold(
      appBar: AppBar(title: Text(widget.producer == null ? 'Nouveau producteur' : widget.producer!.fullName)),
      body: Form(
        key: _form,
        child: SingleChildScrollView(
          key: const Key('producer-form'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rejection != null)
                Notice(
                  title: 'Envoi refusé par le serveur',
                  text: '${rejection.lastError ?? ''}\nCorrigez puis enregistrez, ou écartez cette saisie.',
                  actions: [
                    OutlinedButton(
                      onPressed: () async {
                        await s.discard(rejection);
                        setState(() {});
                      },
                      child: const Text('Écarter'),
                    ),
                  ],
                ),
              const _Section('Identité'),
              TextFormField(
                key: const Key('last-name'),
                controller: _lastName,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Nom *'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('first-name'),
                controller: _firstName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Prénom *'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Téléphone', hintText: '77 123 45 67'),
                validator: (v) {
                  final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
                  return d.isEmpty || d.length >= 9 ? null : 'Numéro incomplet';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('member-card'),
                controller: _card,
                decoration: const InputDecoration(labelText: 'Numéro de carte de membre'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'F', label: Text('Femme')),
                  ButtonSegment(value: 'H', label: Text('Homme')),
                ],
                selected: {if (_sex != null) _sex!},
                emptySelectionAllowed: true,
                onSelectionChanged: (v) => setState(() => _sex = v.isEmpty ? null : v.first),
              ),
              const SizedBox(height: 12),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _village),
                optionsBuilder: (v) => s.lists.villages.where((x) => fold(x).contains(fold(v.text))),
                onSelected: (v) => _village = v,
                fieldViewBuilder: (context, controller, focus, onSubmit) => TextFormField(
                  key: const Key('village'),
                  controller: controller,
                  focusNode: focus,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (v) => _village = v,
                  decoration: const InputDecoration(
                    labelText: 'Village / localité',
                    helperText: 'Choisir dans la liste ou saisir un nouveau nom',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              PhotoBox(
                services: s,
                label: 'producer',
                photoId: s.producers[_id]?.photoId ?? widget.producer?.photoId,
                pending: _photo,
                onTaken: (p) => setState(() => _photo = p),
              ),
              const _Section('Consentement'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('À lire au producteur :', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      const Text(consentText),
                      CheckboxListTile(
                        key: const Key('consent'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _consentAt != null,
                        title: const Text('Le producteur a donné son accord'),
                        subtitle: _consentAt == null ? null : Text('Le ${formatDateTime(_consentAt)}'),
                        // Un consentement déjà enregistré sur le serveur ne se retire pas depuis l'app.
                        onChanged: widget.producer?.consentAt != null
                            ? null
                            : (v) => setState(() => _consentAt = v == true ? DateTime.now() : null),
                      ),
                    ],
                  ),
                ),
              ),
              const _Section('Semences reçues'),
              if (_seeds.isEmpty) const Text('Aucune semence notée.', style: TextStyle(color: Colors.black54)),
              for (final seed in _seeds)
                Card(
                  child: ListTile(
                    title: Text('${seed.variety} — ${seed.quantityKg.toStringAsFixed(seed.quantityKg % 1 == 0 ? 0 : 1)} kg'),
                    subtitle: seed.receivedOn == null ? null : Text('Reçue le ${formatDate(seed.receivedOn)}'),
                    onTap: () => _editSeed(seed),
                    trailing: IconButton(tooltip: 'Supprimer', icon: const Icon(Icons.delete_outline), onPressed: () => _removeSeed(seed)),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('add-seed'),
                  onPressed: _editSeed,
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter une semence'),
                ),
              ),
              const _Section('Champs'),
              for (final f in s.fieldsOf(_id))
                Card(
                  child: ListTile(
                    onTap: () => _openField(f),
                    leading: Icon(f.contour.length >= 3 ? Icons.crop_square : Icons.location_off_outlined, color: GuisColors.forest),
                    title: Text(f.name ?? 'Champ'),
                    subtitle: Text(
                      [
                        f.measuredHa == null ? 'Sans contour' : 'Mesurée ${formatHa(f.measuredHa)}',
                        if (f.areaDeclaredHa != null) 'déclarée ${formatHa(f.areaDeclaredHa)}',
                        if (f.sownOn != null) 'semé le ${formatDate(f.sownOn)}',
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('add-field'),
                  onPressed: _saving ? null : () => _openField(),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Ajouter un champ'),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(key: const Key('save-producer'), onPressed: _saving ? null : _save, child: const Text('Enregistrer')),
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

/// Saisie d'une ligne de semence : variété, quantité, date de réception.
class _SeedDialog extends StatefulWidget {
  const _SeedDialog({required this.varieties, this.seed});

  final List<String> varieties;
  final Seed? seed;

  @override
  State<_SeedDialog> createState() => _SeedDialogState();
}

class _SeedDialogState extends State<_SeedDialog> {
  final _form = GlobalKey<FormState>();
  late String _variety = widget.seed?.variety ?? (widget.varieties.length == 1 ? widget.varieties.first : '');
  late final _kg = TextEditingController(
    text: widget.seed == null ? '' : widget.seed!.quantityKg.toString().replaceAll(RegExp(r'\.0$'), ''),
  );
  late DateTime? _date = DateTime.tryParse(widget.seed?.receivedOn ?? '') ?? DateTime.now();

  @override
  void dispose() {
    _kg.dispose();
    super.dispose();
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.seed == null ? 'Semence reçue' : 'Modifier la semence'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _variety),
              optionsBuilder: (v) => widget.varieties.where((x) => fold(x).contains(fold(v.text))),
              onSelected: (v) => _variety = v,
              fieldViewBuilder: (context, controller, focus, _) => TextFormField(
                key: const Key('variety'),
                controller: controller,
                focusNode: focus,
                onChanged: (v) => _variety = v,
                decoration: const InputDecoration(labelText: 'Variété *'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('quantity'),
              controller: _kg,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantité (kg) *'),
              validator: (v) {
                final x = double.tryParse((v ?? '').replaceAll(',', '.'));
                return x == null || x <= 0 ? 'Quantité positive' : null;
              },
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date ?? DateTime.now(),
                  firstDate: DateTime(2025),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _date = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date de réception'),
                child: Text(_date == null ? '—' : formatDate(_iso(_date!))),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          key: const Key('save-seed'),
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              Seed(
                id: widget.seed?.id ?? newId(),
                variety: _variety.trim(),
                quantityKg: double.parse(_kg.text.replaceAll(',', '.')),
                receivedOn: _date == null ? null : _iso(_date!),
              ),
            );
          },
          child: const Text('Valider'),
        ),
      ],
    );
  }
}
