export CEPH_DEPLOY_REPO_URL=http://mirrors.163.com/ceph/debian-jewel
export CEPH_DEPLOY_GPG_URL=http://mirrors.163.com/ceph/keys/release.asc

1.0 准备

三台虚拟机分别改hosts和hostname文件为ceph-node1、ceph-node2、ceph-node3，并分别挂载三个磁盘。ceph-node1节点作为ceph-deploy节点，三个节点同时作为osd节点和monitor节点。

1.1 添加release.key

apt-get update && apt-get -y upgrade
wget -q -O- 'https://download.ceph.com/keys/autobuild.asc' | apt-key add -
1.2 添加Ceph软件包源，用Ceph稳定版

echo deb http://download.ceph.com/debian-jewel/ $(lsb_release -sc) main | tee /etc/apt/sources.list.d/ceph.list
1.3 更新源仓库并安装Ceph

apt-get update && apt-get install ceph-deploy
1.4 安装NTP（以免因时钟漂移导致故障）

apt-get install ntp
1.5安装 SSH 服务器

apt-get install openssh-server
 注意：以下命令只在ceph-node1节点中执行
1.6允许无密码 SSH 登录

1.6.1 生成 SSH 密钥对，但不要用 sudo 或 root 用户。提示 “Enter passphrase” 时，直接回车，口令即为空：

ssh-keygen
1.6.2 把公钥拷贝到各 Ceph 节点。

ssh-copy-id　ceph-node1 ceph-node2 ceph-node3
1.7 创建集群

ceph-deploy new ceph-node1 ceph-node2 ceph-node3
1.8 安装ceph

ceph-deploy install ceph-node1 ceph-node2 ceph-node3
1.9 配置初始监视器，并收集所有秘钥

ceph-deploy mon create-initial
1.10 删除磁盘现有分区表和磁盘内容

ceph-deploy disk zap ceph-node1:xvdb ceph-node1:xvdc ceph-node1:xvde ceph-node2:xvdb ceph-node2:xvdc ceph-node2:xvde ceph-node3:xvdb ceph-node3:xvdc ceph-node3:xvde
1.11 准备OSD

ceph-deploy osd prepare ceph-node1:xvdb ceph-node1:xvdc ceph-node1:xvde ceph-node2:xvdb ceph-node2:xvdc ceph-node2:xvde ceph-node3:xvdb ceph-node3:xvdc ceph-node3:xvde
1.12 激活OSD

ceph-deploy osd activate ceph-node1:xvdb1 ceph-node1:xvdc1 ceph-node1:xvde1 ceph-node2:xvdb1 ceph-node2:xvdc1 ceph-node2:xvde1 ceph-node3:xvdb1 ceph-node3:xvdc1 ceph-node3:xvde1
1.13 调整rbd存储池pg_num和pgp_num的值

ceph osd pool set rbd pg_num 256
ceph osd pool set rbd pgp_num 256
1.14 验证

ceph -s

