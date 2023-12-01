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
################################################################################
#
Copy ceph.conf file from ceph node to all openstack nodes from ceph mgr node:

# Copy /etc/ceph/ceph.conf from mgr node(ceph1) to all openstack nodes
ssh ems-vm-controller.es.equinix.com sudo tee /etc/ceph/ceph.conf </etc/ceph/ceph.conf
ssh ems-vm-compute1.es.equinix.com sudo tee /etc/ceph/ceph.conf </etc/ceph/ceph.conf
ssh ems-vm-compute2.es.equinix.com sudo tee /etc/ceph/ceph.conf </etc/ceph/ceph.conf
Setup Cephx Authentication
# Ceph1 node (mgr node)
# If you have cephx authentication enabled, create a new user for Nova/Cinder and Glance. Execute the following:
ceph auth get-or-create client.cinder mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=volumes, allow rwx pool=vms, allow rx pool=images'
ceph auth get-or-create client.cinder-backup mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=backups'
ceph auth get-or-create client.glance mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=images'
# Add the keyrings for client.cinder, client.glance, and client.cinder-backup to the appropriate nodes and change their ownership:
ceph auth get-or-create client.cinder | ssh 10.195.231.213 sudo tee /etc/ceph/ceph.client.cinder.keyring
ssh 10.195.231.213 sudo chown cinder:cinder /etc/ceph/ceph.client.cinder.keyring
ceph auth get-or-create client.cinder-backup | ssh 10.195.231.213 sudo tee /etc/ceph/ceph.client.cinder-backup.keyring
ssh 10.195.231.213 sudo chown cinder:cinder /etc/ceph/ceph.client.cinder-backup.keyring
ceph auth get-or-create client.glance | ssh 10.195.231.213 sudo tee /etc/ceph/ceph.client.glance.keyring
ssh 10.195.231.213 sudo chown glance:glance /etc/ceph/ceph.client.glance.keyring
ceph auth get-or-create client.cinder | ssh 10.195.231.214 sudo tee /etc/ceph/ceph.client.cinder.keyring
ceph auth get-or-create client.cinder | ssh 10.195.231.215 sudo tee /etc/ceph/ceph.client.cinder.keyring
ceph auth get-key client.cinder | ssh 10.195.231.214 tee /etc/ceph/client.cinder.key
ceph auth get-key client.cinder | ssh 10.195.231.215 tee /etc/ceph/client.cinder.key
Create Secret

# All Compute nodes, could use the same uuid value across all compute nodes
# Then, on the compute nodes, add the secret key to libvirt and remove the temporary copy of the key:
uuidgen # generate uuid, the reset of openstack could use the same uuid value.
bb3df3eb-7ac9-4964-b2dc-c254d9c71448
cat > secret.xml <<EOF
<secret ephemeral='no' private='no'>
  <uuid>bb3df3eb-7ac9-4964-b2dc-c254d9c71448</uuid>
  <usage type='ceph'>
    <name>client.cinder secret</name>
  </usage>
</secret>
EOF
sudo virsh secret-define --file secret.xml
sudo virsh secret-set-value --secret bb3df3eb-7ac9-4964-b2dc-c254d9c71448 --base64 $(cat client.cinder.key) && rm client.cinder.key secret.xml
Configure openstack to use ceph
Glance
Edit /etc/glance/glance-api.conf and add under the [glance_store] section:

# Controller node
[root@ems-vm-controller ~]# vim /etc/glance/glance-api.conf
[glance_store]
stores = rbd
default_store = rbd
rbd_store_pool = images
rbd_store_user = glance
rbd_store_ceph_conf = /etc/ceph/ceph.conf
rbd_store_chunk_size = 8
#If you want to enable copy-on-write cloning of images, also add under the [DEFAULT] section:
show_image_direct_url = True
#Disable the Glance cache management to avoid images getting cached under /var/lib/glance/image-cache/, assuming your configuration file has flavor = keystone+cachemanagement:
[paste_deploy]
flavor = keystone
# Recommand Configuraiton
# add the virtio-scsi controller and get better performance and support for discard operation
hw_scsi_model=virtio-scsi
# connect every cinder block devices to that controller
hw_disk_bus=scsi
# enable the QEMU guest agent
hw_qemu_guest_agent=yes
# send fs-freeze/thaw calls through the QEMU guest agent
os_require_quiesce=yes
Cinder
OpenStack requires a driver to interact with Ceph block devices. You must also specify the pool name for the block device. On your OpenStack node, edit /etc/cinder/cinder.conf by adding:

# Controller node
# rbd_secret_uuid is the uudi we create before, please note we can not put any comments with the parameter below, otherwise, it will broken.
# remove the [lvm] section
# vim /etc/cinder/cinder.conf
[DEFAULT]
...
enabled_backends = ceph
glance_api_version = 2
...
[ceph]
volume_driver = cinder.volume.drivers.rbd.RBDDriver
volume_backend_name = ceph
rbd_pool = volumes
rbd_ceph_conf = /etc/ceph/ceph.conf
rbd_flatten_volume_from_snapshot = false
rbd_max_clone_depth = 5
rbd_store_chunk_size = 4
rados_connect_timeout = -1
rbd_user = cinder
rbd_secret_uuid = bb3df3eb-7ac9-4964-b2dc-c254d9c71448
backup_driver = cinder.backup.drivers.ceph
backup_ceph_conf = /etc/ceph/ceph.conf
backup_ceph_user = cinder-backup
backup_ceph_chunk_size = 134217728
backup_ceph_pool = backups
backup_ceph_stripe_unit = 0
backup_ceph_stripe_count = 0
restore_discard_excess_bytes = true
Openstack using iscsi as volume Type by default, after change to ceph, we need change the default_volume_type.

[root@ems-vm-controller ~(keystone_admin)]# openstack volume type create --public --property volume_backend_name="ceph" ceph
# ceph just a name, need to match above volume_backend_name
[root@ems-vm-controller ~]# vim /etc/cinder/cinder.conf
default_volume_type=ceph

Nova

In order to attach Cinder devices (either normal block or by issuing a boot from volume), you must tell Nova (and libvirt) which user and UUID to refer to when attaching the device. libvirt will refer to this user when connecting and authenticating with the Ceph cluster.

# This configure, all vms still running on each local ndoe.
# compute node
[libvirt]
...
rbd_user = cinder
rbd_secret_uuid = bb3df3eb-7ac9-4964-b2dc-c254d9c71448
Full configuration on [libvirt] section:

# Compute node
[libvirt]
virt_type = qemu
images_type = rbd
images_rbd_pool = vms
images_rbd_ceph_conf = /etc/ceph/ceph.conf
rbd_user = cinder
rbd_secret_uuid = 4810c760-dc42-4e5f-9d41-7346db7d7da2
disk_cachemodes="network=writeback"
inject_password = false
inject_key = false
inject_partition = -2
live_migration_flag="VIR_MIGRATE_UNDEFINE_SOURCE,VIR_MIGRATE_PEER2PEER,VIR_MIGRATE_LIVE,VIR_MIGRATE_PERSIST_DEST"
on all computes node, add [client] section to /etc/ceph/ceph.conf file.

[root@ems-vm-compute1 ~]# vim /etc/ceph/ceph.conf
[client]
rbd cache = true
rbd cache writethrough until flush = true
rbd concurrent management ops = 20
admin socket = /var/run/ceph/guests/$cluster-$type.$id.$pid.$cctid.asok
log file = /var/log/ceph/qemu-guest-$pid.log
Configure the permissions of these paths:

mkdir -p /var/run/ceph/guests/ /var/log/ceph/
chown qemu:libvirt /var/run/ceph/guests /var/log/ceph/
Restart services
systemctl restart openstack-cinder-volume openstack-cinder-api openstack-cinder-scheduler openstack-cinder-backup openstack-glance-api
systemctl restart openstack-nova-compute
Note
Using QCOW2 for hosting a virtual machine disk is NOT recommended. If you want to boot virtual machines in Ceph (ephemeral backend or boot from volume), please use the raw image format within Glance.

Here is the qemu-img command convert image type.

qemu-img convert -f {source-format} -O {output-format} {source-filename} {output-filename}
For example

# check file format
[root@ems-sv4-centos7 Downloads]# qemu-img info bionic-server-cloudimg-amd64.raw
# convert from qcow2 to raw format
[root@ems-sv4-centos7 Downloads]# qemu-img convert -f qcow2 -O raw bionic-server-cloudimg-amd64.img bionic-server-cloudimg-amd64.raw
Openstack
Ceph
Private Cloud

