# Databricks notebook source
# DBTITLE 1,Configuration and Setup
# Databricks notebook source
# TITLE: Data Quality Checks & Assertions
# PURPOSE: Validate data quality across Bronze, Silver, and Gold layers
# AUTHOR: Principal Big Data Engineer
# DATE: September 2026

# COMMAND ----------

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, count, sum as _sum, avg, min, max, isnan, isnull, when
import sys

dbutils.widgets.text("catalog", "catalog_lcom", "Unity Catalog Name")
dbutils.widgets.text("schema", "supply_chain", "Schema Name")

catalog_name = dbutils.widgets.get("catalog")
schema_name = dbutils.widgets.get("schema")

spark.sql(f"USE CATALOG {catalog_name}")

print("=" * 80)
print("DATA QUALITY CHECKS & ASSERTIONS")
print("=" * 80)

# Track quality check results
quality_results = []

# COMMAND ----------

# DBTITLE 1,Bronze Layer Quality Checks
# COMMAND ----------

print("\nBRONZE LAYER - Quality Checks")
print("-" * 80)

# Check 1: Bronze tables exist and have data
bronze_tables = [
    "modelo_bigdata_raw",
    "oc_agosto_raw",
    "stock_lcom_raw"
]

for table in bronze_tables:
    try:
        df = spark.table(f"{catalog_name}.bronze.{table}")
        row_count = df.count()
        
        assert row_count > 0, f"Table {table} has no data"
        
        quality_results.append({
            "layer": "Bronze",
            "check": f"{table}_row_count",
            "status": "PASS",
            "value": row_count,
            "message": f"{row_count:,} records"
        })
        print(f"✓ {table}: {row_count:,} records")
        
    except Exception as e:
        quality_results.append({
            "layer": "Bronze",
            "check": f"{table}_existence",
            "status": "FAIL",
            "value": 0,
            "message": str(e)
        })
        print(f"✗ {table}: ERROR - {str(e)}")

print("✓ Bronze layer existence checks complete")

# COMMAND ----------

# DBTITLE 1,Silver Layer Quality Checks
# COMMAND ----------

print("\nSILVER LAYER - Quality Checks")
print("-" * 80)

# Load silver master table
df_silver = spark.table(f"{catalog_name}.silver.supply_chain_master")

# Check 2: Silver table has data
silver_count = df_silver.count()
assert silver_count > 0, "Silver table has no data"
print(f"✓ Silver table row count: {silver_count:,}")

# Check 3: No duplicate cod_pus
duplicate_count = df_silver.groupBy("cod_pus").count().filter(col("count") > 1).count()
if duplicate_count == 0:
    quality_results.append({"layer": "Silver", "check": "duplicates", "status": "PASS", "value": 0, "message": "No duplicates"})
    print(f"✓ No duplicate cod_pus")
else:
    quality_results.append({"layer": "Silver", "check": "duplicates", "status": "FAIL", "value": duplicate_count, "message": f"{duplicate_count} duplicates found"})
    print(f"✗ WARNING: {duplicate_count} duplicate cod_pus found")

# Check 4: Required columns not null
required_cols = ["cod_pus", "DEPARTAMENTO", "MUNICIPIO", "TIPOLOGIA_ROLLOS"]
for col_name in required_cols:
    null_count = df_silver.filter(col(col_name).isNull()).count()
    if null_count == 0:
        quality_results.append({"layer": "Silver", "check": f"{col_name}_not_null", "status": "PASS", "value": 0, "message": "No nulls"})
        print(f"✓ {col_name}: No nulls")
    else:
        quality_results.append({"layer": "Silver", "check": f"{col_name}_not_null", "status": "WARN", "value": null_count, "message": f"{null_count} nulls"})
        print(f"⚠ {col_name}: {null_count} nulls found")

# Check 5: Numeric columns in valid range
negative_stock = df_silver.filter(col("saldo_rollos_ajustado") < -100).count()
if negative_stock == 0:
    quality_results.append({"layer": "Silver", "check": "stock_range", "status": "PASS", "value": 0, "message": "Stock in valid range"})
    print(f"✓ Stock values in valid range")
else:
    quality_results.append({"layer": "Silver", "check": "stock_range", "status": "WARN", "value": negative_stock, "message": f"{negative_stock} sites with highly negative stock"})
    print(f"⚠ {negative_stock} sites with stock < -100")

print("✓ Silver layer quality checks complete")

# COMMAND ----------

# DBTITLE 1,Gold Layer Quality Checks
# COMMAND ----------

print("\nGOLD LAYER - Quality Checks")
print("-" * 80)

# Check 6: Gold ML predictions table
df_gold_ml = spark.table(f"{catalog_name}.gold.ml_supply_chain_predictions")
gold_ml_count = df_gold_ml.count()

