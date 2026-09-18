-- EXECUTIVE KPI CARDS FOR DASHBOARD
-- PURPOSE: High-level metrics for executive summary
-- CATALOG: catalog_lcom.gold
-- AUTHOR: Principal Big Data Engineer
-- DATE: September 2026

-- KPI Card 1: Total Sites
SELECT 
  'Total Sites' AS metric,
  total_sitios AS value,
  NULL AS change_pct
FROM catalog_lcom.gold.kpi_executive_summary
UNION ALL

-- KPI Card 2: Total Rolls Delivered
SELECT 
  'Total Rolls Delivered' AS metric,
  FORMAT_NUMBER(total_rollos_entregados, 0) AS value,
  NULL AS change_pct
FROM catalog_lcom.gold.kpi_executive_summary
UNION ALL

-- KPI Card 3: Current Stock Available
SELECT 
  'Stock Available' AS metric,
  FORMAT_NUMBER(total_rollos_disponibles, 0) AS value,
  NULL AS change_pct
FROM catalog_lcom.gold.kpi_executive_summary
UNION ALL

-- KPI Card 4: Critical Sites Count
SELECT 
  'Critical Sites' AS metric,
  sitios_criticos AS value,
  CONCAT(CAST(porcentaje_sitios_criticos AS STRING), '%') AS change_pct
FROM catalog_lcom.gold.kpi_executive_summary
UNION ALL

-- KPI Card 5: Sites with Less Than 7 Days Stock
SELECT 
  'Sites < 7 Days Stock' AS metric,
  sitios_menos_7_dias AS value,
  CONCAT('Urgent Action Required') AS change_pct
FROM catalog_lcom.gold.kpi_executive_summary
UNION ALL

-- KPI Card 6: Average Daily Consumption Rate
SELECT 
  'Avg Daily Consumption' AS metric,
  CAST(tasa_consumo_diario_promedio AS STRING) AS value,
  'rolls/day' AS change_pct
FROM catalog_lcom.gold.kpi_executive_summary
UNION ALL

-- KPI Card 7: Average Stock Days Remaining
SELECT 
  'Avg Stock Days' AS metric,
  CAST(promedio_dias_stock AS STRING) AS value,
  'days' AS change_pct
FROM catalog_lcom.gold.kpi_executive_summary
UNION ALL

-- KPI Card 8: Total Recommended Restocking
SELECT 
  'Recommended Restocking' AS metric,
  FORMAT_NUMBER(cantidad_reabastecimiento_total, 0) AS value,
  'rolls needed' AS change_pct
FROM catalog_lcom.gold.kpi_executive_summary;