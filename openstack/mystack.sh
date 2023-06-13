#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("67eda0e[2023-06-13T17:16:01+08:00]:mystack.sh")
set -o errtrace  # trace ERR through 'time command' and other functions
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
# [ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
MYSQL_HOST=""
##OPTION_START##
MYSQL_PASS=${MYSQL_PASS:-}
RABBIT_USER=${RABBIT_USER:-rabbit}
RABBIT_PASS=${RABBIT_PASS:-rabbit_pass}
KEYSTONE_USER=${KEYSTONE_USER:-admin}
KEYSTONE_PASS=${KEYSTONE_PASS:-admin_pass}
KEYSTONE_DBPASS=${KEYSTONE_DBPASS:-keystone_dbpass}
GLANCE_PASS=${GLANCE_PASS:-glance_pass}
GLANCE_DBPASS=${GLANCE_DBPASS:-glance_dbpass}
NOVA_PASS=${NOVA_PASS:-nova_pass}
NOVA_DBPASS=${NOVA_DBPASS:-nova_dbpass}
PLACEMENT_PASS=${PLACEMENT_PASS:-palcement_pass}
PLACEMENT_DBPASS=${PLACEMENT_DBPASS:-placement_dbpass}
NEUTRON_PASS=${NEUTRON_PASS:-neutron_pass}
NEUTRON_DBPASS=${NEUTRON_DBPASS:-neutron_dbpass}
OPENSTACK_DEBUG=${OPENSTACK_DEBUG:-false}
##OPTION_END##

readonly my_conf=/etc/mysql/mariadb.conf.d/50-server.cnf
readonly memcached_conf=/etc/memcached.conf
readonly keystone_conf=/etc/keystone/keystone.conf
readonly glance_conf=/etc/glance/glance-api.conf
readonly nova_conf=/etc/nova/nova.conf
readonly nova_compute_conf=/etc/nova/nova-compute.conf
readonly placement_conf=/etc/placement/placement.conf
readonly neutron_conf=/etc/neutron/neutron.conf
readonly metadata_agent_ini=/etc/neutron/metadata_agent.ini
readonly ml2_conf_ini=/etc/neutron/plugins/ml2/ml2_conf.ini
readonly linuxbridge_agent_ini=/etc/neutron/plugins/ml2/linuxbridge_agent.ini
readonly horizon_settings_py=/etc/openstack-dashboard/local_settings.py
readonly horizon_debian_cache_py=/etc/openstack-dashboard/local_settings.d/_0006_debian_cache.py
readonly horizon_dashboard_conf=/etc/apache2/conf-available/openstack-dashboard.conf
readonly nova_consoleproxy=/etc/default/nova-consoleproxy

LOGFILE=""
BACK_DIR=backup
log() { echo "$(tput setaf 141)##$(tput sgr0) $(tput setaf 70)$*$(tput sgr0)" | tee ${LOGFILE:-} >&2; }

backup() {
    local src=${1}
    local mv=${2:-}
    [ -d "${BACK_DIR}" ] || mkdir -p ${BACK_DIR}
    local __backup=$(basename ${src})
    log "${mv:-BACKUP}: ${src} => ${BACK_DIR} "
    [ -e "${BACK_DIR}/${__backup}" ] && return 0
    cat ${src} 2>/dev/null > ${BACK_DIR}/${__backup} || true
    [ -z "${mv}" ] || echo "" > ${src} # for keep file owner etc.
}
get_mysql_connection() {
    local user=${1}
    local pass=${2}
    local db=${3}
    printf "mysql+pymysql://%s:%s@%s/%s"  "${user}" "${pass}" "${MYSQL_HOST}" "${db}"
}
ini_get() {
    local file=${1}
    local sec=${2}
    local key=${3}
    crudini --get "${file}" "${sec}" "${key}"
}
ini_del() {
    local file=${1}
    local sec=${2}
    local key=${3:-}
    log "del ${file} [${sec}] ${key}"
    crudini --del "${file}" "${sec}" "${key}"
    # # Comment
    # $sudo sed -i -e "/^\[$section\]/,/^\[.*\]/ s|^\($option[ \t]*=.*$\)|#\1|" "$file"
    # # del
    # $sudo sed -i -e "/^\[$section\]/,/^\[.*\]/ { /^$option[ \t]*=/ d; }" "$file"
    # # get
    # line=$(sed -ne "/^\[$section\]/,/^\[.*\]/ { /^$option[ \t]*=/ p; }" "$file"); echo ${line#*=}
}

ini_set() {
    local file=${1}
    local sec=${2}
    local key=${3}
    local val=${4}
    log "set ${file} [${sec}] ${key} = ${val}"
    crudini --verbose --set "${file}" "${sec}" "${key}" "${val}"
}

ini_append_list() {
    local ini=${1}
    local sec=${2}
    local key=${3}
    local val=${4}
    local old="$(ini_get ${ini} ${sec} ${key} 2>/dev/null)"
    ini_set ${ini} ${sec} ${key} "${val}${old:+,${old}}"
}

create_mysql_db() {
    local db=${1}
    local user=${2}
    local pass=${3}
    log "Add a User [${user}/${pass}] and Database [${db}] on MariaDB."
    cat <<EOF | mysql ${MYSQL_PASS:+"-uroot -p${MYSQL_PASS}"}
DROP DATABASE IF EXISTS ${db};
CREATE DATABASE ${db} CHARACTER SET utf8;
GRANT ALL PRIVILEGES ON ${db}.* TO '${user}'@'localhost' IDENTIFIED BY '${pass}';
GRANT ALL PRIVILEGES ON ${db}.* TO '${user}'@'%' IDENTIFIED BY '${pass}';
FLUSH PRIVILEGES;
EOF
}

