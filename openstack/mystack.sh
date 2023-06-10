#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("5a0b056[2023-06-10T11:57:07+08:00]:mystack.sh")
set -o errtrace  # trace ERR through 'time command' and other functions
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
# [ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
MYSQL_PASS=${MYSQL_PASS:-}
PUBLIC_NETWORK=public
OPENSTACK_DEBUG=true

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

LOGFILE=""
GREEN=$(tput setaf 70)
RESET=$(tput sgr0)
TIMESPAN=$(date '+%Y%m%d%H%M%S')

log() { echo "## ${GREEN}$*${RESET}" | tee ${LOGFILE} >&2; }

backup() {
    local src=${1}
    [ -d "${TIMESPAN}" ] || mkdir -p ${TIMESPAN}
    local backup=$(basename ${src})
    log "BACKUP: ${src} => ${TIMESPAN} "
    [ -e "${TIMESPAN}/${backup}" ] && return 0
    cat ${src} 2>/dev/null > ${TIMESPAN}/${backup} || true
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
    local key=${3}
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
flush privileges;
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
    mysql_install_db -u mysql &>/dev/null
    systemctl enable mariadb --now

    # mysql_secure_installation
    # echo -e "\nY\n$MYSQLDB_PASSWORD\n$MYSQLDB_PASSWORD\nY\nn\nY\nY\n" | mysql_secure_installation
    log "Add the rabbitmq user [${rabbit_user}]"
    systemctl enable rabbitmq-server --now
    rabbitmqctl delete_user openstack 2>/dev/null || true
    rabbitmqctl add_user ${rabbit_user} ${rabbit_pass}
    rabbitmqctl set_permissions ${rabbit_user} ".*" ".*" ".*"

    backup ${memcached_conf}
    sed -i -E \
        -e 's/^\s*#*\s*-l \s*.*/-l 0.0.0.0/g' \
        ${memcached_conf}
    systemctl enable memcached --now || true
}

