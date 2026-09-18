# BD_PROJECT: Quick Reference Card

**Last Updated:** September 17, 2026  
**Project Status:** ✅ Design & Implementation Complete | ⏳ Ready for Testing

---

## 📁 Key File Locations

### Notebooks
```
/Workspace/Users/pao.m.328@gmail.com/BD_Project/notebooks/
├── 01_bronze_ingestion.py.py
├── 02_silver_transformations.py.py
├── 03_gold_ml_forecasting.py.py
├── 04_gold_kpis_aggregation.py.py
└── 05_data_quality_checks.py.py
```

### Dashboards & SQL
```
/Workspace/Users/pao.m.328@gmail.com/BD_Project/dashboards/
├── PAGE_1_Executive_Overview.sql
├── PAGE_2_ML_Forecasting.sql
├── PAGE_3_Purchase_Orders.sql
└── ALERTS_Automated_Notifications.sql
```

### Documentation
```
/Workspace/Users/pao.m.328@gmail.com/BD_Project/
├── README.md                          (15 pages - Project overview)
├── WORKFLOW_ARCHITECTURE.md           (25 pages - Complete workflow guide)
├── PROJECT_STATUS_SUMMARY.md          (8 pages - Current status)
└── QUICK_REFERENCE.md                 (This file)
```

---

## 🚀 Quick Start Commands

### 1. Create Unity Catalog Schemas

```sql
-- Run in Databricks SQL Editor
CREATE CATALOG IF NOT EXISTS catalog_lcom;

CREATE SCHEMA IF NOT EXISTS catalog_lcom.bronze
  COMMENT 'Raw data ingestion layer';

CREATE SCHEMA IF NOT EXISTS catalog_lcom.silver
  COMMENT 'Cleaned and transformed data';

CREATE SCHEMA IF NOT EXISTS catalog_lcom.gold
  COMMENT 'Aggregated KPIs and ML predictions';

CREATE SCHEMA IF NOT EXISTS catalog_lcom.supply_chain
  COMMENT 'ML models and supply chain objects';

-- Verify schemas created
SHOW SCHEMAS IN catalog_lcom;
```

### 2. Create Cluster with Libraries

**Option A: Via Databricks UI**

1. Go to **Compute** → **Create Cluster**
2. Configuration:
   - **Name:** `bd_project_cluster`
   - **Policy:** Unrestricted (or your workspace policy)
   - **Access Mode:** Single User
   - **Databricks Runtime:** 14.3 LTS ML (or latest stable)
   - **Node Type:** `i3.xlarge` (or `Standard_DS3_v2` on Azure)
   - **Workers:** 2 (min) to 4 (max) with autoscaling
   - **Spot Instances:** Optional (for cost savings)

3. **Libraries Tab** → Add PyPI packages:
   ```
   openpyxl==3.1.2
   pandas==2.0.3
   scikit-learn==1.3.0
   xgboost==2.0.3
   lightgbm==4.1.0
   mlflow==2.9.2
   ```

4. Click **Create Cluster** and wait for it to start (~5 minutes)

**Option B: Via Databricks CLI (if available)**

```bash
# Create cluster config file
cat > cluster_config.json << EOF
{
  "cluster_name": "bd_project_cluster",
  "spark_version": "14.3.x-scala2.12",
  "node_type_id": "i3.xlarge",
  "num_workers": 2,
  "autoscale": {
    "min_workers": 2,
    "max_workers": 4
  },
  "libraries": [
    {"pypi": {"package": "openpyxl==3.1.2"}},
    {"pypi": {"package": "pandas==2.0.3"}},
    {"pypi": {"package": "scikit-learn==1.3.0"}},
    {"pypi": {"package": "xgboost==2.0.3"}},
    {"pypi": {"package": "lightgbm==4.1.0"}}
  ]
}
EOF

# Create cluster
databricks clusters create --json-file cluster_config.json
```

### 3. Run Notebooks Manually (Testing)

Attach each notebook to `bd_project_cluster` and run sequentially:

1. **Bronze Ingestion:**
   ```
   Open: /Users/pao.m.328@gmail.com/BD_Project/notebooks/01_bronze_ingestion.py.py
   Select Cluster: bd_project_cluster
   Click: Run All
   Expected Duration: ~5-10 minutes
   ```

