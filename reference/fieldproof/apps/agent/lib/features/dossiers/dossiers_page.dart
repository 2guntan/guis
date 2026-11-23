import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/model/dossier.dart';
import '../../core/services.dart';
import '../../ui/theme.dart';
import '../editor/editor_page.dart';

/// « Mes dossiers » : les dossiers du téléphone (hors ligne d'abord) et ceux que le
/// serveur connaît (`dossier.file_overview`), avec l'état de la synchronisation.
class DossiersPage extends StatefulWidget {
  const DossiersPage({super.key, required this.services});

  final AgentServices services;

  @override
  State<DossiersPage> createState() => _DossiersPageState();
}

class _DossiersPageState extends State<DossiersPage> with WidgetsBindingObserver {
  List<Dossier> _local = [];
  List<Map<String, dynamic>> _server = [];
  String _filter = 'all';

  AgentServices get s => widget.services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s.revision.addListener(_load);
    _load();
    s.refreshCounts();
    s.startAutoSync();
    unawaited(s.sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    s.revision.removeListener(_load);
    s.stopAutoSync();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(s.sync());
  }

  Future<void> _load() async {
    final local = await s.localDossiers();
    final server = await s.cachedServerFiles();
    if (mounted) {
      setState(() {
        _local = local;
        _server = server;
      });
    }
  }

  Future<void> _open(Dossier d, {int step = 0}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => EditorPage(services: s, dossier: d, initialStep: step)));
    await _load();
  }

  Future<void> _new() async {
    if (s.referentials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Synchronisez une première fois avec du réseau pour charger les listes.')));
    }
    final d = s.newDossier();
    await s.dossiers.put(d);
    if (mounted) await _open(d);
  }

  /// Un brouillon jamais synchronisé peut être supprimé du téléphone (appui long).
  Future<void> _delete(Dossier d) async {
    if (d.reference != null || d.lastSyncedAt != null || d.status != statusDraft) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ce dossier est déjà sur le serveur : il ne peut pas être supprimé du téléphone.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer ce brouillon ?'),
        content: Text('« ${d.displayName} » n\'a jamais été envoyé. Ses données et ses photos seront effacées du téléphone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Garder')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: FpColors.clay), onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok == true) await s.deleteLocalDraft(d);
  }

  bool _matches(String status, bool pending) => switch (_filter) {
        'draft' => status == statusDraft && !pending,
        'submitted' => status == statusSubmitted || pending,
        'returned' => status == statusReturned,
        'sent' => status == statusSent || status == statusClosed,
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final localIds = {for (final d in _local) d.id};
    final serverOnly = _server.where((r) => !localIds.contains(r['id'])).toList();
    final returned = _local.where((d) => d.status == statusReturned).length;
    final items = [
      for (final d in _local)
        if (_matches(d.status, d.submitPending)) _LocalTile(dossier: d, onTap: () => _open(d, step: d.editable ? 0 : 8), onLongPress: () => _delete(d)),
      for (final r in serverOnly)
        if (_matches(r['status'] as String, false)) _ServerTile(row: r),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes dossiers'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'signout') {
                final pending = s.status.value.pending;
                final ok = pending == 0 ||
                    await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Se déconnecter ?'),
                            content: Text('$pending envoi(s) en attente partiront à la prochaine connexion de ce compte.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
                              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Se déconnecter')),
                            ],
                          ),
                        ) ==
                        true;
                if (ok) await s.signOut();
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'signout', child: Text('Se déconnecter'))],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-dossier'),
        onPressed: _new,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau dossier'),
      ),
      body: RefreshIndicator(
        onRefresh: () => s.sync(force: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            SyncBanner(services: s),
            if (returned > 0)
              Notice(
                title: '$returned dossier${returned > 1 ? 's' : ''} renvoyé${returned > 1 ? 's' : ''}',
                text: 'Le superviseur demande des corrections : ouvrez le dossier pour lire le motif.',
                icon: Icons.reply,
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final f in const {'all': 'Tous', 'draft': 'Brouillons', 'submitted': 'Soumis', 'returned': 'Renvoyés', 'sent': 'Envoyés'}.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(label: Text(f.value), selected: _filter == f.key, onSelected: (_) => setState(() => _filter = f.key)),
                  ),
              ]),
            ),
            const SizedBox(height: 6),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('Aucun dossier. Touchez « Nouveau dossier » pour commencer une collecte.', textAlign: TextAlign.center),
              ),
            ...items,
          ],
        ),
      ),
    );
  }
}

