#!/bin/bash
#http://docs.ceph.org.cn/
CEPH_USER=ceph
CEPH_PASSWD=password
[[ -r "hosts.conf" ]] || {
	cat >"hosts.conf" <<- EOF
#IP          hostname(小写)  ssh_port   type
10.0.2.100   kvm1         60022         deploy|mon|osd
10.0.2.101   kvm2         60022         mon|osd
10.0.2.102   kvm3         60022         mon|osd

EOF
	echo "Created hosts.conf using defaults.  Please review it/configure before running again."
	exit 1
}

CONF='cat hosts.conf | grep -v -e "^$" -e "^#"'
IPS=$(eval $CONF | awk '{print $1}')

echo "127.0.0.1 localhost" > hosts
>config
for ip in $IPS
do
	CUR_HOSTNAME=$(eval $CONF | grep ${ip} | awk '{print $2}')
	SSH_PORT=$(eval $CONF | grep ${ip} | awk '{print $3}')
    cat >>config <<- EOF
Host $CUR_HOSTNAME 
    Hostname $ip
    Port $SSH_PORT
    User $CEPH_USER
EOF
echo "${ip} ${CUR_HOSTNAME}" >> hosts

done

for ip in $IPS
do
    CUR_HOSTNAME=$(eval $CONF | grep ${ip} | awk '{print $2}')
    cat > init_ceph.${ip}.sh << EOF
hostnamectl set-hostname ${CUR_HOSTNAME}
id $CEPH_USER || useradd -m $CEPH_USER
echo $CEPH_PASSWD | passwd --stdin $CEPH_USER
echo -e 'Defaults: $CEPH_USER !requiretty\\n$CEPH_USER ALL = (root) NOPASSWD:ALL' | tee /etc/sudoers.d/$CEPH_USER
chmod 440 /etc/sudoers.d/$CEPH_USER
cat > /etc/hosts <<EOFI
$(cat hosts)
EOFI
su - ceph -c "ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa"
#ssh-keygen -t rsa -b 2048 -f "/var/tmp/packstack/20171024-075012-mlCitr/nova_migration_key" -N ""
#mkdir -p ~/.ssh && chmod 700 ~/.ssh
cat > /home/$CEPH_USER/.ssh/config <<EOFC
$(cat config)
EOFC
chown $CEPH_USER:$CEPH_USER /home/$CEPH_USER/.ssh/config 
chmod 600 /home/$CEPH_USER/.ssh/config
yum -y install epel-release yum-plugin-priorities https://download.ceph.com/rpm-jewel/el7/noarch/ceph-release-1-0.el7.noarch.rpm
#(rpm -q 'epel-release' || yum -y install epel-release) || true
yum makecache && yum update -y
#(rpm -q 'centos-release-ceph-jewel' || yum -y install centos-release-ceph-jewel) || true
# sed -i -e "s/enabled=1/enabled=1\\npriority=1/g" /etc/yum.repos.d/ceph.repo
(rpm -q 'ceph-deploy' || yum -y install ceph-deploy) || true

cat >>/home/$CEPH_USER/.bashrc<<EOFI
#export CEPH_DEPLOY_REPO_URL=http://mirrors.163.com/ceph/rpm-jewel/el7
#export CEPH_DEPLOY_GPG_URL=http://mirrors.163.com/ceph/keys/release.asc
EOFI

EOF
done
rm -f hosts config

# deploy机器可ssh无密码登陆到其他节点
#    su - ceph
#    cd && mkdir -p ceph&&cd ceph

#    1. ceph-deploy new kvm1
#    #最小副本数
#    2. echo "osd pool default size = 2" >> ~/ceph/ceph.conf
#       echo "rbd_default_features = 1" >> ~/ceph/ceph.conf
#    3. ceph-deploy install kvm1 kvm2 kvm3 ...
#    4. ceph-deploy mon create-initial 
#    5. ceph-deploy disk list kvm1 ...
#          A. ceph-deploy disk zap kvm1:/dev/sda #whole disk
#          B. ceph-deploy osd prepare kvm1:/dev/sda3 #partition
#    6. ceph-deploy osd activate kvm1:/dev/sda3 ...
#    7. MUST:add mount point in fstab!
#    8. ceph-deploy admin kvm1
#    9. sudo chmod 644 /etc/ceph/ceph.client.admin.keyring   
#    0. ceph health
# 时间一定同步
#    chronyc sourcestats -v


