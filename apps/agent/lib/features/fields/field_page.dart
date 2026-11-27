import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/limits.dart';
import '../../core/model/models.dart';
import '../../core/photos.dart';
import '../../core/services.dart';
import '../../ui/confirm.dart';
import '../../ui/dates.dart';
import '../../ui/photo_box.dart';
import '../../ui/theme.dart';
import 'field_walk_page.dart';

/// Fiche d'un champ (maquette android/05) : contour, surface déclarée, semis, irrigation, source d'eau, photo.
class FieldPage extends StatefulWidget {
  const FieldPage({super.key, required this.services, required this.producer, this.field, this.draft});

  final AppServices services;
  final Producer producer;

  /// Null : nouveau champ.
  final Field? field;

  /// Saisie interrompue à reprendre (app arrêtée par Android pendant l'appareil photo ou le tour).
  final Map<String, dynamic>? draft;

  @override
  State<FieldPage> createState() => _FieldPageState();
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _FieldPageState extends State<FieldPage> {
  final _form = GlobalKey<FormState>();
  late final String _id = widget.field?.id ?? widget.draft?['id'] as String? ?? newId();
  late final _name = TextEditingController(text: widget.field?.name ?? 'Champ ${widget.services.fieldsOf(widget.producer.id).length + 1}');
  late final _declared = TextEditingController(text: _num(widget.field?.areaDeclaredHa));
  late List<GpsPoint> _contour = [...?widget.field?.contour];
  late String? _sownOn = widget.field == null ? isoDate(DateTime.now()) : widget.field!.sownOn;
  late String? _irrigation = widget.field?.irrigation;
  late String? _water = widget.field?.waterSource;
  LocalPhoto? _photo;
  bool _saving = false;

  /// Tour du champ en cours : ses points, gardés sur le disque à chaque changement.
  List<GpsPoint>? _walking;

  AppServices get s => widget.services;
  late final _life = AppLifecycleListener(onHide: _keepDraft);

  /// État à l'ouverture : sert à repérer une saisie non enregistrée.
  late final String _clean;

  String _snapshot() => jsonEncode([
    _name.text.trim(),
    _declared.text.trim(),
    [for (final p in _contour) p.toJson()],
    _sownOn,
    _irrigation,
    _water,
    _photo?.id,
  ]);

  @override
  void initState() {
    super.initState();
    _clean = _snapshot();
    _life;
    final d = widget.draft;
    if (d != null) _restore(d);
  }

  bool get _dirty => !_saving && _snapshot() != _clean;

  Map<String, dynamic> _draftJson({String? camera}) => {
    'id': _id,
    'producer_id': widget.producer.id,
    'name': _name.text,
    'declared': _declared.text,
    'contour': [for (final p in _contour) p.toJson()],
    'sown_on': _sownOn,
    'irrigation': _irrigation,
    'water': _water,
    'photo': _photo?.toJson(),
    if (camera != null) 'camera': camera,
    if (_walking != null) 'walk': [for (final p in _walking!) p.toJson()],
  };

  /// Garde la saisie sur le disque si elle n'est pas enregistrée (sinon, retire l'ancienne).
  Future<void> _keepDraft({String? camera}) =>
      s.saveDraft('field', _dirty || _walking != null || camera != null ? _draftJson(camera: camera) : null);

  void _restore(Map<String, dynamic> d) {
    List<GpsPoint> points(Object? x) => [for (final p in (x as List?) ?? const []) GpsPoint.fromJson(Map<String, dynamic>.from(p as Map))];
    _name.text = d['name'] as String? ?? _name.text;
    _declared.text = d['declared'] as String? ?? '';
    _contour = points(d['contour']);
    _sownOn = d['sown_on'] as String?;
    _irrigation = d['irrigation'] as String?;
    _water = d['water'] as String?;
    final photo = d['photo'];
    if (photo is Map) {
      final p = LocalPhoto.fromJson(Map<String, dynamic>.from(photo));
      if (File(p.path).existsSync()) _photo = p;
    }
    final camera = d['camera'];
    if (camera is String) {
      recoverPhoto(s.photosDir, camera).then((p) {
        if (p != null && mounted) setState(() => _photo = p);
      });
    }
    // Tour interrompu : ses points deviennent le contour, et le tour reprend où il en était.
    if (d['walk'] is List) {
      _contour = points(d['walk']);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _walk();
      });
    }
  }

  static String _num(double? v) => v == null ? '' : formatNumber(v);

  @override
  void dispose() {
    _life.dispose();
    // Fiche quittée normalement (enregistrée ou abandonnée) : plus rien à reprendre.
    s.saveDraft('field', null);
    _name.dispose();
    _declared.dispose();
    super.dispose();
  }

  Future<void> _walk() async {
    _walking = [..._contour];
    unawaited(_keepDraft());
    final r = await Navigator.push<List<GpsPoint>>(
      context,
      MaterialPageRoute(
        builder: (_) => FieldWalkPage(
          name: _name.text.trim().isEmpty ? 'Champ' : _name.text.trim(),
          initial: _contour,
          onChanged: (points) {
            _walking = points;
            unawaited(_keepDraft());
          },
        ),
      ),
    );
    _walking = null;
    if (r != null && mounted) setState(() => _contour = r);
    unawaited(_keepDraft());
  }

  Future<void> _pickSowing() async {
    final now = DateTime.now();
    final d = await pickDate(
      context,
      initial: DateTime.tryParse(_sownOn ?? ''),
      first: DateTime(now.year - 1),
      last: now.add(const Duration(days: 60)),
      helpText: 'Date de semis',
    );
    if (d != null) setState(() => _sownOn = isoDate(d));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final problem = _contour.isEmpty
        ? null
        : _contour.length > Limits.contourPoints
        ? 'plus de ${Limits.contourPoints} sommets'
        : contourProblem(_contour);
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Contour à reprendre : $problem.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await _store();
    } catch (e, st) {
      // Écriture impossible sur le téléphone : la saisie reste à l'écran, le bouton revient.
      await s.errorLog.write(e, st);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Enregistrement impossible sur le téléphone. Libérez de la place, puis réessayez.')));
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_contour.isEmpty ? 'Champ enregistré sans contour : revenez faire le tour.' : 'Champ enregistré sur le téléphone.'),
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _store() => s.saveField(
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
      editedAt: (s.fields[_id] ?? widget.field)?.editedAt,
    ),
    photo: _photo,
  );

  @override
  Widget build(BuildContext context) {
    final problem = _contour.isEmpty ? null : contourProblem(_contour);
    final measured = _contour.length >= 3 ? areaHa(_contour) : widget.field?.serverAreaHa;
    final declared = double.tryParse(_declared.text.replaceAll(',', '.'));
    final gap = measured != null && declared != null && declared > 0 ? (measured - declared) / declared * 100 : null;
    final title = '${widget.field?.name ?? (widget.field == null ? 'Nouveau champ' : 'Champ')} · ${widget.producer.fullName}';
    return UnsavedGuard(
      isDirty: () => _dirty,
      child: Scaffold(
        appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        bottomNavigationBar: BottomAction(
          caption: 'Gardé sur le téléphone, envoyé avec le réseau',
          button: FilledButton(key: const Key('save-field'), onPressed: _saving ? null : _save, child: const Text('Enregistrer le champ')),
        ),
        body: Form(
          key: _form,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FieldLabel('Nom du champ'),
                TextFormField(key: const Key('field-name'), controller: _name, validator: (v) => tooLong(v, Limits.name)),
                const SizedBox(height: 24),
                _ContourCard(contour: _contour, measured: measured, problem: problem, onWalk: _walk),
                const SizedBox(height: 24),
                const FieldLabel('Surface emblavée déclarée'),
                TextFormField(
                  key: const Key('declared'),
                  controller: _declared,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(suffixText: 'ha'),
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) return null;
                    final x = double.tryParse(v!.replaceAll(',', '.'));
                    if (x == null || x <= 0) return 'Surface positive en hectares';
                    return x > Limits.areaHa ? '${formatNumber(Limits.areaHa)} ha au plus' : null;
                  },
                ),
                if (gap != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Icon(gap < 0 ? Icons.arrow_downward : Icons.arrow_upward, size: 18, color: GuisColors.ochreText),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(text: 'Écart avec la surface mesurée : '),
                                TextSpan(
                                  text:
                                      '${gap > 0
                                          ? '+'
                                          : gap < 0
                                          ? '−'
                                          : ''}${gap.abs().toStringAsFixed(0)} %',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            style: const TextStyle(color: GuisColors.ochreText, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                const FieldLabel('Date de semis'),
                InkWell(
                  key: const Key('sown-on'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: _pickSowing,
                  child: InputDecorator(
                    decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today_outlined)),
                    child: Text(_sownOn == null ? '—' : formatDate(_sownOn), style: const TextStyle(fontSize: 17)),
                  ),
                ),
                const SizedBox(height: 24),
                const FieldLabel('Irrigation'),
                _Choices(
                  key: const Key('irrigation'),
                  options: s.lists.irrigation,
                  value: _irrigation,
                  onChanged: (v) => setState(() => _irrigation = v),
                ),
                const SizedBox(height: 24),
                const FieldLabel('Source d\'eau'),
                _Choices(
                  key: const Key('water'),
                  options: s.lists.waterSources,
                  value: _water,
                  onChanged: (v) => setState(() => _water = v),
                ),
                const SizedBox(height: 24),
                const FieldLabel('Photo du champ'),
                PhotoBox(
                  services: s,
                  label: 'field',
                  large: true,
                  photoId: widget.field?.photoId,
                  pending: _photo,
                  onCamera: (id) => _keepDraft(camera: id),
                  onTaken: (p) {
                    setState(() => _photo = p);
                    _keepDraft();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastilles à choix unique (irrigation, source d'eau) ; toucher la pastille choisie la retire.
class _Choices extends StatelessWidget {
  const _Choices({super.key, required this.options, required this.value, required this.onChanged});

  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (final o in options)
        ChoiceChip(
          label: Text(o),
          selected: value == o,
          onSelected: (sel) => onChanged(sel ? o : null),
          showCheckmark: true,
          checkmarkColor: Colors.white,
          selectedColor: GuisColors.forest,
          backgroundColor: Colors.white,
          labelStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: value == o ? Colors.white : GuisColors.ink),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: value == o ? GuisColors.forest : GuisColors.sandDeep, width: 1.5),
          ),
        ),
    ],
  );
}