/// Envois en attente, refus, dernière synchronisation, bouton « Synchroniser ».
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key, required this.services});

  final AgentServices services;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SyncStatus>(
        valueListenable: services.status,
        builder: (context, st, _) {
          final ok = st.pending == 0 && st.rejected == 0 && st.lastError == null;
          final color = st.rejected > 0 ? FpColors.clay : (st.pending > 0 || st.lastError != null ? FpColors.ochre : FpColors.forest);
          return Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(children: [
                Icon(ok ? Icons.cloud_done_outlined : (st.lastError != null ? Icons.cloud_off_outlined : Icons.cloud_upload_outlined), color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      st.pending == 0 ? 'Tout est envoyé' : '${st.pending} envoi${st.pending > 1 ? 's' : ''} en attente',
                      key: const Key('sync-pending'),
                      style: TextStyle(fontWeight: FontWeight.w700, color: color),
                    ),
                    if (st.rejected > 0) Text('${st.rejected} refusé${st.rejected > 1 ? 's' : ''} : voir le dossier', style: const TextStyle(color: FpColors.clay)),
                    Text('Dernière synchro : ${formatDateTime(st.lastSyncAt)}', style: const TextStyle(fontSize: 13, color: Colors.black54)),
                    if (st.lastError != null)
                      Text(st.lastError!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                  ]),
                ),
                st.syncing
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)))
                    : TextButton(key: const Key('sync-now'), onPressed: () => services.sync(force: true), child: const Text('Synchroniser')),
              ]),
            ),
          );
        },
      );
}

class _LocalTile extends StatelessWidget {
  const _LocalTile({required this.dossier, required this.onTap, required this.onLongPress});

  final Dossier dossier;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final d = dossier;
    final phone = (d.client['phone'] as String?) ?? '';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(d.displayName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              StatusChip(d.status, pending: d.submitPending),
            ]),
            const SizedBox(height: 4),
            Text([d.reference ?? 'Non synchronisé', if (phone.isNotEmpty) phone, '${d.parcels.length} parcelle(s)'].join(' · '),
                style: const TextStyle(color: Colors.black54)),
            Text('Modifié le ${formatDateTime(d.updatedAt)}', style: const TextStyle(color: Colors.black54, fontSize: 13)),
            if (d.status == statusReturned && (d.returnReason ?? '').isNotEmpty)
              Notice(title: 'Motif du renvoi', text: d.returnReason!, icon: Icons.reply),
            if (d.serverMessage != null) Notice(title: 'Message du serveur', text: d.serverMessage!),
          ]),
        ),
      ),
    );
  }
}

/// Un dossier connu du serveur mais absent de ce téléphone (autre appareil, réinstallation) : lecture seule.
class _ServerTile extends StatelessWidget {
  const _ServerTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final status = row['status'] as String;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text((row['client_name'] as String?)?.trim().isNotEmpty == true ? row['client_name'] as String : 'Client', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
            StatusChip(status),
          ]),
          const SizedBox(height: 4),
          Text(
            [row['reference'], row['commune_name'] ?? row['locality'] ?? row['region_name'], '${row['parcel_count'] ?? 0} parcelle(s)', formatHa(row['total_gps_area_ha'] as num?)]
                .whereType<Object>()
                .join(' · '),
            style: const TextStyle(color: Colors.black54),
          ),
          const Text('Sur le serveur (saisi sur un autre téléphone)', style: TextStyle(color: Colors.black45, fontSize: 13)),
          if (status == statusReturned && (row['return_reason'] as String? ?? '').isNotEmpty)
            Notice(title: 'Motif du renvoi', text: row['return_reason'] as String, icon: Icons.reply),
        ]),
      ),
    );
  }
}
