import 'package:flutter/material.dart';

import '../../core/model/models.dart';
import '../../core/services.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import 'producer_page.dart';

/// Accueil (maquettes android/02*) et état de la synchronisation.
/// - Admin : tous les producteurs, avec une recherche libre.
/// - Agent (ADR-0001) : pas de liste complète. Une recherche exacte par téléphone ou numéro de carte,
///   et « Mes producteurs » (ceux qu'il a déjà ouverts ou créés). Sans résultat : « Nouveau producteur ».
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
        title: const Text('Se déconnecter ?', style: GuisText.sectionTitle),
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

  bool get _admin => s.account?.isAdmin ?? false;

  void _open(Producer? p, {String? phone}) {
    if (p != null && !_admin) s.markMine(p.id);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProducerPage(services: s, producer: p, initialPhone: phone),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final admin = _admin;
        final q = _query.trim();
        final list = admin
            ? s.producerList.where((p) => p.matches(_query)).toList()
            : q.isEmpty
            ? s.myProducers
            : s.searchExact(q);
        return Scaffold(
          appBar: AppBar(
            title: Text(admin ? 'Producteurs' : 'Mes producteurs'),
            toolbarHeight: 72,
            actions: [
              IconButton(
                key: const Key('sync'),
                tooltip: 'Synchroniser',
                onPressed: s.syncing ? null : _sync,
                icon: Badge(
                  isLabelVisible: s.pendingCount > 0,
                  backgroundColor: GuisColors.ochre,
                  textColor: GuisColors.ink,
                  label: Text('${s.pendingCount}'),
                  child: const Icon(Icons.sync, color: Colors.white, size: 28),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Menu',
                iconColor: Colors.white,
                onSelected: (v) => v == 'logout' ? _signOut() : null,
                itemBuilder: (_) => [
                  PopupMenuItem(enabled: false, child: Text(s.account?.name ?? '')),
                  const PopupMenuItem(value: 'logout', child: Text('Se déconnecter')),
                ],
              ),
              const SizedBox(width: 4),
            ],
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(s.syncing ? 84 : 80),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: TextField(
                      key: const Key('search'),
                      onChanged: (v) => setState(() => _query = v),
                      style: const TextStyle(fontSize: 16),
                      decoration: InputDecoration(
                        hintStyle: const TextStyle(fontSize: 16, color: GuisColors.muted),
                        prefixIcon: const Icon(Icons.search, color: GuisColors.muted),
                        hintText: admin ? 'Nom, téléphone, carte, village ou commune' : 'Téléphone ou n° de carte complet',
                        enabledBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  if (s.syncing) const LinearProgressIndicator(minHeight: 4, color: GuisColors.ochre, backgroundColor: Color(0xFF4F7A65)),
                ],
              ),
            ),
          ),
          // L'agent crée un producteur depuis une recherche sans résultat (numéro déjà rempli).
          floatingActionButton: admin
              ? FloatingActionButton.extended(
                  key: const Key('new-producer'),
                  onPressed: () => _open(null),
                  icon: const Icon(Icons.add, size: 28),
                  label: const Text('Nouveau producteur'),
                )
              : null,
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${list.length}',
                            style: const TextStyle(fontWeight: FontWeight.w600, color: GuisColors.ink),
                          ),
                          TextSpan(
                            text: !admin && q.isNotEmpty
                                ? (list.length > 1 ? ' résultats' : ' résultat')
                                : (list.length > 1 ? ' producteurs' : ' producteur'),
                          ),
                        ],
                      ),
                      style: const TextStyle(fontSize: 16, color: GuisColors.muted),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _SyncStatus(services: s)),
                  ],
                ),
              ),
              if (s.sessionExpired)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: Notice(
                    title: 'Session expirée',
                    text: 'Vos saisies sont gardées sur le téléphone. Reconnectez-vous pour les envoyer.',
                    icon: Icons.lock_outline,
                    actions: [
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: GuisColors.clay),
                        onPressed: s.signOut,
                        child: const Text('Se reconnecter'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: list.isEmpty
                    ? (admin
                          ? _Empty(searching: _query.isNotEmpty)
                          : _AgentEmpty(
                              query: q,
                              onCreate: () => _open(null, phone: localPhoneDigits(q) != null ? q : null),
                            ))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 104),
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

class _SyncStatus extends StatelessWidget {
  const _SyncStatus({required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final s = services;
    final (dot, text, color) = s.syncing
        ? (GuisColors.ochre, 'Envoi en cours…', GuisColors.ochreText)
        : s.pendingCount > 0
        ? (GuisColors.ochre, '${s.pendingCount} à envoyer', GuisColors.ochreText)
        : s.syncedAt == null
        ? (GuisColors.muted, 'Jamais synchronisé', GuisColors.muted)
        : (GuisColors.forest, 'Synchronisé ${formatDateTime(s.syncedAt).replaceFirst(' à ', ' ')}', GuisColors.muted);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 16, color: color),
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 104),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 104,
            height: 104,
            decoration: const BoxDecoration(color: GuisColors.sandDeep, shape: BoxShape.circle),
            child: Icon(searching ? Icons.search_off : Icons.download, size: 40, color: GuisColors.forest),
          ),
          const SizedBox(height: 20),
          Text(
            searching ? 'Aucun producteur ne correspond' : 'Aucun producteur pour l\'instant',
            textAlign: TextAlign.center,
            style: GuisText.sectionTitle.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 10),
          Text(
            searching
                ? 'Vérifiez l\'orthographe, ou cherchez par téléphone ou numéro de carte.'
                : 'Touchez « Nouveau producteur » pour enregistrer le premier. Les producteurs importés par la coopérative apparaîtront ici après la synchronisation.',
            textAlign: TextAlign.center,
            style: GuisText.secondary.copyWith(fontSize: 16, height: 1.45),
          ),
        ],
      ),
    ),
  );
}

