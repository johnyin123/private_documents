yum -y install yum-utils drpmsync
yum clean all
yum makecache
yum repolist

#!/bin/bash
cat <<'EOF'>Centos-7.repo
[base]
name=CentOS-$releasever - Base - xikang
baseurl=http://10.3.60.99/centos/$releasever/base/$basearch/
gpgcheck=0

#released updates
[updates]
name=CentOS-$releasever - Updates - xikang
baseurl=http://10.3.60.99/centos/$releasever/updates/$basearch/
gpgcheck=0

#additional packages that may be useful
[extras]
name=CentOS-$releasever - Extras - xikang
baseurl=http://10.3.60.99/centos/$releasever/extras/$basearch/
enabled=0
gpgcheck=0

[epel]
name=Extra Packages for Enterprise Linux 7 - $basearch
baseurl=http://10.3.60.99/centos/$releasever/epel/$basearch
gpgcheck=0

[centos-openstack-queens]
name=CentOS-7 - OpenStack queens
baseurl=http://10.3.60.99/centos/$releasever/openstack-queens/$basearch
gpgcheck=0
exclude=sip,PyQt4

[centos-qemu-ev]
name=CentOS-$releasever - QEMU EV
baseurl=http://10.3.60.99/centos/$releasever/virt/$basearch/kvm-common/
gpgcheck=0

[centos-ceph-luminous]
name=CentOS-$releasever - Ceph Luminous
baseurl=http://10.3.60.99/centos/$releasever/storage/$basearch/ceph-luminous/
gpgcheck=0
EOF

PREFIX=/opt
releasever=7
basearch=x86_64

reposync --norepopath -nr base -p ${PREFIX}/centos/$releasever/base/$basearch/
createrepo -d ${PREFIX}/centos/$releasever/base/$basearch/

reposync --norepopath -nr updates -p ${PREFIX}/centos/$releasever/updates/$basearch/
createrepo -d ${PREFIX}/centos/$releasever/updates/$basearch/

reposync --norepopath -nr extras -p ${PREFIX}/centos/$releasever/extras/$basearch/
createrepo -d ${PREFIX}/centos/$releasever/extras/$basearch/

reposync --norepopath -nr epel -p ${PREFIX}/centos/$releasever/epel/$basearch
createrepo -d ${PREFIX}/centos/$releasever/epel/$basearch/

reposync --norepopath -nr centos-openstack-queens -p ${PREFIX}/centos/$releasever/openstack-queens/$basearch/Packages
createrepo -d ${PREFIX}/centos/$releasever/openstack-queens/$basearch/

reposync --norepopath -nr centos-qemu-ev -p ${PREFIX}/centos/$releasever/virt/$basearch/kvm-common/Packages
createrepo -d ${PREFIX}/centos/$releasever/virt/$basearch/kvm-common/

reposync --norepopath -nr centos-ceph-luminous -p ${PREFIX}/centos/$releasever/storage/$basearch/ceph-luminous/Packages
createrepo -d ${PREFIX}/centos/$releasever/storage/$basearch/ceph-luminous/

可上传自有rpm包到仓库，上传后使用createrepo -u 仓库目录，更新仓库索引即可。
# Minimal deployment for Queens
#    Identity service      – keystone installation for Queens
#    Image service         – glance installation for Queens
#    Compute service       – nova installation for Queens
#    Networking service    – neutron installation for Queens
# We advise to also install the following components after you have installed the minimal deployment services:
#    Dashboard             – horizon installation for Queens
#    Block Storage service – cinder installation for Queens

CTRL_IP=10.3.60.88
MYSQL_PASS="password"
PROVIDER_INTERFACE_NAME="eth0"
#Password of user admin
ADMIN_PASS="adminpass"
#the name of the underlying provider physical network interface
FLAT_NETWORKS=public
RABBIT_PASS="rabbitpass"
KEYSTONE_DBPASS="keystonepass"	
#Database password for Image service
GLANCE_DBPASS="glancedbpass"
#Password of Image service user glance
GLANCE_PASS="glancepass"
#Database password for Compute service
NOVA_DBPASS="novadbpass"
#Password of Compute service user nova
NOVA_PASS="novapass"
#Password of the Placement service user placement
PLACEMENT_PASS="placementpass"
#Database password for the Networking service
NEUTRON_DBPASS="neutrondbpass"
#Secret for the metadata proxy
METADATA_SECRET="metadatapass"
#Password of Networking service user neutron
NEUTRON_PASS="neutronpass"

