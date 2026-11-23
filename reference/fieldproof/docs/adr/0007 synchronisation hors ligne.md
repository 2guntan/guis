# ADR-0007 — Synchronisation hors ligne : le droit d'écrire suit le statut du dossier

Statut : Accepté — 19/11/2026

## Décision
- App agent : Flutter, Android en priorité, base locale + file de synchronisation (repris de SOLIR / Agriva).
- Brouillon ou renvoyé : seul l'agent écrit (sur son téléphone). Soumis : verrouillé côté agent ; seul le superviseur agit.
- Chaque changement de statut est une commande horodatée sur le téléphone, rejouée par le serveur, qui la refuse si le statut a changé entre-temps ; l'agent reçoit le motif.
- Pièces et photos montent séparément, avec reprise ; jamais écrasées, toujours versionnées.

## Alternatives écartées
- Dernière écriture gagnante : perte de données silencieuse.
- Fusion champ par champ : complexe, inutile puisqu'un seul acteur écrit à la fois.
