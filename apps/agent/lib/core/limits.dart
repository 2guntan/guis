/// Limites des saisies, les mêmes que celles du serveur (`apps/web/app/api/app/producers/[id]/route.ts`
/// et `fields/[id]/route.ts`) : vérifiées sur la fiche, elles évitent un « Refusé » découvert plus tard,
/// loin du producteur. À changer des deux côtés en même temps.
abstract final class Limits {
  /// Nom, prénom, variété de semence, nom du champ.
  static const name = 100;

  /// Carte de membre, village.
  static const text = 200;

  static const seedKg = 100000.0;
  static const seeds = 50;
  static const areaHa = 1000.0;
  static const contourPoints = 2000;
}

/// Message si le texte dépasse [max] caractères, sinon null.
String? tooLong(String? v, int max) => (v ?? '').trim().length > max ? '$max caractères au plus' : null;
