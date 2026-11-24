import 'package:flutter/material.dart';

import '../../core/model/models.dart';
import '../../core/photos.dart';
import '../../core/services.dart';
import '../../ui/format.dart';
import '../../ui/photo_box.dart';
import '../../ui/theme.dart';
import '../fields/field_page.dart';

/// Phrase lue au producteur avant de cocher le consentement (NOTE-CADRAGE.md §7, maquette android/03).
const consentText =
    'La coopérative enregistre votre nom, votre téléphone et le contour de votre champ pour suivre la campagne '
    'par satellite. Ces informations ne sont pas vendues. Êtes-vous d\'accord ?';

/// Fiche d'un producteur (maquettes android/03, 03a, 03b).
/// Un producteur déjà enregistré s'ouvre en **consultation** (ce qui reste à faire, champs, semences,
/// consentement, identité résumée) ; « Modifier » ou un nouveau producteur ouvrent la **saisie**.
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
  final _consentKey = GlobalKey();
  late final String _id = widget.producer?.id ?? newId();
  late final _lastName = TextEditingController(text: widget.producer?.lastName);
  late final _firstName = TextEditingController(text: widget.producer?.firstName);
  late final _phone = TextEditingController(text: formatPhone(widget.producer?.phone));
  late final _card = TextEditingController(text: widget.producer?.memberCard);
  late String _village = widget.producer?.village ?? '';
  late String? _sex = widget.producer?.sex;
  late DateTime? _consentAt = widget.producer?.consentAt;
  late List<Seed> _seeds = [...?widget.producer?.seeds];
  final List<String> _deletedSeeds = [];
  LocalPhoto? _photo;
  bool _saving = false;
  bool _consentMissing = false;
  late bool _editing = widget.producer == null || widget.services.rejectionFor(widget.producer!.id) != null;

  AppServices get s => widget.services;
  Producer? get _saved => s.producers[_id];

  @override
  void dispose() {
    for (final c in [_lastName, _firstName, _phone, _card]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  /// Enregistre le producteur sur le téléphone ; null si la fiche est incomplète.
  Future<Producer?> _store() async {
    if (_editing && !_form.currentState!.validate()) return null;
    if (_consentAt == null) {
      setState(() => _consentMissing = true);
      final ctx = _consentKey.currentContext;
      if (ctx != null) await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), alignment: 0.2);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Cochez le consentement du producteur avant d\'enregistrer.')));
      }
      return null;
    }
    setState(() => _saving = true);
    final base = _saved ?? widget.producer;
    final p = Producer(
      id: _id,
      lastName: _lastName.text.trim(),
      firstName: _firstName.text.trim(),
      phone: _opt(_phone),
      memberCard: _opt(_card),
      sex: _sex,
      village: _village.trim().isEmpty ? null : _village.trim(),
      photoId: base?.photoId,
      consentAt: _consentAt,
      source: base?.source ?? 'app',
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fiche enregistrée sur le téléphone.')));
    Navigator.pop(context);
  }

  /// Ouvre un champ ; le producteur n'est enregistré d'abord que s'il est nouveau ou n'a pas encore donné son
  /// consentement (producteur importé) : un producteur déjà enregistré n'est pas renvoyé à chaque champ.
  Future<void> _openField([Field? field]) async {
    final saved = _saved;
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
      _seeds = i >= 0 ? ([..._seeds]..[i] = r) : [..._seeds, r];
    });
  }

  void _removeSeed(Seed seed) => setState(() {
    _seeds = _seeds.where((x) => x.id != seed.id).toList();
    if (widget.producer?.seeds.any((x) => x.id == seed.id) ?? false) _deletedSeeds.add(seed.id);
  });

  @override
  Widget build(BuildContext context) {
    final rejection = s.rejectionFor(_id);
    final p = _saved ?? widget.producer;
    final fields = s.fieldsOf(_id);
    final noContour = fields.where((f) => f.contour.length < 3).toList();
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: _editing || p == null ? 64 : 76,
        title: p == null
            ? const Text('Nouveau producteur')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.fullName, style: GuisText.screenTitle.copyWith(fontSize: 20, color: Colors.white)),
                  if (!_editing && [p.village, p.memberCard].any((x) => x != null))
                    Text(
                      [p.village, if (p.memberCard != null) 'carte n° ${p.memberCard}'].whereType<String>().join(' · '),
                      style: const TextStyle(fontFamily: 'Geist', fontSize: 14, fontWeight: FontWeight.w400, color: Color(0xFFD9E3DC)),
                    ),
                ],
              ),
      ),
      bottomNavigationBar: BottomAction(
        button: FilledButton(key: const Key('save-producer'), onPressed: _saving ? null : _save, child: const Text('Enregistrer la fiche')),
      ),
      body: Form(
        key: _form,
        child: SingleChildScrollView(
          key: const Key('producer-form'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rejection != null)
                Notice(
                  title: 'Refusé par le serveur',
                  text: '${rejection.lastError ?? ''}\nCorrigez puis enregistrez à nouveau, ou écartez cette saisie.',
                  icon: Icons.warning_amber_rounded,
                  actions: [
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: GuisColors.clay),
                      onPressed: () async {
                        await s.discard(rejection);
                        setState(() {});
                      },
                      child: const Text('Écarter'),
                    ),
                  ],
                ),
              if (!_editing) ...[
                if (p?.consentAt == null)
                  Notice(
                    tone: ChipTone.ochre,
                    title: 'Reste à faire : le consentement',
                    text: 'Lisez le texte au producteur, puis cochez son accord plus bas.',
                    actions: [
                      FilledButton(
                        onPressed: () => Scrollable.ensureVisible(_consentKey.currentContext!, duration: const Duration(milliseconds: 250)),
                        child: const Text('Recueillir le consentement'),
                      ),
                    ],
                  )
                else if (noContour.isNotEmpty)
                  Notice(
                    tone: ChipTone.ochre,
                    title: 'Reste à faire : ${noContour.length} contour${noContour.length > 1 ? 's' : ''}',
                    text:
                        '${noContour.first.name ?? 'Un champ'} n\'a pas encore de contour GPS. Sans contour, il ne sera pas suivi par satellite.',
                    actions: [
                      FilledButton.icon(
                        onPressed: () => _openField(noContour.first),
                        icon: const Icon(Icons.directions_walk),
                        label: Text('Faire le tour : ${noContour.first.name ?? 'champ'}'),
                      ),
                    ],
                  ),
                ..._fieldsSection(fields),
                ..._seedsSection(),
                _consentSection(),
                _identitySummary(p!),
              ] else ...[
                ..._identityForm(),
                const SectionTitle('Photo (facultative)'),
                PhotoBox(
                  services: s,
                  label: 'producer',
                  photoId: p?.photoId,
                  pending: _photo,
                  onTaken: (ph) => setState(() => _photo = ph),
                ),
                _consentSection(),
                ..._seedsSection(),
                ..._fieldsSection(fields),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _identityForm() => [
    const SectionTitle('Identité'),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FieldLabel('Nom'),
              TextFormField(
                key: const Key('last-name'),
                controller: _lastName,
                textCapitalization: TextCapitalization.characters,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FieldLabel('Prénom'),
              TextFormField(
                key: const Key('first-name'),
                controller: _firstName,
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
              ),
            ],
          ),
        ),
      ],
    ),
    const SizedBox(height: 16),
    const FieldLabel('Téléphone'),
    TextFormField(
      key: const Key('phone'),
      controller: _phone,
      keyboardType: TextInputType.phone,
      decoration: const InputDecoration(hintText: '77 123 45 67'),
      validator: (v) {
        final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
        return d.isEmpty || d.length >= 9 ? null : 'Numéro incomplet';
      },
    ),
    const SizedBox(height: 16),
    const FieldLabel('Carte de membre'),
    TextFormField(key: const Key('member-card'), controller: _card),
    const SizedBox(height: 16),
    SizedBox(
      height: 52,
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'F', label: Text('Femme')),
          ButtonSegment(value: 'H', label: Text('Homme')),
        ],
        selected: {?_sex},
        emptySelectionAllowed: true,
        showSelectedIcon: true,
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: GuisColors.forest,
          selectedForegroundColor: Colors.white,
          backgroundColor: Colors.white,
          foregroundColor: GuisColors.forest,
          side: const BorderSide(color: GuisColors.forest, width: 1.5),
          textStyle: GuisText.button,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onSelectionChanged: (v) => setState(() => _sex = v.isEmpty ? null : v.first),
      ),
    ),
    const SizedBox(height: 16),
    const FieldLabel('Village'),
    Autocomplete<String>(
      initialValue: TextEditingValue(text: _village),
      optionsBuilder: (v) {
        final q = fold(v.text.trim());
        if (q.isEmpty) return const Iterable<String>.empty();
        final matches = s.lists.villages.where((x) => fold(x).contains(q)).toList();
        if (!s.lists.villages.any((x) => fold(x) == q)) matches.add('+ Ajouter le village « ${v.text.trim()} »');
        return matches;
      },
      displayStringForOption: (o) => o.startsWith('+ Ajouter le village « ') ? o.substring(23, o.length - 2) : o,
      onSelected: (v) => _village = v.startsWith('+ Ajouter le village « ') ? v.substring(23, v.length - 2) : v,
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextFormField(
        key: const Key('village'),
        controller: controller,
        focusNode: focus,
        textCapitalization: TextCapitalization.words,
        onChanged: (v) => _village = v,
      ),
    ),
  ];

  Widget _consentSection() {
    final done = _consentAt != null;
    final locked = (_saved ?? widget.producer)?.consentAt != null;
    final error = _consentMissing && !done;
    return Container(
      key: _consentKey,
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: GuisColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: error ? Border.all(color: GuisColors.clay, width: 1.5) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Consentement', style: GuisText.sectionTitle),
          const SizedBox(height: 8),
          const Text('Lisez ce texte au producteur :', style: GuisText.secondary),
          const SizedBox(height: 6),
          const Text(consentText, style: GuisText.read),
          const SizedBox(height: 12),
          Material(
            color: done ? GuisColors.forestSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: CheckboxListTile(
              key: const Key('consent'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              controlAffinity: ListTileControlAffinity.leading,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: BorderSide(color: error ? GuisColors.clay : GuisColors.forest, width: 2),
              value: done,
              title: const Text('Le producteur est d\'accord', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
              subtitle: done ? Text('Noté le ${formatDateTime(_consentAt)}', style: GuisText.secondary) : null,
              // Un consentement déjà enregistré ne se retire pas depuis l'app.
              onChanged: locked ? null : (v) => setState(() => _consentAt = v == true ? DateTime.now() : null),
            ),
          ),
          if (error)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Lisez le texte au producteur, puis cochez son accord pour enregistrer.',
                style: TextStyle(color: GuisColors.clay, fontSize: 15),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _seedsSection() => [
    const SectionTitle('Semences reçues'),
    GroupCard(
      children: [
        for (final seed in _seeds)
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(20, 6, 4, 6),
            title: Text('${seed.variety}, ${formatKg(seed.quantityKg)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
            subtitle: seed.receivedOn == null ? null : Text('Reçue le ${formatDate(seed.receivedOn)}', style: GuisText.secondary),
            onTap: () => _editSeed(seed),
            trailing: PopupMenuButton<String>(
              tooltip: 'Actions',
              onSelected: (v) => v == 'edit' ? _editSeed(seed) : _removeSeed(seed),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Modifier')),
                PopupMenuItem(value: 'delete', child: Text('Supprimer')),
              ],
            ),
          ),
        _AddRow(key: const Key('add-seed'), label: 'Ajouter une semence reçue', onTap: _editSeed),
      ],
    ),
  ];

  List<Widget> _fieldsSection(List<Field> fields) => [
    const SectionTitle('Champs'),
    GroupCard(
      children: [
        for (final f in fields)
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            onTap: () => _openField(f),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: f.contour.length >= 3 ? GuisColors.forestSoft : GuisColors.ochreSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                f.contour.length >= 3 ? Icons.pentagon_outlined : Icons.border_clear,
                color: f.contour.length >= 3 ? GuisColors.forest : GuisColors.ochreText,
              ),
            ),
            title: Text(f.name ?? 'Champ', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
            subtitle: f.contour.length >= 3
                ? Text(
                    [
                      '${formatHa(f.measuredHa)}${f.areaDeclaredHa != null ? ' (déclaré : ${formatNumber(f.areaDeclaredHa!)} ha)' : ''}',
                      if (f.sownOn != null) 'Semé le ${formatDate(f.sownOn)}',
                    ].join('\n'),
                    style: GuisText.secondary.copyWith(fontSize: 15),
                  )
                : Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Contour à relever',
                          style: TextStyle(color: GuisColors.ochreText, fontWeight: FontWeight.w500),
                        ),
                        if (f.areaDeclaredHa != null) TextSpan(text: '\nDéclaré : ${formatNumber(f.areaDeclaredHa!)} ha'),
                      ],
                    ),
                    style: GuisText.secondary.copyWith(fontSize: 15),
                  ),
            trailing: const Icon(Icons.chevron_right),
          ),
        _AddRow(key: const Key('add-field'), label: 'Ajouter un champ', onTap: _saving ? null : () => _openField()),
      ],
    ),
  ];

  Widget _identitySummary(Producer p) {
    final file = s.localPhoto(p.photoId);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('Identité'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: GuisColors.surface, borderRadius: BorderRadius.circular(20)),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: GuisColors.forestSoft,
                  backgroundImage: file != null ? FileImage(file) : null,
                  child: file == null ? const Icon(Icons.photo_camera_outlined, color: GuisColors.forest) : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p.fullName}${p.sex == null
                            ? ''
                            : p.sex == 'F'
                            ? ', femme'
                            : ', homme'}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
                      ),
                      if (p.phone != null) Text(formatPhone(p.phone), style: GuisText.secondary.copyWith(fontSize: 15)),
                      Text(p.photoId == null ? 'Pas encore de photo' : 'Photo enregistrée', style: GuisText.secondary),
                    ],
                  ),
                ),
                TextButton(
                  key: const Key('edit-identity'),
                  onPressed: () => setState(() => _editing = true),
                  child: const Text('Modifier'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          const Icon(Icons.add, color: GuisColors.forest),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(color: GuisColors.forest, fontWeight: FontWeight.w600, fontSize: 17),
          ),
        ],
      ),
    ),
  );
}

