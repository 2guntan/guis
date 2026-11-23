import 'package:geolocator/geolocator.dart';

/// Position courante, ou null (permission refusée, GPS coupé, délai dépassé).
Future<Position?> currentPosition({Duration timeLimit = const Duration(seconds: 12)}) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(accuracy: LocationAccuracy.best, timeLimit: timeLimit),
    );
  } catch (_) {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }
}

/// Demande la permission de localisation ; vrai si accordée.
Future<String?> ensureLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) return 'Activez la localisation (GPS) du téléphone.';
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
  if (perm == LocationPermission.denied) return 'Autorisez la localisation pour Guis.';
  if (perm == LocationPermission.deniedForever) return 'Localisation refusée : autorisez-la dans les réglages du téléphone.';
  return null;
}