/// Bloc « Contour » : aperçu du tracé, surface mesurée en grand, bouton du tour.
class _ContourCard extends StatelessWidget {
  const _ContourCard({required this.contour, required this.measured, required this.problem, required this.onWalk});

  final List<GpsPoint> contour;
  final double? measured;
  final String? problem;
  final VoidCallback onWalk;

  @override
  Widget build(BuildContext context) {
    final has = contour.length >= 3;
    return Container(
      decoration: BoxDecoration(color: GuisColors.surface, borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: contour.length < 3
                ? 'Pas encore de contour'
                : 'Contour du champ : ${contour.length} sommets${problem != null ? ', à reprendre' : ''}',
            child: SizedBox(height: 150, child: CustomPaint(painter: _ContourPainter(contour, problem != null))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('Contour', style: GuisText.sectionTitle),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        has ? '${contour.length} sommets · ${perimeterM(contour).toStringAsFixed(0)} m de tour' : 'Pas encore de contour',
                        key: const Key('contour-summary'),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GuisText.secondary.copyWith(fontSize: 15),
                      ),
                    ),
                  ],
                ),
                if (measured != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(formatHa(measured), maxLines: 1, style: GuisText.bigNumber.copyWith(fontSize: 32, height: 1.2)),
                      const SizedBox(width: 10),
                      const Text('surface mesurée', style: GuisText.secondary),
                    ],
                  ),
                ],
                if (problem != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(problem!, style: const TextStyle(color: GuisColors.clay, fontSize: 15)),
                  ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  key: const Key('walk'),
                  onPressed: onWalk,
                  icon: const Icon(Icons.pentagon_outlined),
                  label: Text(contour.isEmpty ? 'Faire le tour du champ' : 'Reprendre le tour'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Aperçu du tracé sans fond de carte (l'app travaille hors ligne) : sillons stylisés et polygone mis à l'échelle.
class _ContourPainter extends CustomPainter {
  _ContourPainter(this.points, this.invalid);

  final List<GpsPoint> points;
  final bool invalid;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFD9D1BC));
    final furrow = Paint()
      ..color = const Color(0xFFC9BFA5)
      ..strokeWidth = 10;
    for (var y = 20.0; y < size.height + 40; y += 46) {
      canvas.drawLine(Offset(0, y + 8), Offset(size.width, y - 8), furrow);
    }
    if (points.length < 3) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'Le tracé apparaîtra ici',
          style: TextStyle(color: GuisColors.muted, fontSize: 15),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
      return;
    }
    final lat0 = points.map((p) => p.lat).reduce((a, b) => a + b) / points.length;
    final kx = math.cos(lat0 * math.pi / 180);
    final xs = points.map((p) => p.lng * kx).toList(), ys = points.map((p) => p.lat).toList();
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max), minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    final scale = math.min((size.width - 60) / math.max(maxX - minX, 1e-9), (size.height - 40) / math.max(maxY - minY, 1e-9));
    final ox = (size.width - (maxX - minX) * scale) / 2, oy = (size.height - (maxY - minY) * scale) / 2;
    final pts = [for (var i = 0; i < points.length; i++) Offset(ox + (xs[i] - minX) * scale, oy + (maxY - ys[i]) * scale)];
    final path = Path()..addPolygon(pts, true);
    final color = invalid ? GuisColors.clay : GuisColors.forest;
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.28));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    for (final p in pts) {
      canvas.drawCircle(p, 6, Paint()..color = Colors.white);
      canvas.drawCircle(
        p,
        6,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ContourPainter old) => old.points != points || old.invalid != invalid;
}
