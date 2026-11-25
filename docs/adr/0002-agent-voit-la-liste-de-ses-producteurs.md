---
statut: accepté
---

# L'agent voit la liste de ses producteurs attribués dès la connexion

L'ADR-0001 cachait à l'**agent** la liste de ses **producteurs** : il devait les retrouver par téléphone exact. Sur le terrain, cette recherche gêne le travail, et elle ne protège rien : le serveur envoie déjà au téléphone tous les producteurs des **communes** attribuées à l'agent, et l'ADR-0001 notait lui-même que masquer n'est pas protéger. On lève donc cette contrainte :

- à la connexion, l'app affiche la liste de tous les producteurs attribués à l'agent (ceux de ses communes et ceux qu'il a créés), triée par **village** puis par nom, avec un filtre au fil de la frappe sur le nom, le téléphone ou le village, et un filtre par commune quand l'agent en a plusieurs ;
- l'onglet « Mes producteurs » disparaît ; la création repasse par un bouton permanent « Nouveau producteur », et un téléphone déjà connu reste signalé comme **doublon possible**.

Le reste de l'ADR-0001 tient : le serveur n'envoie à un agent que ses producteurs, l'**attribution** se fait par commune, et l'**admin** voit tout.

## Conséquences

- Quand une commune est retirée à un agent, ses saisies non envoyées sur cette commune sont refusées par le serveur mais restent sur le téléphone (« Refusé ») ; le **coordinateur** peut rendre la commune, l'agent renvoie. Le serveur n'accepte pas de saisie hors périmètre, même récente.
