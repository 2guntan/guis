import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/services.dart';
import '../../ui/theme.dart';

/// Connexion par numéro de téléphone et mot de passe (maquette android/01-connexion).
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
    final error = _error != null;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          children: [
            const Align(alignment: Alignment.centerLeft, child: LogoMark(size: 64)),
            const SizedBox(height: 20),
            const Text(
              'Guis',
              style: TextStyle(fontFamily: 'Fraunces', fontSize: 40, height: 1.1, fontWeight: FontWeight.w600, color: GuisColors.forest),
            ),
            const SizedBox(height: 4),
            const Text(
              'Collecte des champs',
              style: TextStyle(fontFamily: 'Fraunces', fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 36),
            const FieldLabel('Numéro de téléphone'),
            TextField(
              key: const Key('phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                hintText: '77 123 45 67',
                prefixIcon: Padding(
                  padding: EdgeInsets.only(left: 16, right: 10),
                  child: Text('+221', style: TextStyle(fontSize: 18, color: GuisColors.muted)),
                ),
                prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
              ),
            ),
            const SizedBox(height: 16),
            FieldLabel('Mot de passe', color: error ? GuisColors.clay : null),
            TextField(
              key: const Key('password'),
              controller: _password,
              obscureText: _hidden,
              autofillHints: const [AutofillHints.password],
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                fillColor: error ? const Color(0xFFF9EFEC) : Colors.white,
                enabledBorder: error
                    ? const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: GuisColors.clay, width: 1.5),
                      )
                    : null,
                suffixIcon: IconButton(
                  tooltip: _hidden ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
                  icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _hidden = !_hidden),
                ),
              ),
              onSubmitted: (_) => _signIn(),
            ),
            if (error)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: GuisColors.clay, fontSize: 15)),
              ),
            const SizedBox(height: 24),
            FilledButton(key: const Key('sign-in'), onPressed: _busy ? null : _signIn, child: Text(_busy ? 'Connexion…' : 'Se connecter')),
            const SizedBox(height: 48),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: GuisColors.sky),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'La première connexion demande du réseau ; ensuite, l\'application fonctionne hors ligne.',
                    style: TextStyle(color: GuisColors.muted, fontSize: 15, height: 1.4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
