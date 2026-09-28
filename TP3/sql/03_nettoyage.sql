-- Nettoyage : on part des relevés typés (tp3.releve_avant) et on applique les règles une par une.
-- Chaque règle écrit le nombre de lignes touchées dans tp3.journal_nettoyage.

DROP TABLE IF EXISTS tp3.journal_nettoyage;
CREATE TABLE tp3.journal_nettoyage (
    ordre     INT,
    regle     TEXT,
    controle  TEXT,   -- contrôle de la matrice concerné
    action    TEXT,   -- suppression, substitution, imputation, correction, aucune
    nb_lignes BIGINT
);

-- table de travail : uniquement la partie API, le référentiel sera re-joint proprement (R4)
DROP TABLE IF EXISTS tp3.releve_travail;
CREATE TABLE tp3.releve_travail AS
SELECT ligne_id, station_id, code_station, date_collecte, date_maj_station, nb_velos,
       velos_mecaniques, velos_electriques, bornes_libres, est_installee,
       false AS date_corrigee, false AS velos_imputes
FROM tp3.releve_avant;
CREATE INDEX ON tp3.releve_travail (station_id, date_collecte);


-- R1 - Heure de collecte fausse (V6)
-- Sur 2 collectes, presque toutes les stations ont une mise à jour jusqu'à 58 min APRÈS la collecte.
-- Ce n'est pas la station qui se trompe mais l'horloge du conteneur producer, en retard après une mise
-- en veille du PC. On remplace l'heure de collecte par la plus récente mise à jour reçue dans cette collecte.
WITH collectes_ko AS (
    SELECT date_collecte, max(date_maj_station) AS nouvelle_date
    FROM tp3.releve_travail
    GROUP BY date_collecte
    HAVING count(*) FILTER (WHERE date_maj_station > date_collecte + interval '5 minutes') > count(*) / 2
), maj AS (
    UPDATE tp3.releve_travail t SET date_collecte = c.nouvelle_date, date_corrigee = true
    FROM collectes_ko c WHERE t.date_collecte = c.date_collecte
    RETURNING 1
)
INSERT INTO tp3.journal_nettoyage SELECT 1, 'R1 - heure de collecte recalée sur la dernière mise à jour reçue', 'V6', 'correction', count(*) FROM maj;


-- R2 - Code station absent (C1)
-- L'API renvoie parfois stationCode = null pour toute une collecte. Le contrôle U2 montre qu'un station_id
-- correspond toujours au même code : on reprend le code connu pour ce station_id.
WITH codes AS (
    SELECT station_id, max(code_station) AS code_station
    FROM tp3.releve_travail WHERE code_station IS NOT NULL GROUP BY station_id
), maj AS (
    UPDATE tp3.releve_travail t SET code_station = c.code_station
    FROM codes c WHERE t.code_station IS NULL AND t.station_id = c.station_id
    RETURNING 1
)
INSERT INTO tp3.journal_nettoyage SELECT 2, 'R2 - code station repris depuis le station_id', 'C1', 'substitution', count(*) FROM maj;


-- R3 - Répartition mécanique / électrique absente (C2)
-- Sur ces mêmes collectes le total de vélos est bon, seule la répartition manque ([{}, {}]).
-- On garde le total et on reprend la part d'électriques du relevé précédent de la station (sinon du suivant),
-- plafonnée au total. Les collectes sont à 1 min d'écart, la répartition bouge très peu.
WITH voisins AS (
    SELECT ligne_id, nb_velos,
           lag(velos_electriques)  OVER w AS elec_avant,
           lead(velos_electriques) OVER w AS elec_apres
    FROM tp3.releve_travail
    WINDOW w AS (PARTITION BY station_id ORDER BY date_collecte)
), maj AS (
    UPDATE tp3.releve_travail t
    SET velos_electriques = least(coalesce(v.elec_avant, v.elec_apres), t.nb_velos),
        velos_mecaniques  = t.nb_velos - least(coalesce(v.elec_avant, v.elec_apres), t.nb_velos),
        velos_imputes = true
    FROM voisins v
    WHERE v.ligne_id = t.ligne_id AND t.velos_electriques IS NULL
      AND coalesce(v.elec_avant, v.elec_apres) IS NOT NULL
    RETURNING 1
)
INSERT INTO tp3.journal_nettoyage SELECT 3, 'R3 - répartition imputée depuis le relevé voisin', 'C2', 'imputation', count(*) FROM maj;

WITH sup AS (DELETE FROM tp3.releve_travail WHERE velos_electriques IS NULL OR velos_mecaniques IS NULL RETURNING 1)
INSERT INTO tp3.journal_nettoyage SELECT 3, 'R3 - répartition impossible à imputer (pas de voisin)', 'C2', 'suppression', count(*) FROM sup;


-- R4 / R5 - Référentiel (C3, V5)
-- 3 fichiers Paris Data du 26/09 (01h44, 03h00, 04h29) sont vides ou quasi vides. On ne garde que
-- les fichiers complets (au moins 1500 stations avec un nom) et on nettoie les noms au passage (R5).
DROP TABLE IF EXISTS tp3.referentiel_valide;
CREATE TABLE tp3.referentiel_valide AS
SELECT r.stationcode AS code_station,
       regexp_replace(trim(r.name), '\s+', ' ', 'g') AS nom,
       r.name <> regexp_replace(trim(r.name), '\s+', ' ', 'g') AS nom_corrige,
       tp3.en_entier(r.capacity) AS capacite,
       tp3.en_decimal(split_part(r.coordonnees_geo, ',', 1)) AS latitude,
       tp3.en_decimal(split_part(r.coordonnees_geo, ',', 2)) AS longitude,
       trim(r.commune) AS commune,
       trim(r.code_insee) AS code_insee,
       r.fichier, r.date_fichier
