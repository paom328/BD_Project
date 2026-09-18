-- GEOGRAPHICAL DISTRIBUTION HEATMAP
-- PURPOSE: Visualize consumption and risk by Department and Municipality
-- CATALOG: catalog_lcom.gold
-- AUTHOR: Principal Big Data Engineer
-- DATE: September 2026

SELECT 
  DEPARTAMENTO,
  MUNICIPIO,
  total_sitios,
  sitios_criticos,
  porcentaje_sitios_criticos,
  consumo_total,
  stock_actual,
  dias_stock_promedio,
  consumo_diario_promedio,
  riesgo_critico,
  riesgo_alto,
  riesgo_medio,
  CASE 
    WHEN porcentaje_sitios_criticos >= 50 THEN 'Critical Zone'
    WHEN porcentaje_sitios_criticos >= 25 THEN 'High Risk Zone'
    WHEN porcentaje_sitios_criticos >= 10 THEN 'Medium Risk Zone'
    ELSE 'Normal Zone'
  END AS risk_zone,
  CASE
    WHEN dias_stock_promedio <= 7 THEN '#E74C3C'  -- Red
    WHEN dias_stock_promedio <= 15 THEN '#F39C12' -- Orange
    WHEN dias_stock_promedio <= 30 THEN '#F1C40F' -- Yellow
    ELSE '#27AE60' -- Green
  END AS color_code
FROM catalog_lcom.gold.kpi_geographical_distribution
WHERE total_sitios > 0
ORDER BY sitios_criticos DESC, porcentaje_sitios_criticos DESC
LIMIT 100;