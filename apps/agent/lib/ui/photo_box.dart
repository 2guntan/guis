import 'dart:io';

import 'package:flutter/material.dart';

import '../core/photos.dart';
import '../core/services.dart';
import 'theme.dart';

/// Photo d'un producteur (vignette carrée et bouton, maquette android/03a) ou d'un champ
/// (grande photo avec sa position et sa date incrustées, maquette android/05).
/// [photoId] : photo déjà enregistrée ; [pending] : photo prise sur cet écran, pas encore enregistrée.
class PhotoBox extends StatelessWidget {
  const PhotoBox({
    super.key,
    required this.services,
    required this.photoId,
    required this.pending,
    required this.onTaken,
    required this.label,
    this.large = false,
  });

  final AppServices services;
  final String? photoId;
  final LocalPhoto? pending;
  final ValueChanged<LocalPhoto> onTaken;
  final String label;
  final bool large;

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
    final has = photoId != null || pending != null;
    final button = OutlinedButton.icon(
      key: Key('photo-$label'),
      onPressed: () => _take(context),
      icon: const Icon(Icons.photo_camera_outlined),
      label: Text(has ? 'Remplacer la photo' : 'Prendre une photo'),
    );
    if (!large) {
      return Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 96,
              height: 96,
              color: GuisColors.forestSoft,
              child: file != null
                  ? Image.file(file, fit: BoxFit.cover)
                  : Icon(has ? Icons.cloud_done_outlined : Icons.person_outline, size: 40, color: GuisColors.forest),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: button),
        ],
      );
    }
    final p = pending;
    final stamp = p == null
        ? null
        : [
            if (p.lat != null && p.lng != null) '${_deg(p.lat!, 'N', 'S')} · ${_deg(p.lng!, 'E', 'O')}',
            '${p.takenAt.day.toString().padLeft(2, '0')}/${p.takenAt.month.toString().padLeft(2, '0')} '
                '${p.takenAt.hour.toString().padLeft(2, '0')}:${p.takenAt.minute.toString().padLeft(2, '0')}',
          ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (file != null || has)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (file != null)
                    Image.file(file, fit: BoxFit.cover)
                  else
                    const ColoredBox(
                      color: GuisColors.forestSoft,
                      child: Center(child: Text('Photo envoyée depuis un autre téléphone', style: GuisText.secondary)),
                    ),
                  if (stamp != null)
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on, size: 16, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              stamp,
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (has) const SizedBox(height: 10),
        button,
      ],
    );
  }

  static String _deg(double v, String pos, String neg) => '${v.abs().toStringAsFixed(4).replaceAll('.', ',')} ${v >= 0 ? pos : neg}';
}
