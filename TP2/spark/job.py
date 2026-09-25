"""Job PySpark : data lake (zone aggregated) -> nettoyage -> PostgreSQL.

Le job est lancé toutes les X minutes par run.sh. Il ne traite que les fichiers
qu'il n'a pas encore vus (liste gardée dans /datalake/_spark/fichiers_traites.txt).
"""
import glob
import os
from datetime import datetime, timezone

import psycopg2
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import StringType, StructField, StructType

LAKE = os.getenv("DATALAKE_PATH", "/datalake")
ETAT = f"{LAKE}/_spark/fichiers_traites.txt"

PG = {
    "host": os.getenv("POSTGRES_HOST", "postgres"),
    "dbname": os.getenv("POSTGRES_DB", "velib"),
    "user": os.getenv("POSTGRES_USER", "velib"),
    "password": os.getenv("POSTGRES_PASSWORD", "velib"),
}
JDBC_URL = f"jdbc:postgresql://{PG['host']}:5432/{PG['dbname']}"

# tout est lu en texte, les types sont contrôlés ensuite
COLONNES = ["station_id", "station_code", "date_collecte", "last_reported", "velos_mecaniques",
            "velos_electriques", "bornes_libres", "is_installed", "is_renting", "is_returning",
            "nom", "capacite", "coordonnees_geo", "commune", "code_insee"]
SCHEMA = StructType([StructField(c, StringType()) for c in COLONNES])


def nouveaux_fichiers():
    deja_faits = set()
    if os.path.exists(ETAT):
        with open(ETAT) as f:
            deja_faits = set(f.read().split())
    tous = sorted(glob.glob(f"{LAKE}/aggregated/date=*/*.jsonl"))
    return [f for f in tous if f not in deja_faits]


def nettoyer(df):
    coords = F.split(F.col("coordonnees_geo"), ",")
    df = df.select(
        F.col("station_id").cast("long").alias("station_id"),
        F.trim("station_code").alias("code_station"),
        F.regexp_replace(F.trim("nom"), r"\s+", " ").alias("nom"),
        F.trim(coords.getItem(0)).cast("double").alias("latitude"),
        F.trim(coords.getItem(1)).cast("double").alias("longitude"),
        F.col("capacite").cast("int").alias("capacite"),
        F.lpad(F.trim("code_insee"), 5, "0").alias("code_insee"),
        F.trim("commune").alias("commune"),
        F.to_timestamp("date_collecte").alias("date_collecte"),
        F.to_timestamp(F.col("last_reported").cast("long")).alias("date_maj_station"),
        F.col("velos_mecaniques").cast("int").alias("velos_mecaniques"),
        F.col("velos_electriques").cast("int").alias("velos_electriques"),
        F.col("bornes_libres").cast("int").alias("bornes_libres"),
        (F.col("is_installed").cast("int") == 1).alias("est_installee"),
        (F.col("is_renting").cast("int") == 1).alias("location_active"),
        (F.col("is_returning").cast("int") == 1).alias("retour_actif"),
    )
    # un nombre de vélos absent pour un type = aucun vélo de ce type
    df = df.fillna({"velos_mecaniques": 0, "velos_electriques": 0})

    # lignes inutilisables : station inconnue du référentiel, champs obligatoires vides ou valeurs incohérentes
    valide = (
        F.col("station_id").isNotNull() & F.col("date_collecte").isNotNull()
        & F.col("date_maj_station").isNotNull() & F.col("code_insee").isNotNull()
        & F.col("nom").isNotNull() & F.col("latitude").isNotNull() & F.col("longitude").isNotNull()
        & (F.col("capacite") > 0) & (F.col("bornes_libres") >= 0)
        & (F.col("velos_mecaniques") >= 0) & (F.col("velos_electriques") >= 0)
        & F.col("est_installee").isNotNull()
    )
    return df.filter(valide)


