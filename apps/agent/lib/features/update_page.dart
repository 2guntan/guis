import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/services.dart';
import '../ui/theme.dart';

/// Lien de téléchargement de l'APK, lisible et copiable (pas de navigateur intégré).
class ApkLink extends StatelessWidget {
  const ApkLink({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: SelectableText(url, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      IconButton(
        key: const Key('copy-apk-url'),
        tooltip: 'Copier le lien',
        icon: const Icon(Icons.copy),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: url));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lien copié : collez-le dans le navigateur.')));
          }
        },
      ),
    ],
  );
}

/// L'app est trop ancienne pour le serveur (audit M10) : rien d'autre ne s'ouvre tant qu'elle n'est pas
/// mise à jour. Les saisies non envoyées restent sur le téléphone et partiront avec la nouvelle version,
/// installée par-dessus celle-ci.
class UpdatePage extends StatelessWidget {
  const UpdatePage({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final url = services.apkUrl;
    final n = services.pending.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Mise à jour nécessaire')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Cette version de Guis est trop ancienne.', style: GuisText.sectionTitle),
          const SizedBox(height: 12),
          Text(
            'Installez la nouvelle version par-dessus celle-ci, sans désinstaller : '
            '${n == 0 ? 'vos données restent sur le téléphone.' : 'vos $n saisie(s) non envoyée(s) restent sur le téléphone et partiront ensuite.'}',
            style: const TextStyle(fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 20),
          if (url != null) ...[
            const FieldLabel('Lien de téléchargement'),
            ApkLink(url: url),
          ] else
            const Text('Demandez la nouvelle version au coordinateur.', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}