init_keystone() {
    local ctrl_host=${1}
    local keystone_user=${2}
    local keystone_pass=${3}
    local keystone_dbpass=${4}
    local region=${5:-RegionOne}
    log "##########################INSTALL KEYSTONE##########################"
    systemctl enable keystone --now || true
    create_mysql_db keystone keystone "${keystone_dbpass}"
    backup ${keystone_conf}
    ini_set ${keystone_conf} database connection mysql+pymysql://keystone:${keystone_dbpass}@${ctrl_host}/keystone
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
    log "Configure Glance"
    backup ${glance_conf}
    ini_set ${glance_conf} DEFAULT bind_host 0.0.0.0
    ini_set ${glance_conf} database connection mysql+pymysql://glance:${glance_dbpass}@${ctrl_host}/glance
    ini_set ${glance_conf} keystone_authtoken auth_url http://${ctrl_host}:5000
    ini_set ${glance_conf} keystone_authtoken www_authenticate_uri http://${ctrl_host}:5000
    ini_set ${glance_conf} keystone_authtoken memcached_servers ${ctrl_host}:11211
    ini_set ${glance_conf} keystone_authtoken auth_type password
    ini_set ${glance_conf} keystone_authtoken project_domain_name default
    ini_set ${glance_conf} keystone_authtoken user_domain_name default
    ini_set ${glance_conf} keystone_authtoken project_name service
    ini_set ${glance_conf} keystone_authtoken username glance
    ini_set ${glance_conf} keystone_authtoken password ${glance_pass}
    ini_del ${glance_conf} keystone_authtoken region_name
    ini_set ${glance_conf} paste_deploy flavor keystone
    ini_set ${glance_conf} glance_store stores file,http
    ini_set ${glance_conf} glance_store default_store file
    ini_set ${glance_conf} glance_store filesystem_store_datadir /var/lib/glance/images/
    # chmod 640 ${glance_conf}
    # chown root:glance ${glance_conf}
    log "sync glance db"
    su -s /bin/bash glance -c "glance-manage db_sync"
    log "restart service"
    systemctl enable glance-api --now
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
    log "Add users and others for Nova in Keystone."
    openstack_add_admin_user nova "${nova_pass}"
    openstack_add_admin_user placement "${placement_pass}"
    openstack_add_service_endpoint nova compute "http://${ctrl_host}:8774/v2.1/%(tenant_id)s" "OpenStack Compute service"
    openstack_add_service_endpoint placement placement "http://${ctrl_host}:8778" "OpenStack Compute Placement service"
    create_mysql_db nova nova "${nova_dbpass}"
    create_mysql_db nova_api nova "${nova_dbpass}"
    create_mysql_db nova_cell0 nova "${nova_dbpass}"
    create_mysql_db placement placement "${placement_dbpass}"

    backup ${nova_conf}
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

    ini_set ${nova_conf} api_database connection mysql+pymysql://nova:${nova_dbpass}@${ctrl_host}/nova_api
    ini_set ${nova_conf} database connection mysql+pymysql://nova:${nova_dbpass}@${ctrl_host}/nova

    ini_set ${nova_conf} api auth_strategy keystone
    ini_set ${nova_conf} keystone_authtoken www_authenticate_uri http://${ctrl_host}:5000
    ini_set ${nova_conf} keystone_authtoken auth_url http://${ctrl_host}:5000
    ini_set ${nova_conf} keystone_authtoken memcached_servers ${ctrl_host}:11211
    ini_set ${nova_conf} keystone_authtoken auth_type password
    ini_set ${nova_conf} keystone_authtoken project_domain_name default
    ini_set ${nova_conf} keystone_authtoken user_domain_name default
    ini_set ${nova_conf} keystone_authtoken project_name service
    ini_set ${nova_conf} keystone_authtoken username nova
    ini_set ${nova_conf} keystone_authtoken password ${nova_pass}
    ini_del ${nova_conf} keystone_authtoken region_name
    # # enable vnc
    # ini_set ${nova_conf} vnc enabled True
    ini_set ${nova_conf} vnc server_listen 0.0.0.0
    ini_set ${nova_conf} vnc server_proxyclient_address '$my_ip'
    # ini_set ${nova_conf} vnc novncproxy_base_url http://${ctrl_host}:6080/vnc_auto.html
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
    # # wsgi
    ini_set ${nova_conf} wsgi api_paste_config /etc/nova/api-paste.ini

    backup ${placement_conf}
    ini_set ${placement_conf} DEFAULT debug ${OPENSTACK_DEBUG:-false}
    ini_set ${placement_conf} api auth_strategy keystone
    # # keystone_authtoken
    ini_set ${placement_conf} keystone_authtoken www_authenticate_uri http://${ctrl_host}:5000
    ini_set ${placement_conf} keystone_authtoken auth_url http://${ctrl_host}:5000
    ini_set ${placement_conf} keystone_authtoken memcached_servers ${ctrl_host}:11211
    ini_set ${placement_conf} keystone_authtoken auth_type password
    ini_set ${placement_conf} keystone_authtoken project_domain_name default
    ini_set ${placement_conf} keystone_authtoken user_domain_name default
    ini_set ${placement_conf} keystone_authtoken project_name service
    ini_set ${placement_conf} keystone_authtoken username placement
    ini_set ${placement_conf} keystone_authtoken password ${placement_pass}
    ini_del ${placement_conf} keystone_authtoken region_name
    # # placement_database
    ini_set ${placement_conf} placement_database connection mysql+pymysql://placement:${placement_dbpass}@${ctrl_host}/placement
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

    # systemctl restart apache2
    log "restart service"
    systemctl restart nova-api
    systemctl restart nova-conductor
    systemctl restart nova-scheduler
    systemctl restart placement-api
    systemctl enable nova-api nova-conductor nova-scheduler --now || true
    systemctl enable placement-api --now || true
}