openstack_add_admin_user() {
    local user=${1}
    local pass=${2}
    local project=${3:-service}
    local domain=${4:-default}
    local id=$(openstack user create --domain ${domain} --project ${project} --password ${pass} ${user} --or-show -f value -c id)
    openstack role add --project ${project} --user ${user} admin
    log "Add admin user [${user}/${pass}] id [${id}]"
    # openstack role assignment list --role $1 --user $2 --domain $3 -c Role -f value
}

openstack_add_service_endpoint() {
    local name=${1}
    local type=${2}
    local url=${3}
    local desc=${4}
    local region="${5:-RegionOne}"
    local id=""
    id=$(openstack service show ${name} -f value -c id 2>/dev/null || openstack service create --name ${name} --description "${desc}" ${type} -f value -c id)
    log "create service [${name}] id [${id}]"
    for __t in admin public internal; do
        id=$(openstack endpoint list --service  ${name} --interface ${__t} --region ${region} -c ID -f value)
        [ -z "${id}" ] && id=$(openstack endpoint create --region ${region} ${type} ${__t} ${url} -f value -c id)
        log "create endpoint for [${name} : ${__t}] id [${id}]"
    done
}
service_restart() {
    local svc=""
    for svc in "$@"; do
        log "enable & restart ${svc} service"
        systemctl restart ${svc}
        systemctl enable ${svc}
    done
}
####################################################################################################
prepare_env() {
    local ctrl_host=${1}
    local keystone_user=${2}
    local keystone_pass=${3}
    log "##########################PREPARE ENV##########################"
    log "~/keystonerc"
    tee ~/keystonerc <<EOF
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=admin
export OS_USERNAME=${keystone_user}
export OS_PASSWORD=${keystone_pass}
export OS_AUTH_URL=http://${ctrl_host}:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF
    source ~/keystonerc
    sed -i '/keystonerc/d' ~/.bashrc
    echo "source ~/keystonerc " >> ~/.bashrc
}

prepare_db_mq() {
    local rabbit_user=${1}
    local rabbit_pass=${2}
    log "##########################CONTROLL NODE#############################"
    log "install mariadb memcached rabbitmq"
#     sudo debconf-set-selections <<MYSQL_PRESEED
# mysql-server mysql-server/root_password password $DATABASE_PASSWORD
# mysql-server mysql-server/root_password_again password $DATABASE_PASSWORD
# mysql-server mysql-server/start_on_boot boolean true
# MYSQL_PRESEED
    backup ${my_conf}
    ini_set ${my_conf} mysqld bind-address 0.0.0.0
    ini_set ${my_conf} mysqld character-set-server utf8mb4
    ini_set ${my_conf} mysqld collation-server utf8mb4_general_ci
    ini_set ${my_conf} mysqld sql_mode TRADITIONAL
    ini_set ${my_conf} mysqld default-storage-engine InnoDB
    ini_set ${my_conf} mysqld max_connections 1024
    # # MYSQL_REDUCE_MEMORY
    ini_set ${my_conf} mysqld read_buffer_size 64K
    ini_set ${my_conf} mysqld innodb_buffer_pool_size 16M
    ini_set ${my_conf} mysqld thread_stack 192K
    ini_set ${my_conf} mysqld thread_cache_size 8
    ini_set ${my_conf} mysqld tmp_table_size 8M
    ini_set ${my_conf} mysqld sort_buffer_size 8M
    ini_set ${my_conf} mysqld max_allowed_packet 8M
    log "install db"
    mysql_install_db -u mysql --skip-name-resolve --skip-test-db &>/dev/null
    service_restart mariadb.service
    # mysql_secure_installation
    # echo -e "\nY\n$MYSQLDB_PASSWORD\n$MYSQLDB_PASSWORD\nY\nn\nY\nY\n" | mysql_secure_installation
    service_restart rabbitmq-server.service
    log "Add the rabbitmq user [${rabbit_user}]"
    rabbitmqctl delete_user ${rabbit_user} 2>/dev/null || true
    rabbitmqctl add_user ${rabbit_user} ${rabbit_pass}
    rabbitmqctl set_permissions ${rabbit_user} ".*" ".*" ".*"

    backup ${memcached_conf}
    sed -i -E \
        -e 's/^\s*#*\s*-l \s*.*/-l 0.0.0.0/g' \
        ${memcached_conf}
    log "restart memcached service"
    service_restart memcached.service
}

