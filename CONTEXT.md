# Guis

Collecte sur le terrain et suivi satellite des champs de pomme de terre des producteurs d'une coopérative, pendant une campagne de contre-saison.

## Langage

### Surfaces

**Surface déclarée** :
Surface totale que le **producteur** dit cultiver, en hectares, relevée sur la fiche de **visite de validation**.
_Éviter_ : surface annoncée

**Surface validée** :
Surface totale du **producteur** retenue par l'équipe de la coopérative lors de la **visite de validation** ; base de la **dotation**.
_Éviter_ : surface officielle, surface accordée

**Surface déclarée du champ** :
Surface d'un **champ** donnée par le producteur à l'agent Guis au moment du relevé.

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

**Commune** :
Secteur de la coopérative, confié à un responsable, dont l'équipe a fait la **visite de validation** du **producteur**.
_Éviter_ : zone, secteur

**Village** :
Localité où habite le **producteur**, écrite sous une orthographe unique retenue par la coopérative.
_Éviter_ : adresse, localité

**Agent** :
Personne de terrain qui relève les **champs** des **producteurs** qui lui sont **attribués**, depuis l'app Android ; il retrouve un producteur par recherche exacte, sans parcourir de liste.
_Éviter_ : enquêteur, technicien

**Admin** :
Personne de la coopérative ou d'IBRIZ qui voit tous les **producteurs**, sur le tableau de bord et dans l'app Android.
_Éviter_ : superviseur

**Attribution** :
Rattachement des **producteurs** d'une **commune** à un **agent** ; un agent ne reçoit sur son téléphone que les producteurs qui lui sont attribués.
_Éviter_ : affectation, portefeuille

**Champ** :
Parcelle d'un **producteur**, avec son contour GPS et sa date de semis.
_Éviter_ : parcelle (dans l'interface)

## Relations

- Un **producteur** appartient à une seule **commune** et habite un seul **village** ; un même **village** peut compter des producteurs de deux **communes**
- Un **producteur** a au plus une **dotation** par campagne, calculée sur sa **surface validée**
- Un **producteur** a zéro, une ou plusieurs **remises** ; leur total peut être inférieur à la **dotation** (remise en cours)
- Un **producteur** a un ou plusieurs **champs** ; chaque **champ** a sa **surface mesurée**
- La **surface déclarée** et la **surface validée** sont celles du **producteur** ; la **surface déclarée du champ** et la **surface mesurée** sont celles d'un **champ**
- La comparaison utile : **surface déclarée** / **surface validée** / somme des **surfaces mesurées** des champs du producteur

## Exemple de dialogue

> **Dev :** « Ce producteur a une **dotation** de 120 sacs : il a donc reçu 3 t ? »
> **Coopérative :** « Non, la **dotation** est ce qu'on lui a attribué. Ce qu'il a reçu, ce sont ses **remises**, que l'agent note dans l'app. »
> **Dev :** « Et si la **surface mesurée** de ses champs fait 0,6 ha pour 1 ha **validé** ? »
> **Coopérative :** « C'est justement l'écart qu'on veut voir. »

## Ambiguïtés relevées

- « distribution » désignait à la fois la **dotation** et la **remise** (script `import-distributions`, table `seed_distributions`). Tranché : ce sont deux notions distinctes ; `seed_distributions` correspond aux **remises**.
- « surface déclarée » désignait à la fois la surface totale du producteur (fiche de la coopérative) et celle d'un champ (saisie dans l'app). Tranché : **surface déclarée** (producteur) et **surface déclarée du champ**.
- Dans la fiche Excel, la colonne « ADRESSE » est le **village**, et chaque feuille est une **commune**.
- Dans la fiche Excel, la colonne « TONNAGE (kg) » est en réalité en **tonnes** (sacs × 25 kg).