modify_linux_bridge_plugin() {
    local public_network=${1}
    local mapping_dev=${2}
    backup ${ml2_conf_ini}
    # ml2 configuration
    ini_set ${ml2_conf_ini} ml2 type_drivers "flat,vlan"
    ini_set ${ml2_conf_ini} ml2 tenant_network_types ""
    ini_set ${ml2_conf_ini} ml2 mechanism_drivers linuxbridge
    ini_set ${ml2_conf_ini} ml2 extension_drivers port_security
    ini_set ${ml2_conf_ini} ml2_type_flat flat_networks ${public_network}
    ini_set ${ml2_conf_ini} securitygroup enable_ipset True
    backup ${linuxbridge_agent_ini}
    # linuxbridge configuration
    ini_set ${linuxbridge_agent_ini} vxlan enable_vxlan False
    ini_set ${linuxbridge_agent_ini} linux_bridge physical_interface_mappings ${public_network}:${mapping_dev}
    # # map to exists bridge
    ini_set ${linuxbridge_agent_ini} linux_bridge bridge_mappings ${public_network}:${mapping_dev}
    ini_set ${linuxbridge_agent_ini} securitygroup enable_security_group False
    ini_set ${linuxbridge_agent_ini} securitygroup firewall_driver neutron.agent.firewall.NoopFirewallDriver
    # ini_set ${linuxbridge_agent_ini} securitygroup enable_security_group True
    # ini_set ${linuxbridge_agent_ini} securitygroup firewall_driver neutron.agent.linux.iptables_firewall.IptablesFirewallDriver

    # # dhcp agent configuration
    # ini_set /etc/neutron/dhcp_agent.ini DEFAULT interface_driver linuxbridge
    # ini_set /etc/neutron/dhcp_agent.ini DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
    # ini_set /etc/neutron/dhcp_agent.ini DEFAULT enable_isolated_metadata true

    ln -sf ${ml2_conf_ini} /etc/neutron/plugin.ini
    systemctl enable neutron-linuxbridge-agent.service --now
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
    backup ${neutron_conf}
    ini_set ${neutron_conf} DEFAULT auth_strategy keystone
    ini_set ${neutron_conf} DEFAULT core_plugin ml2
    ini_set ${neutron_conf} DEFAULT service_plugins ""
    ini_set ${neutron_conf} DEFAULT notify_nova_on_port_status_changes True
    ini_set ${neutron_conf} DEFAULT notify_nova_on_port_data_changes True
    ini_set ${neutron_conf} DEFAULT transport_url rabbit://${rabbit_user}:${rabbit_pass}@${ctrl_host}
    # # database
    ini_set ${neutron_conf} database connection mysql+pymysql://neutron:${neutron_dbpass}@${ctrl_host}/neutron_ml2

    # # keystone_authtoken
    ini_set ${neutron_conf} keystone_authtoken www_authenticate_uri http://${ctrl_host}:5000
    ini_set ${neutron_conf} keystone_authtoken auth_url http://${ctrl_host}:5000
    ini_set ${neutron_conf} keystone_authtoken memcached_servers ${ctrl_host}:11211
    ini_set ${neutron_conf} keystone_authtoken auth_type password
    ini_set ${neutron_conf} keystone_authtoken project_domain_name default
    ini_set ${neutron_conf} keystone_authtoken user_domain_name default
    ini_set ${neutron_conf} keystone_authtoken project_name service
    ini_set ${neutron_conf} keystone_authtoken username neutron
    ini_set ${neutron_conf} keystone_authtoken password ${neutron_pass}
    ini_del ${neutron_conf} keystone_authtoken region_name
    # # Nova connection info
    ini_set ${neutron_conf} nova auth_url http://${ctrl_host}:5000
    ini_set ${neutron_conf} nova auth_type password
    ini_set ${neutron_conf} nova project_domain_name default
    ini_set ${neutron_conf} nova user_domain_name default
    ini_set ${neutron_conf} nova region_name ${region}
    ini_set ${neutron_conf} nova project_name service
    ini_set ${neutron_conf} nova username nova
    ini_set ${neutron_conf} nova password ${nova_pass}

    modify_linux_bridge_plugin ${PUBLIC_NETWORK} "br-ext"

    backup ${metadata_agent_ini}
    ini_set ${metadata_agent_ini} DEFAULT nova_metadata_host ${ctrl_host}
    ini_set ${metadata_agent_ini} DEFAULT metadata_proxy_shared_secret ${metadata_secret}
    ini_set ${metadata_agent_ini} cache memcache_servers ${ctrl_host}:11211
    systemctl enable neutron-metadata-agent.service --now
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
    systemctl restart neutron-api neutron-rpc-server neutron-metadata-agent neutron-metadata-agent neutron-linuxbridge-agent
    systemctl enable neutron-api neutron-rpc-server neutron-metadata-agent neutron-metadata-agent neutron-linuxbridge-agent --now || true
    systemctl restart nova-api
}

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
    # on Debian 11 default is set cgroup v2, however,
    # specific feature does not work on Nova-Compute, so fall back to cgroup v1
    # sed -i -E \
    #     's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=false systemd.legacy_systemd_cgroup_controller=false"/g' \
    #     /etc/default/grub
    # update-grub
    # reboot
    backup ${nova_compute_conf}
    ini_set ${nova_compute_conf} DEFAULT compute_driver libvirt.LibvirtDriver
    # # kvm/qemu
    ini_set ${nova_compute_conf} libvirt virt_type kvm

    backup ${nova_conf}
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
    ini_set ${nova_conf} keystone_authtoken www_authenticate_uri http://${ctrl_host}:5000
    ini_set ${nova_conf} keystone_authtoken auth_url http://${ctrl_host}:5000
    ini_set ${nova_conf} keystone_authtoken memcached_servers ${ctrl_host}:11211
    ini_set ${nova_conf} keystone_authtoken auth_type password
    ini_set ${nova_conf} keystone_authtoken project_domain_name default
    ini_set ${nova_conf} keystone_authtoken user_domain_name default
    ini_set ${nova_conf} keystone_authtoken project_name service
    ini_set ${nova_conf} keystone_authtoken username nova
    ini_set ${nova_conf} keystone_authtoken password ${nova_pass}
    ini_del ${nova_conf} keystone_authtoken region_name
    # # enable vnc
    ini_set ${nova_conf} vnc enabled True
    ini_set ${nova_conf} vnc server_listen 0.0.0.0
    ini_set ${nova_conf} vnc server_proxyclient_address '$my_ip'
    ini_set ${nova_conf} vnc novncproxy_base_url http://${ctrl_host}:6080/vnc_auto.html
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
    # # wsgi
    ini_set ${nova_conf} wsgi api_paste_config /etc/nova/api-paste.ini

    log "start nova-compute.service, maybe failed, before neutron network not ready!"
    systemctl enable nova-compute --now 2>/dev/null || true
}

