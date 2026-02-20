"""
Metrics API Service
Provides versioned KPI and user segment queries via FastAPI + Trino
"""

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse
from datetime import date, datetime
from typing import Optional, List, Dict, Any
import trino
from functools import lru_cache
import os
import logging
from contextlib import contextmanager

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Metrics API",
    description="Versioned metrics service for KPIs and user segments",
    version="1.0.0"
)

# Configuration
TRINO_HOST = os.getenv("TRINO_HOST", "localhost")
TRINO_PORT = int(os.getenv("TRINO_PORT", "8080"))
TRINO_USER = os.getenv("TRINO_USER", "admin")
TRINO_CATALOG = os.getenv("TRINO_CATALOG", "iceberg")
TRINO_SCHEMA = os.getenv("TRINO_SCHEMA", "mart_mart")  # P1/P2 dbt write to mart_mart

# Cache configuration
CACHE_TTL_SECONDS = int(os.getenv("CACHE_TTL_SECONDS", "300"))  # 5 minutes default
QUERY_TIMEOUT_SECONDS = int(os.getenv("QUERY_TIMEOUT_SECONDS", "30"))


@contextmanager
def get_trino_connection():
    """Context manager for Trino connections"""
    conn = trino.dbapi.connect(
        host=TRINO_HOST,
        port=TRINO_PORT,
        user=TRINO_USER,
        catalog=TRINO_CATALOG,
        schema=TRINO_SCHEMA,
        http_scheme="http"
    )
    try:
        yield conn
    finally:
        conn.close()


def execute_trino_query(query: str, params: Optional[Dict] = None) -> List[Dict[str, Any]]:
    """Execute a Trino query and return results as list of dicts"""
    try:
        with get_trino_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(query, params or {})
            
            # Get column names
            columns = [desc[0] for desc in cursor.description]
            
            # Fetch results
            rows = cursor.fetchall()
            
            # Convert to list of dicts
            results = [dict(zip(columns, row)) for row in rows]
            
            cursor.close()
            return results
    except Exception as e:
        logger.error(f"Trino query failed: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Query execution failed: {str(e)}")


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "metrics-api"}


