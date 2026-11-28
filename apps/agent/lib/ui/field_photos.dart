import 'dart:io';

import 'package:flutter/material.dart';

import '../core/model/models.dart';
import '../core/photos.dart';
import '../core/services.dart';
import 'theme.dart';

/// Photos d'un champ (de zéro à [Field.maxPhotos]) : vignettes en grille, chacune avec sa date
/// et sa position si elle a été prise sur cet écran, une croix pour la retirer, et le bouton
/// « Prendre une photo » tant que le maximum n'est pas atteint.
class FieldPhotos extends StatelessWidget {
  const FieldPhotos({
    super.key,
    required this.services,
    required this.photoIds,
    required this.taken,
    required this.onTaken,
    required this.onRemove,
    this.onCamera,
  });

  final AppServices services;

  /// Photos du champ, dans l'ordre (enregistrées et prises sur cet écran).
  final List<String> photoIds;

  /// Photos prises sur cet écran, pas encore enregistrées (date et position connues).
  final List<LocalPhoto> taken;
  final ValueChanged<LocalPhoto> onTaken;
  final ValueChanged<String> onRemove;

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

  Future<void> _remove(BuildContext context, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Retirer cette photo ?', style: GuisText.sectionTitle),
        content: const Text('Elle ne fera plus partie des photos du champ.'),
        actions: [
          TextButton(key: const Key('keep-photo'), onPressed: () => Navigator.pop(c, false), child: const Text('Garder')),
          FilledButton(
            key: const Key('remove-photo'),
            style: FilledButton.styleFrom(backgroundColor: GuisColors.clay),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (ok == true) onRemove(id);
  }

  @override
  Widget build(BuildContext context) {
    final full = photoIds.length >= Field.maxPhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (photoIds.isNotEmpty) ...[
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 4 / 3,
            children: [
              for (final (i, id) in photoIds.indexed)
                _Tile(
                  key: Key('field-photo-$i'),
                  file: _file(id),
                  local: taken.where((p) => p.id == id).firstOrNull,
                  number: i + 1,
                  onRemove: () => _remove(context, id),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (full)
          Text(
            '${Field.maxPhotos} photos au maximum. Retirez-en une pour en prendre une autre.',
            key: const Key('photos-full'),
            style: GuisText.secondary.copyWith(fontSize: 15),
          )
        else
          OutlinedButton.icon(
            key: const Key('photo-field'),
            onPressed: () => _take(context),
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(photoIds.isEmpty ? 'Prendre une photo' : 'Prendre une autre photo'),
          ),
      ],
    );
  }

  File? _file(String id) {
    final p = taken.where((p) => p.id == id).firstOrNull;
    return p != null ? File(p.path) : services.localPhoto(id);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.file, required this.local, required this.number, required this.onRemove});

  final File? file;
  final LocalPhoto? local;
  final int number;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = local?.takenAt;
    final stamp = t == null
        ? null
        : '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} '
              '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
              '${local!.lat != null ? ' · GPS' : ''}';
    return Semantics(
      label: file == null ? 'Photo du champ $number, envoyée depuis un autre téléphone' : 'Photo du champ $number',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (file != null)
              Image.file(file!, fit: BoxFit.cover, cacheWidth: 540)
            else
              // Photo déjà au bureau, prise sur un autre téléphone (pas de copie ici).
              const ColoredBox(
                color: GuisColors.forestSoft,
                child: Center(child: Icon(Icons.cloud_done_outlined, size: 40, color: GuisColors.forest)),
              ),
            if (stamp != null)
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(14)),
                  child: Text(
                    stamp,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            Positioned(
              right: 4,
              top: 4,
              child: Material(
                color: Colors.black.withValues(alpha: 0.6),
                shape: const CircleBorder(),
                child: IconButton(
                  key: Key('remove-photo-$number'),
                  tooltip: 'Retirer la photo $number',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
