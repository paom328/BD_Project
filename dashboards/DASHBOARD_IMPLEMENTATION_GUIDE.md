# LCOM Supply Chain Analytics Dashboard - Implementation Guide

## Overview

This guide covers the implementation of a 3-page Databricks Lakehouse Dashboard with automated SQL alerts for the LCOM supply chain analytics project.

**Catalog**: `catalog_lcom`  
**Schemas**: `bronze`, `silver`, `gold`  
**Compute**: Serverless SQL Warehouse (Photon-enabled)

---

## Dashboard Parameters (Global Filters)

All three pages share the following parameters, defined on each SQL file using `:param_name` syntax:

| Parameter | Type | Label | Default | Choices |
|-----------|------|-------|---------|--------|
| `p_departamento` | Multi-select | Departamento | CUNDINAMARCA | Dynamic from `supply_chain_master` |
| `p_municipio` | Multi-select | Municipio | ABEJORRAL | Dynamic from `supply_chain_master` |
| `p_tipologia` | Multi-select | Tipología Rollos | PRINCIPAL | PRINCIPAL, INTERMEDIA, LEJANA |

### Filter Pattern (used in all queries)

```sql
WHERE (COALESCE(ARRAY_SIZE(:p_departamento), 0) = 0 OR DEPARTAMENTO IN (:p_departamento))
  AND (COALESCE(ARRAY_SIZE(:p_municipio), 0) = 0 OR MUNICIPIO IN (:p_municipio))
  AND (COALESCE(ARRAY_SIZE(:p_tipologia), 0) = 0 OR TIPOLOGIA_ROLLOS IN (:p_tipologia))
```

When no values are selected, `ARRAY_SIZE` returns 0 and the filter is bypassed (all data shown).

### Setting Up in Dashboard UI

1. Open each SQL file in the Databricks SQL editor
2. Parameters appear as widgets at the top — configure each as Multi-select
3. For `p_departamento` and `p_municipio`, switch to **Query-Based Dropdown** in the dashboard builder:
   - Departamento query: `SELECT DISTINCT DEPARTAMENTO AS value, DEPARTAMENTO AS label FROM catalog_lcom.silver.supply_chain_master ORDER BY DEPARTAMENTO`
   - Municipio query: `SELECT DISTINCT MUNICIPIO AS value, MUNICIPIO AS label FROM catalog_lcom.silver.supply_chain_master ORDER BY MUNICIPIO`
4. Clear the default selection to show all data on initial load

---

## Page 1: Executive Supply Chain Overview

**File**: `PAGE_1_Executive_Overview.sql`  
**Data Source**: `catalog_lcom.silver.supply_chain_master`

| Widget | Title | Visualization | Key Metric |
|--------|-------|--------------|------------|
| 1.1 | Total Sites Covered | Counter (Blue) | `COUNT(DISTINCT cod_pus)` |
| 1.2 | Overall Stockout Rate | Counter (% Red/Yellow/Green) | `% where T = 'DESABASTECIDO'` |
| 1.3 | Roll Consumption vs Delivered | Counter (comparison) | Consumed vs Delivered YTD |
| 1.4 | Avg Remaining Stock Days | Counter + Gauge | `AVG(saldo_dias_ajustado)` |
| 1.5 | Critical Action Required | Counter (Red Alert) | Sites needing restocking |
| 1.6 | Geographic Risk Heatmap | Pivot/Heatmap | Dept × Municipio risk matrix |
| 1.7 | Supply vs Burn Rate Trend | Stacked Area / Dual-Axis | Monthly delivered vs consumed |
| 1.8 | Top 10 Critical Sites | Horizontal Bar | Lowest `saldo_dias_ajustado` |
| 1.9 | Risk Distribution | Donut Chart | Sites by `riesgo_desabastecimiento` |