#    1. cephfs
#    su - ceph
#        echo "建立元数据服务,至少需要一个元数据服务器才能使用CephFS"
#        ceph-deploy mds create kvm1
#        echo "create pool(pg=256)"
#        ceph osd pool create pool1 256
#        ceph osd pool create pool2 256
#        ceph fs new cephfs pool2 pool1
#        #ceph.client.admin.keyring 
#        sudo mount -t ceph 10.0.2.100:/ /mnt -oname=admin,secret=AQCSQ+VZcc1aGRAAmi38hv51DUzwb9t/lpojBA==

#    2. rbd
#    su - ceph
#        sudo chmod 644 /etc/ceph/ceph.client.admin.keyring 
#        rbd create disk01 --size 10G --image-feature layering
#        rbd ls -l 
#        sudo rbd map disk01 
#        rbd showmapped 
#        sudo mkfs.xfs /dev/rbd0
#        sudo mount /dev/rbd0 /mnt

#    3. kvm pool rbd
#    su - ceph
#        ceph osd pool create libvirt-pool 100 100
#        ceph auth get-or-create client.libvirt mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=libvirt-pool'
#      #all kvm nodes run: uuid 各个主机要使用一个
#        echo -e "<secret ephemeral='no' private='no'>\n<uuid>$(cat /proc/sys/kernel/random/uuid)</uuid>\n<usage type='ceph'>\n<name>client.libvirt secret</name>\n</usage>\n</secret>" > secret.xml
#        sudo virsh secret-define --file secret.xml | awk '{print $2}' | tee uuid.txt
#        ceph auth get-key client.libvirt | sudo tee client.libvirt.key
#        sudo virsh secret-set-value --secret $(cat uuid.txt) --base64 $(cat client.libvirt.key) && rm -f client.libvirt.key secret.xml uuid.txt
#        # echo "<pool type='rbd'>
#        #   <name>libvirtpool</name>
#        #   <source>
#        #     <host name='10.0.2.101' port='6789'/>
#        #     <host name='10.0.2.102' port='6789'/>
#        #     <name>libvirt-pool</name>
#        #     <auth type='ceph' username='libvirt'>
#        #       <secret uuid='{uuid of secret}'/>
#        #     </auth>
#        #   </source>
#        # </pool>" > libvirt-pool.xml
#        # virsh pool-define libvirt-pool.xml
#        sudo virsh pool-define-as libvirtpool --type rbd --source-host kvm01:6789,kvm02:6789,kvm03:6789 --source-name libvirt-pool --auth-type ceph --auth-username libvirt --secret-usage "client.libvirt secret"
#        sudo virsh pool-start libvirtpool
#        sudo virsh pool-autostart libvirtpool

#    1.virt-manager add a regual vm
#    2.virsh edit ....
#        <disk type='network' device='disk'>
#          <auth username='libvirt'>
#            <secret type='ceph' uuid='d718b247-a799-443f-b4a4-a0179c2ccfb9'/>
#          </auth>
#          <source protocol='rbd' name='libvirt-pool/centos7'>
#            <host name='kvm01' port='6789'/>
#            <host name='kvm02' port='6789'/>
#            <host name='kvm03' port='6789'/>
#          </source>
#          <target dev='vda' bus='virtio'/>
#        </disk>
#    3.boot and startvm ..


