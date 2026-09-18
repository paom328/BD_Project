-- ============================================================================
-- DATABRICKS LAKEHOUSE DASHBOARD - PAGE 2: ML FORECASTING & REPLENISHMENT
-- ============================================================================
-- Purpose: ML-powered inventory forecasting and replenishment planning
-- Catalog: catalog_lcom.gold (ML predictions)
-- Author: Senior BI Architect & ML Specialist
-- Last Updated: September 2026
-- ============================================================================

-- NOTE: This page uses the same parameters as Page 1 (p_departamento, p_municipio, p_tipologia)
--       Ensure parameters are configured at the dashboard level for cross-page filtering


-- ============================================================================
-- WIDGET 2.1: ML MODEL PERFORMANCE SUMMARY (KPI Cards Row)
-- ============================================================================
-- Visualization: 4 Counter widgets side-by-side
-- Display: Model accuracy metrics and prediction statistics

-- Card 2.1.a: ML Stockout Predictions Count
SELECT 
  SUM(ml_stockout_risk_pred) AS ml_predicted_stockouts,
  ROUND(AVG(ml_stockout_probability) * 100, 1) AS avg_stockout_probability_pct,
  'ML Predicted Stockouts' AS metric_label
FROM catalog_lcom.gold.ml_supply_chain_predictions ml
INNER JOIN catalog_lcom.silver.supply_chain_master s
  ON ml.cod_pus = s.cod_pus
WHERE 1=1
  AND (ARRAY_SIZE({{p_departamento}}) = 0 OR s.DEPARTAMENTO IN ({{p_departamento}}))
  AND (ARRAY_SIZE({{p_municipio}}) = 0 OR s.MUNICIPIO IN ({{p_municipio}}))
  AND (ARRAY_SIZE({{p_tipologia}}) = 0 OR s.TIPOLOGIA_ROLLOS IN ({{p_tipologia}}));

-- Card 2.1.b: High Risk Sites (Probability > 70%)
SELECT 
  COUNT(DISTINCT ml.cod_pus) AS high_risk_sites,
  ROUND(
    (COUNT(DISTINCT ml.cod_pus)::FLOAT / 
     (SELECT COUNT(DISTINCT cod_pus) FROM catalog_lcom.gold.ml_supply_chain_predictions)::FLOAT
    ) * 100,
    1
  ) AS pct_high_risk,
  'High Risk Sites (>70% probability)' AS metric_label
FROM catalog_lcom.gold.ml_supply_chain_predictions ml
INNER JOIN catalog_lcom.silver.supply_chain_master s
  ON ml.cod_pus = s.cod_pus
WHERE ml.ml_stockout_probability > 0.70
  AND (ARRAY_SIZE({{p_departamento}}) = 0 OR s.DEPARTAMENTO IN ({{p_departamento}}))
  AND (ARRAY_SIZE({{p_municipio}}) = 0 OR s.MUNICIPIO IN ({{p_municipio}}))
  AND (ARRAY_SIZE({{p_tipologia}}) = 0 OR s.TIPOLOGIA_ROLLOS IN ({{p_tipologia}}));

-- Card 2.1.c: ML Recommended Restocking Quantity
SELECT 
  FORMAT_NUMBER(SUM(ml_cantidad_reabastecimiento), 0) AS ml_total_recommended_rolls,
  FORMAT_NUMBER(AVG(ml_cantidad_reabastecimiento), 0) AS ml_avg_per_site,
  'ML Recommended Total Rolls' AS metric_label
FROM catalog_lcom.gold.ml_supply_chain_predictions ml
INNER JOIN catalog_lcom.silver.supply_chain_master s
  ON ml.cod_pus = s.cod_pus
WHERE ml.ml_stockout_risk_pred = 1
  AND (ARRAY_SIZE({{p_departamento}}) = 0 OR s.DEPARTAMENTO IN ({{p_departamento}}))
  AND (ARRAY_SIZE({{p_municipio}}) = 0 OR s.MUNICIPIO IN ({{p_municipio}}))
  AND (ARRAY_SIZE({{p_tipologia}}) = 0 OR s.TIPOLOGIA_ROLLOS IN ({{p_tipologia}}));

