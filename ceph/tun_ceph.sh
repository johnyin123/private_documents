# stats rbd iops
rbd --cluster armsite perf image iostat libvirt-pool
rbd --cluster armsite perf image iotop libvirt-pool
# rbd resize --image rbd1 --size 20480 --name client.rbd
# rbd info --image rbd1 --name client.rbd
# dmesg | grep -i capacity
# xfs_growfs -d /mnt/ceph-disk1
# cat pxe.raw | pv | ssh -p60022 root@10.32.151.250 'rbd import - libvirt-pool/pxe.raw'
############################################################
Active           Ceph可正常处理此pg请求
Clean            PG内所有的对象都被正确的复制了对应的份数
Down             一个包含必备数据的副本离线，所以PG也离线了
Degraded         PG中的一些对象还没有被复制到规定的份数
Inconsistent     Ceph检测到PG中对象的一份或多份数据不一致
Peering          PG正在互联过程中
Recovering       Ceph正在迁移/同步对象和其副本
Incomplete       Ceph探测到某一PG可能丢失了写入信息，或者没有健康的副本
Stale            PG状态未知，从PG mapping更新后Monitor一直没有收到更新

$ceph health detail
HEALTH_ERR 1 scrub errors; Possible data damage: 1 pg inconsistent
OSD_SCRUB_ERRORS 1 scrub errors
PG_DAMAGED Possible data damage: 1 pg inconsistent
    pg 1.5 is active+clean+inconsistent, acting [10,29,20]
$ceph pg repair 1.5
wait heath ok.
############################################################
#To reboot the Ceph Storage nodes
1.Disable Ceph Storage cluster rebalancing temporarily:
    $ ceph osd set noout
    $ ceph osd set nobackfill
    $ ceph osd set norecover
    $ reboot
2.Log into the node and check the cluster status:
    $ ceph -s
3.When complete, enable cluster rebalancing again:
    $ ceph osd unset noout
    $ ceph osd unset nobackfill
    $ ceph osd unset norecover
    $ ceph -s
############################################################
#reboot ceph node tempory
ceph osd set noout
ceph osd set norebalance
     # reboot it & power up
ceph osd unset noout
ceph osd unset norebalance
ceph -s

# health: HEALTH_WARN
#         1 pools have many more objects per pg than average
# # To disable the warning completely the value of mon_pg_warn_max_object_skew must be set to 0 or a negative number.
ceph config get mgr mon_pg_warn_max_object_skew
ceph config set mgr mon_pg_warn_max_object_skew 0
#更换故障硬盘过程
disk=sdd
ceph-volume lvm list
#pvs | grep ${disk}
/dev/... ceph-9fbe38b2-69a5-4e46-bb0c-c4d50546b369 lvm2 a--  1.09t    0
#ll /var/lib/ceph/osd/*/block | grep ceph-9fbe38b2-69a5-4e46-bb0c-c4d50546b369
lrwxrwxrwx 1 ceph ceph 93 4月  17 2019 /var/lib/ceph/osd/ceph-24/block -> /dev/ceph-9fbe38b2-69a5-4e46-bb0c-c4d50546b369/osd-block-265e3a5d-81d2-4e72-bbd9-1617cd8da3eb
#ceph osd tree
 -7        3.27480     host node03
 14   hdd  1.09160         osd.14      up  1.00000 1.00000
 19   hdd  1.09160         osd.19      up  1.00000 1.00000
 24   hdd  1.09160         osd.24      up  1.00000 1.00000

osd_id=24
#reweight the osd
ceph osd crush reweight osd.${osd_id} 0
#waiting_for_active_clean
ceph osd out osd.${osd_id}
#waiting_for_active_clean
ceph osd stat
#down the osd
systemctl stop ceph-osd@${osd_id}
ceph osd tree
#将删除的OSD从crush map中删除
ceph osd crush remove osd.${osd_id}
#此时使用ceph osd tree 已经看不到 osd.24
#清除到OSD的认证密钥
ceph auth del osd.${osd_id}
#在OSD Map中清除OSD
ceph osd rm ${osd_id}

#查看disk是否还挂载系统中.....
ceph-volume lvm zap /dev/${disk} --destroy
cat /sys/block/${disk}/device/state
#echo "1" > /sys/block/${disk}/device/delete

watch -n 1 "ceph -s"
#wait HEALTH OK!
############################################################

其他：
ceph osd set noout
ceph osd unset noout


