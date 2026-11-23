import 'dart:io';

import 'package:flutter/material.dart';

import '../core/photos.dart';
import '../core/services.dart';
import 'theme.dart';

/// Aperçu d'une photo et bouton pour la prendre ou la remplacer.
/// [photoId] : photo déjà enregistrée ; [pending] : photo prise sur cet écran, pas encore enregistrée.
class PhotoBox extends StatelessWidget {
  const PhotoBox({
    super.key,
    required this.services,
    required this.photoId,
    required this.pending,
    required this.onTaken,
    required this.label,
  });

  final AppServices services;
  final String? photoId;
  final LocalPhoto? pending;
  final ValueChanged<LocalPhoto> onTaken;
  final String label;

  Future<void> _take(BuildContext context) async {
    try {
      final p = await takePhoto(services.photosDir, newId());
      if (p != null) onTaken(p);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Appareil photo indisponible : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final File? file = pending != null ? File(pending!.path) : services.localPhoto(photoId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 84,
                height: 84,
                color: GuisColors.sandDeep,
                child: file != null
                    ? Image.file(file, fit: BoxFit.cover)
                    : Icon(photoId != null ? Icons.cloud_done_outlined : Icons.photo_camera_outlined, color: GuisColors.forest),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pending != null
                        ? 'Nouvelle photo, envoyée avec l\'enregistrement'
                        : photoId != null
                        ? (file != null ? 'Photo enregistrée' : 'Photo envoyée depuis un autre téléphone')
                        : 'Pas de photo',
                  ),
                  TextButton.icon(
                    key: Key('photo-$label'),
                    onPressed: () => _take(context),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(photoId != null || pending != null ? 'Remplacer' : 'Prendre une photo'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
