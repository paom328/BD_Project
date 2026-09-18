# Databricks notebook source
# DBTITLE 1,Configuration and Imports
# Databricks notebook source
# TITLE: Silver Layer - Data Transformations & Feature Engineering
# PURPOSE: Clean, join, and transform Bronze data into curated Silver tables
# AUTHOR: Principal Big Data Engineer
# DATE: September 2026
# NOTES: Replicates KNIME workflow logic for data cleaning and feature engineering

# COMMAND ----------

from pyspark.sql import SparkSession, Window
from pyspark.sql.functions import (
    col, lit, when, coalesce, trim, upper, regexp_replace,
    to_date, datediff, current_date, avg, sum as _sum, count,
    round as spark_round, abs as spark_abs, lag, lead,
    row_number, dense_rank, monotonically_increasing_id
)
from pyspark.sql.types import *
from delta.tables import DeltaTable
import re

# Widgets
dbutils.widgets.text("catalog", "catalog_lcom", "Unity Catalog Name")
dbutils.widgets.text("schema", "supply_chain", "Schema Name")

catalog_name = dbutils.widgets.get("catalog")
schema_name = dbutils.widgets.get("schema")

spark.sql(f"USE CATALOG {catalog_name}")

print(f"Configuration:")
print(f"  Catalog: {catalog_name}")
print(f"  Schema: {schema_name}")

# COMMAND ----------

# DBTITLE 1,Load Bronze Tables
# COMMAND ----------

print("=" * 80)
print("LOADING BRONZE LAYER TABLES")
print("=" * 80)

# Load bronze tables
df_modelo_bronze = spark.table(f"{catalog_name}.bronze.modelo_bigdata_raw")
df_oc_bronze = spark.table(f"{catalog_name}.bronze.oc_agosto_raw")
df_stock_bronze = spark.table(f"{catalog_name}.bronze.stock_lcom_raw")

print(f"✓ Modelo BigData: {df_modelo_bronze.count():,} records")
print(f"✓ Purchase Orders: {df_oc_bronze.count():,} records")
print(f"✓ Current Stock: {df_stock_bronze.count():,} records")

# COMMAND ----------

# DBTITLE 1,Clean Modelo BigData - Master Consumption
# COMMAND ----------

print("=" * 80)
print("CLEANING: Modelo BigData - Master Consumption History")
print("=" * 80)

# Clean and transform modelo bigdata
df_modelo_clean = df_modelo_bronze \
    .withColumn("cod_pus", col("cod_pus").cast("string")) \
    .withColumn("prom_mensual_anterior", 
                regexp_replace(col("prom_mensual_anterior"), ",", "").cast("double")) \
    .withColumn("DEPARTAMENTO", upper(trim(col("DEPARTAMENTO")))) \
    .withColumn("MUNICIPIO", upper(trim(col("MUNICIPIO")))) \
    .withColumn("SEDE_OPERACIONES", upper(trim(col("SEDE_OPERACIONES")))) \
    .withColumn("TIPOLOGIA_OPERACIONES", upper(trim(col("TIPOLOGIA_OPERACIONES")))) \
    .withColumn("SEDE_ROLLOS", upper(trim(col("SEDE_ROLLOS")))) \
    .withColumn("TIPOLOGIA_ROLLOS", upper(trim(col("TIPOLOGIA_ROLLOS")))) \
    .withColumn("PERIODO_ABAST_E-5", col("PERIODO_ABAST_E-5").cast("int")) \
    .withColumn("ROLLOS_PERIODO_ABAST_E-5", col("ROLLOS_PERIODO_ABAST_E-5").cast("int")) \
    .withColumn("ROLLOS_AÑO_E-5", col("ROLLOS_AÑO_E-5").cast("int")) \
    .withColumn("ROLLOS_ENTREGADOS_DESDE_MIGRACIÓN_O_APERTURA", 
                col("ROLLOS_ENTREGADOS_DESDE_MIGRACIÓN_O_APERTURA").cast("int")) \
    .withColumn("TRX_DESDE_MIGRACIÓN_O_APERTURA",
                regexp_replace(col("TRX_DESDE_MIGRACIÓN_O_APERTURA"), ",", "").cast("double")) \
    .withColumn("ROLLOS_CONSUMIDOS_DESDE_MIGRACIÓN_O_APERTURA",
                regexp_replace(col("ROLLOS_CONSUMIDOS_DESDE_MIGRACIÓN_O_APERTURA"), ",", "").cast("double")) \
    .withColumn("SALDO_ROLLOS",
                regexp_replace(col("SALDO_ROLLOS"), ",", "").cast("double")) \
    .withColumn("SALDO_DIAS",
                regexp_replace(col("SALDO_DIAS"), ",", "").cast("double")) \
    .withColumn("ACCIÓN", upper(trim(col("ACCIÓN")))) \
    .withColumn("T", upper(trim(col("T"))))

