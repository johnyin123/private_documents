#!/bin/bash
#http://docs.ceph.org.cn/
CEPH_RELEASE=luminous
#CEPH_RELEASE=jewel

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
yum -y install epel-release yum-plugin-priorities https://download.ceph.com/rpm-${CEPH_RELEASE}/el7/noarch/ceph-release-1-1.el7.noarch.rpm
#(rpm -q 'epel-release' || yum -y install epel-release) || true
yum makecache && yum update -y
#(rpm -q 'centos-release-ceph-${CEPH_RELEASE}' || yum -y install centos-release-ceph-${CEPH_RELEASE}) || true
# sed -i -e "s/enabled=1/enabled=1\\npriority=1/g" /etc/yum.repos.d/ceph.repo
(rpm -q 'ceph-deploy' || yum -y install ceph-deploy) || true

cat >>/home/$CEPH_USER/.bashrc<<EOFI
#export CEPH_DEPLOY_REPO_URL=http://mirrors.163.com/ceph/rpm-${CEPH_RELEASE}/el7
#export CEPH_DEPLOY_GPG_URL=http://mirrors.163.com/ceph/keys/release.asc
EOFI

# #根据一些Ceph的公开分享，8192是比较理想的值
# echo "8192" > /sys/block/sda/queue/read_ahead_kb
# echo "vm.swappiness = 0" | tee -a /etc/sysctl.conf
# echo "deadline" > /sys/block/sd[x]/queue/scheduler #for sata
# echo "noop" > /sys/block/sd[x]/queue/scheduler  #for ssd
# [osd] - filestore
# 参数名	描述	默认值	建议值
# filestore xattr use omap	为XATTRS使用object map，EXT4文件系统时使用，XFS或者btrfs也可以使用	false	true
# filestore max sync interval	从日志到数据盘最大同步间隔(seconds)	5	15
# filestore min sync interval	从日志到数据盘最小同步间隔(seconds)	0.1	10
# filestore queue max ops	数据盘最大接受的操作数	500	25000
# filestore queue max bytes	数据盘一次操作最大字节数(bytes)	100 << 20	10485760
# filestore queue committing max ops	数据盘能够commit的操作数	500	5000
# filestore queue committing max bytes	数据盘能够commit的最大字节数(bytes)	100 << 20	10485760000
# filestore op threads	并发文件系统操作数	2	32
# [osd] - journal
# 参数名	描述	默认值	建议值
# osd journal size	OSD日志大小(MB)	5120	20000
# journal max write bytes	journal一次性写入的最大字节数(bytes)	10 << 20	1073714824
# journal max write entries	journal一次性写入的最大记录数	100	10000
# journal queue max ops	journal一次性最大在队列中的操作数	500	50000
# journal queue max bytes	journal一次性最大在队列中的字节数(bytes)	10 << 20	10485760000
# 
# PG Number
# PG和PGP数量一定要根据OSD的数量进行调整，计算公式如下，但是最后算出的结果一定要接近或者等于一个2的指数。
# Total PGs = (Total_number_of_OSD * 100) / max_replication_count
# 例如15个OSD，副本数为3的情况下，根据公式计算的结果应该为500，最接近512，所以需要设定该pool(volumes)的pg_num和pgp_num都为512.
# ceph osd pool set volumes pg_num 512
# ceph osd pool set volumes pgp_num 512

EOF
done
rm -f hosts config

# deploy机器可ssh无密码登陆到其他节点
#    su - ceph
#    cd && mkdir -p ceph&&cd ceph

#    1. ceph-deploy new kvm1
#    #最小副本数
#    2. echo "osd pool default size = 2" >> ~/ceph/ceph.conf
#       ## echo "osd pool default min size = 1" >> ~/ceph/ceph.conf
#       ## echo "rbd_default_features = 1" >> ~/ceph/ceph.conf
#       ## public network = 10.0.1.0/24     #公共网络(monitorIP段) 
#       ## cluster network = 10.0.1.0/24    #集群网络
#    3. ceph-deploy install kvm1 kvm2 kvm3 ...
#    4. ceph-deploy mon create-initial 
#       # Deploy a manager daemon. (Required only for luminous+ builds):
#       # The Ceph Manager daemons operate in an active/standby pattern. 
#       # Deploying additional manager daemons ensures that if one daemon or host fails,
#       # another one can take over without interrupting service. ceph-deploy mgr create node2 node3
#       4.1. ceph-deploy mgr create kvm1  *Required only for luminous+ builds, i.e >= 12.x builds*
#       4.2. ceph mgr module enable dashboard
#           #The dashboard module runs on port 7000 by default. http://<active mgr host>:7000/
#    5. ceph-deploy disk list kvm1 ...
#          A. ceph-deploy disk zap kvm1:/dev/sda #clear disk old info
#              #. sudo parted -s /dev/sdd mkpart -a optimal primary 1 100%
#          B. ceph-deploy osd create --bluestore --data /dev/vda2 radosgw
#          B. ceph-deploy osd prepare kvm1:/dev/sda3 #partition
#          B. ceph-deploy osd prepare kvm1:/dev/sda  #disk
#    6. ceph-deploy osd activate kvm1:/dev/sda1 ...
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
#        ceph osd pool create cephfs_data <pg_num>
#        ceph osd pool create cephfs_metadata <pg_num>
#        ceph fs new <fsname> cephfs_metadata cephfs_data
#        #ceph.client.admin.keyring 
#        sudo mount -t ceph 10.0.2.100:/ /mnt -oname=admin,secret=AQCSQ+VZcc1aGRAAmi38hv51DUzwb9t/lpojBA==
#    remove cephfs
#        systemctl stop ceph-mds@kvm1.service
#        ceph mds fail 0
#        ceph fs rm <fsname> --yes-i-really-mean-it
#        ceph -s
        
