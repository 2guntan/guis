import 'dart:math' as math;

/// Un point relevé au GPS pendant le tour de la parcelle.
class GpsPoint {
  const GpsPoint({required this.lat, required this.lng, required this.accuracyM, required this.capturedAt});

  final double lat;
  final double lng;
  final double accuracyM;
  final DateTime capturedAt;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'accuracy_m': double.parse(accuracyM.toStringAsFixed(1)),
        'captured_at': capturedAt.toUtc().toIso8601String(),
      };

  factory GpsPoint.fromJson(Map<String, dynamic> j) => GpsPoint(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        accuracyM: (j['accuracy_m'] as num?)?.toDouble() ?? 0,
        capturedAt: DateTime.tryParse(j['captured_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}

/// Précision maximale acceptée pour un sommet (mètres).
const maxAccuracyM = 30.0;

/// Nombre minimal de sommets d'un contour.
const minVertices = 3;

/// Surface minimale acceptée par la base (identity.parcels_check_geometry) : 100 m².
const minAreaM2 = 100.0;

/// Surface maximale acceptée par la base : 500 ha.
const maxAreaM2 = 5000000.0;

const _earthRadiusM = 6378137.0;
const _e2 = 0.00669437999014; // excentricité² de l'ellipsoïde WGS84

double _rad(double d) => d * math.pi / 180;

/// Surface d'un contour (m²) sur l'ellipsoïde WGS84 : projection locale autour du
/// centre (rayons de courbure méridien et normal), puis formule du lacet. Pour une
/// parcelle agricole (quelques km au plus), l'écart avec `ST_Area(geography)` de
/// PostGIS reste inférieur à 0,1 %.
double ringAreaM2(List<({double lat, double lng})> ring) {
  if (ring.length < 3) return 0;
  final lat0 = ring.map((p) => p.lat).reduce((a, b) => a + b) / ring.length;
  final lng0 = ring.map((p) => p.lng).reduce((a, b) => a + b) / ring.length;
  final s2 = math.pow(math.sin(_rad(lat0)), 2);
  final m = _earthRadiusM * (1 - _e2) / math.pow(1 - _e2 * s2, 1.5);
  final n = _earthRadiusM / math.sqrt(1 - _e2 * s2);
  final kx = _rad(1) * n * math.cos(_rad(lat0)), ky = _rad(1) * m;
  var twice = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i], b = ring[(i + 1) % ring.length];
    twice += ((a.lng - lng0) * kx) * ((b.lat - lat0) * ky) - ((b.lng - lng0) * kx) * ((a.lat - lat0) * ky);
  }
  return twice.abs() / 2;
}

double areaHa(List<GpsPoint> points) => ringAreaM2([for (final p in points) (lat: p.lat, lng: p.lng)]) / 10000;

/// Périmètre approché (m), formule de haversine.
double perimeterM(List<GpsPoint> points) {
  if (points.length < 2) return 0;
  var total = 0.0;
  for (var i = 0; i < points.length; i++) {
    total += distanceM(points[i], points[(i + 1) % points.length]);
  }
  return total;
}

double distanceM(GpsPoint a, GpsPoint b) {
  final dLat = _rad(b.lat - a.lat), dLng = _rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.min(1, math.sqrt(h)));
}

bool _segmentsCross(GpsPoint a, GpsPoint b, GpsPoint c, GpsPoint d) {
  double orient(GpsPoint p, GpsPoint q, GpsPoint r) => (q.lng - p.lng) * (r.lat - p.lat) - (q.lat - p.lat) * (r.lng - p.lng);
  final o1 = orient(a, b, c), o2 = orient(a, b, d), o3 = orient(c, d, a), o4 = orient(c, d, b);
  return (o1 * o2 < 0) && (o3 * o4 < 0);
}

/// Vrai si deux côtés non adjacents du contour se croisent (« papillon »).
bool selfIntersects(List<GpsPoint> points) {
  final n = points.length;
  if (n < 4) return false;
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if ((i - j).abs() <= 1 || (i == 0 && j == n - 1)) continue;
      if (_segmentsCross(points[i], points[(i + 1) % n], points[j], points[(j + 1) % n])) return true;
    }
  }
  return false;
}

/// Problème bloquant du contour, en français, ou null s'il est acceptable (mêmes règles que la base).
String? contourProblem(List<GpsPoint> points) {
  if (points.length < minVertices) return 'Au moins $minVertices sommets (${points.length} relevé${points.length > 1 ? 's' : ''})';
  if (selfIntersects(points)) return 'Le contour se croise : reprenez le tour dans l\'ordre';
  final a = ringAreaM2([for (final p in points) (lat: p.lat, lng: p.lng)]);
  if (a < minAreaM2) return 'Surface inférieure à 100 m²';
  if (a > maxAreaM2) return 'Surface supérieure à 500 ha';
  return null;
}

/// Polygone GeoJSON (anneau fermé, [lng, lat]) attendu par `dossier.save_draft`.
Map<String, dynamic>? polygonGeoJson(List<GpsPoint> points) {
  if (points.length < minVertices) return null;
  final ring = [for (final p in points) [p.lng, p.lat]];
  ring.add([points.first.lng, points.first.lat]);
  return {
    'type': 'Polygon',
    'coordinates': [ring],
  };
}
