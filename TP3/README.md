# TP3 - Audit qualité et nettoyage des données Vélib'

Suite des TP1 et TP2. Après 3 jours de collecte, on audite les données produites par le pipeline du TP2, on corrige ce qui peut l'être, et on vérifie que le résultat respecte le schéma cible du TP1.

Point de départ : en regardant la table `pipeline_run` du TP2, Spark avait rejeté environ 10 % des lignes. On attendait seulement 3 stations fermées par collecte. Il fallait donc comprendre ce qui se passait.

## Contenu

| Fichier | Rôle |
|---|---|
| [cartographie.md](cartographie.md) | cartographie mise à jour (sources, champs, types, tables) |
| [matrice_controles.md](matrice_controles.md) | les 18 contrôles : dimension, règle, criticité, action prévue |
| [sql/00_schema.sql](sql/00_schema.sql) | schéma de travail `tp3`, tables brutes, fonctions de conversion |
| [scripts/charger.sh](scripts/charger.sh) | chargement des données brutes du data lake dans `tp3` |
| [sql/01_releve_avant.sql](sql/01_releve_avant.sql) | relevés typés, joints au référentiel comme dans le TP2 (état avant) |
| [sql/02_audit.sql](sql/02_audit.sql) | les contrôles, paramétrés par table et phase |
| [sql/03_nettoyage.sql](sql/03_nettoyage.sql) | les règles de correction R1 à R9 + journal |
| [sql/04_chargement_cible.sql](sql/04_chargement_cible.sql) | chargement dans `tp3_cible`, copie du schéma cible avec ses contraintes |
| [sql/05_controle_base.sql](sql/05_controle_base.sql) | base du TP2 contre base nettoyée |
| [sql/06_comparaison.sql](sql/06_comparaison.sql) | tableau avant / après |
| [resultats/](resultats/) | sorties des scripts + [avant_apres.md](resultats/avant_apres.md) |

## Lancer l'audit

La stack du TP2 doit tourner (`docker compose up -d` dans `TP2/`). Ensuite :

```
cd TP3
./scripts/lancer_audit.sh
```

Il faut environ 9 minutes pour 2 millions de lignes. Le script recharge tout depuis le data lake à chaque lancement et écrit les résultats dans `resultats/`. La période est figée par défaut jusqu'au 28/09 08h00 UTC pour que les chiffres restent les mêmes. On peut la changer avec la variable `FIN` (ex. `FIN=2026-09-29/000000 ./scripts/lancer_audit.sh`).

Tout se passe dans deux schémas à part (`tp3` et `tp3_cible`) de la base `velib`. Le schéma `public` du TP2 n'est pas modifié, on ne fait que le lire.

## Démarche

1. **Repartir du brut.** Les tables du TP2 sont protégées par les contraintes, donc les lignes rejetées par Spark n'y sont plus. Pour les voir, on recharge `raw/api` et `raw/source2` en texte, sans aucune conversion.
2. **Reconstituer l'état "avant".** On type les colonnes (avec des fonctions qui renvoient NULL au lieu de planter) et on joint chaque relevé au dernier CSV téléchargé avant lui, comme le faisait l'agrégateur.
3. **Auditer.** On lance les 18 contrôles de la matrice. Chaque résultat est stocké dans `tp3.resultat_controle`.
4. **Analyser les anomalies.** On regarde quand et où elles apparaissent (par fichier, par collecte, par station) pour trouver leur cause.
5. **Nettoyer.** On applique une règle par anomalie. Chaque règle écrit son nombre de lignes dans `tp3.journal_nettoyage`.
6. **Charger dans une copie du schéma cible.** Si une ligne ne respectait pas le schéma, l'insertion échouerait. Elle passe, donc les données sont conformes.
7. **Recontrôler.** On relance exactement le même script d'audit sur les données relues depuis le schéma cible, puis on compare.

## Anomalies trouvées

Classées par importance (volume × impact) :

