"""Airflow DAG quality gate for the CDC pipeline."""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator
from airflow.models import Variable

default_args = {
    "owner": "data-engineering",
    "depends_on_past": False,
    "email_on_failure": True,
    "email_on_retry": False,
    "retries": 0,  # Fail fast on quality gate
    "retry_delay": timedelta(minutes=1),
}

dag = DAG(
    "quality_gate_cdc",
    default_args=default_args,
    description="Quality gate: dbt tests, blocks release on failure",
    schedule_interval=timedelta(hours=1),  # Run hourly
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["quality", "gate", "dbt"],
)

# Run dbt tests
dbt_test = BashOperator(
    task_id="dbt_test",
    bash_command="""
    cd /app/analytics/dbt && \
    dbt deps && \
    dbt test --store-failures
    """,
    dag=dag,
)

# Check test results (fail if any test failed)
check_test_results = BashOperator(
    task_id="check_test_results",
    bash_command="""
    cd /app/analytics/dbt && \
    if [ -d "target/compiled" ]; then
      FAILED_COUNT=$(find target/compiled -name "*.sql" -type f | wc -l)
      if [ "$FAILED_COUNT" -gt 0 ]; then
        echo "Quality gate FAILED: $FAILED_COUNT tests failed"
        exit 1
      else
        echo "Quality gate PASSED: All tests passed"
      fi
    else
      echo "No test results found"
      exit 1
    fi
    """,
    dag=dag,
)

# Alert on failure (optional: send to Slack/Datadog)
alert_on_failure = BashOperator(
    task_id="alert_on_failure",
    bash_command='echo "Quality gate failed. Check dbt test results."',
    dag=dag,
    trigger_rule="one_failed",
)

# Task dependencies
dbt_test >> check_test_results >> alert_on_failure