# echo "install epel repo"
# yum -y install epel-release && yum -y update
# echo "install queens repo"
# yum -y install centos-release-openstack-queens && yum -y upgrade
echo "##########################controll node#############################"
echo "install mariadb"
yum -y install mariadb mariadb-server python2-PyMySQL
cat > /etc/my.cnf.d/openstack.cnf<<EOF
[mysqld]
bind-address = ${CTRL_IP}
default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF
systemctl enable mariadb.service
systemctl start mariadb.service
cat <<EOF | mysql_secure_installation


password
password






EOF
echo "install rabbitmq"
yum -y install rabbitmq-server
systemctl enable rabbitmq-server.service
systemctl start rabbitmq-server.service
echo "Add the openstack user."
rabbitmqctl add_user openstack ${RABBIT_PASS}
echo "Permit configuration, write, and read access for the openstack user:"
rabbitmqctl set_permissions openstack ".*" ".*" ".*"

echo "install memcached"
yum -y install memcached python-memcached
HOSTNAME=$(hostname)
sed -i "s/OPTIONS=.*/OPTIONS=\"-l 127.0.0.1,::1,${HOSTNAME}\"/g"  /etc/sysconfig/memcached
systemctl enable memcached.service
systemctl start memcached.service

echo "install etcd"
yum -y install etcd
cat >/etc/etcd/etcd.conf <<EOF
#[Member]
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_PEER_URLS="http://${CTRL_IP}:2380"
ETCD_LISTEN_CLIENT_URLS="http://${CTRL_IP}:2379"
ETCD_NAME="controller"
#[Clustering]
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://${CTRL_IP}:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://${CTRL_IP}:2379"
ETCD_INITIAL_CLUSTER="controller=http://${CTRL_IP}:2380"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-01"
ETCD_INITIAL_CLUSTER_STATE="new"
EOF
systemctl enable etcd
systemctl start etcd


echo "====================INSTALL keystone======================"
cat <<EOF | mysql -uroot -p${MYSQL_PASS}
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '${KEYSTONE_DBPASS}';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '${KEYSTONE_DBPASS}';
flush privileges;
EOF

[[ ! -x $(which openstack-config) ]] && { yum -y install python-openstackclient openstack-utils; }
yum -y install openstack-keystone httpd mod_wsgi
openstack-config --set /etc/keystone/keystone.conf database connection mysql+pymysql://keystone:${KEYSTONE_DBPASS}@${CTRL_IP}/keystone
openstack-config --set /etc/keystone/keystone.conf token provider fernet
su -s /bin/sh -c "keystone-manage db_sync" keystone
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

keystone-manage bootstrap --bootstrap-password ${ADMIN_PASS} \
  --bootstrap-admin-url http://${CTRL_IP}:35357/v3/ \
  --bootstrap-internal-url http://${CTRL_IP}:5000/v3/ \
  --bootstrap-public-url http://${CTRL_IP}:5000/v3/ \
  --bootstrap-region-id RegionOne

ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
systemctl enable httpd.service
systemctl start httpd.service

cat << EOF > ~/env.sh
export OS_USERNAME=admin
export OS_PASSWORD=${ADMIN_PASS}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_DOMAIN_NAME=default
export OS_AUTH_URL=http://${CTRL_IP}:35357/v3
export OS_IDENTITY_API_VERSION=3
EOF

echo "====================INSTALL glance======================"
cat <<EOF | mysql -uroot -p${MYSQL_PASS}
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '${GLANCE_DBPASS}';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '${GLANCE_DBPASS}';
flush privileges;
EOF