#    2. rbd
#    su - ceph
#      2.1:rbd
#        sudo chmod 644 /etc/ceph/ceph.client.admin.keyring 
#        rbd create disk01 --size 10G --image-feature layering
#        rbd ls -l 
#        sudo rbd map disk01 
#        rbd showmapped 
#        sudo mkfs.xfs /dev/rbd0
#        sudo mount /dev/rbd0 /mnt
#      2.2:RBD-NBD
#        sudo rbd-nbd map disk01 
#        sudo rbd-nbd list-mapped

#    3. kvm pool rbd
#    su - ceph
#        ceph osd pool create libvirt-pool 128
#        rbd pool init libvirt-pool
#        ceph auth get-or-create client.libvirt mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=libvirt-pool'
#      #all kvm nodes run: uuid 各个主机要使用一个
#        echo -e "<secret ephemeral='no' private='no'>\n<uuid>$(cat /proc/sys/kernel/random/uuid)</uuid>\n<usage type='ceph'>\n<name>client.libvirt secret</name>\n</usage>\n</secret>" > secret.xml
#        sudo virsh secret-define --file secret.xml | awk '{print $2}' | tee uuid.txt
#        ceph auth get-key client.libvirt | tee client.libvirt.key
#        sudo virsh secret-set-value --secret $(cat uuid.txt) --base64 $(cat client.libvirt.key) && rm -f client.libvirt.key secret.xml uuid.txt
#        echo "<pool type='rbd'>
#          <name>libvirtpool</name>
#          <source>
#            <host name='10.0.2.101' port='6789'/>
#            <host name='10.0.2.102' port='6789'/>
#            <name>libvirt-pool</name>
#            <auth type='ceph' username='libvirt'>
#              <secret uuid='{uuid of secret}'/>
#            </auth>
#          </source>
#        </pool>" > libvirt-pool.xml
#        virsh pool-define libvirt-pool.xml
#        # sudo virsh pool-define-as libvirtpool --type rbd --source-host kvm01:6789,kvm02:6789,kvm03:6789 --source-name libvirt-pool --auth-type ceph --auth-username libvirt --secret-usage "client.libvirt secret"
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

# ceph --admin-daemon /var/run/ceph/ceph-osd.0.asok config show
# 安装Ceph环境
# 1. ceph-deploy install kvm03
# 
# 清除Ceph环境
# 1. ceph-deploy purge kvm1 kvm2 kvm3
# 2. ceph-deploy purgedata kvm1 kvm2 kvm3 
# 3. ceph-deploy forgetkeys
# ps aux|grep ceph |awk '{print $2}'|xargs kill -9
#
# ps -ef|grep ceph
# #确保此时所有ceph进程都已经关闭！！！如果没有关闭，多执行几次。
# umount /var/lib/ceph/osd/*
# rm -rf /var/lib/ceph/osd/*
# rm -rf /var/lib/ceph/mon/*
# rm -rf /var/lib/ceph/mds/*
# rm -rf /var/lib/ceph/bootstrap-mds/*
# rm -rf /var/lib/ceph/bootstrap-osd/*
# rm -rf /var/lib/ceph/bootstrap-mon/*
# rm -rf /var/lib/ceph/tmp/*
# rm -rf /etc/ceph/*
# rm -rf /var/run/ceph/*
# 
# Mon添加
# 0. ceph mon dump
# 1. ceph-deploy --overwrite-conf mon create kvm02
# 
# 1. ##echo "public network = 10.0.2.0/24">>ceph.conf
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

