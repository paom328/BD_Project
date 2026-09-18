# Databricks notebook source
# DBTITLE 1,Configuration and Load Data
# Databricks notebook source
# TITLE: Gold Layer - KPI Aggregations for Dashboards
# PURPOSE: Create business-level aggregations for executive dashboards
# AUTHOR: Principal Big Data Engineer
# DATE: September 2026

# COMMAND ----------

from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col, count, sum as _sum, avg, max, min,
    round as spark_round, when, lit, current_date
)

dbutils.widgets.text("catalog", "catalog_lcom", "Unity Catalog Name")
dbutils.widgets.text("schema", "supply_chain", "Schema Name")

catalog_name = dbutils.widgets.get("catalog")
schema_name = dbutils.widgets.get("schema")

spark.sql(f"USE CATALOG {catalog_name}")

print("=" * 80)
print("GOLD LAYER - KPI AGGREGATIONS FOR EXECUTIVE DASHBOARDS")
print("=" * 80)

# Load silver and gold ML predictions
df_silver = spark.table(f"{catalog_name}.silver.supply_chain_master")
df_ml = spark.table(f"{catalog_name}.gold.ml_supply_chain_predictions")

print(f"✓ Loaded silver: {df_silver.count():,} records")
print(f"✓ Loaded ML predictions: {df_ml.count():,} records")

# COMMAND ----------

# DBTITLE 1,KPI 1 - Executive Summary Metrics
# COMMAND ----------

print("Creating KPI Table 1: Executive Summary Metrics")

# Calculate high-level KPIs
kpi_summary = df_silver.agg(
    count("cod_pus").alias("total_sitios"),
    _sum("ROLLOS_ENTREGADOS_DESDE_MIGRACIÓN_O_APERTURA").alias("total_rollos_entregados"),
    _sum("ROLLOS_CONSUMIDOS_DESDE_MIGRACIÓN_O_APERTURA").alias("total_rollos_consumidos"),
    _sum("saldo_rollos_ajustado").alias("total_rollos_disponibles"),
    _sum(when(col("requiere_reabastecimiento") == 1, 1).otherwise(0)).alias("sitios_criticos"),
    _sum(when(col("saldo_dias_ajustado") <= 7, 1).otherwise(0)).alias("sitios_menos_7_dias"),
    _sum("total_rollos_oc_agosto").alias("rollos_entregados_agosto"),
    spark_round(avg("tasa_consumo_diario"), 2).alias("tasa_consumo_diario_promedio"),
    spark_round(avg("saldo_dias_ajustado"), 1).alias("promedio_dias_stock"),
    _sum("cantidad_reabastecimiento_optima").alias("cantidad_reabastecimiento_total")
).withColumn("fecha_calculo", current_date())

# Add calculated percentages
kpi_summary = kpi_summary \
    .withColumn("porcentaje_sitios_criticos", 
                spark_round((col("sitios_criticos") / col("total_sitios")) * 100, 2)) \
    .withColumn("eficiencia_consumo_global",
                spark_round((col("total_rollos_consumidos") / col("total_rollos_entregados")) * 100, 2))

# Write to gold
kpi_summary.write \
    .format("delta") \
    .mode("overwrite") \
    .saveAsTable(f"{catalog_name}.gold.kpi_executive_summary")

print(f"✓ Created: {catalog_name}.gold.kpi_executive_summary")
kpi_summary.show(truncate=False)

# COMMAND ----------

# DBTITLE 1,KPI 2 - Geographical Distribution
# COMMAND ----------

print("Creating KPI Table 2: Geographical Distribution by Department and Municipality")

kpi_geo = df_silver.groupBy("DEPARTAMENTO", "MUNICIPIO").agg(
    count("cod_pus").alias("total_sitios"),
    _sum("ROLLOS_CONSUMIDOS_DESDE_MIGRACIÓN_O_APERTURA").alias("consumo_total"),
    _sum("saldo_rollos_ajustado").alias("stock_actual"),
    spark_round(avg("tasa_consumo_diario"), 2).alias("consumo_diario_promedio"),
    spark_round(avg("saldo_dias_ajustado"), 1).alias("dias_stock_promedio"),
    _sum(when(col("requiere_reabastecimiento") == 1, 1).otherwise(0)).alias("sitios_criticos"),
    _sum(when(col("riesgo_desabastecimiento") == "CRITICO", 1).otherwise(0)).alias("riesgo_critico"),
    _sum(when(col("riesgo_desabastecimiento") == "ALTO", 1).otherwise(0)).alias("riesgo_alto"),
    _sum(when(col("riesgo_desabastecimiento") == "MEDIO", 1).otherwise(0)).alias("riesgo_medio")
).withColumn("fecha_calculo", current_date()) \
 .withColumn("porcentaje_sitios_criticos",
             spark_round((col("sitios_criticos") / col("total_sitios")) * 100, 2))

kpi_geo.write \
    .format("delta") \
    .mode("overwrite") \
    .saveAsTable(f"{catalog_name}.gold.kpi_geographical_distribution")

print(f"✓ Created: {catalog_name}.gold.kpi_geographical_distribution")
kpi_geo.orderBy(col("sitios_criticos").desc()).show(10)

# COMMAND ----------