FROM tp3.referentiel_brut r
WHERE r.fichier IN (SELECT fichier FROM tp3.referentiel_brut GROUP BY fichier HAVING count(name) >= 1500);
CREATE INDEX ON tp3.referentiel_valide (date_fichier, code_station);

INSERT INTO tp3.journal_nettoyage
SELECT 4, 'R4 - fichiers référentiel écartés (vides)', 'C3', 'suppression', count(*)
FROM tp3.referentiel_brut WHERE fichier NOT IN (SELECT fichier FROM tp3.referentiel_valide);

-- chaque collecte est jointe au dernier fichier VALIDE téléchargé avant elle (ou au premier après, s'il n'y en a pas)
DROP TABLE IF EXISTS tp3.releve_apres_nettoyage;
CREATE TABLE tp3.releve_apres_nettoyage AS
WITH fichiers AS MATERIALIZED (SELECT DISTINCT date_fichier FROM tp3.referentiel_valide),
fichier_collecte AS MATERIALIZED (
    SELECT c.date_collecte,
           coalesce((SELECT max(date_fichier) FROM fichiers WHERE date_fichier <= c.date_collecte),
                    (SELECT min(date_fichier) FROM fichiers)) AS date_fichier
    FROM (SELECT DISTINCT date_collecte FROM tp3.releve_travail) c
)
SELECT t.*, r.nom, r.nom_corrige, r.capacite, r.latitude, r.longitude, r.code_insee, r.commune
FROM tp3.releve_travail t
JOIN fichier_collecte fc ON fc.date_collecte = t.date_collecte
LEFT JOIN tp3.referentiel_valide r ON r.date_fichier = fc.date_fichier AND r.code_station = t.code_station;

INSERT INTO tp3.journal_nettoyage
SELECT 4, 'R4 - infos station reprises du dernier référentiel valide', 'C3', 'substitution', count(*)
FROM tp3.releve_apres_nettoyage n JOIN tp3.releve_avant a USING (ligne_id)
WHERE a.nom IS NULL AND n.nom IS NOT NULL;

INSERT INTO tp3.journal_nettoyage
SELECT 5, 'R5 - noms de station sans espaces en trop', 'V5', 'correction', count(*)
FROM tp3.releve_apres_nettoyage WHERE nom_corrige;


-- R6 - Capacité à 0 (V1)
-- 3 stations ont une capacité de 0 : fermées ou en travaux, elles ne proposent aucun vélo.
-- Elles sont refusées par la contrainte CHECK (capacite > 0) du schéma cible : on supprime leurs relevés.
WITH sup AS (DELETE FROM tp3.releve_apres_nettoyage WHERE capacite <= 0 RETURNING 1)
INSERT INTO tp3.journal_nettoyage SELECT 6, 'R6 - relevés de stations à capacité 0', 'V1', 'suppression', count(*) FROM sup;


-- R7 - Stations muettes (K3)
-- 17 stations n'ont rien remonté depuis plus de 24 h (une depuis 2021). Leurs compteurs sont figés,
-- les garder fausserait les indicateurs de disponibilité. On supprime ces relevés (la station reste connue).
WITH sup AS (DELETE FROM tp3.releve_apres_nettoyage WHERE date_maj_station < date_collecte - interval '24 hours' RETURNING 1)
INSERT INTO tp3.journal_nettoyage SELECT 7, 'R7 - relevés de stations muettes depuis plus de 24 h', 'K3', 'suppression', count(*) FROM sup;


-- R8 - Relevés sans station rattachable (I2) : ne devrait plus rien rester après R2 et R4
WITH sup AS (DELETE FROM tp3.releve_apres_nettoyage
             WHERE station_id IS NULL OR code_station IS NULL OR code_insee IS NULL OR nom IS NULL RETURNING 1)
INSERT INTO tp3.journal_nettoyage SELECT 8, 'R8 - relevés impossibles à rattacher', 'I2', 'suppression', count(*) FROM sup;


-- R9 - Doublons (U1) : par sécurité, un seul relevé par station et collecte
WITH sup AS (
    DELETE FROM tp3.releve_apres_nettoyage t
    USING tp3.releve_apres_nettoyage d
    WHERE t.station_id = d.station_id AND t.date_collecte = d.date_collecte AND t.ligne_id > d.ligne_id
    RETURNING 1
)
INSERT INTO tp3.journal_nettoyage SELECT 9, 'R9 - doublons station / collecte', 'U1', 'suppression', count(*) FROM sup;


-- Pas de correction pour :
-- K2 : vélos + bornes > capacité. Vélib' accepte des vélos en surplus sur certaines stations ("overflow"),
--      l'info vient de l'opérateur, on la garde telle quelle.
-- C4 : collectes manquantes. On ne fabrique pas de relevés pour les minutes où le PC était en veille.
INSERT INTO tp3.journal_nettoyage
SELECT 10, 'K2 - vélos + bornes > capacité (surplus accepté par Vélib'')', 'K2', 'aucune', count(*)
FROM tp3.releve_apres_nettoyage WHERE nb_velos + bornes_libres > capacite;

SELECT ordre, regle, controle, action, nb_lignes FROM tp3.journal_nettoyage ORDER BY ordre, regle;