| # | Anomalie | Contrôles | Volume | Criticité | Cause |
|---|---|---|---:|---|---|
| 1 | Référentiel Paris Data vide | C3, I2 | 206 584 relevés (9,9 %) | bloquante | 3 fichiers du 26/09 entre 01h44 et 06h29 : toutes les lignes sont là, mais toutes les colonnes sont vides. L'agrégateur les a utilisés quand même. |
| 2 | Trous dans les collectes | C4 | 2 915 minutes sur 4 291 (68 %) | majeure | PC en veille (nuits, week-end) : Docker est suspendu, rien n'est collecté |
| 3 | Collectes API sans code station ni répartition | C1, C2 | 19 747 relevés, 13 collectes | bloquante | environ une fois par heure, l'API renvoie `stationCode: null` et `[{}, {}]` pour les types de vélos (le total reste bon) |
| 4 | Stations muettes | K3 | 18 043 relevés, 17 stations | majeure | stations qui ne remontent plus rien, une depuis février 2021 ; leurs compteurs sont figés |
| 5 | Surplus de vélos | K2 | 13 949 relevés, 35 stations | mineure | vélos + bornes libres > capacité, jusqu'à 24 vélos de plus |
| 6 | Noms mal formés | V5 | 8 680 relevés, 7 stations | mineure | espaces doublés dans le CSV (ex. `Bassano -  Iéna`) |
| 7 | Capacité à 0 | V1 | 3 670 relevés, 3 stations | bloquante | stations fermées ou en travaux |
| 8 | Heure de collecte fausse | V6 | 2 998 relevés, 2 collectes | majeure | l'horloge du conteneur retardait de près d'une heure à la sortie de veille |

Contrôles sans anomalie : doublons (U1, U2), compteurs négatifs (V2), coordonnées (V3), codes INSEE (V4), total = mécaniques + électriques (K1), communes (K4), codes inconnus du référentiel (I1).

## Corrections et justifications

- **R1, heure de collecte (correction).** Sur les 2 collectes concernées, plus de la moitié des stations ont une mise à jour "dans le futur". C'est donc l'heure du producer qui est fausse, pas les stations. On prend comme heure de collecte la mise à jour la plus récente reçue dans la collecte, qui vient de l'horloge du serveur Vélib'.
- **R2, code station (substitution).** Le contrôle U2 montre qu'un `station_id` a toujours le même code. On reprend donc le code connu du même `station_id` sans risque d'erreur.
- **R3, répartition mécanique / électrique (imputation).** Le total de vélos est connu, il ne manque que la répartition. On reprend le nombre d'électriques du relevé précédent de la station (ou du suivant), plafonné au total. Les mécaniques = total − électriques. Les relevés sont à 1 minute d'écart, l'erreur possible est de 1 ou 2 vélos. Les lignes imputées sont marquées (`velos_imputes`) dans `tp3.releve_travail`.
- **R4, référentiel (suppression du fichier + substitution).** Un fichier est jugé valide s'il contient au moins 1 500 stations avec un nom. Les 3 fichiers vides sont écartés et on reprend le dernier fichier valide précédent. Le nom, la capacité et la position d'une station ne changent pas en quelques heures : sur 3 jours, une seule station a changé de capacité.
- **R5, noms (correction).** On enlève les espaces au début et à la fin, et on remplace les espaces multiples par un seul.
- **R6, capacité 0 (suppression).** Ces stations ne proposent ni vélo ni borne, et le schéma cible les refuse (`CHECK capacite > 0`). On ne peut pas deviner une capacité.
- **R7, stations muettes (suppression des relevés).** Un compteur figé depuis des jours n'est pas une disponibilité réelle : le garder fausserait les indicateurs du dashboard. La station reste dans la table `station`, seuls ses relevés sont retirés.
- **R8 / R9, rattachement et doublons (suppression).** Ce sont des filets de sécurité : ils ne suppriment rien ici.
- **K2, pas de correction.** Vélib' accepte des vélos en surplus sur certaines stations quand elles sont pleines ("overflow"). C'est une information de l'opérateur, pas une erreur. On la garde et on la signale.
- **C4, pas de correction.** On ne fabrique pas des mesures pour les minutes où rien n'a été collecté. Il faut simplement en tenir compte dans les analyses temporelles (moyennes par heure, etc.).

## Résultat

Tous les contrôles corrigeables passent à 0 anomalie. Les données nettoyées entrent dans une copie du schéma cible sans violer aucune contrainte. On récupère 191 355 relevés (+10,2 %) et 136 collectes que la base du TP2 avait perdus. Détail dans [resultats/avant_apres.md](resultats/avant_apres.md).

## Ce qu'il faudrait changer dans le pipeline du TP2

- `source2` : vérifier le fichier avant de le déposer (au moins 1 500 stations avec un nom), sinon garder l'ancien.
- `aggregator` : garder en mémoire la correspondance `station_id -> code station` pour les collectes où l'API renvoie des codes vides.
- `producer` : utiliser `lastUpdatedOther` (l'heure du fichier côté serveur) plutôt que l'horloge du conteneur.
- `spark` : ajouter la règle des stations muettes (K3) au nettoyage.
