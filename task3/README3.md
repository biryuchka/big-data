# Task 3

Ansible-плейбук для автоматического развертывания Apache Hive. 


## Что делает плейбук

### Play 1 — PostgreSQL на NN
Устанавливаются `postgresql`, `postgresql-contrib`, `python3-psycopg2`.
Создаётся пользователь `hive` и база `hive_metastore` через модули `community.postgresql`.

### Play 2 — Загрузка Hive и JDBC-драйвера
На **jn** скачиваются `apache-hive-4.0.0-alpha-2-bin.tar.gz` и `postgresql-42.7.3.jar`, затем копируются на **nn** через `scp`.

### Play 3 — Установка и настройка Hive на NN
- Распаковка архива, JDBC-драйвер → `$HIVE_HOME/lib/`
- Переменные окружения `HIVE_HOME`, `PATH` → `.bash_profile`
- Деплой `hive-site.xml` из шаблона

### Play 4 — YARN-конфигурация на все ноды
На все узлы кластера раскладываются `mapred-site.xml` и `yarn-site.xml`.

### Play 5 — Запуск сервисов
- YARN (ResourceManager + NodeManagers)
- HDFS-директории `/tmp`, `/user/hive/warehouse`
- Инициализация схемы Metastore (`schematool -initSchema`)
- Запуск Hive Metastore (порт 9083) и HiveServer2 (порт 10000)

### Play 6 — Загрузка данных
Через Beeline выполняется `load_data.hql`


## Зависимости

```bash
ansible-galaxy collection install community.postgresql
```


## Запуск

```bash
cd task3
ansible-vault encrypt vars/secrets.yml
ansible-playbook site.yml --ask-vault-pass
```


## Проверка

```bash
beeline -u "jdbc:hive2://192.168.10.9:10000" -n hadoop
```

```sql
SHOW DATABASES;
USE demo;
SHOW PARTITIONS sales;
SELECT * FROM demo.sales;
```


## Веб-интерфейсы (SSH-туннель)

```bash
ssh -4 -L 9870:192.168.10.9:9870 -L 8088:192.168.10.9:8088 -L 10002:192.168.10.9:10002 hadoop@178.236.25.98
```

- http://localhost:9870 — HDFS NameNode
- http://localhost:8088 — YARN ResourceManager
- http://localhost:10002 — HiveServer2 Web UI