init_neutron_compute() {
    local compute_host=${1}
    local ctrl_host=${2}
    local neutron_pass=${3}
    local placement_pass=${4}
    local rabbit_user=${5}
    local rabbit_pass=${6}
    local region="${7:-RegionOne}"
    backup ${neutron_conf}
    ini_set ${neutron_conf} DEFAULT auth_strategy keystone
    ini_set ${neutron_conf} DEFAULT transport_url rabbit://${rabbit_user}:${rabbit_pass}@${ctrl_host}
    # # keystone_authtoken
    ini_set ${neutron_conf} keystone_authtoken www_authenticate_uri http://${ctrl_host}:5000
    ini_set ${neutron_conf} keystone_authtoken auth_url http://${ctrl_host}:5000
    ini_set ${neutron_conf} keystone_authtoken memcached_servers ${ctrl_host}:11211
    ini_set ${neutron_conf} keystone_authtoken auth_type password
    ini_set ${neutron_conf} keystone_authtoken project_domain_name default
    ini_set ${neutron_conf} keystone_authtoken user_domain_name default
    ini_set ${neutron_conf} keystone_authtoken project_name service
    ini_set ${neutron_conf} keystone_authtoken username neutron
    ini_set ${neutron_conf} keystone_authtoken password ${neutron_pass}
    ini_del ${neutron_conf} keystone_authtoken region_name

    log "on compute node only ${linuxbridge_agent_ini} need modiry"
    modify_linux_bridge_plugin ${PUBLIC_NETWORK} "br-ext"

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
    # # placement
    ini_set ${nova_conf} placement auth_url http://${ctrl_host}:5000
    ini_set ${nova_conf} placement auth_type password
    ini_set ${nova_conf} placement project_domain_name default
    ini_set ${nova_conf} placement user_domain_name default
    ini_set ${nova_conf} placement project_name service
    ini_set ${nova_conf} placement username placement
    ini_set ${nova_conf} placement password ${placement_pass}
    ini_del ${nova_conf} placement region_name

    systemctl restart nova-compute neutron-linuxbridge-agent
    systemctl enable  nova-compute neutron-linuxbridge-agent --now || true
}

