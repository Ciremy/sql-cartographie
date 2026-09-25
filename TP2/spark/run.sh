#!/bin/bash
# lance le job toutes les SPARK_INTERVAL secondes
while true; do
  /opt/spark/bin/spark-submit \
    --master "local[2]" \
    --driver-memory 1g \
    --conf spark.sql.session.timeZone=UTC \
    --conf spark.driver.extraJavaOptions=-Duser.timezone=UTC \
    /app/job.py || echo "le job a échoué, nouvel essai au prochain tour"
  sleep "${SPARK_INTERVAL:-120}"
done
