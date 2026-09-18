-- ============================================================================
-- DATABRICKS LAKEHOUSE DASHBOARD - PAGE 1: EXECUTIVE SUPPLY CHAIN OVERVIEW
-- ============================================================================
-- Purpose: High-level KPIs and supply chain health monitoring
-- Catalog: catalog_lcom.supply_chain
-- Author: Senior BI Architect
-- Last Updated: September 2026
-- ============================================================================

-- PREREQUISITES: Set up dashboard parameters (apply to all queries on this page)
-- Parameter 1: p_departamento (Type: Dropdown Multi-Select, Source: Dynamic from query below)
-- Parameter 2: p_municipio (Type: Dropdown Multi-Select)
-- Parameter 3: p_tipologia (Type: Dropdown Multi-Select)
-- Parameter 4: p_fecha_desde (Type: Date, Default: DATE_SUB(CURRENT_DATE(), 90))
-- Parameter 5: p_fecha_hasta (Type: Date, Default: CURRENT_DATE())


-- ============================================================================
-- WIDGET 1.1: TOTAL SITES COVERED (Counter KPI Card)
-- ============================================================================
-- Visualization: Counter
-- Display: Large number with label "Total Sites"
-- Color: Blue (#1F77B4)

SELECT 
  COUNT(DISTINCT cod_pus) AS total_sites,
  'Active Operational Sites' AS metric_label
FROM catalog_lcom.silver.supply_chain_master
WHERE 1=1
  AND (COALESCE(ARRAY_SIZE(:p_departamento), 0) = 0 OR DEPARTAMENTO IN (:p_departamento))
  AND (COALESCE(ARRAY_SIZE(:p_municipio), 0) = 0 OR MUNICIPIO IN (:p_municipio))
  AND (COALESCE(ARRAY_SIZE(:p_tipologia), 0) = 0 OR TIPOLOGIA_ROLLOS IN (:p_tipologia));


-- ============================================================================
-- WIDGET 1.2: OVERALL STOCKOUT RATE (Counter with % - Red Alert)
-- ============================================================================
-- Visualization: Counter
-- Display: Percentage with trend indicator
-- Color: Red (#E74C3C) if > 5%, Yellow (#F39C12) if 2-5%, Green (#27AE60) if < 2%

SELECT 
  ROUND(
    (SUM(CASE WHEN T = 'DESABASTECIDO' THEN 1 ELSE 0 END)::FLOAT / 
     COUNT(DISTINCT cod_pus)::FLOAT) * 100, 
    2
  ) AS stockout_rate_pct,
  SUM(CASE WHEN T = 'DESABASTECIDO' THEN 1 ELSE 0 END) AS sites_out_of_stock,
  COUNT(DISTINCT cod_pus) AS total_sites,
  'Critical Stockout Rate' AS metric_label
FROM catalog_lcom.silver.supply_chain_master
WHERE 1=1
  AND (COALESCE(ARRAY_SIZE(:p_departamento), 0) = 0 OR DEPARTAMENTO IN (:p_departamento))
  AND (COALESCE(ARRAY_SIZE(:p_municipio), 0) = 0 OR MUNICIPIO IN (:p_municipio))
  AND (COALESCE(ARRAY_SIZE(:p_tipologia), 0) = 0 OR TIPOLOGIA_ROLLOS IN (:p_tipologia));


-- ============================================================================
-- WIDGET 1.3: ROLL CONSUMPTION VS DELIVERED (Counter with Comparison)
-- ============================================================================
-- Visualization: Counter with secondary value
-- Display: Main = Consumed, Secondary = Delivered, Show difference
-- Color: Dynamic based on consumption efficiency

SELECT 
  FORMAT_NUMBER(SUM(`ROLLOS_CONSUMIDOS_DESDE_MIGRACIÓN_O_APERTURA`), 0) AS total_consumed,
  FORMAT_NUMBER(SUM(`ROLLOS_ENTREGADOS_DESDE_MIGRACIÓN_O_APERTURA`), 0) AS total_delivered,
  ROUND(
    (SUM(`ROLLOS_CONSUMIDOS_DESDE_MIGRACIÓN_O_APERTURA`)::FLOAT / 
     NULLIF(SUM(`ROLLOS_ENTREGADOS_DESDE_MIGRACIÓN_O_APERTURA`), 0)::FLOAT) * 100,
    1
  ) AS consumption_efficiency_pct,
  FORMAT_NUMBER(
    SUM(`ROLLOS_ENTREGADOS_DESDE_MIGRACIÓN_O_APERTURA`) - 
    SUM(`ROLLOS_CONSUMIDOS_DESDE_MIGRACIÓN_O_APERTURA`), 
    0
  ) AS net_inventory_change
FROM catalog_lcom.silver.supply_chain_master
WHERE 1=1
  AND (COALESCE(ARRAY_SIZE(:p_departamento), 0) = 0 OR DEPARTAMENTO IN (:p_departamento))
  AND (COALESCE(ARRAY_SIZE(:p_municipio), 0) = 0 OR MUNICIPIO IN (:p_municipio))
  AND (COALESCE(ARRAY_SIZE(:p_tipologia), 0) = 0 OR TIPOLOGIA_ROLLOS IN (:p_tipologia));


-- ============================================================================
-- WIDGET 1.4: AVERAGE REMAINING STOCK DAYS (Counter with Gauge)
-- ============================================================================
-- Visualization: Counter + Gauge (0-60 days scale)
-- Display: Days remaining with color zones
-- Zones: Red (0-7), Yellow (8-15), Green (16+)

SELECT 
  ROUND(AVG(saldo_dias_ajustado), 1) AS avg_stock_days,
  ROUND(MIN(saldo_dias_ajustado), 1) AS min_stock_days,
  ROUND(MAX(saldo_dias_ajustado), 1) AS max_stock_days,
  ROUND(PERCENTILE(saldo_dias_ajustado, 0.5), 1) AS median_stock_days,
  'National Average Stock Days' AS metric_label
FROM catalog_lcom.silver.supply_chain_master
WHERE saldo_dias_ajustado BETWEEN 0 AND 365  -- Filter outliers
  AND (COALESCE(ARRAY_SIZE(:p_departamento), 0) = 0 OR DEPARTAMENTO IN (:p_departamento))
  AND (COALESCE(ARRAY_SIZE(:p_municipio), 0) = 0 OR MUNICIPIO IN (:p_municipio))
  AND (COALESCE(ARRAY_SIZE(:p_tipologia), 0) = 0 OR TIPOLOGIA_ROLLOS IN (:p_tipologia));


-- ============================================================================
-- WIDGET 1.5: CRITICAL ACTION REQUIRED COUNT (Counter - Red Alert)
-- ============================================================================
-- Visualization: Counter with alert icon
-- Display: Number of sites requiring immediate restocking
-- Color: Red with pulsing animation if > 100

SELECT 
  SUM(CASE WHEN requiere_reabastecimiento = 1 THEN 1 ELSE 0 END) AS sites_need_restocking,
  SUM(CASE WHEN `ACCIÓN` = 'REABASTECER' THEN 1 ELSE 0 END) AS sites_action_restock,
  SUM(CASE WHEN saldo_dias_ajustado <= 7 THEN 1 ELSE 0 END) AS sites_critical_7days,
  ROUND(
    (SUM(CASE WHEN requiere_reabastecimiento = 1 THEN 1 ELSE 0 END)::FLOAT / 
     COUNT(*)::FLOAT) * 100,
    1
  ) AS pct_sites_critical,
  'Critical Action Required' AS metric_label
FROM catalog_lcom.silver.supply_chain_master
WHERE 1=1
  AND (COALESCE(ARRAY_SIZE(:p_departamento), 0) = 0 OR DEPARTAMENTO IN (:p_departamento))
  AND (COALESCE(ARRAY_SIZE(:p_municipio), 0) = 0 OR MUNICIPIO IN (:p_municipio))
  AND (COALESCE(ARRAY_SIZE(:p_tipologia), 0) = 0 OR TIPOLOGIA_ROLLOS IN (:p_tipologia));


-- ============================================================================
-- WIDGET 1.6: GEOGRAPHIC RISK HEATMAP
-- ============================================================================
-- Visualization: Pivot Table / Heatmap
-- Display: Department rows, Municipality columns, colored by risk level
-- Color Scale: Green (low risk) → Yellow → Orange → Red (high risk)

SELECT 
  DEPARTAMENTO,
  MUNICIPIO,
  COUNT(DISTINCT cod_pus) AS total_sites,
  SUM(CASE WHEN requiere_reabastecimiento = 1 THEN 1 ELSE 0 END) AS critical_sites,
  ROUND(
    (SUM(CASE WHEN requiere_reabastecimiento = 1 THEN 1 ELSE 0 END)::FLOAT / 
     COUNT(DISTINCT cod_pus)::FLOAT) * 100,
    1
  ) AS pct_critical,
  ROUND(AVG(saldo_dias_ajustado), 1) AS avg_days_remaining,
  SUM(saldo_rollos_ajustado) AS total_stock_rolls,
  ROUND(AVG(tasa_consumo_diario), 2) AS avg_daily_burn_rate,
  CASE 
    WHEN AVG(saldo_dias_ajustado) <= 7 THEN 'Critical'
    WHEN AVG(saldo_dias_ajustado) <= 15 THEN 'High Risk'
    WHEN AVG(saldo_dias_ajustado) <= 30 THEN 'Medium Risk'
    ELSE 'Low Risk'
  END AS risk_level,
  CASE 
    WHEN AVG(saldo_dias_ajustado) <= 7 THEN '#C0392B'  -- Dark Red
    WHEN AVG(saldo_dias_ajustado) <= 15 THEN '#E74C3C' -- Red
    WHEN AVG(saldo_dias_ajustado) <= 30 THEN '#F39C12' -- Orange
    ELSE '#27AE60' -- Green
  END AS color_code
FROM catalog_lcom.silver.supply_chain_master
WHERE 1=1
  AND (COALESCE(ARRAY_SIZE(:p_departamento), 0) = 0 OR DEPARTAMENTO IN (:p_departamento))
  AND (COALESCE(ARRAY_SIZE(:p_municipio), 0) = 0 OR MUNICIPIO IN (:p_municipio))
  AND (COALESCE(ARRAY_SIZE(:p_tipologia), 0) = 0 OR TIPOLOGIA_ROLLOS IN (:p_tipologia))
GROUP BY DEPARTAMENTO, MUNICIPIO
ORDER BY pct_critical DESC, avg_days_remaining ASC
LIMIT 100;


-- ============================================================================
-- WIDGET 1.7: SUPPLY VS CONSUMPTION TREND (Time Series)
-- ============================================================================
-- Visualization: Stacked Area Chart or Dual-Axis Line Chart
-- X-Axis: Month
-- Y-Axis: Roll quantity
-- Series: Delivered (Blue), Consumed (Orange), Net Change (Green line)

WITH monthly_metrics AS (
  SELECT 
    DATE_TRUNC('month', TRY_TO_DATE(SUBSTR(`FECHA_MIGRACIÓN_O_APERTURA`, 1, 10))) AS month_date,
    SUM(`ROLLOS_ENTREGADOS_DESDE_MIGRACIÓN_O_APERTURA`) AS delivered,
    SUM(`ROLLOS_CONSUMIDOS_DESDE_MIGRACIÓN_O_APERTURA`) AS consumed,
    COUNT(DISTINCT cod_pus) AS sites_active
  FROM catalog_lcom.silver.supply_chain_master
  WHERE TRY_TO_DATE(SUBSTR(`FECHA_MIGRACIÓN_O_APERTURA`, 1, 10)) IS NOT NULL
    AND TRY_TO_DATE(SUBSTR(`FECHA_MIGRACIÓN_O_APERTURA`, 1, 10)) >= DATE_SUB(CURRENT_DATE(), 365)
    AND (COALESCE(ARRAY_SIZE(:p_departamento), 0) = 0 OR DEPARTAMENTO IN (:p_departamento))
    AND (COALESCE(ARRAY_SIZE(:p_municipio), 0) = 0 OR MUNICIPIO IN (:p_municipio))
    AND (COALESCE(ARRAY_SIZE(:p_tipologia), 0) = 0 OR TIPOLOGIA_ROLLOS IN (:p_tipologia))
  GROUP BY DATE_TRUNC('month', TRY_TO_DATE(SUBSTR(`FECHA_MIGRACIÓN_O_APERTURA`, 1, 10)))
)
SELECT 
  DATE_FORMAT(month_date, 'MMM yyyy') AS month_label,
  month_date,
  delivered,
  consumed,
  (delivered - consumed) AS net_change,
  ROUND((consumed::FLOAT / NULLIF(delivered, 0)::FLOAT) * 100, 1) AS consumption_rate_pct,
  sites_active
FROM monthly_metrics
ORDER BY month_date;


-- ============================================================================
-- WIDGET 1.8: TOP 10 CRITICAL OPERATIONS SITES (Horizontal Bar Chart)
-- ============================================================================
-- Visualization: Horizontal Bar Chart
-- X-Axis: Days remaining (sorted ascending)
-- Y-Axis: Site name (cod_pus + location)
-- Color: By typology (Principal=Blue, Intermedia=Orange, Lejana=Red)

SELECT 
  cod_pus,
  CONCAT(SEDE_OPERACIONES, ' - ', MUNICIPIO) AS site_location,
  TIPOLOGIA_ROLLOS AS typology,
  ROUND(saldo_dias_ajustado, 1) AS days_remaining,
  saldo_rollos_ajustado AS current_stock,
  ROUND(tasa_consumo_diario, 2) AS daily_burn_rate,
  cantidad_reabastecimiento_optima AS recommended_restock,
  riesgo_desabastecimiento AS risk_level,
  CASE 
    WHEN TIPOLOGIA_ROLLOS = 'PRINCIPAL' THEN '#3498DB'  -- Blue
    WHEN TIPOLOGIA_ROLLOS = 'INTERMEDIA' THEN '#F39C12' -- Orange
    WHEN TIPOLOGIA_ROLLOS = 'LEJANA' THEN '#E74C3C'     -- Red
    ELSE '#95A5A6' -- Gray
  END AS bar_color
FROM catalog_lcom.silver.supply_chain_master
WHERE saldo_dias_ajustado >= 0  -- Exclude extreme negatives
  AND (COALESCE(ARRAY_SIZE(:p_departamento), 0) = 0 OR DEPARTAMENTO IN (:p_departamento))
  AND (COALESCE(ARRAY_SIZE(:p_municipio), 0) = 0 OR MUNICIPIO IN (:p_municipio))
  AND (COALESCE(ARRAY_SIZE(:p_tipologia), 0) = 0 OR TIPOLOGIA_ROLLOS IN (:p_tipologia))
ORDER BY saldo_dias_ajustado ASC
LIMIT 10;


-- ============================================================================
-- WIDGET 1.9: RISK DISTRIBUTION DONUT CHART
-- ============================================================================
-- Visualization: Donut Chart
-- Display: Proportion of sites by risk level
-- Colors: Match risk level palette

SELECT 
  riesgo_desabastecimiento AS risk_category,
  COUNT(DISTINCT cod_pus) AS site_count,
  ROUND(
    (COUNT(DISTINCT cod_pus)::FLOAT / 
     SUM(COUNT(DISTINCT cod_pus)) OVER ()::FLOAT) * 100,
    1
  ) AS percentage,
  CASE riesgo_desabastecimiento
    WHEN 'CRITICO' THEN '#C0392B'  -- Dark Red
    WHEN 'ALTO' THEN '#E74C3C'     -- Red
    WHEN 'MEDIO' THEN '#F39C12'    -- Orange
    WHEN 'BAJO' THEN '#F1C40F'     -- Yellow
    ELSE '#27AE60'                 -- Green
  END AS segment_color,
  CASE riesgo_desabastecimiento
    WHEN 'CRITICO' THEN 1
    WHEN 'ALTO' THEN 2
    WHEN 'MEDIO' THEN 3
    WHEN 'BAJO' THEN 4
    ELSE 5
  END AS sort_order
FROM catalog_lcom.silver.supply_chain_master
WHERE 1=1
  AND (COALESCE(ARRAY_SIZE(:p_departamento), 0) = 0 OR DEPARTAMENTO IN (:p_departamento))
  AND (COALESCE(ARRAY_SIZE(:p_municipio), 0) = 0 OR MUNICIPIO IN (:p_municipio))
  AND (COALESCE(ARRAY_SIZE(:p_tipologia), 0) = 0 OR TIPOLOGIA_ROLLOS IN (:p_tipologia))
GROUP BY riesgo_desabastecimiento
ORDER BY sort_order;


-- ============================================================================
-- PARAMETER SOURCE QUERIES (For Dashboard Filters)
-- ============================================================================

-- Parameter Source: p_departamento
SELECT DISTINCT DEPARTAMENTO AS value, DEPARTAMENTO AS label
FROM catalog_lcom.silver.supply_chain_master
WHERE DEPARTAMENTO IS NOT NULL
ORDER BY DEPARTAMENTO;

-- Parameter Source: p_municipio (Cascading - depends on p_departamento)
SELECT DISTINCT MUNICIPIO AS value, MUNICIPIO AS label
FROM catalog_lcom.silver.supply_chain_master
WHERE MUNICIPIO IS NOT NULL
  AND (COALESCE(ARRAY_SIZE(:p_departamento), 0) = 0 OR DEPARTAMENTO IN (:p_departamento))
ORDER BY MUNICIPIO;

-- Parameter Source: p_tipologia
SELECT DISTINCT TIPOLOGIA_ROLLOS AS value, TIPOLOGIA_ROLLOS AS label
FROM catalog_lcom.silver.supply_chain_master
WHERE TIPOLOGIA_ROLLOS IS NOT NULL
ORDER BY TIPOLOGIA_ROLLOS;


-- ============================================================================
-- END OF PAGE 1: EXECUTIVE SUPPLY CHAIN OVERVIEW
-- ============================================================================