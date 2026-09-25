"""Dashboard Vélib' (Streamlit) branché sur PostgreSQL."""
import os

import numpy as np
import pandas as pd
import requests
import streamlit as st
from sqlalchemy import create_engine

engine = create_engine(
    f"postgresql+psycopg2://{os.getenv('POSTGRES_USER', 'velib')}:{os.getenv('POSTGRES_PASSWORD', 'velib')}"
    f"@{os.getenv('POSTGRES_HOST', 'postgres')}:5432/{os.getenv('POSTGRES_DB', 'velib')}"
)

st.set_page_config(page_title="Vélib' - disponibilité", layout="wide")
st.title("Disponibilité des Vélib'")


@st.cache_data(ttl=60)
def requete(sql):
    return pd.read_sql(sql, engine)


derniere = requete("SELECT MAX(date_collecte) AS d FROM releve")["d"][0]
if derniere is None:
    st.info("Pas encore de données dans PostgreSQL, le pipeline est en train de démarrer (quelques minutes).")
    st.stop()

st.caption(f"Dernière collecte chargée : {derniere:%d/%m/%Y %H:%M} (UTC)")

# état de toutes les stations à la dernière collecte
etat = requete("""
    SELECT * FROM v_releve
    WHERE date_collecte = (SELECT MAX(date_collecte) FROM releve)
""")

meca = int(etat["velos_mecaniques"].sum())
elec = int(etat["velos_electriques"].sum())
c1, c2, c3, c4, c5 = st.columns(5)
c1.metric("Stations", len(etat))
c2.metric("Vélos disponibles", meca + elec)
c3.metric("dont électriques", f"{elec} ({elec / max(meca + elec, 1):.0%})")
c4.metric("Stations vides", int(((etat["velos_mecaniques"] + etat["velos_electriques"]) == 0).sum()))
c5.metric("Stations pleines", int((etat["bornes_libres"] == 0).sum()))

st.subheader("Trouver un Vélib' près d'une adresse")
col_adresse, col_rayon = st.columns([3, 1])
adresse = col_adresse.text_input("Adresse", placeholder="ex : 10 rue de Rivoli, Paris")
rayon = col_rayon.slider("Rayon (m)", 100, 2000, 500, step=100)

if adresse:
    # géocodage avec l'API de la Géoplateforme IGN (ex api-adresse.data.gouv.fr)
    try:
        rep = requests.get("https://data.geopf.fr/geocodage/search", params={"q": adresse, "limit": 1}, timeout=10)
        resultats = rep.json().get("features", [])
    except requests.RequestException:
        resultats = None

    if resultats is None:
        st.error("Le service de géocodage ne répond pas, réessaie dans un moment.")
    elif not resultats:
        st.warning("Adresse introuvable.")
    else:
        lon, lat = resultats[0]["geometry"]["coordinates"]
        st.caption(f"Adresse trouvée : {resultats[0]['properties']['label']}")

        # distance à vol d'oiseau (formule de haversine)
        lat1, lon1 = np.radians(lat), np.radians(lon)
        lat2, lon2 = np.radians(etat["latitude"]), np.radians(etat["longitude"])
        a = np.sin((lat2 - lat1) / 2) ** 2 + np.cos(lat1) * np.cos(lat2) * np.sin((lon2 - lon1) / 2) ** 2
        proches = etat.assign(distance_m=(2 * 6371000 * np.arcsin(np.sqrt(a))).round())
        proches = proches[(proches["distance_m"] <= rayon) & proches["est_installee"]].sort_values("distance_m")

        if proches.empty:
            st.info(f"Aucune station dans un rayon de {rayon} m.")
        else:
            m1, m2, m3 = st.columns(3)
            m1.metric("Stations", len(proches))
            m2.metric("Vélos mécaniques", int(proches["velos_mecaniques"].sum()))
            m3.metric("Vélos électriques", int(proches["velos_electriques"].sum()))

            # l'adresse en bleu, les stations en vert (vélos dispo) ou rouge (vide)
            points = pd.concat([
                pd.DataFrame({"latitude": [lat], "longitude": [lon], "couleur": ["#1f77b4"], "taille": [25]}),
                pd.DataFrame({
                    "latitude": proches["latitude"], "longitude": proches["longitude"],
                    "couleur": np.where(proches["velos_mecaniques"] + proches["velos_electriques"] > 0, "#2ca02c", "#d62728"),
                    "taille": 15,
                }),
            ])
            st.map(points, latitude="latitude", longitude="longitude", color="couleur", size="taille",
                   zoom=15 if rayon <= 500 else 14 if rayon <= 1000 else 13)

            st.dataframe(
                proches[["station", "distance_m", "velos_mecaniques", "velos_electriques", "bornes_libres"]]
                .rename(columns={"distance_m": "distance (m)", "velos_mecaniques": "mécaniques",
                                 "velos_electriques": "électriques", "bornes_libres": "places libres"}),
                use_container_width=True, hide_index=True,
            )

st.subheader("Évolution du nombre de vélos disponibles (dernières 24 h)")
evolution = requete("""
    SELECT date_collecte, SUM(velos_mecaniques) AS mecaniques, SUM(velos_electriques) AS electriques
    FROM v_releve
    WHERE date_collecte > now() - interval '24 hours'
    GROUP BY date_collecte ORDER BY date_collecte
""")
st.line_chart(evolution.set_index("date_collecte"))

gauche, droite = st.columns(2)

with gauche:
    st.subheader("Vélos disponibles par commune (top 15, hors Paris)")
    communes = (etat[etat["commune"] != "Paris"].groupby("commune")[["velos_mecaniques", "velos_electriques"]].sum()
                .assign(total=lambda d: d.sum(axis=1)).sort_values("total", ascending=False).head(15))
    st.bar_chart(communes[["velos_mecaniques", "velos_electriques"]])

with droite:
    st.subheader("Taux de remplissage moyen par commune")
    etat["remplissage"] = (etat["velos_mecaniques"] + etat["velos_electriques"]) / etat["capacite"]
    taux = (etat.groupby("commune").agg(stations=("station", "count"), remplissage=("remplissage", "mean"))
            .query("stations >= 5").sort_values("remplissage"))
    taux["remplissage"] = (taux["remplissage"] * 100).round(1)
    st.dataframe(taux, use_container_width=True, height=400)

st.subheader("Carte des stations")
st.caption("Taille du point = nombre de vélos disponibles")
carte = etat.assign(taille=(etat["velos_mecaniques"] + etat["velos_electriques"]) * 8 + 10)
st.map(carte, latitude="latitude", longitude="longitude", size="taille")

st.subheader("Stations vides en ce moment")
vides = etat[(etat["velos_mecaniques"] + etat["velos_electriques"]) == 0]
st.dataframe(vides[["code_station", "station", "commune", "capacite", "bornes_libres"]],
             use_container_width=True, hide_index=True)