-- Card 2.1.d: Average Predicted Days Remaining
SELECT 
  ROUND(AVG(ml_predicted_saldo_dias), 1) AS ml_avg_predicted_days,
  ROUND(AVG(s.saldo_dias_ajustado), 1) AS actual_avg_days,
  ROUND(AVG(ml_predicted_saldo_dias - s.saldo_dias_ajustado), 1) AS avg_prediction_error,
  'ML Avg Predicted Days' AS metric_label
FROM catalog_lcom.gold.ml_supply_chain_predictions ml
INNER JOIN catalog_lcom.silver.supply_chain_master s
  ON ml.cod_pus = s.cod_pus
WHERE s.saldo_dias_ajustado BETWEEN 0 AND 365
  AND (ARRAY_SIZE({{p_departamento}}) = 0 OR s.DEPARTAMENTO IN ({{p_departamento}}))
  AND (ARRAY_SIZE({{p_municipio}}) = 0 OR s.MUNICIPIO IN ({{p_municipio}}))
  AND (ARRAY_SIZE({{p_tipologia}}) = 0 OR s.TIPOLOGIA_ROLLOS IN ({{p_tipologia}}));


-- ============================================================================
-- WIDGET 2.2: STOCK DEPLETION & ML RISK MATRIX (Scatter/Bubble Chart)
-- ============================================================================
-- Visualization: Scatter Plot with Bubble Sizing
-- X-Axis: saldo_dias_ajustado (Days Remaining)
-- Y-Axis: prom_mensual_anterior (Monthly Average Consumption)
-- Bubble Size: saldo_rollos_ajustado (Current Stock Volume)
-- Color: ml_stockout_probability (0.0 = Green, 1.0 = Red gradient)

SELECT 
  s.cod_pus,
  s.SEDE_OPERACIONES AS site_name,
  s.MUNICIPIO,
  s.DEPARTAMENTO,
  s.TIPOLOGIA_ROLLOS,
  s.saldo_dias_ajustado AS days_remaining,
  s.prom_mensual_anterior AS monthly_avg_consumption,
  s.saldo_rollos_ajustado AS current_stock_volume,
  ml.ml_stockout_probability AS risk_probability,
  ml.ml_predicted_saldo_dias AS ml_predicted_days,
  s.riesgo_desabastecimiento AS risk_level,
  CASE 
    WHEN ml.ml_stockout_probability >= 0.8 THEN '#C0392B'  -- Dark Red (Very High Risk)
    WHEN ml.ml_stockout_probability >= 0.6 THEN '#E74C3C'  -- Red (High Risk)
    WHEN ml.ml_stockout_probability >= 0.4 THEN '#F39C12'  -- Orange (Medium Risk)
    WHEN ml.ml_stockout_probability >= 0.2 THEN '#F1C40F'  -- Yellow (Low Risk)
    ELSE '#27AE60'                                         -- Green (Very Low Risk)
  END AS bubble_color,
  -- Tooltip information
  CONCAT(
    'Site: ', s.cod_pus, '\n',
    'Location: ', s.MUNICIPIO, ', ', s.DEPARTAMENTO, '\n',
    'Days Left: ', CAST(ROUND(s.saldo_dias_ajustado, 1) AS STRING), '\n',
    'Stock: ', CAST(ROUND(s.saldo_rollos_ajustado, 0) AS STRING), ' rolls\n',
    'ML Risk: ', CAST(ROUND(ml.ml_stockout_probability * 100, 1) AS STRING), '%'
  ) AS tooltip_text
FROM catalog_lcom.silver.supply_chain_master s
INNER JOIN catalog_lcom.gold.ml_supply_chain_predictions ml
  ON s.cod_pus = ml.cod_pus
