# Bronze ingest: Spark 3.5, Iceberg, Kafka; PyYAML for contracts.
FROM apache/spark:3.5.0-python3

USER root
RUN pip install --no-cache-dir PyYAML>=6.0 pandas pyarrow>=4.0.0

USER ${spark_uid}
WORKDIR /app

ENV PROJECT_ROOT=/app

# Kafka, S3, catalog: set via env (BronzeConfig.from_env).
ENTRYPOINT []
CMD ["/opt/spark/bin/spark-submit", "--master", "local[*]", "--packages", "org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2,org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0,org.apache.hadoop:hadoop-aws:3.3.4", "/app/streaming/spark/bronze_ingest/ingest_raw_cdc.py"]
