# kolla-ansible Openstack HA Cluster Deployment

     架构 docker 部署基础组件
     准备2张网卡 1张集群管理网络 1张虚拟机网络
     db mariadb galera 高可用
     haproxy+keeplive 做 api 调度
     dvr 分布式路由， dhcp高可用
     cinder-volume 高可用
     ceph集群存储 高可用
     
## reference

    https://github.com/openstack/kolla-ansible
    https://docs.openstack.org/project-deploy-guide/kolla-ansible/rocky/quickstart.html
    https://cloud-atlas.readthedocs.io/zh_CN/latest/ceph/bluestore.html
    https://www.voidking.com/dev-openstack-vm-block-live-migration/
    https://ceph.com/pgcalc/
    https://docs.openstack.org/cinder/pike/man/cinder-manage.html
    
# 开始环境装备
    (venv-kolla) [root@deploy ansible]# cat /etc/hosts
    127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
    ::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
    172.16.1.21 storage01
    172.16.1.22 storage02
    172.16.1.23 storage03
    172.16.1.31 control01
    172.16.1.32 control02
    172.16.1.33 control03
    172.16.1.34 compute01 
    172.16.1.35 compute02
    172.16.1.41 network01
    172.16.1.42 network02
    172.16.1.51 monitoring01
    
    for i in controller0{1,2,3} network0{1,2}  compute01 storage0{1..3};do ssh-copy-id $i ;done
    
# 各个节点安装最新docker

    #hostnamectl set-hostname
    #curl -sSL https://get.docker.io | bash
    for i in controller0{1,2,3} network0{1,2}  compute01 storage0{1..3};do ssh $i "hostnamectl set-hostname $i" ;done
    for i in controller0{1,2,3} network0{1,2}  compute01 storage0{1..3};do ssh $i 'curl -sSL https://get.docker.io | bash' ;done

# 提供裸盘做ceph osd
	parted /dev/sdb rm 1
	parted /dev/sdb rm 2
	parted /dev/sdc rm 1
	parted /dev/sdc rm 2
	parted /dev/sdd rm 1
	parted /dev/sdd rm 2

## 1、简单部署方式
	parted /dev/sdb -s -- mklabel gpt mkpart KOLLA_CEPH_OSD_BOOTSTRAP_BS 1 -1 
	parted /dev/sdc -s -- mklabel gpt mkpart KOLLA_CEPH_OSD_BOOTSTRAP_BS 1 -1 
	parted /dev/sdd -s -- mklabel gpt mkpart KOLLA_CEPH_OSD_BOOTSTRAP_BS 1 -1
## 2、磁盘标记为 bluestore 存储方式  cache 缓存

	parted /dev/sdb -s -- mklabel gpt mkpart KOLLA_CEPH_OSD_CACHE_BOOTSTRAP_BS  1 -1 
	parted /dev/sdc -s -- mklabel gpt mkpart KOLLA_CEPH_OSD_BOOTSTRAP_BS 1 -1 
	parted /dev/sdd -s -- mklabel gpt mkpart KOLLA_CEPH_OSD_BOOTSTRAP_BS 1 -1 

## 3、多分区 做为 block, block.wal, block.db
	parted /dev/sdb -s -- mklabel gpt 
	parted /dev/sdc -s -- mklabel gpt 
	parted /dev/sdd -s -- mklabel gpt 
	parted /dev/sdb -s -- mkpart KOLLA_CEPH_OSD_BOOTSTRAP_BS 1 -1
	parted /dev/sdc -s -- mkpart KOLLA_CEPH_OSD_BOOTSTRAP_BS 1 -1
	parted /dev/sdd -s -- mkpart KOLLA_CEPH_OSD_BOOTSTRAP_BS 1 -1


# 在deploy 节点 
	git clone https://github.com/openstack/kolla-ansible -b stable/rocky
## 安装 pip 虚拟环境
	yum -y install python-pip
	pip install -U pip
	pip install virtualenv
	virtualenv venv-kolla
	source venv-kolla/bin/activate

## 安装kolla-ansible 依赖模块
	pip install -r kolla-ansible/requirements.txt
