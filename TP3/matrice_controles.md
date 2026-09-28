# Matrice de contrôles qualité

Les contrôles portent sur les relevés (1 ligne = 1 station à 1 collecte) une fois les deux sources rapprochées, c'est-à-dire sur ce que le pipeline du TP2 envoie vers le schéma cible. Ils sont tous dans [sql/02_audit.sql](sql/02_audit.sql) et tournent à l'identique avant et après nettoyage.

Criticité :
- **bloquante** : la ligne ne peut pas entrer dans le schéma cible (NOT NULL, FK, CHECK) ;
- **majeure** : la ligne entre mais l'information est fausse ou manquante pour l'analyse ;
- **mineure** : forme ou présentation, sans impact sur les chiffres.

| ID | Dimension | Objet | Règle | Criticité | Seuil visé | Action prévue si KO |
|---|---|---|---|---|---|---|
| C1 | Complétude | code_station (API) | non NULL | bloquante | 0 | substitution depuis station_id |
| C2 | Complétude | vélos mécaniques / électriques (API) | non NULL | majeure | 0 | imputation depuis le relevé voisin |
| C3 | Complétude | nom, capacité, position, commune (référentiel) | non NULL | bloquante | 0 | reprendre le dernier référentiel valide |
| C4 | Complétude | collectes | 1 collecte par minute entre la première et la dernière | majeure | < 5 % de minutes manquantes | aucune (on n'invente pas de mesure), à documenter |
| U1 | Unicité | (station_id, date_collecte) | pas de doublon | bloquante | 0 | suppression des doublons |
| U2 | Unicité | code_station | un seul station_id par code | bloquante | 0 | à analyser au cas par cas |
| V1 | Validité | capacité | > 0 | bloquante (CHECK) | 0 | suppression |
| V2 | Validité | compteurs vélos / bornes | >= 0 | bloquante (CHECK) | 0 | suppression |
| V3 | Validité | latitude / longitude | dans l'Île-de-France (lat 48,1-49,3 ; lon 1,4-3,6) | majeure | 0 | correction ou suppression |
| V4 | Validité | code INSEE | 5 chiffres, département 75, 77, 78, 91, 92, 93, 94 ou 95 | bloquante (FK commune) | 0 | correction |
| V5 | Validité | nom de station | pas d'espace en début/fin ni d'espaces doublés | mineure | 0 | correction (trim) |
| V6 | Validité | date_maj_station | pas plus de 5 min après la date de collecte | majeure | 0 | correction de la date |
| K1 | Cohérence | total vélos | = mécaniques + électriques | majeure | 0 | recalcul |
| K2 | Cohérence | vélos + bornes libres | <= capacité | mineure | à mesurer | analyse métier |
| K3 | Cohérence | fraîcheur station | dernière remontée de moins de 24 h avant la collecte | majeure | 0 | exclure les relevés figés |
| K4 | Cohérence | commune | un code INSEE = un seul nom | majeure | 0 | correction du nom |
| I1 | Intégrité | code station API | existe dans le référentiel (source 2) | bloquante (FK station) | 0 | suppression |
| I2 | Intégrité | relevé | rattachable à une station et une commune | bloquante (FK) | 0 | suppression après tentative de correction |

Les contrôles sur la base chargée (relevés sans leurs 2 lignes `releve_velo`, stations sans relevé, etc.) sont à part, dans [sql/05_controle_base.sql](sql/05_controle_base.sql). Les contraintes du schéma cible empêchent déjà les orphelins de clés étrangères.
