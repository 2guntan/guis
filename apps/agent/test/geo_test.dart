import 'package:guis/core/model/geo.dart';
import 'package:flutter_test/flutter_test.dart';

GpsPoint p(double lat, double lng, {double acc = 4}) =>
    GpsPoint(lat: lat, lng: lng, accuracyM: acc, capturedAt: DateTime.utc(2026, 11, 20));

void main() {
  // Carré de 0,001° (repris de Fieldproof) : PostGIS y mesure 1,1 à 1,3 ha (ST_Area geography).
  final square = [p(12.5600, -16.2700), p(12.5600, -16.2690), p(12.5590, -16.2690), p(12.5590, -16.2700)];

  test('surface d\'un carré de 0,001° près de Ziguinchor ≈ 1,2 ha (comme PostGIS)', () {
    final ha = areaHa(square);
    // Sur l'ellipsoïde : 110,6 m (latitude) × 108,7 m (longitude) ≈ 1,202 ha
    expect(ha, closeTo(1.202, 0.002));
    expect(contourProblem(square), isNull);
  });

  test('le sens de parcours ne change pas la surface', () {
    expect(areaHa(square.reversed.toList()), closeTo(areaHa(square), 1e-9));
  });

  test('un rectangle de 100 m × 100 m mesure 1 ha', () {
    // À 12,56° N : 1° de latitude ≈ 110 626 m, 1° de longitude ≈ 108 671 m (WGS84)
    const dLat = 100 / 110626.0, dLng = 100 / 108671.0;
    final rect = [p(12.56, -16.27), p(12.56, -16.27 + dLng), p(12.56 + dLat, -16.27 + dLng), p(12.56 + dLat, -16.27)];
    expect(areaHa(rect), closeTo(1.0, 0.002));
    expect(perimeterM(rect), closeTo(400, 2));
  });

  test('moins de 3 sommets : surface nulle et contour refusé', () {
    expect(areaHa(square.take(2).toList()), 0);
    expect(contourProblem(square.take(2).toList()), contains('Au moins 3 sommets'));
  });

  test('un contour en papillon est refusé', () {
    final bow = [p(12.560, -16.270), p(12.559, -16.269), p(12.560, -16.269), p(12.559, -16.270)];
    expect(selfIntersects(bow), isTrue);
    expect(contourProblem(bow), contains('se croise'));
    expect(selfIntersects(square), isFalse);
  });

  test('moins de 100 m² est refusé (règle de la base)', () {
    final tiny = [p(12.56, -16.27), p(12.56, -16.27005), p(12.56005, -16.27005)];
    expect(contourProblem(tiny), contains('100 m²'));
  });

  test('GeoJSON : anneau fermé en [lng, lat]', () {
    final g = polygonGeoJson(square)!;
    expect(g['type'], 'Polygon');
    final ring = (g['coordinates'] as List).first as List;
    expect(ring.length, 5);
    expect(ring.first, [-16.27, 12.56]);
    expect(ring.last, ring.first);
    expect(polygonGeoJson(square.take(2).toList()), isNull);
  });
}
