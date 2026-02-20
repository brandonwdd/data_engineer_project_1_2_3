"""
Reverse ETL: Upsert user segments to Postgres
Idempotent upsert with source_run_id tracking
Uses psycopg (v3) for Python 3.13 compatibility on Windows.
"""

import psycopg
from datetime import date, datetime, timezone
from typing import List, Dict, Any, Optional
import os
import logging
import uuid

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class PostgresSegmentUpserter:
    """Handles idempotent upsert of user segments to Postgres"""
    
    def __init__(
        self,
        host: str = None,
        port: int = None,
        database: str = None,
        user: str = None,
        password: str = None
    ):
        self.host = host or os.getenv("POSTGRES_HOST", "localhost")
        self.port = port or int(os.getenv("POSTGRES_PORT", "5432"))
        self.database = database or os.getenv("POSTGRES_DB", "project1")
        self.user = user or os.getenv("POSTGRES_USER", "postgres")
        self.password = password or os.getenv("POSTGRES_PASSWORD", "postgres")
        self.table_name = os.getenv("SEGMENT_TABLE", "customer_segments")
    
    def get_connection(self):
        """Get Postgres connection"""
        return psycopg.connect(
            host=self.host,
            port=self.port,
            dbname=self.database,
            user=self.user,
            password=self.password
        )
    
    def ensure_table_exists(self):
        """Create customer_segments table if it doesn't exist"""
        create_table_sql = f"""
        CREATE TABLE IF NOT EXISTS {self.table_name} (
            user_id VARCHAR NOT NULL,
            segment_date DATE NOT NULL,
            value_segment VARCHAR,
            activity_segment VARCHAR,
            last_90d_gmv DECIMAL(18, 2),
            is_churn_risk INTEGER,
            is_active INTEGER,
            source_run_id VARCHAR NOT NULL,
            last_updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (user_id, segment_date)
        );
        
        CREATE INDEX IF NOT EXISTS idx_{self.table_name}_segment_date 
        ON {self.table_name}(segment_date);
        
        CREATE INDEX IF NOT EXISTS idx_{self.table_name}_value_segment 
        ON {self.table_name}(value_segment);
        
        CREATE INDEX IF NOT EXISTS idx_{self.table_name}_activity_segment 
        ON {self.table_name}(activity_segment);
        """
        
        conn = self.get_connection()
        try:
            cursor = conn.cursor()
            cursor.execute(create_table_sql)
            conn.commit()
            cursor.close()
            logger.info(f"Table {self.table_name} ensured")
        finally:
            conn.close()
    
    def upsert_segments(
        self,
        segments: List[Dict[str, Any]],
        source_run_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Upsert user segments to Postgres
        
        Args:
            segments: List of segment dicts with keys:
                - user_id
                - segment_date
                - value_segment
                - activity_segment
                - last_90d_gmv
                - is_churn_risk
                - is_active
            source_run_id: Unique identifier for this run
        
        Returns:
            Dict with stats: inserted_count, updated_count, failed_count
        """
        if not segments:
            return {"inserted_count": 0, "updated_count": 0, "failed_count": 0, "total": 0}
        
        run_id = source_run_id or str(uuid.uuid4())
        now = datetime.now(timezone.utc)
        
        self.ensure_table_exists()
        
        conn = self.get_connection()
        inserted_count = 0
        updated_count = 0
        failed_count = 0
        
        try:
            cursor = conn.cursor()
            
            # Prepare data for upsert
            values = []
            for seg in segments:
                try:
                    values.append((
                        str(seg["user_id"]),
                        seg["segment_date"] if isinstance(seg["segment_date"], date) else date.fromisoformat(str(seg["segment_date"])),
                        seg.get("value_segment"),
                        seg.get("activity_segment"),
                        float(seg.get("last_90d_gmv", 0)),
                        int(seg.get("is_churn_risk", 0)),
                        int(seg.get("is_active", 0)),
                        run_id,
                        now
                    ))
                except Exception as e:
                    logger.error(f"Failed to prepare segment {seg.get('user_id')}: {str(e)}")
                    failed_count += 1
            
            if not values:
                return {"inserted_count": 0, "updated_count": 0, "failed_count": failed_count, "total": len(segments)}
            
            # Upsert using ON CONFLICT (psycopg3: use single-row placeholder, executemany)
            upsert_sql = f"""
            INSERT INTO {self.table_name} (
                user_id, segment_date, value_segment, activity_segment,
                last_90d_gmv, is_churn_risk, is_active,
                source_run_id, last_updated_at
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (user_id, segment_date)
            DO UPDATE SET
                value_segment = EXCLUDED.value_segment,
                activity_segment = EXCLUDED.activity_segment,
                last_90d_gmv = EXCLUDED.last_90d_gmv,
                is_churn_risk = EXCLUDED.is_churn_risk,
                is_active = EXCLUDED.is_active,
                source_run_id = EXCLUDED.source_run_id,
                last_updated_at = EXCLUDED.last_updated_at
            """
            cursor.executemany(upsert_sql, values)
            
            # Count inserted vs updated
            # Note: PostgreSQL doesn't directly return this, so we estimate
            # In production, you might use a trigger or check before/after counts
            total_affected = cursor.rowcount
            conn.commit()
            
            # Estimate: if rowcount == len(values), likely all inserts
            # If less, some were updates (though this is approximate)
            # For exact counts, you'd need to check before insert
            updated_count = max(0, total_affected - len(values))
            inserted_count = total_affected - updated_count
            
            cursor.close()
            
            logger.info(
                f"Upserted {total_affected} segments (inserted: {inserted_count}, "
                f"updated: {updated_count}, failed: {failed_count})"
            )
            
            return {
                "inserted_count": inserted_count,
                "updated_count": updated_count,
                "failed_count": failed_count,
                "total": len(segments),
                "source_run_id": run_id
            }
            
        except Exception as e:
            conn.rollback()
            logger.error(f"Failed to upsert segments: {str(e)}")
            raise
        finally:
            conn.close()


def main():
    """Example usage"""
    import trino
    
    # Example: Fetch segments from Trino and upsert to Postgres
    trino_conn = trino.dbapi.connect(
        host=os.getenv("TRINO_HOST", "localhost"),
        port=int(os.getenv("TRINO_PORT", "8080")),
        user=os.getenv("TRINO_USER", "admin"),
        catalog=os.getenv("TRINO_CATALOG", "iceberg"),
        schema=os.getenv("TRINO_SCHEMA", "mart")
    )
    
    cursor = trino_conn.cursor()
    cursor.execute("""
        SELECT 
            user_id,
            segment_date,
            value_segment,
            activity_segment,
            last_90d_gmv,
            is_churn_risk,
            is_active
        FROM mart_mart.mart_user_segments
        WHERE segment_date = CURRENT_DATE
        LIMIT 1000
    """)
    
    columns = [desc[0] for desc in cursor.description]
    rows = cursor.fetchall()
    segments = [dict(zip(columns, row)) for row in rows]
    cursor.close()
    trino_conn.close()
    
    # Upsert to Postgres
    upserter = PostgresSegmentUpserter()
    result = upserter.upsert_segments(segments)
    print(f"Upsert result: {result}")


if __name__ == "__main__":
    main()