init_keystone() {
    local ctrl_host=${1}
    local keystone_user=${2}
    local keystone_pass=${3}
    local keystone_dbpass=${4}
    local region=${5:-RegionOne}
    log "##########################INSTALL KEYSTONE##########################"
    service_restart keystone.service
    create_mysql_db keystone keystone "${keystone_dbpass}"
    backup ${keystone_conf}
    ini_set ${keystone_conf} database connection "$(get_mysql_connection keystone ${keystone_dbpass} keystone)"
    ini_set ${keystone_conf} token provider fernet
    ini_set ${keystone_conf} cache memcache_servers ${ctrl_host}:11211
    log "keystone-manage db_sync"
    su -s /bin/bash keystone -c "keystone-manage db_sync"
    log "initialize Fernet key"
    keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
    keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
    log "bootstrap keystone"
    keystone-manage bootstrap \
        --bootstrap-username ${keystone_user} \
        --bootstrap-password ${keystone_pass} \
        --bootstrap-admin-url http://${ctrl_host}:5000/v3/ \
        --bootstrap-internal-url http://${ctrl_host}:5000/v3/ \
        --bootstrap-public-url http://${ctrl_host}:5000/v3/ \
        --bootstrap-region-id ${region}
    local id=$(openstack project create --domain default --description "Service Project" service --or-show -f value -c id)
    log "Add Projects, create [service], id ${id} "
}
add_keystone_authtoken() {
    local conf=${1}
    local host=${2}
    local user=${3}
    local pass=${4}
    log "add keystone_authtoken"
    ini_set ${conf} keystone_authtoken auth_url http://${host}:5000
    ini_set ${conf} keystone_authtoken www_authenticate_uri http://${host}:5000
    ini_set ${conf} keystone_authtoken memcached_servers ${host}:11211
    ini_set ${conf} keystone_authtoken auth_type password
    ini_set ${conf} keystone_authtoken project_domain_name default
    ini_set ${conf} keystone_authtoken user_domain_name default
    ini_set ${conf} keystone_authtoken project_name service
    ini_set ${conf} keystone_authtoken username ${user}
    ini_set ${conf} keystone_authtoken password ${pass}
    ini_del ${conf} keystone_authtoken region_name
}
init_glance() {
    local ctrl_host=${1}
    local glance_pass=${2}
    local glance_dbpass=${3}
    log "##########################INSTALL GLANCE##########################"
    log "install glance: Image Service"
    openstack_add_admin_user glance "${glance_pass}"
    openstack_add_service_endpoint glance image "http://${ctrl_host}:9292" "OpenStack Image service"
    log "Add a User and Database on MariaDB for Glance"
    create_mysql_db glance glance "${glance_dbpass}"
    log "Configure Glance create new"
    backup ${glance_conf} "MOVE"
    ini_set ${glance_conf} DEFAULT bind_host 0.0.0.0
    ini_set ${glance_conf} database connection "$(get_mysql_connection glance ${glance_dbpass} glance)"
    add_keystone_authtoken ${glance_conf} ${ctrl_host} glance ${glance_pass}
    ini_set ${glance_conf} paste_deploy flavor keystone
    ini_set ${glance_conf} glance_store stores file,http
    ini_set ${glance_conf} glance_store default_store file
    ini_set ${glance_conf} glance_store filesystem_store_datadir /var/lib/glance/images/
    # chmod 640 ${glance_conf}
    # chown root:glance ${glance_conf}
    log "sync glance db"
    su -s /bin/bash glance -c "glance-manage db_sync"
    log "restart glance-api service"
    service_restart glance-api.service
}

init_nova() {
    local ctrl_host=${1}
    local nova_pass=${2}
    local placement_pass=${3}
    local nova_dbpass=${4}
    local placement_dbpass=${5}
    local rabbit_user=${6}
    local rabbit_pass=${7}
    local region=${8:-RegionOne}
    local my_ip=${ctrl_host}
    log "##########################INSTALL NOVA##########################"
    log "Install nova(Compute Service) ctrl node"
    openstack_add_admin_user nova "${nova_pass}"
    openstack_add_admin_user placement "${placement_pass}"
    openstack_add_service_endpoint nova compute "http://${ctrl_host}:8774/v2.1/%(tenant_id)s" "OpenStack Compute service"
    openstack_add_service_endpoint placement placement "http://${ctrl_host}:8778" "OpenStack Compute Placement service"
    create_mysql_db nova nova "${nova_dbpass}"
    create_mysql_db nova_api nova "${nova_dbpass}"
    create_mysql_db nova_cell0 nova "${nova_dbpass}"
    create_mysql_db placement placement "${placement_dbpass}"

    log "Configure Nova create new"
    backup ${nova_conf} "MOVE"
    ini_set ${nova_conf} DEFAULT debug ${OPENSTACK_DEBUG:-false}
    ini_set ${nova_conf} DEFAULT my_ip ${my_ip}
    ini_set ${nova_conf} DEFAULT enabled_apis osapi_compute,metadata
    ini_set ${nova_conf} DEFAULT transport_url rabbit://${rabbit_user}:${rabbit_pass}@${ctrl_host}
    ini_set ${nova_conf} DEFAULT state_path /var/lib/nova
    ini_set ${nova_conf} DEFAULT log_dir /var/log/nova
    # disable the Compute firewall driver by using the nova.virt.firewall.NoopFirewallDriver
    ini_set ${nova_conf} DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
    ini_set ${nova_conf} oslo_concurrency lock_path /var/lib/nova/tmp
    # glance
    ini_set ${nova_conf} glance api_servers http://${ctrl_host}:9292

    ini_set ${nova_conf} api_database connection "$(get_mysql_connection nova ${nova_dbpass} nova_api)"
    ini_set ${nova_conf} database connection "$(get_mysql_connection nova ${nova_dbpass} nova)"

    ini_set ${nova_conf} api auth_strategy keystone
    add_keystone_authtoken ${nova_conf} ${ctrl_host} nova ${nova_pass}
    # # placement
    ini_set ${nova_conf} placement auth_url http://${ctrl_host}:5000
    ini_set ${nova_conf} placement os_region_name RegionOne
    ini_set ${nova_conf} placement auth_type password
    ini_set ${nova_conf} placement project_domain_name default
    ini_set ${nova_conf} placement user_domain_name default
    ini_set ${nova_conf} placement project_name service
    ini_set ${nova_conf} placement username placement
    ini_set ${nova_conf} placement password ${placement_pass}
    ini_del ${nova_conf} placement region_name
    # # enable vnc
    ini_set ${nova_conf} vnc enabled True
    ini_set ${nova_conf} vnc server_listen 0.0.0.0
    ini_set ${nova_conf} vnc server_proxyclient_address '$my_ip'
    ini_set ${nova_conf} vnc novncproxy_base_url http://${ctrl_host}:6080/vnc_auto.html
    # # wsgi
    ini_set ${nova_conf} wsgi api_paste_config /etc/nova/api-paste.ini

    log "Configure Placement create new"
    backup ${placement_conf} "MOVE"
    ini_set ${placement_conf} DEFAULT debug ${OPENSTACK_DEBUG:-false}
    ini_set ${placement_conf} api auth_strategy keystone
    add_keystone_authtoken ${placement_conf} ${ctrl_host} placement ${placement_pass}
    # # placement_database
    ini_set ${placement_conf} placement_database connection "$(get_mysql_connection placement ${placement_dbpass} placement)"
    log "placement db sync"
    su -s /bin/bash placement -c "placement-manage db sync"
    log "nova api db sync"
    su -s /bin/bash nova -c "nova-manage api_db sync"
    log "nova map_cell0"
    su -s /bin/bash nova -c "nova-manage cell_v2 map_cell0"
    log "nova db sync"
    su -s /bin/bash nova -c "nova-manage db sync"
    log "nova create_cell cell1"
    su -s /bin/bash nova -c "nova-manage cell_v2 create_cell --name cell1"
    service_restart nova-api.service nova-conductor.service nova-scheduler.service placement-api.service
}
init_neutron_ml2_plugin() {
    backup ${ml2_conf_ini}
    # ml2 configuration
    ini_set ${ml2_conf_ini} ml2 mechanism_drivers linuxbridge
    # # ['local', 'flat', 'vlan', 'gre', 'vxlan', 'geneve']
    ini_set ${ml2_conf_ini} ml2 type_drivers "flat,vlan"
    ini_set ${ml2_conf_ini} ml2 tenant_network_types ""
    ini_set ${ml2_conf_ini} ml2 extension_drivers ""
    # # flat_networks = public,public2, * allow use any phy network
    ini_set ${ml2_conf_ini} ml2_type_flat flat_networks '*'
    ini_set ${ml2_conf_ini} securitygroup enable_ipset false
    ln -sf ${ml2_conf_ini} /etc/neutron/plugin.ini
}