# 安装Ceph环境
# 1. ceph-deploy install kvm03
# 
# 清除Ceph环境
# 1. ceph-deploy purge kvm1 kvm2 kvm3
# 1. ceph-deploy purgedata kvm1 kvm2 kvm3 
# 1. ceph-deploy forgetkeys
# 
# 
# Mon添加
# 0. ceph mon dump
# 1. ceph-deploy --overwrite-conf mon create kvm02
# 
# 1. echo "public network = 10.0.2.0/24">>ceph.conf
# 2. ceph-deploy --overwrite-conf admin kvm01 kvm02
# 3. sudo chmod 644 /etc/ceph/ceph.client.admin.keyring   
# 
# Mon删除
# 0. ceph mon dump
# 1. ceph-deploy mon destroy kvm02
# 2. ceph-deploy --overwrite-conf admin kvm01 kvm02
# 3. sudo chmod 644 /etc/ceph/ceph.client.admin.keyring   
# 
# OSD添加
# 0. ceph osd tree
# 1. ceph-deploy disk list kvm02
# 2.    ceph-deploy disk zap kvm02:/dev/sda #whole disk
# 2. ceph-deploy osd prepare kvm02:/dev/sda3 #partition
# 3. ceph-deploy osd activate kvm02:/dev/sda3
# 4. MUST:add mount point in fstab!
# 
# OSD删除
# 0. ceph osd tree #查看目前cluster 状态
# 1. ceph osd out osd.3
# 2. service ceph stop osd.3 / systemctl stop ceph-osd@3
# 3. ceph osd crush remove osd.3
# 4. ceph auth del osd.3
# 5. ceph osd rm 3
# 6. ceph osd crush remove kvm02
# 7. MUST:remove mount point in fstab!



cat >rbd.service<<EOF
# rbd info foo
# rbd feature disable foo exclusive-lock, object-map, fast-diff, deep-flatten
#/etc/systemd/system/rbd-{ceph_pool}-{ceph_image}.service
[Unit]
Description=RADOS block device mapping for "{ceph_pool}"/"{ceph_image}"
Conflicts=shutdown.target
Wants=network-online.target
# Remove this if you don't have Networkmanager
After=NetworkManager-wait-online.service

