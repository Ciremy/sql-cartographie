-- Audit qualité : les mêmes contrôles sont lancés avant et après nettoyage.
-- Utilisation :
--   psql -v tbl=tp3.releve_avant -v phase=avant -f 02_audit.sql
--   psql -v tbl=tp3.releve_apres -v phase=apres -f 02_audit.sql
-- La table contrôlée doit avoir les colonnes : station_id, code_station, date_collecte, date_maj_station,
-- nb_velos, velos_mecaniques, velos_electriques, bornes_libres, est_installee,
-- nom, capacite, latitude, longitude, code_insee, commune

DELETE FROM tp3.resultat_controle WHERE phase = :'phase';

-- ================= COMPLÉTUDE =================

INSERT INTO tp3.resultat_controle (phase, id_controle, dimension, libelle, nb_controle, nb_anomalies)
SELECT :'phase', 'C1', 'Complétude', 'Code station renseigné',
       count(*), count(*) FILTER (WHERE code_station IS NULL)
FROM :tbl;

INSERT INTO tp3.resultat_controle (phase, id_controle, dimension, libelle, nb_controle, nb_anomalies)
SELECT :'phase', 'C2', 'Complétude', 'Répartition mécanique / électrique renseignée',
       count(*), count(*) FILTER (WHERE velos_mecaniques IS NULL OR velos_electriques IS NULL)
FROM :tbl;

INSERT INTO tp3.resultat_controle (phase, id_controle, dimension, libelle, nb_controle, nb_anomalies)
SELECT :'phase', 'C3', 'Complétude', 'Infos station renseignées (nom, capacité, position, commune)',
       count(*), count(*) FILTER (WHERE nom IS NULL OR capacite IS NULL OR latitude IS NULL
                                     OR longitude IS NULL OR code_insee IS NULL OR commune IS NULL)
FROM :tbl;

-- une collecte attendue par minute entre la première et la dernière
INSERT INTO tp3.resultat_controle (phase, id_controle, dimension, libelle, nb_controle, nb_anomalies)
SELECT :'phase', 'C4', 'Complétude', 'Collectes présentes (1 par minute attendue)',
       extract(epoch FROM max(m) - min(m)) / 60 + 1,
       extract(epoch FROM max(m) - min(m)) / 60 + 1 - count(DISTINCT m)
FROM (SELECT date_trunc('minute', date_collecte) AS m FROM :tbl) x;

-- ================= UNICITÉ =================

INSERT INTO tp3.resultat_controle (phase, id_controle, dimension, libelle, nb_controle, nb_anomalies)
SELECT :'phase', 'U1', 'Unicité', 'Un seul relevé par station et par collecte',
       count(*), count(*) - count(DISTINCT (station_id, date_collecte))
FROM :tbl;

INSERT INTO tp3.resultat_controle (phase, id_controle, dimension, libelle, nb_controle, nb_anomalies)
SELECT :'phase', 'U2', 'Unicité', 'Un code station = un seul identifiant station',
       count(*), count(*) FILTER (WHERE nb_id > 1)
FROM (SELECT code_station, count(DISTINCT station_id) AS nb_id FROM :tbl
      WHERE code_station IS NOT NULL GROUP BY code_station) x;

-- ================= VALIDITÉ =================

INSERT INTO tp3.resultat_controle (phase, id_controle, dimension, libelle, nb_controle, nb_anomalies)
SELECT :'phase', 'V1', 'Validité', 'Capacité strictement positive',
       count(capacite), count(*) FILTER (WHERE capacite <= 0)
FROM :tbl;

INSERT INTO tp3.resultat_controle (phase, id_controle, dimension, libelle, nb_controle, nb_anomalies)
SELECT :'phase', 'V2', 'Validité', 'Compteurs de vélos et de bornes positifs',
       count(*), count(*) FILTER (WHERE nb_velos < 0 OR velos_mecaniques < 0 OR velos_electriques < 0 OR bornes_libres < 0)
FROM :tbl;

-- emprise large de l'Île-de-France
INSERT INTO tp3.resultat_controle (phase, id_controle, dimension, libelle, nb_controle, nb_anomalies)
SELECT :'phase', 'V3', 'Validité', 'Coordonnées dans l''Île-de-France',
       count(latitude), count(*) FILTER (WHERE latitude NOT BETWEEN 48.1 AND 49.3 OR longitude NOT BETWEEN 1.4 AND 3.6)