init_neutron() {
    local ctrl_host=${1}
    local nova_pass=${2}
    local neutron_pass=${3}
    local neutron_dbpass=${4}
    local rabbit_user=${5}
    local rabbit_pass=${6}
    local region=${7:-RegionOne}
    local metadata_secret="metadata_secret"
    log "##########################INSTALL NEUTRON##########################"
    log "Configure OpenStack Network Service (Neutron)."
    openstack_add_admin_user neutron "${neutron_pass}"
    openstack_add_service_endpoint neutron network "http://${ctrl_host}:9696" "OpenStack Networking service"
    create_mysql_db neutron_ml2 neutron "${neutron_dbpass}"

    log "Configure Neutron create new"
    backup ${neutron_conf} "MOVE"
    ini_set ${neutron_conf} DEFAULT debug ${OPENSTACK_DEBUG:-false}
    ini_set ${neutron_conf} DEFAULT core_plugin ml2
    ini_set ${neutron_conf} DEFAULT service_plugins ""
    ini_set ${neutron_conf} DEFAULT notify_nova_on_port_status_changes True
    ini_set ${neutron_conf} DEFAULT notify_nova_on_port_data_changes True
    ini_set ${neutron_conf} DEFAULT transport_url rabbit://${rabbit_user}:${rabbit_pass}@${ctrl_host}
    ### ini_set ${neutron_conf} DEFAULT interface_driver linuxbridge
    ini_set ${neutron_conf} DEFAULT auth_strategy keystone
    add_keystone_authtoken ${neutron_conf} ${ctrl_host} neutron ${neutron_pass}
    # # database
    ini_set ${neutron_conf} database connection "$(get_mysql_connection neutron ${neutron_dbpass} neutron_ml2)"
    ini_set ${neutron_conf} agent root_helper 'sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf'
    ini_set ${neutron_conf} oslo_concurrency lock_path /var/lib/neutron/tmp

    # # Nova connection info
    ini_set ${neutron_conf} nova auth_url http://${ctrl_host}:5000
    ini_set ${neutron_conf} nova auth_type password
    ini_set ${neutron_conf} nova project_domain_name default
    ini_set ${neutron_conf} nova user_domain_name default
    ini_set ${neutron_conf} nova region_name ${region}
    ini_set ${neutron_conf} nova project_name service
    ini_set ${neutron_conf} nova username nova
    ini_set ${neutron_conf} nova password ${nova_pass}

    init_neutron_ml2_plugin
    log "Configure metadata agent"
    backup ${metadata_agent_ini}
    ini_set ${metadata_agent_ini} DEFAULT nova_metadata_host ${ctrl_host}
    ini_set ${metadata_agent_ini} DEFAULT metadata_proxy_shared_secret ${metadata_secret}
    ini_set ${metadata_agent_ini} cache memcache_servers ${ctrl_host}:11211
    service_restart neutron-metadata-agent.service
    log "Configure Neutron in Nova"
    backup ${nova_conf}
    ini_set ${nova_conf} DEFAULT use_neutron True
    ini_set ${nova_conf} DEFAULT vif_plugging_is_fatal false
    ini_set ${nova_conf} DEFAULT vif_plugging_timeout 0
    # # neutron in nova
    ini_set ${nova_conf} neutron auth_url http://${ctrl_host}:5000
    ini_set ${nova_conf} neutron auth_type password
    ini_set ${nova_conf} neutron project_domain_name default
    ini_set ${nova_conf} neutron user_domain_name default
    ini_set ${nova_conf} neutron region_name ${region}
    ini_set ${nova_conf} neutron project_name service
    ini_set ${nova_conf} neutron username neutron
    ini_set ${nova_conf} neutron password ${neutron_pass}
    ini_set ${nova_conf} neutron service_metadata_proxy True
    ini_set ${nova_conf} neutron metadata_proxy_shared_secret ${metadata_secret}

    su -s /bin/bash neutron -c "neutron-db-manage --config-file ${neutron_conf} --config-file /etc/neutron/plugin.ini upgrade head"
    # ctrl node not a compute note no need neutron-linuxbridge-agent.service
    service_restart neutron-api.service neutron-rpc-server.service neutron-metadata-agent.service nova-api.service
}

