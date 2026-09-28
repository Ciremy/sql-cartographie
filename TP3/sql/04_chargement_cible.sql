-- Chargement des données nettoyées dans une copie du schéma cible (le même que TP1/TP2, avec ses contraintes).
-- Si une ligne ne respecte pas le schéma (FK, CHECK, UNIQUE), le script s'arrête : c'est le contrôle de conformité.

DROP SCHEMA IF EXISTS tp3_cible CASCADE;
CREATE SCHEMA tp3_cible;

CREATE TABLE tp3_cible.commune (
    code_insee       CHAR(5)       PRIMARY KEY,
    nom              VARCHAR(100)  NOT NULL,
    code_departement CHAR(2)       NOT NULL,
    population       INTEGER       CHECK (population >= 0),
    surface_ha       NUMERIC(10,2) CHECK (surface_ha > 0)
);

CREATE TABLE tp3_cible.station (
    station_id   BIGINT       PRIMARY KEY,
    code_station VARCHAR(10)  NOT NULL UNIQUE,
    nom          VARCHAR(150) NOT NULL,
    latitude     DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude    DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    capacite     SMALLINT     NOT NULL CHECK (capacite > 0),
    code_insee   CHAR(5)      NOT NULL REFERENCES tp3_cible.commune(code_insee)
);

CREATE TABLE tp3_cible.type_velo (
    type_velo_id SERIAL      PRIMARY KEY,
    code         VARCHAR(20) NOT NULL UNIQUE,
    libelle      VARCHAR(50) NOT NULL
);
INSERT INTO tp3_cible.type_velo (code, libelle) VALUES ('mechanical', 'Vélo mécanique'), ('ebike', 'Vélo électrique');

CREATE TABLE tp3_cible.releve (
    releve_id        BIGSERIAL   PRIMARY KEY,
    station_id       BIGINT      NOT NULL REFERENCES tp3_cible.station(station_id) ON DELETE CASCADE,
    date_collecte    TIMESTAMPTZ NOT NULL,
    date_maj_station TIMESTAMPTZ NOT NULL,
    bornes_libres    SMALLINT    NOT NULL CHECK (bornes_libres >= 0),
    est_installee    BOOLEAN     NOT NULL,
    location_active  BOOLEAN     NOT NULL,
    retour_actif     BOOLEAN     NOT NULL,
    UNIQUE (station_id, date_collecte)
);

CREATE TABLE tp3_cible.releve_velo (
    releve_id    BIGINT   NOT NULL REFERENCES tp3_cible.releve(releve_id) ON DELETE CASCADE,
    type_velo_id INTEGER  NOT NULL REFERENCES tp3_cible.type_velo(type_velo_id),
    nb_velos     SMALLINT NOT NULL CHECK (nb_velos >= 0),
    PRIMARY KEY (releve_id, type_velo_id)
);

-- stations : dernière version valide du référentiel (source 2), avec le station_id vu dans l'API (source 1).
-- On part du référentiel et pas des relevés pour garder aussi les stations dont on a supprimé les relevés (R7).
-- Les stations à capacité 0 sont exclues : elles ne passent pas le CHECK du schéma cible.
DROP TABLE IF EXISTS tp3.station_propre;
CREATE TABLE tp3.station_propre AS
SELECT DISTINCT ON (r.code_station) i.station_id, r.code_station, r.nom, r.latitude, r.longitude, r.capacite,
       r.code_insee, r.commune
FROM tp3.referentiel_valide r
JOIN (SELECT DISTINCT station_id, code_station FROM tp3.releve_travail) i ON i.code_station = r.code_station
WHERE r.capacite > 0
ORDER BY r.code_station, r.date_fichier DESC;

INSERT INTO tp3_cible.commune (code_insee, nom, code_departement)
SELECT DISTINCT code_insee, commune, left(code_insee, 2) FROM tp3.station_propre;

INSERT INTO tp3_cible.station (station_id, code_station, nom, latitude, longitude, capacite, code_insee)
SELECT station_id, code_station, nom, latitude, longitude, capacite, code_insee FROM tp3.station_propre;

-- relevés (location_active / retour_actif ne sont pas dans releve_avant, on les reprend du brut)
INSERT INTO tp3_cible.releve (station_id, date_collecte, date_maj_station, bornes_libres, est_installee, location_active, retour_actif)
SELECT n.station_id, n.date_collecte, n.date_maj_station, n.bornes_libres, n.est_installee,
       b.is_renting = '1', b.is_returning = '1'
FROM tp3.releve_apres_nettoyage n JOIN tp3.api_brut b USING (ligne_id);

INSERT INTO tp3_cible.releve_velo (releve_id, type_velo_id, nb_velos)
SELECT r.releve_id, t.type_velo_id, v.nb
FROM tp3.releve_apres_nettoyage n
JOIN tp3_cible.releve r ON r.station_id = n.station_id AND r.date_collecte = n.date_collecte
CROSS JOIN LATERAL (VALUES ('mechanical', n.velos_mecaniques), ('ebike', n.velos_electriques)) AS v(code, nb)
JOIN tp3_cible.type_velo t ON t.code = v.code;

-- table "après" relue depuis le schéma cible, avec les mêmes colonnes que tp3.releve_avant
DROP TABLE IF EXISTS tp3.releve_apres;
CREATE TABLE tp3.releve_apres AS
SELECT r.releve_id, s.station_id, s.code_station, r.date_collecte, r.date_maj_station,
       coalesce(sum(rv.nb_velos), 0) AS nb_velos,
       sum(rv.nb_velos) FILTER (WHERE t.code = 'mechanical') AS velos_mecaniques,
       sum(rv.nb_velos) FILTER (WHERE t.code = 'ebike') AS velos_electriques,
       r.bornes_libres, r.est_installee,
       s.nom, s.capacite, s.latitude, s.longitude, s.code_insee::text AS code_insee, c.nom AS commune
FROM tp3_cible.releve r
JOIN tp3_cible.station s ON s.station_id = r.station_id
JOIN tp3_cible.commune c ON c.code_insee = s.code_insee
LEFT JOIN tp3_cible.releve_velo rv ON rv.releve_id = r.releve_id
LEFT JOIN tp3_cible.type_velo t ON t.type_velo_id = rv.type_velo_id
GROUP BY r.releve_id, s.station_id, c.nom;

ANALYZE tp3.releve_apres;

SELECT 'commune' AS table_cible, count(*) FROM tp3_cible.commune
UNION ALL SELECT 'station', count(*) FROM tp3_cible.station
UNION ALL SELECT 'releve', count(*) FROM tp3_cible.releve
UNION ALL SELECT 'releve_velo', count(*) FROM tp3_cible.releve_velo;
