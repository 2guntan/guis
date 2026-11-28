import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/model/geo.dart';
import '../../core/photos.dart';
import '../../core/screen.dart';
import '../../ui/confirm.dart';
import '../../ui/theme.dart';

/// Tour du champ au GPS (repris de Fieldproof, parcel_walk_page.dart) : l'agent marche le long du contour et relève un
/// point à chaque coin. « Ajouter ce point » mesure pendant [cornerSeconds] secondes, l'agent immobile, et garde la
/// moyenne des mesures ([averagePoint]). Un point moins précis que 30 m est refusé. Le relevé automatique tous les 5 m
/// (champs aux bords courbes) reste dans le menu ⋮.
/// L'écran reste allumé pendant le tour (la mise en veille couperait le GPS) ; chaque changement du tracé
/// est signalé par [onChanged] pour être gardé sur le disque (l'app peut être arrêtée en arrière-plan).
class FieldWalkPage extends StatefulWidget {
  const FieldWalkPage({super.key, required this.name, required this.initial, this.onChanged, this.cornerSeconds = 4, this.positions});

  final String name;
  final List<GpsPoint> initial;
  final ValueChanged<List<GpsPoint>>? onChanged;

  /// Durée de la mesure d'un coin.
  final int cornerSeconds;

  /// Positions GPS fournies par les tests ; sinon celles du téléphone.
  final Stream<Position>? positions;

  @override
  State<FieldWalkPage> createState() => _FieldWalkPageState();
}

final _tileCache = BuiltInMapCachingProvider.getOrCreateInstance(maxCacheSize: 200000000, overrideFreshAge: const Duration(days: 90));

class _FieldWalkPageState extends State<FieldWalkPage> {
  late final List<GpsPoint> _points = [...widget.initial];
  final _map = MapController();
  StreamSubscription<Position>? _sub;
  Position? _current;
  String? _problem;
  bool _auto = false;
  bool _mapReady = false;

  /// Mesures du coin en cours (null hors mesure) et secondes restantes.
  List<GpsPoint>? _corner;
  int _left = 0;
  Timer? _cornerTimer;

  static const _autoStepM = 5.0;
  static const _autoMaxAccuracyM = 15.0;

  @override
  void initState() {
    super.initState();
    keepScreenOn(true);
    _start();
  }

  /// Modifie le tracé et le signale (gardé sur le disque par la fiche du champ).
  void _change(VoidCallback f) {
    setState(f);
    widget.onChanged?.call(List.unmodifiable(_points));
  }

