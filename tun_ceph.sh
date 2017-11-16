sed -i "s/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"numa=off\"" /etc/default/grub
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
ceph osd set noout #避免在异常情况下不可控
ceph osd down x #提前mark down， 减少slow request
service ceph restart osd.x

更换硬件或者升级内核时需要对机器进行重启
把这台机器上的虚拟机迁移到其他机器上
ceph osd set noout
ceph osd down x #把这个机器上的OSD都设置为down状态
service ceph stop osd.x
重启机器

扩展集群的时候需要非常小心，因为它会触发数据迁移：
设置crush map
设置recovery options
在凌晨12点触发数据迁移
观察数据迁移的速度，观察每个机器上网口的带宽，避免跑满
观察slow requests的数量


查看rbd被挂载到哪里
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
