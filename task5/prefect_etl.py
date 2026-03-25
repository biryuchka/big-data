from prefect import flow, task
from prefect.cache_policies import NO_CACHE

from pyspark.sql import SparkSession
from pyspark.sql import functions as F


HDFS_SALES_PATH = "/user/hive/warehouse/demo.db/sales"


@task(cache_policy=NO_CACHE)
def start_spark():
    spark = (
        SparkSession.builder
        .master("yarn")
        .appName("prefect_etl")
        .config("spark.sql.warehouse.dir", "/user/hive/warehouse")
        .config("hive.metastore.uris", "thrift://192.168.10.9:9083")
        .enableHiveSupport()
        .getOrCreate()
    )
    return spark


@task(cache_policy=NO_CACHE)
def extract(spark):
    schema = "id INT, product STRING, amount DOUBLE"
    df = (
        spark.read
        .option("basePath", HDFS_SALES_PATH)
        .schema(schema)
        .csv(f"{HDFS_SALES_PATH}/year=*")
    )
    print(f"[extract] {df.count()} rows from HDFS")
    df.show()
    return df


@task(cache_policy=NO_CACHE)
def transform(df):
    df = (
        df
        .withColumn("product", F.upper(F.col("product")))
        .withColumn(
            "price_category",
            F.when(F.col("amount") >= 1000, "premium")
             .when(F.col("amount") >= 300, "mid")
             .otherwise("budget"),
        )
    )
    print("[transform] done")
    df.show()
    return df


@task(cache_policy=NO_CACHE)
def load(spark, df):
    spark.sql("CREATE DATABASE IF NOT EXISTS prefect_demo")

    df.write.mode("overwrite") \
        .partitionBy("year", "price_category") \
        .saveAsTable("prefect_demo.sales_transformed")
    print("[load] prefect_demo.sales_transformed written")

    agg_product = df.groupBy("product").agg(
        F.count("*").alias("cnt"),
        F.round(F.sum("amount"), 2).alias("total_amount"),
        F.round(F.avg("amount"), 2).alias("avg_amount"),
    )
    agg_product.write.mode("overwrite") \
        .saveAsTable("prefect_demo.sales_by_product")
    print("[load] prefect_demo.sales_by_product written")
    agg_product.show()

    agg_year = df.groupBy("year").agg(
        F.count("*").alias("cnt"),
        F.round(F.sum("amount"), 2).alias("total_amount"),
        F.round(F.avg("amount"), 2).alias("avg_amount"),
    )
    agg_year.write.mode("overwrite") \
        .saveAsTable("prefect_demo.sales_by_year")
    print("[load] prefect_demo.sales_by_year written")
    agg_year.show()


@task(cache_policy=NO_CACHE)
def stop_spark(spark):
    spark.stop()


@flow(name="sales_etl")
def process_data():
    spark = start_spark()
    df = extract(spark)
    df = transform(df)
    load(spark, df)
    stop_spark(spark)


if __name__ == "__main__":
    process_data()
