import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/services.dart';
import 'core/sync/outbox.dart' show errorMessage;
import 'features/auth/sign_in_page.dart';
import 'features/dossiers/dossiers_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AgentConfig.missing.isNotEmpty) {
    runApp(_Message('Configuration absente : ${AgentConfig.missing.join(', ')}.\n'
        'Compiler avec --dart-define-from-file=env.json (voir apps/agent/README.md).'));
    return;
  }
  await Supabase.initialize(url: AgentConfig.supabaseUrl, publishableKey: AgentConfig.supabaseAnonKey);
  final services = await AgentServices.open(Supabase.instance.client);
  runApp(AgentApp(services: services));
}

class AgentApp extends StatelessWidget {
  const AgentApp({super.key, required this.services});

  final AgentServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fieldproof Agent',
      debugShowCheckedModeBanner: false,
      theme: fieldproofTheme(),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: StreamBuilder<AuthState>(
        stream: services.client.auth.onAuthStateChange,
        builder: (context, _) => services.client.auth.currentSession == null
            ? SignInPage(client: services.client)
            // La clé force un écran neuf à chaque changement de compte.
            : RoleGate(key: ValueKey(services.profileId), services: services),
      ),
    );
  }
}

/// Vérifie que le compte est agent terrain (`core.my_memberships()`), en ligne si possible,
/// sinon d'après le dernier rattachement gardé sur le téléphone.
class RoleGate extends StatefulWidget {
  const RoleGate({super.key, required this.services});

  final AgentServices services;

  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> {
  late Future<String?> _check = _run();

  /// Null si le compte peut travailler ; sinon le message à afficher.
  Future<String?> _run() async {
    final s = widget.services;
    await s.loadCachedReferentials();
    try {
      final m = await s.fetchMemberships();
      if (!m.any((x) => x['role'] == 'field_agent')) {
        final roles = m.map((x) => x['role']).toSet().join(', ');
        return 'Ce compte n\'est pas rattaché comme agent terrain${roles.isEmpty ? '' : ' (rôle : $roles)'}.\n'
            'L\'application agent est réservée aux agents terrain. Les superviseurs utilisent l\'application web.';
      }
      try {
        await s.refreshReferentials();
      } catch (_) {/* hors ligne : le cache suffit */}
    } catch (e) {
      if (s.referentials.memberships.isEmpty) {
        return 'Première connexion : le réseau est nécessaire pour vérifier votre rôle et charger les listes (${errorMessage(e)}).';
      }
      if (!s.referentials.isFieldAgent) return 'Ce compte n\'est pas rattaché comme agent terrain.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _check,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final problem = snap.data;
        if (problem == null) return DossiersPage(services: widget.services);
        return Scaffold(
          appBar: AppBar(title: const Text('Fieldproof Agent')),
          body: ListView(padding: const EdgeInsets.all(24), children: [
            Notice(title: 'Accès impossible', text: problem),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => setState(() => _check = _run()), child: const Text('Réessayer')),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: widget.services.signOut, child: const Text('Se déconnecter')),
          ]),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      MaterialApp(home: Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(text)))));
}
