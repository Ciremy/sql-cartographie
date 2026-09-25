"""Producer : interroge l'API GBFS Vélib' et envoie chaque station dans Kafka."""
import json
import os
import time
from datetime import datetime, timezone

import requests
from confluent_kafka import Producer
from prometheus_client import Counter, Gauge, start_http_server

API_URL = os.getenv("VELIB_API_URL", "https://velib-metropole-opendata.smovengo.cloud/opendata/Velib_Metropole/station_status.json")
TOPIC = os.getenv("KAFKA_TOPIC", "velib-status")
INTERVALLE = int(os.getenv("POLL_INTERVAL", "60"))

messages_envoyes = Counter("velib_producer_messages_total", "Messages envoyés dans Kafka")
erreurs_api = Counter("velib_producer_api_errors_total", "Appels API en échec")
dernier_appel = Gauge("velib_producer_last_success_timestamp", "Date du dernier appel API réussi")

producer = Producer({"bootstrap.servers": os.getenv("KAFKA_BOOTSTRAP", "kafka:9092")})


def collecter():
    rep = requests.get(API_URL, timeout=30)
    rep.raise_for_status()
    stations = rep.json()["data"]["stations"]

    # même date de collecte pour toutes les stations d'un appel
    date_collecte = datetime.now(timezone.utc).isoformat(timespec="seconds")
    for st in stations:
        st["date_collecte"] = date_collecte
        producer.produce(TOPIC, key=str(st["station_id"]), value=json.dumps(st))
        producer.poll(0)
    producer.flush(30)

    messages_envoyes.inc(len(stations))
    dernier_appel.set_to_current_time()
    print(f"{date_collecte} : {len(stations)} stations envoyées dans {TOPIC}", flush=True)


if __name__ == "__main__":
    start_http_server(8000)
    while True:
        try:
            collecter()
        except Exception as e:
            erreurs_api.inc()
            print("erreur collecte :", e, flush=True)
        time.sleep(INTERVALLE)