init_horizon() {
    local ctrl_host=${1}
    log "##########################INSTALL HORIZON##########################"
    log "Configure OpenStack Dashboard Service (Horizon)."
    backup ${horizon_settings_py}
    sed -i -E \
        -e "s/^\s*#*\s*ALLOWED_HOSTS\s*=.*/ALLOWED_HOSTS = ['${ctrl_host}', 'localhost', ]/g" \
        -e 's/^\s*#*\s*SESSION_ENGINE\s*=.*/SESSION_ENGINE = "django.contrib.sessions.backends.cache"/g' \
        -e "s/^\s*#*\s*OPENSTACK_HOST\s*=.*/OPENSTACK_HOST = \"${ctrl_host}\"/g" \
        -e "s/^\s*#*\s*OPENSTACK_KEYSTONE_URL\s*=.*/OPENSTACK_KEYSTONE_URL = \"http:\/\/${ctrl_host}:5000\/v3\"/g" \
        -e 's/^\s*#*\s*TIME_ZONE\s*=.*/TIME_ZONE = "Asia\/Shanghai"/g' \
        ${horizon_settings_py}

    backup ${horizon_debian_cache_py}
    sed -i -E \
        -e "s/^\s*'BACKEND'\s*:.*/'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache', 'LOCATION': '${ctrl_host}:11211',/g" \
        ${horizon_debian_cache_py}

    backup ${horizon_dashboard_conf}
    tee ${horizon_dashboard_conf} <<EOF
WSGIScriptAlias / /usr/share/openstack-dashboard/wsgi.py process-group=horizon
WSGIDaemonProcess horizon user=horizon group=horizon processes=3 threads=10 display-name=%{GROUP}
WSGIProcessGroup horizon
WSGIApplicationGroup %{GLOBAL}

Alias /static /var/lib/openstack-dashboard/static/
Alias /horizon/static /var/lib/openstack-dashboard/static/

<Directory /usr/share/openstack-dashboard>
  Require all granted
</Directory>

<Directory /var/lib/openstack-dashboard/static>
  Require all granted
</Directory>
EOF
    a2enconf openstack-dashboard
    mv /etc/openstack-dashboard/policy /etc/openstack-dashboard/policy.org
    chown -R horizon /var/lib/openstack-dashboard/secret-key
    service_restart apache2.service || log "need restart apache2.service youself!!!!!!!!!!!!!!!!!"

    backup ${nova_consoleproxy}
    sed -i -E \
        -e 's/^\s*NOVA_CONSOLE_PROXY_TYPE\s*=.*/NOVA_CONSOLE_PROXY_TYPE=novnc/g' \
        ${nova_consoleproxy}
    service_restart nova-novncproxy.service || log "need restart nova-novncproxy.service youself!!!!!!!!!!!!!!!!!"
}
####################################################################################################
init_nova_compute() {
    local compute_host=${1}
    local ctrl_host=${2}
    local nova_pass=${3}
    local placement_pass=${4}
    local rabbit_user=${5}
    local rabbit_pass=${6}
    local my_ip=${compute_host}
    # getent hosts ctl01 | grep -v 127.0.0.1 | awk '{print $1}'
    log "##########################INSTALL NOVA COMPUTE##########################"
    log "Install KVM HyperVisor on Compute Host"
    backup ${nova_compute_conf}
    ini_set ${nova_compute_conf} DEFAULT compute_driver libvirt.LibvirtDriver
    # # kvm/qemu
    ini_set ${nova_compute_conf} libvirt virt_type kvm

    log "Configure Nova compute node create new"
    backup ${nova_conf} "MOVE"
    ini_set ${nova_conf} DEFAULT my_ip ${my_ip}
    ini_set ${nova_conf} DEFAULT debug ${OPENSTACK_DEBUG:-false}
    ini_set ${nova_conf} DEFAULT enabled_apis osapi_compute,metadata
    ini_set ${nova_conf} DEFAULT transport_url rabbit://${rabbit_user}:${rabbit_pass}@${ctrl_host}
    ini_set ${nova_conf} DEFAULT state_path /var/lib/nova
    ini_set ${nova_conf} DEFAULT log_dir /var/log/nova
    ini_set ${nova_conf} oslo_concurrency lock_path /var/lib/nova/tmp
    # # glance
    ini_set ${nova_conf} glance api_servers http://${ctrl_host}:9292

    ini_set ${nova_conf} api auth_strategy keystone
    add_keystone_authtoken ${nova_conf} ${ctrl_host} nova ${nova_pass}
    # # placement
    ini_set ${nova_conf} placement auth_url http://${ctrl_host}:5000
    ini_set ${nova_conf} placement os_region_name RegionOne
    ini_set ${nova_conf} placement auth_type password
    ini_set ${nova_conf} placement project_domain_name default
    ini_set ${nova_conf} placement user_domain_name default
    ini_set ${nova_conf} placement project_name service
    ini_set ${nova_conf} placement username placement
    ini_set ${nova_conf} placement password ${placement_pass}
    ini_del ${nova_conf} placement region_name
    # # enable vnc
    ini_set ${nova_conf} vnc enabled True
    ini_set ${nova_conf} vnc server_listen 0.0.0.0
    ini_set ${nova_conf} vnc server_proxyclient_address '$my_ip'
    ini_set ${nova_conf} vnc novncproxy_base_url http://${ctrl_host}:6080/vnc_auto.html
    # # wsgi
    ini_set ${nova_conf} wsgi api_paste_config /etc/nova/api-paste.ini
    service_restart nova-compute.service
}

