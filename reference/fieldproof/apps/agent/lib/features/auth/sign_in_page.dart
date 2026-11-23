import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../ui/theme.dart';

/// Connexion par adresse et mot de passe (comptes créés par IBRIZ). Le message d'Auth
/// s'affiche tel quel ; la session est gardée sur le téléphone par supabase_flutter.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.client});

  final SupabaseClient client;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidden = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.auth.signInWithPassword(email: _email.text.trim().toLowerCase(), password: _password.text);
    } on AuthException catch (e) {
      setState(() => _error = e.message == 'Invalid login credentials' ? 'Adresse ou mot de passe incorrect.' : e.message);
    } catch (e) {
      setState(() => _error = 'Connexion impossible : vérifiez le réseau.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 24), children: [
          const SizedBox(height: 40),
          Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: FpColors.forest, borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.verified_outlined, color: FpColors.ochre, size: 34),
            ),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Fieldproof', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: FpColors.forest, fontWeight: FontWeight.w700)),
              const Text('Agent terrain', style: TextStyle(color: FpColors.ochre, fontWeight: FontWeight.w600, fontSize: 16)),
            ]),
          ]),
          const SizedBox(height: 16),
          const Text('Collecte des dossiers clients, avec ou sans réseau.', style: TextStyle(fontSize: 15)),
          const SizedBox(height: 32),
          TextField(
            key: const Key('email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Adresse électronique', prefixIcon: Icon(Icons.alternate_email)),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('password'),
            controller: _password,
            obscureText: _hidden,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _hidden ? 'Afficher' : 'Masquer',
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
            onSubmitted: (_) => _signIn(),
          ),
          if (_error != null) Notice(title: 'Connexion refusée', text: _error!),
          const SizedBox(height: 24),
          FilledButton(onPressed: _busy ? null : _signIn, child: Text(_busy ? 'Connexion…' : 'Se connecter')),
          const SizedBox(height: 16),
          const Text('La première connexion demande du réseau ; ensuite, l\'application fonctionne hors ligne.',
              style: TextStyle(color: Colors.black54)),
        ]),
      ),
    );
  }
}