# Handle missing values - KNIME imputation logic
df_modelo_clean = df_modelo_clean \
    .withColumn("SALDO_DIAS", 
                when(col("SALDO_DIAS").isNull() | (col("SALDO_DIAS") < -365), 0)
                .otherwise(col("SALDO_DIAS"))) \
    .withColumn("SALDO_ROLLOS",
                when(col("SALDO_ROLLOS").isNull(), 0)
                .otherwise(col("SALDO_ROLLOS"))) \
    .withColumn("ACCIÓN",
                when(col("ACCIÓN").isNull(), "NO_ACTION")
                .otherwise(col("ACCIÓN"))) \
    .withColumn("T",
                when(col("T").isNull(), "NORMAL")
                .otherwise(col("T")))

print(f"✓ Cleaned Modelo BigData: {df_modelo_clean.count():,} records")
df_modelo_clean.show(5)

# COMMAND ----------

# DBTITLE 1,Clean Purchase Orders - OC AGOSTO
# COMMAND ----------

print("=" * 80)
print("CLEANING: Purchase Orders - OC AGOSTO")
print("=" * 80)

# Clean purchase orders
df_oc_clean = df_oc_bronze \
    .withColumn("cod_pus", col("cod_pus").cast("string")) \
    .withColumn("CIUDAD_SEDE", upper(trim(col("CIUDAD_SEDE")))) \
    .withColumn("DEPARTAMENTO", upper(trim(col("DEPARTAMENTO")))) \
    .withColumn("CIUDAD", upper(trim(col("CIUDAD")))) \
    .withColumn("TIPOLOGIA", upper(trim(col("TIPOLOGIA")))) \
    .withColumn("TIPOLOGIA_ROLLOS", upper(trim(col("TIPOLOGIA_ROLLOS")))) \
    .withColumn("ESTADO", upper(trim(col("ESTADO")))) \
    .withColumn("ROLLOS_ENTREGADOS", col("ROLLOS_ENTREGADOS").cast("int"))

# Parse fecha de solución
df_oc_clean = df_oc_clean \
    .withColumn("FECHA_SOLUCION", 
                to_date(col("FECHA_DE_SOLUCIÓN_(DD_MM_AAAA)"), "dd/MM/yyyy HH:mm"))

# Filter only successfully executed orders
df_oc_executed = df_oc_clean.filter(col("ESTADO") == "EJECUTADO_EXITOSO")

# Aggregate deliveries by cod_pus
df_oc_agg = df_oc_executed.groupBy("cod_pus").agg(
    _sum("ROLLOS_ENTREGADOS").alias("total_rollos_oc_agosto"),
    count("*").alias("num_ordenes_agosto"),
    max("FECHA_SOLUCION").alias("ultima_entrega_agosto")
)

print(f"✓ Cleaned Purchase Orders: {df_oc_agg.count():,} unique sites")
df_oc_agg.show(5)

# COMMAND ----------

# DBTITLE 1,Clean Current Stock - Stock LCOM
# COMMAND ----------

print("=" * 80)
print("CLEANING: Current Stock - Stock LCOM Rollos")
print("=" * 80)

# Clean current stock
df_stock_clean = df_stock_bronze \
    .withColumn("cod_pus", col("cod_pus").cast("string")) \
    .withColumn("ROLLOS_ENTREGADOS", col("ROLLOS_ENTREGADOS").cast("int")) \
    .withColumn("Nombre_ubicacion", upper(trim(col("Nombre_de_la_ubicación")))) \
    .withColumn("Tipo_ubicacion", upper(trim(col("Tipo_de_ubicación")))) \
    .withColumn("Categoria", upper(trim(col("Categoría")))) \
    .withColumn("Negocio", upper(trim(col("Negocio"))))

