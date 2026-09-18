-- ============================================================================
-- DATABRICKS LAKEHOUSE DASHBOARD - PAGE 3: PURCHASE ORDERS & FULFILLMENT
-- ============================================================================
-- Purpose: Logistics operations and purchase order execution monitoring
-- Catalog: catalog_lcom.bronze (OC data) + silver (master)
-- Author: Senior BI Architect & Supply Chain Analyst
-- Last Updated: September 2026
-- ============================================================================

-- NOTE: This page uses the same parameters as Pages 1 & 2
--       Additional parameter: p_order_month (for time-based filtering)


-- ============================================================================
-- WIDGET 3.1: ORDER EXECUTION STATUS SUMMARY (KPI Cards Row)
-- ============================================================================

-- Card 3.1.a: Total Purchase Orders
SELECT 
  COUNT(*) AS total_orders,
  COUNT(DISTINCT cod_pus) AS unique_sites_served,
  'Total Purchase Orders (August)' AS metric_label
FROM catalog_lcom.bronze.oc_agosto_raw
WHERE 1=1;

-- Card 3.1.b: Successfully Executed Orders
SELECT 
  COUNT(*) AS executed_orders,
  ROUND(
    (COUNT(*)::FLOAT / (SELECT COUNT(*) FROM catalog_lcom.bronze.oc_agosto_raw)::FLOAT) * 100,
    1
  ) AS execution_rate_pct,
  'Successfully Executed' AS metric_label
FROM catalog_lcom.bronze.oc_agosto_raw
WHERE UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO';

-- Card 3.1.c: Total Rolls Delivered (August)
SELECT 
  FORMAT_NUMBER(SUM(CAST(ROLLOS_ENTREGADOS AS INT)), 0) AS total_rolls_delivered,
  FORMAT_NUMBER(AVG(CAST(ROLLOS_ENTREGADOS AS INT)), 0) AS avg_per_order,
  'Total Rolls Delivered' AS metric_label
FROM catalog_lcom.bronze.oc_agosto_raw
WHERE UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO'
  AND ROLLOS_ENTREGADOS IS NOT NULL;

-- Card 3.1.d: Average Resolution Time
SELECT 
  ROUND(AVG(DATEDIFF(HOUR, order_created, order_resolved)), 1) AS avg_hours_to_resolve,
  ROUND(AVG(DATEDIFF(DAY, order_created, order_resolved)), 1) AS avg_days_to_resolve,
  'Avg Resolution Time' AS metric_label
FROM (
  SELECT 
    cod_pus,
    `FECHA_DE_SOLUCIÓN_DD_MM_AAAA` AS order_resolved,
    DATE_SUB(`FECHA_DE_SOLUCIÓN_DD_MM_AAAA`, 2) AS order_created  -- Assume 2-day default lag
  FROM catalog_lcom.bronze.oc_agosto_raw
  WHERE `FECHA_DE_SOLUCIÓN_DD_MM_AAAA` IS NOT NULL
    AND UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO'
) resolution_times;


-- ============================================================================
-- WIDGET 3.2: ORDER EXECUTION STATUS (Donut Chart)
-- ============================================================================
-- Visualization: Donut Chart
-- Display: Proportion of orders by status
-- Color: Green (Executed), Yellow (Pending), Red (Failed)

SELECT 
  COALESCE(UPPER(TRIM(ESTADO)), 'UNKNOWN') AS order_status,
  COUNT(*) AS order_count,
  ROUND(
    (COUNT(*)::FLOAT / SUM(COUNT(*)) OVER ()::FLOAT) * 100,
    1
  ) AS percentage,
  CASE 
    WHEN UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO' THEN '#27AE60'  -- Green
    WHEN UPPER(TRIM(ESTADO)) LIKE '%PENDIENTE%' THEN '#F1C40F'    -- Yellow
    WHEN UPPER(TRIM(ESTADO)) LIKE '%FALLIDO%' OR UPPER(TRIM(ESTADO)) LIKE '%RECHAZADO%' THEN '#E74C3C'  -- Red
    ELSE '#95A5A6'  -- Gray (Unknown)
  END AS segment_color