FROM :tbl;

INSERT INTO tp3.resultat_controle (phase, id_controle, dimension, libelle, nb_controle, nb_anomalies)
SELECT :'phase', 'V4', 'Validité', 'Code INSEE sur 5 chiffres et département francilien',
       count(code_insee), count(*) FILTER (WHERE code_insee !~ '^\d{5}$'
                                              OR left(code_insee, 2) NOT IN ('75','77','78','91','92','93','94','95'))
FROM :tbl;

INSERT INTO tp3.resultat_controle (phase, id_controle, dimension, libelle, nb_controle, nb_anomalies)
SELECT :'phase', 'V5', 'Validité', 'Nom de station sans espaces en trop',
       count(nom), count(*) FILTER (WHERE nom <> trim(nom) OR nom ~ '\s{2,}')
FROM :tbl;

-- 5 minutes de tolérance
INSERT INTO tp3.resultat_controle (phase, id_controle, dimension, libelle, nb_controle, nb_anomalies)
SELECT :'phase', 'V6', 'Validité', 'Mise à jour station antérieure à la collecte',
       count(*), count(*) FILTER (WHERE date_maj_station > date_collecte + interval '5 minutes')
FROM :tbl;

-- ================= COHÉRENCE =================

INSERT INTO tp3.resultat_controle (phase, id_controle, dimension, libelle, nb_controle, nb_anomalies)
SELECT :'phase', 'K1', 'Cohérence', 'Total vélos = mécaniques + électriques',
       count(*) FILTER (WHERE velos_mecaniques IS NOT NULL AND velos_electriques IS NOT NULL),
       count(*) FILTER (WHERE nb_velos <> velos_mecaniques + velos_electriques)
FROM :tbl;

INSERT INTO tp3.resultat_controle (phase, id_controle, dimension, libelle, nb_controle, nb_anomalies)
SELECT :'phase', 'K2', 'Cohérence', 'Vélos + bornes libres <= capacité',
       count(capacite), count(*) FILTER (WHERE nb_velos + bornes_libres > capacite)
FROM :tbl;

INSERT INTO tp3.resultat_controle (phase, id_controle, dimension, libelle, nb_controle, nb_anomalies)
SELECT :'phase', 'K3', 'Cohérence', 'Station qui a remonté une info dans les dernières 24 h',
       count(*), count(*) FILTER (WHERE date_maj_station < date_collecte - interval '24 hours')
FROM :tbl;

INSERT INTO tp3.resultat_controle (phase, id_controle, dimension, libelle, nb_controle, nb_anomalies)
SELECT :'phase', 'K4', 'Cohérence', 'Un code INSEE = un seul nom de commune',
       count(*), count(*) FILTER (WHERE nb_noms > 1)
FROM (SELECT code_insee, count(DISTINCT commune) AS nb_noms FROM :tbl
      WHERE code_insee IS NOT NULL GROUP BY code_insee) x;

-- ================= INTÉGRITÉ =================

-- le code station de l'API doit exister dans le référentiel (source 2)
INSERT INTO tp3.resultat_controle (phase, id_controle, dimension, libelle, nb_controle, nb_anomalies)
SELECT :'phase', 'I1', 'Intégrité', 'Code station connu du référentiel',
       count(code_station),
       count(*) FILTER (WHERE code_station IS NOT NULL AND code_station NOT IN
                        (SELECT stationcode FROM tp3.referentiel_brut WHERE stationcode IS NOT NULL))
FROM :tbl;

-- un relevé doit pouvoir être rattaché à une station ET à une commune pour respecter les FK du schéma cible
INSERT INTO tp3.resultat_controle (phase, id_controle, dimension, libelle, nb_controle, nb_anomalies)
SELECT :'phase', 'I2', 'Intégrité', 'Relevé rattachable à une station et une commune (FK cible)',
       count(*), count(*) FILTER (WHERE station_id IS NULL OR code_station IS NULL OR code_insee IS NULL)
FROM :tbl;

SELECT id_controle, dimension, libelle, nb_controle, nb_anomalies,
       round(100.0 * nb_anomalies / NULLIF(nb_controle, 0), 2) AS taux_pct
FROM tp3.resultat_controle WHERE phase = :'phase' ORDER BY id_controle;
