# Cartographie mise à jour

Reprise de la cartographie du TP1, complétée avec ce que le TP2 a ajouté et ce que le TP3 utilise.

## Chemin des données

```
Source 1 : API GBFS station_status (JSON)          Source 2 : CSV Paris Data (1 fichier / heure)
        |                                                   |
    producer -> Kafka (topic velib-status)             source2
        |                                                   |
    aggregator ------------- jointure sur le code station --+
        |
    Data Lake : raw/api  raw/source2  aggregated  clean
        |
    Spark -> PostgreSQL schéma public (commune, station, releve, type_velo, releve_velo, pipeline_run)
        |
    TP3 : raw/api + raw/source2 rechargés dans le schéma tp3 -> audit -> nettoyage -> schéma tp3_cible
```

Changement par rapport au TP1 : l'API geo (population, surface des communes) n'est pas utilisée dans le pipeline. Les colonnes `population` et `surface_ha` de `commune` restent donc vides.

## Sources vérifiées

| Source | Format | Volume chargé (25/09 08h29 -> 28/09 08h00 UTC) | Clé | Remarques de l'audit |
|---|---|---|---|---|
| API GBFS `station_status` | JSON, un tableau `stations` imbriqué | 2 090 144 lignes, 1 376 collectes, 1 519 stations | station_id (stationCode en clé métier) | sur 13 collectes `stationCode` est null et `num_bikes_available_types` vaut `[{}, {}]` |
| CSV Paris Data | CSV `;` avec BOM | 26 fichiers, 39 486 lignes | stationcode | 3 fichiers du 26/09 (01h44, 03h00, 04h29) ont toutes leurs colonnes vides |

## Champs, types et correspondances

| Champ source | Type brut | Champ cible | Type cible | Transformation |
|---|---|---|---|---|
| station_id (API) | nombre JSON | station.station_id / releve.station_id | BIGINT | aucune |
| stationCode (API) / stationcode (CSV) | texte | station.code_station | VARCHAR(10) | clé de jointure entre les 2 sources |
| date_collecte (ajoutée par le producer) | texte ISO 8601 | releve.date_collecte | TIMESTAMPTZ | cast |
| last_reported (API) | timestamp Unix | releve.date_maj_station | TIMESTAMPTZ | to_timestamp |
| num_bikes_available_types (API) | tableau d'objets | releve_velo.nb_velos (1 ligne par type) | SMALLINT | dépliage du tableau |
| num_bikes_available (API) | entier | pas stocké | - | sert au contrôle K1 et à l'imputation R3 |
| num_docks_available (API) | entier | releve.bornes_libres | SMALLINT | aucune |
| is_installed / is_renting / is_returning (API) | 0 / 1 | releve.est_installee / location_active / retour_actif | BOOLEAN | = 1 |
| name (CSV) | texte | station.nom | VARCHAR(150) | trim + espaces multiples |
| capacity (CSV) | texte | station.capacite | SMALLINT | cast, doit être > 0 |
| coordonnees_geo (CSV) | texte "lat, lon" | station.latitude / longitude | DOUBLE PRECISION | découpage sur la virgule |
| nom_arrondissement_communes (CSV) | texte | commune.nom | VARCHAR(100) | trim |
| code_insee_commune (CSV) | texte | commune.code_insee / station.code_insee | CHAR(5) | trim, département = 2 premiers caractères |

## Tables

Schéma cible (inchangé depuis le TP1) :

```
commune 1 ── N station 1 ── N releve N ── N type_velo   (association : releve_velo, attribut nb_velos)
```

Ajouts du TP2 dans le schéma `public` : `pipeline_run` (suivi des exécutions Spark), `stg_releve` (table tampon) et la vue `v_releve`.

Schéma `tp3` (travail de l'audit) :

| Table | Contenu |
|---|---|
| api_brut | source 1 à plat, tout en texte |
| referentiel_brut | toutes les versions du CSV, tout en texte, avec le nom du fichier et sa date |
| releve_avant | relevés typés, joints au référentiel comme le faisait le pipeline (état "avant") |
| releve_travail, releve_apres_nettoyage | étapes du nettoyage |
| referentiel_valide | référentiel sans les fichiers vides, noms nettoyés |
| station_propre | dernière version valide de chaque station |
| journal_nettoyage | nombre de lignes touchées par chaque règle |
| resultat_controle | résultat de chaque contrôle, avant et après |
| releve_apres | relevés relus depuis `tp3_cible` (état "après") |

Schéma `tp3_cible` : copie exacte du schéma cible (mêmes contraintes), remplie avec les données nettoyées.