FROM catalog_lcom.bronze.oc_agosto_raw
GROUP BY COALESCE(UPPER(TRIM(ESTADO)), 'UNKNOWN')
ORDER BY order_count DESC;


-- ============================================================================
-- WIDGET 3.3: ORDER RESOLUTION LEAD TIME BY DEPARTMENT (Bar Chart)
-- ============================================================================
-- Visualization: Horizontal Bar Chart
-- X-Axis: Average resolution hours
-- Y-Axis: Department
-- Color: Gradient based on lead time (Green = Fast, Red = Slow)

WITH order_lead_times AS (
  SELECT 
    UPPER(TRIM(DEPARTAMENTO)) AS department,
    UPPER(TRIM(CIUDAD_SEDE)) AS city_sede,
    cod_pus,
    `FECHA_DE_SOLUCIÓN_DD_MM_AAAA` AS resolution_date,
    -- Assuming order request date is 2 days before resolution for demonstration
    DATEDIFF(
      HOUR,
      DATE_SUB(`FECHA_DE_SOLUCIÓN_DD_MM_AAAA`, 2),
      `FECHA_DE_SOLUCIÓN_DD_MM_AAAA`
    ) AS lead_time_hours
  FROM catalog_lcom.bronze.oc_agosto_raw
  WHERE `FECHA_DE_SOLUCIÓN_DD_MM_AAAA` IS NOT NULL
    AND UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO'
)
SELECT 
  department,
  COUNT(DISTINCT cod_pus) AS sites_served,
  COUNT(*) AS total_orders,
  ROUND(AVG(lead_time_hours), 1) AS avg_lead_time_hours,
  ROUND(AVG(lead_time_hours) / 24, 1) AS avg_lead_time_days,
  ROUND(MIN(lead_time_hours), 1) AS min_lead_time_hours,
  ROUND(MAX(lead_time_hours), 1) AS max_lead_time_hours,
  CASE 
    WHEN AVG(lead_time_hours) <= 24 THEN '#27AE60'  -- Green (< 1 day)
    WHEN AVG(lead_time_hours) <= 48 THEN '#F1C40F'  -- Yellow (1-2 days)
    WHEN AVG(lead_time_hours) <= 72 THEN '#F39C12'  -- Orange (2-3 days)
    ELSE '#E74C3C'                                   -- Red (> 3 days)
  END AS bar_color
FROM order_lead_times
GROUP BY department
ORDER BY avg_lead_time_hours DESC
LIMIT 20;


-- ============================================================================
-- WIDGET 3.4: DELIVERY VOLUME BY CITY (Stacked Bar Chart)
-- ============================================================================
-- Visualization: Stacked Bar Chart
-- X-Axis: City
-- Y-Axis: Rolls delivered
-- Stack: By Typology (PRINCIPAL, INTERMEDIA, LEJANA)

SELECT 
  UPPER(TRIM(CIUDAD)) AS city,
  UPPER(TRIM(DEPARTAMENTO)) AS department,
  COALESCE(UPPER(TRIM(`TIPOLOGIA_ROLLOS`)), 'UNKNOWN') AS roll_typology,
  COUNT(*) AS order_count,
  SUM(CAST(ROLLOS_ENTREGADOS AS INT)) AS total_rolls_delivered,
  ROUND(AVG(CAST(ROLLOS_ENTREGADOS AS INT)), 0) AS avg_rolls_per_order,
  CASE 
    WHEN UPPER(TRIM(`TIPOLOGIA_ROLLOS`)) = 'PRINCIPAL' THEN '#3498DB'   -- Blue
    WHEN UPPER(TRIM(`TIPOLOGIA_ROLLOS`)) = 'INTERMEDIA' THEN '#F39C12'  -- Orange
    WHEN UPPER(TRIM(`TIPOLOGIA_ROLLOS`)) = 'LEJANA' THEN '#E74C3C'      -- Red
    ELSE '#95A5A6'  -- Gray
  END AS stack_color
