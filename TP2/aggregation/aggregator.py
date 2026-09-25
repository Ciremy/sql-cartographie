"""Agrégation : consomme le topic Kafka et rapproche chaque message du référentiel (source 2).

Toutes les minutes environ on écrit deux fichiers dans le Data Lake :
- raw/api/...        les messages Kafka tels quels (on garde la donnée brute)
- aggregated/...     les messages enrichis avec le nom, la capacité et la commune de la station

Les offsets Kafka ne sont validés qu'après l'écriture des fichiers : en cas de crash on
peut relire des messages en double, c'est Spark qui fait le dédoublonnage.
"""
import csv
import glob
import json
import os
import time
from datetime import datetime, timezone

from confluent_kafka import Consumer
from prometheus_client import Counter, Gauge, start_http_server

LAKE = os.getenv("DATALAKE_PATH", "/datalake")
TOPIC = os.getenv("KAFKA_TOPIC", "velib-status")
BATCH_SECONDES = int(os.getenv("BATCH_SECONDS", "60"))

messages_lus = Counter("velib_aggregator_messages_total", "Messages lus dans Kafka")
sans_referentiel = Counter("velib_aggregator_unmatched_total", "Messages sans station correspondante dans la source 2")
raw_lake = Gauge("velib_datalake_raw_records", "Nombre de lignes brutes (API) dans le Data Lake")
agg_lake = Gauge("velib_datalake_aggregated_records", "Nombre de lignes agrégées dans le Data Lake")

referentiel = {}
fichier_referentiel = None


def compter_lignes(motif):
    total = 0
    for f in glob.glob(motif):
        with open(f) as fh:
            total += sum(1 for _ in fh)
    return total


def charger_referentiel():
    """Recharge le dernier CSV de la source 2 s'il a changé."""
    global referentiel, fichier_referentiel
    fichiers = sorted(glob.glob(f"{LAKE}/raw/source2/date=*/stations_*.csv"))
    if not fichiers or fichiers[-1] == fichier_referentiel:
        return
    with open(fichiers[-1], encoding="utf-8-sig") as f:
        referentiel = {row["stationcode"]: row for row in csv.DictReader(f, delimiter=";")}
    fichier_referentiel = fichiers[-1]
    print(f"référentiel chargé : {fichier_referentiel} ({len(referentiel)} stations)", flush=True)


def enrichir(msg):
    types = {}
    for t in msg.get("num_bikes_available_types") or []:
        types.update(t)
    ref = referentiel.get(str(msg.get("stationCode")))
    if ref is None:
        sans_referentiel.inc()
        ref = {}
    return {
        "station_id": msg.get("station_id"),
        "station_code": msg.get("stationCode"),
        "date_collecte": msg.get("date_collecte"),
        "last_reported": msg.get("last_reported"),
        "velos_mecaniques": types.get("mechanical"),
        "velos_electriques": types.get("ebike"),
        "bornes_libres": msg.get("num_docks_available"),
        "is_installed": msg.get("is_installed"),
        "is_renting": msg.get("is_renting"),
        "is_returning": msg.get("is_returning"),
        # champs venant de la source 2
        "nom": ref.get("name"),
        "capacite": ref.get("capacity"),
        "coordonnees_geo": ref.get("coordonnees_geo"),
        "commune": ref.get("nom_arrondissement_communes"),
        "code_insee": ref.get("code_insee_commune"),
    }


def ecrire(zone, lignes):
    now = datetime.now(timezone.utc)
    dossier = f"{LAKE}/{zone}/date={now:%Y-%m-%d}"
    os.makedirs(dossier, exist_ok=True)
    chemin = f"{dossier}/velib_{now:%H%M%S}.jsonl"
    with open(chemin + ".tmp", "w") as f:
        for l in lignes:
            f.write(json.dumps(l, ensure_ascii=False) + "\n")
    os.replace(chemin + ".tmp", chemin)


def main():
    start_http_server(8000)
    raw_lake.set(compter_lignes(f"{LAKE}/raw/api/date=*/*.jsonl"))
    agg_lake.set(compter_lignes(f"{LAKE}/aggregated/date=*/*.jsonl"))

    # pas d'agrégation possible sans référentiel, on attend le premier fichier de la source 2
    while not referentiel:
        charger_referentiel()
        if not referentiel:
            print("en attente du référentiel source 2...", flush=True)
            time.sleep(10)

    consumer = Consumer({
        "bootstrap.servers": os.getenv("KAFKA_BOOTSTRAP", "kafka:9092"),
        "group.id": "aggregator",
        "auto.offset.reset": "earliest",
        "enable.auto.commit": False,
    })
    consumer.subscribe([TOPIC])

    while True:
        charger_referentiel()
        bruts = []
        debut = time.time()
        while time.time() - debut < BATCH_SECONDES:
            for m in consumer.consume(num_messages=500, timeout=1):
                if m.error():
                    print("erreur kafka :", m.error(), flush=True)
                    continue
                bruts.append(json.loads(m.value()))
        if not bruts:
            continue

        ecrire("raw/api", bruts)
        ecrire("aggregated", [enrichir(m) for m in bruts])
        consumer.commit(asynchronous=False)

        messages_lus.inc(len(bruts))
        raw_lake.inc(len(bruts))
        agg_lake.inc(len(bruts))
        print(f"{len(bruts)} messages écrits dans le data lake", flush=True)


if __name__ == "__main__":
    main()
