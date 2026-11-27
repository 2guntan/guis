import 'package:flutter/material.dart';

import 'theme.dart';

/// Demande confirmation avant une action qui efface la saisie de l'agent. Vrai si confirmée.
Future<bool> confirmLoss(
  BuildContext context, {
  required String title,
  required String text,
  required String confirm,
  String cancel = 'Continuer la saisie',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, style: GuisText.sectionTitle),
      content: Text(text),
      actions: [
        TextButton(key: const Key('keep-editing'), onPressed: () => Navigator.pop(c, false), child: Text(cancel)),
        FilledButton(
          key: const Key('confirm-loss'),
          style: FilledButton.styleFrom(backgroundColor: GuisColors.clay),
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Retour arrière (bouton, geste système) protégé : si [isDirty] est vrai au moment du retour, l'agent
/// confirme avant de perdre sa saisie. Évalué à chaque retour (une frappe au clavier ne reconstruit pas l'écran).
class UnsavedGuard extends StatelessWidget {
  const UnsavedGuard({
    super.key,
    required this.isDirty,
    required this.child,
    this.title = 'Quitter sans enregistrer ?',
    this.text = 'Les modifications de cette fiche ne sont pas enregistrées et seront perdues.',
    this.confirm = 'Quitter',
  });

  final bool Function() isDirty;
  final Widget child;
  final String title;
  final String text;
  final String confirm;

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      if ((!isDirty() || await confirmLoss(context, title: title, text: text, confirm: confirm)) && context.mounted) {
        Navigator.of(context).pop();
      }
    },
    child: child,
  );
}
