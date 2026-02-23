"""Airflow DAG for backfill of Bronze to Silver/Gold."""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator

default_args = {
    "owner": "data-engineering",
    "depends_on_past": False,
    "email_on_failure": True,
    "retries": 1,
    "retry_delay": timedelta(minutes=10),
}

dag = DAG(
    "backfill",
    default_args=default_args,
    description="Backfill: Reprocess Bronze -> Silver/Gold for a time window",
    schedule_interval=None,  # Manual trigger only
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["backfill", "replay"],
)

# Backfill Silver
backfill_silver = BashOperator(
    task_id="backfill_silver",
    bash_command="""
    spark-submit --master local[*] \
      --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2 \
      /app/streaming/spark/silver_merge/merge_silver.py
    """,
    dag=dag,
)

# Backfill Gold (dbt run)
backfill_gold = BashOperator(
    task_id="backfill_gold",
    bash_command="cd /app/analytics/dbt && dbt run",
    dag=dag,
)

backfill_silver >> backfill_gold
