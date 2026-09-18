# BD_PROJECT: Complete Workflow Architecture & Implementation Guide

## 🎯 Executive Summary

This document provides the complete end-to-end workflow architecture for the **BD_Project Supply Chain Analytics & ML Forecasting System**, integrating medallion architecture, machine learning forecasting, and executive dashboards with automated alerting.

**Project Scope:**
- **Data Sources:** Modelo_bigdata.xlsx, OC AGOSTO.xlsx, Stock_LCOM_Rollos_2026-09-12.xlsx, KNIME workflows
- **Architecture:** Medallion (Bronze → Silver → Gold) with ML integration
- **Analytics:** Executive dashboards, ML-powered forecasting, automated alerts
- **Catalog:** Unity Catalog (catalog_lcom.bronze, .silver, .gold, .supply_chain)

---

## 📊 Workflow Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DATA SOURCES (Excel Files)                          │
├─────────────────────────────────────────────────────────────────────────────┤
│  • Modelo_bigdata.xlsx        → Business model & KPIs                       │
│  • OC AGOSTO.xlsx             → Purchase orders (August 2026)               │
│  • Stock_LCOM_Rollos.xlsx    → Current inventory snapshot                  │
│  • KNIME Workflows            → ETL logic (translated to Spark/SQL)         │
└─────────────────────────────────────────────────────────────────────────────┘
                                       ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│                     TASK 1: BRONZE INGESTION (01_bronze_ingestion.py)       │
├─────────────────────────────────────────────────────────────────────────────┤
│  Purpose: Ingest raw Excel files into Unity Catalog Bronze layer            │
│  Operations:                                                                 │
│    • Read Excel files with openpyxl/pandas                                  │
│    • Add audit columns (ingestion_timestamp, source_file, row_hash)         │
│    • Write to Delta tables with ACID guarantees                             │
│  Output Tables:                                                              │
│    ✓ catalog_lcom.bronze.modelo_bigdata_raw                                │
│    ✓ catalog_lcom.bronze.oc_agosto_raw                                     │
│    ✓ catalog_lcom.bronze.stock_lcom_raw                                   │
│  SLA: < 10 minutes | Retry: 2 attempts | Timeout: 3600s                     │
└─────────────────────────────────────────────────────────────────────────────┘
                                       ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│                TASK 2: SILVER TRANSFORMATIONS (02_silver_transformations.py)│
├─────────────────────────────────────────────────────────────────────────────┤
│  Purpose: Apply KNIME logic, cleanse data, create master supply chain table │
│  Operations:                                                                 │
│    • Join Bronze tables (modelo + stock) on cod_pus                         │
│    • Calculate business metrics:                                             │
│        - saldo_dias_ajustado (days remaining)                               │
│        - tasa_consumo_diario (daily consumption rate)                       │
│        - cantidad_reabastecimiento_optima (optimal restock qty)             │
│        - riesgo_desabastecimiento (stockout risk level)                     │
│    • Implement KNIME decision rules (T status, ACCIÓN flags)                │
│    • Data quality: Remove duplicates, handle nulls, validate ranges         │
│  Output Tables:                                                              │
│    ✓ catalog_lcom.silver.supply_chain_master (MAIN TABLE)                  │
│    ✓ catalog_lcom.silver.modelo_bigdata_clean                              │
│    ✓ catalog_lcom.silver.oc_agosto_clean                                   │
│  SLA: < 15 minutes | Retry: 2 attempts | Timeout: 3600s                     │
└─────────────────────────────────────────────────────────────────────────────┘
                                       ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│              TASK 3: GOLD ML FORECASTING (03_gold_ml_forecasting.py)        │
