"""
Reverse ETL: Publish user segments to Kafka
Keyed by user_id to preserve per-user ordering
"""

from kafka import KafkaProducer
from kafka.errors import KafkaError
import json
from datetime import date, datetime
from typing import List, Dict, Any, Optional
import os
import logging
import uuid

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class KafkaSegmentPublisher:
    """Publishes user segments to Kafka with keyed ordering"""
    
    def __init__(
        self,
        bootstrap_servers: str = None,
        topic: str = None
    ):
        self.bootstrap_servers = bootstrap_servers or os.getenv(
            "KAFKA_BOOTSTRAP_SERVERS", 
            "localhost:9092"
        )
        self.topic = topic or os.getenv("SEGMENT_TOPIC", "segment_updates")
        self.producer = None
    
    def get_producer(self):
        """Get or create Kafka producer"""
        if self.producer is None:
            self.producer = KafkaProducer(
                bootstrap_servers=self.bootstrap_servers.split(","),
                value_serializer=lambda v: json.dumps(v, default=str).encode('utf-8'),
                key_serializer=lambda k: str(k).encode('utf-8') if k else None,
                acks='all',  # Wait for all replicas
                retries=3,
                max_in_flight_requests_per_connection=1,  # Preserve ordering
                enable_idempotence=True  # Exactly-once semantics
            )
        return self.producer
    
    def publish_segments(
        self,
        segments: List[Dict[str, Any]],
        source_run_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Publish user segments to Kafka
        
        Args:
            segments: List of segment dicts
            source_run_id: Unique identifier for this run
        
        Returns:
            Dict with stats: published_count, failed_count
        """
        if not segments:
            return {"published_count": 0, "failed_count": 0, "total": 0}
        
        run_id = source_run_id or str(uuid.uuid4())
        producer = self.get_producer()
        
        published_count = 0
        failed_count = 0
        
        for seg in segments:
            try:
                # Key by user_id to preserve per-user ordering
                key = str(seg["user_id"])
                
                # Message payload
                message = {
                    "user_id": str(seg["user_id"]),
                    "segment_date": str(seg.get("segment_date", date.today())),
                    "value_segment": seg.get("value_segment"),
                    "activity_segment": seg.get("activity_segment"),
                    "last_90d_gmv": float(seg.get("last_90d_gmv", 0)),
                    "is_churn_risk": int(seg.get("is_churn_risk", 0)),
                    "is_active": int(seg.get("is_active", 0)),
                    "source_run_id": run_id,
                    "published_at": datetime.utcnow().isoformat()
                }
                
                # Send message (async)
                future = producer.send(
                    self.topic,
                    key=key,
                    value=message
                )
                
                # Wait for delivery confirmation
                record_metadata = future.get(timeout=10)
                
                published_count += 1
                
                if published_count % 100 == 0:
                    logger.info(f"Published {published_count} segments...")
                    
            except KafkaError as e:
                logger.error(f"Failed to publish segment for user {seg.get('user_id')}: {str(e)}")
                failed_count += 1
            except Exception as e:
                logger.error(f"Unexpected error publishing segment: {str(e)}")
                failed_count += 1
        
        # Flush remaining messages
        producer.flush()
        
        logger.info(
            f"Published {published_count} segments, failed: {failed_count}, "
            f"run_id: {run_id}"
        )
        
        return {
            "published_count": published_count,
            "failed_count": failed_count,
            "total": len(segments),
            "source_run_id": run_id,
            "topic": self.topic
        }
    
    def close(self):
        """Close producer"""
        if self.producer:
            self.producer.close()
            self.producer = None


def main():
    """Example usage"""
    import trino
    
    # Example: Fetch segments from Trino and publish to Kafka
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
          AND value_segment = 'high_value'
        LIMIT 100
    """)
    
    columns = [desc[0] for desc in cursor.description]
    rows = cursor.fetchall()
    segments = [dict(zip(columns, row)) for row in rows]
    cursor.close()
    trino_conn.close()
    
    # Publish to Kafka
    publisher = KafkaSegmentPublisher()
    try:
        result = publisher.publish_segments(segments)
        print(f"Publish result: {result}")
    finally:
        publisher.close()


if __name__ == "__main__":
    main()