2. **Silver Transformations:**
   ```
   Open: 02_silver_transformations.py.py
   Run All
   Expected Duration: ~10-15 minutes
   ```

3. **Gold ML Forecasting:**
   ```
   Open: 03_gold_ml_forecasting.py.py
   Run All
   Expected Duration: ~20-30 minutes (includes ML training)
   ```

4. **Gold KPIs:**
   ```
   Open: 04_gold_kpis_aggregation.py.py
   Run All
   Expected Duration: ~5-10 minutes
   ```

5. **Data Quality:**
   ```
   Open: 05_data_quality_checks.py.py
   Run All
   Expected Duration: ~3-5 minutes
   ```

### 4. Verify Table Creation

```sql
-- Check Bronze tables
SHOW TABLES IN catalog_lcom.bronze;
SELECT COUNT(*) FROM catalog_lcom.bronze.modelo_bigdata_raw;
SELECT COUNT(*) FROM catalog_lcom.bronze.oc_agosto_raw;
SELECT COUNT(*) FROM catalog_lcom.bronze.stock_lcom_raw;

-- Check Silver master table
SHOW TABLES IN catalog_lcom.silver;
SELECT COUNT(*), COUNT(DISTINCT cod_pus) FROM catalog_lcom.silver.supply_chain_master;
SELECT * FROM catalog_lcom.silver.supply_chain_master LIMIT 10;

-- Check Gold ML predictions
SHOW TABLES IN catalog_lcom.gold;
SELECT COUNT(*) FROM catalog_lcom.gold.ml_supply_chain_predictions;
SELECT * FROM catalog_lcom.gold.ml_supply_chain_predictions
WHERE ml_stockout_probability > 0.7
ORDER BY ml_stockout_probability DESC
LIMIT 10;

-- Check Gold KPIs
SELECT * FROM catalog_lcom.gold.kpis_department_summary;

-- Check Data Quality results
SELECT * FROM catalog_lcom.gold.data_quality_results
ORDER BY check_timestamp DESC;
```

---

## 🔄 Create Databricks Job (Workflow)

### Via Databricks UI

1. Go to **Workflows** → **Jobs** → **Create Job**
2. **Job Name:** `BD_Project_Supply_Chain_ETL_ML_Pipeline`
3. Add 5 tasks:

#### Task 1: Bronze Ingestion
- **Task name:** `bronze_ingestion`
- **Type:** Notebook
- **Notebook path:** `/Users/pao.m.328@gmail.com/BD_Project/notebooks/01_bronze_ingestion.py`
- **Cluster:** Use existing `bd_project_cluster`
- **Timeout:** 3600 seconds (1 hour)
- **Retries:** 2

#### Task 2: Silver Transformations
- **Task name:** `silver_transformations`
- **Type:** Notebook
- **Notebook path:** `/Users/pao.m.328@gmail.com/BD_Project/notebooks/02_silver_transformations.py`
- **Depends on:** `bronze_ingestion`
- **Cluster:** Use existing `bd_project_cluster`
- **Timeout:** 3600 seconds
- **Retries:** 2

#### Task 3: Gold ML Forecasting
- **Task name:** `gold_ml_forecasting`
- **Type:** Notebook
- **Notebook path:** `/Users/pao.m.328@gmail.com/BD_Project/notebooks/03_gold_ml_forecasting.py`
- **Depends on:** `silver_transformations`
- **Cluster:** Use existing `bd_project_cluster`
- **Timeout:** 7200 seconds (2 hours)
- **Retries:** 1

#### Task 4: Gold KPI Aggregation
- **Task name:** `gold_kpis_aggregation`
- **Type:** Notebook
- **Notebook path:** `/Users/pao.m.328@gmail.com/BD_Project/notebooks/04_gold_kpis_aggregation.py`
- **Depends on:** `gold_ml_forecasting`
- **Cluster:** Use existing `bd_project_cluster`
- **Timeout:** 1800 seconds (30 min)
- **Retries:** 2

#### Task 5: Data Quality Checks
- **Task name:** `data_quality_checks`
- **Type:** Notebook
- **Notebook path:** `/Users/pao.m.328@gmail.com/BD_Project/notebooks/05_data_quality_checks.py`
- **Depends on:** `gold_kpis_aggregation`
- **Cluster:** Use existing `bd_project_cluster`
- **Timeout:** 1800 seconds
- **Retries:** 1

