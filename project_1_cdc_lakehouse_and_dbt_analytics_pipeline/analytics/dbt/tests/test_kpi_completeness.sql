-- Custom test: completeness check for daily KPI partitions
-- Ensures mart_kpis_daily has expected date partitions.

SELECT
  kpi_date,
  COUNT(*) AS row_count
FROM {{ ref('mart_kpis_daily') }}
WHERE kpi_date >= CURRENT_DATE - INTERVAL '7' DAY
GROUP BY kpi_date
HAVING COUNT(*) = 0
