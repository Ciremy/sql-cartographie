# TP Audit & cartographie des données - Vélib'

## Présentation du sujet

Thème choisi : le transport, avec les vélos en libre-service Vélib' (Paris et communes autour).

Contexte : il y a environ 1500 stations Vélib' et leur état (vélos dispo, places libres) est publié en open data. Mais les infos sont réparties dans plusieurs sources différentes.

Problématique : comment regrouper ces données pour suivre la disponibilité des vélos par station et par commune au cours du temps ?

Objectif : documenter les sources, faire le modèle de données et créer la base PostgreSQL.

## Sources de données

**1. Flux GBFS Vélib' Métropole**
- Organisation : Smovengo (opérateur Vélib')
- URL : https://velib-metropole-opendata.smovengo.cloud/opendata/Velib_Metropole/gbfs.json
- Format : JSON
- Nature : semi-structurée
- Description : deux fichiers, `station_information` (nom, position, capacité des stations) et `station_status` (vélos et places dispo en temps réel).

**2. Vélib' - Disponibilité en temps réel**
- Organisation : Ville de Paris (Paris Data)
- URL : https://opendata.paris.fr/explore/dataset/velib-disponibilite-en-temps-reel/
- Format : CSV, JSON, Excel
- Nature : structurée
- Description : les mêmes infos que le GBFS mais en tableau, avec en plus la commune de chaque station (code INSEE).

**3. API Découpage administratif**
- Organisation : Etalab (geo.api.gouv.fr)
- URL : https://geo.api.gouv.fr/decoupage-administratif/communes
- Format : JSON
- Nature : semi-structurée
- Description : infos sur les communes (nom, département, population, surface).

On relie le GBFS et Paris Data avec le code station, et Paris Data et l'API geo avec le code INSEE.

## Livrables

- Dictionnaire de données : [docs/dictionnaire.md](docs/dictionnaire.md)
- Entités, relations, MCD et modèle logique : [docs/modeles.md](docs/modeles.md)
- Modèle dbdiagram.io : [modele/velib.dbml](modele/velib.dbml)
- Script de création : [sql/01_schema.sql](sql/01_schema.sql)
- Données de test : [sql/02_donnees_test.sql](sql/02_donnees_test.sql)
- Requêtes de vérification : [sql/03_verifications.sql](sql/03_verifications.sql)

Pour créer la base :

```
createdb velib
psql -d velib -f sql/01_schema.sql
psql -d velib -f sql/02_donnees_test.sql
psql -d velib -f sql/03_verifications.sql
```

Les données de test viennent des vraies sources (récupérées le 24/09/2026) : 4 communes, 12 stations et 2 relevés par station.

## Cartographie globale

```
Sources (GBFS JSON, Paris Data CSV, API geo JSON)
   -> analyse des données + dictionnaire
   -> entités / relations (commune, station, releve, type_velo)
   -> MCD
   -> modèle logique (dbdiagram.io)
   -> base PostgreSQL
```

Qui alimente quoi dans la base :
- API geo -> table commune
- GBFS station_information + Paris Data -> table station
- GBFS station_status -> tables releve et releve_velo
