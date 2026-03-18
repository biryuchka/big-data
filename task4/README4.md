# Apache Spark на YARN: чтение, трансформация и запись данных

Пошаговая инструкция по использованию Apache Spark 3.5.3 (PySpark) под управлением YARN для чтения данных из HDFS, выполнения нескольких трансформаций и сохранения результата как таблиц Hive.

---
## 1. Топология кластера

| Узел | Hostname | IP | Роли |
|------|-----------|----|------|
| NameNode | `nn` | `192.168.10.9` | NameNode, SecondaryNameNode, ResourceManager, JobHistoryServer, HiveServer2, Hive Metastore |
| DataNode 0 | `dn-00` | `192.168.10.8` | DataNode, NodeManager |
| DataNode 1 | `dn-01` | `192.168.10.10` | DataNode, NodeManager |
| Jump Node | `jn` | `192.168.10.58` | точка входа / управление |

---
## 2. Предварительные требования

На кластере уже должны быть развернуты и запущены:

- Hadoop 3.4.3 (HDFS + YARN)
- Hive 4.0.0-alpha-2:
  - HiveServer2 на порту `5433`
- Java 11 в `/home/hadoop/java11`
- Python 3 на всех узлах
- Исходные данные в HDFS (загружены ранее через Hive и партиционированы по `year`):

```
/user/hive/warehouse/demo.db/sales/year=2023/data_2023.csv
/user/hive/warehouse/demo.db/sales/year=2024/data_2024.csv
```

Формат CSV: `id,product,amount` (без заголовка).

---
## 3. Установка Spark на NameNode (`nn`)

### 3.1. Копирование архива

С Jump Node:

```bash
scp /home/hadoop/spark-3.5.3-bin-hadoop3.tgz nn:/home/hadoop/
```

### 3.2. Распаковка

На NameNode:

```bash
ssh nn
cd /home/hadoop
tar -xzf spark-3.5.3-bin-hadoop3.tgz
```

---
## 4. Настройка окружения Spark

На `nn` добавьте в `/home/hadoop/.profile`:

```bash
export SPARK_HOME=/home/hadoop/spark-3.5.3-bin-hadoop3
export PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
```

Примените:

```bash
source /home/hadoop/.profile
```

---
## 5. Конфигурация Spark

### 5.1. `spark-env.sh`

Создайте `$SPARK_HOME/conf/spark-env.sh`:

```bash
#!/usr/bin/env bash
export JAVA_HOME=/home/hadoop/java11
export HADOOP_HOME=/home/hadoop/hadoop-3.4.3
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
export SPARK_HOME=/home/hadoop/spark-3.5.3-bin-hadoop3
export SPARK_DIST_CLASSPATH=$($HADOOP_HOME/bin/hadoop classpath)
export PYSPARK_PYTHON=python3
```

И сделайте исполняемым:

```bash
chmod +x $SPARK_HOME/conf/spark-env.sh
```

### 5.2. `spark-defaults.conf`

Создайте `$SPARK_HOME/conf/spark-defaults.conf`:

```properties
spark.master                     yarn
spark.submit.deployMode          client
spark.driver.memory              512m
spark.executor.memory            512m
spark.executor.cores             1
spark.executor.instances         2
spark.sql.warehouse.dir          /user/hive/warehouse
spark.hadoop.hive.metastore.uris thrift://nn:9083
```

---
## 6. Интеграция Spark с Hive

### 6.1. `hive-site.xml` в Spark

Скопируйте hive-site.xml из Hive в конфиги Spark:

```bash
cp $HIVE_HOME/conf/hive-site.xml $SPARK_HOME/conf/hive-site.xml
```

### 6.2. JDBC-драйвер PostgreSQL для Hive Metastore

Скопируйте драйвер метастора в `spark/jars`:

```bash
cp /home/hadoop/apache-hive-4.0.0-alpha-2-bin/lib/postgresql-42.7.4.jar \
   $SPARK_HOME/jars/
```

---
## 7. Настройка YARN на DataNodes

В `$HADOOP_HOME/etc/hadoop/yarn-site.xml` на каждом DataNode добавьте:

DN-00:

```xml
<property>
  <name>yarn.nodemanager.hostname</name>
  <value>192.168.10.8</value>
</property>
```

DN-01:

```xml
<property>
  <name>yarn.nodemanager.hostname</name>
  <value>192.168.10.10</value>
</property>
```

Перезапустите NodeManager на каждом DataNode:

```bash
export JAVA_HOME=/home/hadoop/java11
export HADOOP_HOME=/home/hadoop/hadoop-3.4.3
$HADOOP_HOME/bin/yarn --daemon stop nodemanager
sleep 2
$HADOOP_HOME/bin/yarn --daemon start nodemanager
```

Проверьте:

```bash
yarn node -list
```

---
## 8. Запуск Hive Metastore

На `nn`:

```bash
nohup hive --service metastore > /tmp/metastore.log 2>&1 &
```

---
## 9. ETL-скрипт Spark

Скрипт находится на NameNode: `/home/hadoop/spark_etl.py`.

Что делает ETL:

- Читает CSV из HDFS:
  - `.../sales/year=2023/`
  - `.../sales/year=2024/`
- Применяет трансформации:
  - приведение типов (`id`, `amount`)
  - нормализация `product` в верхний регистр
  - вычисление `price_category`
  - агрегации по `product` и по `year`
- Сохраняет результат как таблицы Hive:
  - `spark_demo.sales_transformed` (партиционирование: `year`, `price_category`)
  - `spark_demo.sales_by_product`
  - `spark_demo.sales_by_year`

---
## 10. Запуск Spark на YARN

На NameNode:

```bash
source /home/hadoop/.profile
spark-submit \
  --master yarn \
  --deploy-mode client \
  --conf spark.pyspark.python=python3 \
  --conf spark.pyspark.driver.python=python3 \
  /home/hadoop/spark_etl.py
```

---
## 11. Проверка результата через Hive (beeline)

Подключитесь к HiveServer2:

```bash
beeline -u "jdbc:hive2://localhost:5433" -n hadoop
```

Выполните:

```sql
SHOW DATABASES;
USE spark_demo;
SHOW TABLES;

SELECT * FROM sales_transformed;
SHOW PARTITIONS sales_transformed;

SELECT * FROM sales_by_product;
SELECT * FROM sales_by_year;
```

---
## 12. HDFS-расположение результатов

Обычно результаты таблиц Hive появляются в:

```
/user/hive/warehouse/spark_demo.db/sales_transformed/
/user/hive/warehouse/spark_demo.db/sales_by_product/
/user/hive/warehouse/spark_demo.db/sales_by_year/
```