# Aggregate stock by cod_pus
df_stock_agg = df_stock_clean.groupBy("cod_pus").agg(
    _sum("ROLLOS_ENTREGADOS").alias("stock_actual_sistema"),
    count("*").alias("num_registros_stock")
)

print(f"✓ Cleaned Current Stock: {df_stock_agg.count():,} unique sites")
df_stock_agg.show(5)

# COMMAND ----------

# DBTITLE 1,Join All Datasets - Master Integration
# COMMAND ----------

print("=" * 80)
print("JOINING ALL DATASETS - MASTER INTEGRATION")
print("=" * 80)

# Join modelo with purchase orders
df_integrated = df_modelo_clean.join(
    df_oc_agg,
    on="cod_pus",
    how="left"
)

# Join with current stock
df_integrated = df_integrated.join(
    df_stock_agg,
    on="cod_pus",
    how="left"
)

# Fill nulls for sites without purchase orders or stock
df_integrated = df_integrated \
    .withColumn("total_rollos_oc_agosto", coalesce(col("total_rollos_oc_agosto"), lit(0))) \
    .withColumn("num_ordenes_agosto", coalesce(col("num_ordenes_agosto"), lit(0))) \
    .withColumn("stock_actual_sistema", coalesce(col("stock_actual_sistema"), lit(0))) \
    .withColumn("num_registros_stock", coalesce(col("num_registros_stock"), lit(0)))

print(f"✓ Integrated dataset: {df_integrated.count():,} records")
df_integrated.printSchema()

# COMMAND ----------

# DBTITLE 1,Feature Engineering - Business Logic
# COMMAND ----------

print("=" * 80)
print("FEATURE ENGINEERING - BUSINESS CALCULATIONS")
print("=" * 80)

# Calculate daily burn rate (average consumption per day)
df_featured = df_integrated \
    .withColumn("dias_desde_migracion",
                datediff(current_date(), to_date(col("FECHA_MIGRACIÓN_O_APERTURA"), "M/d/yy"))) \
    .withColumn("tasa_consumo_diario",
                when(col("dias_desde_migracion") > 0,
                     col("ROLLOS_CONSUMIDOS_DESDE_MIGRACIÓN_O_APERTURA") / col("dias_desde_migracion"))
                .otherwise(0)) \
    .withColumn("tasa_consumo_diario",
                when(col("tasa_consumo_diario").isNull(), 0)
                .otherwise(col("tasa_consumo_diario")))

# Projected demand for 30, 60, 90 days
df_featured = df_featured \
    .withColumn("demanda_proyectada_30d", spark_round(col("tasa_consumo_diario") * 30, 2)) \
    .withColumn("demanda_proyectada_60d", spark_round(col("tasa_consumo_diario") * 60, 2)) \
    .withColumn("demanda_proyectada_90d", spark_round(col("tasa_consumo_diario") * 90, 2))

# Adjusted remaining stock days (using actual system stock if available)
df_featured = df_featured \
    .withColumn("saldo_rollos_ajustado",
                when(col("stock_actual_sistema") > 0, col("stock_actual_sistema"))
                .otherwise(col("SALDO_ROLLOS"))) \
    .withColumn("saldo_dias_ajustado",
                when(col("tasa_consumo_diario") > 0,
                     spark_round(col("saldo_rollos_ajustado") / col("tasa_consumo_diario"), 1))
                .otherwise(999))

# Stockout risk classification
df_featured = df_featured \
    .withColumn("riesgo_desabastecimiento",
                when(col("saldo_dias_ajustado") <= 0, "CRITICO")
                .when(col("saldo_dias_ajustado") <= 7, "ALTO")
                .when(col("saldo_dias_ajustado") <= 15, "MEDIO")
                .when(col("saldo_dias_ajustado") <= 30, "BAJO")
                .otherwise("NORMAL")) \
    .withColumn("requiere_reabastecimiento",
                when((col("ACCIÓN") == "REABASTECER") | 
                     (col("T") == "DESABASTECIDO") | 
                     (col("saldo_dias_ajustado") <= 7), 1)
                .otherwise(0))