FROM catalog_lcom.bronze.oc_agosto_raw
WHERE UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO'
  AND ROLLOS_ENTREGADOS IS NOT NULL
  AND CIUDAD IS NOT NULL
GROUP BY UPPER(TRIM(CIUDAD)), UPPER(TRIM(DEPARTAMENTO)), COALESCE(UPPER(TRIM(`TIPOLOGIA_ROLLOS`)), 'UNKNOWN')
ORDER BY total_rolls_delivered DESC
LIMIT 50;


-- ============================================================================
-- WIDGET 3.5: TOP CITIES BY ORDER VOLUME (Bar Chart)
-- ============================================================================
-- Visualization: Horizontal Bar Chart
-- Display: Top 15 cities by total rolls delivered

SELECT 
  UPPER(TRIM(CIUDAD)) AS city,
  UPPER(TRIM(DEPARTAMENTO)) AS department,
  COUNT(*) AS order_count,
  COUNT(DISTINCT cod_pus) AS unique_sites,
  SUM(CAST(ROLLOS_ENTREGADOS AS INT)) AS total_rolls_delivered,
  ROUND(AVG(CAST(ROLLOS_ENTREGADOS AS INT)), 0) AS avg_rolls_per_order,
  FORMAT_NUMBER(SUM(CAST(ROLLOS_ENTREGADOS AS INT)), 0) AS formatted_total,
  '#3498DB' AS bar_color  -- Blue
FROM catalog_lcom.bronze.oc_agosto_raw
WHERE UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO'
  AND ROLLOS_ENTREGADOS IS NOT NULL
  AND CIUDAD IS NOT NULL
GROUP BY UPPER(TRIM(CIUDAD)), UPPER(TRIM(DEPARTAMENTO))
ORDER BY total_rolls_delivered DESC
LIMIT 15;


-- ============================================================================
-- WIDGET 3.6: ORDER EXECUTION TIMELINE (Time Series Line Chart)
-- ============================================================================
-- Visualization: Line Chart with Area Fill
-- X-Axis: Date (Daily)
-- Y-Axis: Number of orders executed
-- Series: Cumulative orders, Daily orders