init_linux_bridge_plugin() {
    local net_tag=${1}
    local mapping_dev=${2}
    backup ${linuxbridge_agent_ini}
    # linuxbridge configuration
    ini_set ${linuxbridge_agent_ini} DEFAULT debug true #${OPENSTACK_DEBUG:-false}
    ini_set ${linuxbridge_agent_ini} vxlan enable_vxlan False

    # # map to exists bridge
    # # bridge_mappings configuration must correlate with network_vlan_ranges option on the controller node
    # ini_set ${ml2_conf_ini} ml2_type_vlan network_vlan_ranges ${net_tag}
    ini_append_list ${linuxbridge_agent_ini} linux_bridge bridge_mappings "${net_tag}:${mapping_dev}"
    ini_append_list ${linuxbridge_agent_ini} linux_bridge physical_interface_mappings "${net_tag}:${mapping_dev}"

    ini_set ${linuxbridge_agent_ini} securitygroup enable_security_group false
    ini_set ${linuxbridge_agent_ini} securitygroup firewall_driver neutron.agent.firewall.NoopFirewallDriver
    ini_set ${linuxbridge_agent_ini} securitygroup enable_ipset false
    # ini_set ${linuxbridge_agent_ini} securitygroup enable_security_group True
    # ini_set ${linuxbridge_agent_ini} securitygroup firewall_driver neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
    # # dhcp agent configuration
    # ini_set /etc/neutron/dhcp_agent.ini DEFAULT interface_driver linuxbridge
    # ini_set /etc/neutron/dhcp_agent.ini DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
    # ini_set /etc/neutron/dhcp_agent.ini DEFAULT enable_isolated_metadata true
}
init_neutron_compute() {
    local compute_host=${1}
    local ctrl_host=${2}
    local neutron_pass=${3}
    local placement_pass=${4}
    local rabbit_user=${5}
    local rabbit_pass=${6}
    local region="${7:-RegionOne}"
    log "Configure Neutron compute node create new"
    backup ${neutron_conf} "MOVE"
    ini_set ${neutron_conf} DEFAULT transport_url rabbit://${rabbit_user}:${rabbit_pass}@${ctrl_host}

    ini_set ${neutron_conf} DEFAULT auth_strategy keystone
    ini_set ${neutron_conf} agent root_helper 'sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf'

    add_keystone_authtoken ${neutron_conf} ${ctrl_host} neutron ${neutron_pass}

    log "on compute node only ${linuxbridge_agent_ini} need modiry"
    init_neutron_ml2_plugin

    backup ${nova_conf}
    # # neutron in nova
    ini_set ${nova_conf} neutron auth_url http://${ctrl_host}:5000
    ini_set ${nova_conf} neutron auth_type password
    ini_set ${nova_conf} neutron project_domain_name default
    ini_set ${nova_conf} neutron user_domain_name default
    ini_set ${nova_conf} neutron region_name ${region}
    ini_set ${nova_conf} neutron project_name service
    ini_set ${nova_conf} neutron username neutron
    ini_set ${nova_conf} neutron password ${neutron_pass}
    service_restart nova-compute.service neutron-linuxbridge-agent.service
}
####################################################################################################
add_neutron_linux_bridge_net() {
    local net_name=${1}
    log "Create network [${net_name}]"
    local id=$(openstack project create --domain default service --or-show -f value -c id)
    openstack network show ${net_name}-net 2>/dev/null || openstack network create --project ${id} --external --share --provider-network-type flat --provider-physical-network ${net_name} ${net_name}-net -c id -c project_id
    log "create subnet"
    openstack subnet show subnet-${net_name}-net 2>/dev/null || openstack subnet create subnet-${net_name}-net --network ${net_name}-net \
        --no-dhcp \
        --project ${id} --subnet-range 192.168.168.0/24 \
        --gateway 192.168.168.1 --dns-nameserver 114.114.114.114 \
        -c id -c network_id -c project_id
}
addflaver() {
    local name=m1.small
    log "create a flavor [${name}]"
    openstack flavor show ${name} 2>/dev/null || openstack flavor create --vcpus 1 --ram 256 --disk 4 ${name} || true
}
adduser() {
    project=${1}
    user=${2}
    pass=${3}
    log "create a project"
    openstack project create --domain default --description "my project ${project}" ${project} --or-show -f value -c id
    log "create a user ${user}"
    openstack user create --domain default --project ${project} --password ${pass} ${user} --or-show -f value -c id
    log "create a role"
    openstack role create CloudUser --or-show -f value -c id
    log "create a user to the role CloudUser"
    openstack role add --project ${project} --user ${user} CloudUser
}
####################################################################################################
verify_neutron() {
    log "Verify Neutron installation"
    source ~/keystonerc
    openstack extension list --network
    openstack network agent list
}
verify_nova() {
    log "Verify Nova Installation"
    source ~/keystonerc
    log "List service components to verify successful launch and registration of each process"
    nova-manage cell_v2 list_cells
    openstack compute service list
    openstack catalog list
    openstack image list
    nova-status upgrade check || true
}
verify_glance() {
    log "verify glance installation"
    source ~/keystonerc
    local img="cirros.qcow2"
    local img_name=cirros
    log "Create Image Cirros"
    log "IMG: wget -O ${img} http://download.cirros-cloud.net/0.3.5/cirros-0.3.5-x86_64-disk.img"
    [ -e "${img}" ] || { log "wget --no-check-certificate -O ${img} http://download.cirros-cloud.net/0.3.5/cirros-0.3.5-x86_64-disk.img"; qemu-img create -f qcow2 ${img} 2G; }
    openstack image show ${img_name} 2>/dev/null ||\
        openstack image create "${img_name}" --file ${img} --disk-format qcow2 --container-format bare --public
    openstack image list
}
verify_keystone() {
    log "Verify Keystone Installation"
    source ~/keystonerc
    openstack project list
    openstack user list
    openstack service list
    openstack role list
    openstack endpoint list
}