├─────────────────────────────────────────────────────────────────────────────┤
│  Purpose: Train ML models, generate predictions, register models in MLflow  │
│  ML Models:                                                                  │
│    1. Stockout Risk Classifier (RandomForest / XGBoost)                     │
│        Input Features:                                                       │
│          • saldo_dias_ajustado, saldo_rollos_ajustado                       │
│          • tasa_consumo_diario, prom_mensual_anterior                       │
│          • TIPOLOGIA_ROLLOS (encoded), DEPARTAMENTO (encoded)               │
│        Output: ml_stockout_risk_pred (0/1), ml_stockout_probability (0-1)  │
│        Metrics: ROC-AUC, Precision, Recall, F1-Score                        │
│                                                                              │
│    2. Demand Forecasting Regressor (RandomForest / LightGBM)                │
│        Input Features: Same as above + historical trends                    │
│        Output: ml_predicted_saldo_dias, ml_cantidad_reabastecimiento        │
│        Metrics: MAE, RMSE, R²                                               │
│                                                                              │
│  MLflow Integration:                                                         │
│    • Log models, parameters, metrics to MLflow                              │
│    • Register models in catalog_lcom.supply_chain.* namespace              │
│    • Version tracking for model governance                                  │
│                                                                              │
│  Output Tables:                                                              │
│    ✓ catalog_lcom.gold.ml_supply_chain_predictions                         │
│    ✓ catalog_lcom.gold.ml_model_performance_metrics                        │
│  SLA: < 30 minutes | Retry: 1 attempt | Timeout: 7200s                      │
└─────────────────────────────────────────────────────────────────────────────┘
                                       ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│           TASK 4: GOLD KPI AGGREGATION (04_gold_kpis_aggregation.py)        │
├─────────────────────────────────────────────────────────────────────────────┤
│  Purpose: Calculate executive KPIs and create dashboard-ready aggregations  │
│  Aggregations:                                                               │
│    • Department-level summaries (total stock, avg days, risk counts)        │
│    • Municipality-level summaries                                            │
│    • Typology-level summaries (PRINCIPAL, INTERMEDIA, LEJANA)               │
│    • Time-series trends (daily/weekly stock changes)                        │
│    • Top N lists (critical sites, high-risk locations)                      │
│                                                                              │
│  Output Tables:                                                              │
│    ✓ catalog_lcom.gold.kpis_department_summary                             │
│    ✓ catalog_lcom.gold.kpis_municipality_summary                           │
│    ✓ catalog_lcom.gold.kpis_typology_summary                               │
│    ✓ catalog_lcom.gold.kpis_critical_sites                                 │
│  SLA: < 10 minutes | Retry: 2 attempts | Timeout: 1800s                     │
└─────────────────────────────────────────────────────────────────────────────┘
                                       ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│          TASK 5: DATA QUALITY CHECKS (05_data_quality_checks.py)            │
├─────────────────────────────────────────────────────────────────────────────┤
│  Purpose: Comprehensive data validation across all layers                   │
│  Validations:                                                                │
│    • Row count checks (Bronze → Silver → Gold reconciliation)               │
│    • Null checks (critical columns must be populated)                       │
│    • Range checks (saldo_dias_ajustado >= 0, probabilities 0-1)             │
│    • Referential integrity (FK checks between tables)                       │
│    • Outlier detection (Z-score > 3 for consumption rates)                  │
│    • Freshness checks (data < 24 hours old)                                 │
│                                                                              │
│  Output:                                                                     │
│    ✓ catalog_lcom.gold.data_quality_results                                │
│    ✓ Raises exceptions on critical failures (halts downstream processes)    │
│  SLA: < 5 minutes | Retry: 1 attempt | Timeout: 1800s                       │
└─────────────────────────────────────────────────────────────────────────────┘
                                       ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│                    DASHBOARDS & ANALYTICS (Databricks SQL)                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  PAGE 1: Executive Overview (PAGE_1_Executive_Overview.sql)                 │