/// Agent : rien encore dans « Mes producteurs », numéro incomplet, ou aucun producteur avec ce numéro.
class _AgentEmpty extends StatelessWidget {
  const _AgentEmpty({required this.query, required this.onCreate});

  final String query;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final digits = query.replaceAll(RegExp(r'\D'), '');
    final incomplete = query.isNotEmpty && !RegExp(r'[A-Za-z]').hasMatch(query) && localPhoneDigits(query) == null && digits.length < 9;
    final (icon, title, text) = query.isEmpty
        ? (
            Icons.search,
            'Cherchez un producteur',
            'Saisissez son numéro de téléphone complet ou son numéro de carte de membre. Les producteurs que vous ouvrez s\'ajoutent ici.',
          )
        : incomplete
        ? (Icons.dialpad, 'Numéro incomplet', 'Saisissez les 9 chiffres du téléphone, par exemple 77 123 45 67.')
        : (
            Icons.search_off,
            'Aucun producteur avec ce numéro',
            'Vérifiez le numéro. S\'il s\'agit d\'un nouveau producteur, enregistrez-le.',
          );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 104),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: const BoxDecoration(color: GuisColors.sandDeep, shape: BoxShape.circle),
              child: Icon(icon, size: 40, color: GuisColors.forest),
            ),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: GuisText.sectionTitle.copyWith(fontSize: 20)),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: GuisText.secondary.copyWith(fontSize: 16, height: 1.45)),
            if (query.isNotEmpty && !incomplete) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const Key('new-producer'),
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Nouveau producteur'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProducerTile extends StatelessWidget {
  const _ProducerTile({required this.services, required this.producer, required this.onTap});

  final AppServices services;
  final Producer producer;
  final VoidCallback onTap;

  static const _avatars = [
    (GuisColors.forestSoft, GuisColors.forest),
    (GuisColors.skySoft, GuisColors.skyText),
    (GuisColors.ochreSoft, GuisColors.ochreText),
  ];

  @override
  Widget build(BuildContext context) {
    final p = producer;
    final nFields = services.fieldsOf(p.id).length;
    final details = [
      p.village,
      formatPhone(p.phone),
      if (p.memberCard != null) 'n° ${p.memberCard}',
    ].where((x) => x != null && x.isNotEmpty).join(' · ');
    final chip = services.rejectionFor(p.id) != null
        ? const StateChip('Refusé', tone: ChipTone.clay)
        : services.isPending(p.id)
        ? const StateChip('À envoyer')
        : p.consentAt == null
        ? const StateChip('Consentement à recueillir', tone: ChipTone.sky)
        : services.recentlySent.contains(p.id)
        ? const StateChip('Envoyé', tone: ChipTone.forest)
        : null;
    final wide = p.consentAt == null && chip != null && services.rejectionFor(p.id) == null && !services.isPending(p.id);
    final (bg, fg) = _avatars[p.id.hashCode.abs() % _avatars.length];
    final fields = Text(
      nFields == 0 ? 'Aucun champ' : '$nFields champ${nFields > 1 ? 's' : ''}',
      style: TextStyle(fontSize: 16, color: nFields == 0 ? GuisColors.muted : GuisColors.ink),
    );
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: bg,
                child: Text(
                  initials(p.firstName, p.lastName),
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.fullName, style: GuisText.listName),
                    if (details.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(details, style: GuisText.secondary.copyWith(fontSize: 15)),
                      ),
                    const SizedBox(height: 10),
                    if (wide) ...[
                      fields,
                      const SizedBox(height: 8),
                      chip,
                    ] else
                      Row(
                        children: [
                          Expanded(child: fields),
                          ?chip,
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