# Optimal replenishment quantity (based on monthly average and period)
df_featured = df_featured \
    .withColumn("cantidad_reabastecimiento_optima",
                when(col("requiere_reabastecimiento") == 1,
                     spark_round((col("prom_mensual_anterior") / 30) * 
                                col("PERIODO_ABAST_E-5"), 0))
                .otherwise(0))

# Stock efficiency metrics
df_featured = df_featured \
    .withColumn("eficiencia_consumo",
                when(col("ROLLOS_ENTREGADOS_DESDE_MIGRACIÓN_O_APERTURA") > 0,
                     spark_round(col("ROLLOS_CONSUMIDOS_DESDE_MIGRACIÓN_O_APERTURA") / 
                                col("ROLLOS_ENTREGADOS_DESDE_MIGRACIÓN_O_APERTURA") * 100, 2))
                .otherwise(0)) \
    .withColumn("dias_hasta_desabastecimiento",
                spark_round(col("saldo_dias_ajustado"), 0).cast("int"))

print(f"✓ Feature engineering complete: {df_featured.count():,} records")
print(f"\nNew features created:")
print("  - tasa_consumo_diario (daily burn rate)")
print("  - demanda_proyectada_30d/60d/90d")
print("  - saldo_dias_ajustado")
print("  - riesgo_desabastecimiento")
print("  - requiere_reabastecimiento")
print("  - cantidad_reabastecimiento_optima")
print("  - eficiencia_consumo")

# COMMAND ----------

# DBTITLE 1,Write to Silver Layer
# COMMAND ----------

print("=" * 80)
print("WRITING TO SILVER LAYER")
print("=" * 80)

# Create silver schema if not exists
spark.sql(f"CREATE SCHEMA IF NOT EXISTS {catalog_name}.silver")

# Write main silver table
silver_table = f"{catalog_name}.silver.supply_chain_master"

df_featured.write \
    .format("delta") \
    .mode("overwrite") \
    .option("overwriteSchema", "true") \
    .option("delta.enableChangeDataFeed", "true") \
    .saveAsTable(silver_table)

print(f"✓ Written {df_featured.count():,} records to {silver_table}")

# Create additional silver views for specific use cases
print("\nCreating silver views...")

# View 1: Critical sites requiring immediate action
spark.sql(f"""
CREATE OR REPLACE VIEW {catalog_name}.silver.critical_sites AS
SELECT 
    cod_pus,
    DEPARTAMENTO,
    MUNICIPIO,
    SEDE_OPERACIONES,
    TIPOLOGIA_ROLLOS,
    saldo_rollos_ajustado,
    saldo_dias_ajustado,
    tasa_consumo_diario,
    riesgo_desabastecimiento,
    cantidad_reabastecimiento_optima,
    ACCIÓN,
    T
FROM {silver_table}
WHERE requiere_reabastecimiento = 1
ORDER BY saldo_dias_ajustado ASC
""")

print(f"✓ Created view: {catalog_name}.silver.critical_sites")

# View 2: Inventory health by region
spark.sql(f"""
CREATE OR REPLACE VIEW {catalog_name}.silver.inventory_health_by_region AS
SELECT 
    DEPARTAMENTO,
    MUNICIPIO,
    COUNT(DISTINCT cod_pus) as total_sitios,
    SUM(CASE WHEN requiere_reabastecimiento = 1 THEN 1 ELSE 0 END) as sitios_criticos,
    ROUND(AVG(saldo_dias_ajustado), 2) as promedio_dias_stock,
    ROUND(SUM(saldo_rollos_ajustado), 0) as total_rollos_disponibles,
    ROUND(AVG(tasa_consumo_diario), 2) as tasa_consumo_promedio
FROM {silver_table}
GROUP BY DEPARTAMENTO, MUNICIPIO
ORDER BY sitios_criticos DESC, promedio_dias_stock ASC
""")

print(f"✓ Created view: {catalog_name}.silver.inventory_health_by_region")

print("\n" + "=" * 80)
print("SILVER LAYER READY FOR GOLD ML FORECASTING")
print("=" * 80)