│    • Total sites, critical stockouts, avg days remaining                    │
│    • Geographic risk heatmap (DEPARTAMENTO × MUNICIPIO)                     │
│    • Risk level distribution (donut chart)                                  │
│    • Stock depletion trends (time series)                                   │
│    • Top 10 critical sites table                                            │
│    • Filters: p_departamento, p_municipio, p_tipologia                      │
│                                                                              │
│  PAGE 2: ML Forecasting & Replenishment (PAGE_2_ML_Forecasting.sql)        │
│    • ML model performance summary (accuracy, predictions count)             │
│    • Stock depletion vs ML risk matrix (scatter/bubble chart)               │
│    • Replenishment requirement table (sortable, exportable)                 │
│    • Consumption variance analysis (forecast vs actual)                     │
│    • ML recommendations (quantities, priorities)                            │
│                                                                              │
│  PAGE 3: Purchase Orders & Fulfillment (PAGE_3_Purchase_Orders.sql)        │
│    • Order execution status summary (total, executed, delivered rolls)      │
│    • Order status distribution (donut chart)                                │
│    • Resolution lead time by department (bar chart)                         │
│    • Delivery volume by city (stacked bar)                                  │
│    • Order execution timeline (time series)                                 │
│                                                                              │
│  Dashboard Parameters (Shared across all pages):                            │
│    • p_departamento: Multi-select dropdown (values from supply_chain_master)│
│    • p_municipio: Multi-select dropdown (cascades from p_departamento)      │
│    • p_tipologia: Multi-select dropdown (PRINCIPAL, INTERMEDIA, LEJANA)     │
└─────────────────────────────────────────────────────────────────────────────┘
                                       ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│              AUTOMATED ALERTS (ALERTS_Automated_Notifications.sql)          │
├─────────────────────────────────────────────────────────────────────────────┤
│  ALERT 1: Critical Stockout Alert                                           │
│    • Trigger: critical_sites_count > 0 (saldo_dias <= 0)                    │
│    • Frequency: Every 4 hours                                               │
│    • Recipients: Operations Team, Supply Chain Managers                     │
│    • Channels: Email + Slack + SMS (P1 severity)                            │
│                                                                              │
│  ALERT 2: Urgent Replenishment Alert                                        │
│    • Trigger: urgent_sites_count > 50 (1-7 days remaining)                  │
│    • Frequency: Every 6 hours                                               │
│    • Recipients: Logistics Coordinators, Regional Managers                  │
│    • Channels: Email + Slack (P2 severity)                                  │
│                                                                              │
│  ALERT 3: Purchase Order Execution Delay Alert                              │
│    • Trigger: delayed_orders_count > 0 (>48h SLA breach)                    │
│    • Frequency: Daily at 9 AM                                               │
│    • Recipients: Procurement Team, Vendor Managers                          │
│    • Channels: Email (P2 severity)                                          │
│                                                                              │
│  ALERT 4: ML Model Drift Alert                                              │
│    • Trigger: model_accuracy_drop > 5% (vs baseline)                        │
│    • Frequency: Weekly (Mondays 8 AM)                                       │
│    • Recipients: Data Science Team, ML Engineers                            │
│    • Channels: Email (P3 severity)                                          │
│                                                                              │
│  ALERT 5: Data Quality Failure Alert                                        │
│    • Trigger: critical_checks_failed > 0                                    │
│    • Frequency: After every pipeline run                                    │
│    • Recipients: Data Engineering Team, Project Owner                       │
│    • Channels: Email + Slack (P1 severity)                                  │
└─────────────────────────────────────────────────────────────────────────────┘

---

## 🔧 Workflow Orchestration Configuration

### Job Configuration Summary

**Job Name:** `BD_Project_Supply_Chain_ETL_ML_Pipeline`

**Schedule:** Daily at 2:00 AM (Colombia Time - America/Bogota)
- Cron: `0 0 2 * * ?`
- Timezone: America/Bogota

**Task Dependencies (Sequential Execution):**

```
bronze_ingestion
       ↓
silver_transformations
       ↓
gold_ml_forecasting
       ↓
gold_kpis_aggregation
       ↓
data_quality_checks
```