source ~/env.sh
#glance user
openstack user create --domain default --password ${GLANCE_PASS} glance
openstack project create --domain default --description "default Project" service 
openstack role add --project service --user glance admin
#service
openstack service create --name glance --description "OpenStack Image" image
#endpoint
openstack endpoint create --region RegionOne image public http://${CTRL_IP}:9292
openstack endpoint create --region RegionOne image internal http://${CTRL_IP}:9292
openstack endpoint create --region RegionOne image admin http://${CTRL_IP}:9292
yum -y install openstack-glance

echo "修改/etc/glance/glance-api.conf"
openstack-config --set /etc/glance/glance-api.conf database connection mysql+pymysql://glance:${GLANCE_DBPASS}@${CTRL_IP}/glance
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken auth_uri http://${CTRL_IP}:5000
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken auth_url http://${CTRL_IP}:35357
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken memcached_servers ${CTRL_IP}:11211
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken auth_type password
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken project_domain_name default
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken user_domain_name default
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken project_name service
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken username glance
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken password ${GLANCE_PASS}
openstack-config --set /etc/glance/glance-api.conf paste_deploy flavor keystone
openstack-config --set /etc/glance/glance-api.conf glance_store stores file,http
openstack-config --set /etc/glance/glance-api.conf glance_store default_store file
openstack-config --set /etc/glance/glance-api.conf glance_store filesystem_store_datadir /var/lib/glance/images/

echo "修改/etc/glance/glance-registry.conf"
openstack-config --set /etc/glance/glance-registry.conf database connection mysql+pymysql://glance:${GLANCE_DBPASS}@${CTRL_IP}/glance
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken auth_uri http://${CTRL_IP}:5000
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken auth_url http://${CTRL_IP}:35357
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken memcached_servers ${CTRL_IP}:11211
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken project_domain_id default
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken user_domain_name default
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken project_name service
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken auth_type password
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken username glance
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken password ${GLANCE_PASS}
openstack-config --set /etc/glance/glance-registry.conf paste_deploy flavor keystone

su -s /bin/sh -c "glance-manage db_sync" glance
systemctl enable openstack-glance-api.service openstack-glance-registry.service
systemctl start openstack-glance-api.service openstack-glance-registry.service

echo "check glance ok"
truncate -s 10M img.test
openstack image create "test" --file img.test --disk-format qcow2 --container-format bare --public
rm -f img.test
openstack image list


echo "====================INSTALL nova controller node======================"
cat <<EOF | mysql -uroot -p${MYSQL_PASS}
CREATE DATABASE nova_api;
CREATE DATABASE nova;
CREATE DATABASE nova_cell0;
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '${NOVA_DBPASS}';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '${NOVA_DBPASS}';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '${NOVA_DBPASS}';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '${NOVA_DBPASS}';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '${NOVA_DBPASS}';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '${NOVA_DBPASS}';
flush privileges;
EOF

source ~/env.sh
#创建nova用户：
openstack user create --domain default --password ${NOVA_PASS} nova
openstack role add --project service --user nova admin
openstack service create --name nova --description "OpenStack Compute" compute
#创建endpoint：
openstack endpoint create --region RegionOne compute public http://${CTRL_IP}:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://${CTRL_IP}:8774/v2.1
openstack endpoint create --region RegionOne compute admin http://${CTRL_IP}:8774/v2.1
#创建placement用户：
openstack user create --domain default --password ${PLACEMENT_PASS} placement
openstack role add --project service --user placement admin
openstack service create --name placement --description "Placement API" placement
#创建endpoint：
openstack endpoint create --region RegionOne placement public http://${CTRL_IP}:8778
openstack endpoint create --region RegionOne placement internal http://${CTRL_IP}:8778
openstack endpoint create --region RegionOne placement admin http://${CTRL_IP}:8778

