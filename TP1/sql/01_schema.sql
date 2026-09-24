-- Base vélib : création des tables
-- à lancer sur une base vide :  createdb velib  puis  psql -d velib -f 01_schema.sql

DROP TABLE IF EXISTS releve_velo, releve, type_velo, station, commune CASCADE;

CREATE TABLE commune (
    code_insee       CHAR(5)       PRIMARY KEY,
    nom              VARCHAR(100)  NOT NULL,
    code_departement CHAR(2)       NOT NULL,
    population       INTEGER       CHECK (population >= 0),
    surface_ha       NUMERIC(10,2) CHECK (surface_ha > 0)
);

CREATE TABLE station (
    station_id  BIGINT       PRIMARY KEY,          -- id technique du flux GBFS
    code_station VARCHAR(10) NOT NULL UNIQUE,      -- code "métier" affiché sur la borne
    nom         VARCHAR(150) NOT NULL,
    latitude    DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude   DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    capacite    SMALLINT     NOT NULL CHECK (capacite > 0),
    code_insee  CHAR(5)      NOT NULL REFERENCES commune(code_insee)
);

CREATE TABLE type_velo (
    type_velo_id SERIAL      PRIMARY KEY,
    code         VARCHAR(20) NOT NULL UNIQUE,      -- valeur brute du flux : mechanical, ebike
    libelle      VARCHAR(50) NOT NULL
);

CREATE TABLE releve (
    releve_id        BIGSERIAL   PRIMARY KEY,
    station_id       BIGINT      NOT NULL REFERENCES station(station_id) ON DELETE CASCADE,
    date_collecte    TIMESTAMPTZ NOT NULL,          -- quand on a interrogé l'API
    date_maj_station TIMESTAMPTZ NOT NULL,          -- last_reported renvoyé par la station
    bornes_libres    SMALLINT    NOT NULL CHECK (bornes_libres >= 0),
    est_installee    BOOLEAN     NOT NULL,
    location_active  BOOLEAN     NOT NULL,
    retour_actif     BOOLEAN     NOT NULL,
    UNIQUE (station_id, date_collecte)
);

CREATE TABLE releve_velo (
    releve_id    BIGINT   NOT NULL REFERENCES releve(releve_id) ON DELETE CASCADE,
    type_velo_id INTEGER  NOT NULL REFERENCES type_velo(type_velo_id),
    nb_velos     SMALLINT NOT NULL CHECK (nb_velos >= 0),
    PRIMARY KEY (releve_id, type_velo_id)
);

CREATE INDEX idx_station_commune ON station(code_insee);
CREATE INDEX idx_releve_date ON releve(date_collecte);
