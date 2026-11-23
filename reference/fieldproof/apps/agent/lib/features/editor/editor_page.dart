import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/model/dossier.dart';
import '../../core/photos.dart';
import '../../core/services.dart';
import '../../ui/theme.dart';
import '../consent/consent_step.dart';
import 'farm_need_steps.dart';
import 'identity_steps.dart';
import 'parcels_documents_steps.dart';
import 'summary_step.dart';

/// Les étapes du dossier client ; la section de la complétude renvoie à l'étape.
const _steps = [
  (title: 'Client', icon: Icons.person_outline, section: 'identity'),
  (title: 'Adresse', icon: Icons.home_outlined, section: 'address'),
  (title: 'Exploitation', icon: Icons.agriculture_outlined, section: 'farm'),
  (title: 'Parcelles', icon: Icons.crop_free, section: 'parcels'),
  (title: 'Besoin', icon: Icons.account_balance_outlined, section: 'need'),
  (title: 'Compléments', icon: Icons.playlist_add_check, section: 'extra'),
  (title: 'Pièces', icon: Icons.photo_camera_outlined, section: 'documents'),
  (title: 'Consentement', icon: Icons.draw_outlined, section: 'consent'),
  (title: 'Récapitulatif', icon: Icons.fact_check_outlined, section: 'summary'),
];

/// Saisie d'un dossier client, étape par étape. Tout est enregistré sur le téléphone à
/// chaque changement d'étape, puis mis en file d'envoi (brouillon complet rejouable).
class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.services, required this.dossier, this.initialStep = 0});

  final AgentServices services;
  final Dossier dossier;
  final int initialStep;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late Dossier _d = widget.dossier;
  late int _step = widget.initialStep;
  bool _dirty = false;
  final _scroll = ScrollController();

  AgentServices get s => widget.services;

  @override
  void initState() {
    super.initState();
    s.revision.addListener(_reloadIfClean);
    _locate();
  }

  /// Lieu de la collecte : relevé à l'ouverture d'un dossier neuf, envoyé avec le premier brouillon.
  Future<void> _locate() async {
    if (_d.lat != null || !_d.editable || _d.reference != null) return;
    final pos = await currentPosition(timeLimit: const Duration(seconds: 15));
    if (pos == null || !mounted) return;
    _d
      ..lat = pos.latitude
      ..lng = pos.longitude;
  }

  @override
  void dispose() {
    s.revision.removeListener(_reloadIfClean);
    _scroll.dispose();
    super.dispose();
  }

  /// Après une synchronisation, relit le dossier (statut, pièces envoyées, motif) s'il n'y a pas de saisie en cours.
  Future<void> _reloadIfClean() async {
    if (_dirty) return;
    final fresh = await s.dossier(_d.id);
    if (fresh != null && mounted && !_dirty) setState(() => _d = fresh);
  }

  void _changed({bool saveNow = false}) {
    setState(() => _dirty = true);
    if (saveNow) _save();
  }

  Future<void> _save() async {
    if (!_dirty || !_d.editable) return;
    try {
      await s.saveDraft(_d);
      _dirty = false;
      unawaited(s.sync());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistrement impossible : $e')));
    }
  }

  Future<void> _goTo(int i) async {
    await _save();
    if (!mounted) return;
    setState(() => _step = i.clamp(0, _steps.length - 1));
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _goToSection(String section) {
    final i = _steps.indexWhere((x) => x.section == section);
    _goTo(i < 0 ? 0 : (section == 'farm' && _d.farm['name'] != null ? 3 : i));
  }

  Future<void> _submit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Soumettre le dossier ?'),
        content: const Text('Le dossier passe au superviseur et devient non modifiable sur le téléphone. '
            'La soumission partira dès qu\'il y aura du réseau.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Soumettre')),
        ],
      ),
    );
    if (ok != true) return;
    final tappedAt = DateTime.now();
    _dirty = true;
    await s.submit(_d, tappedAt);
    _dirty = false;
    final report = await s.sync(force: true);
    final fresh = await s.dossier(_d.id);
    if (!mounted) return;
    if (fresh != null) setState(() => _d = fresh);
    final msg = fresh?.status == statusSubmitted
        ? 'Dossier soumis au superviseur.'
        : (fresh?.serverMessage ?? (report?.transientError != null ? 'Hors ligne : la soumission partira dès que possible.' : 'Soumission en file.'));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final config = s.referentials.configFor(_d.lenderOrganizationId);
    final editable = _d.editable;
    final step = _steps[_step];
    Widget body = switch (_step) {
      0 => ClientStep(dossier: _d, onChanged: _changed),
      1 => AddressStep(dossier: _d, services: s, onChanged: _changed),
      2 => FarmStep(dossier: _d, onChanged: _changed),
      3 => ParcelsStep(dossier: _d, onChanged: _changed, editable: editable),
      4 => NeedStep(dossier: _d, onChanged: _changed),
      5 => ExtraFieldsStep(dossier: _d, config: config, lenderName: s.referentials.lenderName(_d.lenderOrganizationId), onChanged: _changed),
      6 => DocumentsStep(dossier: _d, services: s, config: config, editable: editable, onChanged: () => _changed(saveNow: true)),
      7 => ConsentStep(dossier: _d, services: s, config: config, editable: editable, onChanged: () => _changed(saveNow: true)),
      _ => SummaryStep(key: ValueKey('summary-${_d.status}-${_d.submitPending}'), dossier: _d, services: s, config: config, onGoTo: _goToSection, onSubmit: _submit),
    };
    if (!editable && _step < _steps.length - 1) body = IgnorePointer(child: Opacity(opacity: 0.85, child: body));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _save();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_d.displayName, overflow: TextOverflow.ellipsis),
            Text(_d.reference ?? statusLabel(_d.status), style: const TextStyle(fontSize: 13, color: Colors.white70)),
          ]),
        ),
        body: Column(children: [
          Container(
            color: FpColors.forest,
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: _steps.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final selected = i == _step;
                return ChoiceChip(
                  key: Key('step-$i'),
                  avatar: Icon(_steps[i].icon, size: 18, color: selected ? FpColors.forest : Colors.white),
                  label: Text('${i + 1}. ${_steps[i].title}'),
                  labelStyle: TextStyle(color: selected ? FpColors.forest : Colors.white, fontWeight: FontWeight.w600),
                  selected: selected,
                  showCheckmark: false,
                  selectedColor: FpColors.sand,
                  backgroundColor: FpColors.forestDark,
                  side: BorderSide.none,
                  onSelected: (_) => _goTo(i),
                );
              },
            ),
          ),
          if (!editable && _step < _steps.length - 1)
            Container(
              width: double.infinity,
              color: FpColors.sandDeep,
              padding: const EdgeInsets.all(10),
              child: Text(
                _d.submitPending ? 'Soumission en attente : dossier verrouillé.' : 'Dossier ${statusLabel(_d.status).toLowerCase()} : lecture seule.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              key: PageStorageKey('step-$_step'),
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: KeyedSubtree(key: ValueKey('body-$_step'), child: body),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: const BoxDecoration(color: Color(0xFFFBF8F1), border: Border(top: BorderSide(color: FpColors.sandDeep))),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('prev'),
                    onPressed: _step == 0 ? null : () => _goTo(_step - 1),
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Précédent'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('next'),
                    onPressed: _step == _steps.length - 1 ? null : () => _goTo(_step + 1),
                    icon: const Icon(Icons.chevron_right),
                    label: Text(_step == _steps.length - 2 ? 'Récapitulatif' : (step.title == 'Récapitulatif' ? 'Fin' : 'Suivant')),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
