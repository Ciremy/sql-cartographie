"""Source 2 : téléchargement du référentiel des stations (export CSV Paris Data).

On récupère pour chaque station son nom, sa capacité, sa position et sa commune.
Le fichier est déposé tel quel dans le Data Lake (zone raw/source2).
"""
import os
import time
from datetime import datetime, timezone

import requests
from prometheus_client import Counter, Gauge, start_http_server

CSV_URL = os.getenv(
    "SOURCE2_URL",
    "https://parisdata.opendatasoft.com/api/explore/v2.1/catalog/datasets/velib-disponibilite-en-temps-reel/exports/csv"
    "?select=stationcode,name,capacity,coordonnees_geo,nom_arrondissement_communes,code_insee_commune",
)
LAKE = os.getenv("DATALAKE_PATH", "/datalake")
INTERVALLE = int(os.getenv("FETCH_INTERVAL", "3600"))

telechargements = Counter("velib_source2_downloads_total", "Téléchargements du référentiel réussis")
erreurs = Counter("velib_source2_errors_total", "Téléchargements en échec")
nb_stations = Gauge("velib_source2_stations", "Nombre de stations dans le dernier fichier")


def telecharger():
    rep = requests.get(CSV_URL, timeout=60)
    rep.raise_for_status()

    now = datetime.now(timezone.utc)
    dossier = f"{LAKE}/raw/source2/date={now:%Y-%m-%d}"
    os.makedirs(dossier, exist_ok=True)
    chemin = f"{dossier}/stations_{now:%H%M%S}.csv"

    # écriture dans un .tmp puis renommage pour ne jamais laisser un fichier à moitié écrit
    with open(chemin + ".tmp", "wb") as f:
        f.write(rep.content)
    os.replace(chemin + ".tmp", chemin)

    lignes = rep.content.decode("utf-8-sig").count("\n") - 1
    nb_stations.set(lignes)
    telechargements.inc()
    print(f"référentiel enregistré : {chemin} ({lignes} stations)", flush=True)


if __name__ == "__main__":
    start_http_server(8000)
    while True:
        try:
            telecharger()
        except Exception as e:
            erreurs.inc()
            print("erreur téléchargement :", e, flush=True)
            time.sleep(60)
            continue
        time.sleep(INTERVALLE)
