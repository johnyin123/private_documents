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

ceph osd pool set libvirt-pool size 2
ceph osd pool set libvirt-pool pg_num 128

