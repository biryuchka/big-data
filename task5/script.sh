#!/bin/bash

NN="192.168.10.9"
HADOOP_USER="hadoop"
SCRIPT="prefect_etl.py"

echo "Setting up Python venv on NameNode..."
# curl -sS https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
# scp /tmp/get-pip.py ${HADOOP_USER}@${NN}:/tmp/get-pip.py
ssh ${HADOOP_USER}@${NN} "python3 -m venv --without-pip ~/prefect_venv && ~/prefect_venv/bin/python3 /tmp/get-pip.py && ~/prefect_venv/bin/pip install prefect"

echo "Copying ${SCRIPT} to ${HADOOP_USER}@${NN}:~/"
scp ${SCRIPT} ${HADOOP_USER}@${NN}:~/${SCRIPT}

echo "Launching ${SCRIPT} on ${NN}..."
ssh ${HADOOP_USER}@${NN} "source ~/.profile; export PYTHONPATH=\$SPARK_HOME/python:\$(echo \$SPARK_HOME/python/lib/py4j-*-src.zip); ~/prefect_venv/bin/python3 ~/${SCRIPT}"

echo "Done."
