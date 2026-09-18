# Databricks notebook source
# DBTITLE 1,Configuration and Imports
# Databricks notebook source
# TITLE: Gold Layer - ML Forecasting & Batch Inference
# PURPOSE: Train stockout risk classifier and demand forecasting models
# AUTHOR: Principal ML Engineer
# DATE: September 2026

# COMMAND ----------

import mlflow
import mlflow.sklearn
from mlflow.models import infer_signature

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, when, lit, current_timestamp
from pyspark.ml import Pipeline
from pyspark.ml.feature import VectorAssembler, StandardScaler, StringIndexer
from pyspark.ml.classification import RandomForestClassifier, GBTClassifier
from pyspark.ml.regression import RandomForestRegressor, GBTRegressor
from pyspark.ml.evaluation import BinaryClassificationEvaluator, MulticlassClassificationEvaluator, RegressionEvaluator

import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier as SKRandomForestClassifier
from sklearn.ensemble import GradientBoostingRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix, mean_absolute_error, mean_squared_error, r2_score
import warnings
warnings.filterwarnings('ignore')

# Widgets
dbutils.widgets.text("catalog", "catalog_lcom", "Unity Catalog Name")
dbutils.widgets.text("schema", "supply_chain", "Schema Name")
dbutils.widgets.text("experiment_name", "/Users/pao.m.328@gmail.com/BD_Project/supply_chain_forecasting", "MLflow Experiment")

catalog_name = dbutils.widgets.get("catalog")
schema_name = dbutils.widgets.get("schema")
experiment_name = dbutils.widgets.get("experiment_name")

spark.sql(f"USE CATALOG {catalog_name}")

print(f"Configuration:")
print(f"  Catalog: {catalog_name}")
print(f"  Schema: {schema_name}")
print(f"  Experiment: {experiment_name}")

# COMMAND ----------

# DBTITLE 1,Load Silver Data and Setup MLflow
# COMMAND ----------

print("=" * 80)
print("LOADING SILVER DATA & SETTING UP MLFLOW")
print("=" * 80)

# Load silver layer data
df_silver = spark.table(f"{catalog_name}.silver.supply_chain_master")

print(f"✓ Loaded silver data: {df_silver.count():,} records")

# Setup MLflow experiment
mlflow.set_experiment(experiment_name)
print(f"✓ MLflow experiment set: {experiment_name}")

# Create gold schema if not exists
spark.sql(f"CREATE SCHEMA IF NOT EXISTS {catalog_name}.gold")
print(f"✓ Gold schema ready")

# COMMAND ----------

# DBTITLE 1,Prepare ML Features - Stockout Classification
# COMMAND ----------

print("=" * 80)
print("PREPARING ML FEATURES - STOCKOUT RISK CLASSIFICATION")
print("=" * 80)

# Select features for stockout classification
feature_cols_class = [
    'prom_mensual_anterior',
    'PERIODO_ABAST_E-5',
    'ROLLOS_PERIODO_ABAST_E-5',
    'ROLLOS_AÑO_E-5',
    'ROLLOS_ENTREGADOS_DESDE_MIGRACIÓN_O_APERTURA',
    'TRX_DESDE_MIGRACIÓN_O_APERTURA',
    'ROLLOS_CONSUMIDOS_DESDE_MIGRACIÓN_O_APERTURA',
    'SALDO_ROLLOS',
    'SALDO_DIAS',
    'total_rollos_oc_agosto',
    'stock_actual_sistema',
    'tasa_consumo_diario',
    'demanda_proyectada_30d',
    'saldo_rollos_ajustado',
    'saldo_dias_ajustado',
    'eficiencia_consumo'
]

# Prepare classification dataset (target: requiere_reabastecimiento)
df_class = df_silver.select(
    ['cod_pus'] + feature_cols_class + ['requiere_reabastecimiento']
).na.fill(0)

# Convert to pandas for sklearn
pdf_class = df_class.toPandas()

X_class = pdf_class[feature_cols_class]
y_class = pdf_class['requiere_reabastecimiento']

print(f"✓ Classification features shape: {X_class.shape}")
print(f"✓ Target distribution:")
print(y_class.value_counts())
print(f"  Class balance: {y_class.mean()*100:.2f}% require restocking")

