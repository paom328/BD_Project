-- ============================================================================
-- DATABRICKS SQL ALERTS - AUTOMATED NOTIFICATIONS SYSTEM
-- ============================================================================
-- Purpose: Proactive alerting for critical supply chain events
-- Delivery Channels: Email, Slack, Webhook, PagerDuty integration
-- Author: Senior BI Architect
-- Last Updated: September 2026
-- ============================================================================

-- HOW TO CONFIGURE DATABRICKS SQL ALERTS:
-- 1. In Databricks SQL UI, go to "Alerts" → "Create Alert"
-- 2. Paste the query below
-- 3. Set the "Value" column to monitor (typically a count or metric)
-- 4. Define trigger condition (e.g., "Value" > 0 or "Value" > 50)
-- 5. Set refresh schedule (e.g., Every 6 hours, Daily at 8 AM)
-- 6. Configure notification destinations (Email, Slack webhook, etc.)
-- 7. Test and enable the alert


-- ============================================================================
-- ALERT 1: CRITICAL STOCKOUT ALERT
-- ============================================================================
-- Alert Name: CRITICAL_STOCKOUT_IMMEDIATE_ACTION
-- Frequency: Every 4 hours (or Daily at 6 AM, 12 PM, 6 PM)
-- Trigger Condition: critical_sites_count > 0
-- Severity: HIGH (P1)
-- Recipients: Operations Team, Supply Chain Managers, Site Directors
-- Delivery: Email + Slack + SMS (for critical alerts)

-- PURPOSE: Notify when any site reaches zero stock or DESABASTECIDO status
-- ACTIONS: Immediate emergency restocking, alternative supply arrangements

SELECT 
  COUNT(DISTINCT cod_pus) AS critical_sites_count,
  STRING_AGG(
    CONCAT(
      '• Site: ', cod_pus, 
      ' | Location: ', MUNICIPIO, ', ', DEPARTAMENTO,
      ' | Stock: ', CAST(ROUND(saldo_rollos_ajustado, 0) AS STRING), ' rolls',
      ' | Days: ', CAST(ROUND(saldo_dias_ajustado, 1) AS STRING),
      ' | Status: ', T,
      ' | Typology: ', TIPOLOGIA_ROLLOS
    ),
    '\n'
  ) AS critical_sites_details,
  CURRENT_TIMESTAMP() AS alert_timestamp,
  'CRITICAL STOCKOUT - IMMEDIATE ACTION REQUIRED' AS alert_title,
  CONCAT(
    '⚠️ URGENT: ', 
    CAST(COUNT(DISTINCT cod_pus) AS STRING), 
    ' site(s) are currently OUT OF STOCK or in CRITICAL status (≤0 days remaining).\n\n',
    'AFFECTED SITES:\n',
    STRING_AGG(
      CONCAT(
        '• Site: ', cod_pus, 
        ' | Location: ', MUNICIPIO, ', ', DEPARTAMENTO,
        ' | Stock: ', CAST(ROUND(saldo_rollos_ajustado, 0) AS STRING), ' rolls',
        ' | Days: ', CAST(ROUND(saldo_dias_ajustado, 1) AS STRING),
        ' | Status: ', T,
        ' | Typology: ', TIPOLOGIA_ROLLOS
      ),
      '\n'
    ),
    '\n\n',
    'ACTION REQUIRED: Initiate emergency restocking procedures immediately.\n',
    'Dashboard: [View Critical Sites](#critical-sites-dashboard)'
  ) AS alert_message_body
FROM catalog_lcom.silver.supply_chain_master
WHERE (
  saldo_dias_ajustado <= 0 
  OR T = 'DESABASTECIDO'
  OR (ACCIÓN = 'REABASTECER' AND saldo_dias_ajustado <= 1)
)
HAVING COUNT(DISTINCT cod_pus) > 0;