$ceph health detail
# HEALTH_WARN 1/784075 objects unfound (0.000%); Degraded data redundancy: 1/2352225 objects degraded (0.000%), 1 pg degrade
# OBJECT_UNFOUND 1/784075 objects unfound (0.000%)
#     pg 1.ac has 1 unfound objects
# PG_DEGRADED Degraded data redundancy: 1/2352225 objects degraded (0.000%), 1 pg degraded
#     pg 1.ac is active+recovery_wait+degraded, acting [29,32,7], 1 unfound
1. For a new object without a previous version:
# ceph pg {pg.num} mark_unfound_lost delete
2. For an object which is likely to have a previous version:
# ceph pg {pg.num} mark_unfound_lost revert

for ip in $(seq 2 11)
do
	host=10.4.38.${ip}
    port=60022
    ssh -p60022 root@${host} "grep -Hn 'ERR' /var/log/ceph/ceph-osd.*.log"
done

/var/log/ceph/ceph-osd.29.log:280:2019-12-23 07:28:05.803229 7fc8c3146700 -1 log_channel(cluster) log [ERR] : 1.29d shard 29 soid 1:b9788255:::rbd_data.e59106b8b4567.0000000000000687:head : candidate had a read error
/var/log/ceph/ceph-osd.29.log:281:2019-12-23 07:28:13.207279 7fc8c3146700 -1 log_channel(cluster) log [ERR] : 1.29d repair 0 missing, 1 inconsistent objects
/var/log/ceph/ceph-osd.29.log:282:2019-12-23 07:28:13.207310 7fc8c3146700 -1 log_channel(cluster) log [ERR] : 1.29d repair 1 errors, 1 fixed

 then find which OSD error. and then sudo find the object

    /var/lib/ceph/osd/ceph-21/current/17.1c1_head/ -name 'rb.0.90213.238e1f29.00000001232d*' -ls
671193536 4096 -rw-r--r-- 1 root root 4194304 Feb 14 01:05 /var/lib/ceph/osd/ceph-21/current/17.1c1_head/DIR_1/DIR_C/DIR_1/DIR_C/rb.0.90213.238e1f29.00000001232d__head_58BCC1C1__11

smartctl -C -a /dev/sdb





sed -i "s/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"numa=off\"/g" /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
echo "8192" > /sys/block/sda/queue/read_ahead_kb
echo "vm.swappiness = 0"/etc/sysctl.conf
#SATA/SAS使用deadline
echo "deadline" >/sys/block/sd[x]/queue/scheduler
#SSD noop
echo "noop" >/sys/block/sd[x]/queue/scheduler
PG和PGP数量一定要根据OSD的数量进行调整，计算公式如下，但是最后算出的结果一定要接近或者等于一个2的指数。
Total PGs = (Total_number_of_OSD * 100) / max_replication_count
例：
有100个osd，2副本，5个pool
Total PGs =100*100/2=5000
每个pool 的PG=5000/5=1000，那么创建pool的时候就指定pg为1024
ceph osd pool create pool_name 1024


ceph --admin-daemon /var/run/ceph/ceph-osd.0.asok config show
ceph osd pool set <poolname> pg_num 128
ceph osd pool set <poolname> size 2
ceph osd pool set <poolname> min_size 1
ceph osd pool set <poolname> max_size 1

升级Ceph
    设置sortbitwis
        如果未设置，升级过程中可能会出现数据丢失的情况
        # ceph osd set sortbitwise
    设置noout
    为了防止升级过程中出现数据重平衡，升级完成后取消设置即可
        # ceph osd set noout
设置完成后集群状态ceph -s,

ceph osd set sortbitwise
ceph osd set noout #避免在异常情况下不可控
ceph osd down osd.x #提前mark down， 减少slow request

ceph osd stop osd.x
    systemctl stop ceph-osd@X #service ceph restart osd.x
#here you work or reboot.....
ceph osd start osd.x
ceph osd unset noout

扩展集群的时候需要非常小心，因为它会触发数据迁移：
设置crush map
设置recovery options
在凌晨12点触发数据迁移
观察数据迁移的速度，观察每个机器上网口的带宽，避免跑满
观察slow requests的数量


查看rbd被挂载到哪里
for id in $(for i in $(rbd --cluster armsite ls k8spool); do rbd --cluster armsite info k8spool/$i; done | grep prefix | sed -r "s/^.*prefix\s*:\s*rbd_data.(.*)/\1/")
do
    rados --cluster armsite  -p k8spool listwatchers rbd_header.$id
