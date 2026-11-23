import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/model/geo.dart';
import '../../core/photos.dart';
import '../../ui/theme.dart';

/// Tour de la parcelle au GPS : l'agent marche le long du contour et relève les sommets
/// (à la main ou automatiquement tous les 5 m). Un point moins précis que 30 m est refusé.
class ParcelWalkPage extends StatefulWidget {
  const ParcelWalkPage({super.key, required this.name, required this.initial});

  final String name;
  final List<GpsPoint> initial;

  @override
  State<ParcelWalkPage> createState() => _ParcelWalkPageState();
}

class _ParcelWalkPageState extends State<ParcelWalkPage> {
  late final List<GpsPoint> _points = [...widget.initial];
  final _map = MapController();
  StreamSubscription<Position>? _sub;
  Position? _current;
  String? _problem;
  bool _auto = false;
  bool _mapReady = false;

  static const _autoStepM = 5.0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final p = await ensureLocation();
    if (p != null) {
      setState(() => _problem = p);
      return;
    }
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0),
    ).listen((pos) {
      setState(() {
        _current = pos;
        _problem = null;
      });
      if (_mapReady && _points.isEmpty) _map.move(LatLng(pos.latitude, pos.longitude), 17);
      if (_auto && pos.accuracy <= maxAccuracyM) {
        final here = _toPoint(pos);
        if (_points.isEmpty || distanceM(_points.last, here) >= _autoStepM) setState(() => _points.add(here));
      }
    }, onError: (Object e) => setState(() => _problem = 'GPS indisponible : $e'));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  GpsPoint _toPoint(Position p) => GpsPoint(lat: p.latitude, lng: p.longitude, accuracyM: p.accuracy, capturedAt: DateTime.now());

  void _add() {
    final pos = _current;
    if (pos == null) return;
    if (pos.accuracy > maxAccuracyM) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Point refusé : précision ${pos.accuracy.toStringAsFixed(0)} m (> ${maxAccuracyM.toStringAsFixed(0)} m). Attendez un meilleur signal.'),
      ));
      return;
    }
    setState(() => _points.add(_toPoint(pos)));
  }

  Color _accuracyColor(double a) => a <= 10 ? FpColors.forest : (a <= maxAccuracyM ? FpColors.ochre : FpColors.clay);

  @override
  Widget build(BuildContext context) {
    final latlngs = [for (final p in _points) LatLng(p.lat, p.lng)];
    final problem = contourProblem(_points);
    final area = areaHa(_points);
    final acc = _current?.accuracy;
    final center = latlngs.isNotEmpty
        ? latlngs.last
        : (_current != null ? LatLng(_current!.latitude, _current!.longitude) : const LatLng(14.5, -14.5));
    return Scaffold(
      appBar: AppBar(title: Text('Tracé — ${widget.name}')),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: center,
                initialZoom: latlngs.isNotEmpty || _current != null ? 17 : 6,
                backgroundColor: FpColors.sandDeep,
                onMapReady: () => _mapReady = true,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.fieldproof.agent',
                  maxZoom: 19,
                ),
                if (latlngs.length >= 3)
                  PolygonLayer(polygons: [
                    Polygon(
                      points: latlngs,
                      color: (problem == null ? FpColors.forest : FpColors.clay).withValues(alpha: 0.25),
                      borderColor: problem == null ? FpColors.forest : FpColors.clay,
                      borderStrokeWidth: 3,
                    ),
                  ])
                else if (latlngs.length == 2)
                  PolylineLayer(polylines: [Polyline(points: latlngs, color: FpColors.forest, strokeWidth: 3)]),
                MarkerLayer(markers: [
                  for (final (i, p) in latlngs.indexed)
                    Marker(
                      point: p,
                      width: 26,
                      height: 26,
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: FpColors.forest, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                        child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  if (_current != null)
                    Marker(
                      point: LatLng(_current!.latitude, _current!.longitude),
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(color: FpColors.sky, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                      ),
                    ),
                ]),
                const RichAttributionWidget(attributions: [TextSourceAttribution('© contributeurs OpenStreetMap')]),
              ],
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.gps_fixed, color: acc == null ? Colors.grey : _accuracyColor(acc)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _problem ?? (acc == null ? 'Recherche du signal GPS…' : 'Précision : ${acc.toStringAsFixed(0)} m'),
                          style: TextStyle(fontWeight: FontWeight.w600, color: acc == null ? null : _accuracyColor(acc)),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text('${_points.length} sommet${_points.length > 1 ? 's' : ''} · ${formatHa(area)} · ${perimeterM(_points).toStringAsFixed(0)} m de tour'),
                    if (problem != null && _points.isNotEmpty)
                      Padding(padding: const EdgeInsets.only(top: 4), child: Text(problem, style: const TextStyle(color: FpColors.clay))),
                  ]),
                ),
              ),
            ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Relevé automatique en marchant (tous les 5 m)'),
                value: _auto,
                onChanged: (v) => setState(() => _auto = v),
              ),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _points.isEmpty ? null : () => setState(() => _points.removeLast()),
                    icon: const Icon(Icons.undo),
                    label: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    key: const Key('add-point'),
                    onPressed: _current == null ? null : _add,
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: const Text('Ajouter ce point'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: _points.isEmpty ? null : () => setState(_points.clear),
                    child: const Text('Recommencer'),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: const Key('finish-walk'),
                    style: FilledButton.styleFrom(backgroundColor: FpColors.ochre),
                    onPressed: () => Navigator.pop(context, _points),
                    child: const Text('Terminer le tracé'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