WHERE s.saldo_dias_ajustado BETWEEN 0 AND 90  -- Focus on near-term risk
  AND s.prom_mensual_anterior > 0
  AND (ARRAY_SIZE({{p_departamento}}) = 0 OR s.DEPARTAMENTO IN ({{p_departamento}}))
  AND (ARRAY_SIZE({{p_municipio}}) = 0 OR s.MUNICIPIO IN ({{p_municipio}}))
  AND (ARRAY_SIZE({{p_tipologia}}) = 0 OR s.TIPOLOGIA_ROLLOS IN ({{p_tipologia}}))
ORDER BY ml.ml_stockout_probability DESC
LIMIT 500;


-- ============================================================================
-- WIDGET 2.3: REPLENISHMENT REQUIREMENT TABLE (Interactive Data Grid)
-- ============================================================================
-- Visualization: Table with Conditional Formatting
-- Features: Sortable, Filterable, Exportable to CSV/Excel
-- Conditional Formatting: Row background color based on days_remaining

SELECT 
  s.cod_pus,
  s.SEDE_OPERACIONES AS sede,
  s.MUNICIPIO,
  s.DEPARTAMENTO,
  s.TIPOLOGIA_ROLLOS AS tipologia,
  ROUND(s.saldo_rollos_ajustado, 0) AS saldo_actual,
  ROUND(s.saldo_dias_ajustado, 1) AS dias_restantes,
  DATE_ADD(CURRENT_DATE(), CAST(s.saldo_dias_ajustado AS INT)) AS fecha_probable_desabastecimiento,
  ROUND(s.cantidad_reabastecimiento_optima, 0) AS sugerido_reabastecimiento_rollos,
  ROUND(ml.ml_cantidad_reabastecimiento, 0) AS ml_sugerido_reabastecimiento,
  ROUND(ml.ml_stockout_probability * 100, 1) AS ml_probabilidad_stockout_pct,
  ROUND(s.tasa_consumo_diario, 2) AS tasa_consumo_diario,
  s.riesgo_desabastecimiento AS nivel_riesgo,
  s.ACCIÓN AS accion_requerida,
  -- Priority ranking for sorting
  CASE 
    WHEN s.saldo_dias_ajustado <= 0 THEN 1  -- Immediate
    WHEN s.saldo_dias_ajustado <= 3 THEN 2  -- Urgent (1-3 days)
    WHEN s.saldo_dias_ajustado <= 7 THEN 3  -- High Priority (4-7 days)
    WHEN s.saldo_dias_ajustado <= 15 THEN 4 -- Medium Priority (8-15 days)
    ELSE 5                                   -- Monitor
  END AS priority_rank,
  -- Color coding for conditional formatting
  CASE 
    WHEN s.saldo_dias_ajustado <= 0 THEN '#FFCDD2'     -- Light Red Background
    WHEN s.saldo_dias_ajustado <= 7 THEN '#FFECB3'     -- Light Orange Background
    WHEN s.saldo_dias_ajustado <= 15 THEN '#FFF9C4'    -- Light Yellow Background
    ELSE '#C8E6C9'                                      -- Light Green Background
  END AS row_background_color
FROM catalog_lcom.silver.supply_chain_master s
INNER JOIN catalog_lcom.gold.ml_supply_chain_predictions ml
  ON s.cod_pus = ml.cod_pus
WHERE (s.requiere_reabastecimiento = 1 OR ml.ml_stockout_risk_pred = 1)
  AND (ARRAY_SIZE({{p_departamento}}) = 0 OR s.DEPARTAMENTO IN ({{p_departamento}}))
  AND (ARRAY_SIZE({{p_municipio}}) = 0 OR s.MUNICIPIO IN ({{p_municipio}}))
  AND (ARRAY_SIZE({{p_tipologia}}) = 0 OR s.TIPOLOGIA_ROLLOS IN ({{p_tipologia}}))
ORDER BY priority_rank ASC, s.saldo_dias_ajustado ASC, ml.ml_stockout_probability DESC
LIMIT 1000;