4. **Schedule Tab:**
   - **Trigger:** Scheduled
   - **Quartz cron:** `0 0 2 * * ?` (Daily at 2 AM)
   - **Timezone:** America/Bogota
   - **Pause status:** Unpaused

5. **Notifications Tab:**
   - **On start:** pao.m.328@gmail.com
   - **On success:** pao.m.328@gmail.com
   - **On failure:** pao.m.328@gmail.com

6. Click **Create** and then **Run Now** to test

---

## 📊 Create Dashboard

### Step-by-Step

1. Go to **SQL** → **Dashboards** → **Create Dashboard**
2. **Name:** `Supply Chain Analytics - Executive Dashboard`
3. **Description:** `Real-time supply chain monitoring with ML-powered forecasting`

### Add Dashboard Parameters (Filters)

1. Click **Add** → **Parameter**
2. Create 3 parameters:

#### Parameter 1: Department Filter
- **Name:** `p_departamento`
- **Type:** Query dropdown
- **Query:**
  ```sql
  SELECT DISTINCT DEPARTAMENTO AS value
  FROM catalog_lcom.silver.supply_chain_master
  WHERE DEPARTAMENTO IS NOT NULL
  ORDER BY DEPARTAMENTO
  ```
- **Multi-select:** Enabled
- **Default:** (All)

#### Parameter 2: Municipality Filter
- **Name:** `p_municipio`
- **Type:** Query dropdown
- **Query:**
  ```sql
  SELECT DISTINCT MUNICIPIO AS value
  FROM catalog_lcom.silver.supply_chain_master
  WHERE MUNICIPIO IS NOT NULL
  ORDER BY MUNICIPIO
  ```
- **Multi-select:** Enabled
- **Default:** (All)

#### Parameter 3: Typology Filter
- **Name:** `p_tipologia`
- **Type:** Query dropdown
- **Query:**
  ```sql
  SELECT DISTINCT TIPOLOGIA_ROLLOS AS value
  FROM catalog_lcom.silver.supply_chain_master
  WHERE TIPOLOGIA_ROLLOS IS NOT NULL
  ORDER BY TIPOLOGIA_ROLLOS
  ```
- **Multi-select:** Enabled
- **Default:** (All)

### Add Pages (Tabs)

1. **PAGE 1: Executive Overview**
   - Copy queries from `dashboards/PAGE_1_Executive_Overview.sql`
   - Create widgets: KPI cards, heatmap, donut chart, line chart, table

2. **PAGE 2: ML Forecasting & Replenishment**
   - Copy queries from `dashboards/PAGE_2_ML_Forecasting.sql`
   - Create widgets: ML metrics, scatter plot, replenishment table

3. **PAGE 3: Purchase Orders & Fulfillment**
   - Copy queries from `dashboards/PAGE_3_Purchase_Orders.sql`
   - Create widgets: Order status, lead time, delivery volume

### Dashboard Refresh Schedule

1. Click **Schedule** tab
2. **Refresh every:** 6 hours
3. **Start time:** 3:00 AM (1 hour after job completes)
4. Click **Save**

---

## 🔔 Create SQL Alerts

### Alert 1: Critical Stockout

1. Go to **SQL** → **Alerts** → **Create Alert**
2. **Name:** `CRITICAL_STOCKOUT_IMMEDIATE_ACTION`
3. **Query:** Copy from `ALERTS_Automated_Notifications.sql` (Alert 1)
4. **Trigger:** `critical_sites_count` > 0
5. **Schedule:** Every 4 hours (0 */4 * * *)
6. **Notifications:**
   - Email: pao.m.328@gmail.com, operations-team@company.com
   - Slack: (webhook URL if available)
7. **Rearm:** 4 hours
8. Click **Create** and **Enable**

### Alert 2: Urgent Replenishment

- **Name:** `URGENT_REPLENISHMENT_THRESHOLD_EXCEEDED`
- **Trigger:** `urgent_sites_count` > 50
- **Schedule:** Every 6 hours
- (Follow same steps as Alert 1)

### Alert 3-5: PO Delay, ML Drift, Data Quality

Follow same pattern for remaining 3 alerts using queries from `ALERTS_Automated_Notifications.sql`

---

## 🔍 Monitoring & Troubleshooting

### Check Job Run Status