### Notes
- Widget 1.7 uses `TRY_TO_DATE(SUBSTR(\`FECHA_MIGRACIÓN_O_APERTURA\`, 1, 10))` to handle mixed values (e.g., 'NO MIGRADO' strings)
- All accented column names use backtick quoting (e.g., \`ACCIÓN\`, \`FECHA_MIGRACIÓN_O_APERTURA\`)

---

## Page 2: ML Forecasting & Replenishment Planning

**File**: `PAGE_2_ML_Forecasting.sql`  
**Data Sources**: `catalog_lcom.gold.ml_supply_chain_predictions` + `catalog_lcom.silver.supply_chain_master`

| Widget | Title | Visualization | Key Metric |
|--------|-------|--------------|------------|
| 2.1a-d | ML Model Performance | 4 Counter cards | Predictions, high-risk, rolls, days |
| 2.2 | Stock Depletion Risk Matrix | Scatter/Bubble | Days vs Consumption, sized by stock |
| 2.3 | Replenishment Action Table | Data Grid (conditional fmt) | Priority-ranked sites |
| 2.4 | Burn Rate by Typology | Box Plot / Bar | Daily rate distribution |
| 2.5 | Forecast vs Actuals | Multi-series Line | 30/60/90-day projections |
| 2.6 | Predicted Stockout Timeline | Gantt-style | Sites by predicted stockout date |

### Key Column Mapping (Gold Table)

| Original (wrong) | Corrected |
|-------------------|-----------|
| `ml_stockout_risk_pred` | `ml_stockout_prediction` |
| `ml_cantidad_reabastecimiento` | `cantidad_reabastecimiento_optima` |
| `ml_predicted_saldo_dias` | `ml_predicted_days_remaining` |

---

## Page 3: Purchase Orders & Fulfillment Monitoring

**File**: `PAGE_3_Purchase_Orders.sql`  
**Data Source**: `catalog_lcom.bronze.oc_agosto_raw`

| Widget | Title | Visualization | Key Metric |
|--------|-------|--------------|------------|
| 3.1a-d | Order Execution KPIs | 4 Counter cards | Total, executed, rolls, resolution |
| 3.2 | Order Execution Status | Donut Chart | EJECUTADO_EXITOSO vs others |
| 3.3 | Resolution Lead Time | Horizontal Bar | Avg hours by department |
| 3.4 | Delivery Volume by City | Stacked Bar | Rolls by city × typology |
| 3.5 | Top Cities by Volume | Horizontal Bar | Top 15 cities by rolls delivered |
| 3.6 | Order Execution Timeline | Line + Area | Daily + cumulative orders |
| 3.7 | Delivery Performance | Grouped Bar | Execution rate by typology |
| 3.8 | Order Details Table | Data Grid | Full order listing (500 rows) |
| 3.9 | Fulfillment Funnel | Funnel Chart | Requested → Processed → Executed |
| 3.10 | Department Comparison | Heatmap Table | Performance score matrix |

### Notes
- `FECHA_DE_SOLUCIÓN_DD_MM_AAAA` is already a TIMESTAMP — no `TO_TIMESTAMP()` conversion needed
- Column name has no parentheses (cleaned during Delta ingestion)

---

## SQL Alerts (Automated Notifications)

**File**: `ALERTS_Automated_Notifications.sql`

### Alert 1: Critical Stockout Alert
- **Schedule**: Every 4 hours
- **Trigger**: `critical_sites_count > 0`
- **Query**: Sites where `saldo_dias_ajustado <= 0` OR `T = 'DESABASTECIDO'`
- **Destinations**: Email (operations team) + Slack (#supply-chain-alerts)

### Alert 2: Urgent Replenishment Threshold
- **Schedule**: Every 6 hours
- **Trigger**: `urgent_sites_count > 50`
- **Query**: Sites with `ACCIÓN = 'REABASTECER'` AND `saldo_dias_ajustado` between 1-7 days
- **Destinations**: Email (logistics) + Slack (#logistics-alerts)

### Alert 3: PO Execution Delay
- **Schedule**: Daily at 9 AM
- **Trigger**: `delayed_orders_count > 0`
- **Query**: Purchase orders exceeding 48-hour SLA without EJECUTADO_EXITOSO
- **Destinations**: Email (procurement team)

### Bonus Alert 4: ML High-Risk Predictions
- **Schedule**: Daily at 8 AM
- **Trigger**: `high_risk_sites > 20`
- **Query**: Sites with `ml_stockout_probability > 0.70`
- **Destinations**: Email (analytics team)

### Setup Instructions
1. Go to **SQL > Alerts > Create Alert**
2. Paste the alert query
3. Set the **Value** column and **Trigger** condition
4. Configure the refresh schedule
5. Add notification destinations (Email, Slack webhook, PagerDuty)
6. Test and enable

---

## SQL Syntax Notes

1. **Parameter syntax**: Use `:param_name` (not deprecated `{{param_name}}`)
2. **Accented columns**: Must use backtick quoting (e.g., \`ACCIÓN\`, \`FECHA_MIGRACIÓN_O_APERTURA\`)
3. **Mixed-type date columns**: Use `TRY_TO_DATE()` instead of `TO_DATE()` to handle non-date strings like 'NO MIGRADO'
4. **Timestamp columns**: Bronze table's `FECHA_DE_SOLUCIÓN_DD_MM_AAAA` is already TIMESTAMP type — reference directly without conversion
5. **ARRAY_SIZE for multiselect**: Use `COALESCE(ARRAY_SIZE(:param), 0) = 0` to handle empty/NULL parameter values

---

## README Snippet

```markdown
## LCOM Supply Chain Dashboard

A 3-page Databricks AI/BI Lakehouse dashboard providing end-to-end supply chain visibility:

- **Page 1 - Executive Overview**: KPI cards, geographic risk heatmap, supply vs consumption trends, top critical sites
- **Page 2 - ML Forecasting**: ML model performance, depletion risk matrix, replenishment planning table, 30/60/90-day forecasts
- **Page 3 - Purchase Orders**: Order execution rates, fulfillment lead times, delivery volume by city, order details grid

### Automated Alerts
- Critical stockout (every 4h) — sites at 0 days or DESABASTECIDO
- Urgent replenishment (every 6h) — 50+ sites needing restocking within 7 days
- PO execution delay (daily) — orders exceeding 48-hour SLA
- ML high-risk predictions (daily) — 20+ sites with >70% stockout probability

### Data Sources
- Silver: `catalog_lcom.silver.supply_chain_master` (17,655 sites)
- Gold: `catalog_lcom.gold.ml_supply_chain_predictions` (ML predictions)
- Bronze: `catalog_lcom.bronze.oc_agosto_raw` (August purchase orders, 1,234 records)
```