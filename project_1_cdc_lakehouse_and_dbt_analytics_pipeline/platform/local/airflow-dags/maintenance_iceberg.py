"""
Airflow DAG: Iceberg maintenance (compact, expire snapshots, remove orphans).
Runs daily to keep Iceberg tables healthy (small file compaction, snapshot expiration).
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator

default_args = {
    "owner": "data-engineering",
    "depends_on_past": False,
    "email_on_failure": True,
    "email_on_retry": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

dag = DAG(
    "maintenance_iceberg",
    default_args=default_args,
    description="Daily Iceberg maintenance: compact, expire snapshots, remove orphans",
    schedule_interval=timedelta(days=1),
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["maintenance", "iceberg"],
)

# Compact data files (rewrite small files)
compact_bronze = BashOperator(
    task_id="compact_bronze_raw_cdc",
    bash_command="""
    spark-sql --master local[*] \
      --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2 \
      -e "CALL iceberg.system.rewrite_data_files('iceberg.bronze.raw_cdc', REWRITE_ALL);"
    """,
    dag=dag,
)

compact_silver_users = BashOperator(
    task_id="compact_silver_users",
    bash_command="""
    spark-sql --master local[*] \
      --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2 \
      -e "CALL iceberg.system.rewrite_data_files('iceberg.silver.users', REWRITE_ALL);"
    """,
    dag=dag,
)

compact_silver_orders = BashOperator(
    task_id="compact_silver_orders",
    bash_command="""
    spark-sql --master local[*] \
      --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2 \
      -e "CALL iceberg.system.rewrite_data_files('iceberg.silver.orders', REWRITE_ALL);"
    """,
    dag=dag,
)

compact_silver_payments = BashOperator(
    task_id="compact_silver_payments",
    bash_command="""
    spark-sql --master local[*] \
      --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2 \
      -e "CALL iceberg.system.rewrite_data_files('iceberg.silver.payments', REWRITE_ALL);"
    """,
    dag=dag,
)

# Expire snapshots (keep last 7 days)
expire_snapshots = BashOperator(
    task_id="expire_snapshots",
    bash_command="""
    spark-sql --master local[*] \
      --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2 \
      -e "
      CALL iceberg.system.expire_snapshots('iceberg.bronze.raw_cdc', TIMESTAMP '$(date -u -d "7 days ago" +%Y-%m-%dT%H:%M:%S)');
      CALL iceberg.system.expire_snapshots('iceberg.silver.users', TIMESTAMP '$(date -u -d "7 days ago" +%Y-%m-%dT%H:%M:%S)');
      CALL iceberg.system.expire_snapshots('iceberg.silver.orders', TIMESTAMP '$(date -u -d "7 days ago" +%Y-%m-%dT%H:%M:%S)');
      CALL iceberg.system.expire_snapshots('iceberg.silver.payments', TIMESTAMP '$(date -u -d "7 days ago" +%Y-%m-%dT%H:%M:%S)');
      "
    """,
    dag=dag,
)

# Remove orphan files
remove_orphans = BashOperator(
    task_id="remove_orphan_files",
    bash_command="""
    spark-sql --master local[*] \
      --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.4.2 \
      -e "
      CALL iceberg.system.remove_orphan_files('iceberg.bronze.raw_cdc');
      CALL iceberg.system.remove_orphan_files('iceberg.silver.users');
      CALL iceberg.system.remove_orphan_files('iceberg.silver.orders');
      CALL iceberg.system.remove_orphan_files('iceberg.silver.payments');
      "
    """,
    dag=dag,
)

# Task dependencies
[compact_bronze, compact_silver_users, compact_silver_orders, compact_silver_payments] >> expire_snapshots >> remove_orphans
