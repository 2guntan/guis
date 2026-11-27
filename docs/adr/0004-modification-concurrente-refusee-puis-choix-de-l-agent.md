---
statut: accepté
---

# Une fiche modifiée ailleurs entre-temps est refusée, l'agent choisit

Un **agent** travaille souvent hors ligne pendant plusieurs jours. Pendant ce temps, l'**admin**, le **coordinateur** ou un autre agent de la même commune peut modifier le même producteur ou le même champ. Jusqu'ici, la version qui arrivait en dernier écrasait l'autre sans prévenir : une correction faite au bureau pouvait disparaître au retour d'un téléphone (audit Android, M4). On a donc décidé :

- le serveur garde, pour chaque producteur et chaque champ, la date et l'auteur de la **dernière modification faite par une personne** (`edited_at`, `edited_by`) : un envoi de l'app, ou la fusion d'un doublon. Les imports et le calcul satellite ne comptent pas ;
- l'app renvoie avec chaque envoi la date `edited_at` qu'elle a reçue (`base_edited_at`) ;
- si quelqu'un d'autre a modifié la fiche après cette date, le serveur refuse l'envoi (409, « modifié par quelqu'un d'autre ») ;
- sur le téléphone, la saisie apparaît alors « Refusé ». « Renvoyer » l'envoie sans date et remplace la version du serveur ; « Écarter » garde la version du serveur, qui revient au chargement suivant ;
- les envois successifs du même agent ne sont jamais en conflit entre eux, même avant un nouveau chargement ;
- un envoi sans `base_edited_at` (ancienne version de l'app) remplace la version du serveur, comme avant.

## Options écartées

- **Le dernier qui envoie gagne** (comportement d'avant) : simple, mais une correction du bureau peut se perdre sans que personne ne le sache.
- **Fusion champ par champ** : garde le plus d'information, mais demande de connaître la version d'origine de chaque champ, et les cas de fusion (semences, contour) sont difficiles à expliquer à l'agent.
- **Comparer `updated_at`** : cette date change aussi à chaque import et à chaque calcul satellite, ce qui donnerait de faux conflits.