## copy 配置文件
	mkdir -p /etc/kolla/config
	cp -r kolla-ansible/etc/kolla/* /etc/kolla

	/etc/kolla/
	├── config
	│   ├── ceph.conf
	│   └── nova
	│       └── nova-compute.conf
	├── globals.yml
	└── passwords.yml

	(venv-kolla) [root@deploy ansible]# cat /etc/kolla/config/ceph.conf 
	osd pool default size = 1
	osd pool default min size = 1

	(venv-kolla) [root@deploy ansible]# cat /etc/kolla/config/nova/nova-compute.conf 
	[libvirt]
	virt_type = qemu
	cpu_mode = none

# 生成密码文件
	cd kolla-ansible/tools
	./generate_passwords.py

# 修改 multinode, globals.yml
	...
# 开始部署
	ansible-playbook -i inventory/multinode pull
	ansible-playbook -i inventory/multinode bootstrap-servers
	ansible-playbook -i inventory/multinode prechecks
	ansible-playbook -i inventory/multinode deploy

# after deploy
	#All the pools must be modified if Glance, Nova, and Cinder have been deployed. An example of modifying the pools to have 2 copies:
	for p in images vms volumes backups; do docker exec ceph_mon ceph osd pool set ${p} size 2; done
	(venv-kolla) [root@deploy ansible]# cat /etc/kolla/config/ceph.conf 
	osd pool default size = 3
	osd pool default min size = 2
	osd pool default pg num = 128
	osd pool default pgp num = 128
	mon max pg per osd = 3000
	kolla-ansible  -i  inventory/multinode reconfigure
	
	docker exec -it ceph_mon bash
		ceph osd pool set vms pg_num 128 
		ceph osd pool set vms pgp_num 128 
		ceph osd pool set volumes pg_num 128 
		ceph osd pool set volumes pgp_num 128 
		ceph osd pool set images pg_num 128 
		ceph osd pool set images pgp_num 128 
		ceph osd pool get vms pg_num
 
# 新增加一个计算节点
	curl -sSL https://get.docker.io | bash
## 在deploy主机
	vim /etc/hosts
	ssh-copy-id  compute02
	vim inventory/multinode

	kolla-ansible  -i  inventory/multinode bootstrap-servers --limit compute02
	kolla-ansible  -i  inventory/multinode pull --limit compute02
	kolla-ansible  -i  inventory/multinode deploy --limit compute02

# 删除一个计算节点
	kolla-ansible -i inventory/multinode destroy --limit compute02 --yes-i-really-really-mean-it
	openstack  compute service list
	openstack  compute service delete  <compute ID>
	openstack  network agent list
	openstack  network agent delete  <ID>
# 管理cinder 后端
	docker exec -it cinder_scheduler bash
		cinder-manage service list
		cinder-manage service remove cinder-volume storage02@lvm-1
	cinder后端存储步骤：
	（）把存储准备好，如NFS，ISCSI
	（）安装cinder-volume
	（）vim /etc/cinder/cinder.conf
	[xxx]
	volume_driver=xxx
	......
	volume_backend_name=xxx-Storage
	（）创建类型：cinder type-create xxx
	（）关联类型：cinder type-key xxx set volume_backend_name=xxx-Storage	
 
## 疑难杂症
    #浮动IP down
    重启计算节点的 neutron-l3-agent  nova-compute
    
# 修复ceph OSD
    https://docs.oracle.com/cd/E52668_01/E96266/html/ceph-luminous-node-remove.html
### stop osd进程之后，状态变为down 且 out
	docker stop ceph_osd_10
	docker exec -it ceph_mon bash 
    	ceph osd out osd.10
        ceph osd crush remove osd.10
        # 删除 CRUSH 图的对应 OSD 条目，它就不再接收数据了
	    ceph osd crush remove osd.10
        # 移除osd认证key
    	ceph auth del osd.10
        # 从osd中删除osd 10，ceph osd tree中移除
	    ceph osd rm osd.10
### 重新添加osd
	 parted /dev/sdb -s -- mklabel gpt
	 parted /dev/sdb -s -- mkpart KOLLA_CEPH_OSD_BOOTSTRAP_BS 1 -1
	 partprobe
	 # deploy 节点
	 kolla-ansible -i inventory/multinode  deploy --limit storage01


## 问题描述
    mariadb服务异常
    # 解决办法
    停止所有mariadb容器
    docker stop mariadb
### 找到最后关闭的mariadb主机，如果不记得就随机选取一台或者根据/var/lib/docker/volumes/mariadb/_data/grastate.dat的seqno进行选取(越大优先级越高)，然后修改其grastate.dat文件的safe_to_bootstrap参数 ##########
    vim /var/lib/docker/volumes/mariadb/_data/grastate.dat
    safe_to_bootstrap: 1
### 修改mariadb容器启动命令后启动容器，查询日志保证mariadb服务正常启动 ##########
     vim /etc/kolla/mariadb/config.json
     "command": "/usr/bin/mysqld_safe --wsrep-new-cluster",
     docker start mariadb
     tail -200f /var/lib/docker/volumes/kolla_logs/_data/mariadb/mariadb.log
### 启动其他节点的mariadb容器 ##########
     docker start mariadb
     tail -200f /var/lib/docker/volumes/kolla_logs/_data/mariadb/mariadb.log
### 确保集群运行正常后，恢复最初修改的config.json（这样就保证集群中所有的mariadb容器都是平等的）##########
     vim /etc/kolla/mariadb/config.json
     command": "/usr/bin/mysqld_safer",
     docker stop mariadb
     docker start mariadb
     tail -200f /var/lib/docker/volumes/kolla_logs/_data/mariadb/mariadb.log

# live migration
    https://www.voidking.com/dev-openstack-vm-block-live-migration/
    
+ pg 状态信息
	https://www.jianshu.com/p/a104d156f120
	