# COMMAND ----------

# DBTITLE 1,Train Stockout Risk Classifier
# COMMAND ----------

print("=" * 80)
print("TRAINING STOCKOUT RISK CLASSIFIER")
print("=" * 80)

# Split data
X_train_c, X_test_c, y_train_c, y_test_c = train_test_split(
    X_class, y_class, test_size=0.2, random_state=42, stratify=y_class
)

print(f"✓ Training set: {X_train_c.shape[0]} samples")
print(f"✓ Test set: {X_test_c.shape[0]} samples")

# Start MLflow run
with mlflow.start_run(run_name="stockout_risk_classifier") as run:
    
    # Train Random Forest Classifier
    clf = SKRandomForestClassifier(
        n_estimators=100,
        max_depth=10,
        min_samples_split=5,
        min_samples_leaf=2,
        random_state=42,
        n_jobs=-1
    )
    
    print("Training model...")
    clf.fit(X_train_c, y_train_c)
    
    # Predictions
    y_pred_c = clf.predict(X_test_c)
    y_pred_proba_c = clf.predict_proba(X_test_c)[:, 1]
    
    # Calculate metrics
    from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, roc_auc_score
    
    accuracy = accuracy_score(y_test_c, y_pred_c)
    precision = precision_score(y_test_c, y_pred_c)
    recall = recall_score(y_test_c, y_pred_c)
    f1 = f1_score(y_test_c, y_pred_c)
    auc = roc_auc_score(y_test_c, y_pred_proba_c)
    
    # Log parameters
    mlflow.log_param("model_type", "RandomForestClassifier")
    mlflow.log_param("n_estimators", 100)
    mlflow.log_param("max_depth", 10)
    mlflow.log_param("features", len(feature_cols_class))
    
    # Log metrics
    mlflow.log_metric("accuracy", accuracy)
    mlflow.log_metric("precision", precision)
    mlflow.log_metric("recall", recall)
    mlflow.log_metric("f1_score", f1)
    mlflow.log_metric("auc_roc", auc)
    
    # Feature importance
    feature_importance = pd.DataFrame({
        'feature': feature_cols_class,
        'importance': clf.feature_importances_
    }).sort_values('importance', ascending=False)
    
    print("\n✓ Model Performance:")
    print(f"  Accuracy:  {accuracy:.4f}")
    print(f"  Precision: {precision:.4f}")
    print(f"  Recall:    {recall:.4f}")
    print(f"  F1 Score:  {f1:.4f}")
    print(f"  AUC-ROC:   {auc:.4f}")
    
    print("\n✓ Top 10 Features:")
    print(feature_importance.head(10))
    
    # Confusion Matrix
    cm = confusion_matrix(y_test_c, y_pred_c)
    print("\n✓ Confusion Matrix:")
    print(cm)
    
    # Log model with signature
    signature = infer_signature(X_train_c, clf.predict(X_train_c))
    mlflow.sklearn.log_model(
        clf,
        "stockout_classifier",
        signature=signature,
        registered_model_name=f"{catalog_name}.{schema_name}.stockout_risk_classifier"
    )
    
    classifier_run_id = run.info.run_id
    print(f"\n✓ Model logged to MLflow with run_id: {classifier_run_id}")
    print(f"✓ Model registered: {catalog_name}.{schema_name}.stockout_risk_classifier")

# COMMAND ----------

# DBTITLE 1,Prepare Features - Demand Forecasting
# COMMAND ----------

print("=" * 80)
print("PREPARING FEATURES - DEMAND FORECASTING (SALDO DIAS)")
print("=" * 80)

# Select features for regression (predict remaining stock days)
feature_cols_reg = [
    'prom_mensual_anterior',
    'PERIODO_ABAST_E-5',
    'ROLLOS_PERIODO_ABAST_E-5',
    'ROLLOS_ENTREGADOS_DESDE_MIGRACIÓN_O_APERTURA',
    'TRX_DESDE_MIGRACIÓN_O_APERTURA',
    'ROLLOS_CONSUMIDOS_DESDE_MIGRACIÓN_O_APERTURA',
    'SALDO_ROLLOS',
    'total_rollos_oc_agosto',
    'stock_actual_sistema',
    'tasa_consumo_diario',
    'demanda_proyectada_30d',
    'saldo_rollos_ajustado',
    'eficiencia_consumo'
]

