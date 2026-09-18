# Databricks notebook source
# /// script
# [tool.databricks.environment]
# base_environment = "databricks_ai_v5"
# environment_version = "5"
# ///
# DBTITLE 1,Notebook Configuration and Imports
# Databricks notebook source
# TITLE: Bronze Layer - Raw Data Ingestion
# PURPOSE: Ingest raw Excel files into Bronze Delta tables with audit columns
# AUTHOR: Principal Big Data Engineer
# DATE: September 2026

# COMMAND ----------

from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    current_timestamp, input_file_name, lit, col, 
    to_date, regexp_replace, trim, when
)
from pyspark.sql.types import *
from delta.tables import DeltaTable
import re

# Widgets for parameterization
dbutils.widgets.text("catalog", "catalog_lcom", "Unity Catalog Name")
dbutils.widgets.text("schema", "supply_chain", "Schema Name")
dbutils.widgets.text("data_path", "/Workspace/Users/pao.m.328@gmail.com/BD_Project/data", "Data Source Path")

catalog_name = dbutils.widgets.get("catalog")
schema_name = dbutils.widgets.get("schema")
data_path = dbutils.widgets.get("data_path")

print(f"Configuration:")
print(f"  Catalog: {catalog_name}")
print(f"  Schema: {schema_name}")
print(f"  Data Path: {data_path}")

# COMMAND ----------

# DBTITLE 1,Install Required Libraries
# MAGIC %pip install openpyxl pandas scikit-learn xgboost lightgbm

# COMMAND ----------

# DBTITLE 1,Create Catalog and Schema
# COMMAND ----------

# Create Unity Catalog and Schema if not exists
spark.sql(f"CREATE CATALOG IF NOT EXISTS {catalog_name}")
spark.sql(f"USE CATALOG {catalog_name}")
spark.sql(f"CREATE SCHEMA IF NOT EXISTS {schema_name}")
spark.sql(f"USE SCHEMA {schema_name}")

print(f"✓ Catalog '{catalog_name}' and schema '{schema_name}' ready")

# Create bronze schema
spark.sql(f"CREATE SCHEMA IF NOT EXISTS {catalog_name}.bronze")
print(f"✓ Bronze schema created")

# COMMAND ----------

# DBTITLE 1,Helper Functions
# COMMAND ----------

def clean_column_name(name):
    """Clean column names for Delta compatibility (remove special chars)"""
    import re
    cleaned = name.strip()
    cleaned = re.sub(r'[\(\),;\{\}\=\t\n\r/]', '_', cleaned)
    cleaned = cleaned.replace(" ", "_")
    cleaned = re.sub(r'_+', '_', cleaned)  # collapse multiple underscores
    cleaned = cleaned.strip('_')  # remove leading/trailing underscores
    # Prefix with _ if starts with a digit
    if cleaned and cleaned[0].isdigit():
        cleaned = f"_{cleaned}"
    return cleaned

def read_excel_with_audit(file_path, sheet_name=None):
    """
    Read Excel file using pandas+openpyxl (serverless-compatible)
    and add audit columns. Converts to Spark DataFrame.
    Handles mixed-type columns by converting problematic ones to string.
    """
    import pandas as pd
    import numpy as np
    
    # Read with pandas using openpyxl engine
    if sheet_name:
        pdf = pd.read_excel(file_path, sheet_name=sheet_name, engine='openpyxl')
    else:
        pdf = pd.read_excel(file_path, engine='openpyxl')
    
    # Clean column names for Delta compatibility
    pdf.columns = [clean_column_name(str(c)) for c in pdf.columns]
    
    # Handle mixed-type columns: convert object columns with mixed types to string
    for col in pdf.columns:
        if pdf[col].dtype == 'object':
            # Check if column has datetime values mixed with strings
            if pdf[col].apply(lambda x: isinstance(x, (pd.Timestamp, type(pd.NaT)))).any():
                pdf[col] = pd.to_datetime(pdf[col], errors='coerce')
            else:
                pdf[col] = pdf[col].astype(str).replace('nan', None).replace('None', None)
        elif pd.api.types.is_datetime64_any_dtype(pdf[col]):
            pass  # Keep datetime columns as-is
        else:
            if pdf[col].isna().any():
                pdf[col] = pdf[col].where(pd.notna(pdf[col]), None)
    
    # Second pass: convert any remaining object columns to string for Arrow compatibility
    problematic = []
    for col in pdf.columns:
        if pdf[col].dtype == 'object':
            pdf[col] = pdf[col].apply(lambda x: str(x) if x is not None and not (isinstance(x, float) and np.isnan(x)) else None)
            problematic.append(col)
    
    if problematic:
        print(f"  Converted to string (mixed types): {problematic}")
    
    # Try direct conversion, fallback to all-string conversion
    try:
        df = spark.createDataFrame(pdf)
    except Exception:
        print(f"  Direct conversion failed, converting ALL columns to string...")
        for col in pdf.columns:
            if not pd.api.types.is_datetime64_any_dtype(pdf[col]):
                pdf[col] = pdf[col].astype(str).replace('nan', None).replace('None', None)
        df = spark.createDataFrame(pdf)
    
    # Add audit columns
    df_with_audit = df \
        .withColumn("ingestion_time", current_timestamp()) \
        .withColumn("source_file", lit(file_path.split("/")[-1]))
    
    return df_with_audit