ctrller_discover_compute_node() {
    backup /etc/default/nova-consoleproxy
    sed -i -E \
        -e 's/^\s*NOVA_CONSOLE_PROXY_TYPE\s*=.*/NOVA_CONSOLE_PROXY_TYPE=novnc/g' \
        /etc/default/nova-consoleproxy
    log "Start Nova Compute service."
    systemctl enable nova-novncproxy --now
    su -s /bin/bash nova -c "nova-manage cell_v2 discover_hosts --verbose"
    openstack compute service list
    #或者： 修改nova.conf修改时间间隔:
    #[scheduler]
    #discover_hosts_in_cells_interval = 300
}

####################################################################################################
add_neutron_linux_bridge_net() {
    local net_name=${1}
    log "Create network ${net_name}"
    local id=$(openstack project create --domain default service --or-show -f value -c id)
    log "projectid = ${id}"
    openstack network show ${net_name}-net 2>/dev/null || openstack network create --project ${id} --external --share --provider-network-type flat --provider-physical-network ${net_name} ${net_name}-net
    log "create subnet"
    openstack subnet show subnet-${net_name}-net 2>/dev/null || openstack subnet create subnet-${net_name}-net --network ${net_name}-net \
        --no-dhcp \
        --project ${id} --subnet-range 192.168.168.0/24 \
        --gateway 192.168.168.1 --dns-nameserver 114.114.114.114
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
    local net_name=${PUBLIC_NETWORK}
    local flaver_name=m1.small
    local secgroup=secgroup01
    local key_name=mykey
    log "create a [flavor]"
    openstack flavor show ${flaver_name} 2>/dev/null || openstack flavor create --id 0 --vcpus 1 --ram 256 --disk 1 ${flaver_name} || true
    log "create a security group for instances"
    openstack security group show ${secgroup} 2>/dev/null || openstack security group create ${secgroup} || true
    log "add public-keyc${key_name}"
    rm -f test.key test.key.pub 2>/dev/null || true
    ssh-keygen -q -N "" -f  test.key
    openstack keypair show ${key_name} 2>/dev/null || \
        openstack keypair create --public-key test.key.pub ${key_name} -f value -c fingerprint || true
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
    [ -e "${img}" ] || { log "wget --no-check-certificate -O ${img} http://download.cirros-cloud.net/0.3.5/cirros-0.3.5-x86_64-disk.img"; return 0; }
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
    local net_name=${PUBLIC_NETWORK}
    local flaver_name=m1.small
    local secgroup=secgroup01
    local img_name=cirros

    local key_name=mykey
    source ~/keystonerc
    local netid=$(openstack network list | grep ${net_name}-net | awk '{ print $2 }')
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
    log "openstack server create --flavor ${flaver_name} --image ${img_name} --security-group ${secgroup} --nic net-id=${netid} --key-name ${key_name} testvm1"
    openstack server show testvm1 &>/dev/null || openstack server create --flavor ${flaver_name} --image ${img_name} --security-group ${secgroup} --nic net-id=${netid} --key-name ${key_name} testvm1 || true
    log "openstack server show testvm1 "
    openstack server show testvm1 || true
    log "openstack extension list --network"
    openstack extension list --network || true
}

