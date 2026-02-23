"""Airflow DAG for Bronze/Silver/Gold reconciliation checks."""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator

default_args = {
    "owner": "data-engineering",
    "depends_on_past": False,
    "email_on_failure": True,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

dag = DAG(
    "reconciliation",
    default_args=default_args,
    description="Reconciliation: Bronze/Silver/Gold consistency checks",
    schedule_interval=timedelta(hours=6),  # Run every 6 hours
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["reconciliation", "data-quality"],
)

run_reconciliation = BashOperator(
    task_id="run_reconciliation",
    bash_command="/app/scripts/run_reconciliation.sh",
    dag=dag,
)

run_reconciliation
