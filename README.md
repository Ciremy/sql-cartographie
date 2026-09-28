# TP SQL - Vélib'

Fil rouge des TP : la disponibilité des vélos en libre-service Vélib' (≈ 1 500 stations à Paris et en petite couronne), à partir de données ouvertes et réelles.
On part des sources brutes pour arriver à un dashboard alimenté en continu, puis on audite la qualité de ce que le pipeline a produit.

- [TP1 - Audit & cartographie des données (Vélib')](TP1/) : sources, dictionnaire de données, modèle conceptuel et logique, base PostgreSQL
- [TP2 - Pipeline data temps réel & plateforme data](TP2/) : API → Kafka → data lake → PySpark → PostgreSQL → Streamlit, supervisé avec Prometheus / Grafana
- [TP3 - Audit qualité & nettoyage des données](TP3/) : 18 contrôles SQL, correction des anomalies, comparaison avant / après

Chaque dossier a son propre README avec les explications et les commandes pour tout relancer (le TP2 démarre avec un simple `docker compose up -d`).
