readonly cinder_conf=/etc/cinder/cinder.conf

readonly SVC_CINDER_API=cinder-api.service
readonly SVC_CINDER_SCHEDULER=cinder-scheduler.service

init_cinder() {
    local ctrl_host=${1}
    local cinder_pass=${2}
    local cinder_dbpass=${3}
    local rabbit_user=${5}
    local rabbit_pass=${6}

    local my_ip=${ctrl_host}
    #  apt -y install cinder-api cinder-scheduler python3-cinderclient
    log "##########################INSTALL CINDER##########################"
    log "install cinder: Block Storage"
    openstack_add_admin_user cinder "${cinder_pass}"
    openstack_add_service_endpoint cinderv3 volumev3  "http://${ctrl_host}:8776/v3/%(tenant_id)s" "OpenStack Block Storage"
    log "Add a User and Database on MariaDB for Cinder"
    create_mysql_db cinder cinder "${cinder_dbpass}"
    log "Configure Cinder create new"
    backup ${cinder_conf} "MOVE"
    ini_set ${cinder_conf} DEFAULT my_ip ${my_ip}
    ini_set ${cinder_conf} DEFAULT auth_strategy keystone
    ini_set ${cinder_conf} DEFAULT enable_v3_api True
    ini_set ${cinder_conf} DEFAULT transport_url rabbit://${rabbit_user}:${rabbit_pass}@${ctrl_host}
    ini_set ${cinder_conf} DEFAULT rootwrap_config /etc/cinder/rootwrap.conf
    ini_set ${cinder_conf} DEFAULT api_paste_confg /etc/cinder/api-paste.ini
    ini_set ${cinder_conf} DEFAULT state_path /var/lib/cinder
    ini_set ${cinder_conf} database connection "$(get_mysql_connection cinder ${cinder_dbpass} cinder)"
    add_keystone_authtoken ${cinder_conf} ${ctrl_host} cinder ${cinder_pass}
    ini_set ${cinder_conf} oslo_concurrency lock_path /var/lib/cinder/tmp
    log "sync cinder db"
    su -s /bin/bash cinder -c "cinder-manage db sync"
    log "restart ${SVC_CINDER_API} ${SVC_CINDER_SCHEDULER}"
    service_restart ${SVC_CINDER_API} ${SVC_CINDER_SCHEDULER}
    cinder-api cinder-scheduler
}

init_cinder_storage() {
    # apt -y install cinder-volume python3-mysqldb python3-rtslib-fb
    #  vi /etc/cinder/cinder.conf
# create new
[DEFAULT]
# define own IP address
my_ip = 10.0.0.50
rootwrap_config = /etc/cinder/rootwrap.conf
api_paste_confg = /etc/cinder/api-paste.ini
state_path = /var/lib/cinder
auth_strategy = keystone
# RabbitMQ connection info
transport_url = rabbit://openstack:password@10.0.0.30
enable_v3_api = True
# Glance connection info
glance_api_servers = http://10.0.0.30:9292
# OK with empty value now
enabled_backends =

# MariaDB connection info
[database]
connection = mysql+pymysql://cinder:password@10.0.0.30/cinder

# Keystone auth info
[keystone_authtoken]
www_authenticate_uri = http://10.0.0.30:5000
auth_url = http://10.0.0.30:5000
memcached_servers = 10.0.0.30:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = cinder
password = servicepassword

[oslo_concurrency]
lock_path = $state_path/tmp

root@storage:~# chmod 640 /etc/cinder/cinder.conf
root@storage:~# chgrp cinder /etc/cinder/cinder.conf
root@storage:~# systemctl restart cinder-volume
root@storage:~# systemctl enable cinder-volume
}
openstack volume create --size 10 disk01
openstack server add volume Debian-11 disk01
openstack server remove volume Debian-11 disk01

verify_cinder() {
    log "Verify Cinder installation"
    source ~/keystonerc
    openstack volume service list
}




Prerequisites

Root-level access to the Cinder node.
A Ceph volume pool.
The user and UUID of the secret to interact with Ceph block devices.
Procedure

Edit the Cinder configuration file:

[root@cinder ~]# vim /etc/cinder/cinder.conf
In the [DEFAULT] section, enable Ceph as a backend for Cinder:

enabled_backends = ceph
Ensure that the Glance API version is set to 2. If you are configuring multiple cinder back ends in enabled_backends, the glance_api_version = 2 setting must be in the [DEFAULT] section and not the [ceph] section.

glance_api_version = 2
Create a [ceph] section in the cinder.conf file. Add the Ceph settings in the following steps under the [ceph] section.
Specify the volume_driver setting and set it to use the Ceph block device driver:

volume_driver = cinder.volume.drivers.rbd.RBDDriver
Specify the cluster name and Ceph configuration file location. In typical deployments the Ceph cluster has a cluster name of ceph and a Ceph configuration file at /etc/ceph/ceph.conf. If the Ceph cluster name is not ceph, specify the cluster name and configuration file path appropriately:

rbd_cluster_name = us-west
rbd_ceph_conf = /etc/ceph/us-west.conf
By default, Red Hat OpenStack Platform stores Ceph volumes in the rbd pool. To use the volumes pool created earlier, specify the rbd_pool setting and set the volumes pool:

rbd_pool = volumes
Red Hat OpenStack Platform does not have a default user name or a UUID of the secret for volumes. Specify rbd_user and set it to the cinder user. Then, specify the rbd_secret_uuid setting and set it to the generated UUID stored in the uuid-secret.txt file:

rbd_user = cinder
rbd_secret_uuid = 4b5fd580-360c-4f8c-abb5-c83bb9a3f964
Specify the following settings:

rbd_flatten_volume_from_snapshot = false
rbd_max_clone_depth = 5
rbd_store_chunk_size = 4
rados_connect_timeout = -1
When you configure Cinder to use Ceph block devices, the configuration file might look similar to this:

Example

Expand
[DEFAULT]
enabled_backends = ceph
glance_api_version = 2
…

[ceph]
volume_driver = cinder.volume.drivers.rbd.RBDDriver
rbd_cluster_name = ceph
rbd_pool = volumes
rbd_user = cinder
rbd_ceph_conf = /etc/ceph/ceph.conf
rbd_flatten_volume_from_snapshot = false
rbd_secret_uuid = 4b5fd580-360c-4f8c-abb5-c83bb9a3f964
rbd_max_clone_depth = 5
rbd_store_chunk_size = 4
rados_connect_timeout = -1