/// Saisie d'une ligne de semence : variété, quantité, date de réception (maquette android/04).
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
  late final _kg = TextEditingController(text: widget.seed == null ? '' : formatNumber(widget.seed!.quantityKg, decimals: 1));
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
      backgroundColor: const Color(0xFFF8F6F0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text(widget.seed == null ? 'Semence reçue' : 'Modifier la semence', style: GuisText.screenTitle.copyWith(fontSize: 24)),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FieldLabel('Variété'),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _variety),
                optionsBuilder: (v) => widget.varieties.where((x) => fold(x).contains(fold(v.text))),
                onSelected: (v) => _variety = v,
                fieldViewBuilder: (context, controller, focus, _) => TextFormField(
                  key: const Key('variety'),
                  controller: controller,
                  focusNode: focus,
                  onChanged: (v) => _variety = v,
                  decoration: const InputDecoration(suffixIcon: Icon(Icons.expand_more)),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const FieldLabel('Quantité'),
                        TextFormField(
                          key: const Key('quantity'),
                          controller: _kg,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(suffixText: 'kg'),
                          validator: (v) {
                            final x = double.tryParse((v ?? '').replaceAll(',', '.'));
                            return x == null || x <= 0 ? 'Quantité positive' : null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const FieldLabel('Reçue le'),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
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
                            decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today_outlined, size: 20)),
                            child: Text(_date == null ? '—' : formatDate(_iso(_date!)), maxLines: 1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          key: const Key('save-seed'),
          style: FilledButton.styleFrom(minimumSize: const Size(120, 52)),
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
          child: Text(widget.seed == null ? 'Ajouter' : 'Enregistrer'),
        ),
      ],
    );
  }
}