-- ============================================================================
-- WIDGET 2.4: CONSUMPTION VARIANCE BY TYPOLOGY (Box Plot / Violin Plot)
-- ============================================================================
-- Visualization: Box Plot or Grouped Bar Chart
-- Display: Daily burn rate distribution by roll typology
-- Shows: Min, Q1, Median, Q3, Max, Outliers

SELECT 
  s.TIPOLOGIA_ROLLOS AS typology,
  COUNT(DISTINCT s.cod_pus) AS site_count,
  ROUND(MIN(s.tasa_consumo_diario), 2) AS min_daily_rate,
  ROUND(PERCENTILE(s.tasa_consumo_diario, 0.25), 2) AS q1_daily_rate,
  ROUND(PERCENTILE(s.tasa_consumo_diario, 0.50), 2) AS median_daily_rate,
  ROUND(AVG(s.tasa_consumo_diario), 2) AS mean_daily_rate,
  ROUND(PERCENTILE(s.tasa_consumo_diario, 0.75), 2) AS q3_daily_rate,
  ROUND(MAX(s.tasa_consumo_diario), 2) AS max_daily_rate,
  ROUND(STDDEV(s.tasa_consumo_diario), 2) AS stddev_daily_rate,
  -- Color by typology
  CASE s.TIPOLOGIA_ROLLOS
    WHEN 'PRINCIPAL' THEN '#3498DB'   -- Blue
    WHEN 'INTERMEDIA' THEN '#F39C12'  -- Orange
    WHEN 'LEJANA' THEN '#E74C3C'      -- Red
    ELSE '#95A5A6'                    -- Gray
  END AS box_color
FROM catalog_lcom.silver.supply_chain_master s
WHERE s.tasa_consumo_diario > 0 
  AND s.tasa_consumo_diario < 1000  -- Filter extreme outliers
  AND (ARRAY_SIZE({{p_departamento}}) = 0 OR s.DEPARTAMENTO IN ({{p_departamento}}))
  AND (ARRAY_SIZE({{p_municipio}}) = 0 OR s.MUNICIPIO IN ({{p_municipio}}))
  AND (ARRAY_SIZE({{p_tipologia}}) = 0 OR s.TIPOLOGIA_ROLLOS IN ({{p_tipologia}}))
GROUP BY s.TIPOLOGIA_ROLLOS
ORDER BY mean_daily_rate DESC;


-- ============================================================================
-- WIDGET 2.5: ML FORECAST VS ACTUALS (Multi-Series Line Chart)
-- ============================================================================
-- Visualization: Line Chart with 4 series
-- X-Axis: Forecast horizon (30/60/90 days)
-- Y-Axis: Projected roll demand
-- Series: Actual Historical, ML 30d Forecast, ML 60d Forecast, ML 90d Forecast

