# Guis — specs de design (maquettes V1, novembre 2026)

Source : fichier Paper « Guis — maquettes V1 ». Ce dossier en est la copie de référence pour le code.
Les captures PNG montrent le rendu attendu ; les valeurs exactes sont ci-dessous.
Toutes les données des maquettes sont fictives.

Lire avec `BRIEF-PAPER.md` (le brief de départ) quand il est présent.

## Ce qui est retenu

| Surface | Écrans de référence | Direction |
|---|---|---|
| App Android | `android/*.png` (14 écrans, états d'erreur compris) | unique |
| Tableau de bord web — connexion | `web/w1-connexion.png` | A |
| Tableau de bord web — reste | `web/w2-carte.png` à `web/w5-producteurs.png` | B « Relevé » |
| Couleurs, typo, composants communs | `fondations.png` | — |

## Polices (Android et web)

- **Fraunces** (titres, gros chiffres) — poids 600, `letter-spacing: -0.005em`.
- **Geist** (tout le reste : texte, libellés, boutons, tableaux).
- **Geist Mono** : seulement pour les échantillons de la page Fondations, pas dans les écrans.
- Roboto et Archivo ne sont plus utilisées.
- Les deux polices sont sur Google Fonts. Android : les embarquer dans `res/font/` (l'app travaille hors ligne).

### Échelle Android

| Rôle | Police | Taille / interligne | Poids |
|---|---|---|---|
| Titre d'écran (barre du haut) | Fraunces | 22 / 28 px (20 px pour un nom long, ex. « Awa DIOP ») | 600 |
| Titre de section | Fraunces | 18 / 24 | 600 |
| Gros chiffre (surface) | Fraunces | 26 / 32 (32 px sur la fiche champ) | 600 |
| Nom dans une liste | Geist | 18 / 24 | 600 |
| Texte lu au producteur | Geist | 16 / 24 | 400 |
| Bouton | Geist | 16 / 24 | 600 |
| Texte secondaire | Geist | 14 / 20 | 400 |

Règles : texte 14 px minimum ; pas d'italique ni de majuscules espacées ; zones tactiles 48 × 48 px minimum ; bouton principal 52 px de haut, pleine largeur, fixé en bas des formulaires. Les chiffres de surface ne passent jamais à la ligne (`maxLines = 1`).

### Échelle web

| Rôle | Police | Taille / interligne | Poids |
|---|---|---|---|
| Titre de page (barre du haut) | Fraunces | 22 / 28 | 650 |
| Grand chiffre (ex. « 142 ») | Fraunces | 40 / 44 | 600 |
| Titre de bloc (ex. « 4 champs à vérifier ») | Fraunces | 18 / 24 | 600 |
| Nom en tête de ligne | Geist | 15 / 20 | 650 |
| Texte, cellules, filtres, boutons | Geist | 14 / 18-19 | 400 (600 boutons) |
| Métadonnées, légende | Geist | 13 / 16-18 | 400 |
| Libellés du rail | Geist | 11 / 14 | 500 (600 actif) |

## Couleurs communes (tokens)

```css
:root {
  --color-sand: #F4EEE1;       /* fond app Android */
  --color-surface: #FFFFFF;    /* cartes */
  --color-sand-deep: #E9DFCB;  /* bordures */
  --color-ink: #1E2420;        /* texte */
  --color-muted: #5A635D;      /* texte secondaire */
  --color-forest: #1F4D3A;     /* marque : barres, boutons */
  --color-forest-dark: #163A2C;
  --color-ochre: #C8892B;      /* « à envoyer », bouton flottant */
  --color-clay: #B4442F;       /* erreur, refus */
  --color-sky: #2F6B8E;        /* information */

  /* Statuts satellite — app Android et pastilles */
  --color-st-none: #7C857E;    /* sans contour */
  --color-st-wait: #CFC4AA;    /* en attente d'images */
  --color-st-bare: #D9A23F;    /* semé, sol nu */
  --color-st-emerge: #7FA68C;  /* levée */
  --color-st-grow: #2F6B4F;    /* en croissance */
  --color-st-peak: #1E4D3A;    /* pic */
  --color-st-senesce: #C08A2B; /* sénescence / récolte */

  --font-display: "Fraunces";
  --font-body: "Geist";
  --font-app: "Geist";

  --spacing-xs: 4px; --spacing-sm: 8px; --spacing-md: 16px;
  --spacing-lg: 24px; --spacing-xl: 40px;
  --radius-sm: 6px; --radius-md: 12px; --radius-lg: 20px;
}
```

Le logo (carré arrondi vert forêt, soleil ocre, sillons) est sur `fondations.png` et en haut du rail web.

## Tableau de bord web — direction B « Relevé » (W2 à W5)

Mise en page : rail vertical à gauche, barre du haut, contenu. Plus froid et plus dense que l'app.

| Élément | Valeur |
|---|---|
| Fond de page, barre du haut | `#EEF1EC` (craie) |
| Rail de navigation | 72 px de large, fond `#1F4D3A` ; item actif fond `#2E6A51`, radius 10 px, 60 px de large ; icônes et libellés inactifs `#BFD3C7` |
| Barre du haut | 64 px, bordure basse 1 px `#D3DAD0`, marges 24 px |
| Texte principal | `#163A2C` |
| Texte secondaire | `#4F5F55` ; texte d'aide, champ de recherche `#6B7A70` |
| Bordures | `#D3DAD0` ; séparateurs de lignes `#E5EAE2` |
| Champs de saisie, filtres | fond blanc, bordure 1 px `#D3DAD0`, radius 8 px, 40 px de haut |
| Bouton principal | fond `#1F4D3A`, texte blanc, radius 8 px, 40 px de haut |
| Alerte « à vérifier » | jaune `#E0A100` : bordure gauche 4 px, fond de ligne `#FFF6DC` ; cercle 4 px autour du champ sur la carte |
| Panneau latéral de la carte | 360 px, fond blanc, bordure gauche `#D3DAD0` |

Rampe NDVI de la carte et de la légende web (remplace les `--color-st-*` côté web) :

| Statut | Couleur |
|---|---|
| Sans contour | pas de remplissage, contour pointillé `#163A2C` |
| En attente d'images | `#D5D8D0` |
| Semé, sol nu | `#B49A74` |
| Levée | `#A9C47F` |
| En croissance | `#5E9B4E` |
| Pic | `#1F5E33` |
| Sénescence | `#C9A24A` |

Fond de carte (placeholder des maquettes) : `#CFC8B4`. En production, la carte affiche un vrai fond satellite ou cartographique.

## Écran de connexion web (W1, direction A)

Voir `web/w1-connexion.png` : fond sable `#F4EEE1`, logo, titre en Fraunces, champs et bouton vert forêt. C'est la seule page web en direction A.

## Fichiers

```
docs/design/
  SPECS.md          ce fichier
  fondations.png    couleurs, typo, pastilles, boutons, champs, règles
  android/          01 connexion … 06c tour — contour qui se croise
  web/              w1 connexion (A), w2 carte … w5 producteurs (B)
```

Les maquettes ne sont pas pixel-parfaites : en cas de doute, suivre ce fichier plutôt que la capture.
