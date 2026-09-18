-- INVENTORY DEPLETION TIME-SERIES CHART
-- PURPOSE: Track sites by remaining stock days buckets
-- CATALOG: catalog_lcom.gold
-- AUTHOR: Principal Big Data Engineer
-- DATE: September 2026

SELECT 
  bucket_dias_stock,
  total_sitios,
  stock_disponible,
  reabastecimiento_necesario,
  ROUND((total_sitios::FLOAT / SUM(total_sitios) OVER ()) * 100, 2) AS porcentaje_sitios,
  CASE 
    WHEN bucket_dias_stock = '0: Desabastecido' THEN 1
    WHEN bucket_dias_stock = '1-7: Critico' THEN 2
    WHEN bucket_dias_stock = '8-15: Alto Riesgo' THEN 3
    WHEN bucket_dias_stock = '16-30: Medio Riesgo' THEN 4
    WHEN bucket_dias_stock = '31-60: Bajo Riesgo' THEN 5
    ELSE 6
  END AS sort_order,
  CASE 
    WHEN bucket_dias_stock LIKE '0:%' THEN '#C0392B'  -- Dark Red
    WHEN bucket_dias_stock LIKE '1-7:%' THEN '#E74C3C' -- Red
    WHEN bucket_dias_stock LIKE '8-15:%' THEN '#E67E22' -- Orange
    WHEN bucket_dias_stock LIKE '16-30:%' THEN '#F39C12' -- Light Orange
    WHEN bucket_dias_stock LIKE '31-60:%' THEN '#F1C40F' -- Yellow
    ELSE '#27AE60' -- Green
  END AS bar_color
FROM catalog_lcom.gold.kpi_inventory_depletion
ORDER BY sort_order;