**Cluster Configuration:**
- **Spark Version:** 14.3.x-scala2.12
- **Node Type:** i3.xlarge (or equivalent)
- **Workers:** 2 (autoscaling optional: 2-4)
- **Runtime:** Standard (or ML for ML tasks)
- **Data Security Mode:** Single User

**Email Notifications:**
- On Start: pao.m.328@gmail.com
- On Success: pao.m.328@gmail.com
- On Failure: pao.m.328@gmail.com (immediate alert)

**Retry Policy:**
- Bronze/Silver/Gold KPIs: 2 retries, 60s interval
- Gold ML: 1 retry, 120s interval (avoid model corruption)
- Data Quality: 1 retry, 60s interval

**Timeouts:**
- Bronze Ingestion: 1 hour (3600s)
- Silver Transformations: 1 hour (3600s)
- Gold ML Forecasting: 2 hours (7200s)
- Gold KPIs: 30 minutes (1800s)
- Data Quality: 30 minutes (1800s)
- **Total Job Timeout:** 8 hours (28800s)

**Concurrency:** Max 1 concurrent run (prevent data corruption)

---

## 📦 Project Directory Structure

```
BD_Project/
├── data/                                   # Raw data files (Excel sources)
│   ├── Modelo_bigdata.xlsx
│   ├── OC AGOSTO.xlsx
│   └── Stock_LCOM_Rollos_2026-09-12.xlsx
│
├── notebooks/                              # Databricks notebooks (PySpark/SQL)
│   ├── 01_bronze_ingestion.py             # Bronze layer ETL
│   ├── 02_silver_transformations.py       # Silver layer transformations + KNIME logic
│   ├── 03_gold_ml_forecasting.py          # ML model training & predictions
│   ├── 04_gold_kpis_aggregation.py        # Executive KPI calculations
│   └── 05_data_quality_checks.py          # Data validation & quality gates
│
├── dashboards/                             # Databricks SQL queries for dashboards
│   ├── PAGE_1_Executive_Overview.sql      # Executive summary page
│   ├── PAGE_2_ML_Forecasting.sql          # ML forecasting & replenishment
│   ├── PAGE_3_Purchase_Orders.sql         # Purchase order logistics
│   ├── ALERTS_Automated_Notifications.sql # All alert definitions (5 alerts)
│   └── DASHBOARD_IMPLEMENTATION_GUIDE.md  # Dashboard setup instructions
│
├── config/                                 # Configuration files
│   └── workflow_job_config.json           # Job orchestration definition
│
├── README.md                               # Project documentation (comprehensive)
└── WORKFLOW_ARCHITECTURE.md                # This file (workflow & architecture)
```

---

## 🚀 Deployment Instructions

### Step 1: Verify Data Files

```bash
# Ensure all Excel files are in the data/ directory
ls /Workspace/Users/pao.m.328@gmail.com/BD_Project/data/

# Expected output:
Modelo_bigdata.xlsx
OC AGOSTO.xlsx
Stock_LCOM_Rollos_2026-09-12.xlsx
```

### Step 2: Create Unity Catalog Schemas

```sql
-- Create catalog (if not exists)
CREATE CATALOG IF NOT EXISTS catalog_lcom;

-- Create schemas
CREATE SCHEMA IF NOT EXISTS catalog_lcom.bronze
  COMMENT 'Raw data ingestion layer - Excel files with audit columns';

CREATE SCHEMA IF NOT EXISTS catalog_lcom.silver
  COMMENT 'Cleaned and transformed data with KNIME business logic';

CREATE SCHEMA IF NOT EXISTS catalog_lcom.gold
  COMMENT 'Aggregated KPIs and ML predictions for analytics';

CREATE SCHEMA IF NOT EXISTS catalog_lcom.supply_chain
  COMMENT 'ML models and supply chain-specific objects';
```

### Step 3: Install Required Libraries (Cluster Init Script)

For Excel file processing, install these libraries on the cluster:

