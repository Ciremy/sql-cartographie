#!/bin/bash
# Charge les données brutes du data lake du TP2 dans le schéma tp3.
# À lancer depuis le dossier TP3, avec la stack du TP2 démarrée.
set -e
cd "$(dirname "$0")/.."
LAKE=../TP2/datalake/data
# le TP2 continue de collecter : on fige la période pour que les résultats soient reproductibles
# (fichiers du data lake jusqu'à cette date, en UTC, au format du nom de dossier/fichier)
FIN=${FIN:-2026-09-28/080000}

# liste des fichiers d'une zone jusqu'à FIN (dossier date=AAAA-MM-JJ, fichier xxx_HHMMSS)
fichiers() {
  for f in $LAKE/$1/date=*/*_*.$2; do
    cle="$(basename "$(dirname "$f")" | cut -d= -f2)/$(basename "$f" .$2 | cut -d_ -f2)"
    [[ "$cle" < "$FIN" || "$cle" == "$FIN" ]] && echo "$f"
  done
}
PSQL="docker compose -f ../TP2/docker-compose.yml exec -T postgres psql -U velib -d velib -v ON_ERROR_STOP=1 -q"

$PSQL -f - < sql/00_schema.sql

# source 1 : tous les fichiers raw/api, une ligne JSON par ligne de fichier.
# Le format csv avec des caractères de contrôle comme séparateur/guillemet évite que COPY interprète le JSON.
echo "chargement raw/api..."
fichiers raw/api jsonl | xargs cat | $PSQL -c "\copy tp3.api_json(doc) from stdin with (format csv, quote e'\x01', delimiter e'\x02')"

$PSQL <<'SQL'
INSERT INTO tp3.api_brut (station_id, station_code, date_collecte, last_reported, nb_velos,
                          velos_mecaniques, velos_electriques, bornes_libres, is_installed, is_renting, is_returning)
SELECT doc->>'station_id', doc->>'stationCode', doc->>'date_collecte', doc->>'last_reported',
       doc->>'num_bikes_available',
       -- num_bikes_available_types = [{"mechanical": 8}, {"ebike": 1}]
       (SELECT t->>'mechanical' FROM jsonb_array_elements(doc->'num_bikes_available_types') t WHERE t ? 'mechanical'),
       (SELECT t->>'ebike'      FROM jsonb_array_elements(doc->'num_bikes_available_types') t WHERE t ? 'ebike'),
       doc->>'num_docks_available', doc->>'is_installed', doc->>'is_renting', doc->>'is_returning'
FROM tp3.api_json;
TRUNCATE tp3.api_json;
SQL

# source 2 : chaque CSV, en gardant le nom du fichier (sa date = heure du téléchargement, en UTC)
echo "chargement raw/source2..."
for f in $(fichiers raw/source2 csv); do
  jour=$(basename "$(dirname "$f")" | cut -d= -f2)
  heure=$(basename "$f" .csv | cut -d_ -f2)
  $PSQL -c "\copy tp3.referentiel_brut(stationcode, name, capacity, coordonnees_geo, commune, code_insee) from stdin with (format csv, header, delimiter ';')" < "$f"
  $PSQL -c "UPDATE tp3.referentiel_brut SET fichier = '$(basename "$f")', date_fichier = '$jour ${heure:0:2}:${heure:2:2}:${heure:4:2}+00' WHERE fichier IS NULL"
done

$PSQL -c "ANALYZE tp3.api_brut; ANALYZE tp3.referentiel_brut;"
$PSQL -c "SELECT 'api_brut' AS table_, count(*) FROM tp3.api_brut UNION ALL SELECT 'referentiel_brut', count(*) FROM tp3.referentiel_brut"
