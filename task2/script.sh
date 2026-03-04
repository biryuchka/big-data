#!/bin/bash
set -e 

# Параметры кластера
HADOOP_HOME="${HADOOP_HOME:-/home/hadoop/hadoop}"          # путь к Hadoop
NAMENODE_IP="192.168.10.9"                                  # IP NameNode
DATANODE_IPS=("192.168.10.8" "192.168.10.10")               # IP DataNode'ов
ALL_NODES=("$NAMENODE_IP" "${DATANODE_IPS[@]}")             # все узлы кластера
HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop"

# Проверка, что скрипт запущен именно на NameNode
current_ip=$(hostname -I | awk '{print $1}')
if [[ "$current_ip" != "$NAMENODE_IP" ]]; then
    echo "Ошибка: скрипт должен выполняться на NameNode ($NAMENODE_IP)."
    echo "Текущий IP: $current_ip"
    exit 1
fi

echo ">>> Создание конфигурационных файлов в $HADOOP_CONF_DIR"

# 1. Файл mapred-site.xml
cat > "$HADOOP_CONF_DIR/mapred-site.xml" << 'EOF'
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>mapreduce.framework.name</name>
        <value>yarn</value>
    </property>
    <property>
        <name>mapreduce.application.classpath</name>
        <value>$HADOOP_HOME/share/hadoop/mapreduce/*:$HADOOP_HOME/share/hadoop/mapreduce/lib/*</value>
    </property>
</configuration>
EOF

# 2. Файл yarn-site.xml
cat > "$HADOOP_CONF_DIR/yarn-site.xml" << EOF
<?xml version="1.0"?>
<configuration>
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
        <value>$NAMENODE_IP</value>
    </property>
    <property>
        <name>yarn.resourcemanager.address</name>
        <value>$NAMENODE_IP:8032</value>
    </property>
    <property>
        <name>yarn.resourcemanager.resource-tracker.address</name>
        <value>$NAMENODE_IP:8031</value>
    </property>
</configuration>
EOF

# 3. Файл workers
cat > "$HADOOP_CONF_DIR/workers" << EOF
${DATANODE_IPS[0]}
${DATANODE_IPS[1]}
EOF

echo ">>> Конфигурация создана."

# 4. Копирование файлов на все узлы кластера
for node in "${ALL_NODES[@]}"; do
    echo ">>> Копирование на $node ..."
    scp "$HADOOP_CONF_DIR/mapred-site.xml" \
        "$HADOOP_CONF_DIR/yarn-site.xml" \
        "$HADOOP_CONF_DIR/workers" \
        "$node:$HADOOP_CONF_DIR/"
done

# 5. Остановка старых сервисов YARN
echo ">>> Остановка текущих сервисов YARN (если есть)..."
"$HADOOP_HOME/sbin/stop-yarn.sh" 2>/dev/null || true
sleep 2

# 6. Запуск YARN и HistoryServer
echo ">>> Запуск YARN..."
"$HADOOP_HOME/sbin/start-yarn.sh"

echo ">>> Запуск History Server..."
"$HADOOP_HOME/bin/mapred" --daemon start historyserver
sleep 3

# 7. Проверка запущенных процессов
echo ""
echo "=== ПРОВЕРКА ЗАПУЩЕННЫХ СЕРВИСОВ ==="

echo "--- NameNode ($NAMENODE_IP) ---"
ssh "$NAMENODE_IP" "jps | grep -E 'ResourceManager|JobHistoryServer|NameNode|DataNode'"

for dn in "${DATANODE_IPS[@]}"; do
    echo "--- DataNode $dn ---"
    ssh "$dn" "jps | grep -E 'NodeManager|DataNode'"
done

echo ""
echo "=== РАЗВЕРТЫВАНИЕ YARN ЗАВЕРШЕНО УСПЕШНО ==="
echo ""
echo "Для доступа к веб-интерфейсам с локальной машины выполните туннель:"
echo "ssh -L 9870:$NAMENODE_IP:9870 -L 8088:$NAMENODE_IP:8088 -L 19888:$NAMENODE_IP:19888 hadoop@178.236.25.98"
echo ""
echo "После подключения откройте в браузере:"
echo "  http://localhost:9870  – HDFS (NameNode)"
echo "  http://localhost:8088  – YARN ResourceManager"
echo "  http://localhost:19888 – JobHistoryServer"