WITH forecast_comparison AS (
  SELECT 
    s.TIPOLOGIA_ROLLOS,
    '30-Day Forecast' AS forecast_period,
    30 AS days_ahead,
    SUM(s.demanda_proyectada_30d) AS projected_demand,
    SUM(s.tasa_consumo_diario * 30) AS ml_forecast,
    COUNT(DISTINCT s.cod_pus) AS site_count
  FROM catalog_lcom.silver.supply_chain_master s
  WHERE (ARRAY_SIZE({{p_departamento}}) = 0 OR s.DEPARTAMENTO IN ({{p_departamento}}))
    AND (ARRAY_SIZE({{p_municipio}}) = 0 OR s.MUNICIPIO IN ({{p_municipio}}))
    AND (ARRAY_SIZE({{p_tipologia}}) = 0 OR s.TIPOLOGIA_ROLLOS IN ({{p_tipologia}}))
  GROUP BY s.TIPOLOGIA_ROLLOS
  
  UNION ALL
  
  SELECT 
    s.TIPOLOGIA_ROLLOS,
    '60-Day Forecast' AS forecast_period,
    60 AS days_ahead,
    SUM(s.demanda_proyectada_60d) AS projected_demand,
    SUM(s.tasa_consumo_diario * 60) AS ml_forecast,
    COUNT(DISTINCT s.cod_pus) AS site_count
  FROM catalog_lcom.silver.supply_chain_master s
  WHERE (ARRAY_SIZE({{p_departamento}}) = 0 OR s.DEPARTAMENTO IN ({{p_departamento}}))
    AND (ARRAY_SIZE({{p_municipio}}) = 0 OR s.MUNICIPIO IN ({{p_municipio}}))
    AND (ARRAY_SIZE({{p_tipologia}}) = 0 OR s.TIPOLOGIA_ROLLOS IN ({{p_tipologia}}))
  GROUP BY s.TIPOLOGIA_ROLLOS
  
  UNION ALL
  
  SELECT 
    s.TIPOLOGIA_ROLLOS,
    '90-Day Forecast' AS forecast_period,
    90 AS days_ahead,
    SUM(s.demanda_proyectada_90d) AS projected_demand,
    SUM(s.tasa_consumo_diario * 90) AS ml_forecast,
    COUNT(DISTINCT s.cod_pus) AS site_count
  FROM catalog_lcom.silver.supply_chain_master s
  WHERE (ARRAY_SIZE({{p_departamento}}) = 0 OR s.DEPARTAMENTO IN ({{p_departamento}}))
    AND (ARRAY_SIZE({{p_municipio}}) = 0 OR s.MUNICIPIO IN ({{p_municipio}}))
    AND (ARRAY_SIZE({{p_tipologia}}) = 0 OR s.TIPOLOGIA_ROLLOS IN ({{p_tipologia}}))
  GROUP BY s.TIPOLOGIA_ROLLOS
)
SELECT 
  TIPOLOGIA_ROLLOS,
  forecast_period,
  days_ahead,
  ROUND(projected_demand, 0) AS rule_based_forecast,
  ROUND(ml_forecast, 0) AS ml_enhanced_forecast,
  ROUND(ABS(projected_demand - ml_forecast), 0) AS forecast_variance,
  ROUND(
    (ABS(projected_demand - ml_forecast) / NULLIF(projected_demand, 0)) * 100,
    1
  ) AS variance_pct,
  site_count
FROM forecast_comparison
ORDER BY TIPOLOGIA_ROLLOS, days_ahead;


-- ============================================================================
-- WIDGET 2.6: PREDICTED STOCKOUT TIMELINE (Gantt-Style Chart)
-- ============================================================================
-- Visualization: Horizontal Timeline / Gantt Chart
-- Display: Sites ordered by predicted stockout date
-- X-Axis: Date (Today → 60 days ahead)
-- Y-Axis: Site cod_pus
-- Color: ML risk probability gradient

SELECT 
  s.cod_pus,
  CONCAT(s.SEDE_OPERACIONES, ' (', s.MUNICIPIO, ')') AS site_label,
  CURRENT_DATE() AS today,
  DATE_ADD(CURRENT_DATE(), CAST(ml.ml_predicted_saldo_dias AS INT)) AS predicted_stockout_date,
  CAST(ml.ml_predicted_saldo_dias AS INT) AS days_until_stockout,
  ROUND(ml.ml_stockout_probability * 100, 1) AS stockout_probability_pct,
  s.TIPOLOGIA_ROLLOS,
  ROUND(s.saldo_rollos_ajustado, 0) AS current_stock,
  ROUND(ml.ml_cantidad_reabastecimiento, 0) AS recommended_restock,
  CASE 
    WHEN ml.ml_predicted_saldo_dias <= 7 THEN '#C0392B'   -- Dark Red
    WHEN ml.ml_predicted_saldo_dias <= 15 THEN '#E74C3C'  -- Red
    WHEN ml.ml_predicted_saldo_dias <= 30 THEN '#F39C12'  -- Orange
    ELSE '#F1C40F'                                        -- Yellow
  END AS timeline_color
