# Guis — note de cadrage

Version 0.3 du 23/11/2026.

**Guis** (du wolof *gis*, « voir ») : application générique de collecte et de suivi satellite des champs. Premier usage : la campagne de pomme de terre d'une coopérative partenaire.

## 1. Objectif

Une coopérative partenaire distribue en ce moment des semences de pomme de terre à ses producteurs. Il faut :

1. **Identifier sur le terrain les champs réellement emblavés.** Pour chaque producteur, on relève qui il est, où se trouve son champ (contour GPS), sa surface et sa date de semis.
2. **Suivre ces champs par satellite** pendant la campagne, et le montrer sur un tableau de bord web.

C'est un projet **séparé de Fieldproof** : il n'y a ni prêteur, ni paquet, ni envoi, ni lien sécurisé, ni formulaire à remplir. On collecte, on cartographie, on suit. Fieldproof n'est pas modifié. On y **copie** du code, en traçant chaque copie dans un `PROVENANCE.md`, comme Fieldproof le fait déjà avec Agriva.

## 2. Périmètre minimal (V1)

| Surface | Ce qu'elle fait |
|---|---|
| **App Android** (agent de la coopérative) | Fonctionne hors ligne. Saisie du producteur, du champ (tour GPS du contour), du semis, d'une photo. Synchronisation dès qu'il y a du réseau. |
| **Tableau de bord web** (coopérative et IBRIZ) | Carte de tous les champs, liste filtrable, fiche d'un champ avec sa courbe satellite, chiffres clés, export Excel. |
| **Worker satellite** | Pour chaque champ, série NDVI Sentinel-2 depuis la date de semis, avec un statut et des alertes simples. |

Hors V1 : comptes des producteurs, SMS, rendement estimé, intrants autres que la semence, validation par un superviseur.

### Données collectées

