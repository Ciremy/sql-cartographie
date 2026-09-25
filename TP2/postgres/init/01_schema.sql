-- Schéma repris du TP1 (TP1/sql/01_schema.sql)
-- population et surface sont laissées vides : elles ne sont pas dans les sources du TP2

CREATE TABLE commune (
    code_insee       CHAR(5)       PRIMARY KEY,
    nom              VARCHAR(100)  NOT NULL,
    code_departement CHAR(2)       NOT NULL,
    population       INTEGER       CHECK (population >= 0),
    surface_ha       NUMERIC(10,2) CHECK (surface_ha > 0)
);

CREATE TABLE station (
    station_id   BIGINT       PRIMARY KEY,
    code_station VARCHAR(10)  NOT NULL UNIQUE,
    nom          VARCHAR(150) NOT NULL,
    latitude     DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude    DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    capacite     SMALLINT     NOT NULL CHECK (capacite > 0),
    code_insee   CHAR(5)      NOT NULL REFERENCES commune(code_insee)
);

CREATE TABLE type_velo (
    type_velo_id SERIAL      PRIMARY KEY,
    code         VARCHAR(20) NOT NULL UNIQUE,
    libelle      VARCHAR(50) NOT NULL
);

CREATE TABLE releve (
    releve_id        BIGSERIAL   PRIMARY KEY,
    station_id       BIGINT      NOT NULL REFERENCES station(station_id) ON DELETE CASCADE,
    date_collecte    TIMESTAMPTZ NOT NULL,
    date_maj_station TIMESTAMPTZ NOT NULL,
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

INSERT INTO type_velo (code, libelle) VALUES
    ('mechanical', 'Vélo mécanique'),
    ('ebike', 'Vélo électrique');

-- Nouveau pour le TP2 : une ligne par exécution du job Spark (sert au suivi raw vs clean)
CREATE TABLE pipeline_run (
    run_id          SERIAL      PRIMARY KEY,
    debut           TIMESTAMPTZ NOT NULL,
    fin             TIMESTAMPTZ NOT NULL,
    nb_fichiers     INTEGER     NOT NULL,
    lignes_raw      INTEGER     NOT NULL,   -- lignes lues dans le data lake
    lignes_rejetees INTEGER     NOT NULL,   -- valeurs manquantes / incohérentes
    doublons        INTEGER     NOT NULL,
    lignes_chargees INTEGER     NOT NULL    -- nouveaux relevés insérés dans releve
);

-- Vue utilisée par le dashboard : un relevé à plat avec les vélos par type
CREATE VIEW v_releve AS
SELECT r.releve_id, r.date_collecte, s.station_id, s.code_station, s.nom AS station,
       s.latitude, s.longitude, s.capacite, c.code_insee, c.nom AS commune,
       COALESCE(SUM(rv.nb_velos) FILTER (WHERE t.code = 'mechanical'), 0) AS velos_mecaniques,
       COALESCE(SUM(rv.nb_velos) FILTER (WHERE t.code = 'ebike'), 0)      AS velos_electriques,
       r.bornes_libres, r.est_installee
FROM releve r
JOIN station s ON s.station_id = r.station_id
JOIN commune c ON c.code_insee = s.code_insee
LEFT JOIN releve_velo rv ON rv.releve_id = r.releve_id
LEFT JOIN type_velo t ON t.type_velo_id = rv.type_velo_id
GROUP BY r.releve_id, s.station_id, c.code_insee;

-- Table tampon remplie par Spark (vidée à chaque exécution) avant insertion dans les vraies tables
CREATE TABLE stg_releve (
    station_id        BIGINT,
    code_station      TEXT,
    nom               TEXT,
    latitude          DOUBLE PRECISION,
    longitude         DOUBLE PRECISION,
    capacite          INTEGER,
    code_insee        TEXT,
    commune           TEXT,
    date_collecte     TIMESTAMPTZ,
    date_maj_station  TIMESTAMPTZ,
    velos_mecaniques  INTEGER,
    velos_electriques INTEGER,
    bornes_libres     INTEGER,
    est_installee     BOOLEAN,
    location_active   BOOLEAN,
    retour_actif      BOOLEAN
);