FROM catalog_lcom.silver.supply_chain_master s
INNER JOIN catalog_lcom.gold.ml_supply_chain_predictions ml
  ON s.cod_pus = ml.cod_pus
WHERE ml.ml_stockout_risk_pred = 1
  AND ml.ml_predicted_saldo_dias BETWEEN 0 AND 60
  AND (ARRAY_SIZE({{p_departamento}}) = 0 OR s.DEPARTAMENTO IN ({{p_departamento}}))
  AND (ARRAY_SIZE({{p_municipio}}) = 0 OR s.MUNICIPIO IN ({{p_municipio}}))
  AND (ARRAY_SIZE({{p_tipologia}}) = 0 OR s.TIPOLOGIA_ROLLOS IN ({{p_tipologia}}))
ORDER BY ml.ml_predicted_saldo_dias ASC, ml.ml_stockout_probability DESC
LIMIT 50;


-- ============================================================================
-- WIDGET 2.7: RULE-BASED VS ML COMPARISON (Side-by-Side Bar Chart)
-- ============================================================================
-- Visualization: Grouped Bar Chart
-- Display: Compare rule-based predictions vs ML predictions
-- Groups: Total sites needing restock, Total rolls recommended

SELECT 
  'Sites Requiring Restocking' AS metric,
  SUM(s.requiere_reabastecimiento) AS rule_based_count,
  SUM(ml.ml_stockout_risk_pred) AS ml_predicted_count,
  SUM(ml.ml_stockout_risk_pred) - SUM(s.requiere_reabastecimiento) AS difference,
  ROUND(
    ((SUM(ml.ml_stockout_risk_pred) - SUM(s.requiere_reabastecimiento))::FLOAT / 
     NULLIF(SUM(s.requiere_reabastecimiento), 0)::FLOAT) * 100,
    1
  ) AS pct_difference
FROM catalog_lcom.silver.supply_chain_master s
INNER JOIN catalog_lcom.gold.ml_supply_chain_predictions ml
  ON s.cod_pus = ml.cod_pus
WHERE (ARRAY_SIZE({{p_departamento}}) = 0 OR s.DEPARTAMENTO IN ({{p_departamento}}))
  AND (ARRAY_SIZE({{p_municipio}}) = 0 OR s.MUNICIPIO IN ({{p_municipio}}))
  AND (ARRAY_SIZE({{p_tipologia}}) = 0 OR s.TIPOLOGIA_ROLLOS IN ({{p_tipologia}}))

UNION ALL

SELECT 
  'Total Rolls Recommended' AS metric,
  CAST(SUM(s.cantidad_reabastecimiento_optima) AS BIGINT) AS rule_based_count,
  CAST(SUM(ml.ml_cantidad_reabastecimiento) AS BIGINT) AS ml_predicted_count,
  CAST(SUM(ml.ml_cantidad_reabastecimiento) - SUM(s.cantidad_reabastecimiento_optima) AS BIGINT) AS difference,
  ROUND(
    ((SUM(ml.ml_cantidad_reabastecimiento) - SUM(s.cantidad_reabastecimiento_optima))::FLOAT / 
     NULLIF(SUM(s.cantidad_reabastecimiento_optima), 0)::FLOAT) * 100,
    1
  ) AS pct_difference
FROM catalog_lcom.silver.supply_chain_master s
INNER JOIN catalog_lcom.gold.ml_supply_chain_predictions ml
  ON s.cod_pus = ml.cod_pus
WHERE (ARRAY_SIZE({{p_departamento}}) = 0 OR s.DEPARTAMENTO IN ({{p_departamento}}))
  AND (ARRAY_SIZE({{p_municipio}}) = 0 OR s.MUNICIPIO IN ({{p_municipio}}))
  AND (ARRAY_SIZE({{p_tipologia}}) = 0 OR s.TIPOLOGIA_ROLLOS IN ({{p_tipologia}}));


-- ============================================================================
-- END OF PAGE 2: ML FORECASTING & REPLENISHMENT PLANNING
-- ============================================================================