assert gold_ml_count > 0, "Gold ML predictions table has no data"
print(f"✓ Gold ML predictions: {gold_ml_count:,} records")

# Check 7: ML predictions within valid range
invalid_proba = df_gold_ml.filter(
    (col("ml_stockout_probability") < 0) | (col("ml_stockout_probability") > 1)
).count()

if invalid_proba == 0:
    quality_results.append({"layer": "Gold", "check": "ml_proba_range", "status": "PASS", "value": 0, "message": "Probabilities in [0,1]"})
    print(f"✓ ML probabilities in valid range [0, 1]")
else:
    quality_results.append({"layer": "Gold", "check": "ml_proba_range", "status": "FAIL", "value": invalid_proba, "message": "Invalid probabilities"})
    print(f"✗ {invalid_proba} records with invalid ML probabilities")

# Check 8: Gold KPI tables exist
kpi_tables = [
    "kpi_executive_summary",
    "kpi_geographical_distribution",
    "kpi_inventory_by_typology",
    "kpi_inventory_depletion",
    "kpi_ml_performance"
]

for table in kpi_tables:
    try:
        df_kpi = spark.table(f"{catalog_name}.gold.{table}")
        kpi_count = df_kpi.count()
        quality_results.append({"layer": "Gold", "check": f"{table}_exists", "status": "PASS", "value": kpi_count, "message": f"{kpi_count} records"})
        print(f"✓ {table}: {kpi_count} records")
    except Exception as e:
        quality_results.append({"layer": "Gold", "check": f"{table}_exists", "status": "FAIL", "value": 0, "message": str(e)})
        print(f"✗ {table}: ERROR - {str(e)}")

print("✓ Gold layer quality checks complete")

# COMMAND ----------

# DBTITLE 1,Business Logic Validation
# COMMAND ----------

print("\nBUSINESS LOGIC VALIDATION")
print("-" * 80)

# Check 9: Sites flagged as critical should have low stock days
df_silver_check = spark.table(f"{catalog_name}.silver.supply_chain_master")

critical_but_high_stock = df_silver_check.filter(
    (col("requiere_reabastecimiento") == 1) & (col("saldo_dias_ajustado") > 30)
).count()

if critical_but_high_stock == 0:
    quality_results.append({"layer": "Business Logic", "check": "critical_flag_consistency", "status": "PASS", "value": 0, "message": "Flags consistent"})
    print(f"✓ Critical flags consistent with stock levels")
else:
    quality_results.append({"layer": "Business Logic", "check": "critical_flag_consistency", "status": "WARN", "value": critical_but_high_stock, "message": f"{critical_but_high_stock} inconsistent flags"})
    print(f"⚠ {critical_but_high_stock} sites flagged critical but have >30 days stock")

# Check 10: Consumption rate reasonableness
unreasonable_consumption = df_silver_check.filter(
    col("tasa_consumo_diario") > 1000
).count()

if unreasonable_consumption == 0:
    quality_results.append({"layer": "Business Logic", "check": "consumption_rate", "status": "PASS", "value": 0, "message": "Reasonable rates"})
    print(f"✓ Consumption rates within reasonable bounds")
else:
    quality_results.append({"layer": "Business Logic", "check": "consumption_rate", "status": "WARN", "value": unreasonable_consumption, "message": f"{unreasonable_consumption} high rates"})
    print(f"⚠ {unreasonable_consumption} sites with consumption rate > 1000 rolls/day")

print("✓ Business logic validation complete")

# COMMAND ----------

# DBTITLE 1,Summary Report
# COMMAND ----------

print("\n" + "=" * 80)
print("DATA QUALITY SUMMARY REPORT")
print("=" * 80)

# Convert results to DataFrame
df_results = spark.createDataFrame(quality_results)

# Count by status
status_summary = df_results.groupBy("status").count().collect()

print("\nQuality Check Status:")
for row in status_summary:
    print(f"  {row['status']}: {row['count']}")

# Show all checks
print("\nDetailed Results:")
df_results.orderBy("layer", "check").show(100, truncate=False)

# Determine overall status
failed_checks = df_results.filter(col("status") == "FAIL").count()
warning_checks = df_results.filter(col("status") == "WARN").count()

if failed_checks > 0:
    print(f"\n✗ DATA QUALITY: FAILED ({failed_checks} critical issues)")
    dbutils.notebook.exit("FAILED")
elif warning_checks > 0:
    print(f"\n⚠ DATA QUALITY: PASSED WITH WARNINGS ({warning_checks} warnings)")
    dbutils.notebook.exit("WARNING")
else:
    print(f"\n✓ DATA QUALITY: PASSED (All checks successful)")
    dbutils.notebook.exit("SUCCESS")

print("=" * 80)