# OSD删除pool
# 1. ceph osd lspools
# 2. echo "mon allow pool delete = true" >> /etc/ceph/ceph.conf
# 3. systemctl restart ceph-mon@kvm1.service
# 4. ceph osd pool rm <poolname> <poolname> --yes-i-really-really-mean-it

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
cat > cephfs.fstab<<EOF
KVM1:6789:/ /mount-point    ceph    name=cephfs,secretfile=/etc/ceph/client.cephfs,noatime  0   2    
EOF
cat > create_kvmpool.sh<<EOF
#!/bin/bash
POOLNAME=libvirtpool
ceph osd pool create \${POOLNAME} 128
rbd pool init \${POOLNAME}
ceph auth get-or-create client.libvirt mon "allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=\${POOLNAME}"
KEY=\$(ceph auth get-key client.libvirt)

echo "all kvm nodes run: uuid 各个主机要使用一个"
SECRET_UUID=\$(cat /proc/sys/kernel/random/uuid)
echo -e "<secret ephemeral='no' private='no'>
  <uuid>\${SECRET_UUID}</uuid>
  <usage type='ceph'>
  <name>client.libvirt secret</name>
  </usage>
</secret>" > secret.xml
sudo virsh secret-define --file secret.xml
sudo virsh secret-set-value --secret \${SECRET_UUID} --base64 \${KEY}
echo -e "<pool type='rbd'>
  <name>\${POOLNAME}</name>
  <source>
    <host name='10.0.2.101' port='6789'/>
    <host name='10.0.2.102' port='6789'/>
    <name>\${POOLNAME}</name>
    <auth type='ceph' username='libvirt'>
      <secret uuid='\${SECRET_UUID}'/>
    </auth>
  </source>
</pool>" > \${POOLNAME}.xml

#use secret-usage cannot list host by virt-install 1.5.1
#sudo virsh pool-define-as \${POOLNAME} --type rbd --source-host kvm01:6789,kvm02:6789,kvm03:6789 --source-name \${POOLNAME} --auth-type ceph --auth-username libvirt --secret-usage "client.libvirt secret"

sudo virsh pool-define \${POOLNAME}.xml
sudo virsh pool-start \${POOLNAME}
sudo virsh pool-autostart \${POOLNAME}
EOF


cat <<EOF
#RadosGW S3 api
ceph-deploy rgw create {rgw-node-name}
ceph auth get-or-create client.radosgw.gateway osd 'allow rwx' mon 'allow rwx' -o ceph.client.radosgw.keyring
ceph-deploy --overwrite-conf admin radosgw
sudo cp ceph.client.radosgw.keyring /etc/ceph/
#手动创建各个存储池：
#ceph osd pool create {poolname} {pg-num} {pgp-num} {replicated | erasure} [{erasure-code-profile}] {ruleset-name} {ruleset-number}
#添加rgw配置
#在ceph.conf中添加一个名为gateway的实例。
[client.rgw.radosgw]
keyring = /etc/ceph/ceph.client.radosgw.keyring
rgw socket path = ""
rgw frontends = civetweb port=127.0.0.1:9980
rgw print continue = false

#添加rgw用户
radosgw-admin user create --uid=cephtest --display-name="ceph test" --email=a@a.com
#radosgw-admin user create --uid=admin --display-name=admin --access_key=admin --secret=123456
#测试
#!/usr/bin/env python
# -*- coding: utf-8 -*-
#最后一步生成的object url，通过wget访问时需要把一些特殊字符进行转义；
from __future__ import print_function
import boto3

def main():
    access_key = 'YZWPNTWAS69IP42NEQG2'
    secret_key = 'pq4SQ8jz81VvHvdf1RBRdJY0QhQn8lQ1RYBv7rbZ'
    s3_host = 'http://10.0.2.100'

    bucket_name = 'bruins'
    object_key = 'hello.txt'

    s3client = boto3.client('s3',
        aws_secret_access_key = secret_key,
        aws_access_key_id = access_key,
        endpoint_url = s3_host)
    response = s3client.list_buckets()
    for bucket in response['Buckets']:
        print("Listing owned buckets returns => {0} was created on {1}\n".format(bucket['Name'], bucket['CreationDate']))

    # creating a bucket
    response = s3client.create_bucket(Bucket = bucket_name)
    print("Creating bucket {0} returns => {1}\n".format(bucket_name, response))

    # creating an object
    response = s3client.put_object(Bucket = bucket_name, Key = object_key, Body = 'Hello World!')
    print("Creating object {0} returns => {1}\n".format(object_key, response))

    hello_url = s3client.generate_presigned_url('get_object', Params={'Bucket': bucket_name, 'Key': object_key}, ExpiresIn= 3600)
    print(hello_url)

if __name__ == '__main__':
    main() 

#rgw多实例
多rgw实例：安装rgw包，ceph.conf，密钥文件，前端配置文件拷贝到相应的节点，启动实例。
EOF
