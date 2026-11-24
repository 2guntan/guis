# Brief de design Guis, V1 (pour Paper)

Ce brief sert à dessiner dans Paper (paper.design) les écrans de l'**app Android** et du **tableau de bord web**. Il décrit les écrans tels qu'ils sont déjà codés (`apps/agent`, `apps/web`) : la maquette doit les améliorer, pas inventer de nouveaux parcours. Le contexte métier est dans `NOTE-CADRAGE.md`.

## Principes

- **Textes en français**, simples, lisibles par des agents de terrain.
- **App** : téléphone Android d'entrée de gamme, **360 × 640**, en plein soleil, une main, souvent sans réseau. Grandes cibles (48 px au moins), fort contraste, aucun écran de configuration.
- **Web** : écran de bureau **1280 × 800** d'abord, utilisable aussi sur tablette.
- Données d'exemple **fictives** uniquement (aucun vrai producteur) : Awa DIOP, Moussa NDIAYE, Ibou FALL ; villages « Village A », « Village B » ; variétés Spunta et Sahel.

## Identité (reprise de Fieldproof, à affiner)

| Jeton | Valeur | Usage |
|---|---|---|
| forest | `#1F4D3A` (web `#163A2C` pour les fonds sombres) | barres, boutons principaux |
| sand | `#F4EEE1` | fond des écrans |
| sandDeep | `#E9DFCB` | bordures, fonds secondaires |
| ochre | `#C8892B` | accent, « à envoyer », courbe attendue |
| clay | `#B4442F` | erreurs, refus, alertes |
| sky | `#2F6B8E` | information, « consentement à recueillir » |
| ink | `#1E2420` | texte |

- Typographie web : Fraunces (titres) et Geist (texte). App : Roboto (Material 3).
- Logo : un œil sur un champ (*gis*, « voir » en wolof). À dessiner proprement.

### Couleurs des statuts satellite (carte, pastilles)

| Statut | Couleur |
|---|---|
| Sans contour | `#7C857E` |
| En attente d'images | `#CFC4AA` |
| Semé, sol nu | `#D9A23F` |
| Levée | `#7FA68C` |
| En croissance | `#2F6B4F` |
| Pic | `#1E4D3A` |
| Sénescence / récolte | `#C08A2B` |

## App Android (agent de la coopérative), 6 écrans

