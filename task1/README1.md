# Task 1 — Hadoop Cluster Setup via Ansible

Ansible-плейбук для автоматической установки и запуска HDFS-кластера на 4 узлах.

## Топология кластера

```
Internet
    │
    ▼
[jn]  178.236.25.98          — jump node, точка входа извне
    │
    │ (internal network 192.168.10.0/24)
    ├──▶ [nn]    192.168.10.9   — NameNode
    ├──▶ [dn-00] 192.168.10.8   — DataNode 0
    └──▶ [dn-01] 192.168.10.10  — DataNode 1
```

Внутренние узлы недоступны снаружи напрямую — Ansible ходит к ним через `ProxyCommand` по jn.

## Структура

```
task1/
├── ansible.cfg              # конфиг Ansible
├── inventory.ini            
├── site.yml                 
├── group_vars/
│   ├── all.yml              
│   └── internal.yml         # ProxyCommand и ssh_pass для внутренних узлов
├── vars/
│   └── secrets.yml          # пароли зашифрованные vault
└── templates/
    ├── core-site.xml.j2    
    ├── hdfs-site.xml.j2     
    └── workers.j2           
```

## Что делает плейбук


### Play 1 — Создание пользователя `hadoop`
На **всех** узлах создаётся группа и пользователь `hadoop` с паролем из vault,
домашней директорией `/home/hadoop`, каталогом `.ssh` с правами `0700`.

### Play 2 — Генерация SSH-ключей на jn
На **jn** от имени пользователя `hadoop` генерируется пара ключей ed25519
(`~/.ssh/id_ed25519` + `.pub`). Ключи считываются и сохраняются в host facts,
чтобы следующий play мог их забрать.

### Play 3 — Раздача SSH-ключей на все узлы
На **всех** узлах:
- публичный ключ добавляется в `authorized_keys` пользователя `hadoop`;
- пара ключей (private + public) копируется в `~/.ssh/`;
- через `ssh-keyscan` строится `known_hosts` со всеми четырьмя узлами кластера.


### Play 4 — Исправление прав на внутренних узлах
На **nn, dn-00, dn-01** рекурсивно исправляется владелец `/home/hadoop` на `hadoop:hadoop`.
Нужно потому, что user-модуль мог создать директорию под `root`.

### Play 5 — Установка Hadoop
На **jn** (от имени `hadoop`):
1. Скачивается `hadoop-3.3.6.tar.gz` с apache.org (idempotent — пропускается если файл уже есть).
2. Архив распаковывается и переименовывается в `/home/hadoop/hadoop`.
3. Через `scp` tarball копируется на каждый внутренний узел, там же распаковывается и переименовывается — всё по SSH через уже настроенные ключи.

### Play 6 — Повторное исправление прав
После `scp` на **nn, dn-00, dn-01** снова исправляется владелец `/home/hadoop`.

### Play 7 — Переменные окружения
На **всех** узлах (от имени `hadoop`):
- автоматически определяется `JAVA_HOME` (`readlink -f $(which java)`);
- в `~/.bash_profile` добавляется блок с `JAVA_HOME`, `HADOOP_HOME`, `PATH`;
- в `hadoop-env.sh` прописывается `JAVA_HOME`.

### Play 8 — Конфигурация Hadoop
На **всех** узлах разворачиваются Jinja2-шаблоны:
- `core-site.xml` — `fs.defaultFS = hdfs://nn:9000`;
- `hdfs-site.xml` — фактор репликации, пути namenode/datanode data;
- `workers` — список DataNode-ов (dn-00, dn-01).

### Play 9 — Обновление `/etc/hosts`
На **всех** узлах в `/etc/hosts` добавляется блок с именами и IP всех четырёх машин кластера (`jn`, `nn`, `dn-00`, `dn-01`), чтобы они разрешались по hostname.

### Play 10 — Форматирование NameNode и запуск HDFS
На **nn** (от имени `hadoop`):
1. Проверяется, отформатирован ли уже NameNode (`/tmp/hadoop-.../dfs/name/current`).
2. Если нет — запускается `hdfs namenode -format -nonInteractive`.
3. Запускается `start-dfs.sh`, который стартует NameNode на nn и DataNode-ы на dn-00, dn-01.
4. На каждом узле выполняется `jps` и вывод выводится в лог — для проверки, что нужные Java-процессы запущены.

## Запуск

```bash
# Полная установка
ansible-playbook site.yml --ask-vault-pass
```

## Остановка кластера (вручную)

```bash
ssh -J ubuntu@178.236.25.98 hadoop@192.168.10.9 \
  "/home/hadoop/hadoop/sbin/stop-dfs.sh"
```
