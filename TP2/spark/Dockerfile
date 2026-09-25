FROM apache/spark:3.5.3-python3

USER root
RUN pip install --no-cache-dir psycopg2-binary==2.9.10
# driver JDBC pour écrire dans postgres
ADD https://jdbc.postgresql.org/download/postgresql-42.7.4.jar /opt/spark/jars/postgresql-42.7.4.jar
RUN chmod 644 /opt/spark/jars/postgresql-42.7.4.jar

WORKDIR /app
COPY job.py run.sh ./
CMD ["/app/run.sh"]