done

    对于image format为1的块：
    $ rbd info boot
    rbd image 'boot':
        size 10240 MB in 2560 objects
        order 22 (4096 kB objects)
        block_name_prefix: rb.0.89ee.2ae8944a
        format: 1
    $ rados -p rbd listwatchers boot.rbd
    watcher=192.168.251.102:0/2550823152 client.35321 cookie=1
    
    对于image format为2的块，有些不一样：
    [root@osd2 ceph]# rbd info myrbd/rbd1
    rbd image 'rbd1':
    	size 8192 kB in 2 objects
    	order 22 (4096 kB objects)
    	block_name_prefix: rbd_data.13436b8b4567
    	format: 2
    	features: layering
    [root@osd2 ceph]# rados -p myrbd listwatchers rbd_header.13436b8b4567
    watcher=192.168.108.3:0/2292307264 client.5130 cookie=1
    需要将rbd info得到的序号加到rbd_header后面。



ceph osd tier add satapool ssdpool
ceph osd tier cache-mode ssdpool writeback
ceph osd pool set ssdpool hit_set_type bloom
ceph osd pool set ssdpool hit_set_count 1
## In this example 80-85% of the cache pool is equal to 280GB
ceph osd pool set ssdpool target_max_bytes $((280*1024*1024*1024))
ceph osd tier set-overlay satapool ssdpool
ceph osd pool set ssdpool hit_set_period 300
ceph osd pool set ssdpool cache_min_flush_age 300   # 10 minutes
ceph osd pool set ssdpool cache_min_evict_age 1800   # 30 minutes
ceph osd pool set ssdpool cache_target_dirty_ratio .4
ceph osd pool set ssdpool cache_target_full_ratio .8


19. 修改osd journal的存储路径
#noout参数会阻止osd被标记为out，使其权重为0
ceph osd set noout
service ceph stop osd.1
ceph-osd -i 1 --flush-journal
mount /dev/sdc /journal
ceph-osd -i 1 --mkjournal /journal
service ceph start osd.1
ceph osd unset noout


22. pg_num不够用，进行迁移和重命名
ceph osd pool create new-pool pg_num
rados cppool old-pool new-pool
ceph osd pool delete old-pool
ceph osd pool rename new-pool old-pool

#或者直接增加pool的pg_num


ceph 可以在运行时更改 ceph-osd、ceph-mon、ceph-mds 守护进程的配置,这种功能在增加/降低日志输出、启
用/禁用调试设置、甚至是运行时优化的时候非常有用,下面是运行时配置的用法:
ceph {daemon-type} tell {id or *} injectargs '--{name} {value} [--{name} {value}]'
用 osd、mon、mds 中的一个替代{daemon-type},你可以用星号(*)或具体进程 ID(其数字或字母)把运行时
配置应用到一类进程的所有例程,例如增加名为 osd.0 的 ceph-osd 进程的调试级别的命令如下:
ceph osd tell 0 injectargs '--debug-osd 20 --debug-ms 1'


REMOVE OSD:
    systemctl stop ceph-osd@$osdid.service
    ceph osd down $osdid
    ceph osd crush remove osd.$osdid
    ceph auth del osd.$osdid
    ceph osd rm $osdid
    umount /var/lib/ceph/osd/ceph-$osdid
REMOVE MON
    systemctl stop ceph-mon@$monid.service
    ceph mon remove $monid

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





# [global]
# fsid = 059f27e8-a23f-4587-9033-3e3679d03b31
# mon_host = 10.10.20.102, 10.10.20.101, 10.10.20.100
# auth cluster required = cephx
# auth service required = cephx
# auth client required = cephx
# osd pool default size = 3
# osd pool default min size = 1
# 
# public network = 10.10.20.0/24
# cluster network = 10.10.20.0/24
# 
# max open files = 131072
# 
# [mon]
# mon data = /var/lib/ceph/mon/ceph-$id
# 
# [osd]
# osd data = /var/lib/ceph/osd/ceph-$id
# osd journal size = 20000
# osd mkfs type = xfs
# osd mkfs options xfs = -f
# 
# filestore xattr use omap = true
# filestore min sync interval = 10
# filestore max sync interval = 15
# filestore queue max ops = 25000
# filestore queue max bytes = 10485760
# filestore queue committing max ops = 5000
# filestore queue committing max bytes = 10485760000
# 
# journal max write bytes = 1073714824
# journal max write entries = 10000
# journal queue max ops = 50000
# journal queue max bytes = 10485760000
# 
# osd max write size = 512
# osd client message size cap = 2147483648
# osd deep scrub stride = 131072
# osd op threads = 8
# osd disk threads = 4
# osd map cache size = 1024
# osd map cache bl size = 128
# osd mount options xfs = "rw,noexec,nodev,noatime,nodiratime,nobarrier"
# osd recovery op priority = 4
# osd recovery max active = 10
# osd max backfills = 4
# 
# [client]
# rbd cache = true
# rbd cache size = 268435456
# rbd cache max dirty = 134217728
# rbd cache max dirty age = 5
