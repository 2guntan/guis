import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/services.dart';
import '../../ui/theme.dart';

/// Connexion par numéro de téléphone et code de 4 chiffres (maquette android/01-connexion, ADR-0003).
/// L'admin peut passer au mot de passe (clavier texte). Après 5 essais faux, le serveur bloque
/// 15 minutes (429) ; un compte coordinateur est refusé (403) : l'app affiche le message du serveur.
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
  bool _passwordMode = false;
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
      setState(
        () => _error = e.status == 401 ? (_passwordMode ? 'Numéro ou mot de passe incorrect.' : 'Numéro ou code incorrect.') : e.message,
      );
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
            FieldLabel(_passwordMode ? 'Mot de passe' : 'Code', color: error ? GuisColors.clay : null),
            TextField(
              key: ValueKey(_passwordMode ? 'password' : 'code'),
              controller: _password,
              obscureText: _hidden,
              keyboardType: _passwordMode ? TextInputType.visiblePassword : TextInputType.number,
              autofillHints: const [AutofillHints.password],
              style: TextStyle(fontSize: 18, letterSpacing: _passwordMode ? null : 6),
              decoration: InputDecoration(
                hintText: _passwordMode ? null : '4 chiffres',
                fillColor: error ? const Color(0xFFF9EFEC) : Colors.white,
                enabledBorder: error
                    ? const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: GuisColors.clay, width: 1.5),
                      )
                    : null,
                suffixIcon: IconButton(
                  tooltip: _hidden ? 'Afficher' : 'Masquer',
                  icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _hidden = !_hidden),
                ),
              ),
              onSubmitted: (_) => _signIn(),
            ),
            if (error)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: const Key('sign-in-error'),
                  style: const TextStyle(color: GuisColors.clay, fontSize: 15),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('password-mode'),
                onPressed: () => setState(() {
                  _passwordMode = !_passwordMode;
                  _password.clear();
                  _error = null;
                }),
                child: Text(_passwordMode ? 'Se connecter avec un code' : 'Se connecter avec un mot de passe (admin)'),
              ),
            ),
            const SizedBox(height: 16),
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