[Service]
Type=oneshot
ExecStart=/sbin/modprobe rbd
ExecStart=/bin/sh -c "/bin/echo {ceph_mon_ip} name={ceph_admin},secret={ceph_key} {ceph_pool} {ceph_image} >/sys/bus/rbd/add"
TimeoutSec=0
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
WantedBy=remote-fs-pre.target
EOF
# ceph.conf
# [global]#全局设置
# fsid = 88caa60a-e6d1-4590-a2b5-bd4e703e46d9           #集群标识ID 
# mon host = 10.0.1.21,10.0.1.22,10.0.1.23            #monitor IP 地址
# auth cluster required = cephx                  #集群认证
# auth service required = cephx                           #服务认证
# auth client required = cephx                            #客户端认证
# osd pool default size = 2                             #最小副本数
# osd pool default min size = 1                           #PG 处于 degraded 状态不影响其 IO 能力,min_size是一个PG能接受IO的最小副本数
# osd pool default pg num = 128                           #pool的pg数量
# osd pool default pgp num = 128                          #pool的pgp数量
# public network = 10.0.1.0/24                            #公共网络(monitorIP段) 
# cluster network = 10.0.1.0/24                           #集群网络
# max open files = 131072                                 #默认0#如果设置了该选项，Ceph会设置系统的max open fds
# mon initial members = controller1, controller2, compute01 #初始monitor (由创建monitor命令而定)
# ##############################################################
# [mon]
# mon data = /var/lib/ceph/mon/ceph-$id
# mon clock drift allowed = 1                             #默认值0.05#monitor间的clock drift
# mon osd min down reporters = 13                         #默认值1#向monitor报告down的最小OSD数
# mon osd down out interval = 600      #默认值300      #标记一个OSD状态为down和out之前ceph等待的秒数
# ##############################################################
# [osd]
# osd data = /var/lib/ceph/osd/ceph-$id
# osd journal size = 20000 #默认5120                      #osd journal大小
# osd journal = /var/lib/ceph/osd/$cluster-$id/journal #osd journal 位置
# osd mkfs type = xfs                                     #格式化系统类型
# osd mkfs options xfs = -f -i size=2048                  #强制格式化
# filestore xattr use omap = true                         #默认false#为XATTRS使用object map，EXT4文件系统时使用，XFS或者btrfs也可以使用
# filestore min sync interval = 10                        #默认0.1#从日志到数据盘最小同步间隔(seconds)
# filestore max sync interval = 15                        #默认5#从日志到数据盘最大同步间隔(seconds)
# filestore queue max ops = 25000                        #默认500#数据盘最大接受的操作数
# filestore queue max bytes = 1048576000      #默认100   #数据盘一次操作最大字节数(bytes
# filestore queue committing max ops = 50000 #默认500     #数据盘能够commit的操作数
# filestore queue committing max bytes = 10485760000 #默认100 #数据盘能够commit的最大字节数(bytes)
# filestore split multiple = 8 #默认值2                  #前一个子目录分裂成子目录中的文件的最大数量
# filestore merge threshold = 40 #默认值10               #前一个子类目录中的文件合并到父类的最小数量
# filestore fd cache size = 1024 #默认值128              #对象文件句柄缓存大小
# journal max write bytes = 1073714824 #默认值1048560    #journal一次性写入的最大字节数(bytes)
# journal max write entries = 10000 #默认值100         #journal一次性写入的最大记录数
# journal queue max ops = 50000  #默认值50            #journal一次性最大在队列中的操作数
# journal queue max bytes = 10485760000 #默认值33554432   #journal一次性最大在队列中的字节数(bytes)
# osd max write size = 512 #默认值90                   #OSD一次可写入的最大值(MB)
# osd client message size cap = 2147483648 #默认值100    #客户端允许在内存中的最大数据(bytes)
# osd deep scrub stride = 131072 #默认值524288         #在Deep Scrub时候允许读取的字节数(bytes)
# osd op threads = 16 #默认值2                         #并发文件系统操作数
# osd disk threads = 4 #默认值1                        #OSD密集型操作例如恢复和Scrubbing时的线程
# osd map cache size = 1024 #默认值500                 #保留OSD Map的缓存(MB)
# osd map cache bl size = 128 #默认值50                #OSD进程在内存中的OSD Map缓存(MB)
# osd mount options xfs = "rw,noexec,nodev,noatime,nodiratime,nobarrier" #默认值rw,noatime,inode64  #Ceph OSD xfs Mount选项
# osd recovery op priority = 2 #默认值10              #恢复操作优先级，取值1-63，值越高占用资源越高
# osd recovery max active = 10 #默认值15              #同一时间内活跃的恢复请求数 
# osd max backfills = 4  #默认值10                  #一个OSD允许的最大backfills数
# osd min pg log entries = 30000 #默认值3000           #修建PGLog是保留的最大PGLog数
# osd max pg log entries = 100000 #默认值10000         #修建PGLog是保留的最大PGLog数
# osd mon heartbeat interval = 40 #默认值30            #OSD ping一个monitor的时间间隔（默认30s）
# ms dispatch throttle bytes = 1048576000 #默认值 104857600 #等待派遣的最大消息数
# objecter inflight ops = 819200 #默认值1024           #客户端流控，允许的最大未发送io请求数，超过阀值会堵塞应用io，为0表示不受限
# osd op log threshold = 50 #默认值5                  #一次显示多少操作的log
# osd crush chooseleaf type = 0 #默认值为1              #CRUSH规则用到chooseleaf时的bucket的类型
# ##############################################################
# [client]
# rbd cache = true #默认值 true      #RBD缓存
# rbd cache size = 335544320 #默认值33554432           #RBD缓存大小(bytes)
# rbd cache max dirty = 134217728 #默认值25165824      #缓存为write-back时允许的最大dirty字节数(bytes)，如果为0，使用write-through
# rbd cache max dirty age = 30 #默认值1                #在被刷新到存储盘前dirty数据存在缓存的时间(seconds)
# rbd cache writethrough until flush = false #默认值true  #该选项是为了兼容linux-2.6.32之前的virtio驱动，避免因为不发送flush请求，数据不回写
#               #设置该参数后，librbd会以writethrough的方式执行io，直到收到第一个flush请求，才切换为writeback方式。
# rbd cache max dirty object = 2 #默认值0              #最大的Object对象数，默认为0，表示通过rbd cache size计算得到，librbd默认以4MB为单位对磁盘Image进行逻辑切分
#       #每个chunk对象抽象为一个Object；librbd中以Object为单位来管理缓存，增大该值可以提升性能
# rbd cache target dirty = 235544320 #默认值16777216    #开始执行回写过程的脏数据大小，不能超过 rbd_cache_max_dirty

