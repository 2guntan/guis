# Guis

Collecte sur le terrain et suivi satellite des champs de pomme de terre des producteurs d'une coopérative, pendant une campagne de contre-saison.

## Langage

### Surfaces

**Surface déclarée** :
Surface emblavée que le producteur dit cultiver, en hectares.
_Éviter_ : surface annoncée

**Surface validée** :
Surface retenue par l'équipe de la coopérative lors de la **visite de validation**, qui sert à calculer la **dotation**.
_Éviter_ : surface officielle, surface accordée

**Surface mesurée** :
Surface calculée à partir du contour GPS d'un **champ**, relevé par un agent Guis.
_Éviter_ : surface réelle, surface GPS

### Semence

**Dotation** :
Quantité de semence attribuée à un **producteur** par la coopérative, à raison de 120 sacs de 25 kg (3 t) par hectare de **surface validée**.
_Éviter_ : distribution, allocation, tonnage

**Remise** :
Semence effectivement reçue par un **producteur**, avec une variété, une quantité et une date.
_Éviter_ : distribution, livraison

### Terrain

**Visite de validation** :
Passage d'une équipe de la coopérative chez un **producteur**, avant la campagne Guis, qui fixe la **surface validée**. Résultat consigné dans la fiche de visite-validation (Excel).

**Producteur** :
Membre de la coopérative qui cultive un ou plusieurs **champs**.
_Éviter_ : client, bénéficiaire

**Champ** :
Parcelle d'un **producteur**, avec son contour GPS et sa date de semis.
_Éviter_ : parcelle (dans l'interface)

## Relations

- Un **producteur** a au plus une **dotation** par campagne, calculée sur sa **surface validée**
- Un **producteur** a zéro, une ou plusieurs **remises** ; leur total peut être inférieur à la **dotation** (remise en cours)
- Un **producteur** a un ou plusieurs **champs** ; chaque **champ** a sa **surface mesurée**
- La **surface déclarée** et la **surface validée** sont celles du **producteur** ; la **surface mesurée** est celle d'un **champ**

## Exemple de dialogue

> **Dev :** « Ce producteur a une **dotation** de 120 sacs : il a donc reçu 3 t ? »
> **Coopérative :** « Non, la **dotation** est ce qu'on lui a attribué. Ce qu'il a reçu, ce sont ses **remises**, que l'agent note dans l'app. »
> **Dev :** « Et si la **surface mesurée** de ses champs fait 0,6 ha pour 1 ha **validé** ? »
> **Coopérative :** « C'est justement l'écart qu'on veut voir. »

## Ambiguïtés relevées

- « distribution » désignait à la fois la **dotation** et la **remise** (script `import-distributions`, table `seed_distributions`). Tranché : ce sont deux notions distinctes ; `seed_distributions` correspond aux **remises**.
- Dans la fiche Excel, la colonne « TONNAGE (kg) » est en réalité en **tonnes** (sacs × 25 kg).