####################################################################################################
CTRL_HOST=192.168.168.1
COMPUTE_HOST=192.168.168.102
RABBIT_USER=openstack
RABBIT_PASS=password
KEYSTONE_USER=admin
KEYSTONE_PASS=adminpassword
KEYSTONE_DBPASS=keystone_password
GLANCE_PASS=glancepassword
GLANCE_DBPASS=glance_password
NOVA_PASS=novapassword
NOVA_DBPASS=nova_dbpass
PLACEMENT_PASS=palcement_pass
PLACEMENT_DBPASS=placement_dbpass
NEUTRON_PASS=neutron_pass
NEUTRON_DBPASS=neutron_dbpass

teardown() {
    sed -i '/keystonerc/d' ~/.bashrc || true
    rm -f ~/keystonerc  || true
    for s in placement keystone glance neutron nova rabbitmq-server memcached; do
        log "stop & disable service ${s}"
        systemctl stop ${s}* --force &>/dev/null || true
        systemctl disable ${s}* &>/dev/null || true
    done
    command -v "mysql" &> /dev/null && {
        log "stop & disable service mariadb"
        systemctl stop mariadb --force &>/dev/null || true
        systemctl disable mariadb &>/dev/null || true
        datadir=$(ini_get ${my_conf} mysqld datadir) || true
        [ -z "${datadir}" ] || rm -vrf "${datadir}" || true
    }
    for d in keystone glance nova placement neutron rabbitmq libvirt; do
        rm -vrf /var/log/${d}/* || true
    done
    log "TEARDOWN ALL DONE"
}

init_ctrl_node() {
    prepare_env "${CTRL_HOST}" "${KEYSTONE_USER}" "${KEYSTONE_PASS}"
    prepare_db_mq "${RABBIT_USER}" "${RABBIT_PASS}"
    init_keystone "${CTRL_HOST}" "${KEYSTONE_USER}" "${KEYSTONE_PASS}" "${KEYSTONE_DBPASS}"
    init_glance "${CTRL_HOST}" "${GLANCE_PASS}" "${GLANCE_DBPASS}"
    init_nova "${CTRL_HOST}" "${NOVA_PASS}" "${PLACEMENT_PASS}" "${NOVA_DBPASS}" "${PLACEMENT_DBPASS}" "${RABBIT_USER}" "${RABBIT_PASS}"
    init_neutron "${CTRL_HOST}" "${NOVA_PASS}" "${NEUTRON_PASS}" "${NEUTRON_DBPASS}" "${RABBIT_USER}" "${RABBIT_PASS}"
    add_neutron_linux_bridge_net "${PUBLIC_NETWORK}"
    adduser "tsd" "user1" "password"
    log "CTRL NODE ALL DONE"
}

init_comput_node() {
    prepare_env "${CTRL_HOST}" "${KEYSTONE_USER}" "${KEYSTONE_PASS}"
    init_nova_compute "${COMPUTE_HOST}" "${CTRL_HOST}" "${NOVA_PASS}" "${PLACEMENT_PASS}" "${RABBIT_USER}" "${RABBIT_PASS}"
    init_neutron_compute "${COMPUTE_HOST}" "${CTRL_HOST}" "${NEUTRON_PASS}" "${PLACEMENT_PASS}" "${RABBIT_USER}" "${RABBIT_PASS}"
    log 'su -s /bin/bash nova -c "nova-manage cell_v2 discover_hosts --verbose"'
    log "openstack compute service list"
    log "COMPUT NODE ALL DONE"
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME} <ctrl|compute|teardown>
        -v|--verify <keystone|glance|nova|neutron|all>
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
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
    local verify="" 
    local opt_short="v:"
    local opt_long="verify:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -v | --verify)  shift; declare -f -F verify_${1} >/dev/null && verify_${1} || usage; exit 0; shift;;
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
        ctrl)       init_ctrl_node ;;
        compute)    init_comput_node ;;
        teardown)   teardown ;;
        *)          usage;;
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