# Filter to sites with reasonable saldo_dias values (exclude extreme outliers)
df_reg = df_silver.filter(
    (col('saldo_dias_ajustado') >= 0) & 
    (col('saldo_dias_ajustado') <= 365)
).select(
    ['cod_pus'] + feature_cols_reg + ['saldo_dias_ajustado']
).na.fill(0)

pdf_reg = df_reg.toPandas()

X_reg = pdf_reg[feature_cols_reg]
y_reg = pdf_reg['saldo_dias_ajustado']

print(f"✓ Regression features shape: {X_reg.shape}")
print(f"✓ Target statistics:")
print(y_reg.describe())

# COMMAND ----------

# DBTITLE 1,Train Demand Forecasting Model
# COMMAND ----------

print("=" * 80)
print("TRAINING DEMAND FORECASTING MODEL (REMAINING STOCK DAYS)")
print("=" * 80)

# Split data
X_train_r, X_test_r, y_train_r, y_test_r = train_test_split(
    X_reg, y_reg, test_size=0.2, random_state=42
)

print(f"✓ Training set: {X_train_r.shape[0]} samples")
print(f"✓ Test set: {X_test_r.shape[0]} samples")

# Start MLflow run
with mlflow.start_run(run_name="demand_forecasting_regressor") as run:
    
    # Train Gradient Boosting Regressor
    reg = GradientBoostingRegressor(
        n_estimators=100,
        max_depth=8,
        learning_rate=0.1,
        min_samples_split=5,
        random_state=42
    )
    
    print("Training model...")
    reg.fit(X_train_r, y_train_r)
    
    # Predictions
    y_pred_r = reg.predict(X_test_r)
    
    # Calculate metrics
    mae = mean_absolute_error(y_test_r, y_pred_r)
    rmse = np.sqrt(mean_squared_error(y_test_r, y_pred_r))
    r2 = r2_score(y_test_r, y_pred_r)
    mape = np.mean(np.abs((y_test_r - y_pred_r) / (y_test_r + 1))) * 100
    
    # Log parameters
    mlflow.log_param("model_type", "GradientBoostingRegressor")
    mlflow.log_param("n_estimators", 100)
    mlflow.log_param("max_depth", 8)
    mlflow.log_param("learning_rate", 0.1)
    mlflow.log_param("features", len(feature_cols_reg))
    
    # Log metrics
    mlflow.log_metric("mae", mae)
    mlflow.log_metric("rmse", rmse)
    mlflow.log_metric("r2_score", r2)
    mlflow.log_metric("mape", mape)
    
    # Feature importance
    feature_importance_reg = pd.DataFrame({
        'feature': feature_cols_reg,
        'importance': reg.feature_importances_
    }).sort_values('importance', ascending=False)
    
    print("\n✓ Model Performance:")
    print(f"  MAE:       {mae:.2f} days")
    print(f"  RMSE:      {rmse:.2f} days")
    print(f"  R² Score:  {r2:.4f}")
    print(f"  MAPE:      {mape:.2f}%")
    
    print("\n✓ Top 10 Features:")
    print(feature_importance_reg.head(10))
    
    # Log model with signature
    signature = infer_signature(X_train_r, reg.predict(X_train_r))
    mlflow.sklearn.log_model(
        reg,
        "demand_forecaster",
        signature=signature,
        registered_model_name=f"{catalog_name}.{schema_name}.demand_forecasting_model"
    )
    
    regressor_run_id = run.info.run_id
    print(f"\n✓ Model logged to MLflow with run_id: {regressor_run_id}")
    print(f"✓ Model registered: {catalog_name}.{schema_name}.demand_forecasting_model")

# COMMAND ----------

# DBTITLE 1,Batch Inference - Apply Models
# COMMAND ----------

print("=" * 80)
print("BATCH INFERENCE - APPLYING MODELS TO FULL DATASET")
print("=" * 80)

# Load models for inference (in production, load from Unity Catalog)
# For now, we'll use the trained models from memory

