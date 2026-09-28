-- Vue "avant nettoyage" : les données telles que le pipeline du TP2 les a vues.
-- Chaque relevé API est joint au dernier fichier référentiel téléchargé avant la collecte,
-- même si ce fichier est vide (c'est ce que faisait l'agrégateur).
-- Seules les conversions de type sont faites (en douceur, NULL si invalide) pour pouvoir contrôler.

DROP TABLE IF EXISTS tp3.releve_avant;

CREATE INDEX IF NOT EXISTS idx_ref_brut ON tp3.referentiel_brut (stationcode, date_fichier);

CREATE TABLE tp3.releve_avant AS
WITH fichier_collecte AS MATERIALIZED (
    -- pour chaque collecte, le dernier fichier référentiel téléchargé avant
    SELECT c.date_collecte,
           (SELECT max(f.date_fichier) FROM (SELECT DISTINCT date_fichier FROM tp3.referentiel_brut) f
            WHERE f.date_fichier <= c.date_collecte::timestamptz) AS date_fichier
    FROM (SELECT DISTINCT date_collecte FROM tp3.api_brut) c
)
SELECT a.ligne_id,
       tp3.en_entier(a.station_id)                        AS station_id,
       a.station_code                                     AS code_station,
       a.date_collecte::timestamptz                       AS date_collecte,
       to_timestamp(tp3.en_entier(a.last_reported))       AS date_maj_station,
       tp3.en_entier(a.nb_velos)                          AS nb_velos,
       tp3.en_entier(a.velos_mecaniques)                  AS velos_mecaniques,
       tp3.en_entier(a.velos_electriques)                 AS velos_electriques,
       tp3.en_entier(a.bornes_libres)                     AS bornes_libres,
       a.is_installed = '1'                               AS est_installee,
       r.name                                             AS nom,
       tp3.en_entier(r.capacity)                          AS capacite,
       tp3.en_decimal(split_part(r.coordonnees_geo, ',', 1)) AS latitude,
       tp3.en_decimal(split_part(r.coordonnees_geo, ',', 2)) AS longitude,
       r.code_insee,
       r.commune
FROM tp3.api_brut a
JOIN fichier_collecte fc ON fc.date_collecte = a.date_collecte
LEFT JOIN tp3.referentiel_brut r ON r.date_fichier = fc.date_fichier AND r.stationcode = a.station_code;

ANALYZE tp3.releve_avant;