def charger(cur):
    cur.execute("""
        INSERT INTO commune (code_insee, nom, code_departement)
        SELECT DISTINCT ON (code_insee) code_insee, commune, LEFT(code_insee, 2)
        FROM stg_releve ORDER BY code_insee
        ON CONFLICT (code_insee) DO NOTHING
    """)
    # la dernière version de la station gagne (nom ou capacité peuvent changer)
    cur.execute("""
        INSERT INTO station (station_id, code_station, nom, latitude, longitude, capacite, code_insee)
        SELECT DISTINCT ON (station_id) station_id, code_station, nom, latitude, longitude, capacite, code_insee
        FROM stg_releve ORDER BY station_id, date_collecte DESC
        ON CONFLICT (station_id) DO UPDATE SET
            nom = EXCLUDED.nom, latitude = EXCLUDED.latitude, longitude = EXCLUDED.longitude,
            capacite = EXCLUDED.capacite, code_insee = EXCLUDED.code_insee
    """)
    cur.execute("""
        WITH ins AS (
            INSERT INTO releve (station_id, date_collecte, date_maj_station, bornes_libres,
                                est_installee, location_active, retour_actif)
            SELECT station_id, date_collecte, date_maj_station, bornes_libres,
                   est_installee, location_active, retour_actif
            FROM stg_releve
            ON CONFLICT (station_id, date_collecte) DO NOTHING
            RETURNING releve_id, station_id, date_collecte
        ), velos AS (
            INSERT INTO releve_velo (releve_id, type_velo_id, nb_velos)
            SELECT ins.releve_id, t.type_velo_id, v.nb
            FROM ins
            JOIN stg_releve s ON s.station_id = ins.station_id AND s.date_collecte = ins.date_collecte
            CROSS JOIN LATERAL (VALUES ('mechanical', s.velos_mecaniques), ('ebike', s.velos_electriques)) AS v(code, nb)
            JOIN type_velo t ON t.code = v.code
            RETURNING 1
        )
        SELECT COUNT(*) FROM ins
    """)
    return cur.fetchone()[0]


def main():
    debut = datetime.now(timezone.utc)
    fichiers = nouveaux_fichiers()
    if not fichiers:
        print("rien de nouveau dans le data lake")
        return

    spark = SparkSession.builder.appName("velib-clean").getOrCreate()
    spark.sparkContext.setLogLevel("WARN")

    brut = spark.read.schema(SCHEMA).json(fichiers)
    nb_raw = brut.count()

    propre = nettoyer(brut).cache()
    nb_valides = propre.count()

    # doublons : même station, même collecte (possible si un message Kafka est relu)
    propre = propre.dropDuplicates(["station_id", "date_collecte"])
    nb_propres = propre.count()

    # zone clean du data lake (parquet) puis table de staging dans postgres
    propre.withColumn("date", F.to_date("date_collecte")) \
        .write.mode("append").partitionBy("date").parquet(f"{LAKE}/clean/releves")
    propre.write.format("jdbc").mode("overwrite") \
        .option("url", JDBC_URL).option("dbtable", "stg_releve").option("truncate", "true") \
        .option("user", PG["user"]).option("password", PG["password"]) \
        .option("driver", "org.postgresql.Driver").save()

    with psycopg2.connect(**PG) as conn, conn.cursor() as cur:
        nb_charges = charger(cur)
        doublons = nb_valides - nb_charges
        cur.execute(
            "INSERT INTO pipeline_run (debut, fin, nb_fichiers, lignes_raw, lignes_rejetees, doublons, lignes_chargees)"
            " VALUES (%s, now(), %s, %s, %s, %s, %s)",
            (debut, len(fichiers), nb_raw, nb_raw - nb_valides, doublons, nb_charges),
        )

    os.makedirs(os.path.dirname(ETAT), exist_ok=True)
    with open(ETAT, "a") as f:
        f.write("\n".join(fichiers) + "\n")

    print(f"{len(fichiers)} fichiers, {nb_raw} lignes brutes, {nb_raw - nb_valides} rejetées, "
          f"{doublons} doublons, {nb_charges} relevés chargés ({nb_propres} après dédoublonnage)")
    spark.stop()


if __name__ == "__main__":
    main()