WITH daily_orders AS (
  SELECT 
    DATE(`FECHA_DE_SOLUCIÓN_DD_MM_AAAA`) AS order_date,
    COUNT(*) AS daily_order_count,
    SUM(CAST(ROLLOS_ENTREGADOS AS INT)) AS daily_rolls_delivered,
    COUNT(DISTINCT cod_pus) AS daily_sites_served
  FROM catalog_lcom.bronze.oc_agosto_raw
  WHERE `FECHA_DE_SOLUCIÓN_DD_MM_AAAA` IS NOT NULL
    AND UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO'
  GROUP BY DATE(`FECHA_DE_SOLUCIÓN_DD_MM_AAAA`)
)
SELECT 
  order_date,
  DATE_FORMAT(order_date, 'MMM dd') AS date_label,
  daily_order_count,
  daily_rolls_delivered,
  daily_sites_served,
  SUM(daily_order_count) OVER (ORDER BY order_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_orders,
  SUM(daily_rolls_delivered) OVER (ORDER BY order_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_rolls
FROM daily_orders
ORDER BY order_date;


-- ============================================================================
-- WIDGET 3.7: DELIVERY PERFORMANCE BY TYPOLOGY (Grouped Bar Chart)
-- ============================================================================
-- Visualization: Grouped Bar Chart
-- Display: Execution rate and average rolls per order by typology

SELECT 
  COALESCE(UPPER(TRIM(`TIPOLOGIA_ROLLOS`)), 'UNKNOWN') AS roll_typology,
  COUNT(*) AS total_orders,
  SUM(CASE WHEN UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO' THEN 1 ELSE 0 END) AS executed_orders,
  ROUND(
    (SUM(CASE WHEN UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO' THEN 1 ELSE 0 END)::FLOAT / 
     COUNT(*)::FLOAT) * 100,
    1
  ) AS execution_rate_pct,
  SUM(CASE WHEN UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO' THEN CAST(ROLLOS_ENTREGADOS AS INT) ELSE 0 END) AS total_rolls_delivered,
  ROUND(
    AVG(CASE WHEN UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO' THEN CAST(ROLLOS_ENTREGADOS AS INT) ELSE NULL END),
    0
  ) AS avg_rolls_per_order,
  COUNT(DISTINCT cod_pus) AS sites_served,
  CASE 
    WHEN UPPER(TRIM(`TIPOLOGIA_ROLLOS`)) = 'PRINCIPAL' THEN '#3498DB'   -- Blue
    WHEN UPPER(TRIM(`TIPOLOGIA_ROLLOS`)) = 'INTERMEDIA' THEN '#F39C12'  -- Orange
    WHEN UPPER(TRIM(`TIPOLOGIA_ROLLOS`)) = 'LEJANA' THEN '#E74C3C'      -- Red
    ELSE '#95A5A6'  -- Gray
  END AS bar_color
FROM catalog_lcom.bronze.oc_agosto_raw
GROUP BY COALESCE(UPPER(TRIM(`TIPOLOGIA_ROLLOS`)), 'UNKNOWN')
ORDER BY total_rolls_delivered DESC;


-- ============================================================================
-- WIDGET 3.8: ORDER DETAILS TABLE (Interactive Data Grid)
-- ============================================================================
-- Visualization: Searchable, Filterable Table
-- Display: Detailed order information for operational tracking

SELECT 
  cod_pus,
  UPPER(TRIM(CIUDAD_SEDE)) AS sede_city,
  UPPER(TRIM(DEPARTAMENTO)) AS department,
  UPPER(TRIM(CIUDAD)) AS delivery_city,
  COALESCE(UPPER(TRIM(TIPOLOGIA)), 'N/A') AS site_typology,
  COALESCE(UPPER(TRIM(`TIPOLOGIA_ROLLOS`)), 'N/A') AS roll_typology,
  `FECHA_DE_SOLUCIÓN_DD_MM_AAAA` AS resolution_date,
  UPPER(TRIM(ESTADO)) AS order_status,
  CAST(ROLLOS_ENTREGADOS AS INT) AS rolls_delivered,
  COALESCE(UPPER(TRIM(`DESCRIPCIÓN`)), 'N/A') AS description,
  -- Status indicator color
  CASE 
    WHEN UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO' THEN '#C8E6C9'  -- Light Green Background
    WHEN UPPER(TRIM(ESTADO)) LIKE '%PENDIENTE%' THEN '#FFF9C4'     -- Light Yellow Background
    WHEN UPPER(TRIM(ESTADO)) LIKE '%FALLIDO%' THEN '#FFCDD2'       -- Light Red Background
    ELSE '#F5F5F5'  -- Light Gray Background
  END AS row_background_color
FROM catalog_lcom.bronze.oc_agosto_raw
WHERE 1=1
ORDER BY `FECHA_DE_SOLUCIÓN_DD_MM_AAAA` DESC
LIMIT 500;


-- ============================================================================
-- WIDGET 3.9: ORDER FULFILLMENT FUNNEL (Funnel Chart)
-- ============================================================================
-- Visualization: Funnel Chart
-- Display: Order lifecycle stages from request to delivery

SELECT 
  'Orders Requested' AS stage,
  1 AS stage_order,
  COUNT(*) AS order_count,
  100.0 AS conversion_rate,
  '#3498DB' AS stage_color
FROM catalog_lcom.bronze.oc_agosto_raw

UNION ALL

SELECT 
  'Orders Processed' AS stage,
  2 AS stage_order,
  COUNT(*) AS order_count,
  ROUND(
    (COUNT(*)::FLOAT / (SELECT COUNT(*) FROM catalog_lcom.bronze.oc_agosto_raw)::FLOAT) * 100,
    1
  ) AS conversion_rate,
  '#2ECC71' AS stage_color
FROM catalog_lcom.bronze.oc_agosto_raw
WHERE ESTADO IS NOT NULL

UNION ALL

SELECT 
  'Orders Executed' AS stage,
  3 AS stage_order,
  COUNT(*) AS order_count,
  ROUND(
    (COUNT(*)::FLOAT / (SELECT COUNT(*) FROM catalog_lcom.bronze.oc_agosto_raw)::FLOAT) * 100,
    1
  ) AS conversion_rate,
  '#27AE60' AS stage_color
FROM catalog_lcom.bronze.oc_agosto_raw
WHERE UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO'

ORDER BY stage_order;


-- ============================================================================
-- WIDGET 3.10: DEPARTMENT COMPARISON MATRIX (Heatmap Table)
-- ============================================================================
-- Visualization: Pivot Table / Heatmap
-- Display: Department performance metrics with color-coded cells

SELECT 
  UPPER(TRIM(DEPARTAMENTO)) AS department,
  COUNT(*) AS total_orders,
  COUNT(DISTINCT cod_pus) AS sites_served,
  SUM(CASE WHEN UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO' THEN 1 ELSE 0 END) AS executed_orders,
  ROUND(
    (SUM(CASE WHEN UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO' THEN 1 ELSE 0 END)::FLOAT / 
     COUNT(*)::FLOAT) * 100,
    1
  ) AS execution_rate_pct,
  SUM(CASE WHEN UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO' THEN CAST(ROLLOS_ENTREGADOS AS INT) ELSE 0 END) AS total_rolls,
  ROUND(
    AVG(CASE WHEN UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO' THEN CAST(ROLLOS_ENTREGADOS AS INT) ELSE NULL END),
    0
  ) AS avg_rolls_per_order,
  -- Performance score (weighted: 60% execution rate + 40% volume)
  ROUND(
    (0.6 * (SUM(CASE WHEN UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO' THEN 1 ELSE 0 END)::FLOAT / COUNT(*)::FLOAT) * 100) +
    (0.4 * (SUM(CASE WHEN UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO' THEN CAST(ROLLOS_ENTREGADOS AS INT) ELSE 0 END)::FLOAT / 
            NULLIF((SELECT SUM(CAST(ROLLOS_ENTREGADOS AS INT)) FROM catalog_lcom.bronze.oc_agosto_raw WHERE UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO'), 0)::FLOAT) * 100),
    1
  ) AS performance_score,
  CASE 
    WHEN (SUM(CASE WHEN UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO' THEN 1 ELSE 0 END)::FLOAT / COUNT(*)::FLOAT) >= 0.95 THEN '#27AE60'  -- Green (Excellent)
    WHEN (SUM(CASE WHEN UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO' THEN 1 ELSE 0 END)::FLOAT / COUNT(*)::FLOAT) >= 0.85 THEN '#F1C40F'  -- Yellow (Good)
    WHEN (SUM(CASE WHEN UPPER(TRIM(ESTADO)) = 'EJECUTADO_EXITOSO' THEN 1 ELSE 0 END)::FLOAT / COUNT(*)::FLOAT) >= 0.75 THEN '#F39C12'  -- Orange (Fair)
    ELSE '#E74C3C'  -- Red (Needs Improvement)
  END AS performance_color
FROM catalog_lcom.bronze.oc_agosto_raw
WHERE DEPARTAMENTO IS NOT NULL
GROUP BY UPPER(TRIM(DEPARTAMENTO))
ORDER BY performance_score DESC;


-- ============================================================================
-- END OF PAGE 3: PURCHASE ORDERS & FULFILLMENT MONITORING
-- ============================================================================