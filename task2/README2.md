# Развертывание YARN на кластере Hadoop

В этом руководстве описан процесс установки и настройки YARN (ResourceManager, NodeManager) и History Server на работающем кластере Hadoop. Предполагается, что HDFS уже развернута и функционирует, а все узлы доступны по SSH без пароля с NameNode.

## Предварительные условия

- Кластер Hadoop состоит из узлов:
  - NameNode: `192.168.10.9`
  - DataNode-00: `192.168.10.8`
  - DataNode-01: `192.168.10.10`
  - Jump-узел: `178.236.25.98` (внутренний адрес `192.168.10.58`)
- На всех узлах создан пользователь `hadoop` с одинаковыми домашними каталогами.
- Настроен SSH-доступ без пароля с NameNode на все узлы кластера (включая самого себя).
- Переменные окружения `JAVA_HOME` и `HADOOP_HOME` заданы в `~/.profile` или аналогичном файле и доступны при входе.
- Директория `$HADOOP_HOME/etc/hadoop` существует на всех узлах.

## Настройка конфигурационных файлов

Все изменения выполняются на **NameNode** (`192.168.10.9`) в каталоге `$HADOOP_HOME/etc/hadoop`.

### 1. Файл `mapred-site.xml`

Этот файл определяет, что в качестве фреймворка выполнения заданий MapReduce будет использоваться YARN. Если файла нет, создайте его из шаблона:

```bash
cp mapred-site.xml.template mapred-site.xml
```

Отредактируйте `mapred-site.xml`, добавив в секцию `<configuration>` следующие свойства:

```xml
<property>
  <name>mapreduce.framework.name</name>
  <value>yarn</value>
</property>
<property>
  <name>mapreduce.application.classpath</name>
  <value>$HADOOP_HOME/share/hadoop/mapreduce/*:$HADOOP_HOME/share/hadoop/mapreduce/lib/*</value>
</property>
```

### 2. Файл `yarn-site.xml`

В нём задаются основные параметры работы YARN. Добавьте в секцию `<configuration>`:

```xml
<property>
  <name>yarn.nodemanager.aux-services</name>
  <value>mapreduce_shuffle</value>
</property>
<property>
  <name>yarn.nodemanager.env-whitelist</name>
  <value>JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_DIR,CLASSPATH_PREPEND_DISTCACHE,HADOOP_YARN_HOME,HADOOP_HOME,PATH,LANG,TZ,HADOOP_MAPRED_HOME</value>
</property>
<property>
  <name>yarn.resourcemanager.hostname</name>
  <value>192.168.10.9</value>
</property>
<property>
  <name>yarn.resourcemanager.address</name>
  <value>192.168.10.9:8032</value>
</property>
<property>
  <name>yarn.resourcemanager.resource-tracker.address</name>
  <value>192.168.10.9:8031</value>
</property>
```

При необходимости можно добавить явные указания портов для веб-интерфейсов, но по умолчанию они будут использовать стандартные значения.

### 3. Файл `workers`

В этом файле перечисляются узлы, на которых будут запущены NodeManager. Замените содержимое на актуальные IP-адреса DataNode'ов:

```
192.168.10.8
192.168.10.10
```

## Распространение конфигурации на узлы кластера

Скопируйте изменённые файлы на все узлы, включая сам NameNode (для единообразия). Выполните на NameNode:

```bash
cd $HADOOP_HOME/etc/hadoop
for node in 192.168.10.9 192.168.10.8 192.168.10.10; do
    scp mapred-site.xml yarn-site.xml workers $node:$HADOOP_HOME/etc/hadoop/
done
```

Убедитесь, что копирование прошло без ошибок (проверьте SSH-доступность каждого узла).

## Запуск YARN и History Server

Все команды запуска выполняются на **NameNode**.

### Запуск YARN

```bash
$HADOOP_HOME/sbin/start-yarn.sh
```

Скрипт запустит ResourceManager на текущем узле (NameNode) и NodeManager на всех узлах, перечисленных в файле `workers`.

### Запуск History Server

History Server необходим для просмотра информации о завершённых заданиях MapReduce.

```bash
$HADOOP_HOME/bin/mapred --daemon start historyserver
```

## Проверка работоспособности

Убедитесь, что все необходимые процессы запущены.

### На NameNode (`192.168.10.9`)

Выполните `jps` и найдите:

- `ResourceManager`
- `JobHistoryServer`
- (также должны присутствовать `NameNode` и `DataNode`, если HDFS уже запущена)

Пример вывода:

```
12345 NameNode
12346 DataNode
12347 ResourceManager
12348 JobHistoryServer
```

### На DataNode'ах (`192.168.10.8`, `192.168.10.10`)

Запустите `jps` и проверьте наличие:

- `NodeManager`
- `DataNode`

Если процессы не появились, проверьте логи в `$HADOOP_HOME/logs`.

## Доступ к веб-интерфейсам через SSH-туннель

Для доступа к веб-интерфейсам кластера с локальной машины используется SSH-туннелирование через публичный узел (`178.236.25.98`). Ниже приведены стандартные порты:

- NameNode Web UI: `9870`
- ResourceManager Web UI: `8088`
- History Server Web UI: `19888`

Выполните на локальной машине команду:

```bash
ssh -L 9870:192.168.10.9:9870 -L 8088:192.168.10.9:8088 -L 19888:192.168.10.9:19888 hadoop@178.236.25.98
```

После успешного подключения откройте браузер и перейдите по адресам:

- [http://localhost:9870](http://localhost:9870) — интерфейс HDFS (NameNode)
- [http://localhost:8088](http://localhost:8088) — интерфейс YARN ResourceManager
- [http://localhost:19888](http://localhost:19888) — интерфейс JobHistoryServer

## Остановка сервисов

При необходимости остановить YARN и History Server выполните на NameNode:

```bash
$HADOOP_HOME/sbin/stop-yarn.sh
$HADOOP_HOME/bin/mapred --daemon stop historyserver
```

## Заключение

Теперь ваш кластер Hadoop поддерживает выполнение приложений MapReduce поверх YARN. Вы можете запускать тестовые задания (например, примеры из `hadoop-mapreduce-examples-*.jar`) и отслеживать их выполнение через веб-интерфейсы.