-- DATABRICKS ALERT CONFIGURATION:
-- Alert Settings:
--   - Name: CRITICAL_STOCKOUT_IMMEDIATE_ACTION
--   - Value Column: critical_sites_count
--   - Trigger Condition: Value > 0
--   - Schedule: Every 4 hours (0 */4 * * *)
--   - Rearm: 4 hours (send new alert only if condition persists)
-- Notification Template:
--   Subject: "🚨 CRITICAL STOCKOUT ALERT - {{critical_sites_count}} Sites Affected"
--   Body: Use {{alert_message_body}} placeholder
-- Destinations:
--   - Email: operations-team@company.com, supply-chain@company.com
--   - Slack: #supply-chain-alerts channel webhook
--   - PagerDuty: P1 incident (for 5+ sites)


-- ============================================================================
-- ALERT 2: URGENT REPLENISHMENT ALERT (High Volume)
-- ============================================================================
-- Alert Name: URGENT_REPLENISHMENT_THRESHOLD_EXCEEDED
-- Frequency: Every 6 hours
-- Trigger Condition: urgent_sites_count > 50
-- Severity: MEDIUM (P2)
-- Recipients: Logistics Coordinators, Regional Managers
-- Delivery: Email + Slack

-- PURPOSE: Alert when large number of sites need restocking within 1-7 days
-- ACTIONS: Coordinate bulk replenishment, prioritize logistics resources

SELECT 
  COUNT(DISTINCT cod_pus) AS urgent_sites_count,
  SUM(cantidad_reabastecimiento_optima) AS total_rolls_needed,
  ROUND(AVG(saldo_dias_ajustado), 1) AS avg_days_remaining,
  STRING_AGG(
    DEPARTAMENTO,
    ', '
  ) AS affected_departments,
  CURRENT_TIMESTAMP() AS alert_timestamp,
  'URGENT REPLENISHMENT THRESHOLD EXCEEDED' AS alert_title,
  CONCAT(
    '⚡ ATTENTION: ', 
    CAST(COUNT(DISTINCT cod_pus) AS STRING), 
    ' sites require urgent restocking within the next 7 days.\n\n',
    'SUMMARY:\n',
    '• Total Sites: ', CAST(COUNT(DISTINCT cod_pus) AS STRING), '\n',
    '• Total Rolls Needed: ', FORMAT_NUMBER(CAST(SUM(cantidad_reabastecimiento_optima) AS BIGINT), 0), '\n',
    '• Avg Days Remaining: ', CAST(ROUND(AVG(saldo_dias_ajustado), 1) AS STRING), '\n',
    '• Affected Regions: ', COUNT(DISTINCT DEPARTAMENTO), ' departments\n\n',
    'BREAKDOWN BY PRIORITY:\n',
    '• 0-1 days: ', CAST(SUM(CASE WHEN saldo_dias_ajustado <= 1 THEN 1 ELSE 0 END) AS STRING), ' sites\n',
    '• 2-3 days: ', CAST(SUM(CASE WHEN saldo_dias_ajustado BETWEEN 2 AND 3 THEN 1 ELSE 0 END) AS STRING), ' sites\n',
    '• 4-7 days: ', CAST(SUM(CASE WHEN saldo_dias_ajustado BETWEEN 4 AND 7 THEN 1 ELSE 0 END) AS STRING), ' sites\n\n',
    'BREAKDOWN BY TYPOLOGY:\n',
    '• Principal: ', CAST(SUM(CASE WHEN TIPOLOGIA_ROLLOS = 'PRINCIPAL' THEN 1 ELSE 0 END) AS STRING), ' sites\n',
    '• Intermedia: ', CAST(SUM(CASE WHEN TIPOLOGIA_ROLLOS = 'INTERMEDIA' THEN 1 ELSE 0 END) AS STRING), ' sites\n',
    '• Lejana: ', CAST(SUM(CASE WHEN TIPOLOGIA_ROLLOS = 'LEJANA' THEN 1 ELSE 0 END) AS STRING), ' sites\n\n',
    'ACTION REQUIRED: Coordinate bulk replenishment logistics across regions.\n',
    'Dashboard: [View Replenishment Plan](#replenishment-dashboard)'
  ) AS alert_message_body