verify_all() {
    source ~/keystonerc
    log "verify all"
    verify_keystone
    verify_glance
    verify_neutron
    verify_nova
    log "openstack service list"
    openstack service list
    log "openstack compute service list"
    # openstack resource provider list --name kvm01
    # openstack resource provider show --allocations de7072db-f20c-4bf9-9ece-74e359f54b8f
    openstack compute service list|| true
    log "openstack network agent list"
    openstack network agent list || true
    log "openstack network list"
    openstack network list || true
    log "openstack subnet list"
    openstack subnet list || true
    log "openstack image list"
    openstack image list || true
    log "openstack flavor list"
    openstack flavor list || true
    log "openstack extension list --network"
    openstack extension list --network || true
#    local secgroup=secgroup01
#    log "create a security group [${secgroup}]"
#    openstack security group show ${secgroup} 2>/dev/null || openstack security group create ${secgroup} || true
#    local key_name=mykey
#    log "add public-keyc [${key_name}]"
#    rm -f test.key test.key.pub 2>/dev/null || true
#    ssh-keygen -q -N "" -f  test.key
#    openstack keypair show ${key_name} 2>/dev/null || \
#        openstack keypair create --public-key test.key.pub ${key_name} -f value -c fingerprint || true
    log "openstack server create --flavor m1.small --image cirros --nic net-id=\$(openstack network show YOU_NET_ID -c id -f value) testvm1"
    log "openstack server show testvm1 "
}
####################################################################################################
teardown() {
    sed -i '/keystonerc/d' ~/.bashrc || true
    rm -f ~/keystonerc  || true
    for s in keystone.service \
        glance-api.service \
        nova-api.service \
        nova-api-metadata.service \
        nova-compute.service \
        nova-conductor.service \
        nova-novncproxy.service \
        nova-scheduler.service \
        nova-serialproxy.service \
        nova-spicehtml5proxy.service \
        neutron-api.service \
        neutron-dhcp-agent.service \
        neutron-l3-agent.service \
        neutron-linuxbridge-agent.service \
        neutron-metadata-agent.service \
        neutron-rpc-server.service \
        placement-api.service \
        rabbitmq-server.service \
        memcached.service; do
        log "stop & disable service ${s}"
        systemctl stop ${s} &>/dev/null || true
        systemctl disable ${s} &>/dev/null || true
    done
    command -v "mysql" &> /dev/null && {
        log "stop & disable service mariadb"
        systemctl stop mariadb.service --force &>/dev/null || true
        systemctl disable mariadb.service &>/dev/null || true
        datadir=$(ini_get ${my_conf} mysqld datadir) || true
        [ -z "${datadir}" ] || rm -vrf "${datadir}" || true
    }
    for d in keystone glance nova placement neutron rabbitmq libvirt; do
        rm -vrf /var/log/${d}/* || true
    done
    [ -d "${BACK_DIR}" ] && {
        log "restore backup config"
        for __cfg in ${my_conf} ${memcached_conf} ${keystone_conf} \
            ${glance_conf} ${nova_conf} ${nova_compute_conf} ${placement_conf} \
            ${neutron_conf} ${metadata_agent_ini} ${ml2_conf_ini} ${linuxbridge_agent_ini}; do
            echo ${__cfg}
            __backup=$(basename ${__cfg})
            [ -e "${BACK_DIR}/${__backup}" ] && {
                log "restore config ${__cfg}"
                cat ${BACK_DIR}/${__backup} > ${__cfg}
            } || {
                log "config ${__cfg} HAS NOT BACKUP"
            }
        done
    }
    log "TEARDOWN ALL DONE"
}

init_ctrl_node() {
    local ctrl=${1}
    local net_tag=${2}
    prepare_env "${ctrl}" "${KEYSTONE_USER}" "${KEYSTONE_PASS}"
    prepare_db_mq "${RABBIT_USER}" "${RABBIT_PASS}"
    init_keystone "${ctrl}" "${KEYSTONE_USER}" "${KEYSTONE_PASS}" "${KEYSTONE_DBPASS}"
    init_glance "${ctrl}" "${GLANCE_PASS}" "${GLANCE_DBPASS}"
    init_nova "${ctrl}" "${NOVA_PASS}" "${PLACEMENT_PASS}" "${NOVA_DBPASS}" "${PLACEMENT_DBPASS}" "${RABBIT_USER}" "${RABBIT_PASS}"
    init_neutron "${ctrl}" "${NOVA_PASS}" "${NEUTRON_PASS}" "${NEUTRON_DBPASS}" "${RABBIT_USER}" "${RABBIT_PASS}"
    add_neutron_linux_bridge_net "${net_tag}"
    addflaver
    adduser "tsd" "user1" "password"
    init_horizon "${ctrl}"
    log "CTRL NODE ALL DONE"
}

init_compute_node() {
    local compute=${1}
    local ctrl=${2}
    local tag=${3}
    local dev=${dev}
    prepare_env "${ctrl}" "${KEYSTONE_USER}" "${KEYSTONE_PASS}"
    init_nova_compute "${compute}" "${ctrl}" "${NOVA_PASS}" "${PLACEMENT_PASS}" "${RABBIT_USER}" "${RABBIT_PASS}"
    init_neutron_compute "${compute}" "${ctrl}" "${NEUTRON_PASS}" "${PLACEMENT_PASS}" "${RABBIT_USER}" "${RABBIT_PASS}"
    init_linux_bridge_plugin "${tag}" "${dev}"
    #init_linux_bridge_plugin vlan100 "bond1"
    service_restart nova-compute.service neutron-linuxbridge-agent.service
    #nova.conf修改时间间隔:
    #[scheduler]
    #discover_hosts_in_cells_interval = 300
    log 'su -s /bin/bash nova -c "nova-manage cell_v2 discover_hosts --verbose"'
    log "openstack compute service list"
    log "COMPUT NODE ALL DONE"
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME} <ctrl|compute|teardown>
        -C|--ctrl     * *    <ipaddr> controller node ipaddress
        -c|--compute    *    <ipaddr> compute node ipaddress
        --tag         * *    network tag
        --dev           *    network mapping dev(in bridge)
        -v|--verify       *  <keystone|glance|nova|neutron|all>
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
$(sed -n '/^##OPTION_START/,/^##OPTION_END/p' ${SCRIPTNAME})
 CTRL:
    apt -y install rabbitmq-server memcached python3-pymysql mariadb-server
    apt -y install keystone python3-openstackclient apache2 libapache2-mod-wsgi-py3 python3-oauth2client
    apt -y install glance
    apt -y install nova-api nova-conductor nova-scheduler nova-novncproxy placement-api python3-novaclient
    apt -y install neutron-server neutron-plugin-ml2 neutron-linuxbridge-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent python3-neutronclient
    apt -y install openstack-dashboard
 COMPUTE
    apt -y install nova-compute nova-compute-kvm qemu-system-data
    apt -y install neutron-common neutron-plugin-ml2 neutron-linuxbridge-agent
    apt -y install qemu-kvm libvirt-daemon-system libvirt-daemon bridge-utils libosinfo-bin
EOF
    exit 1
}
main() {
    local verify="" ctrl="" compute="" tag="" dev=""
    local opt_short="v:C:c:"
    local opt_long="verify:,ctrl:,compute:,tag:,dev:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -C | --ctrl)    shift; ctrl=${1}; MYSQL_HOST=${1}; shift;;
            -c | --compute) shift; compute=${1}; shift;;
            --tag)          shift; tag=${1}; shift;;
            --dev)          shift; dev=${1}; shift;;
            -v | --verify)  shift; declare -f -F verify_${1} >/dev/null && { verify_${1}; log "VERIFY [${1}] DONE"; } || usage; exit 0; shift;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    case "${1:-}" in
        ctrl)
            [ -z "${ctrl}" ] || [ -z "${tag}" ] && usage "ctrl, tag must input"
            init_ctrl_node "${ctrl}" "${tag}";;
        compute)
            [ -z "${ctrl}" ] || [ -z "${compute}" ] || [ -z "${tag}" ] || [ -z "${dev}" ] && usage "ctrl & compute, tag, dev must input"
            init_compute_node "${compute}" "${ctrl}" "${tag}" "${dev}"
            ;;
        teardown)   teardown ;;
        *)          usage "ctrl/compute/teardown";;
    esac
    return 0
}
main "$@"
: <<EOF
        eth0|192.168.168.101
+-----------+-----------+
|    [ Control Node ]   |
|                       |
|  MariaDB    RabbitMQ  |
|  Memcached  httpd     |
|  Keystone   Glance    |
|  Nova API             |
+-----------------------+
     Service                   Code_Name       Description
01   Identity Service          Keystone        User Management
02   Compute Service           Nova            Virtual Machine Management
03   Image Service             Glance          Manages Virtual image like kernel image or disk image
04   Dashboard                 Horizon         Provides GUI console via Web browser
05   Object Storage            Swift           Provides Cloud Storage feature
06   Block Storage             Cinder          Storage Management for Virtual Machine
07   Network Service           Neutron         Virtual Networking Management
08   Load Balancing Service    Octavia         Provides Load Balancing feature
09   Orchestration Service     Heat            Provides Orchestration feature for Virtual Machine
10   Metering Service          Ceilometer      Provides the feature of Usage measurement for accounting
11   Database Service          Trove           Database resource Management
12   Container Service         Magnum          Container Infrastructure Management
13   Data Processing Service   Sahara          Provides Data Processing feature
14   Bare Metal Provisioning   Ironic          Provides Bare Metal Provisioning feature
15   Messaging Service         Zaqar           Provides Messaging Service feature
16   Shared File System        Manila          Provides File Sharing Service
17   DNS Service               Designate       Provides DNS Server Service
18   Key Manager Service       Barbican        Provides Key Management Service
EOF
####################################################################################################
