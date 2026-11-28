import 'dart:io';

import 'package:flutter/material.dart';

import '../core/photos.dart';
import '../core/services.dart';
import 'theme.dart';

/// Photo d'un producteur (vignette carrée et bouton, maquette android/03a). Les photos d'un champ :
/// [FieldPhotos] (ui/field_photos.dart).
/// [photoId] : photo déjà enregistrée ; [pending] : photo prise sur cet écran, pas encore enregistrée.
class PhotoBox extends StatelessWidget {
  const PhotoBox({
    super.key,
    required this.services,
    required this.photoId,
    required this.pending,
    required this.onTaken,
    required this.label,
    this.onCamera,
  });

  final AppServices services;
  final String? photoId;
  final LocalPhoto? pending;
  final ValueChanged<LocalPhoto> onTaken;
  final String label;

  /// Appelé juste avant d'ouvrir l'appareil photo, avec l'identifiant de la future photo : l'écran garde
  /// sa saisie sur le disque (Android peut arrêter l'app pendant la prise de vue).
  final Future<void> Function(String photoId)? onCamera;

  Future<void> _take(BuildContext context) async {
    try {
      final id = newId();
      await onCamera?.call(id);
      final p = await takePhoto(services.photosDir, id);
      if (p != null) onTaken(p);
    } catch (e, st) {
      await services.errorLog.write(e, st);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Appareil photo indisponible. Réessayez ; si cela continue, redémarrez le téléphone.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final File? file = pending != null ? File(pending!.path) : services.localPhoto(photoId);
    final has = photoId != null || pending != null;
    final button = OutlinedButton.icon(
      key: Key('photo-$label'),
      onPressed: () => _take(context),
      icon: const Icon(Icons.photo_camera_outlined),
      label: Text(has ? 'Remplacer la photo' : 'Prendre une photo'),
    );
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 96,
            height: 96,
            color: GuisColors.forestSoft,
            child: file != null
                ? Image.file(file, fit: BoxFit.cover, cacheWidth: 288)
                : Icon(has ? Icons.cloud_done_outlined : Icons.person_outline, size: 40, color: GuisColors.forest),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: button),
      ],
    );
  }
}