FROM catalog_lcom.silver.supply_chain_master
WHERE (
  (ACCIÓN = 'REABASTECER' AND saldo_dias_ajustado BETWEEN 1 AND 7)
  OR (requiere_reabastecimiento = 1 AND saldo_dias_ajustado BETWEEN 1 AND 7)
)
HAVING COUNT(DISTINCT cod_pus) > 50;  -- Threshold: Alert when >50 sites need restocking

-- DATABRICKS ALERT CONFIGURATION:
-- Alert Settings:
--   - Name: URGENT_REPLENISHMENT_THRESHOLD_EXCEEDED
--   - Value Column: urgent_sites_count
--   - Trigger Condition: Value > 50
--   - Schedule: Every 6 hours (0 */6 * * *)
--   - Rearm: 6 hours
-- Notification Template:
--   Subject: "⚡ REPLENISHMENT ALERT - {{urgent_sites_count}} Sites Need Restocking"
--   Body: Use {{alert_message_body}} placeholder
-- Destinations:
--   - Email: logistics@company.com, regional-managers@company.com
--   - Slack: #logistics-alerts channel


-- ============================================================================
-- ALERT 3: PURCHASE ORDER EXECUTION DELAY ALERT
-- ============================================================================
-- Alert Name: PO_EXECUTION_DELAY_SLA_BREACH
-- Frequency: Daily at 9 AM
-- Trigger Condition: delayed_orders_count > 0
-- Severity: MEDIUM (P2)
-- Recipients: Procurement Team, Vendor Managers
-- Delivery: Email

-- PURPOSE: Identify purchase orders that exceed expected resolution time (>48 hours)
-- ACTIONS: Follow up with vendors, escalate delayed orders, update forecasts

SELECT 
  COUNT(*) AS delayed_orders_count,
  COUNT(DISTINCT cod_pus) AS affected_sites_count,
  ROUND(AVG(hours_since_expected), 1) AS avg_hours_overdue,
  CURRENT_TIMESTAMP() AS alert_timestamp,
  'PURCHASE ORDER EXECUTION DELAYS DETECTED' AS alert_title,
  CONCAT(
    '📄 PROCUREMENT ALERT: ', 
    CAST(COUNT(*) AS STRING), 
    ' purchase order(s) have exceeded the 48-hour resolution SLA.\n\n',
    'SUMMARY:\n',
    '• Delayed Orders: ', CAST(COUNT(*) AS STRING), '\n',
    '• Affected Sites: ', CAST(COUNT(DISTINCT cod_pus) AS STRING), '\n',
    '• Avg Hours Overdue: ', CAST(ROUND(AVG(hours_since_expected), 1) AS STRING), '\n',
    '• Departments: ', STRING_AGG(DISTINCT DEPARTAMENTO, ', '), '\n\n',
    'DELAYED ORDERS DETAILS:\n',
    STRING_AGG(
      CONCAT(
        '• Order: ', cod_pus,
        ' | Location: ', CIUDAD, ', ', DEPARTAMENTO,
        ' | Status: ', ESTADO,
        ' | Rolls: ', CAST(ROLLOS_ENTREGADOS AS STRING),
        ' | Typology: ', `TIPOLOGIA_ROLLOS`,
        ' | Hours Overdue: ', CAST(ROUND(hours_since_expected, 1) AS STRING)
      ),
      '\n'
    ),
    '\n\n',
    'ACTION REQUIRED: Follow up with vendors and escalate critical orders.\n',
    'Dashboard: [View Order Status](#purchase-orders-dashboard)'
  ) AS alert_message_body