```sql
-- View recent job runs (via Databricks SQL)
SELECT *
FROM system.workflows.jobs
WHERE job_name = 'BD_Project_Supply_Chain_ETL_ML_Pipeline'
ORDER BY created_time DESC
LIMIT 10;
```

Or go to **Workflows** → **Jobs** → Select job → **Runs** tab

### Check Data Freshness

```sql
-- Check when tables were last updated
DESCRIBE HISTORY catalog_lcom.silver.supply_chain_master;
DESCRIBE HISTORY catalog_lcom.gold.ml_supply_chain_predictions;

-- Check latest ingestion timestamp
SELECT MAX(ingestion_timestamp) AS last_ingestion
FROM catalog_lcom.bronze.stock_lcom_raw;
```

### Check ML Model Versions

```python
import mlflow
from mlflow.tracking import MlflowClient

client = MlflowClient()

# List all versions of stockout classifier
for mv in client.search_model_versions("name='catalog_lcom.supply_chain.stockout_risk_classifier'"):
    print(f"Version: {mv.version}, Status: {mv.current_stage}, Run ID: {mv.run_id}")
```

### Check Data Quality Results

```sql
SELECT 
  check_name,
  check_status,
  rows_checked,
  rows_failed,
  failure_rate,
  check_timestamp
FROM catalog_lcom.gold.data_quality_results
WHERE check_status = 'FAILED'
ORDER BY check_timestamp DESC;
```

---

## 📞 Support Contacts

- **Project Owner:** pao.m.328@gmail.com
- **Databricks Support:** [https://help.databricks.com](https://help.databricks.com)
- **Community Forum:** [https://community.databricks.com](https://community.databricks.com)

---

## 📚 Documentation Links

### Internal Documentation
- [README.md](./README.md)
- [WORKFLOW_ARCHITECTURE.md](./WORKFLOW_ARCHITECTURE.md)
- [PROJECT_STATUS_SUMMARY.md](./PROJECT_STATUS_SUMMARY.md)
- [dashboards/DASHBOARD_IMPLEMENTATION_GUIDE.md](./dashboards/DASHBOARD_IMPLEMENTATION_GUIDE.md)

### Databricks Documentation
- [Unity Catalog](https://docs.databricks.com/data-governance/unity-catalog/)
- [Workflows (Jobs)](https://docs.databricks.com/workflows/)
- [SQL Dashboards](https://docs.databricks.com/sql/user/dashboards/)
- [SQL Alerts](https://docs.databricks.com/sql/user/alerts/)
- [MLflow](https://docs.databricks.com/mlflow/)
- [Delta Lake](https://docs.databricks.com/delta/)

---

## ⚡ Common Issues & Fixes

### Issue: "No module named 'openpyxl'"

**Fix:** Install library on cluster (see Section 2 above)

### Issue: "Table not found: catalog_lcom.bronze.xxx"

**Fix:** Run Bronze ingestion notebook first, or create schemas (see Section 1)

### Issue: "Permission denied on schema catalog_lcom.silver"

**Fix:**
```sql
GRANT CREATE, USAGE ON SCHEMA catalog_lcom.silver TO `pao.m.328@gmail.com`;
```

### Issue: "ML model training takes too long (>1 hour)"

**Fix:** Reduce hyperparameter search space or increase cluster size to 4+ workers

### Issue: "Dashboard queries timeout after 10 minutes"

**Fix:**
- Use SQL Warehouse with larger cluster size
- Create materialized views for complex aggregations
- Add partitioning and Z-ordering on frequently filtered columns

---

## ✅ Deployment Checklist

- [ ] Unity Catalog schemas created
- [ ] Cluster created with libraries installed
- [ ] All 5 notebooks tested individually
- [ ] Job created with 5 tasks and dependencies
- [ ] Job scheduled (Daily 2 AM)
- [ ] Job notifications configured
- [ ] First job run successful
- [ ] Dashboard created with 3 pages
- [ ] Dashboard parameters configured
- [ ] Dashboard refresh schedule set
- [ ] 5 SQL alerts created and enabled
- [ ] Alert notifications tested
- [ ] Documentation reviewed by stakeholders
- [ ] Training completed for end users
- [ ] Monitoring dashboard set up
- [ ] Support procedures documented

---

**Version:** 1.0  
**Last Updated:** September 17, 2026  
**Status:** ✅ Ready for Production Deployment