```python
# On cluster, install via notebook or init script:
%pip install openpyxl==3.1.2
%pip install pandas==2.0.3
%pip install scikit-learn==1.3.0
%pip install xgboost==2.0.3
%pip install lightgbm==4.1.0
%pip install mlflow==2.9.2

# Restart Python kernel
dbutils.library.restartPython()
```

**Alternative:** Create a cluster with these libraries pre-installed in the library configuration.

### Step 4: Run Notebooks Manually (Test Phase)

Before scheduling, test each notebook individually:

1. **Bronze Ingestion:** Run `01_bronze_ingestion.py`
   - Verify tables created in `catalog_lcom.bronze`
   - Check row counts match Excel files

2. **Silver Transformations:** Run `02_silver_transformations.py`
   - Verify `supply_chain_master` table created
   - Spot-check calculated fields (saldo_dias_ajustado, T status)

3. **Gold ML Forecasting:** Run `03_gold_ml_forecasting.py`
   - Verify ML models registered in MLflow
   - Check prediction table created
   - Review model metrics (ROC-AUC, RMSE)

4. **Gold KPIs:** Run `04_gold_kpis_aggregation.py`
   - Verify KPI summary tables created
   - Validate aggregation logic

5. **Data Quality:** Run `05_data_quality_checks.py`
   - Ensure all checks pass
   - Review any warnings

### Step 5: Create Databricks Job (Workflow Orchestration)

**Option A: Using Databricks UI**

1. Go to **Workflows** → **Jobs** → **Create Job**
2. Name: `BD_Project_Supply_Chain_ETL_ML_Pipeline`
3. Add 5 tasks in sequence (use JSON from `config/workflow_job_config.json`)
4. Configure dependencies: Task 2 depends on Task 1, Task 3 on Task 2, etc.
5. Set schedule: Daily at 2:00 AM (Colombia Time)
6. Configure email notifications
7. Save and test with **Run Now**

**Option B: Using Databricks CLI (Recommended for CI/CD)**

```bash
# From workspace terminal
databricks jobs create --json-file /Workspace/Users/pao.m.328@gmail.com/BD_Project/config/workflow_job_config.json

# Verify job created
databricks jobs list --output JSON | grep "BD_Project"

# Trigger manual run
databricks jobs run-now --job-id <JOB_ID>
```

### Step 6: Create Databricks SQL Dashboard

1. Go to **SQL** → **Dashboards** → **Create Dashboard**
2. Name: `Supply Chain Analytics - Executive Dashboard`
3. Create 3 pages/tabs:
   - **Page 1:** Executive Overview
   - **Page 2:** ML Forecasting & Replenishment
   - **Page 3:** Purchase Orders & Fulfillment

4. For each page, add widgets:
   - Copy SQL from `dashboards/PAGE_X_*.sql`
   - Create widgets (Counter, Chart, Table) for each query
   - Configure visualizations (colors, axes, legends)

5. Configure dashboard parameters:
   - `p_departamento`: Multi-select dropdown
     - Source query: `SELECT DISTINCT DEPARTAMENTO FROM catalog_lcom.silver.supply_chain_master ORDER BY DEPARTAMENTO`
   - `p_municipio`: Multi-select dropdown
     - Source query: `SELECT DISTINCT MUNICIPIO FROM catalog_lcom.silver.supply_chain_master ORDER BY MUNICIPIO`
   - `p_tipologia`: Multi-select dropdown
     - Source query: `SELECT DISTINCT TIPOLOGIA_ROLLOS FROM catalog_lcom.silver.supply_chain_master ORDER BY TIPOLOGIA_ROLLOS`

6. Set refresh schedule: **Every 6 hours** (or after job completion)

### Step 7: Configure Databricks SQL Alerts

