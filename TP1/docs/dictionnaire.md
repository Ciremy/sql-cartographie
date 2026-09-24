# Dictionnaire de données

Les exemples viennent des données récupérées le 24/09/2026.

## Flux GBFS `station_information.json` (1 objet par station, dans `data.stations`)

| Champ | Description | Type | Exemple |
|---|---|---|---|
| station_id | Identifiant technique de la station dans le flux | entier (grand) | 213688169 |
| stationCode | Code de la station, celui affiché sur la borne | texte (numérique, parfois 4 chiffres) | "16107" |
| name | Nom de la station (souvent deux rues qui se croisent) | texte | "Benjamin Godard - Victor Hugo" |
| lat | Latitude WGS84 | décimal | 48.865983 |
| lon | Longitude WGS84 | décimal | 2.275725 |
| capacity | Nombre total de bornes (points d'attache) | entier | 35 |
| station_opening_hours | Horaires d'ouverture, toujours vide | null | null |

## Flux GBFS `station_status.json` (état à un instant donné)

| Champ | Description | Type | Exemple |
|---|---|---|---|
| station_id | Même identifiant que dans station_information | entier | 213688169 |
| stationCode | Code station (redondant) | texte | "16107" |
| num_bikes_available | Nombre total de vélos disponibles | entier | 9 |
| numBikesAvailable | Doublon du précédent (ancien nom) | entier | 9 |
| num_bikes_available_types | Détail par type de vélo, tableau d'objets | tableau JSON | `[{"mechanical": 8}, {"ebike": 1}]` |
| num_docks_available | Bornes libres pour déposer un vélo | entier | 26 |
| numDocksAvailable | Doublon du précédent | entier | 26 |
| is_installed | Station en service (1) ou non (0) | entier 0/1 | 1 |
| is_renting | On peut louer un vélo | entier 0/1 | 1 |
| is_returning | On peut rendre un vélo | entier 0/1 | 1 |
| last_reported | Dernière remontée d'info de la station | timestamp Unix (secondes) | 1790236256 |
| lastUpdatedOther (racine) | Date de génération du fichier | timestamp Unix | 1790237772 |

## Jeu Paris Data `velib-disponibilite-en-temps-reel`

Même contenu que le GBFS mais aplati, avec la commune en plus. Seuls les champs qui changent par rapport au GBFS :

| Champ | Description | Type | Exemple |
|---|---|---|---|
| stationcode | Code station, sert de clé pour relier au GBFS | texte | "16107" |
| mechanical | Vélos mécaniques dispo | entier | 8 |
| ebike | Vélos électriques dispo | entier | 1 |
| is_installed / is_renting / is_returning | Mêmes infos, mais en texte | texte OUI/NON | "OUI" |
| duedate | Dernière mise à jour (= last_reported) | date ISO 8601 | "2026-09-24T07:50:56+00:00" |
| coordonnees_geo | Position | objet {lon, lat} | `{"lon": 2.275725, "lat": 48.865983}` |
| nom_arrondissement_communes | Commune de la station | texte | "Paris" |
| code_insee_commune | Code INSEE de la commune | texte (5 car.) | "75056" |

## API Découpage administratif (`/communes/{code}`)

| Champ | Description | Type | Exemple |
|---|---|---|---|
| code | Code INSEE de la commune | texte (5 car.) | "92012" |
| nom | Nom officiel | texte | "Boulogne-Billancourt" |
| codeDepartement | Département | texte | "92" |
| codesPostaux | Codes postaux de la commune | tableau de textes | ["92100"] |
| population | Population municipale | entier | 119019 |
| surface | Surface en hectares | décimal | 615.22 |

## Remarques sur la qualité

- Doublons de colonnes dans le GBFS (`numBikesAvailable` / `num_bikes_available`), on n'en garde qu'une.
- Les booléens sont codés 0/1 d'un côté et OUI/NON de l'autre, on convertit en `BOOLEAN`.
- `stationCode` a l'air numérique mais il faut le garder en texte (codes à 4 chiffres, et ce n'est pas une valeur qu'on additionne).
- Le code INSEE de Paris est 75056 pour toutes les stations : pas de détail par arrondissement.
- Vélos + bornes libres ne font pas toujours la capacité (ex. Transvaal - Charles de Gaulle : 18 vélos + 6 bornes pour 27 places), il y a donc des bornes hors service qui n'apparaissent nulle part.
- Sur deux collectes à 2 min d'écart, certaines stations ont changé de nombre de vélos sans que `last_reported` bouge. D'où la distinction entre date de collecte et date de mise à jour station dans le modèle.
- `station_opening_hours` est toujours null, pas repris.
