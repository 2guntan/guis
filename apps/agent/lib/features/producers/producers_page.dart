import 'package:flutter/material.dart';

import '../../core/model/models.dart';
import '../../core/services.dart';
import '../../ui/theme.dart';
import 'producer_page.dart';

/// Accueil de l'agent : tous les producteurs (y compris ceux des autres agents et ceux importés),
/// avec une recherche et l'état de la synchronisation.
class ProducersPage extends StatefulWidget {
  const ProducersPage({super.key, required this.services});

  final AppServices services;

  @override
  State<ProducersPage> createState() => _ProducersPageState();
}

class _ProducersPageState extends State<ProducersPage> {
  String _query = '';

  AppServices get s => widget.services;

  @override
  void initState() {
    super.initState();
    s.startAutoSync();
    if (!s.hasData) s.sync(force: true);
  }

  Future<void> _sync() async {
    final r = await s.sync(force: true);
    if (!mounted) return;
    final msg = s.lastSyncError != null
        ? 'Envoi interrompu : ${s.lastSyncError}. Nouvel essai automatique plus tard.'
        : r == null
        ? 'Synchronisation déjà en cours.'
        : r.rejected > 0
        ? '${r.sent} envoyé(s), ${r.rejected} refusé(s) : voir les producteurs marqués « Refusé ».'
        : 'À jour${r.sent > 0 ? ' : ${r.sent} envoi(s)' : ''}.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _signOut() async {
    final n = s.pending.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: Text(
          n == 0
              ? 'Toutes vos saisies sont envoyées.'
              : '$n saisie(s) ne sont pas encore envoyées. Elles restent sur le téléphone et partiront quand vous vous reconnecterez avec ce compte.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Se déconnecter')),
        ],
      ),
    );
    if (ok == true) await s.signOut();
  }

  void _open(Producer? p) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ProducerPage(services: s, producer: p),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final list = s.producerList.where((p) => p.matches(_query)).toList();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Producteurs'),
            actions: [
              IconButton(
                key: const Key('sync'),
                tooltip: 'Synchroniser',
                onPressed: s.syncing ? null : _sync,
                icon: Badge(
                  isLabelVisible: s.pendingCount > 0,
                  label: Text('${s.pendingCount}'),
                  child: s.syncing
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => v == 'logout' ? _signOut() : null,
                itemBuilder: (_) => [
                  PopupMenuItem(enabled: false, child: Text(s.account?.name ?? '')),
                  const PopupMenuItem(value: 'logout', child: Text('Se déconnecter')),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('new-producer'),
            onPressed: () => _open(null),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Nouveau producteur'),
          ),
          body: Column(
            children: [
              if (s.sessionExpired)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Notice(
                    title: 'Session expirée',
                    text: 'Reconnectez-vous pour envoyer vos saisies. Elles restent sur le téléphone.',
                    actions: [FilledButton(onPressed: s.signOut, child: const Text('Se reconnecter'))],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: TextField(
                  key: const Key('search'),
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nom, téléphone, carte ou village'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text('${list.length} producteur${list.length > 1 ? 's' : ''}', style: const TextStyle(color: Colors.black54)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s.pendingCount > 0
                            ? '${s.pendingCount} à envoyer'
                            : s.syncedAt == null
                            ? 'Jamais synchronisé'
                            : 'Synchronisé ${formatDateTime(s.syncedAt)}',
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _query.isEmpty
                                ? 'Aucun producteur pour l\'instant. Touchez « Nouveau producteur ».'
                                : 'Aucun producteur ne correspond.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                        itemCount: list.length,
                        itemBuilder: (_, i) => _ProducerTile(services: s, producer: list[i], onTap: () => _open(list[i])),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProducerTile extends StatelessWidget {
  const _ProducerTile({required this.services, required this.producer, required this.onTap});

  final AppServices services;
  final Producer producer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = producer;
    final nFields = services.fieldsOf(p.id).length;
    final details = [p.village, p.phone, if (p.memberCard != null) 'Carte ${p.memberCard}'].whereType<String>().join(' · ');
    final chip = services.rejectionFor(p.id) != null
        ? const StateChip('Refusé', color: GuisColors.clay)
        : services.isPending(p.id)
        ? const StateChip('À envoyer')
        : p.consentAt == null
        ? const StateChip('Consentement à recueillir', color: GuisColors.sky)
        : null;
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(p.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (details.isNotEmpty) Text(details),
            Text('$nFields champ${nFields > 1 ? 's' : ''}'),
            if (chip != null) Padding(padding: const EdgeInsets.only(top: 6), child: chip),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
