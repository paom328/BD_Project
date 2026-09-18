-- CRITICAL SITES ALERT QUERY
-- PURPOSE: Identify sites requiring immediate restocking action
-- CATALOG: catalog_lcom.gold
-- AUTHOR: Principal Big Data Engineer
-- DATE: September 2026
-- USE CASE: Automated alerts and urgent action dashboard

SELECT 
  s.cod_pus,
  s.DEPARTAMENTO,
  s.MUNICIPIO,
  s.SEDE_OPERACIONES,
  s.TIPOLOGIA_ROLLOS,
  s.saldo_rollos_ajustado AS stock_actual,
  s.saldo_dias_ajustado AS dias_restantes,
  s.tasa_consumo_diario,
  s.cantidad_reabastecimiento_optima AS rollos_necesarios,
  ml.ml_stockout_probability AS probabilidad_desabastecimiento_ml,
  ml.ml_predicted_saldo_dias AS dias_predichos_ml,
  ml.ml_cantidad_reabastecimiento AS cantidad_ml_recomendada,
  s.riesgo_desabastecimiento AS nivel_riesgo,
  s.ACCIÓN AS accion_requerida,
  s.T AS tipo_estado,
  CURRENT_DATE() AS fecha_alerta,
  CASE 
    WHEN s.saldo_dias_ajustado <= 0 THEN 'IMMEDIATE ACTION - OUT OF STOCK'
    WHEN s.saldo_dias_ajustado <= 3 THEN 'URGENT - 3 DAYS OR LESS'
    WHEN s.saldo_dias_ajustado <= 7 THEN 'HIGH PRIORITY - 7 DAYS OR LESS'
    ELSE 'MONITOR CLOSELY'
  END AS priority_level,
  CASE
    WHEN s.saldo_dias_ajustado <= 0 THEN 1
    WHEN s.saldo_dias_ajustado <= 3 THEN 2
    WHEN s.saldo_dias_ajustado <= 7 THEN 3
    ELSE 4
  END AS priority_order
FROM catalog_lcom.silver.supply_chain_master s
LEFT JOIN catalog_lcom.gold.ml_supply_chain_predictions ml
  ON s.cod_pus = ml.cod_pus
WHERE 
  s.requiere_reabastecimiento = 1
  OR s.saldo_dias_ajustado <= 7
  OR ml.ml_stockout_risk_pred = 1
ORDER BY 
  priority_order ASC,
  s.saldo_dias_ajustado ASC,
  ml.ml_stockout_probability DESC
LIMIT 500;