1. Go to **SQL** → **Alerts** → **Create Alert**
2. For each alert in `ALERTS_Automated_Notifications.sql`:
   - Name: (e.g., CRITICAL_STOCKOUT_IMMEDIATE_ACTION)
   - Query: Copy SQL from alerts file
   - Value column: (e.g., critical_sites_count)
   - Trigger condition: (e.g., Value > 0)
   - Schedule: (e.g., Every 4 hours)
   - Notifications:
     - **Email:** operations-team@company.com
     - **Slack:** Webhook URL for #supply-chain-alerts
     - **PagerDuty:** (optional) For P1 alerts
3. Test each alert with **Send Test Notification**
4. Enable alert

### Step 8: Monitor & Maintain

**Daily Checks:**
- Job run status (check Workflows UI)
- Dashboard data freshness (last refresh timestamp)
- Alert notifications (any critical stockouts?)

**Weekly Reviews:**
- ML model performance metrics (accuracy, drift)
- Data quality trends (failure rates)
- Business KPIs (stockout reduction, forecast accuracy)

**Monthly Tasks:**
- Retrain ML models with updated data
- Review and adjust alert thresholds
- Optimize query performance (check query history)
- Update documentation for new features

---

## 📈 Success Metrics & KPIs

### Technical Metrics

1. **Pipeline Reliability:**
   - Job success rate: Target >99%
   - Average run duration: <60 minutes end-to-end
   - Data quality pass rate: >98%

2. **ML Model Performance:**
   - Stockout classifier ROC-AUC: >0.85
   - Demand forecasting MAE: <5 days
   - Model refresh frequency: Weekly

3. **Dashboard Performance:**
   - Query execution time: <10 seconds (95th percentile)
   - Dashboard refresh latency: <2 minutes
   - User engagement: >50 daily active users

### Business Metrics

1. **Inventory Optimization:**
   - Stockout incidents reduction: Target -30% in 3 months
   - Average inventory days: Maintain 15-30 days
   - Emergency restocking events: Reduce by 40%

2. **Supply Chain Efficiency:**
   - Purchase order fulfillment rate: >95%
   - Average resolution time: <48 hours
   - Forecast accuracy (MAPE): <10%

3. **Cost Savings:**
   - Reduced emergency shipping costs: Target 25% reduction
   - Inventory holding costs: Optimize buffer stock levels
   - Improved resource allocation: Data-driven decision making

---

## 🔍 Troubleshooting Guide

### Issue 1: Excel File Read Errors

**Error:** `ModuleNotFoundError: No module named 'openpyxl'`

**Solution:**
```python
%pip install openpyxl pandas
dbutils.library.restartPython()
```

### Issue 2: Unity Catalog Permissions

**Error:** `PERMISSION_DENIED: User does not have CREATE TABLE on schema`

**Solution:**
```sql
GRANT CREATE, USAGE ON SCHEMA catalog_lcom.bronze TO `pao.m.328@gmail.com`;
GRANT CREATE, USAGE ON SCHEMA catalog_lcom.silver TO `pao.m.328@gmail.com`;
GRANT CREATE, USAGE ON SCHEMA catalog_lcom.gold TO `pao.m.328@gmail.com`;
```

### Issue 3: ML Model Training Failures

**Error:** `OutOfMemoryError` during XGBoost training

**Solution:**
- Increase cluster size (4 workers instead of 2)
- Reduce feature dimensions (feature selection)
- Use data sampling for hyperparameter tuning

### Issue 4: Dashboard Queries Timeout

**Error:** SQL query exceeds 10-minute timeout

**Solution:**
- Create materialized views for complex aggregations
- Add indexes on frequently filtered columns
- Use incremental refresh strategy
- Optimize join conditions (broadcast small tables)

### Issue 5: Alert False Positives

**Issue:** Alert 2 (Urgent Replenishment) triggers too frequently

**Solution:**
- Adjust threshold from 50 to 75 sites
- Add time-of-day filtering (suppress alerts during off-hours)
- Implement alert rearm period (24 hours instead of 6 hours)

---