  Future<void> _start() async {
    final test = widget.positions;
    final p = test == null ? await ensureLocation() : null;
    if (!mounted) return;
    if (p != null) {
      setState(() => _problem = p);
      return;
    }
    _sub =
        (test ?? Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0)))
            .listen((pos) {
              if (!mounted) return;
              setState(() {
                _current = pos;
                _problem = null;
                _corner?.add(_toPoint(pos));
              });
              if (_mapReady && _points.isEmpty) _map.move(LatLng(pos.latitude, pos.longitude), 17);
              // Relevé automatique : seulement avec un bon signal, et un pas plus grand que l'imprécision
              // annoncée (sinon le tremblement du GPS à l'arrêt dessine des zigzags et le contour se croise).
              if (_auto && pos.accuracy <= _autoMaxAccuracyM) {
                final here = _toPoint(pos);
                final step = math.max(_autoStepM, pos.accuracy);
                if (_points.isEmpty || distanceM(_points.last, here) >= step) _change(() => _points.add(here));
              }
            }, onError: (Object e) => mounted ? setState(() => _problem = 'GPS indisponible : activez la localisation.') : null);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _cornerTimer?.cancel();
    keepScreenOn(false);
    super.dispose();
  }

  /// Le tracé a changé depuis l'ouverture : le quitter sans « Terminer » le perd.
  bool get _changed =>
      _points.length != widget.initial.length ||
      [for (var i = 0; i < _points.length; i++) i].any((i) => !identical(_points[i], widget.initial[i]));

  Future<void> _restart() async {
    final n = _points.length;
    final ok = await confirmLoss(
      context,
      title: 'Effacer tous les points ?',
      text: 'Les $n point${n > 1 ? 's' : ''} relevé${n > 1 ? 's' : ''} seront effacé${n > 1 ? 's' : ''}.',
      confirm: 'Effacer',
      cancel: 'Garder les points',
    );
    if (ok && mounted) _change(_points.clear);
  }

  GpsPoint _toPoint(Position p) => GpsPoint(lat: p.latitude, lng: p.longitude, accuracyM: p.accuracy, capturedAt: DateTime.now());

  void _refuse(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Mesure d'un coin : l'agent reste immobile [FieldWalkPage.cornerSeconds] secondes, puis le point
  /// gardé est la moyenne des mesures reçues pendant ce temps.
  void _add() {
    final pos = _current;
    if (pos == null || _corner != null) return;
    if (pos.accuracy > maxAccuracyM) {
      _refuse(
        'Point refusé : précision ${pos.accuracy.toStringAsFixed(0)} m (> ${maxAccuracyM.toStringAsFixed(0)} m). Attendez un meilleur signal.',
      );
      return;
    }
    setState(() {
      _corner = [_toPoint(pos)];
      _left = widget.cornerSeconds;
    });
    _cornerTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_left > 1) return setState(() => _left--);
      t.cancel();
      final point = averagePoint(_corner!);
      setState(() => _corner = null);
      if (point == null) {
        _refuse('Point refusé : le signal GPS s\'est dégradé pendant la mesure. Attendez que la pastille soit verte.');
      } else {
        _change(() => _points.add(point));
      }
    });
  }

  /// Couleurs de la pastille de précision : bonne (≤ 10 m), moyenne, refusée (> 30 m).
  (Color, Color) _accuracyColors(double? a) => a == null
      ? (GuisColors.sandDeep, GuisColors.muted)
      : a <= 10
      ? (GuisColors.forestSoft, GuisColors.forest)
      : a <= maxAccuracyM
      ? (GuisColors.ochreSoft, GuisColors.ochreText)
      : (GuisColors.claySoft, GuisColors.clayText);

  @override
  Widget build(BuildContext context) {
    final latlngs = [for (final p in _points) LatLng(p.lat, p.lng)];
    final problem = _points.length >= 3 && selfIntersects(_points) ? 'Le contour se croise : reprenez le tour dans l\'ordre.' : null;
    final area = areaHa(_points);
    final acc = _current?.accuracy;
    final refused = acc != null && acc > maxAccuracyM;
    final (chipBg, chipFg) = _accuracyColors(acc);
    final center = latlngs.isNotEmpty
        ? latlngs.last
        : (_current != null ? LatLng(_current!.latitude, _current!.longitude) : const LatLng(14.95, -16.85));
    final banner =
        _problem ??
        (refused
            ? 'Point refusé : précision au-delà de ${maxAccuracyM.toStringAsFixed(0)} m. Restez immobile ou avancez à découvert.'
            : problem);
    return UnsavedGuard(
      isDirty: () => _changed,
      title: 'Abandonner le tracé ?',
      text: 'Les points relevés depuis l\'ouverture seront perdus. Touchez « Terminer le tracé » pour les garder.',
      confirm: 'Abandonner',
      child: Scaffold(
        body: Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: center,
                initialZoom: latlngs.isNotEmpty || _current != null ? 17 : 9,
                // Contour déjà relevé : cadré entre la carte du haut et les boutons du bas.
                initialCameraFit: latlngs.length >= 2
                    ? CameraFit.coordinates(coordinates: latlngs, padding: const EdgeInsets.fromLTRB(48, 300, 48, 260), maxZoom: 18)
                    : null,
                backgroundColor: const Color(0xFF9DA584),
                onMapReady: () => _mapReady = true,
              ),
              children: [
                // Imagerie satellite (Esri, sans clé, attribution requise) : on voit le champ que l'on parcourt.
                TileLayer(
                  urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                  userAgentPackageName: 'com.guis.app',
                  // Tuiles gardées sur le téléphone (200 Mo, 90 jours) : moins de données mobiles, et la
                  // carte d'un endroit déjà vu s'affiche sans réseau. L'imagerie change rarement.
                  tileProvider: NetworkTileProvider(cachingProvider: _tileCache),
                  maxZoom: 19,
                  maxNativeZoom: 17,
                ),
                if (latlngs.length >= 3)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: latlngs,
                        color: (problem == null ? Colors.white : GuisColors.clay).withValues(alpha: 0.25),
                        borderColor: problem == null ? Colors.white : GuisColors.clay,
                        borderStrokeWidth: 3.5,
                      ),
                    ],
                  )
                else if (latlngs.length == 2)
                  PolylineLayer(
                    polylines: [Polyline(points: latlngs, color: Colors.white, strokeWidth: 3.5)],
                  ),
                MarkerLayer(
                  markers: [
                    for (final (i, p) in latlngs.indexed)
                      Marker(
                        point: p,
                        width: 34,
                        height: 34,
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: GuisColors.forest,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    if (_current != null)
                      Marker(
                        point: LatLng(_current!.latitude, _current!.longitude),
                        width: 48,
                        height: 48,
                        child: Container(
                          decoration: BoxDecoration(color: GuisColors.sky.withValues(alpha: 0.25), shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: GuisColors.sky,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const RichAttributionWidget(attributions: [TextSourceAttribution('Imagerie © Esri')]),
              ],
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F6F0),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 4))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(24)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.gps_fixed, color: chipFg, size: 20),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        acc == null ? 'Signal GPS…' : 'Précision : ${acc.toStringAsFixed(0)} m',
                                        style: TextStyle(color: chipFg, fontWeight: FontWeight.w700, fontSize: 16),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            key: const Key('walk-menu'),
                            tooltip: 'Plus d\'options',
                            icon: const Icon(Icons.more_vert, color: GuisColors.ink),
                            onSelected: (_) => setState(() => _auto = !_auto),
                            itemBuilder: (_) => [
                              CheckedPopupMenuItem(
                                key: const Key('auto-walk'),
                                value: 'auto',
                                checked: _auto,
                                child: const Text('Relevé automatique en marchant (tous les 5 m)'),
                              ),
                            ],
                          ),
                          TextButton.icon(
                            key: const Key('cancel-walk'),
                            style: TextButton.styleFrom(foregroundColor: GuisColors.ink),
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(Icons.close),
                            label: const Text('Annuler'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(formatHa(area), maxLines: 1, style: GuisText.bigNumber.copyWith(fontSize: 30)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${_points.length} sommet${_points.length > 1 ? 's' : ''} · ${perimeterM(_points).toStringAsFixed(0)} m de tour',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GuisText.secondary.copyWith(fontSize: 15),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Text(
                        _auto
                            ? 'Relevé automatique : un point tous les 5 m en marchant. Arrêtez-le dans le menu ⋮.'
                            : 'Un point à chaque coin du champ. Attendez que la pastille soit verte, puis restez immobile pendant la mesure.',
                        style: const TextStyle(fontSize: 15, height: 1.35),
                      ),
                      if (_points.isNotEmpty && _corner == null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => _change(_points.removeLast),
                            icon: const Icon(Icons.undo, size: 20),
                            label: const Text('Retirer le dernier point'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (banner != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: const Color(0xFF5A2219), borderRadius: BorderRadius.circular(16)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Color(0xFFF3DED8)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(banner, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
                              ),
                            ],
                          ),
                        ),
                      FilledButton.icon(
                        key: const Key('add-point'),
                        style: FilledButton.styleFrom(
                          backgroundColor: GuisColors.ochre,
                          foregroundColor: GuisColors.ink,
                          disabledBackgroundColor: const Color(0xFFD8D6CE),
                          disabledForegroundColor: GuisColors.ink,
                          minimumSize: const Size.fromHeight(64),
                          textStyle: GuisText.button.copyWith(fontSize: 19),
                        ),
                        onPressed: _current == null || refused || _corner != null ? null : _add,
                        icon: Icon(_corner == null ? Icons.add_location_alt_outlined : Icons.hourglass_top, size: 26),
                        label: Text(_corner == null ? 'Ajouter ce point' : 'Restez immobile… $_left'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFF8F6F0),
                                foregroundColor: GuisColors.clay,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              key: const Key('restart-walk'),
                              onPressed: _points.isEmpty ? null : _restart,
                              child: const Text('Recommencer'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              key: const Key('finish-walk'),
                              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                              onPressed: () => Navigator.pop(context, _points),
                              child: const Text('Terminer le tracé'),
                            ),
                          ),
                        ],
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
