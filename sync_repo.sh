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
enabled=0
gpgcheck=0
exclude=sip,PyQt4

[centos-qemu-ev]
name=CentOS-$releasever - QEMU EV
baseurl=http://10.3.60.99/centos/$releasever/virt/$basearch/kvm-common/
enabled=0
gpgcheck=0

[centos-ceph-luminous]
name=CentOS-$releasever - Ceph Luminous
baseurl=http://10.3.60.99/centos/$releasever/storage/$basearch/ceph-luminous/
enabled=0
gpgcheck=0

[zabbix]
name=zabbix-3.4
baseurl=http://10.3.60.99/centos/$releasever/zabbix/$basearch/
enabled=0
gpgcheck=0
EOF

PREFIX=/opt
releasever=7
basearch=x86_64

#-m选项指明需下载软件分组信息文件——comps.xml,

reposync --norepopath -mnr base -p ${PREFIX}/centos/$releasever/base/$basearch/
createrepo -g ${PREFIX}/centos/7/base/x86_64/comps.xml -d ${PREFIX}/centos/$releasever/base/$basearch/

reposync --norepopath -mnr updates -p ${PREFIX}/centos/$releasever/updates/$basearch/
createrepo -d ${PREFIX}/centos/$releasever/updates/$basearch/

reposync --norepopath -mnr extras -p ${PREFIX}/centos/$releasever/extras/$basearch/
createrepo -d ${PREFIX}/centos/$releasever/extras/$basearch/

reposync --norepopath -mnr epel -p ${PREFIX}/centos/$releasever/epel/$basearch
createrepo -g ${PREFIX}/centos/7/epel/x86_64/comps.xml  -d ${PREFIX}/centos/$releasever/epel/$basearch/

reposync --norepopath -mnr centos-openstack-queens -p ${PREFIX}/centos/$releasever/openstack-queens/$basearch/Packages
createrepo -d ${PREFIX}/centos/$releasever/openstack-queens/$basearch/

reposync --norepopath -mnr centos-qemu-ev -p ${PREFIX}/centos/$releasever/virt/$basearch/kvm-common/Packages
createrepo -d ${PREFIX}/centos/$releasever/virt/$basearch/kvm-common/

reposync --norepopath -mnr centos-ceph-luminous -p ${PREFIX}/centos/$releasever/storage/$basearch/ceph-luminous/Packages
createrepo -d ${PREFIX}/centos/$releasever/storage/$basearch/ceph-luminous/

reposync --norepopath -mnr zabbix -p ${PREFIX}/centos/$releasever/zabbix/$basearch/Packages
createrepo -d ${PREFIX}/centos/$releasever/zabbix/$basearch/


