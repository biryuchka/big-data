# Task 5 — ETL-процесс на Apache Spark + Prefect

Prefect-оркестрированный ETL-пайплайн: Apache Spark на YARN читает данные из HDFS, выполняет трансформации и сохраняет результаты как таблицы Hive.

## Что делает `prefect_etl.py`

1. **`start_spark()`** — запускает Spark-сессию на YARN с подключением к Hive Metastore
2. **`extract()`** — читает CSV из HDFS (`/user/hive/warehouse/demo.db/sales/year=*`)
3. **`transform()`** — upper-case продуктов, добавление `price_category` (premium/mid/budget)
4. **`load()`** — сохраняет в Hive: `prefect_demo.sales_transformed`, `sales_by_product`, `sales_by_year`
5. **`stop_spark()`** — завершает сессию

## Запуск

Скопировать `script.sh` и `prefect_etl.py` на jump node и запустить:

```bash
bash script.sh
```

Скрипт автоматически установит `prefect` на NameNode, скопирует ETL-скрипт и запустит пайплайн.

## Проверка

На NameNode (`ssh hadoop@192.168.10.9` с jump node):

```bash
beeline -u "jdbc:hive2://192.168.10.9:5433" -n hadoop
```

```sql
USE prefect_demo;
SHOW TABLES;
SELECT * FROM sales_transformed;
SELECT * FROM sales_by_product;
SELECT * FROM sales_by_year;
```