## 🎓 KNIME → Spark/SQL Mapping Reference

| KNIME Node | Spark/SQL Equivalent | Implementation Location |
|------------|---------------------|-------------------------|
| **Row Filter** | `WHERE` clause | 02_silver_transformations.py |
| **Joiner** | `JOIN` (left/inner) | 02_silver_transformations.py |
| **Math Formula** | `CASE WHEN`, arithmetic | 02_silver_transformations.py |
| **Column Rename** | `SELECT ... AS` | 02_silver_transformations.py |
| **Rule Engine** | `CASE WHEN ... END` | 02_silver_transformations.py (T, ACCIÓN) |
| **GroupBy** | `GROUP BY`, `SUM()`, `AVG()` | 04_gold_kpis_aggregation.py |
| **Sorter** | `ORDER BY` | All SQL queries |
| **Aggregator** | Window functions, `PARTITION BY` | 04_gold_kpis_aggregation.py |
| **Missing Value** | `COALESCE()`, `IFNULL()` | 02_silver_transformations.py |
| **String Manipulation** | `UPPER()`, `TRIM()`, `CONCAT()` | 02_silver_transformations.py |

**Key KNIME Logic Implemented:**

1. **T Status Calculation (Rule Engine):**
   ```sql
   CASE 
     WHEN saldo_dias_ajustado <= 0 THEN 'DESABASTECIDO'
     WHEN saldo_dias_ajustado BETWEEN 1 AND 3 THEN 'URGENTE'
     WHEN saldo_dias_ajustado BETWEEN 4 AND 7 THEN 'CRITICO'
     WHEN saldo_dias_ajustado BETWEEN 8 AND 15 THEN 'PRECAUCIÓN'
     WHEN saldo_dias_ajustado BETWEEN 16 AND 30 THEN 'ESTABLE'
     ELSE 'OK'
   END AS T
   ```

2. **ACCIÓN Flag (Rule Engine):**
   ```sql
   CASE 
     WHEN T IN ('DESABASTECIDO', 'URGENTE') THEN 'REABASTECER'
     WHEN T = 'CRITICO' THEN 'PLANIFICAR'
     ELSE 'MONITOREAR'
   END AS ACCIÓN
   ```

3. **Optimal Restock Calculation (Math Formula):**
   ```sql
   CASE 
     WHEN requiere_reabastecimiento = 1 
       THEN (tasa_consumo_diario * 30) - saldo_rollos_ajustado
     ELSE 0
   END AS cantidad_reabastecimiento_optima
   ```

---

## 🔐 Security & Governance

### Data Access Control

```sql
-- Read-only access for analysts
GRANT SELECT ON SCHEMA catalog_lcom.silver TO `analysts_group`;
GRANT SELECT ON SCHEMA catalog_lcom.gold TO `analysts_group`;

-- Write access for data engineers
GRANT ALL PRIVILEGES ON SCHEMA catalog_lcom.bronze TO `data_engineers_group`;
GRANT ALL PRIVILEGES ON SCHEMA catalog_lcom.silver TO `data_engineers_group`;

-- ML model access for data scientists
GRANT ALL PRIVILEGES ON SCHEMA catalog_lcom.supply_chain TO `data_scientists_group`;
```

### Data Lineage

Unity Catalog automatically tracks lineage:
- Bronze → Silver: JOIN operations
- Silver → Gold: Aggregations + ML predictions
- Gold → Dashboard: Query dependencies

View lineage:
1. Go to **Data Explorer**
2. Select table (e.g., catalog_lcom.gold.ml_supply_chain_predictions)
3. Click **Lineage** tab

### Audit Logging

All operations logged in Unity Catalog audit logs:
```sql
SELECT 
  event_time,
  user_identity,
  action_name,
  request_params
FROM system.access.audit
WHERE action_name IN ('createTable', 'updateTable', 'deleteTable')
  AND table_catalog = 'catalog_lcom'
ORDER BY event_time DESC
LIMIT 100;
```