yum -y install openstack-nova-api openstack-nova-conductor openstack-nova-console openstack-nova-novncproxy openstack-nova-scheduler openstack-nova-placement-api
openstack-config --set /etc/nova/nova.conf DEFAULT enabled_apis osapi_compute,metadata
openstack-config --set /etc/nova/nova.conf DEFAULT transport_url rabbit://openstack:${RABBIT_PASS}@${CTRL_IP}
openstack-config --set /etc/nova/nova.conf DEFAULT my_ip ${CTRL_IP}
openstack-config --set /etc/nova/nova.conf DEFAULT use_neutron true
openstack-config --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
openstack-config --set /etc/nova/nova.conf api_database connection mysql+pymysql://nova:${NOVA_DBPASS}@${CTRL_IP}/nova_api
openstack-config --set /etc/nova/nova.conf database connection mysql+pymysql://nova:${NOVA_DBPASS}@${CTRL_IP}/nova
openstack-config --set /etc/nova/nova.conf api auth_strategy keystone
openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_uri http://${CTRL_IP}:5000
openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_url http://${CTRL_IP}:35357
openstack-config --set /etc/nova/nova.conf keystone_authtoken memcached_servers ${CTRL_IP}:11211
openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_type password
openstack-config --set /etc/nova/nova.conf keystone_authtoken project_domain_name default
openstack-config --set /etc/nova/nova.conf keystone_authtoken user_domain_name default
openstack-config --set /etc/nova/nova.conf keystone_authtoken project_name service
openstack-config --set /etc/nova/nova.conf keystone_authtoken username nova
openstack-config --set /etc/nova/nova.conf keystone_authtoken password ${NOVA_PASS}
openstack-config --set /etc/nova/nova.conf vnc enabled true
openstack-config --set /etc/nova/nova.conf vnc server_listen '$my_ip'
openstack-config --set /etc/nova/nova.conf vnc server_proxyclient_address '$my_ip'
openstack-config --set /etc/nova/nova.conf glance api_servers http://${CTRL_IP}:9292
openstack-config --set /etc/nova/nova.conf oslo_concurrency lock_path /var/lib/nova/tmp
openstack-config --set /etc/nova/nova.conf placement region_name RegionOne
openstack-config --set /etc/nova/nova.conf placement project_domain_name default
openstack-config --set /etc/nova/nova.conf placement project_name service
openstack-config --set /etc/nova/nova.conf placement auth_type password
openstack-config --set /etc/nova/nova.conf placement user_domain_name default
openstack-config --set /etc/nova/nova.conf placement auth_url http://${CTRL_IP}:35357
openstack-config --set /etc/nova/nova.conf placement username placement
openstack-config --set /etc/nova/nova.conf placement password ${PLACEMENT_PASS}


echo "bug fix"
cat <<EOF >> /etc/httpd/conf.d/00-nova-placement-api.conf

<Directory /usr/bin>
   <IfVersion >= 2.4>
      Require all granted
   </IfVersion>
   <IfVersion < 2.4>
      Order allow,deny
      Allow from all
   </IfVersion>
</Directory>
EOF
systemctl restart httpd
#同步api数据库
su -s /bin/sh -c "nova-manage api_db sync" nova
echo "Register the cell0 database"
su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
echo "Create the cell1 cell"
su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
#同步nova数据库：
su -s /bin/sh -c "nova-manage db sync" nova
echo "check success"
nova-manage cell_v2 list_cells

systemctl enable openstack-nova-api.service openstack-nova-consoleauth.service openstack-nova-scheduler.service openstack-nova-conductor.service openstack-nova-novncproxy.service
systemctl restart openstack-nova-api.service openstack-nova-consoleauth.service openstack-nova-scheduler.service openstack-nova-conductor.service openstack-nova-novncproxy.service

#after installed nova compute node check as below
openstack compute service list
openstack compute service list --service nova-compute
nova-status upgrade check
#添加新的计算节点时，必须在控制器节点上运行nova管理cellv2发现主机来注册新的计算节点
su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova
#或者： 修改nova.conf修改时间间隔:
#[scheduler]
#discover_hosts_in_cells_interval = 300