def write_to_bronze(df, table_name):
    """
    Write DataFrame to Bronze layer as Delta table
    """
    full_table_name = f"{catalog_name}.bronze.{table_name}"
    
    df.write \
        .format("delta") \
        .mode("overwrite") \
        .option("overwriteSchema", "true") \
        .saveAsTable(full_table_name)
    
    print(f"✓ Written {df.count()} records to {full_table_name}")
    return full_table_name

# COMMAND ----------

# DBTITLE 1,Ingest Modelo BigData - Master Consumption History
# COMMAND ----------

print("=" * 80)
print("INGESTING: Modelo_bigdata.xlsx (Master Consumption History)")
print("=" * 80)

modelo_path = f"{data_path}/Modelo_bigdata.xlsx"
df_modelo = read_excel_with_audit(modelo_path)

# Clean column names
for column in df_modelo.columns:
    new_column = column.strip().replace(" ", "_").replace("\n", "_").replace("\r", "")
    df_modelo = df_modelo.withColumnRenamed(column, new_column)

print(f"Schema:")
df_modelo.printSchema()
print(f"\nSample data:")
df_modelo.show(5, truncate=False)

# Write to Bronze
modelo_table = write_to_bronze(df_modelo, "modelo_bigdata_raw")
print(f"✓ Modelo BigData ingested to {modelo_table}")

# COMMAND ----------

# DBTITLE 1,Ingest Purchase Orders - OC AGOSTO
# COMMAND ----------

print("=" * 80)
print("INGESTING: OC AGOSTO.xlsx (August Purchase Orders)")
print("=" * 80)

oc_path = f"{data_path}/OC AGOSTO.xlsx"
df_oc = read_excel_with_audit(oc_path, sheet_name="Hoja1")

# Clean column names
for column in df_oc.columns:
    new_column = column.strip().replace(" ", "_").replace("\n", "_").replace("\r", "")
    df_oc = df_oc.withColumnRenamed(column, new_column)

print(f"Schema:")
df_oc.printSchema()
print(f"\nSample data:")
df_oc.show(5, truncate=False)

# Write to Bronze
oc_table = write_to_bronze(df_oc, "oc_agosto_raw")
print(f"✓ Purchase Orders ingested to {oc_table}")

# COMMAND ----------

# DBTITLE 1,Ingest Current Stock - Stock LCOM Rollos
# COMMAND ----------

print("=" * 80)
print("INGESTING: Stock_LCOM_Rollos_2026-09-12.xlsx (Current Inventory)")
print("=" * 80)

stock_path = f"{data_path}/Stock_LCOM_Rollos_2026-09-12.xlsx"
df_stock = read_excel_with_audit(stock_path, sheet_name="Stock Completo")

# Clean column names
for column in df_stock.columns:
    new_column = column.strip().replace(" ", "_").replace("\n", "_").replace("\r", "").replace("/", "_")
    df_stock = df_stock.withColumnRenamed(column, new_column)

print(f"Schema:")
df_stock.printSchema()
print(f"\nSample data:")
df_stock.show(5, truncate=False)

# Write to Bronze
stock_table = write_to_bronze(df_stock, "stock_lcom_raw")
print(f"✓ Current Stock ingested to {stock_table}")

# COMMAND ----------

# DBTITLE 1,Verification and Statistics
# COMMAND ----------

print("=" * 80)
print("BRONZE LAYER INGESTION COMPLETE - VERIFICATION")
print("=" * 80)

# Verify all tables
tables_info = [
    ("modelo_bigdata_raw", "Master Consumption History"),
    ("oc_agosto_raw", "Purchase Orders August"),
    ("stock_lcom_raw", "Current Stock Inventory")
]

for table_name, description in tables_info:
    full_table = f"{catalog_name}.bronze.{table_name}"
    count = spark.table(full_table).count()
    print(f"✓ {description:40s} : {count:,} records")

print("\n" + "=" * 80)
print("BRONZE LAYER READY FOR SILVER TRANSFORMATIONS")
print("=" * 80)