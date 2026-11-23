import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import 'model/dossier.dart';

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
  if (perm == LocationPermission.denied) return 'Autorisez la localisation pour Fieldproof Agent.';
  if (perm == LocationPermission.deniedForever) return 'Localisation refusée : autorisez-la dans les réglages du téléphone.';
  return null;
}

/// Prend une photo (compressée : 1600 px, qualité 75), la copie dans le dossier de
/// l'application — elle survit au redémarrage jusqu'à son dépôt — et la date et la
/// géolocalise. Null si l'agent annule.
Future<LocalDocument?> takeDocumentPhoto(Directory photos, String documentId, String kind,
    {ImageSource source = ImageSource.camera, CameraDevice camera = CameraDevice.rear}) async {
  final shot = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 75, preferredCameraDevice: camera);
  if (shot == null) return null;
  final capturedAt = DateTime.now();
  final saved = await File(shot.path).copy('${photos.path}/$documentId.jpg');
  final pos = await currentPosition(timeLimit: const Duration(seconds: 8));
  return LocalDocument(
    id: documentId,
    kind: kind,
    localPath: saved.path,
    capturedAt: capturedAt,
    lat: pos?.latitude,
    lng: pos?.longitude,
    sizeBytes: await saved.length(),
  );
}
