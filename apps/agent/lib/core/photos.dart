import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

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

/// Une photo prise sur le téléphone, gardée dans le dossier de l'app jusqu'à son dépôt.
class LocalPhoto {
  const LocalPhoto({required this.id, required this.path, required this.takenAt, this.lat, this.lng});

  final String id;
  final String path;
  final DateTime takenAt;
  final double? lat;
  final double? lng;

  Map<String, dynamic> toJson() => {'id': id, 'path': path, 'taken_at': takenAt.toUtc().toIso8601String(), 'lat': lat, 'lng': lng};

  factory LocalPhoto.fromJson(Map<String, dynamic> j) => LocalPhoto(
    id: j['id'] as String,
    path: j['path'] as String,
    takenAt: DateTime.parse(j['taken_at'] as String).toLocal(),
    lat: (j['lat'] as num?)?.toDouble(),
    lng: (j['lng'] as num?)?.toDouble(),
  );

  /// En-têtes du dépôt (`PUT /api/photos/<id>`).
  Map<String, String> get headers => {
    'X-Taken-At': takenAt.toUtc().toIso8601String(),
    if (lat != null) 'X-Lat': lat!.toStringAsFixed(7),
    if (lng != null) 'X-Lng': lng!.toStringAsFixed(7),
  };
}

/// Prend une photo (compressée : 1600 px, qualité 75), la copie dans le dossier de
/// l'application — elle survit au redémarrage jusqu'à son dépôt — et la date et la
/// géolocalise. Null si l'agent annule. (Repris de Fieldproof : `takeDocumentPhoto`.)
Future<LocalPhoto?> takePhoto(Directory photos, String id, {CameraDevice camera = CameraDevice.rear}) async {
  final shot = await ImagePicker().pickImage(
    source: ImageSource.camera,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 75,
    preferredCameraDevice: camera,
  );
  if (shot == null) return null;
  final takenAt = DateTime.now();
  await photos.create(recursive: true);
  final saved = await File(shot.path).copy('${photos.path}/$id.jpg');
  final pos = await currentPosition(timeLimit: const Duration(seconds: 8));
  return LocalPhoto(id: id, path: saved.path, takenAt: takenAt, lat: pos?.latitude, lng: pos?.longitude);
}

/// Photo prise juste avant qu'Android arrête l'app (appareil photo sur un téléphone à court de mémoire) :
/// déjà copiée dans le dossier de l'app, ou encore gardée par l'appareil photo (`retrieveLostData`).
/// Null si l'agent n'a pas pris la photo. Sans position : celle de la reprise serait fausse.
Future<LocalPhoto?> recoverPhoto(Directory photos, String id) async {
  var file = File('${photos.path}/$id.jpg');
  if (!await file.exists()) {
    try {
      final lost = await ImagePicker().retrieveLostData();
      final shot = lost.file;
      if (lost.isEmpty || shot == null) return null;
      await photos.create(recursive: true);
      file = await File(shot.path).copy(file.path);
    } catch (_) {
      return null;
    }
  }
  return LocalPhoto(id: id, path: file.path, takenAt: await file.lastModified());
}