FROM (
  SELECT 
    cod_pus,
    UPPER(TRIM(DEPARTAMENTO)) AS DEPARTAMENTO,
    UPPER(TRIM(CIUDAD)) AS CIUDAD,
    UPPER(TRIM(ESTADO)) AS ESTADO,
    CAST(ROLLOS_ENTREGADOS AS INT) AS ROLLOS_ENTREGADOS,
    COALESCE(UPPER(TRIM(`TIPOLOGIA_ROLLOS`)), 'N/A') AS `TIPOLOGIA_ROLLOS`,
    TO_TIMESTAMP(`FECHA_DE_SOLUCIÓN_(DD_MM_AAAA)`, 'dd/MM/yyyy HH:mm') AS resolution_date,
    -- Calculate hours since expected resolution (assuming 48-hour SLA)
    DATEDIFF(
      HOUR,
      DATE_ADD(TO_TIMESTAMP(`FECHA_DE_SOLUCIÓN_(DD_MM_AAAA)`, 'dd/MM/yyyy HH:mm'), -2),  -- Order creation (2 days before)
      CURRENT_TIMESTAMP()
    ) - 48 AS hours_since_expected  -- SLA is 48 hours
  FROM catalog_lcom.bronze.oc_agosto_raw
  WHERE `FECHA_DE_SOLUCIÓN_(DD_MM_AAAA)` IS NOT NULL
    AND UPPER(TRIM(ESTADO)) != 'EJECUTADO_EXITOSO'  -- Not yet successfully executed
    AND DATEDIFF(
          HOUR,
          DATE_ADD(TO_TIMESTAMP(`FECHA_DE_SOLUCIÓN_(DD_MM_AAAA)`, 'dd/MM/yyyy HH:mm'), -2),
          CURRENT_TIMESTAMP()
        ) > 48  -- Exceeded 48-hour SLA
) delayed_orders
HAVING COUNT(*) > 0;

-- DATABRICKS ALERT CONFIGURATION:
-- Alert Settings:
--   - Name: PO_EXECUTION_DELAY_SLA_BREACH
--   - Value Column: delayed_orders_count
--   - Trigger Condition: Value > 0
--   - Schedule: Daily at 9:00 AM (0 9 * * *)
--   - Rearm: 24 hours
-- Notification Template:
--   Subject: "📄 PO DELAY ALERT - {{delayed_orders_count}} Orders Overdue"
--   Body: Use {{alert_message_body}} placeholder
-- Destinations:
--   - Email: procurement@company.com, vendor-relations@company.com


-- ============================================================================
-- BONUS ALERT 4: ML HIGH-RISK PREDICTIONS (Optional)
-- ============================================================================
-- Alert Name: ML_HIGH_RISK_STOCKOUT_PREDICTIONS
-- Frequency: Daily at 8 AM
-- Trigger Condition: high_risk_sites > 20
-- Severity: LOW (P3 - Informational)
-- Recipients: Analytics Team, Planning Team
-- Delivery: Email

-- PURPOSE: Proactive notification of ML-predicted high-risk sites (>70% probability)
-- ACTIONS: Review predictions, plan preemptive restocking, validate model accuracy

SELECT 
  COUNT(DISTINCT ml.cod_pus) AS high_risk_sites,
  ROUND(AVG(ml.ml_stockout_probability) * 100, 1) AS avg_risk_probability_pct,
  SUM(ml.ml_cantidad_reabastecimiento) AS total_recommended_rolls,
  CURRENT_TIMESTAMP() AS alert_timestamp,
  'ML HIGH-RISK STOCKOUT PREDICTIONS' AS alert_title,
  CONCAT(
    '🤖 ML FORECAST ALERT: ', 
    CAST(COUNT(DISTINCT ml.cod_pus) AS STRING), 
    ' sites predicted to have HIGH RISK (>70% probability) of stockout.\n\n',
    'SUMMARY:\n',
    '• High-Risk Sites: ', CAST(COUNT(DISTINCT ml.cod_pus) AS STRING), '\n',
    '• Avg Risk Probability: ', CAST(ROUND(AVG(ml.ml_stockout_probability) * 100, 1) AS STRING), '%\n',
    '• ML Recommended Rolls: ', FORMAT_NUMBER(CAST(SUM(ml.ml_cantidad_reabastecimiento) AS BIGINT), 0), '\n',
    '• Forecast Horizon: 30-60 days\n\n',
    'TOP 10 HIGHEST RISK SITES:\n',
    STRING_AGG(
      CONCAT(
        '• ', s.cod_pus, 
        ' - ', s.MUNICIPIO, ', ', s.DEPARTAMENTO,
        ' | Risk: ', CAST(ROUND(ml.ml_stockout_probability * 100, 1) AS STRING), '%',
        ' | Predicted Days: ', CAST(ROUND(ml.ml_predicted_saldo_dias, 1) AS STRING),
        ' | Recommended: ', CAST(ROUND(ml.ml_cantidad_reabastecimiento, 0) AS STRING), ' rolls'
      ),
      '\n'
    ) WITHIN GROUP (ORDER BY ml.ml_stockout_probability DESC LIMIT 10),
    '\n\n',
    'ACTION RECOMMENDED: Review ML predictions and plan preemptive restocking.\n',
    'Dashboard: [View ML Forecasts](#ml-forecasting-dashboard)'
  ) AS alert_message_body
