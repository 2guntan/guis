---
statut: remplacé en partie par ADR-0002 (l'agent voit la liste de ses producteurs)
---

# Un agent ne reçoit que les producteurs de ses communes et les retrouve par recherche exacte

La base initiale compte environ 670 producteurs avec nom et téléphone, pour 5 agents qui travaillent hors ligne. Pour qu'un téléphone perdu ou un agent indélicat n'expose pas toute la base, et pour que chaque agent ne travaille que sur les producteurs qui lui sont confiés, on a décidé ceci :

- le serveur n'envoie à un **agent** que les **producteurs** des **communes** qui lui sont **attribuées**, plus ceux qu'il a créés ;
- l'app ne lui montre aucune liste complète : il retrouve un producteur par **téléphone exact** (ou numéro de membre), et seuls ceux qu'il a déjà ouverts ou créés apparaissent dans « Mes producteurs » ;
- l'**admin** voit tout, sur le tableau de bord et dans l'app Android.

Ce choix remplace le point 5 du §7 de `NOTE-CADRAGE.md`, où l'admin ne se servait que du web et où chaque agent voyait tous les producteurs.

## Options écartées

- **Tout télécharger et masquer à l'écran** : les données restent en clair dans le stockage local du téléphone ; masquer n'est pas protéger.
- **Recherche en ligne uniquement** : incompatible avec le travail hors ligne au moment des semis.
- **Attribution par producteur** : trop lourde à tenir ; la commune suffit, et une commune peut avoir plusieurs agents.
- **Création réservée à l'admin** : bloquante sur le terrain sans réseau. L'agent crée donc le producteur, et le serveur signale à l'admin un **doublon possible** quand le téléphone existe déjà.

## Conséquences

- Un producteur introuvable par l'agent (autre commune, téléphone absent ou faux) passe par l'admin, ou par une création signalée comme doublon possible.
- Changer l'attribution d'une commune change ce que reçoivent les téléphones à la synchronisation suivante, sans réimporter les producteurs.