echo "====================INSTALL neutron controller node======================"
cat <<EOF | mysql -uroot -p${MYSQL_PASS}
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '${NEUTRON_DBPASS}';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '${NEUTRON_DBPASS}';
flush privileges;
EOF
#创建neutron用户：
openstack user create --domain default --password ${NEUTRON_PASS} neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron --description "OpenStack Networking" network
#创建endpoint：
openstack endpoint create --region RegionOne network public http://${CTRL_IP}:9696
openstack endpoint create --region RegionOne network internal http://${CTRL_IP}:9696
openstack endpoint create --region RegionOne network admin http://${CTRL_IP}:9696

echo "Neutron配置二层简单网络(option 1),网络节点执行"
yum -y install openstack-neutron openstack-neutron-ml2 openstack-neutron-linuxbridge ebtables
openstack-config --set /etc/neutron/neutron.conf database connection mysql+pymysql://neutron:${NEUTRON_DBPASS}@${CTRL_IP}/neutron
openstack-config --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2
openstack-config --set /etc/neutron/neutron.conf DEFAULT service_plugins
openstack-config --set /etc/neutron/neutron.conf DEFAULT transport_url rabbit://openstack:${RABBIT_PASS}@${CTRL_IP}
openstack-config --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
openstack-config --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_status_changes true
openstack-config --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_data_changes true
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_uri http://${CTRL_IP}:5000
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_url http://${CTRL_IP}:35357
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken memcached_servers ${CTRL_IP}:11211
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_type password
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken project_domain_name default
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken user_domain_name default
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken project_name service
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken username neutron
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken password ${NEUTRON_PASS}
openstack-config --set /etc/neutron/neutron.conf nova auth_url http://${CTRL_IP}:35357
openstack-config --set /etc/neutron/neutron.conf nova auth_type password
openstack-config --set /etc/neutron/neutron.conf nova project_domain_name default
openstack-config --set /etc/neutron/neutron.conf nova user_domain_name default
openstack-config --set /etc/neutron/neutron.conf nova region_name RegionOne
openstack-config --set /etc/neutron/neutron.conf nova project_name service
openstack-config --set /etc/neutron/neutron.conf nova username nova
openstack-config --set /etc/neutron/neutron.conf nova password ${NOVA_PASS}
openstack-config --set /etc/neutron/neutron.conf oslo_concurrency lock_path /var/lib/neutron/tmp
echo "Modular Layer 2 (ML2) plug-in"
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers flat,vlan
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers linuxbridge
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 extension_drivers port_security
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks ${FLAT_NETWORKS}
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_ipset true

# openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers flat,vlan,vxlan 
# openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers linuxbridge,l2population 
# openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 extension_drivers port_security 
# openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types vxlan 
# openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 path_mtu 1500
# openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks provider
# openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vxlan vni_ranges 1:1000 
# openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_ipset True
echo "Linux bridge agent, controller node"
openstack-config --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini linux_bridge physical_interface_mappings ${FLAT_NETWORKS}:${PROVIDER_INTERFACE_NAME}
openstack-config --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan enable_vxlan false
openstack-config --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup enable_security_group true
openstack-config --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
#disable iptable firewall
# enable_security_group false
# firewall_driver neutron.agent.firewall.NoopFirewall
#maybe need reboot
echo "将下面参数的值确保为1"
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.bridge.bridge-nf-call-ip6tables
cat <<'EOF' > /etc/sysctl.d/00-neutron.conf
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
EOF
sysctl -p
echo "DHCP agent"
source ~/env.sh 
source ~/set.sh 
openstack-config --set /etc/neutron/dhcp_agent.ini DEFAULT interface_driver neutron.agent.linux.interface.BridgeInterfaceDriver
openstack-config --set /etc/neutron/dhcp_agent.ini DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
openstack-config --set /etc/neutron/dhcp_agent.ini DEFAULT enable_isolated_metadata true
echo "metadata agent"
openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT nova_metadata_host ${CTRL_IP} 
openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT metadata_proxy_shared_secret ${METADATA_SECRET}
openstack-config --set /etc/neutron/metadata_agent.ini cache memcache_servers ${CTRL_IP}:11211
ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

