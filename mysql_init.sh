#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2021-12-28T10:15:53+08:00]:mysql_init.sh")
################################################################################
MYSQL_DATA_DIR=${DATA_DIR:-/var/lib/mysql}
MYSQL_PORT=${PORT:-3306}
BIND_IP=${BIND_IP:-10.0.2.10}
MYSQL_SOCK_FILE=/var/lib/mysql/mysql.sock
MYSQL_SERVER_ID=3300001
GROUP_LOCAL_ADDRESS=
GROUP_NAME="$(cat /proc/sys/kernel/random/uuid)"
GROUP_SEED="BAD0BEEF"

cat > /etc/my.cnf <<EOF
[mysqld]
datadir=${MYSQL_DATA_DIR}
socket=${MYSQL_SOCK_FILE}
# Disabling symbolic-links is recommended to prevent assorted security risks
symbolic-links=0
[mysqld_safe]
log-error=/var/log/mariadb/mariadb.log
pid-file=/var/run/mariadb/mariadb.pid
!includedir /etc/my.cnf.d
EOF
mkdir -p /etc/my.cnf.d
cat > /etc/my.cnf.d/client.cnf <<EOF
[client]
port = ${MYSQL_PORT}
socket = ${MYSQL_SOCK_FILE}
EOF

cat > /etc/my.cnf.d/server.cnf <<EOF
[mysqld]
open_files_limit = 8192
max_connections = 1024
port = ${MYSQL_PORT}
socket = ${MYSQL_SOCK_FILE}
back_log = 80
tmpdir = /tmp
datadir = ${MYSQL_DATA_DIR}
default-time-zone = '+8:00'
#-------------------gobal variables------------#
max_connect_errors = 20000
max_connections = 2000
wait_timeout = 3600
interactive_timeout = 3600
net_read_timeout = 3600
net_write_timeout = 3600
table_open_cache = 1024
table_definition_cache = 1024
thread_cache_size = 512
open_files_limit = 10000
character-set-server = utf8
collation-server = utf8_general_ci
skip_external_locking
performance_schema = 1
user = mysql
myisam_recover_options = DEFAULT
skip-name-resolve
local_infile = 0
lower_case_table_names = 0
#--------------------innoDB------------#
innodb_buffer_pool_size = 1G
innodb_data_file_path = ibdata1:10M:autoextend
innodb_flush_log_at_trx_commit = 0
innodb_io_capacity = 1000
innodb_lock_wait_timeout = 120
innodb_log_buffer_size = 8M
innodb_log_file_size = 200M
innodb_log_files_in_group = 3
innodb_max_dirty_pages_pct = 85
innodb_read_io_threads = 4
innodb_write_io_threads = 4
innodb_thread_concurrency = 2
innodb_file_per_table
innodb_rollback_on_timeout
#------------session variables-------#
join_buffer_size = 4M
key_buffer_size = 256M
bulk_insert_buffer_size = 4M
max_heap_table_size = 96M
tmp_table_size = 96M
read_buffer_size = 4M
sort_buffer_size = 2M
max_allowed_packet = 64M
read_rnd_buffer_size = 8M
#------------MySQL Log----------------#
#log-bin = my63306-bin
#binlog_format = mixed
#sync_binlog = 10000
#expire_logs_days = 1
#max_binlog_cache_size = 128M
#max_binlog_size = 500M
#binlog_cache_size = 64k
#slow_query_log
#slow_query_log_file = /data/mysql_63306/slow_query.log
#log-slow-admin-statements
#log_warnings = 1
#long_query_time = 10
#---------------replicate--------------#
#relay-log-index = relay63306.index
#relay-log = relay63306
server-id = ${MYSQL_SERVER_ID}
init_slave = 'set sql_mode=STRICT_ALL_TABLES'
binlog_checksum=NONE
log_slave_updates=ON
log_bin=my-${MYSQL_PORT}-binlog
binlog_format=ROW
report_host=${BIND_IP}
#----------------group replication---------#
loose-group_replication_group_name="${GROUP_NAME}"
loose-group_replication_start_on_boot=off
loose-group_replication_local_address= "${GROUP_LOCAL_ADDRESS}"
loose-group_replication_group_seeds= "${GROUP_SEED}"
loose-group_replication_bootstrap_group= off
[mysqldump]
quick
max_allowed_packet = 128M
[mysql]
no-auto-rehash
[isamchk]
key_buffer = 512M
sort_buffer_size = 512M
read_buffer = 8M
write_buffer = 8M
[myisamchk]
key_buffer = 512M
sort_buffer_size = 512M
read_buffer = 8M
write_buffer = 8M
[mysqlhotcopy]
interactive-timeout
EOF

if id -u mysql >/dev/null 2>&1; then
    echo "user exists"
else
    echo "user does not exist, create it"
    useradd mysql -U
fi
mkdir -p ${MYSQL_DATA_DIR}
chown -R mysql:mysql ${MYSQL_DATA_DIR}
systemctl enable mariadb.service
systemctl start mariadb.service
mysql_secure_installation

mysql -uroot -p << EOF
SET SQL_LOG_BIN=0;
CREATE DATABASE ngxlog;
CREATE USER 'admin'@'%' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%'  WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON mysql_innodb_cluster_metadata.* TO admin@'%' WITH GRANT OPTION;
GRANT RELOAD, SHUTDOWN, PROCESS, FILE, SUPER, REPLICATION SLAVE, REPLICATION CLIENT, CREATE USER ON *.* TO admin@'%' WITH GRANT OPTION;
GRANT SELECT ON performance_schema.* TO admin@'%' WITH GRANT OPTION;
GRANT SELECT ON sys.* TO admin@'%' WITH GRANT OPTION;
GRANT SELECT, INSERT, UPDATE, DELETE ON mysql.* TO admin@'%' WITH GRANT OPTION;
CREATE USER 'admin'@'localhost' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'localhost'  WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON mysql_innodb_cluster_metadata.* TO admin@'localhost' WITH GRANT OPTION;
GRANT RELOAD, SHUTDOWN, PROCESS, FILE, SUPER, REPLICATION SLAVE, REPLICATION CLIENT, CREATE USER ON *.* TO admin@'localhost' WITH GRANT OPTION;
GRANT SELECT ON performance_schema.* TO admin@'localhost' WITH GRANT OPTION;
GRANT SELECT ON sys.* TO admin@'localhost' WITH GRANT OPTION;
GRANT SELECT, INSERT, UPDATE, DELETE ON mysql.* TO admin@'localhost' WITH GRANT OPTION;
CREATE USER 'mon'@'%' IDENTIFIED BY 'password';
GRANT SELECT ON mysql_innodb_cluster_metadata.* TO mon@'%';
GRANT SELECT ON performance_schema.global_status TO mon@'%';
GRANT SELECT ON performance_schema.replication_applier_configuration TO mon@'%';
GRANT SELECT ON performance_schema.replication_applier_status TO mon@'%';
GRANT SELECT ON performance_schema.replication_applier_status_by_coordinator TO mon@'%';
GRANT SELECT ON performance_schema.replication_applier_status_by_worker TO mon@'%';
GRANT SELECT ON performance_schema.replication_connection_configuration TO mon@'%';
GRANT SELECT ON performance_schema.replication_connection_status TO mon@'%';
GRANT SELECT ON performance_schema.replication_group_member_stats TO mon@'%';
GRANT SELECT ON performance_schema.replication_group_members TO mon@'%';
FLUSH PRIVILEGES;
SET SQL_LOG_BIN=1;
EOF
mysql -uroot -p << EOF
show databases;
EOF