# DBTITLE 1,KPI 3 - Inventory by Roll Typology
# COMMAND ----------

print("Creating KPI Table 3: Inventory Analysis by Roll Typology")

kpi_typology = df_silver.groupBy("TIPOLOGIA_ROLLOS", "SEDE_ROLLOS").agg(
    count("cod_pus").alias("total_sitios"),
    _sum("ROLLOS_ENTREGADOS_DESDE_MIGRACIÓN_O_APERTURA").alias("rollos_entregados"),
    _sum("ROLLOS_CONSUMIDOS_DESDE_MIGRACIÓN_O_APERTURA").alias("rollos_consumidos"),
    _sum("saldo_rollos_ajustado").alias("stock_actual"),
    spark_round(avg("tasa_consumo_diario"), 2).alias("tasa_consumo_diario"),
    _sum(when(col("requiere_reabastecimiento") == 1, 1).otherwise(0)).alias("sitios_requieren_reabast"),
    _sum("cantidad_reabastecimiento_optima").alias("cantidad_reabast_total")
).withColumn("fecha_calculo", current_date()) \
 .withColumn("eficiencia_consumo",
             spark_round((col("rollos_consumidos") / col("rollos_entregados")) * 100, 2))

kpi_typology.write \
    .format("delta") \
    .mode("overwrite") \
    .saveAsTable(f"{catalog_name}.gold.kpi_inventory_by_typology")

print(f"✓ Created: {catalog_name}.gold.kpi_inventory_by_typology")
kpi_typology.show()

# COMMAND ----------

# DBTITLE 1,KPI 4 - Time-Series Depletion Tracking
# COMMAND ----------

print("Creating KPI Table 4: Inventory Depletion Time-Series")

# Group sites by remaining stock days buckets
kpi_depletion = df_silver.withColumn(
    "bucket_dias_stock",
    when(col("saldo_dias_ajustado") <= 0, "0: Desabastecido")
    .when(col("saldo_dias_ajustado") <= 7, "1-7: Critico")
    .when(col("saldo_dias_ajustado") <= 15, "8-15: Alto Riesgo")
    .when(col("saldo_dias_ajustado") <= 30, "16-30: Medio Riesgo")
    .when(col("saldo_dias_ajustado") <= 60, "31-60: Bajo Riesgo")
    .otherwise("60+: Normal")
).groupBy("bucket_dias_stock").agg(
    count("cod_pus").alias("total_sitios"),
    _sum("saldo_rollos_ajustado").alias("stock_disponible"),
    _sum("cantidad_reabastecimiento_optima").alias("reabastecimiento_necesario")
).withColumn("fecha_calculo", current_date())

kpi_depletion.write \
    .format("delta") \
    .mode("overwrite") \
    .saveAsTable(f"{catalog_name}.gold.kpi_inventory_depletion")

print(f"✓ Created: {catalog_name}.gold.kpi_inventory_depletion")
kpi_depletion.orderBy("bucket_dias_stock").show()

# COMMAND ----------

# DBTITLE 1,KPI 5 - ML Model Performance Tracking
# COMMAND ----------

print("Creating KPI Table 5: ML Model Performance Comparison")

# Compare rule-based vs ML predictions
kpi_ml_comparison = df_ml.groupBy().agg(
    count("cod_pus").alias("total_sitios"),
    _sum("requiere_reabastecimiento").alias("rule_based_criticos"),
    _sum("ml_stockout_risk_pred").alias("ml_predicted_criticos"),
    spark_round(avg("ml_stockout_probability"), 4).alias("avg_stockout_probability"),
    spark_round(avg("saldo_dias_ajustado"), 2).alias("actual_avg_saldo_dias"),
    spark_round(avg("ml_predicted_saldo_dias"), 2).alias("ml_predicted_avg_saldo_dias"),
    _sum("cantidad_reabastecimiento_optima").alias("rule_based_reabast_total"),
    _sum("ml_cantidad_reabastecimiento").alias("ml_reabast_total")
).withColumn("fecha_calculo", current_date()) \
 .withColumn("diferencia_predicciones",
             col("ml_predicted_criticos") - col("rule_based_criticos")) \
 .withColumn("diferencia_cantidad",
             col("ml_reabast_total") - col("rule_based_reabast_total"))

kpi_ml_comparison.write \
    .format("delta") \
    .mode("overwrite") \
    .saveAsTable(f"{catalog_name}.gold.kpi_ml_performance")

print(f"✓ Created: {catalog_name}.gold.kpi_ml_performance")
kpi_ml_comparison.show(truncate=False)

# COMMAND ----------

# DBTITLE 1,Summary Report
# COMMAND ----------

print("=" * 80)
print("GOLD KPI LAYER COMPLETE")
print("=" * 80)

print("\nCreated Gold KPI Tables:")
print(f"  1. {catalog_name}.gold.kpi_executive_summary")
print(f"  2. {catalog_name}.gold.kpi_geographical_distribution")
print(f"  3. {catalog_name}.gold.kpi_inventory_by_typology")
print(f"  4. {catalog_name}.gold.kpi_inventory_depletion")
print(f"  5. {catalog_name}.gold.kpi_ml_performance")

print("\n✓ All KPI tables ready for Lakehouse Dashboard consumption")
print("=" * 80)