export CEPH_DEPLOY_REPO_URL=http://mirrors.163.com/ceph/debian-jewel
export CEPH_DEPLOY_GPG_URL=http://mirrors.163.com/ceph/keys/release.asc
apt-get update && apt-get -y upgrade
wget -q -O- 'https://download.ceph.com/keys/autobuild.asc' | apt-key add -
echo deb http://download.ceph.com/debian-jewel/ $(lsb_release -sc) main | tee /etc/apt/sources.list.d/ceph.list
apt-get update && apt-get install ceph-deploy

ceph-deploy disk zap ceph-node1:xvdb ceph-node1:xvdc ceph-node1:xvde ceph-node2:xvdb ceph-node2:xvdc ceph-node2:xvde ceph-node3:xvdb ceph-node3:xvdc ceph-node3:xvde
ceph-deploy osd prepare ceph-node1:xvdb ceph-node1:xvdc ceph-node1:xvde ceph-node2:xvdb ceph-node2:xvdc ceph-node2:xvde ceph-node3:xvdb ceph-node3:xvdc ceph-node3:xvde
ceph-deploy osd activate ceph-node1:xvdb1 ceph-node1:xvdc1 ceph-node1:xvde1 ceph-node2:xvdb1 ceph-node2:xvdc1 ceph-node2:xvde1 ceph-node3:xvdb1 ceph-node3:xvdc1 ceph-node3:xvde1

1.13 调整rbd存储池pg_num和pgp_num的值

ceph osd pool set rbd pg_num 256
ceph osd pool set rbd pgp_num 256
1.14 验证

ceph -s