systemctl enable neutron-server.service \
    neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
    neutron-metadata-agent.service
systemctl restart neutron-server.service \
    neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
    neutron-metadata-agent.service

echo "Nova使用 Neutron,控制节点nova配置neutron："
openstack-config --set /etc/nova/nova.conf neutron url http://${CTRL_IP}:9696 
openstack-config --set /etc/nova/nova.conf neutron auth_url http://${CTRL_IP}:35357 
openstack-config --set /etc/nova/nova.conf neutron auth_type password
openstack-config --set /etc/nova/nova.conf neutron project_domain_name default
openstack-config --set /etc/nova/nova.conf neutron user_domain_name default
openstack-config --set /etc/nova/nova.conf neutron region_name RegionOne
openstack-config --set /etc/nova/nova.conf neutron project_name service 
openstack-config --set /etc/nova/nova.conf neutron username neutron 
openstack-config --set /etc/nova/nova.conf neutron password ${NEUTRON_PASS} 
openstack-config --set /etc/nova/nova.conf neutron service_metadata_proxy true
openstack-config --set /etc/nova/nova.conf neutron metadata_proxy_shared_secret ${METADATA_SECRET}
systemctl restart openstack-nova-api.service
echo "check"
openstack network agent list

echo "====================INSTALL dashboard======================"
yum -y install openstack-dashboard
grep "OPENSTACK_HOST = " /etc/openstack-dashboard/local_settings
sed -i "s/ALLOWED_HOSTS =.*/ALLOWED_HOSTS = ['*']/g" /etc/openstack-dashboard/local_settings
cat <<EOF>>/etc/openstack-dashboard/local_settings
SESSION_ENGINE = 'django.contrib.sessions.backends.cache'
CACHES = {
    'default': {
         'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
         'LOCATION': '${CTRL_IP}:11211',
    }
}
EOF
echo "sure use v3"
grep "OPENSTACK_KEYSTONE_URL =" /etc/openstack-dashboard/local_settings
sed -i "s/.*OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT.*/OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True/g" /etc/openstack-dashboard/local_settings
cat <<EOF >> /etc/openstack-dashboard/local_settings
OPENSTACK_API_VERSIONS = {
    "identity": 3,
    "image": 2,
    "volume": 2,
}
EOF
sed -i "s/.*OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = /OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = 'default'/g" /etc/openstack-dashboard/local_settings
sed -i "s/.*OPENSTACK_KEYSTONE_DEFAULT_ROLE =.*/OPENSTACK_KEYSTONE_DEFAULT_ROLE = 'user'/g" /etc/openstack-dashboard/local_settings
echo -e "If you chose networking option 1, disable support for layer-3 networking services:
OPENSTACK_NEUTRON_NETWORK = {
    ...
    'enable_router': False,
    'enable_quotas': False,
    'enable_distributed_router': False,
    'enable_ha_router': False,
    'enable_lb': False,
    'enable_firewall': False,
    'enable_vpn': False,
    'enable_fip_topology_check': False,
}"
sed -i "s/.*TIME_ZONE =.*/TIME_ZONE = 'Asia\/Shanghai'/g" /etc/openstack-dashboard/local_settings
systemctl restart httpd.service memcached.service
echo "check success"
echo "login admin/${ADMIN_PASS} http://${CTRL_IP}/dashboard"




echo "##########################compute node#############################"
echo "compute node run on MANAGEMENT_INTERFACE_IP_ADDRESS"
echo "====================INSTALL nova compute node======================"
#compute node ipaddress
MANAGEMENT_INTERFACE_IP_ADDRESS=10.3.60.89
#计算节点：
[[ ! -x $(which openstack-config) ]] && { yum -y install python-openstackclient openstack-utils; }
yum -y install openstack-nova-compute