# Prepare full dataset for inference
pdf_full = df_silver.select(
    ['cod_pus', 'DEPARTAMENTO', 'MUNICIPIO', 'SEDE_OPERACIONES', 'TIPOLOGIA_ROLLOS'] + 
    list(set(feature_cols_class + feature_cols_reg)) + 
    ['requiere_reabastecimiento', 'saldo_dias_ajustado', 'cantidad_reabastecimiento_optima']
).na.fill(0).toPandas()

# Classification predictions
X_inference_class = pdf_full[feature_cols_class]
stockout_risk_pred = clf.predict(X_inference_class)
stockout_risk_proba = clf.predict_proba(X_inference_class)[:, 1]

pdf_full['ml_stockout_risk_pred'] = stockout_risk_pred
pdf_full['ml_stockout_probability'] = stockout_risk_proba

# Regression predictions (only for valid range)
X_inference_reg = pdf_full[feature_cols_reg]
remaining_days_pred = reg.predict(X_inference_reg)
remaining_days_pred = np.clip(remaining_days_pred, 0, 365)  # Clip to reasonable range

pdf_full['ml_predicted_saldo_dias'] = remaining_days_pred

# Calculate optimal replenishment based on ML predictions
pdf_full['ml_cantidad_reabastecimiento'] = np.where(
    pdf_full['ml_stockout_risk_pred'] == 1,
    (pdf_full['demanda_proyectada_30d'] * 1.2).round(0),  # 20% safety stock
    0
)

print(f"✓ Batch inference complete for {len(pdf_full):,} sites")
print(f"\nML Predictions Summary:")
print(f"  Sites predicted to need restocking: {stockout_risk_pred.sum():,}")
print(f"  Average predicted remaining days: {remaining_days_pred.mean():.1f}")
print(f"  Total ML-recommended rolls: {pdf_full['ml_cantidad_reabastecimiento'].sum():,.0f}")

# COMMAND ----------

# DBTITLE 1,Write Gold Layer - ML Predictions
# COMMAND ----------

print("=" * 80)
print("WRITING GOLD LAYER - ML PREDICTIONS")
print("=" * 80)

# Convert back to Spark DataFrame
df_gold_ml = spark.createDataFrame(pdf_full)

# Add metadata
df_gold_ml = df_gold_ml \
    .withColumn("prediction_timestamp", current_timestamp()) \
    .withColumn("classifier_run_id", lit(classifier_run_id)) \
    .withColumn("regressor_run_id", lit(regressor_run_id))

# Write to Gold table
gold_table = f"{catalog_name}.gold.ml_supply_chain_predictions"

df_gold_ml.write \
    .format("delta") \
    .mode("overwrite") \
    .option("overwriteSchema", "true") \
    .option("delta.enableChangeDataFeed", "true") \
    .saveAsTable(gold_table)

print(f"✓ Written {df_gold_ml.count():,} records to {gold_table}")

# Create critical alerts view
spark.sql(f"""
CREATE OR REPLACE VIEW {catalog_name}.gold.ml_critical_alerts AS
SELECT 
    cod_pus,
    DEPARTAMENTO,
    MUNICIPIO,
    SEDE_OPERACIONES,
    TIPOLOGIA_ROLLOS,
    ml_stockout_probability,
    ml_predicted_saldo_dias,
    ml_cantidad_reabastecimiento,
    saldo_dias_ajustado as actual_saldo_dias,
    cantidad_reabastecimiento_optima as rule_based_cantidad,
    prediction_timestamp
FROM {gold_table}
WHERE ml_stockout_risk_pred = 1
ORDER BY ml_stockout_probability DESC, ml_predicted_saldo_dias ASC
""")

print(f"✓ Created view: {catalog_name}.gold.ml_critical_alerts")

print("\n" + "=" * 80)
print("GOLD ML LAYER COMPLETE - MODELS REGISTERED IN UNITY CATALOG")
print("=" * 80)
print(f"\n✓ Stockout Classifier: {catalog_name}.{schema_name}.stockout_risk_classifier")
print(f"✓ Demand Forecaster: {catalog_name}.{schema_name}.demand_forecasting_model")
print(f"✓ Predictions Table: {gold_table}")