---

## 📞 Support & Contacts

**Project Owner:** pao.m.328@gmail.com

**Key Stakeholders:**
- Operations Team: operations-team@company.com
- Supply Chain Managers: supply-chain@company.com
- Data Engineering: data-engineering@company.com
- ML/AI Team: ml-team@company.com

**Documentation:**
- Main README: [BD_Project/README.md](./README.md)
- Dashboard Guide: [dashboards/DASHBOARD_IMPLEMENTATION_GUIDE.md](./dashboards/DASHBOARD_IMPLEMENTATION_GUIDE.md)
- Workflow Config: [config/workflow_job_config.json](./config/workflow_job_config.json)

**External Resources:**
- Databricks Documentation: https://docs.databricks.com
- Unity Catalog Guide: https://docs.databricks.com/data-governance/unity-catalog/
- MLflow Documentation: https://mlflow.org/docs/latest/index.html
- Delta Lake Guide: https://docs.delta.io/latest/index.html

---

## ✅ Project Completion Checklist

### Phase 1: Setup & Configuration
- [x] Create Unity Catalog schemas (bronze, silver, gold, supply_chain)
- [x] Upload Excel files to BD_Project/data/ directory
- [x] Install required libraries on cluster
- [x] Configure cluster with appropriate node types and autoscaling

### Phase 2: Development
- [x] Develop Bronze ingestion notebook (01_bronze_ingestion.py)
- [x] Develop Silver transformations notebook (02_silver_transformations.py)
- [x] Develop Gold ML forecasting notebook (03_gold_ml_forecasting.py)
- [x] Develop Gold KPI aggregation notebook (04_gold_kpis_aggregation.py)
- [x] Develop Data Quality checks notebook (05_data_quality_checks.py)
- [x] Create dashboard SQL queries (PAGE_1, PAGE_2, PAGE_3)
- [x] Create alert definitions (5 automated alerts)

### Phase 3: Testing
- [ ] Test Bronze ingestion (validate row counts, schema)
- [ ] Test Silver transformations (validate KNIME logic, calculated fields)
- [ ] Test Gold ML (validate model metrics, prediction ranges)
- [ ] Test Gold KPIs (validate aggregations, business logic)
- [ ] Test Data Quality (simulate failures, validate error handling)
- [ ] End-to-end test (run all notebooks sequentially)

### Phase 4: Deployment
- [ ] Create Databricks Job with 5 tasks
- [ ] Configure job schedule (Daily 2 AM Colombia Time)
- [ ] Set up email notifications
- [ ] Test job with manual run
- [ ] Monitor first scheduled run

### Phase 5: Dashboard & Alerts
- [ ] Create Databricks SQL Dashboard (3 pages)
- [ ] Add widgets for all queries (KPI cards, charts, tables)
- [ ] Configure dashboard parameters (filters)
- [ ] Set dashboard refresh schedule (Every 6 hours)
- [ ] Create 5 SQL alerts
- [ ] Configure alert notifications (Email, Slack)
- [ ] Test each alert with manual trigger

### Phase 6: Documentation & Handover
- [x] Complete README.md with project overview
- [x] Complete WORKFLOW_ARCHITECTURE.md (this document)
- [x] Complete DASHBOARD_IMPLEMENTATION_GUIDE.md
- [x] Document KNIME → Spark/SQL mappings
- [ ] Create user training materials
- [ ] Conduct stakeholder demo
- [ ] Hand over to operations team

### Phase 7: Monitoring & Optimization
- [ ] Set up job monitoring dashboard
- [ ] Establish SLA baselines
- [ ] Monitor ML model performance weekly
- [ ] Review and optimize query performance
- [ ] Collect user feedback on dashboards
- [ ] Iterate and improve based on feedback

---

**Last Updated:** September 17, 2026  
**Version:** 1.0  
**Status:** ✅ Design & Implementation Complete | ⏳ Testing & Deployment In Progress