openstack-config --set /etc/nova/nova.conf DEFAULT enabled_apis osapi_compute,metadata
openstack-config --set /etc/nova/nova.conf DEFAULT transport_url rabbit://openstack:${RABBIT_PASS}@${CTRL_IP}
openstack-config --set /etc/nova/nova.conf DEFAULT my_ip ${MANAGEMENT_INTERFACE_IP_ADDRESS}
openstack-config --set /etc/nova/nova.conf DEFAULT use_neutron true
openstack-config --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
openstack-config --set /etc/nova/nova.conf api auth_strategy keystone
openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_uri http://${CTRL_IP}:5000
openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_url http://${CTRL_IP}:35357
openstack-config --set /etc/nova/nova.conf keystone_authtoken memcached_servers ${CTRL_IP}:11211
openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_type password
openstack-config --set /etc/nova/nova.conf keystone_authtoken project_domain_name default
openstack-config --set /etc/nova/nova.conf keystone_authtoken user_domain_name default
openstack-config --set /etc/nova/nova.conf keystone_authtoken project_name service
openstack-config --set /etc/nova/nova.conf keystone_authtoken username nova
openstack-config --set /etc/nova/nova.conf keystone_authtoken password ${NOVA_PASS}
openstack-config --set /etc/nova/nova.conf vnc enabled true
openstack-config --set /etc/nova/nova.conf vnc server_listen 0.0.0.0
openstack-config --set /etc/nova/nova.conf vnc server_proxyclient_address '$my_ip'
openstack-config --set /etc/nova/nova.conf vnc novncproxy_base_url http://${CTRL_IP}:6080/vnc_auto.html
openstack-config --set /etc/nova/nova.conf glance api_servers http://${CTRL_IP}:9292
openstack-config --set /etc/nova/nova.conf oslo_concurrency lock_path /var/lib/nova/tmp
openstack-config --set /etc/nova/nova.conf placement region_name RegionOne
openstack-config --set /etc/nova/nova.conf placement project_domain_name default
openstack-config --set /etc/nova/nova.conf placement project_name service
openstack-config --set /etc/nova/nova.conf placement auth_type password
openstack-config --set /etc/nova/nova.conf placement user_domain_name default
openstack-config --set /etc/nova/nova.conf placement auth_url http://${CTRL_IP}:35357/v3
openstack-config --set /etc/nova/nova.conf placement username placement
openstack-config --set /etc/nova/nova.conf placement password ${PLACEMENT_PASS}
egrep -c '(vmx|svm)' /proc/cpuinfo && openstack-config --set /etc/nova/nova.conf libvirt virt_type kvm
systemctl enable libvirtd.service openstack-nova-compute.service
systemctl start libvirtd.service openstack-nova-compute.service

echo "添加新的计算节点时，必须在控制器节点上运行nova管理cellv2发现主机来注册新的计算节点"
su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova
nova-status upgrade check

echo "====================INSTALL neutron on compute node======================"
[[ ! -x $(which openstack-config) ]] && { yum -y install python-openstackclient openstack-utils; }
yum -y install openstack-neutron-linuxbridge ebtables ipset
echo "修改配置文件"
openstack-config --set /etc/neutron/neutron.conf DEFAULT transport_url rabbit://openstack:${RABBIT_PASS}@${CTRL_IP}
openstack-config --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_uri http://${CTRL_IP}:5000
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_url http://${CTRL_IP}:35357
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken memcached_servers ${CTRL_IP}:11211
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_type password
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken project_domain_name default
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken user_domain_name default
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken project_name service
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken username neutron
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken password ${NEUTRON_PASS}
openstack-config --set /etc/neutron/neutron.conf oslo_concurrency lock_path /var/lib/neutron/tmp
echo "Linux bridge agent compute node"
openstack-config --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini linux_bridge physical_interface_mappings ${FLAT_NETWORKS}:${PROVIDER_INTERFACE_NAME}
openstack-config --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan enable_vxlan false
openstack-config --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup enable_security_group true
openstack-config --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
#disable iptable firewall
# enable_security_group false
# firewall_driver neutron.agent.firewall.NoopFirewall
#maybe need reboot
echo "将下面参数的值确保为1"
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.bridge.bridge-nf-call-ip6tables
cat <<'EOF' > /etc/sysctl.d/00-neutron.conf
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
EOF
sysctl -p

