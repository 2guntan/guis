import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/services.dart';
import '../../ui/theme.dart';

/// Connexion par numéro de téléphone et mot de passe (comptes créés par script).
/// Reprise de Fieldproof : adresse électronique remplacée par le téléphone, Supabase par l'API Guis.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.services});

  final AppServices services;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidden = true;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.services.signIn(_phone.text.trim(), _password.text);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Connexion impossible : vérifiez le réseau (${errorMessage(e)}).');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          children: [
            const SizedBox(height: 40),
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: GuisColors.forest, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.travel_explore, color: GuisColors.ochre, size: 34),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Guis',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: GuisColors.forest, fontWeight: FontWeight.w700),
                      ),
                      const Text(
                        'Collecte des champs',
                        style: TextStyle(color: GuisColors.ochre, fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Producteurs, semences et champs, avec ou sans réseau.', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 32),
            TextField(
              key: const Key('phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Numéro de téléphone',
                hintText: '77 123 45 67',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
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
            FilledButton(key: const Key('sign-in'), onPressed: _busy ? null : _signIn, child: Text(_busy ? 'Connexion…' : 'Se connecter')),
            const SizedBox(height: 16),
            const Text(
              'La première connexion demande du réseau ; ensuite, l\'application fonctionne hors ligne.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
