-- TP3 : schéma de travail pour l'audit qualité
-- On repart des données brutes du data lake du TP2 (raw/api et raw/source2), chargées telles quelles en texte.

DROP SCHEMA IF EXISTS tp3 CASCADE;
CREATE SCHEMA tp3;

-- source 1 : messages de l'API GBFS (1 ligne = 1 station à 1 collecte), JSON brut
CREATE TABLE tp3.api_json (doc JSONB);

-- source 1 à plat, tout en texte : aucune conversion à ce stade
CREATE TABLE tp3.api_brut (
    ligne_id          BIGSERIAL PRIMARY KEY,
    station_id        TEXT,
    station_code      TEXT,
    date_collecte     TEXT,
    last_reported     TEXT,
    nb_velos          TEXT,     -- num_bikes_available
    velos_mecaniques  TEXT,     -- extrait de num_bikes_available_types
    velos_electriques TEXT,
    bornes_libres     TEXT,
    is_installed      TEXT,
    is_renting        TEXT,
    is_returning      TEXT
);

-- source 2 : toutes les versions du CSV Paris Data téléchargées (1 fichier par heure environ)
CREATE TABLE tp3.referentiel_brut (
    stationcode   TEXT,
    name          TEXT,
    capacity      TEXT,
    coordonnees_geo TEXT,
    commune       TEXT,
    code_insee    TEXT,
    fichier       TEXT,
    date_fichier  TIMESTAMPTZ
);

-- résultats des contrôles, une ligne par contrôle et par phase (avant / apres)
CREATE TABLE tp3.resultat_controle (
    phase        TEXT NOT NULL,
    id_controle  TEXT NOT NULL,
    dimension    TEXT NOT NULL,
    libelle      TEXT NOT NULL,
    nb_controle  BIGINT NOT NULL,   -- nombre d'éléments contrôlés
    nb_anomalies BIGINT NOT NULL,
    date_controle TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (phase, id_controle)
);

-- conversion "douce" : renvoie NULL au lieu de planter si le texte n'est pas un nombre
CREATE FUNCTION tp3.en_entier(t TEXT) RETURNS BIGINT AS $$
    SELECT CASE WHEN trim(t) ~ '^-?\d+$' THEN trim(t)::BIGINT END
$$ LANGUAGE sql IMMUTABLE;

CREATE FUNCTION tp3.en_decimal(t TEXT) RETURNS DOUBLE PRECISION AS $$
    SELECT CASE WHEN trim(t) ~ '^-?\d+(\.\d+)?$' THEN trim(t)::DOUBLE PRECISION END
$$ LANGUAGE sql IMMUTABLE;