echo "Configure the Compute service to use the Networking service"
source ~/env.sh 
source ~/set.sh 
openstack-config --set /etc/nova/nova.conf neutron url http://${CTRL_IP}:9696 
openstack-config --set /etc/nova/nova.conf neutron auth_url http://${CTRL_IP}:35357 
openstack-config --set /etc/nova/nova.conf neutron auth_type password
openstack-config --set /etc/nova/nova.conf neutron project_domain_name default
openstack-config --set /etc/nova/nova.conf neutron user_domain_name default
openstack-config --set /etc/nova/nova.conf neutron region_name RegionOne
openstack-config --set /etc/nova/nova.conf neutron project_name service 
openstack-config --set /etc/nova/nova.conf neutron username neutron 
openstack-config --set /etc/nova/nova.conf neutron password ${NEUTRON_PASS} 

systemctl restart openstack-nova-compute.service
systemctl enable neutron-linuxbridge-agent.service
systemctl start neutron-linuxbridge-agent.service
echo "check neutron compute node"
openstack network agent list
openstack extension list --network


echo "====================config neutron network======================"
echo "Create the provider network, On the controller node"
source ~/env.sh

openstack network create  --share --external --provider-physical-network ${FLAT_NETWORKS} \
    --provider-network-type flat ${FLAT_NETWORKS}
openstack subnet create --network ${FLAT_NETWORKS} \
    --allocation-pool start=10.3.57.110,end=10.3.57.120 \
    --dns-nameserver 8.8.8.8 --gateway 10.3.57.1 \
    --subnet-range 10.3.57.0/24 ${FLAT_NETWORKS}
echo "Create m1.nano flavor"
openstack flavor create --id 0 --vcpus 1 --ram 64 --disk 1 m1.nano
echo "Generate a key pair"
ssh-keygen -q -N ""
openstack keypair create --public-key ~/.ssh/id_rsa.pub mykey
echo "Verify addition of the key pair"
openstack keypair list
echo "Add security group rules"
echo "Add rules to the default security group:"
openstack security group rule create --proto icmp default
openstack security group rule create --proto tcp --dst-port 22 default


openstack flavor list
openstack image create "cirros" --file cirros-0.3.4-x86_64-disk.img --disk-format qcow2 --container-format bare --public
openstack image list
openstack network list
openstack security group list

openstack server create --flavor m1.nano --image cirros \
    --nic net-id=PROVIDER_NET_ID --security-group default \
    --key-name mykey test-instance 
echo "Check the status of your instance"
openstack server list
openstack console url show test-instance
ssh cirros@xxx
echo "====================config ok======================"




# The Block Storage service consists of the following components:
# 
# cinder-api
# 	Accepts API requests, and routes them to the cinder-volume for action.
# cinder-volume
# 	Interacts directly with the Block Storage service, and processes such as the cinder-scheduler. It also interacts with these processes through a message queue. The cinder-volume service responds to read and write requests sent to the Block Storage service to maintain state. It can interact with a variety of storage providers through a driver architecture.
# cinder-scheduler daemon
# 	Selects the optimal storage provider node on which to create the volume. A similar component to the nova-scheduler.
# cinder-backup daemon
# 	The cinder-backup service provides backing up volumes of any type to a backup storage provider. Like the cinder-volume service, it can interact with a variety of storage providers through a driver architecture.
# Messaging queue
# 	Routes information between the Block Storage processes.


yum install lvm2 device-mapper-persistent-data
systemctl enable lvm2-lvmetad.service
systemctl start lvm2-lvmetad.service














Password name	Description
Database password (no variable used)	Root password for the database
CINDER_DBPASS	Database password for the Block Storage service
CINDER_PASS	Password of Block Storage service user cinder
DASH_DBPASS	Database password for the Dashboard
DEMO_PASS	Password of user demo




useradd stack  
echo "password" | passwd --stdin stack
echo "stack        ALL=(ALL)       NOPASSWD: ALL" > /etc/sudoers.d/stack  
chmod 0440 /etc/sudoers.d/stack  
su - stack
