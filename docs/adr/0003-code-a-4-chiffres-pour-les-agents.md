---
statut: accepté
---

# Les agents se connectent avec un code de 4 chiffres, bloqué après 5 essais

Les **agents** sont peu à l'aise avec la technologie et oublient vite un mot de passe compliqué ; chaque oubli revient à l'**admin** ou au **coordinateur**. Leurs téléphones, qui servent d'identifiant, sont connus (ils figurent dans la fiche de la coopérative), et le tableau de bord est en ligne. On a donc décidé :

- un agent se connecte avec un **code** de 4 chiffres, généré par le serveur (jamais `0000`, `1234`, une suite ou les 4 derniers chiffres de son téléphone) et affiché une seule fois à qui le crée ou le réinitialise ;
- après 5 codes faux pour un même téléphone, la connexion est bloquée 15 minutes ;
- l'**admin** et le **coordinateur**, qui voient toutes les données, gardent un mot de passe d'au moins 10 caractères ;
- une session dure 90 jours : l'agent ne ressaisit son code que rarement.

## Options écartées

- **Mot de passe de 10 caractères pour tous** : sûr, mais trop d'oublis pour ces utilisateurs.
- **Code simple sans blocage** : 10 000 combinaisons se devinent en quelques minutes depuis Internet.
- **Code à 6 chiffres** : un peu plus sûr, mais moins familier que les 4 chiffres d'Orange Money ou de Wave ; le blocage suffit à rendre 4 chiffres acceptables.