FROM catalog_lcom.gold.ml_supply_chain_predictions ml
INNER JOIN catalog_lcom.silver.supply_chain_master s
  ON ml.cod_pus = s.cod_pus
WHERE ml.ml_stockout_probability > 0.70
HAVING COUNT(DISTINCT ml.cod_pus) > 20;

-- DATABRICKS ALERT CONFIGURATION:
-- Alert Settings:
--   - Name: ML_HIGH_RISK_STOCKOUT_PREDICTIONS
--   - Value Column: high_risk_sites
--   - Trigger Condition: Value > 20
--   - Schedule: Daily at 8:00 AM (0 8 * * *)
--   - Rearm: 24 hours
-- Notification Template:
--   Subject: "🤖 ML FORECAST - {{high_risk_sites}} High-Risk Sites Predicted"
--   Body: Use {{alert_message_body}} placeholder
-- Destinations:
--   - Email: analytics@company.com, planning@company.com


-- ============================================================================
-- ALERT TESTING & VALIDATION QUERIES
-- ============================================================================

-- Test Query: Check current alert trigger status
SELECT 
  'ALERT 1: Critical Stockout' AS alert_name,
  COUNT(DISTINCT cod_pus) AS current_value,
  CASE WHEN COUNT(DISTINCT cod_pus) > 0 THEN 'WOULD TRIGGER' ELSE 'OK' END AS status
FROM catalog_lcom.silver.supply_chain_master
WHERE saldo_dias_ajustado <= 0 OR T = 'DESABASTECIDO'

UNION ALL

SELECT 
  'ALERT 2: Urgent Replenishment' AS alert_name,
  COUNT(DISTINCT cod_pus) AS current_value,
  CASE WHEN COUNT(DISTINCT cod_pus) > 50 THEN 'WOULD TRIGGER' ELSE 'OK' END AS status
FROM catalog_lcom.silver.supply_chain_master
WHERE (ACCIÓN = 'REABASTECER' AND saldo_dias_ajustado BETWEEN 1 AND 7)

UNION ALL

SELECT 
  'ALERT 3: PO Execution Delay' AS alert_name,
  COUNT(*) AS current_value,
  CASE WHEN COUNT(*) > 0 THEN 'WOULD TRIGGER' ELSE 'OK' END AS status
FROM catalog_lcom.bronze.oc_agosto_raw
WHERE UPPER(TRIM(ESTADO)) != 'EJECUTADO_EXITOSO'
  AND DATEDIFF(
        HOUR,
        DATE_ADD(TO_TIMESTAMP(`FECHA_DE_SOLUCIÓN_(DD_MM_AAAA)`, 'dd/MM/yyyy HH:mm'), -2),
        CURRENT_TIMESTAMP()
      ) > 48;


-- ============================================================================
-- ALERT IMPLEMENTATION CHECKLIST
-- ============================================================================
/*
☐ 1. Create alerts in Databricks SQL UI
☐ 2. Configure email distribution lists
☐ 3. Set up Slack incoming webhooks
☐ 4. Define PagerDuty integration (for P1 alerts)
☐ 5. Test each alert with dummy data
☐ 6. Document escalation procedures
☐ 7. Set up alert monitoring dashboard
☐ 8. Train operations team on alert responses
☐ 9. Enable alerts in production
☐ 10. Schedule weekly alert effectiveness review
*/


-- ============================================================================
-- END OF AUTOMATED ALERTS CONFIGURATION
-- ============================================================================