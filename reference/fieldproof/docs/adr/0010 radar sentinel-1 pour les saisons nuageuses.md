# ADR-0010 — Radar Sentinel-1 pour les saisons nuageuses de l'analyse rétroactive

Statut : Accepté — 21/11/2026 (option A choisie par le porteur)

## Contexte
L'analyse rétroactive (module Watch) s'appuie sur Sentinel-2 : en hivernage en Casamance, les nuages laissent souvent moins de 3 images claires par saison, et la saison reste « incertaine ». Le radar Sentinel-1 voit à travers les nuages.

## Décision
- **Option A** : par saison, l'optique tranche quand elle a assez d'images claires ; sinon, le radar tranche. Les deux résultats ne sont pas présentés côte à côte au superviseur.
- Source : Microsoft Planetary Computer, collection `sentinel-1-rtc` (gamma0 corrigé du relief, accès anonyme, comme Sentinel-2). Une seule géométrie d'acquisition par analyse (sens d'orbite et orbite relative la plus fréquente), pour comparer les dates entre elles.
- Indicateur : rétrodiffusion VH moyenne sur le contour (dB). Saison cultivée si l'amplitude (90e - 10e centile) atteint au moins 2,5 dB et le pic au moins -17 dB ; creux déjà ≥ -15 dB sans amplitude : couvert permanent. Au moins 5 passages par saison.
- **Le radar ne peut que confirmer une culture** : il ne déclare jamais seul une saison non cultivée (voir calibration).
- **Mise en eau** : VV sous -17 dB puis VH qui remonte d'au moins 3 dB : riz de bas-fond probable, signalé dans le résumé, sans changer le verdict.
- Seuils provisoires, réglables par variables d'environnement (`SAT_S1_*`) sans nouvelle version.
- Le radar est facultatif : s'il est illisible, l'analyse optique reste publiée et le résumé le dit. `SAT_RADAR=0` le coupe.

## Calibration du 21/11/2026
24 sites de la zone Sud (bons de livraison de juillet 2023, parcelles de 2 ha au plus, carré de 1 ha autour du point), 6 saisons de l'hivernage 2023 à la contre-saison 2025-26, sans vérité terrain : on mesure l'accord du radar avec l'optique là où l'optique voit.
- L'optique voit presque toujours assez : 4 à 11 images claires par hivernage sur ces sites ; aucune saison « incertaine » faute d'images. Le radar tranchera donc rarement.
- Hivernage, seuil 2,5 dB : quand le radar dit « cultivée », l'optique est d'accord 11 fois sur 12. Il ne retrouve que 11 des 35 saisons cultivées en optique : sous couvert arboré, l'amplitude VH reste faible (médiane 2,1 dB contre 1,5 dB pour un couvert permanent).
- Un radar « non cultivé » contredisait l'optique 3 fois sur 5 : d'où la règle ci-dessus.
- Constat sur l'optique : 50 des 65 contre-saisons « cultivées » avaient leur pic de NDVI en décembre, c'est-à-dire la végétation restante de l'hivernage et non une culture. Et avec un hivernage commençant le 1er juillet, l'hivernage 2025 ressortait en « couvert permanent » sur 21 sites : juillet couvert, la ligne de base ne voyait pas le sol nu de juin (NDVI médian 0,37 en juin, 0,68 en août).

## Révision de l'optique et du verdict (21/11/2026, décision du porteur)
- Hivernage du 1er juin au 30 novembre, contre-saison du 1er décembre au 31 mai.
- Saison cultivée seulement si le pic de NDVI est précédé dans la saison d'une valeur plus basse d'au moins 0,15 ; un pic de début de saison suivi d'une baisse est la végétation restante de la saison précédente : non cultivée.
- Verdict fondé sur l'hivernage : hivernage cultivé et contre-saisons sans culture = « cultivée » (culture pluviale, résumé explicite) ; « non cultivée » seulement si un hivernage est observé sans culture ; sinon « incertaine ». Une contre-saison cultivée sans hivernage cultivé reste « partiellement cultivée ».
- Effet sur les 24 sites (3 dernières saisons au 21/11/2026) : avant, 21 « cultivées » appuyées surtout sur des contre-saisons trompeuses ; après, 23 « cultivées » en pluvial (hivernage cultivé, contre-saisons vides) et 1 « incertaine ». En hivernage (juin-novembre), quand le radar dit « cultivée », l'optique est d'accord 23 fois sur 23 ; il retrouve 23 des 45 saisons cultivées.
- Limite connue : une jachère herbeuse verdit aussi en hivernage ; l'optique et le radar ne la distinguent pas encore d'une culture. Il faut des parcelles de référence en jachère pour régler ce point.

## Conséquences
- Sentinel-1B est hors service depuis décembre 2021 : un passage tous les 12 jours sur la zone, assez pour suivre une saison, pas pour dater un semis.
- Petites parcelles (≤ 2 ha, soit environ 200 pixels de 10 m) : la moyenne lisse le chatoiement, mais une bordure d'arbres ou une case dans le contour peut fausser le signal.
- Les seuils doivent être revus avec des parcelles de référence (cultivée / jachère connues par saison), dont du riz de bas-fond.
- Nouvelle colonne `watch.retro_analyses.radar_series` (migration 0012) ; chaque saison porte `source` (`optical` ou `radar`) et ses indicateurs radar.