@app.get("/kpi")
async def get_kpi(
    date: date = Query(..., description="KPI date (YYYY-MM-DD)"),
    version: str = Query("v1", description="Metric version"),
    metrics: Optional[str] = Query(None, description="Comma-separated list of metrics to return")
):
    """
    Get daily KPI metrics
    
    Returns KPIs for a specific date and version.
    Supported metrics: total_gmv, order_count, active_users, payment_count, 
    captured_amount, payment_success_rate, payment_failure_rate
    """
    try:
        # Build query based on version
        if version == "v1":
            table_name = f"{TRINO_SCHEMA}.mart_kpis_daily_v1"
        else:
            # For other versions, query from release log to find table
            raise HTTPException(
                status_code=400, 
                detail=f"Version {version} not supported. Available: v1"
            )
        
        # Base query
        query = f"""
        SELECT 
            kpi_date,
            order_count,
            total_gmv,
            paid_gmv,
            active_users,
            payment_count,
            captured_amount,
            failed_payment_count,
            successful_payment_count,
            payment_success_rate,
            payment_failure_rate,
            _computed_at,
            metric_version
        FROM {table_name}
        WHERE kpi_date = DATE '{date}'
        """
        
        results = execute_trino_query(query)
        
        if not results:
            raise HTTPException(
                status_code=404, 
                detail=f"No KPI data found for date {date} and version {version}"
            )
        
        result = results[0]
        
        # Filter metrics if requested
        if metrics:
            requested_metrics = [m.strip() for m in metrics.split(",")]
            result = {k: v for k, v in result.items() if k in requested_metrics or k in ['kpi_date', 'metric_version']}
        
        return {
            "date": str(result["kpi_date"]),
            "version": result.get("metric_version", version),
            "metrics": {k: v for k, v in result.items() if k not in ["kpi_date", "metric_version", "_computed_at"]},
            "computed_at": str(result.get("_computed_at", ""))
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching KPI: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


@app.get("/kpi/range")
async def get_kpi_range(
    start_date: date = Query(..., description="Start date (YYYY-MM-DD)"),
    end_date: date = Query(..., description="End date (YYYY-MM-DD)"),
    version: str = Query("v1", description="Metric version")
):
    """
    Get KPI metrics for a date range
    """
    try:
        if version == "v1":
            table_name = f"{TRINO_SCHEMA}.mart_kpis_daily_v1"
        else:
            raise HTTPException(
                status_code=400, 
                detail=f"Version {version} not supported. Available: v1"
            )
        
        query = f"""
        SELECT 
            kpi_date,
            order_count,
            total_gmv,
            paid_gmv,
            active_users,
            payment_count,
            captured_amount,
            failed_payment_count,
            successful_payment_count,
            payment_success_rate,
            payment_failure_rate,
            metric_version
        FROM {table_name}
        WHERE kpi_date >= DATE '{start_date}'
          AND kpi_date <= DATE '{end_date}'
        ORDER BY kpi_date
        """
        
        results = execute_trino_query(query)
        
        return {
            "start_date": str(start_date),
            "end_date": str(end_date),
            "version": version,
            "data": results
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching KPI range: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


@app.get("/user_segment")
async def get_user_segment(
    segment: str = Query(..., description="Segment name (high_value, medium_value, low_value, churn_risk, active, dormant)"),
    date: Optional[date] = Query(None, description="Segment date (defaults to latest)"),
    version: str = Query("v1", description="Metric version"),
    limit: int = Query(100, ge=1, le=10000, description="Maximum number of users to return")
):
    """
    Get users in a specific segment
    """
    try:
        table_name = f"{TRINO_SCHEMA}.mart_user_segments"
        
        # Build WHERE clause
        where_clauses = []
        
        if segment in ["high_value", "medium_value", "low_value"]:
            where_clauses.append(f"value_segment = '{segment}'")
        elif segment in ["churn_risk", "active", "dormant"]:
            where_clauses.append(f"activity_segment = '{segment}'")
        else:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid segment: {segment}. Valid: high_value, medium_value, low_value, churn_risk, active, dormant"
            )
        
        if date:
            where_clauses.append(f"segment_date = DATE '{date}'")
        else:
            # Get latest segment_date
            where_clauses.append(f"segment_date = (SELECT MAX(segment_date) FROM {table_name})")
        
        where_clause = " AND ".join(where_clauses)
        
        query = f"""
        SELECT 
            user_id,
            status,
            created_at,
            last_90d_gmv,
            is_churn_risk,
            is_active,
            value_segment,
            activity_segment,
            segment_date,
            _computed_at
        FROM {table_name}
        WHERE {where_clause}
        ORDER BY last_90d_gmv DESC
        LIMIT {limit}
        """
        
        results = execute_trino_query(query)
        
        return {
            "segment": segment,
            "date": str(results[0]["segment_date"]) if results else None,
            "version": version,
            "count": len(results),
            "users": results
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching user segment: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


@app.get("/versions")
async def get_versions():
    """
    Get available metric versions
    """
    try:
        query = f"""
        SELECT DISTINCT
            metric_version,
            MAX(released_at) AS latest_release
        FROM {TRINO_SCHEMA}.metric_release_log
        GROUP BY metric_version
        ORDER BY latest_release DESC
        """
        
        results = execute_trino_query(query)
        
        return {
            "versions": results
        }
        
    except Exception as e:
        logger.warning(f"Could not fetch versions from release log: {str(e)}")
        # Fallback to hardcoded versions
        return {
            "versions": [
                {"metric_version": "v1", "latest_release": None}
            ]
        }


@app.get("/metrics/list")
async def list_metrics(version: str = Query("v1", description="Metric version")):
    """
    List available metrics for a version
    """
    return {
        "version": version,
        "metrics": {
            "kpi": [
                "total_gmv",
                "order_count",
                "active_users",
                "payment_count",
                "captured_amount",
                "payment_success_rate",
                "payment_failure_rate"
            ],
            "segments": [
                "high_value",
                "medium_value",
                "low_value",
                "churn_risk",
                "active",
                "dormant"
            ]
        }
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
