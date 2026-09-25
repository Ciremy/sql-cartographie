# Data Lake

Dossier monté dans les conteneurs `source2`, `aggregator` et `spark` (en `/datalake`). Les fichiers sont dans `data/`, qui n'est pas versionné.

```
data/
├── raw/
│   ├── api/date=AAAA-MM-JJ/velib_HHMMSS.jsonl        messages Kafka bruts, 1 fichier par minute
│   └── source2/date=AAAA-MM-JJ/stations_HHMMSS.csv   CSV Paris Data tel que téléchargé
├── aggregated/date=AAAA-MM-JJ/velib_HHMMSS.jsonl     messages API + infos station de la source 2
├── clean/releves/date=AAAA-MM-JJ/*.parquet           sortie de Spark (données propres)
└── _spark/fichiers_traites.txt                       fichiers déjà traités par Spark
```

- On ne modifie jamais `raw/` : si le traitement change, on peut tout rejouer depuis les données brutes.
- Les fichiers sont d'abord écrits en `.tmp` puis renommés : Spark ne tombe jamais sur un fichier à moitié écrit.
- Les heures dans les noms de fichiers sont en UTC.