1. **Connexion** : logo, « Guis : Collecte des champs », numéro de téléphone (`77 123 45 67`), mot de passe avec œil, bouton « Se connecter », note « La première connexion demande du réseau ; ensuite, l'application fonctionne hors ligne. » États : erreur « Numéro ou mot de passe incorrect. », chargement.
2. **Producteurs** (accueil) : barre « Producteurs » avec bouton Synchroniser (pastille du nombre à envoyer) et menu (nom de l'agent, Se déconnecter) ; recherche « Nom, téléphone, carte ou village » ; ligne « 124 producteurs · Synchronisé 23/11/2026 10:42 » ou « 3 à envoyer » ; cartes producteur avec nom, village · téléphone · carte, « 2 champs », et une pastille d'état : « À envoyer » (ocre), « Refusé » (argile), « Consentement à recueillir » (bleu, pour un producteur importé). Bouton flottant « Nouveau producteur ». États : liste vide, session expirée (encadré « Se reconnecter »), synchronisation en cours.
3. **Fiche producteur** : identité (nom, prénom, téléphone, carte de membre, Femme/Homme, village avec suggestions) ; photo (aperçu et « Prendre une photo ») ; **consentement** (texte à lire au producteur, case « Le producteur a donné son accord », date une fois coché) ; **semences reçues** (lignes « Spunta, 50 kg, reçue le 10/11/2026 », ajouter, supprimer) ; **champs** (« Champ 1 : mesurée 1,19 ha · déclarée 1,5 ha · semé le 15/11/2026 », « Ajouter un champ ») ; bouton « Enregistrer ». États : refus du serveur (encadré argile, « Écarter »), consentement manquant.
4. **Fenêtre « Semence reçue »** : variété avec suggestions, quantité en kg, date de réception, Annuler / Valider.
5. **Fiche champ** : nom du champ ; bloc **Contour** (« 4 sommets · surface mesurée 1,19 ha · 438 m de tour », bouton « Faire le tour du champ » ou « Reprendre le tour », problème éventuel en argile) ; **surface déclarée** en ha, avec l'aide « Écart avec la surface mesurée : −21 % » ; date de semis ; irrigation (goutte-à-goutte, aspersion, raie, arrosoir, autre) ; source d'eau (puits, forage, céane, bassin, réseau, autre) ; photo du champ ; « Enregistrer le champ ».
6. **Tour du champ (GPS)** : carte plein écran avec le tracé et les sommets numérotés ; encadré en haut « Précision : 4 m » (vert, ocre ou argile selon la précision), « 6 sommets · 1,02 ha · 412 m de tour » ; interrupteur « Relevé automatique en marchant (tous les 5 m) » ; boutons « Annuler », « Ajouter ce point », « Recommencer », « Terminer le tracé ». États : recherche du signal, point refusé (précision au-delà de 30 m), contour qui se croise.

## Tableau de bord web (coopérative et IBRIZ), 5 écrans

1. **Connexion** : panneau gauche vert sombre avec le logo et l'accroche « Les champs relevés sur le terrain, suivis depuis le ciel. » ; formulaire à droite (téléphone, mot de passe, « Se connecter »). États : identifiants faux, compte agent refusé.
2. **Tableau de bord** : en-tête (logo, Tableau de bord · Champs · Producteurs, nom, Quitter) ; 5 chiffres clés (Producteurs « 124, dont 31 sans champ relevé », Champs relevés « 142, dont 138 avec contour GPS », Surface mesurée « 186,4 ha, déclarée 201 ha, écart −7 % », Semences distribuées « 6 250 kg », Champs en alerte « 4 » en argile) ; grande carte satellite des champs colorés par statut ; légende avec le nombre de champs par statut.
3. **Champs** : titre et nombre, bouton « Exporter en Excel » ; filtres (recherche, village, agent, statut, case « En alerte ») ; tableau : producteur et nom du champ, village, surface mesurée, surface déclarée, écart (en argile au-delà de 20 %), semis, statut (pastille) et alertes, agent.
4. **Fiche champ** : retour « ← Champs », nom du producteur et pastille de statut ; carte du contour et tableau du champ (surfaces, écart, semis, irrigation, eau, sommets, relevé par, relevé le) ; **Suivi satellite** : alertes en argile, **courbe NDVI** (valeurs mesurées en vert sous forme d'aire, courbe attendue de la pomme de terre en pointillés ocre, trait vertical « Semis »), légende, « Dernier NDVI 0,48 », mention « suivi indicatif » si besoin ; **Producteur** (photo, téléphone, carte, consentement, semences) ; **Photo du champ**.
5. **Producteurs** : recherche, case « Sans champ relevé » ; tableau : photo et nom, téléphone et carte, village, semences, champs (lien et surface, ou pastille « Aucun champ relevé »), origine (« Import » ou nom de l'agent) et « Consentement à recueillir ».

## Livrables attendus dans Paper

- Une page « Fondations » : couleurs, typographies, logo, pastilles de statut, boutons, champs de saisie.
- Une page « App Android » : les 6 écrans en 360 × 640, plus les états principaux (liste vide, à envoyer, refusé, consentement à recueillir, point refusé).
- Une page « Tableau de bord » : les 5 écrans en 1280 × 800.
- Une fois validés, on reportera les maquettes dans le code (`apps/agent/lib/ui/theme.dart`, `apps/web/tailwind.config.ts`, puis les écrans).