**Producteur**
- nom, prénom, téléphone, numéro de carte de membre
- sexe, village / localité
- photo (facultative)
- consentement (une case cochée par l'agent, avec la date)

**Semences reçues**
- variété, quantité en kg, date de réception

**Champ** (un producteur peut en avoir plusieurs)
- contour GPS et surface mesurée (calculée)
- **surface emblavée déclarée** par le producteur
- date de semis
- irrigation : goutte-à-goutte, aspersion, raie, arrosoir…
- source d'eau : puits, forage, céane, bassin…
- photo géolocalisée

**Visites** (facultatives, en V1.1)
- date, stade observé, photo, remarque

La surface **mesurée** et la surface **déclarée** sont gardées toutes les deux. L'écart entre les deux est déjà un résultat utile pour la coopérative.

## 3. Ce qu'on reprend de Fieldproof, et ce qu'on change

| Brique Fieldproof | Reprise | Changement |
|---|---|---|
| `apps/agent` (Flutter) : `parcel_walk_page.dart`, `core/model/geo.dart` (surface, validité du contour), `core/photos.dart`, `core/json_store.dart`, `core/sync/outbox.dart`, `features/auth/sign_in_page.dart`, `ui/theme.dart` | **Copie** | On remplace les 9 étapes du dossier par 3 écrans : Producteur → Champ → Semis. On enlève le consentement signé, les pièces, la complétude et les statuts. |
| Synchronisation (ADR-0007) | L'idée seulement | Pas de statuts ni de verrou. L'agent écrit et le serveur fait un upsert par identifiant. Les photos montent avec reprise. |
| `db/migrations` | Modèle seulement | Un schéma **neuf et court** : `producers`, `fields`, `seed_distributions`, `ndvi_points`, `field_status`, `jobs`. Pas de `dossier`, `identity` ni `core` complet. |
| `workers/sat/sat/retro.py` : `scene_ndvi`, `select_items`, accès Planetary Computer, Dockerfile | **Copie** | On remplace l'analyse rétroactive par un **suivi depuis le semis**. La logique hivernage / contre-saison et le verdict de Fieldproof ne s'appliquent pas (voir §4). |
| `workers/sat/sat/radar.py` | Non | La pomme de terre pousse en saison sèche : le ciel est clair et Sentinel-2 suffit. |
| `apps/web` : `components/map/ParcelsMap*`, `superviseur/NdviChart.tsx`, `FilterBar.tsx`, `ui/*`, `AppHeader.tsx`, Tailwind | **Copie** | Un seul rôle, « coopérative ». On enlève tout ce qui concerne le prêteur et l'envoi. |
| `workers/docs` | Non | Le seul export est un Excel, généré directement dans le web. |

## 4. Suivi satellite de la pomme de terre

- **Campagne.** La pomme de terre se cultive en contre-saison froide et irriguée. Le semis a lieu de novembre à janvier et la récolte vers 90 à 110 jours. Les images sont claires presque tous les 5 jours.
- **Indicateur.** NDVI moyen sur le contour, à chaque image claire depuis la date de semis moins 15 jours. On le compare à une **courbe attendue en fonction du nombre de jours depuis le semis** :
  - sol nu au semis ;
  - levée vers J+20 à J+30 ;
  - pic vers J+50 à J+70 ;
  - sénescence ensuite.
- **Statuts d'un champ** : `en attente d'images` → `semé, sol nu` → `levée` → `en croissance` → `pic` → `sénescence / récolte`.
- **Alertes V1** :
  1. pas de levée à J+35 : semis non fait, échec, ou mauvais contour ;
  2. chute de NDVI de plus de 0,15 entre deux images hors fin de cycle : stress hydrique ou maladie, à vérifier ;
  3. champ déjà vert à la date de semis déclarée : date ou contour à vérifier.
- **Calcul.** Le worker recalcule tous les champs une fois par jour, plus une fois tout de suite quand un nouveau contour arrive.

**Limite à vérifier en premier.** En pomme de terre, les champs sont souvent petits. Un pixel Sentinel-2 couvre 10 m × 10 m. Un champ de 0,1 ha n'en contient que 10 environ, et un champ de 0,05 ha environ 5. Au-dessous de **0,1 ha**, le suivi est **indicatif** et doit être signalé comme tel. Il faut aussi retirer une marge de 5 m sur le bord du contour pour ne pas mesurer la bordure.

## 5. Architecture : un seul VPS

Tout tourne sur **un VPS OVHcloud** (Linux, Docker Compose). Il n'y a ni Supabase, ni Netlify, ni Railway : une seule machine, une seule facture, et les données restent en Europe.

| Conteneur | Rôle |
|---|---|
| `db` | PostgreSQL 16 + PostGIS. |
| `web` | Next.js : tableau de bord **et** API REST pour l'app Android (connexion, envoi des producteurs, champs et photos). |
| `sat` | Worker Python, lancé une fois par jour et à chaque nouveau contour : NDVI Sentinel-2 depuis Planetary Computer. |
| `caddy` | HTTPS automatique (Let's Encrypt) devant `web`. |

- **Photos** : stockées sur le disque du VPS, dans un volume Docker.
- **Comptes** : identifiant et mot de passe, gérés par l'app web. Les comptes sont créés par un script, sans écran d'inscription.
- **Sauvegarde** : un `pg_dump` et une copie des photos chaque nuit, vers OVH Object Storage ou un autre disque.
- **Taille** : un VPS de milieu de gamme (4 vCPU, 8 Go de RAM) suffit largement pour quelques centaines de champs. Le prix est à vérifier sur le site d'OVHcloud.
- **App Android** : APK installée directement sur les téléphones, sans Play Store. Elle pointe vers l'adresse du VPS, par exemple `https://guis.<domaine>`.
- **Il faut fournir** un nom de domaine, ou un sous-domaine, qui pointe vers le VPS.

Ce qui change par rapport à Fieldproof : la couche Supabase (`supabase_flutter`, `@supabase/ssr`, RLS, RPC) est remplacée par l'API de l'app web. Tout le reste se reprend tel quel : tour GPS, calcul de surface, file d'envoi hors ligne, photos, carte, courbe NDVI, lecture des images satellite.

## 6. Démarche

Le développement se fait **de bout en bout par un agent IA**, dans une session cloud, en partant de cette note et de `reference/fieldproof/`. Pas de planning par jour ni de cérémonie. Quatre règles seulement :

1. **On ne touche pas à Fieldproof.** On copie depuis `reference/fieldproof/` et on note chaque copie dans `PROVENANCE.md`.
2. **Le dépôt est public** : pas de secret ni de donnée réelle de producteur dans git.
3. **On vise le plus simple qui marche** : peu d'écrans, aucun écran de configuration, des listes (variétés, villages) remplies par script.
4. **L'ordre de priorité** : d'abord l'app de collecte, puisque les semis ont lieu maintenant ; ensuite le tableau de bord ; enfin le satellite. Les archives Sentinel-2 sont conservées, donc un champ relevé aujourd'hui pourra être analysé plus tard depuis sa date de semis, sans rien perdre.

## 7. Points ouverts

Ils ne bloquent rien : en l'absence de réponse, l'agent applique la valeur par défaut entre parenthèses.

1. ~~Nom~~ : **Guis**, décidé le 23/11/2026.
2. Zone et villages de la coopérative (à renseigner par script).
3. Volume (environ 300 producteurs, 5 agents).
4. Taille habituelle des champs (sous 0,1 ha, le suivi satellite est indicatif).
5. Qui voit le tableau de bord (coopérative et IBRIZ, avec accès à tout).
6. Plusieurs champs par producteur (oui).
7. Consentement (une case cochée par l'agent, avec la date).
8. Fichier de distribution des semences existant, à importer (s'il existe).
