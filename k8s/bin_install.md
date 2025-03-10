# Kubernetes 1.30 集群部署

---

## 索引

* [集群部署说明](#集群部署说明)

  * [组件版本](#组件版本)

  * [网络规划](#网络规划)

  * [主机说明](#主机说明)

* [前置准备](#前置准备此处步骤不做具体说明)

* [设置时区](#设置时区)

* [设置 PATH 环境变量](#设置-path-环境变量)

* [安装所需软件包](#安装所需软件包)

* [禁用 SWAP](#禁用-swap)

* [加载内核模块](#加载内核模块)

* [设置内核参数](#设置内核参数)

* [设置 PAM limits](#设置-pam-limits)

* [（可选） 降级 Cgroups 版本](#可选-降级-cgroups-版本)

* [重启 v1 - v6](#重启-v1---v6)

* [安装配置外部负载均衡 HAProxy](#安装配置外部负载均衡-haproxy)

* [分发 K8S 二进制组件](#分发-k8s-二进制组件)

  * [分发至所有节点](#分发至所有节点)

  * [复制 kubectl kubeadm 至 v0 集群终端主机](#复制-kubectl-kubeadm-至-v0-集群终端主机)

  * [配置 kubectl Bash 自动补全](#配置-kubectl-bash-自动补全)

  * [生成集群 CA 证书](#生成集群-ca-证书)

  * [分发 CA 证书](#分发-ca-证书)

  * [生成 Cluster-Admin 证书](#生成-cluster-admin-证书)

  * [分发 Cluster-Admin 证书（可选，不建议）](#分发-cluster-admin-证书可选不建议)

* [生成 Cluster-Admin kubeconfig](#生成-cluster-admin-kubeconfig)

  * [复制 admin kubeconfig 至 v0 kubectl 配置文件目录](#复制-admin-kubeconfig-至-v0-kubectl-配置文件目录)

  * [分发 admin kubeconfig 至其他节点（可选）](#分发-admin-kubeconfig-至其他节点可选)

* [部署 etcd Cluster](#部署-etcd-cluster)

  * [下载解压](#下载解压)

  * [分发 etcd 程序至 Master 节点](#分发-etcd-程序至-master-节点)

  * [创建 etcd 证书](#创建-etcd-证书)

  * [分发 etcd 证书至 Master 节点](#分发-etcd-证书至-master-节点)

  * [创建 etcd Systemd Service Unit](#创建-etcd-systemd-service-unit)

  * [启动 etcd](#启动-etcd)

  * [检查 etcd Cluster 工作状态](#检查-etcd-cluster-工作状态)

  * [创建 etcd 自动备份](#创建-etcd-自动备份)

* [生成 K8S 证书](#生成-k8s-证书)

  * [分发 K8S 证书](#分发-k8s-证书)

* [创建 K8S 加密配置](#创建-k8s-加密配置)

  * [分发 K8S 加密配置文件](#分发-k8s-加密配置文件)

* [创建审计策略配置](#创建审计策略配置)

  * [分发审计策略配置文件](#分发审计策略配置文件)

* [创建后续 metrics-server、kube-prometheus 证书](#创建后续-metrics-serverkube-prometheus-证书)

  * [分发 metrics-server、kube-prometheus 证书](#分发-metrics-serverkube-prometheus-证书)

* [创建 Service Account 证书](#创建-service-account-证书)

  * [分发 Service Account 证书](#分发-service-account-证书)

* [创建 kube-apiserver Systemd Service Unit](#创建-kube-apiserver-systemd-service-unit)

  * [启动 K8S API Server](#启动-k8s-api-server)

  * [验证 K8S API Server](#验证-k8s-api-server)

* [生成 kube-controller-manager 证书](#生成-kube-controller-manager-证书)

  * [分发 kube-controller-manager 证书](#分发-kube-controller-manager-证书)

  * [生成 kube-controller-manager kubeconfig](#生成-kube-controller-manager-kubeconfig)

  * [分发 kube-controller-manager kubeconfig](#分发-kube-controller-manager-kubeconfig)

* [创建 kube-controller-manager Systemd Service Unit](#创建-kube-controller-manager-systemd-service-unit)

  * [启动 kube-controller-manager](#启动-kube-controller-manager)

  * [验证 kube-controller-manager](#验证-kube-controller-manager)

  * [查看 kube-controller-manager Leader](#查看-kube-controller-manager-leader)

* [生成 kube-scheduler 证书](#生成-kube-scheduler-证书)

  * [分发 kube-scheduler 证书](#分发-kube-scheduler-证书)

  * [生成 kube-scheduler kubeconfig](#生成-kube-scheduler-kubeconfig)

  * [分发 kube-scheduler kubeconfig](#分发-kube-scheduler-kubeconfig)

  * [生成 kube-scheduler Config](#生成-kube-scheduler-config)

  * [创建 kube-scheduler Systemd Service Unit](#创建-kube-scheduler-systemd-service-unit)

  * [启动 kube-scheduler](#启动-kube-scheduler)

  * [验证 kube-scheduler](#验证-kube-scheduler)

  * [查看 kube-scheduler Leader](#查看-kube-scheduler-leader)

* [部署 CRI-O](#部署-cri-o)

  * [Short-Name 镜像默认地址](#short-name-镜像默认地址)

  * [启动 CRI-O](#启动-cri-o)

  * [查看 CRI 信息](#查看-cri-信息)

* [部署 containerd (可选，与 CRI-O 二选一即可)](#部署-containerd-可选与-cri-o-二选一即可)

  * [创建 Containerd 配置文件](#创建-containerd-配置文件)

  * [Containerd Systemd Service Unit](#containerd-systemd-service-unit)

  * [启动 Containerd](#启动-containerd)

  * [创建 crictl 配置文件](#创建-crictl-配置文件)

  * [查看 CRI 信息](#查看-cri-信息-1)

* [创建 Node Bootstrap Token](#创建-node-bootstrap-token)

  * [查看 Token](#查看-token)

  * [创建并分发 kubelet bootstrap kubeconfig 至各节点](#创建并分发-kubelet-bootstrap-kubeconfig-至各节点)

  * [创建 kubelet 配置文件](#创建-kubelet-配置文件)

  * [kubelet Systemd Service Unit](#kubelet-systemd-service-unit)

  * [授权 Kube API Server 访问 kubelet API](#授权-kube-api-server-访问-kubelet-api)

  * [自动审批节点 CSR 签发请求并生成节点证书](#自动审批节点-csr-签发请求并生成节点证书)

  * [启动 kubelet Service](#启动-kubelet-service)

* [审批 Kubelet 证书](#审批-kubelet-证书)

  * [测试 Kubelet 安全性](#测试-kubelet-安全性)

  * [创建测试 ServiceAccount 访问 Kubelet API](#创建测试-serviceaccount-访问-kubelet-api)

* [创建 Kube-Proxy 证书](#创建-kube-proxy-证书)

  * [分发 Kube-Porxy 证书](#分发-kube-porxy-证书)

  * [创建 Kube-Proxy kubeconfig](#创建-kube-proxy-kubeconfig)

  * [分发 Kube-Prxoy kubeconfig](#分发-kube-prxoy-kubeconfig)

  * [创建 Kube-Proxy 配置文件](#创建-kube-proxy-配置文件)

  * [Kube-Proxy systemd Service Unit](#kube-proxy-systemd-service-unit)

  * [启动 Kube-Prxoy](#启动-kube-prxoy)

  * [查看 Kube-Proxy IPVS 策略](#查看-kube-proxy-ipvs-策略)

* [Master 节点添加标签、污点](#master-节点添加标签污点)

* [部署 Calico CNI](#部署-calico-cni)

  * [Calico 终端程序](#calico-终端程序)

* [Node 节点添加标签](#node-节点添加标签)

* [测试集群](#测试集群)

* [部署 Helm](#部署-helm)

* [部署 CoreDNS](#部署-coredns)

  * [验证 CoreDNS](#验证-coredns)

* [创建集群只读账户](#创建集群只读账户)

  * [创建集群只读用户证书](#创建集群只读用户证书)

  * [创建集群只读用户 kubeconfig](#创建集群只读用户-kubeconfig)

* [部署 metrics-server](#部署-metrics-server)

* [部署 Ingress - Nginx](#部署-ingress---nginx)

  * [创建域名证书](#创建域名证书)

* [部署 Ceph-CSI 驱动](#部署-ceph-csi-驱动)

* [部署 nfs-subdir-external-provisioner](#部署-nfs-subdir-external-provisioner)

  * [配置 NFS Server 信息](#配置-nfs-server-信息)

  * [配置 Storage Class](#配置-storage-class)

  * [创建测试 PVC](#创建测试-pvc)

  * [创建持久化存储测试 Pod](#创建持久化存储测试-pod)

  * [清理](#清理)

* [部署 Dashboard](#部署-dashboard)

  * [创建 Dashboard 域名证书](#创建-dashboard-域名证书)

  * [安装 Dashboard](#安装-dashboard)

  * [创建 Dashboard 管理员账户](#创建-dashboard-管理员账户)

  * [创建 Dashboard 只读账户](#创建-dashboard-只读账户)

  * [测试 Dashboard 访问](#测试-dashboard-访问)

  * [创建 Dashboard Ingress](#创建-dashboard-ingress)

* [部署 kube-prometheus](#部署-kube-prometheus)

  * [测试 Prometheus 访问](#测试-prometheus-访问)

  * [创建 Prometheus Ingress](#创建-prometheus-ingress)

  * [测试 Grafana 访问](#测试-grafana-访问)

  * [创建 Grafana Ingress](#创建-grafana-ingress)

  * [测试 Alert Manager 访问](#测试-alert-manager-访问)

  * [创建 Alert Manager Ingress](#创建-alert-manager-ingress)

* [部署 E.F.K.](#部署-efk)

  * [创建命名空间](#创建命名空间)

  * [部署 Elastic Search 有状态副本](#部署-elastic-search-有状态副本)

  * [测试 Elastic Search API](#测试-elastic-search-api)

  * [部署 Kibana](#部署-kibana)

  * [创建 Kibana Ingress](#创建-kibana-ingress)

  * [创建 Fluentd ConfigMap](#创建-fluentd-configmap)

  * [部署 Fluentd DaemonSet](#部署-fluentd-daemonset)

  * [创建日志测试 Pod](#创建日志测试-pod)

  * [清理](#清理-1)

---

## 集群部署说明

* 基于 Debian 11 x86-64。同样适用于 Ubuntu 18.04/20.04 等 Debian 系发行版；

* 纯手工硬核方式（The Hard Way）搭建；

* Kubernetes 集群组件采用二进制方式部署运行；

* 节点加入集群使用“启动引导令牌” (Bootstrap Token) 方式；

* 默认 Container Runtime 使用 CRI-O，也包含 Containerd 部署方法；

* 集群资源组成为：
  
  * 1 HAProxy（Kube API Server、Ingress 外部流量负载均衡、kubectl 管理终端）
  
  * 3 Master 节点
  
  * 3 Node 节点

* etcd 集群复用 3 个 Master 节点，且同样使用二进制方式部署运行；

* Container Network 使用 Calico；

* Contianer Storage 使用 NFS-CSI 和 Ceph-CSI，并创建 NFS Storage Class；

* Kubernetes Dashboard；

* Nginx Ingress；

* E.F.K；

* kube-prometheus；

* metrics-server；

* Helm；

* 证书有效期默认 100 年；

---

### 组件版本

| 组件                            | 版本 / 分支 / 镜像 TAG |
| ------------------------------- | ---------------- |
| Kubernetes                      | 1.30.5           |
| CRI-O                           | 1.30.6           |
| cfssl                           | 1.6.2            |
| Containerd （可选）             | 1.7.23            |
| CNI-Plugins （可选）            | 1.5.1            |
| crictl （可选）                 | 1.30.0           |
| RunC （可选）                   | 1.1.15           |
| etcd                            | 3.5.16           |
| CoreDNS                         | 1.8.6            |
| Dashboard                       | 2.7.0            |
| kube-prometheus                 | 0.10             |
| Calico                          | 3.28.2           |
| calicoctl                       | 3.21.5           |
| Ingress-Nginx                   | 1.11.3            |
| Elastic Search                  | 7.16.2           |
| Kibana                          | 7.16.2           |
| Fluentd                         | latest           |
| Helm                            | 3.16.2           |
| Ceph-CSI                        | 3.12.2            |
| nfs-subdir-external-provisioner | master           |
| metrics-server                  | latest           |

### 网络规划

| 集群网络             | IP / CIDR / 域名           |
| -------------------- | -------------------------- |
| Pod CIDR             | 172.20.0.0/16              |
| Service Cluster CIDR | 10.254.0.0/16              |
| Cluster Endpoint     | 10.254.0.1                 |
| CoreDNS              | 10.254.0.53                |
| Cluster Domain       | k8s.tsd.org                |
| Dashboard            | k8s.tsd.org                |
| Prometheus           | k8s-prometheus.tsd.org     |
| Grafana              | k8s-grafana.tsd.org        |
| Alert Manager        | k8s-alertmanager.tsd.org   |
| Kibana               | k8s-kibana.tsd.org         |

### 主机说明

| 主机名            | IP           | 角色                | 操作系统  |
| ----------------- | ------------ | ------------------- | --------- |
| v0 / v0.tsd.org   | 172.31.31.70 | 外部负载均衡 / kubectl 终端 | Debian 11 |
| v1 / v1.tsd.org   | 172.31.31.71 | Master / etcd       | Debian 11 |
| v2 / v2.tsd.org   | 172.31.31.72 | Master / etcd       | Debian 11 |
| v3 / v3.tsd.org   | 172.31.31.73 | Master / etcd       | Debian 11 |
| v4 / v4.tsd.org   | 172.31.31.74 | Node / Ingress      | Debian 11 |
| v5 / v5.tsd.org   | 172.31.31.75 | Node / Ingress      | Debian 11 |
| v6 / v6.tsd.org   | 172.31.31.76 | Node / Ingress      | Debian 11 |

---

## 前置准备（此处步骤不做具体说明）

* 本文操作均以 root 身份执行；

* v0
  * 作为 K8S API Server 和 Ingress 外部流量负载均衡，在生产环境中应部署至少两台主机，并安装配置 KeepAlived 实现高可用；

  * [下载](https://github.com/cloudflare/cfssl/releases/tag/v1.6.2) CloudFlare cfssl 证书签发工具 (cfssl / cfssljson)；

* v1 - v6
  * /var 分区容量足够大；

  * 配置 /etc/hosts 或 DNS 服务，保证所有节点均可通过主机名、域名访问；

  * 配置 systemd-timesyncd 或 NTP 时间同步；

  * 禁用 iptables；

  * v0 能够以 root 身份通过 SSH 密钥直接登录其他主机；

---

## 设置时区

- v0 - v6

```shell
timedatectl set-timezone Asia/Shanghai
```

---

## 设置 PATH 环境变量

- v1 - v6

```shell
cat > /etc/profile.d/path.sh <<EOF
export PATH="/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/opt/kubernetes/client/bin:/opt/kubernetes/server/bin:/opt/kubernetes/node/bin:/opt/cni/bin:/opt/etcd"
EOF
```

* 如使用 Contianerd CRI，则配置以下 PATH:

```shell
cat > /etc/profile.d/path.sh <<EOF
export PATH="/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/opt/kubernetes/client/bin:/opt/kubernetes/server/bin:/opt/kubernetes/node/bin:/opt/cni/bin:/opt/runc/sbin:/opt/containerd/bin:/opt/crictl/bin:/opt/etcd"
EOF
```

```shell
source /etc/profile
```

---

## 安装所需软件包

* v1 - v6

```shell
apt update && apt upgrade -y
```

```shell
apt install -y \
  bash-completion \
  bridge-utils \
  wget \
  socat \
  jq \
  git \
  curl \
  rsync \
  conntrack \
  ipset \
  ipvsadm \
  jq \
  ebtables \
  sysstat \
  libltdl7 \
  lvm2 \
  iptables \
  lsb-release \
  libseccomp2 \
  scdaemon \
  gnupg \
  gnupg2 \
  gnupg-agent \
  nfs-client \
  ceph-common \
  glusterfs-client \
  ca-certificates \
  apt-transport-https \
  software-properties-common
```

---

## 禁用 SWAP

```shell
sed -i '/swap/ s/^\(.*\)$/#\1/g' /etc/fstab
```

---

## 加载内核模块

* v1 - v6

```
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack
modprobe -- overlay
modprobe -- br_netfilter
modprobe -- rbd
```

```shell
cat >> /etc/modules <<EOF

overlay
br_netfilter
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
rbd
EOF
```

---

## 设置内核参数

* v0 - v6
* 务必根据实际情况设置内核参数；

```ini
cat >> /etc/sysctl.conf <<EOF

### K8S

net.ipv4.ip_forward = 1

net.ipv4.neigh.default.gc_thresh1 = 1024
net.ipv4.neigh.default.gc_thresh2 = 2048
net.ipv4.neigh.default.gc_thresh3 = 4096
net.ipv6.neigh.default.gc_thresh1 = 1024
net.ipv6.neigh.default.gc_thresh2 = 2048
net.ipv6.neigh.default.gc_thresh3 = 4096
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_retries1 = 3
net.ipv4.tcp_retries2 = 10
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_no_metrics_save = 0
net.ipv4.tcp_max_syn_backlog = 1024
net.ipv4.tcp_fin_timeout = 30
net.ipv4.ip_local_port_range = 10240 60999
net.core.somaxconn = 8192
net.core.optmem_max = 20480
net.core.netdev_max_backlog = 3000
net.netfilter.nf_conntrack_max = 2310720
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
vm.dirty_background_ratio = 10
vm.swappiness = 0
vm.overcommit_memory = 1
vm.panic_on_oom = 0
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 1048576
fs.file-max = 52706963
fs.nr_open = 52706963
EOF
```

```shell
sysctl -p
```

---

## 设置 PAM limits

* v0 - v6

```shell
vi /etc/security/limits.conf
```

```
*    soft nproc  131072
*    hard nproc  131072
*    soft nofile 131072
*    hard nofile 131072
```

---                   

## （可选） 降级 Cgroups 版本

* 如使用 Containerd CRI 可能需要将 Debian 11 默认使用的 Cgroups v2 降级至 v1；

* 使用 CRI-O CRI 无需切换 Cgroups 版本；
 
```shell
vi /etc/default/grub
 
GRUB_CMDLINE_LINUX_DEFAULT="quiet systemd.unified_cgroup_hierarchy=0 cgroup_enable=memory swapaccount=1"
```
 
```shell               
update-grub
```

---

## 重启 v1 - v6

```shell
reboot
```

---

## 安装配置外部负载均衡 HAProxy

* v0

* 本文档只部署 1 个 HAProxy 实例。生产环境中应至少部署 2 个 HAProxy 并安装 KeepAlived 进行高可用配置。

* HAProxy 管理后台 URL 默认为 `http://172.31.31.70:9090/ha-status` ，如有需要可修改 URI 和端口号；

* HAProxy 管理后台默认账户为 `admin / admin-inanu`，如有需要自行更改；

```shell
apt install -y haproxy
```

```shell
mv /etc/haproxy/haproxy.cfg{,.ori}
```

```shell
cat > /etc/haproxy/haproxy.cfg <<EOF
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    ca-base /etc/ssl/certs
    crt-base /etc/ssl/private

        ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
        ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
        ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    log     global
    mode    tcp
    option  httplog
    option  dontlognull
    timeout connect 10s
    timeout client  30s
    timeout server  30s


frontend K8S-API-Server
    bind 0.0.0.0:6443
    option tcplog
    mode tcp
    default_backend K8S-API-Server

frontend K8S-Ingress-HTTP
    bind 0.0.0.0:80
    option tcplog
    mode tcp
    default_backend K8S-Ingress-HTTP

frontend K8S-Ingress-HTTPS
    bind 0.0.0.0:443
    option tcplog
    mode tcp
    default_backend K8S-Ingress-HTTPS

frontend HA-Admin
    bind 0.0.0.0:9090
    mode http
    timeout client 5000
    stats uri /ha-status
    stats realm HAProxy\ Statistics
    stats auth admin:admin-inanu  ### CHANGE THIS!

    #This allows you to take down and bring up back end servers.
    #This will produce an error on older versions of HAProxy.
    stats admin if TRUE

backend K8S-API-Server
    mode tcp
    balance roundrobin
    option tcp-check
    server api-server-1 172.31.31.71:6443 check fall 3 rise 2 maxconn 2000
    server api-server-2 172.31.31.72:6443 check fall 3 rise 2 maxconn 2000
    server api-server-3 172.31.31.73:6443 check fall 3 rise 2 maxconn 2000

backend K8S-Ingress-HTTP
    mode tcp
    balance roundrobin
    option tcp-check
    server ingress-1 172.31.31.74:80 check fall 3 rise 2 maxconn 2000
    server ingress-2 172.31.31.75:80 check fall 3 rise 2 maxconn 2000
    server ingress-3 172.31.31.76:80 check fall 3 rise 2 maxconn 2000

backend K8S-Ingress-HTTPS
    mode tcp
    balance roundrobin
    option tcp-check
    server ingress-1 172.31.31.74:443 check fall 3 rise 2 maxconn 2000
    server ingress-2 172.31.31.75:443 check fall 3 rise 2 maxconn 2000
    server ingress-3 172.31.31.76:443 check fall 3 rise 2 maxconn 2000
EOF
```

```shell
systemctl enable --now haproxy.service
```

浏览器打开 `http://172.31.31.70:9090/ha-status`。此时所有 backend 均不可用，因为尚未部署 Kube API Server 和 Nginx Ingress。

---

## 分发 K8S 二进制组件

### 分发至所有节点

* v0
* [下载](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.27.md)

```shell
cd /usr/local/src
```

```shell
tar xzvf kubernetes-client-linux-amd64.tar.gz
```

```shell
tar xzvf kubernetes-node-linux-amd64.tar.gz
```

```shell
tar xzvf kubernetes-server-linux-amd64.tar.gz
```

```shell
chown -R root.root ./kubernetes
```

```shell
mv kubernetes kubernetes-1.30.5
```

```shell
# K8S 组件放置于 /opt/app/kubernetes-1.30.5 并软链至 /opt/kubernetes
for I in {1..6};do
    ssh root@v${I} "mkdir -p /opt/app"
    rsync -avr /usr/local/src/kubernetes-1.30.5 root@v${I}:/opt/app/
    ssh root@v${I} "ln -snf  /opt/app/kubernetes-1.30.5 /opt/kubernetes"
done
```

### 复制 kubectl kubeadm 至 v0 集群终端主机

* v0

```shell
cp /usr/local/src/kubernetes-1.30.5/client/bin/kubectl /usr/local/bin/
```

```shell
cp /usr/local/src/kubernetes-1.30.5/node/bin/kubeadm /usr/local/bin/
```

```shell
chmod +x /usr/local/bin/kube* && chown root:root /usr/local/bin/kube*
```

### 配置 kubectl Bash 自动补全

* v0 - v6

```shell
cat >> /root/.bashrc <<EOF

# kubectl autocompletion

source <(/opt/kubernetes/client/bin/kubectl completion bash)
EOF
```

```shell
kubectl completion bash > /etc/bash_completion.d/kubectl
```

```shell
source /root/.bashrc
```

---

## 生成集群 CA 证书

- v0

```shell
mkdir -p /etc/kubernetes/pki
```

```shell
cd /etc/kubernetes/pki
```

```json
cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "876000h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "876000h"
      }
    }
  }
}
EOF
```

```json
cat > ca-csr.json <<EOF
{
  "CN": "kubernetes-ca",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "Nanu-Network",
      "OU": "K8S"
    }
  ],
  "ca": {
    "expiry": "876000h"
 }
}
EOF
```

```shell
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
```

### 分发 CA 证书

```shell
for I in {1..6};do
    ssh root@v${I} "mkdir -p /etc/kubernetes/cert"
    rsync -avr ./ca*.pem root@v${I}:/etc/kubernetes/cert/
done
```

---

## 生成 Cluster-Admin 证书

* v0
  
  K8S 使用证书中的 `O` (Organization) 字段作为 K8S 用户组名称认证。`system:masters` 为内置管理员组。

```json
cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "system:masters",
      "OU": "K8S"
    }
  ]
}
EOF
```

```shell
cfssl gencert -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes admin-csr.json | cfssljson -bare admin
```

### 分发 Cluster-Admin 证书（可选，不建议）

```shell
for I in {1..6};do
    rsync -avr ./admin*.pem root@v${I}:/root/
    ssh root@v${I} "chmod 600 /root/admin*.pem"
done
```

---

## 生成 Cluster-Admin kubeconfig

* v0

```shell
kubectl config set-cluster kubernetes \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://172.31.31.70:6443 \
  --kubeconfig=admin.kubeconfig
```

```shell
kubectl config set-credentials admin \
  --client-certificate=admin.pem \
  --client-key=admin-key.pem \
  --embed-certs=true \
  --kubeconfig=admin.kubeconfig
```

```shell
kubectl config set-context kubernetes \
  --cluster=kubernetes \
  --user=admin \
  --kubeconfig=admin.kubeconfig
```

```shell
kubectl config use-context kubernetes --kubeconfig=admin.kubeconfig
```

### 复制 admin kubeconfig 至 v0 kubectl 配置文件目录

```shell
mkdir -p mkdir -p /root/.kube
```

```shell
cp ./admin.kubeconfig /root/.kube/config
```

```shell
chmod 700 /root/.kube && chmod 600 /root/.kube/config
```

### 分发 admin kubeconfig 至其他节点（可选）

* 上一步 v0 节点已能够通过 kubeconfig 认证访问 K8S API Server

```shell
for I in {1..6};do
    ssh root@v${I} "mkdir -p /root/.kube"
    scp ./admin.kubeconfig root@v${I}:/root/.kube/config
    ssh root@v${I} "chmod 700 /root/.kube && chmod 600 /root/.kube/config"
done
```

---

## 部署 etcd Cluster

### 下载解压

* v0
* [下载](https://github.com/etcd-io/etcd/releases/tag/v3.5.16)
* etcd data 目录为：`/data/etcd/data`；
* etcd wal 目录为：`/data/etcd/wal`；

```shell
cd /usr/local/src
```

```shell
tar xzvf etcd-v3.5.16-linux-amd64.tar.gz
```

### 分发 etcd 程序至 Master 节点

```shell
for I in {1..3};do
    rsync -avr /usr/local/src/etcd-v3.5.16-linux-amd64 root@v${I}:/opt/app/
    ssh root@v${I} "chown -R root.root /opt/app/etcd-v3.5.16-linux-amd64; ln -snf /opt/app/etcd-v3.5.16-linux-amd64 /opt/etcd"
done
```

### 创建 etcd 证书

```json
cat > etcd-csr.json <<EOF
{
  "CN": "etcd",
  "hosts": [
    "127.0.0.1",
    "172.31.31.71",
    "172.31.31.72",
    "172.31.31.73",
    "v1",
    "v2",
    "v3",
    "v1.tsd.org",
    "v2.tsd.org",
    "v3.tsd.org"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "Nanu-Network",
      "OU": "K8S"
    }
  ]
}
EOF
```

```shell
cfssl gencert -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -profile=kubernetes etcd-csr.json | cfssljson -bare etcd
```

### 分发 etcd 证书至 Master 节点

```shell
for I in {1..3};do
    ssh root@v${I} "mkdir -p /etc/etcd/cert"
    ssh root@v${I} "mkdir -p /data/etcd/{data,wal}"
    rsync -avr etcd*.pem root@v${I}:/etc/etcd/cert/
done
```

### 创建 etcd Systemd Service Unit

* v1 - v3
  * `--name=`

  * `--listen-peer-urls=`

  * `--initial-advertise-peer-urls=`

  * `--listen-client-urls=`

  * `--advertise-client-urls=`

```ini
cat > /etc/systemd/system/etcd.service <<EOF
[Unit]
Description=etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
Type=notify
WorkingDirectory=/data/etcd/data
ExecStart=/opt/etcd/etcd \\
  --name=v1 \\
  --data-dir=/data/etcd/data \\
  --wal-dir=/data/etcd/wal \\
  --snapshot-count=5000 \\
  --cert-file=/etc/etcd/cert/etcd.pem \\
  --key-file=/etc/etcd/cert/etcd-key.pem \\
  --trusted-ca-file=/etc/kubernetes/cert/ca.pem \\
  --peer-cert-file=/etc/etcd/cert/etcd.pem \\
  --peer-key-file=/etc/etcd/cert/etcd-key.pem \\
  --peer-trusted-ca-file=/etc/kubernetes/cert/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --listen-peer-urls=https://172.31.31.71:2380 \\
  --initial-advertise-peer-urls=https://172.31.31.71:2380 \\
  --listen-client-urls=https://172.31.31.71:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls=https://172.31.31.71:2379 \\
  --initial-cluster-token=etcd-cluster-0 \\
  --initial-cluster="v1=https://172.31.31.71:2380,v2=https://172.31.31.72:2380,v3=https://172.31.31.73:2380" \\
  --initial-cluster-state=new \\
  --auto-compaction-mode=periodic \\
  --auto-compaction-retention=1 \\
  --max-snapshots=5 \\
  --max-wals=5 \\
  --max-txn-ops=512 \\
  --max-request-bytes=33554432 \\
  --quota-backend-bytes=6442450944 \\
  --heartbeat-interval=250 \\
  --election-timeout=2000
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
```

### 启动 etcd

* v0

```shell
for I in {1..3};do
    ssh root@v${I} "systemctl daemon-reload && systemctl enable --now etcd.service"
done
```

### 检查 etcd Cluster 工作状态

* v1 or v2 or v3

```shell
for I in {1..3};do
    etcdctl \
    --endpoints=https://v${I}:2379 \
    --cacert=/etc/kubernetes/cert/ca.pem \
    --cert=/etc/etcd/cert/etcd.pem \
    --key=/etc/etcd/cert/etcd-key.pem endpoint health
done
```

```shell
etcdctl \
  -w table --cacert=/etc/kubernetes/cert/ca.pem \
  --cert=/etc/etcd/cert/etcd.pem \
  --key=/etc/etcd/cert/etcd-key.pem \
  --endpoints=https://172.31.31.71:2379,https://172.31.31.72:2379,https://172.31.31.73:2379 endpoint status
```

### 创建 etcd 自动备份

* v1 or v2 or v3

```shell
cat > /usr/local/bin/backup_etcd.sh <<EOF
#!/bin/bash

BACKUP_DIR="/data/backup/etcd"
BACKUP_FILE="etcd-snapshot-$(date +%Y%m%d-%H%M).db"
ENDPOINTS="http://127.0.0.1:2379"

#CACERT="/etc/ssl/etcd/ssl/ca.pem"
#CERT="/etc/ssl/etcd/ssl/node-master1.pem"
#KEY="/etc/ssl/etcd/ssl/node-master1-key.pem"


if [ ! -d ${BACKUP_DIR} ];then
    mkdir -p ${BACKUP_DIR}
fi

#etcdctl \
#  --cacert="${CACERT}" --cert="${CERT}" --key="${KEY}" \
#  --endpoints="${ENDPOINTS}" \
#  snapshot save ${BACKUP_DIR}/${BACKUP_FILE}

/opt/etcd/etcdctl --endpoints="${ENDPOINTS}" \
  snapshot save ${BACKUP_DIR}/${BACKUP_FILE}

cd ${BACKUP_DIR}
tar czf ./${BACKUP_FILE}.tar.gz ./${BACKUP_FILE}
rm -f ./${BACKUP_FILE}

# Keep 7 days backup
find ${BACKUP_DIR}/ -name "*.gz" -mtime +7 -exec rm -f {} \;
EOF
```

```shell
chmod +x /usr/local/bin/backup_etcd.sh
```

```shell
crontab -e

# Backup etcd
0 4 * * * /usr/local/bin/backup_etcd.sh > /dev/null 2>&1
```

---

## 生成 K8S 证书

* v0

```json
cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes-master",
  "hosts": [
    "10.254.0.1",
    "127.0.0.1",
    "172.31.31.70",
    "172.31.31.71",
    "172.31.31.72",
    "172.31.31.73",
    "v0",
    "v1",
    "v2",
    "v3",
    "v0.tsd.org",
    "v1.tsd.org",
    "v2.tsd.org",
    "v3.tsd.org",
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local.",
    "k8s.tsd.org."
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "Nanu-Network",
      "OU": "K8S"
    }
  ]
}
EOF
```

```shell
cfssl gencert -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes kubernetes-csr.json | cfssljson -bare kubernetes
```

### 分发 K8S 证书

```shell
for I in {1..3};do
    ssh root@v${I} "mkdir -p /etc/kubernetes/cert"
    rsync -avr kubernetes*.pem root@v${I}:/etc/kubernetes/cert/
done
```

---

## 创建 K8S 加密配置

```shell
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
```

```yaml
cat > encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF
```

### 分发 K8S 加密配置文件

```shell
for I in {1..3};do
    rsync -avr encryption-config.yaml root@v${I}:/etc/kubernetes/
done
```

---

## 创建审计策略配置

* v0

```yaml
cat > audit-policy.yaml <<EOF
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # The following requests were manually identified as high-volume and low-risk, so drop them.
  - level: None
    resources:
      - group: ""
        resources:
          - endpoints
          - services
          - services/status
    users:
      - 'system:kube-proxy'
    verbs:
      - watch

  - level: None
    resources:
      - group: ""
        resources:
          - nodes
          - nodes/status
    userGroups:
      - 'system:nodes'
    verbs:
      - get

  - level: None
    namespaces:
      - kube-system
    resources:
      - group: ""
        resources:
          - endpoints
    users:
      - 'system:kube-controller-manager'
      - 'system:kube-scheduler'
      - 'system:serviceaccount:kube-system:endpoint-controller'
    verbs:
      - get
      - update

  - level: None
    resources:
      - group: ""
        resources:
          - namespaces
          - namespaces/status
          - namespaces/finalize
    users:
      - 'system:apiserver'
    verbs:
      - get

  # Don't log HPA fetching metrics.
  - level: None
    resources:
      - group: metrics.k8s.io
    users:
      - 'system:kube-controller-manager'
    verbs:
      - get
      - list

  # Don't log these read-only URLs.
  - level: None
    nonResourceURLs:
      - '/healthz*'
      - /version
      - '/swagger*'

  # Don't log events requests.
  - level: None
    resources:
      - group: ""
        resources:
          - events

  # node and pod status calls from nodes are high-volume and can be large, don't log responses
  # for expected updates from nodes
  - level: Request
    omitStages:
      - RequestReceived
    resources:
      - group: ""
        resources:
          - nodes/status
          - pods/status
    users:
      - kubelet
      - 'system:node-problem-detector'
      - 'system:serviceaccount:kube-system:node-problem-detector'
    verbs:
      - update
      - patch

  - level: Request
    omitStages:
      - RequestReceived
    resources:
      - group: ""
        resources:
          - nodes/status
          - pods/status
    userGroups:
      - 'system:nodes'
    verbs:
      - update
      - patch

  # deletecollection calls can be large, don't log responses for expected namespace deletions
  - level: Request
    omitStages:
      - RequestReceived
    users:
      - 'system:serviceaccount:kube-system:namespace-controller'
    verbs:
      - deletecollection

  # Secrets, ConfigMaps, and TokenReviews can contain sensitive & binary data,
  # so only log at the Metadata level.
  - level: Metadata
    omitStages:
      - RequestReceived
    resources:
      - group: ""
        resources:
          - secrets
          - configmaps
      - group: authentication.k8s.io
        resources:
          - tokenreviews
  # Get repsonses can be large; skip them.
  - level: Request
    omitStages:
      - RequestReceived
    resources:
      - group: ""
      - group: admissionregistration.k8s.io
      - group: apiextensions.k8s.io
      - group: apiregistration.k8s.io
      - group: apps
      - group: authentication.k8s.io
      - group: authorization.k8s.io
      - group: autoscaling
      - group: batch
      - group: certificates.k8s.io
      - group: extensions
      - group: metrics.k8s.io
      - group: networking.k8s.io
      - group: policy
      - group: rbac.authorization.k8s.io
      - group: scheduling.k8s.io
      - group: settings.k8s.io
      - group: storage.k8s.io
    verbs:
      - get
      - list
      - watch

  # Default level for known APIs
  - level: RequestResponse
    omitStages:
      - RequestReceived
    resources:
      - group: ""
      - group: admissionregistration.k8s.io
      - group: apiextensions.k8s.io
      - group: apiregistration.k8s.io
      - group: apps
      - group: authentication.k8s.io
      - group: authorization.k8s.io
      - group: autoscaling
      - group: batch
      - group: certificates.k8s.io
      - group: extensions
      - group: metrics.k8s.io
      - group: networking.k8s.io
      - group: policy
      - group: rbac.authorization.k8s.io
      - group: scheduling.k8s.io
      - group: settings.k8s.io
      - group: storage.k8s.io

  # Default level for all other requests.
  - level: Metadata
    omitStages:
      - RequestReceived
EOF
```

### 分发审计策略配置文件

```shell
for I in {1..3};do
    rsync -avr audit-policy.yaml root@v${I}:/etc/kubernetes/
done
```

---

## 创建后续 metrics-server、kube-prometheus 证书

* v0

```json
cat > proxy-client-csr.json <<EOF
{
  "CN": "aggregator",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "Nanu-Network",
      "OU": "K8S"
    }
  ]
}
EOF
```

```shell
cfssl gencert -ca=ca.pem \
  -ca-key=ca-key.pem  \
  -config=ca-config.json  \
  -profile=kubernetes proxy-client-csr.json | cfssljson -bare proxy-client
```

### 分发 metrics-server、kube-prometheus 证书

```shell
for I in {1..3};do
    rsync -avr proxy-client*.pem root@v${I}:/etc/kubernetes/cert/
done
```

---

## 创建 Service Account 证书

* v0

```json
cat > service-account-csr.json <<EOF
{
  "CN": "service-accounts",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "L": "Beijing",
      "O": "Nanu-Network",
      "OU": "K8S"
    }
  ]
}
EOF
```

```shell
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  service-account-csr.json | cfssljson -bare service-account
```

### 分发 Service Account 证书

```shell
for I in {1..3};do
    rsync -avr service-account*.pem root@v${I}:/etc/kubernetes/cert/
done
```

---

## 创建 kube-apiserver Systemd Service Unit

* v0
* Kube API Server 工作目录：/var/lib/kube-apiserver

```shell
for I in {1..3};do
    ssh root@v${I} "mkdir -p /var/lib/kube-apiserver"
done
```

* v1 - v3
  * `--apiserver-count` （如 Master  节点 > 3 请修改）；

  * `--etcd-servers` （如 etcd 节点与文档不一致请修改）；

  * `--service-account-issuer` （K8S API Server 负载均衡地址)；

  * `--service-cluster-ip-range` (Cluster CIDR)；

```ini
cat > /etc/systemd/system/kube-apiserver.service <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
WorkingDirectory=/var/lib/kube-apiserver
ExecStart=/opt/kubernetes/server/bin/kube-apiserver \\
  --advertise-address=0.0.0.0 \\
  --allow-privileged=true \\
  --anonymous-auth=false \\
  --apiserver-count=3 \\
  --audit-log-compress \\
  --audit-log-format="json" \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=50 \\
  --audit-log-maxsize=10 \\
  --audit-log-mode="blocking" \\
  --audit-log-path="/var/lib/kube-apiserver/audit.log" \\
  --audit-log-truncate-enabled \\
  --audit-policy-file="/etc/kubernetes/audit-policy.yaml" \\
  --authorization-mode="Node,RBAC" \\
  --bind-address="0.0.0.0" \\
  --client-ca-file="/etc/kubernetes/cert/ca.pem" \\
  --default-not-ready-toleration-seconds=300 \\
  --default-unreachable-toleration-seconds=300 \\
  --default-watch-cache-size=200 \\
  --delete-collection-workers=4 \\
  --enable-admission-plugins=NodeRestriction \\
  --enable-aggregator-routing \\
  --enable-bootstrap-token-auth \\
  --encryption-provider-config="/etc/kubernetes/encryption-config.yaml" \\
  --etcd-cafile="/etc/kubernetes/cert/ca.pem" \\
  --etcd-certfile="/etc/kubernetes/cert/kubernetes.pem" \\
  --etcd-keyfile="/etc/kubernetes/cert/kubernetes-key.pem" \\
  --etcd-servers="https://172.31.31.71:2379,https://172.31.31.72:2379,https://172.31.31.73:2379" \\
  --event-ttl=168h \\
  --goaway-chance=.001 \\
  --http2-max-streams-per-connection=42 \\
  --kubelet-certificate-authority="/etc/kubernetes/cert/ca.pem" \\
  --kubelet-client-certificate="/etc/kubernetes/cert/kubernetes.pem" \\
  --kubelet-client-key="/etc/kubernetes/cert/kubernetes-key.pem" \\
  --kubelet-timeout=10s \\
  --lease-reuse-duration-seconds=120 \\
  --max-mutating-requests-inflight=2000 \\
  --max-requests-inflight=4000 \\
  --profiling \\
  --proxy-client-cert-file="/etc/kubernetes/cert/proxy-client.pem" \\
  --proxy-client-key-file="/etc/kubernetes/cert/proxy-client-key.pem" \\
  --requestheader-allowed-names="aggregator" \\
  --requestheader-client-ca-file="/etc/kubernetes/cert/ca.pem" \\
  --requestheader-extra-headers-prefix="X-Remote-Extra-" \\
  --requestheader-group-headers="X-Remote-Group" \\
  --requestheader-username-headers="X-Remote-User" \\
  --runtime-config='api/all=true' \\
  --secure-port=6443 \\
  --service-account-extend-token-expiration=true \\
  --service-account-issuer="https://172.31.31.70:6443" \\
  --service-account-key-file="/etc/kubernetes/cert/service-account.pem" \\
  --service-account-signing-key-file="/etc/kubernetes/cert/service-account-key.pem" \\
  --service-cluster-ip-range="10.254.0.0/16" \\
  --service-node-port-range=10001-65535 \\
  --tls-cert-file="/etc/kubernetes/cert/kubernetes.pem" \\
  --tls-private-key-file="/etc/kubernetes/cert/kubernetes-key.pem" \\
  --v=2
Restart=on-failure
RestartSec=10
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
```

### 启动 K8S API Server

* v0

```shell
for I in {1..3};do
    ssh root@v${I} "systemctl daemon-reload && systemctl enable --now kube-apiserver.service"
done
```

### 验证 K8S API Server

* v0

```shell
kubectl cluster-info
```

```shell
kubectl cluster-info dump
```

```shell
kubectl get all -A
```

---

## 生成 kube-controller-manager 证书

* v0

```yaml
cat > kube-controller-manager-csr.json <<EOF
{
    "CN": "system:kube-controller-manager",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
  "hosts": [
    "127.0.0.1",
    "172.31.31.71",
    "172.31.31.72",
    "172.31.31.73",
    "v1",
    "v2",
    "v3",
    "v1.tsd.org",
    "v2.tsd.org",
    "v3.tsd.org"
    ],
    "names": [
      {
        "C": "CN",
        "ST": "Beijing",
        "L": "Beijing",
        "O": "system:kube-controller-manager",
        "OU": "K8S"
      }
    ]
}
EOF
```

```shell
cfssl gencert -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager
```

### 分发 kube-controller-manager 证书

* v0

```shell
for I in {1..3};do
    rsync -avr kube-controller-manager*.pem root@v${I}:/etc/kubernetes/cert/
done
```

### 生成 kube-controller-manager kubeconfig

* v0

```shell
kubectl config set-cluster kubernetes \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server="https://172.31.31.70:6443" \
  --kubeconfig=kube-controller-manager.kubeconfig
```

```shell
kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=kube-controller-manager.pem \
  --client-key=kube-controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-controller-manager.kubeconfig
```

```shell
kubectl config set-context system:kube-controller-manager \
  --cluster=kubernetes \
  --user=system:kube-controller-manager \
  --kubeconfig=kube-controller-manager.kubeconfig
```

```shell
kubectl config use-context system:kube-controller-manager --kubeconfig=kube-controller-manager.kubeconfig
```

### 分发 kube-controller-manager kubeconfig

* v0

```shell
for I in {1..3};do
    rsync -avr kube-controller-manager.kubeconfig root@v${I}:/etc/kubernetes/
done
```

---

## 创建 kube-controller-manager Systemd Service Unit

* v0
* kube-controller-manager 工作目录：/var/lib/kube-controller-manager

```shell
for I in {1..3};do
    ssh root@v${I} "mkdir -p /var/lib/kube-controller-manager"
done
```

* v1 - v3

```ini
cat > /etc/systemd/system/kube-controller-manager.service <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
WorkingDirectory=/var/lib/kube-controller-manager
ExecStart=/opt/kubernetes/server/bin/kube-controller-manager \\
 --authentication-kubeconfig="/etc/kubernetes/kube-controller-manager.kubeconfig" \\
 --authorization-kubeconfig="/etc/kubernetes/kube-controller-manager.kubeconfig" \\
 --bind-address=0.0.0.0 \\
 --client-ca-file="/etc/kubernetes/cert/ca.pem" \\
 --cluster-name="kubernetes" \\
 --cluster-signing-cert-file="/etc/kubernetes/cert/ca.pem" \\
 --cluster-signing-duration=876000h \\
 --cluster-signing-key-file="/etc/kubernetes/cert/ca-key.pem" \\
 --concurrent-deployment-syncs=10 \\
 --concurrent-endpoint-syncs=10 \\
 --concurrent-gc-syncs=30 \\
 --concurrent-namespace-syncs=10 \\
 --concurrent-rc-syncs=10 \\
 --concurrent-replicaset-syncs=10 \\
 --concurrent-resource-quota-syncs=10 \\
 --concurrent-service-endpoint-syncs=10 \\
 --concurrent-service-syncs=2 \\
 --concurrent-serviceaccount-token-syncs=10 \\
 --concurrent-statefulset-syncs=10 \\
 --concurrent-ttl-after-finished-syncs=10 \\
 --contention-profiling \\
 --controllers=*,bootstrapsigner,tokencleaner \\
 --horizontal-pod-autoscaler-sync-period=10s \\
 --http2-max-streams-per-connection=42 \\
 --kube-api-burst=2000 \\
 --kube-api-qps=1000 \\
 --kubeconfig="/etc/kubernetes/kube-controller-manager.kubeconfig" \\
 --leader-elect \\
 --mirroring-concurrent-service-endpoint-syncs=10 \\
 --profiling \\
 --requestheader-allowed-names="aggregator" \\
 --requestheader-client-ca-file="/etc/kubernetes/cert/ca.pem" \\
 --requestheader-extra-headers-prefix="X-Remote-Exra-" \\
 --requestheader-group-headers="X-Remote-Group" \\
 --requestheader-username-headers="X-Remote-User" \\
 --root-ca-file="/etc/kubernetes/cert/ca.pem" \\
 --secure-port=10252 \\
 --service-account-private-key-file="/etc/kubernetes/cert/service-account-key.pem" \\
 --service-cluster-ip-range="10.254.0.0/16" \\
 --tls-cert-file="/etc/kubernetes/cert/kube-controller-manager.pem" \\
 --tls-private-key-file="/etc/kubernetes/cert/kube-controller-manager-key.pem" \\
 --use-service-account-credentials=true \\
 --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### 启动 kube-controller-manager

* v0

```shell
for I in {1..3};do
    ssh root@v${I} "systemctl daemon-reload && systemctl enable --now kube-controller-manager"
done
```

### 验证 kube-controller-manager

```shell
curl -s --cacert ca.pem --cert admin.pem --key admin-key.pem https://172.31.31.71:10252/metrics
```

```shell
curl -s --cacert ca.pem --cert admin.pem --key admin-key.pem https://172.31.31.72:10252/metrics
```

```shell
curl -s --cacert ca.pem --cert admin.pem --key admin-key.pem https://172.31.31.73:10252/metrics
```

### 查看 kube-controller-manager Leader

```shell
journalctl -u kube-controller-manager.service --no-pager | grep -i 'became leader'
```

---

## 生成 kube-scheduler 证书

* v0

```json
cat > kube-scheduler-csr.json <<EOF
{
    "CN": "system:kube-scheduler",
    "hosts": [
    "127.0.0.1",
    "172.31.31.71",
    "172.31.31.72",
    "172.31.31.73",
    "v1",
    "v2",
    "v3",
    "v1.tsd.org",
    "v2.tsd.org",
    "v3.tsd.org"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
      {
        "C": "CN",
        "ST": "Beijing",
        "L": "Beijing",
        "O": "system:kube-scheduler",
        "OU": "K8S"
      }
    ]
}
EOF
```

```shell
cfssl gencert -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes kube-scheduler-csr.json | cfssljson -bare kube-scheduler
```

### 分发 kube-scheduler 证书

```shell
for I in {1..3};do
    rsync -avr kube-scheduler*.pem root@v${I}:/etc/kubernetes/cert/
done
```

### 生成 kube-scheduler kubeconfig

```shell
kubectl config set-cluster kubernetes \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server="https://172.31.31.70:6443" \
  --kubeconfig=kube-scheduler.kubeconfig
```

```shell
kubectl config set-credentials system:kube-scheduler \
  --client-certificate=kube-scheduler.pem \
  --client-key=kube-scheduler-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-scheduler.kubeconfig
```

```shell
kubectl config set-context system:kube-scheduler \
  --cluster=kubernetes \
  --user=system:kube-scheduler \
  --kubeconfig=kube-scheduler.kubeconfig
```

```shell
kubectl config use-context system:kube-scheduler --kubeconfig=kube-scheduler.kubeconfig
```

### 分发 kube-scheduler kubeconfig

```shell
for I in {1..3};do
    rsync -avr kube-scheduler.kubeconfig root@v${I}:/etc/kubernetes/
done
```

### 生成 kube-scheduler Config

* v1 - v3

```yaml
cat > /etc/kubernetes/kube-scheduler.yaml <<EOF
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
clientConnection:
  burst: 200
  kubeconfig: "/etc/kubernetes/kube-scheduler.kubeconfig"
  qps: 100
enableContentionProfiling: false
enableProfiling: true
leaderElection:
  leaderElect: true
EOF
```

### 创建 kube-scheduler Systemd Service Unit

* v0
* kube-scheduler 工作目录：/var/lib/kube-scheduler

```shell
for I in {1..3};do
    ssh root@v${I} "mkdir -p /var/lib/kube-scheduler"
done
```

* v1 - v3

```ini
cat > /etc/systemd/system/kube-scheduler.service <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
WorkingDirectory=/var/lib/kube-scheduler
ExecStart=/opt/kubernetes/server/bin/kube-scheduler \\
 --authentication-kubeconfig="/etc/kubernetes/kube-scheduler.kubeconfig" \\
 --authorization-kubeconfig="/etc/kubernetes/kube-scheduler.kubeconfig" \\
 --bind-address=0.0.0.0 \\
 --client-ca-file="/etc/kubernetes/cert/ca.pem" \\
 --config="/etc/kubernetes/kube-scheduler.yaml" \\
 --http2-max-streams-per-connection=42 \\
 --leader-elect=true \\
 --requestheader-allowed-names="" \\
 --requestheader-client-ca-file="/etc/kubernetes/cert/ca.pem" \\
 --requestheader-extra-headers-prefix="X-Remote-Extra-" \\
 --requestheader-group-headers="X-Remote-Group" \\
 --requestheader-username-headers="X-Remote-User" \\
 --secure-port=10259 \\
 --tls-cert-file="/etc/kubernetes/cert/kube-scheduler.pem" \\
 --tls-private-key-file="/etc/kubernetes/cert/kube-scheduler-key.pem" \\
 --v=2
Restart=always
RestartSec=5
StartLimitInterval=0

[Install]
WantedBy=multi-user.target
EOF
```

### 启动 kube-scheduler

* v0

```shell
for I in {1..3};do
    ssh root@v${I} "systemctl daemon-reload && systemctl enable --now kube-scheduler"
done
```

### 验证 kube-scheduler

```shell
curl -s --cacert ca.pem --cert admin.pem --key admin-key.pem https://172.31.31.71:10259/metrics
```

```shell
curl -s --cacert ca.pem --cert admin.pem --key admin-key.pem https://172.31.31.72:10259/metrics
```

```shell
curl -s --cacert ca.pem --cert admin.pem --key admin-key.pem https://172.31.31.73:10259/metrics
```

### 查看 kube-scheduler Leader

```shell
journalctl -u kube-scheduler.service --no-pager | grep -i 'leader'
```

---

## 部署 CRI-O

* v0

* [下载](https://github.com/cri-o/cri-o/releases/tag/v1.30.6#downloads)

```shell
cd /usr/local/src
```

```shell
tar xzvf cri-o-v1.30.6.tar.gz
```

```shell
for I in {1..6};do
    rsync -avr /usr/local/src/cri-o root@v${I}:/usr/local/src/
    ssh root@v${I} "cd /usr/local/src/cri-o && ./install && rm -rf /usr/local/src/cri-o && mkdir -p /etc/containers"
done
```

### Short-Name 镜像默认地址

* v1 - v6

```shell
cat > /etc/containers/registries.conf <<EOF
unqualified-search-registries = ["docker.io"]
EOF
```

### 启动 CRI-O

* v0

```shell
for I in {1..6};do
    ssh root@v${I} "systemctl daemon-reload && systemctl enable --now crio.service"
done
```

### 查看 CRI 信息

* v0

```shell
for I in {1..6};do
    ssh root@v${I} "crictl info"
done
```

---

## 部署 containerd (可选，与 CRI-O 二选一即可)

* v0

* [下载](https://github.com/containerd/containerd/releases/download/v1.7.23/containerd-1.7.23-linux-amd64.tar.gz) Containerd

* [下载](https://github.com/containernetworking/plugins/releases/download/v1.5.1/cni-plugins-linux-amd64-v1.5.1.tgz) CNI-Plugins

* [下载](https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.30.0/crictl-v1.30.0-linux-amd64.tar.gz) crictl

* [下载](https://github.com/opencontainers/runc/releases/download/v1.1.15/runc.amd64) RunC

```shell
mkdir /usr/local/src/cni-plugins
```

```shell
tar xzvf cni-plugins-linux-amd64-v1.5.1.tgz -C ./cni-plugins
```

```shell
mkdir /usr/local/src/containerd
```

```shell
tar xzvf containerd-1.7.23-linux-amd64.tar.gz -C ./containerd
```

```shell
tar xzvf crictl-v1.30.0-linux-amd64.tar.gz
```

```shell
for I in {1..6};do
    ssh root@v${I} "mkdir -p /opt/app/cni-plugins-linux-amd64-v1.5.1/bin && ln -snf /opt/app/cni-plugins-linux-amd64-v1.5.1 /opt/cni"
    rsync -avr /usr/local/src/cni-plugins/ root@v${I}:/opt/cni/bin/
    ssh root@v${I} "chown -R root.root /opt/cni/bin/* && chmod +x /opt/cni/bin/*"

    ssh root@v${I} "mkdir -p /opt/app/containerd-1.7.23-linux-amd64/bin && ln -snf /opt/app/containerd-1.7.23-linux-amd64 /opt/containerd"
    rsync -avr /usr/local/src/containerd/bin/ root@v${I}:/opt/containerd/bin/
    ssh root@v${I} "chown -R root.root /opt/containerd/bin/* && chmod +x /opt/containerd/bin/*"

    ssh root@v${I} "mkdir -p /opt/app/crictl-v1.30.0-linux-amd64/bin && ln -snf /opt/app/crictl-v1.30.0-linux-amd64 /opt/crictl"
    rsync -avr /usr/local/src/crictl root@v${I}:/opt/crictl/bin/
    ssh root@v${I} "chown -R root.root /opt/crictl/bin/* && chmod +x /opt/crictl/bin/*"

    ssh root@v${I} "mkdir -p /opt/app/runc-v1.1.15-linux-amd64/sbin && ln -snf /opt/app/runc-v1.1.15-linux-amd64 /opt/runc"
    rsync -avr /usr/local/src/runc.amd64 root@v${I}:/opt/runc/sbin/
    ssh root@v${I} "chown -R root.root /opt/runc/sbin/* && chmod +x /opt/runc/sbin/* && mv /opt/runc/sbin/runc.amd64 /opt/runc/sbin/runc"

    ssh root@v${I} "mkdir -p /etc/containerd/ && mkdir -p /etc/cni/net.d && mkdir -p /data/containerd"
done
```

### 创建 Containerd 配置文件

* v1 - v6

```ini
cat > /etc/containerd/config.toml <<EOF
disabled_plugins = []
imports = []
oom_score = 0
plugin_dir = ""
required_plugins = []
root = "/data/containerd"
state = "/run/containerd"
version = 2

[cgroup]
  path = ""

[debug]
  address = ""
  format = ""
  gid = 0
  level = ""
  uid = 0

[grpc]
  address = "/run/containerd/containerd.sock"
  gid = 0
  max_recv_message_size = 16777216
  max_send_message_size = 16777216
  tcp_address = ""
  tcp_tls_cert = ""
  tcp_tls_key = ""
  uid = 0

[metrics]
  address = ""
  grpc_histogram = false

[plugins]

  [plugins."io.containerd.gc.v1.scheduler"]
    deletion_threshold = 0
    mutation_threshold = 100
    pause_threshold = 0.02
    schedule_delay = "0s"
    startup_delay = "100ms"

  [plugins."io.containerd.grpc.v1.cri"]
    disable_apparmor = false
    disable_cgroup = false
    disable_hugetlb_controller = true
    disable_proc_mount = false
    disable_tcp_service = true
    enable_selinux = false
    enable_tls_streaming = false
    ignore_image_defined_volumes = false
    max_concurrent_downloads = 3
    max_container_log_line_size = 16384
    netns_mounts_under_state_dir = false
    restrict_oom_score_adj = false
    sandbox_image = "k8s.gcr.io/pause:3.5"
    selinux_category_range = 1024
    stats_collect_period = 10
    stream_idle_timeout = "4h0m0s"
    stream_server_address = "127.0.0.1"
    stream_server_port = "0"
    systemd_cgroup = false
    tolerate_missing_hugetlb_controller = true
    unset_seccomp_profile = ""

    [plugins."io.containerd.grpc.v1.cri".cni]
      bin_dir = "/opt/cni/bin"
      conf_dir = "/etc/cni/net.d"
      conf_template = ""
      max_conf_num = 1

    [plugins."io.containerd.grpc.v1.cri".containerd]
      default_runtime_name = "runc"
      disable_snapshot_annotations = true
      discard_unpacked_layers = false
      no_pivot = false
      snapshotter = "overlayfs"

      [plugins."io.containerd.grpc.v1.cri".containerd.default_runtime]
        base_runtime_spec = ""
        container_annotations = []
        pod_annotations = []
        privileged_without_host_devices = false
        runtime_engine = "/opt/runc/sbin/runc"
        runtime_root = ""
        runtime_type = "io.containerd.runtime.v1.linux"

        [plugins."io.containerd.grpc.v1.cri".containerd.default_runtime.options]

      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]

        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          base_runtime_spec = ""
          container_annotations = []
          pod_annotations = []
          privileged_without_host_devices = false
          runtime_engine = ""
          runtime_root = ""
          runtime_type = "io.containerd.runc.v2"

          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            BinaryName = ""
            CriuImagePath = ""
            CriuPath = ""
            CriuWorkPath = ""
            IoGid = 0
            IoUid = 0
            NoNewKeyring = false
            NoPivotRoot = false
            Root = ""
            ShimCgroup = ""
            SystemdCgroup = true

      [plugins."io.containerd.grpc.v1.cri".containerd.untrusted_workload_runtime]
        base_runtime_spec = ""
        container_annotations = []
        pod_annotations = []
        privileged_without_host_devices = false
        runtime_engine = ""
        runtime_root = ""
        runtime_type = ""

        [plugins."io.containerd.grpc.v1.cri".containerd.untrusted_workload_runtime.options]

    [plugins."io.containerd.grpc.v1.cri".image_decryption]
      key_model = "node"

    [plugins."io.containerd.grpc.v1.cri".registry]
      config_path = ""

      [plugins."io.containerd.grpc.v1.cri".registry.auths]

      [plugins."io.containerd.grpc.v1.cri".registry.configs]

      [plugins."io.containerd.grpc.v1.cri".registry.headers]

      [plugins."io.containerd.grpc.v1.cri".registry.mirrors]

    [plugins."io.containerd.grpc.v1.cri".x509_key_pair_streaming]
      tls_cert_file = ""
      tls_key_file = ""

  [plugins."io.containerd.internal.v1.opt"]
    path = "/opt/containerd"

  [plugins."io.containerd.internal.v1.restart"]
    interval = "10s"

  [plugins."io.containerd.metadata.v1.bolt"]
    content_sharing_policy = "shared"

  [plugins."io.containerd.monitor.v1.cgroups"]
    no_prometheus = false

  [plugins."io.containerd.runtime.v1.linux"]
    no_shim = false
    runtime = "runc"
    runtime_root = ""
    shim = "containerd-shim"
    shim_debug = false

  [plugins."io.containerd.runtime.v2.task"]
    platforms = ["linux/amd64"]

  [plugins."io.containerd.service.v1.diff-service"]
    default = ["walking"]

  [plugins."io.containerd.snapshotter.v1.aufs"]
    root_path = ""

  [plugins."io.containerd.snapshotter.v1.btrfs"]
    root_path = ""

  [plugins."io.containerd.snapshotter.v1.devmapper"]
    async_remove = false
    base_image_size = ""
    pool_name = ""
    root_path = ""

  [plugins."io.containerd.snapshotter.v1.native"]
    root_path = ""

  [plugins."io.containerd.snapshotter.v1.overlayfs"]
    root_path = ""

  [plugins."io.containerd.snapshotter.v1.zfs"]
    root_path = ""

[proxy_plugins]

[stream_processors]

  [stream_processors."io.containerd.ocicrypt.decoder.v1.tar"]
    accepts = ["application/vnd.oci.image.layer.v1.tar+encrypted"]
    args = ["--decryption-keys-path", "/etc/containerd/ocicrypt/keys"]
    env = ["OCICRYPT_KEYPROVIDER_CONFIG=/etc/containerd/ocicrypt/ocicrypt_keyprovider.conf"]
    path = "ctd-decoder"
    returns = "application/vnd.oci.image.layer.v1.tar"

  [stream_processors."io.containerd.ocicrypt.decoder.v1.tar.gzip"]
    accepts = ["application/vnd.oci.image.layer.v1.tar+gzip+encrypted"]
    args = ["--decryption-keys-path", "/etc/containerd/ocicrypt/keys"]
    env = ["OCICRYPT_KEYPROVIDER_CONFIG=/etc/containerd/ocicrypt/ocicrypt_keyprovider.conf"]
    path = "ctd-decoder"
    returns = "application/vnd.oci.image.layer.v1.tar+gzip"

[timeouts]
  "io.containerd.timeout.shim.cleanup" = "5s"
  "io.containerd.timeout.shim.load" = "5s"
  "io.containerd.timeout.shim.shutdown" = "3s"
  "io.containerd.timeout.task.state" = "2s"

[ttrpc]
  address = ""
  gid = 0
  uid = 0
EOF
```

### Containerd Systemd Service Unit

* v1 - v6

```ini
cat > /etc/systemd/system/containerd.service <<EOF
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
Environment="PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/opt/kubernetes/client/bin:/opt/kubernetes/server/bin:/opt/kubernetes/node/bin:/opt/cni/bin:/opt/runc/sbin:/opt/containerd/bin:/opt/crictl/bin:/opt/etcd"
ExecStartPre=/sbin/modprobe overlay
ExecStart=/opt/containerd/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF
```

### 启动 Containerd

* v0

```shell
for I in {1..6};do
    ssh root@v${I} "systemctl daemon-reload && systemctl enable --now containerd"
done
```

### 创建 crictl 配置文件

* v1 - v6

```shell
cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF
```

### 查看 CRI 信息

* v0

```shell
for I in {1..6};do
    ssh root@v${I} "crictl info"
done
```

---

## 创建 Node Bootstrap Token

* v0

```shell
for I in {1..6};do
kubeadm token create \
  --description kubelet-bootstrap-token \
  --groups system:bootstrappers:v${I} \
  --kubeconfig /root/.kube/config
done
```

### 查看 Token

* v0

```shell
kubeadm token list
```

```shell
kubectl -n kube-system get secret | grep 'bootstrap-token'
```

### 创建并分发 kubelet bootstrap kubeconfig 至各节点

* v0

```shell
for I in {1..6};do
kubectl config set-cluster kubernetes \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://172.31.31.70:6443 \
  --kubeconfig=./kubelet-bootstrap-v${I}.kubeconfig

BS_TOKEN=$(kubeadm token list --kubeconfig /root/.kube/config | grep "bootstrappers:v${I}" | awk '{print $1}')

kubectl config set-credentials kubelet-bootstrap \
  --token=${BS_TOKEN} \
  --kubeconfig=./kubelet-bootstrap-v${I}.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes \
  --user=kubelet-bootstrap \
  --kubeconfig=./kubelet-bootstrap-v${I}.kubeconfig

kubectl config use-context default \
  --kubeconfig=./kubelet-bootstrap-v${I}.kubeconfig

scp ./kubelet-bootstrap-v${I}.kubeconfig root@v${I}:/etc/kubernetes/kubelet-bootstrap.kubeconfig
done
```

### 创建 kubelet 配置文件

* v1 - v6

* **注意修改如下配置：**
  * `podCIDR`

  * `clusterDomain`

  * `clusterDNS`

```yaml
cat > /etc/kubernetes/kubelet-config.yaml <<EOF
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
address: "0.0.0.0"
staticPodPath: ""
syncFrequency: 1m
fileCheckFrequency: 20s
httpCheckFrequency: 20s
staticPodURL: ""
port: 10250
readOnlyPort: 0
rotateCertificates: true
serverTLSBootstrap: true
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/etc/kubernetes/cert/ca.pem"
authorization:
  mode: Webhook
registryPullQPS: 0
registryBurst: 20
eventRecordQPS: 0
eventBurst: 20
enableDebuggingHandlers: true
enableContentionProfiling: true
healthzPort: 10248
healthzBindAddress: "0.0.0.0"
clusterDomain: "k8s.tsd.org"
clusterDNS:
- "10.254.0.53"
  nodeStatusUpdateFrequency: 10s
  nodeStatusReportFrequency: 1m
  imageMinimumGCAge: 2m
  imageGCHighThresholdPercent: 85
  imageGCLowThresholdPercent: 80
  volumeStatsAggPeriod: 1m
  kubeletCgroups: ""
  systemCgroups: ""
  cgroupRoot: ""
  cgroupsPerQOS: true
  cgroupDriver: systemd
  runtimeRequestTimeout: 10m
  hairpinMode: promiscuous-bridge
  maxPods: 220
  podCIDR: "172.20.0.0/16"
  podPidsLimit: -1
  resolvConf: /etc/resolv.conf
  maxOpenFiles: 1000000
  kubeAPIQPS: 1000
  kubeAPIBurst: 2000
  serializeImagePulls: false
  evictionHard:
  memory.available:  "100Mi"
  nodefs.available:  "10%"
  nodefs.inodesFree: "5%"
  imagefs.available: "15%"
  evictionSoft: {}
  enableControllerAttachDetach: true
  failSwapOn: true
  containerLogMaxSize: 20Mi
  containerLogMaxFiles: 10
  systemReserved: {}
  kubeReserved: {}
  systemReservedCgroup: ""
  kubeReservedCgroup: ""
  enforceNodeAllocatable: ["pods"]
EOF
```

### kubelet Systemd Service Unit

* v0

* kubelet 工作目录：/var/lib/kubelet
  
```shell
for I in {1..6};do
    ssh root@v${I} "mkdir -p /var/lib/kubelet/kubelet-plugins/volume/exec"
done
```

* v1 - v6

* **如使用 Containerd CRI 需要改动：**
   
  * `After=containerd.service`

  * `Requires=containerd.service`

  * `Environment="PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/opt/kubernetes/client/bin:/opt/kubernetes/server/bin:/opt/kubernetes/node/bin:/opt/cni/bin:/opt/runc/sbin:/opt/containerd/bin:/opt/crictl/bin:/opt/etcd"`

  * `--container-runtime-endpoint="unix:///run/containerd/containerd.sock"`

```ini
cat > /etc/systemd/system/kubelet.service <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=crio.service
Requires=crio.service

[Service]
Environment="PATH=export PATH="/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/opt/kubernetes/client/bin:/opt/kubernetes/server/bin:/opt/kubernetes/node/bin:/opt/cni/bin:/opt/etcd""
WorkingDirectory=/var/lib/kubelet
ExecStart=/opt/kubernetes/node/bin/kubelet \\
  --bootstrap-kubeconfig="/etc/kubernetes/kubelet-bootstrap.kubeconfig" \\
  --cert-dir="/etc/kubernetes/cert" \\
  --config="/etc/kubernetes/kubelet-config.yaml" \\
  --container-runtime-endpoint="unix:///var/run/crio/crio.sock" \\
  --kubeconfig="/etc/kubernetes/kubelet.kubeconfig" \\
  --root-dir="/var/lib/kubelet" \\
  --volume-plugin-dir="/var/lib/kubelet/kubelet-plugins/volume/exec/" \\
  --v=2
Restart=always
RestartSec=5
StartLimitInterval=0

[Install]
WantedBy=multi-user.target
EOF
```

### 授权 Kube API Server 访问 kubelet API

* v0

```shell
kubectl create clusterrolebinding kube-apiserver:kubelet-apis \
  --clusterrole=system:kubelet-api-admin \
  --user kubernetes-master
```

### 自动审批节点 CSR 签发请求并生成节点证书

* v0

```shell
kubectl create clusterrolebinding kubelet-bootstrap \
  --clusterrole=system:node-bootstrapper \
  --group=system:bootstrappers
```

```yaml
cat > csr-crb.yaml <<EOF
 # Approve all CSRs for the group "system:bootstrappers"
 kind: ClusterRoleBinding
 apiVersion: rbac.authorization.k8s.io/v1
 metadata:
   name: auto-approve-csrs-for-group
 subjects:
 - kind: Group
   name: system:bootstrappers
   apiGroup: rbac.authorization.k8s.io
 roleRef:
   kind: ClusterRole
   name: system:certificates.k8s.io:certificatesigningrequests:nodeclient
   apiGroup: rbac.authorization.k8s.io
---
 # To let a node of the group "system:nodes" renew its own credentials
 kind: ClusterRoleBinding
 apiVersion: rbac.authorization.k8s.io/v1
 metadata:
   name: node-client-cert-renewal
 subjects:
 - kind: Group
   name: system:nodes
   apiGroup: rbac.authorization.k8s.io
 roleRef:
   kind: ClusterRole
   name: system:certificates.k8s.io:certificatesigningrequests:selfnodeclient
   apiGroup: rbac.authorization.k8s.io
---
# A ClusterRole which instructs the CSR approver to approve a node requesting a
# serving cert matching its client cert.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: approve-node-server-renewal-csr
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/selfnodeserver"]
  verbs: ["create"]
---
 # To let a node of the group "system:nodes" renew its own server credentials
 kind: ClusterRoleBinding
 apiVersion: rbac.authorization.k8s.io/v1
 metadata:
   name: node-server-cert-renewal
 subjects:
 - kind: Group
   name: system:nodes
   apiGroup: rbac.authorization.k8s.io
 roleRef:
   kind: ClusterRole
   name: approve-node-server-renewal-csr
   apiGroup: rbac.authorization.k8s.io
EOF
```

```shell
kubectl apply -f ./csr-crb.yaml
```

### 启动 kubelet Service

* v0

```shell
for I in {1..6};do
    ssh root@v${I} "systemctl daemon-reload && systemctl enable --now kubelet"
done
```

---

## 审批 Kubelet 证书

* v0

```shell
kubectl get csr
```

```shell
kubectl get csr | grep Pending | awk '{print $1}' | xargs kubectl certificate approve
```

```shell
kubectl get csr
```

### 测试 Kubelet 安全性

* 使用 CA 证书

```shell
curl -s --cacert /etc/kubernetes/cert/ca.pem https://172.31.31.74:10250/metrics
```

`Unauthorized`

* 使用 CA 证书和 HTTP 基础认证

```shell
curl -s --cacert /etc/kubernetes/cert/ca.pem \
  -H "Authorization: Bearer 123456" \
  https://172.31.31.74:10250/metrics
```

`Unauthorized`

* 使用 Kubelet 客户端证书

```shell
curl -s --cacert /etc/kubernetes/cert/ca.pem \
  --cert /etc/kubernetes/cert/kubelet-client-current.pem \
  --key /etc/kubernetes/cert/kubelet-client-current.pem \
  https://172.31.31.74:10250/metrics
```

`Forbidden`

* 使用 Admin 用户证书
  
  ```shell
  curl -s --cacert /etc/kubernetes/cert/ca.pem \
  --cert admin.pem \
  --key admin-key.pem \
  https://172.31.31.74:10250/metrics
  ```

### 创建测试 ServiceAccount 访问 Kubelet API

* v0
  
```shell
kubectl create sa kubelet-api-test
```

```shell
kubectl create clusterrolebinding kubelet-api-test \
  --clusterrole=system:kubelet-api-admin \
  --serviceaccount=default:kubelet-api-test
```

```shell
SECRET=$(kubectl get secrets | grep kubelet-api-test | awk '{print $1}')
```

```shell
TOKEN=$(kubectl describe secret ${SECRET} | grep -E '^token' | awk '{print $2}')
```

```shell
echo ${TOKEN}
```

```shell
curl -s --cacert /etc/kubernetes/cert/ca.pem \
  -H "Authorization: Bearer ${TOKEN}" \
  https://172.31.31.74:10250/metrics
```

```shell
kubectl delete sa kubelet-api-test
```

```shell
kubectl delete clusterrolebindings.rbac.authorization.k8s.io kubelet-api-test
```

---

## 创建 Kube-Proxy 证书

```json
cat > kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "Nanu-Network",
      "OU": "K8S"
    }
  ]
}
EOF
```

```shell
cfssl gencert -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes  kube-proxy-csr.json | cfssljson -bare kube-proxy
```

### 分发 Kube-Porxy 证书

* v0

```shell
for I in {1..6};do
    rsync -avr ./kube-proxy*.pem root@v${I}:/etc/kubernetes/cert/
done
```

### 创建 Kube-Proxy kubeconfig

* v0

```shell
kubectl config set-cluster kubernetes \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://172.31.31.70:6443 \
  --kubeconfig=kube-proxy.kubeconfig
```

```shell
kubectl config set-credentials kube-proxy \
  --client-certificate=kube-proxy.pem \
  --client-key=kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig
```

```shell
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig
```

```shell
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
```

### 分发 Kube-Prxoy kubeconfig

* v0

```shell
for I in {1..6};do
    rsync -avr ./kube-proxy.kubeconfig root@v${I}:/etc/kubernetes/
done
```

### 创建 Kube-Proxy 配置文件

* v1 - v6

```yaml
cat > /etc/kubernetes/kube-proxy-config.yaml <<EOF
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  burst: 200
  kubeconfig: "/etc/kubernetes/kube-proxy.kubeconfig"
  qps: 100
bindAddress: 0.0.0.0
healthzBindAddress: 0.0.0.0:10256
metricsBindAddress: 0.0.0.0:10249
enableProfiling: true
clusterCIDR: 172.20.0.0/16
mode: "ipvs"
portRange: ""
iptables:
  masqueradeAll: false
ipvs:
  scheduler: rr
  excludeCIDRs: []
EOF
```

### Kube-Proxy systemd Service Unit

* v0

* Kube-Proxy 工作目录：/var/lib/kube-proxy

```shell
for I in {1..6};do
    ssh root@v${I} "mkdir -p /var/lib/kube-proxy"
done
```

* v1 - v6

```ini
cat > /etc/systemd/system/kube-proxy.service <<EOF
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
Environment="PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/opt/kubernetes/client/bin:/opt/kubernetes/server/bin:/opt/kubernetes/node/bin:/opt/cni/bin:/opt/etcd"
WorkingDirectory=/var/lib/kube-proxy
ExecStart=/opt/kubernetes/node/bin/kube-proxy \\
  --config=/etc/kubernetes/kube-proxy-config.yaml \\
  --v=2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
```

### 启动 Kube-Prxoy

* v0
  
```shell
for I in {1..6};do
    ssh root@v${I} "systemctl daemon-reload && systemctl enable --now kube-proxy"
done
  ```

### 查看 Kube-Proxy IPVS 策略

* v1 - v6

```shell
ipvsadm -ln
```

---

## Master 节点添加标签、污点

* v0

```shell
for I in {1..3};do
    kubectl label node v${I} node-role.kubernetes.io/master=""
    kubectl taint nodes v${I} node-role.kubernetes.io/master=:NoSchedule
done
```

```shell
kubectl get nodes
```

---

## 部署 Calico CNI

* v0

```shell
wget https://github.com/projectcalico/calico/releases/download/v3.28.2/release-v3.28.2.tgz
tar xzvf release-v3.28.2.tgz
docker load --input ./release-v3.28.2/images/calico-cni.tar 
docker load --input ./release-v3.28.2/images/calico-kube-controllers.tar
docker load --input ./release-v3.28.2/images/calico-node.tar
vi ./release-v3.28.2/manifests/calico.yaml
```

* 本文未启用 IPIP `- name: CALICO_IPV4POOL_IPIP`，如需跨二层则设置为`Always`

```yaml
vi calico.yaml
            - name: CALICO_IPV4POOL_CIDR
              value: "172.20.0.0/16"
            - name: IP_AUTODETECTION_METHOD
              value: "cidr=172.31.31.0/24"

            # Enable IPIP
            - name: CALICO_IPV4POOL_IPIP
              value: "Never"
```

```shell
kubectl apply -f ./release-v3.28.2/manifests/calico.yaml
```

```shell
kubectl get pods -n kube-system -o wide -w
```

```shell
kubectl describe pods -n kube-system calico-kube-controllers-
```

```shell
kubectl describe pods -n kube-system calico-node-
```

### Calico 终端程序

* v0

```shell
cp ./release-v3.28.2/bin/calicoctl/calicoctl-linux-amd64 /usr/local/bin/kubectl-calico
```

```shell
chmod +x /usr/local/bin/kubectl-calico
```

```shell
kubectl calico get node -o wide
```

```shell
kubectl calico get ipPool -o wide
```

---

## Node 节点添加标签

* v0

```shell
for I in {4..6};do
    kubectl label nodes v${I} node-role.kubernetes.io/node=""
done
```

```shell
kubectl get nodes
```

---

## 测试集群

* v0

```yaml
cat > nginx-test.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: nginx-test
  labels:
    app: nginx-test
spec:
  type: NodePort
  selector:
    app: nginx-test
  ports:
  - name: http
    port: 80
    targetPort: 80
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nginx-test
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
spec:
  selector:
    matchLabels:
      app: nginx-test
  template:
    metadata:
      labels:
        app: nginx-test
    spec:
      containers:
      - name: nanu-nginx
        image: nginx
        ports:
        - containerPort: 80
EOF
```

```shell
kubectl apply -f ./nginx-test.yaml
```

```shell
kubectl get pods -o wide -l app=nginx-test
```

```shell
ping Pod-IP
```

```shell
kubectl get svc -l app=nginx-test
```

```shell
curl -s http://CLUSTER-IP
```

```shell
kubectl delete -f ./nginx-test.yml
```

---

## 部署 Helm
         
* v0     
         
```shell 
wget https://get.helm.sh/helm-v3.16.2-linux-amd64.tar.gz
```      
         
```shell 
tar xzvf helm-v3.16.2-linux-amd64.tar.gz
```      
         
```shell 
chown -R root.root ./linux-amd64
```      
         
```shell 
cp -rp ./linux-amd64/helm /usr/local/bin/
```      
         
```shell 
chmod +x /usr/local/bin/helm
```      
         
```shell 
https://artifacthub.io/packages/search?kind=0
```      
         
```shell 
helm repo add stable https://charts.helm.sh/stable
```      
         
---

## 部署 CoreDNS                   
  
* v0
  
```shell                          
helm repo add coredns https://coredns.github.io/helm     
```
  
```shell                          
helm repo update                  
```
  
* 注意 CoreDNS Service IP         
  
```shell                          
helm --namespace=kube-system install coredns coredns/coredns --set service.clusterIP="10.254.0.53"
```
  
```shell                          
kubectl get pods -n kube-system -o wide -w
```
  
```shell                          
helm status coredns -n kube-system
```

### 验证 CoreDNS

* v0

```shell
kubectl get all -n kube-system -l k8s-app=kube-dns
```

```yaml
cat > nginx-test-coredns.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test-coredns
spec:
  replicas: 3
  selector:
    matchLabels:
      run: nginx-test-coredns
  template:
    metadata:
      labels:
        run: nginx-test-coredns
    spec:
      containers:
      - name: nginx-test-coredns
        image: nginx
        ports:
        - containerPort: 80
EOF
```

```shell
kubectl apply -f ./nginx-test-coredns.yaml
```

```shell
kubectl get pods -o wide
```

```shell
kubectl expose deploy nginx-test-coredns
```

```shell
kubectl get svc nginx-test-coredns -o wide
```

```yaml
cat > dnsutils-check.yml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: dnsutils-check
  labels:
    app: dnsutils-check
spec:
  type: NodePort
  selector:
    app: dnsutils-check
  ports:

- name: http
  port: 80
  targetPort: 80

---

apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: dnsutils-check
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
spec:
  selector:
    matchLabels:
      app: dnsutils-check
  template:
    metadata:
      labels:
        app: dnsutils-check
    spec:
      containers:
      - name: dnsutils
        image: tutum/dnsutils:latest
        command:
          - sleep
          - "3600"
        ports:
        - containerPort: 80
EOF
```

```shell
kubectl apply -f ./dnsutils-check.yml
```

```shell
kubectl get pods -lapp=dnsutils-check -o wide -w
```

```shell
kubectl exec dnsutils-check-XXX -- cat /etc/resolv.conf
```

```shell
kubectl exec dnsutils-check-XXX -- nslookup dnsutils-check
```

```shell
kubectl exec dnsutils-check-XXX -- nslookup nginx-test-coredns
```

```shell
kubectl exec dnsutils-check-XXX -- nslookup kubernetes
```

```shell
kubectl exec dnsutils-check-XXX -- nslookup www.baidu.com
```

```shell
kubectl delete svc nginx-test-coredns
```

```shell
kubectl delete -f ./dnsutils-check.yml
```

```shell
kubectl delete -f ./nginx-test-coredns.yaml
```

---

## 创建集群只读账户

* v0

```yaml
cat > ./cluster-readonly-clusterrole.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-readonly
rules:

- apiGroups:
  - ""
    resources:
  - configmaps
  - endpoints
  - persistentvolumeclaims
  - pods
  - replicationcontrollers
  - replicationcontrollers/scale
  - serviceaccounts
  - services
  - nodes
  - persistentvolumeclaims
  - persistentvolumes
  - bindings
  - events
  - limitranges
  - namespaces/status
  - pods/log
  - pods/status
  - replicationcontrollers/status
  - resourcequotas
  - resourcequotas/status
  - namespaces
    verbs:
  - get
  - list
  - watch
- apiGroups:
  - apps
    resources:
  - daemonsets
  - deployments
  - deployments/scale
  - replicasets
  - replicasets/scale
  - statefulsets
    verbs:
  - get
  - list
  - watch
- apiGroups:
  - autoscaling
    resources:
  - horizontalpodautoscalers
    verbs:
  - get
  - list
  - watch
- apiGroups:
  - batch
    resources:
  - cronjobs
  - jobs
    verbs:
  - get
  - list
  - watch
- apiGroups:
  - extensions
    resources:
  - daemonsets
  - deployments
  - deployments/scale
  - ingresses
  - networkpolicies
  - replicasets
  - replicasets/scale
  - replicationcontrollers/scale
    verbs:
  - get
  - list
  - watch
- apiGroups:
  - policy
    resources:
  - poddisruptionbudgets
    verbs:
  - get
  - list
  - watch
- apiGroups:
  - networking.k8s.io
    resources:
  - networkpolicies
  - ingresses
  - ingressclasses
    verbs:
  - get
  - list
  - watch
- apiGroups:
  - storage.k8s.io
    resources:
  - storageclasses
  - volumeattachments
    verbs:
  - get
  - list
  - watch
- apiGroups:
  - rbac.authorization.k8s.io
    resources:
  - clusterrolebindings
  - clusterroles
  - roles
  - rolebindings
    verbs:
  - get
  - list
  - watch
EOF
```

```shell
kubectl apply -f ./cluster-readonly-clusterrole.yaml
```

```yaml
cat > ./cluster-readonly-clusterrolebinding.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-readonly
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-readonly
subjects:

- kind: User
  name: cluster-ro
EOF
```

```shell
kubectl apply -f ./cluster-readonly-clusterrolebinding.yaml
```

### 创建集群只读用户证书

* v0

```shell
cat > cluster-ro-csr.json <<EOF
{
  "CN": "cluster-ro",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "Nanu-Network",
      "OU": "K8S"
    }
  ]
}
EOF
```

```shell
cfssl gencert -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes cluster-ro-csr.json | cfssljson -bare cluster-ro
```

### 创建集群只读用户 kubeconfig

* v0

```shell
kubectl config set-cluster kubernetes \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://172.31.31.70:6443 \
  --kubeconfig=cluster-ro.kubeconfig
```

```shell
kubectl config set-credentials cluster-ro \
  --client-certificate=cluster-ro.pem \
  --client-key=cluster-ro-key.pem \
  --embed-certs=true \
  --kubeconfig=cluster-ro.kubeconfig
```

```shell
kubectl config set-context kubernetes \
  --cluster=kubernetes \
  --user=cluster-ro \
  --kubeconfig=cluster-ro.kubeconfig
```

```shell
kubectl config use-context kubernetes --kubeconfig=cluster-ro.kubeconfig
```

---

## 部署 metrics-server

* v0

* 单点部署

```shell
wget -O metrics-server.yaml https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

```shell
kubectl apply -f ./metrics-server.yaml
```

* 高可用部署

```shell
wget -O metrics-server-ha.yaml https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/high-availability.yaml
```

```shell
kubectl apply -f ./metrics-server-ha.yaml
```

---

## 部署 Ingress - Nginx

* v0

```shell
for I in {4..6};do
    kubectl label nodes v${I} node-role.kubernetes.io/ingress="true"
done
```

```shell
wget -O ingress-nginx-1.11.3.yaml https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/baremetal/deploy.yaml
```

### 创建域名证书                           
           
* v0       
           
```shell   
kubectl create secret tls tsd.org \      
  --cert=./tsd.org.crt \                 
  --key=./tsd.org.key                    
```        
           
```shell   
vi ingress-nginx-1.11.3.yaml                
```

* 注释 NodePort Service： kind: Service type: NodePort (出于性能考虑，使用 hostNetwork)
* 配置 Deployment:

```yaml
          args:
            - --default-ssl-certificate=default/tsd.org

  ...

      nodeSelector:
        kubernetes.io/os: linux
        node-role.kubernetes.io/ingress: "true"
      hostNetwork: true
```

```shell   
kubectl apply -f ./ingress-nginx-1.11.3.yaml
```        
           
```shell   
kubectl get pods -n ingress-nginx -o wide -w
ipvsadm -Ln                                                                                                                     
```

---

## 部署 Ceph-CSI 驱动

* v0
* [下载](https://github.com/ceph/ceph-csi/releases)

```shell
tar xzvf ceph-csi-3.12.2.tar.gz
```

```shell
cd ./ceph-csi-3.12.2/deploy/cephfs/kubernetes
```

```shell
kubectl apply -f csi-provisioner-rbac.yaml
```

```shell
kubectl apply -f csi-nodeplugin-rbac.yaml
```

* 配置 Ceph 集群信息

```shell
vi csi-config-map.yaml
```

```shell
kubectl apply -f csi-config-map.yaml
```

```shell
kubectl apply -f csi-cephfsplugin-provisioner.yaml
```

```shell
kubectl get pods -o wide -w
```

```shell
kubectl create -f csi-cephfsplugin.yaml
```

```shell
kubectl get all
```

## 部署 nfs-subdir-external-provisioner

* v0

```shell
git clone https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner.git
```

```shell
cd nfs-subdir-external-provisioner/deploy
```

```shell
kubectl apply -f ./rbac.yaml
```

### 配置 NFS Server 信息

* v0

* **需提前部署好 NFS Server 并 Export 共享目录；**

```shell
vi ./deployment.yaml
```
* 配置 NFS Server
* 配置 NFS Path
* 配置 NFS Volumes:
```yaml
      volumes:
        - name: nfs-client-root
          nfs:
            server: NFS_SERVER_IP
            path: NFS_PATH
```

```shell
kubectl apply -f ./deployment.yaml
```

### 配置 Storage Class

* v0

```yaml
vi ./class.yaml

metadata:
  name: SC_NAME

parameters:
  onDelete: "retain"
  pathPattern: "${.PVC.namespace}/${.PVC.name}"
```

```shell
kubectl apply -f ./class.yaml
```

```shell
kubectl get sc
```

### 创建测试 PVC

* v0

```shell
vi ./test-claim.yaml

spec: 
  storageClassName: SC_NAME
```

```shell
kubectl apply -f ./test-claim.yaml
```

```shell
kubectl get pvc
```

```shell
kubectl get pv
```

### 创建持久化存储测试 Pod

```shell
kubectl apply -f ./test-pod.yaml
```

* 检查 NFS 目录是否有 `SUCCESS` 文件生成

### 清理

```shell
kubectl delete -f ./test-pod.yaml
```

```shell
kubectl delete -f ./test-claim.yaml
```

---

## 部署 Dashboard

### 创建 Dashboard 域名证书

* v0

```shell
kubectl create namespace kubernetes-dashboard
```

```shell
kubectl create secret tls kubernetes-dashboard-certs \
  --cert=./tsd.org.crt \
  --key=./tsd.org.key \
  -n kubernetes-dashboard
```

### 安装 Dashboard

* v0

```shell
wget https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

```shell
mv recommended.yaml dashboard-recommended.yaml
```

```yaml
vi ./dashboard-recommended.yaml

#apiVersion: v1
#kind: Secret
#metadata:

# labels:

# k8s-app: kubernetes-dashboard

# name: kubernetes-dashboard-certs

# namespace: kubernetes-dashboard

#type: Opaque

          # Add Start Command
          command:
            - /dashboard
          args: 
            - --auto-generate-certificates
            - --namespace=kubernetes-dashboard
            # Add TLS Config
            - --token-ttl=3600
            - --bind-address=0.0.0.0
            - --tls-cert-file=tls.crt
            - --tls-key-file=tls.key
```

```shell
kubectl apply -f ./dashboard-recommended.yaml
```

```shell
kubectl get pods -n kubernetes-dashboard -o wide -w
```

```shell
kubectl create sa dashboard-admin -n kube-system
```

### 创建 Dashboard 管理员账户

* v0

```shell
kubectl create clusterrolebinding \
  dashboard-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=kube-system:dashboard-admin
```

```shell
ADMIN_SECRET=$(kubectl get secrets -n kube-system | grep dashboard-admin | awk '{print $1}')
```

```shell
DASHBOARD_LOGIN_TOKEN=$(kubectl describe secret -n kube-system ${ADMIN_SECRET} | grep -E '^token' | awk '{print $2}')
```

```shell
kubectl config set-cluster kubernetes \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://172.31.31.70:6443 \
  --kubeconfig=dashboard.kubeconfig
```

```shell
kubectl config set-credentials dashboard_user \
  --token=${DASHBOARD_LOGIN_TOKEN} \
  --kubeconfig=dashboard.kubeconfig
```

```shell
kubectl config set-context default \
  --cluster=kubernetes \
  --user=dashboard_user \
  --kubeconfig=dashboard.kubeconfig
```

```shell
kubectl config use-context default --kubeconfig=dashboard.kubeconfig
```

### 创建 Dashboard 只读账户

* v0

```shell
kubectl create sa dashboard-ro -n kube-system
```

```shell
kubectl create clusterrolebinding \
  dashboard-ro \
  --clusterrole=cluster-readonly \
  --serviceaccount=kube-system:dashboard-ro
```

```shell
RO_SECRET=$(kubectl get secrets -n kube-system | grep dashboard-ro | awk '{print $1}')
```

```shell
RO_LOGIN_TOKEN=$(kubectl describe secret -n kube-system ${RO_SECRET} | grep -E '^token' | awk '{print $2}')
```

```shell
kubectl config set-cluster kubernetes \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://172.31.31.70:6443 \
  --kubeconfig=dashboard-ro.kubeconfig
```

```shell
kubectl config set-credentials dashboard_ro \
  --token=${RO_LOGIN_TOKEN} \
  --kubeconfig=dashboard-ro.kubeconfig
```

```shell
kubectl config set-context default \
  --cluster=kubernetes \
  --user=dashboard_ro \
  --kubeconfig=dashboard-ro.kubeconfig
```

```shell
kubectl config use-context default --kubeconfig=dashboard-ro.kubeconfig
```

### 测试 Dashboard 访问

* v0

```shell
kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard 4443:443 --address 0.0.0.0
```

`https://172.31.31.70:4443/`

### 创建 Dashboard Ingress

* v0

* 域名：`k8s.tsd.org`

```yaml
cat > ./ingress-dashboard.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: k8s-dashboard
  namespace: kubernetes-dashboard
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
  - host: k8s.tsd.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kubernetes-dashboard
            port:
              number: 443
  tls:
  - secretName: kubernetes-dashboard-certs
    hosts:
    - k8s.tsd.org
EOF
```

```shell
kubectl delete -A ValidatingWebhookConfiguration ingress-nginx-admission
```

```shell
kubectl apply -f ./ingress-dashboard.yaml
```

`https://v0.tsd.org:30443`

---

## 部署 kube-prometheus

* v0
* [检查版本兼容性](https://github.com/prometheus-operator/kube-prometheus#compatibility)

```shell
wget https://github.com/prometheus-operator/kube-prometheus/archive/refs/heads/release-0.10.zip
```

```shell
unzip kube-prometheus-release-0.10.zip
```

```shell
cd kube-prometheus-release-0.10
```

* 替换镜像地址（可选）

```shell
sed -i -e 's_quay.io_quay.mirrors.ustc.edu.cn_' manifests/*.yaml manifests/setup/*.yaml
```

```shell
sed -i -e 's_policy/v1beta1_policy/v1_' manifests/*.yaml manifests/setup/*.yaml
```

```shell
kubectl apply --server-side -f manifests/setup
```

```shell
kubectl apply -f manifests/
```

```shell
kubectl get all -n monitoring
```

### 测试 Prometheus 访问

* v0

```shell
kubectl port-forward -n monitoring svc/prometheus-k8s 9091:9090 --address 0.0.0.0
```

`http://v0.tsd.org:9091`

### 创建 Prometheus Ingress

* v0

```yaml
cat > ./ingress-prometheus.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: k8s-prometheus
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /
    #nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
  - host: k8s-prometheus.tsd.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prometheus-k8s
            port:
              number: 9090
  tls:
  #- secretName: tsd.org
  #  hosts:
  #  - k8s-prometheus.tsd.org
EOF
```

```shell
kubectl apply -f ./ingress-prometheus.yaml
```

`http://k8s-prometheus.tsd.org`

### 测试 Grafana 访问

* v0

```shell
kubectl port-forward -n monitoring svc/grafana 3000:3000 --address 0.0.0.0
```

`http://v0.tsd.org:3000`

### 创建 Grafana Ingress

* v0

```yaml
cat > ingress-grafana.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: k8s-grafana
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /
    #nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
  - host: k8s-grafana.tsd.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend: 
          service:
            name: grafana
            port:
              number: 3000
  tls:
  #- secretName: tsd.org
  #  hosts:
  #  - k8s-grafana.tsd.org
EOF
```

```shell
kubectl apply -f ./ingress-grafana.yaml
```

`http://k8s-grafana.tsd.org`

### 测试 Alert Manager 访问

* v0

```shell
kubectl port-forward -n monitoring svc/alertmanager-main 9093:9093 --address 0.0.0.0
```

`http://v0.tsd.org:9093`

### 创建 Alert Manager Ingress

* v0

```yaml
cat > ingress-alertmanager.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: k8s-alertmanager
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /
    #nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
  - host: k8s-alertmanager.tsd.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend: 
          service:
            name: alertmanager-main
            port:
              number: 9093
  tls:
  #- secretName: tsd.org
  #  hosts:
  #  - k8s-grafana.tsd.org
EOF
```

```shell
kubectl apply -f ./ingress-alertmanager.yaml
```

```shell
http://k8s-alertmanager.tsd.org
```

---

## 部署 E.F.K.

### 创建命名空间

* v0

```shell
kubectl create ns logging
```

### 部署 Elastic Search 有状态副本

* v0

* **配置 NFS Squash，将所有 NFS Client 映射为 root，否则 Elastic Search 可能因为权限问题无法写入 NFS 持久卷；**

* **注意以下配置：**
  * `- name: discovery.zen.minimum_master_nodes = quorum = master_nums/2 + 1`

  * `- name: cluster.initial_master_nodes`

  * `- name: ES_JAVA_OPTS`

  * `storageClassName`

  * `storage`

```yaml
cat > elasticsearch-sts.yaml <<EOF
kind: Service
apiVersion: v1
metadata:
  name: elasticsearch
  namespace: logging
  labels:
    app: elasticsearch
spec:
  selector:
    app: elasticsearch
  clusterIP: None
  ports:
  - port: 9200
    name: rest-api
  - port: 9300
    name: node-comm
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: es
  namespace: logging
spec:
  serviceName: elasticsearch
  replicas: 3
  selector:
    matchLabels:
      app: elasticsearch
  template:
    metadata:
      labels:
        app: elasticsearch
    spec:
      initContainers:
      - name: increase-vm-max-map
        image: busybox
        command:
        - "sysctl"
        - "-w"
        - "vm.max_map_count=262144"
        securityContext:
          privileged: true
      - name: increase-fd-ulimit
        image: busybox
        command:
        - "sh"
        - "-c"
        - "ulimit -n 65536"
        securityContext:
          privileged: true
      containers:
      - name: elasticsearch
        image: docker.elastic.co/elasticsearch/elasticsearch:7.16.2
        securityContext:
          capabilities:
            add:
            - "SYS_CHROOT"
        resources:
          limits:
            cpu: 1000m
          requests:
            cpu: 100m
        ports:
        - containerPort: 9200
          name: rest-api
          protocol: TCP
        - containerPort: 9300
          name: node-comm
          protocol: TCP
        volumeMounts:
        - name: elasticsearch-data
          mountPath: /usr/share/elasticsearch/data
        env:
          - name: cluster.name
            value: k8s-logs
          - name: node.name
            valueFrom:
              fieldRef:
                fieldPath: metadata.name
          - name: cluster.initial_master_nodes
            value: "es-0,es-1,es-2"
          - name: discovery.zen.minimum_master_nodes
            value: "2"
          - name: discovery.seed_hosts
            value: "elasticsearch"
          - name: ES_JAVA_OPTS
            value: "-Xms256m -Xmx256m"
          - name: network.host
            value: "0.0.0.0"
  volumeClaimTemplates:
  - metadata:
      name: elasticsearch-data
      labels:
        app: elasticsearch
    spec:
      storageClassName: sc-nfs
      accessModes:
      - "ReadWriteOnce"
      resources:
        requests:
          storage: 5Gi
EOF
```

```shell
kubectl apply -f ./elasticsearch-sts.yaml
```

```shell
kubectl get all -n logging
```

```shell
kubectl get pods -n logging -o wide
```

### 测试 Elastic Search API

* v0

```shell
kubectl port-forward es-0 9200:9200 --namespace=logging
```

`curl http://localhost:9200/_cluster/state?pretty`

### 部署 Kibana

* v0

```shell
for I in {4..6};do
    kubectl label node v${I} node-role.kubernetes.io/efk="kibana"
done
```

```shell
kubectl get nodes --show-labels
```

* `- name: SERVER_PUBLICBASEURL`

```yaml
cat > kibana.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: kibana
  namespace: logging
  labels:
    app: kibana
spec:          
  type: NodePort
  ports:       
  - port: 5601 
    nodePort: 15601
    targetPort: 5601
  selector:    
    app: kibana
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kibana
  namespace: logging
  labels:
    app: kibana
spec:
  selector:
    matchLabels:
      app: kibana
  template:
    metadata:
      labels:
        app: kibana
    spec:
      nodeSelector:
        node-role.kubernetes.io/efk: kibana
      containers:
      - name: kibana
        image: docker.elastic.co/kibana/kibana:7.16.2
        resources:
          limits:
            cpu: 1000m
          requests:
            cpu: 1000m
        env:
        - name: ELASTICSEARCH_HOSTS
          value: http://elasticsearch:9200
        - name: I18N_LOCALE
          value: zh-CN
        - name: SERVER_PUBLICBASEURL
          value: https://k8s-kibana.tsd.org
        ports:
        - containerPort: 5601
EOF
```

```shell
kubectl apply -f ./kibana.yaml
```

```shell
kubectl get pods -n logging -o wide
```

```shell
kubectl get svc -n logging
```

`http://elasticsearch_headless_svc_node:15601`

### 创建 Kibana Ingress

* v0

* `- host: k8s-kibana.tsd.org`

```yaml
cat > kibana-ingress.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: k8s-kibana
  namespace: logging
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /
    #nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
  - host: k8s-kibana.tsd.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kibana
            port:
              number: 5601
EOF
```

`http://k8s-kibana.tsd.org`

### 创建 Fluentd ConfigMap

* v0

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: fluentd-config
  namespace: logging
data:
  system.conf: |-
    <system>
      root_dir /tmp/fluentd-buffers/
    </system>
  containers.input.conf: |-
    <source>
      @id fluentd-containers.log
      @type tail                              # Get latest log from tail.
      path /var/log/containers/*.log          # Containers log DIR.
      pos_file /var/log/es-containers.log.pos # Log position since last time.
      tag raw.kubernetes.*                    # Set log tag.
      read_from_head true
      <parse>                                 # Format multi-line to JSON.
        @type multi_format                    # Use `multi-format-parser` plugin.
        <pattern>
          format json
          time_key time                       # Set `time_key` word.
          time_format %Y-%m-%dT%H:%M:%S.%NZ
        </pattern>
        <pattern>
          format /^(?<time>.+) (?<stream>stdout|stderr) [^ ]* (?<log>.*)$/
          time_format %Y-%m-%dT%H:%M:%S.%N%:z
        </pattern>
      </parse>
    </source>
    # https://github.com/GoogleCloudPlatform/fluent-plugin-detect-exceptions
    <match raw.kubernetes.**>
      @id raw.kubernetes
      @type detect_exceptions
      remove_tag_prefix raw
      message log
      stream stream 
      multiline_flush_interval 5
      max_bytes 500000
      max_lines 1000
    </match>

    <filter **>  # Join log.
      @id filter_concat
      @type concat                # Fluentd Filter plugin - Join multi-events at different lines.
      key message
      multiline_end_regexp /\n$/  # Joined by `\n`.
      separator ""
    </filter> 

    # Add Kubernetes metadata.
    <filter kubernetes.**>
      @id filter_kubernetes_metadata
      @type kubernetes_metadata
    </filter>

    # Fix JSON fields in Elasticsearch.
    # https://github.com/repeatedly/fluent-plugin-multi-format-parser
    <filter kubernetes.**>
      @id filter_parser
      @type parser
      key_name log                # Field name.
      reserve_data true           # Keep original field value.
      remove_key_name_field true  # Delete field after it's analysed.
      <parse>
        @type multi_format
        <pattern>
          format json
        </pattern>
        <pattern>
          format none
        </pattern>
      </parse>
    </filter>

    # Delete unused fields.
    <filter kubernetes.**>
      @type record_transformer
      remove_keys $.docker.container_id,$.kubernetes.container_image_id,$.kubernetes.pod_id,$.kubernetes.namespace_id,$.kubernetes.master_url,$.kubernetes.labels.pod-template-hash
    </filter>

    # Only keep `logging=true` tag in pod's log.
    <filter kubernetes.**>
      @id filter_log
      @type grep
      <regexp>
        key $.kubernetes.labels.logging
        pattern ^true$
      </regexp>
    </filter>

  # Listen configuration - generally used for log aggregation. 
  forward.input.conf: |-
    # Listen TCP messages.
    <source>
      @id forward
      @type forward
    </source>

  output.conf: |-
    <match **>
      @id elasticsearch
      @type elasticsearch
      @log_level info
      include_tag_key true
      host elasticsearch
      port 9200
      logstash_format true
      logstash_prefix k8s
      request_timeout    30s
      <buffer>
        @type file
        path /var/log/fluentd-buffers/kubernetes.system.buffer
        flush_mode interval
        retry_type exponential_backoff
        flush_thread_count 2
        flush_interval 5s
        retry_forever
        retry_max_interval 30
        chunk_limit_size 2M
        queue_limit_length 8
        overflow_action block
      </buffer>
    </match>
EOF
```

```shell
kubectl apply -f ./fluentd-cf.yaml
```

### 部署 Fluentd DaemonSet

* v0

```yaml
cat > fluentd-ds.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fluentd-es
  namespace: logging
  labels:
    k8s-app: fluentd-es
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: fluentd-es
  labels:
    k8s-app: fluentd-es
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
rules:
- apiGroups:
  - ""
  resources:
  - "namespaces"
  - "pods"
  verbs:
  - "get"
  - "watch"
  - "list"
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: fluentd-es
  labels:
    k8s-app: fluentd-es
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
subjects:
- kind: ServiceAccount
  name: fluentd-es
  namespace: logging
  apiGroup: ""
roleRef:
  kind: ClusterRole
  name: fluentd-es
  apiGroup: ""
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd-es
  namespace: logging
  labels:
    k8s-app: fluentd-es
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
spec:
  selector:
    matchLabels:
      k8s-app: fluentd-es
  template:
    metadata:
      labels:
        k8s-app: fluentd-es
        # Ensure Fluentd won't be evicted while node was evicted.
        kubernetes.io/cluster-service: "true"
    spec:
      priorityClassName: system-cluster-critical
      serviceAccountName: fluentd-es
      containers:
      - name: fluentd-es
        image: quay.io/fluentd_elasticsearch/fluentd
        env:
        - name: FLUENTD_ARGS
          value: --no-supervisor -q
        resources:
          limits:
            memory: 500Mi
          requests:
            cpu: 100m
            memory: 200Mi
        volumeMounts:
        - name: varlog
          mountPath: /var/log
        - name: containerslog
          mountPath: /var/log/containers
          readOnly: true
        - name: config-volume
          mountPath: /etc/fluent/config.d
      #nodeSelector:
      #  beta.kubernetes.io/fluentd-ds-ready: "true"
      tolerations:
      - operator: Exists
      terminationGracePeriodSeconds: 30
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: containerslog
        hostPath:
          path: /var/log/containers
      - name: config-volume
        configMap:
          name: fluentd-config
EOF
```

```shell
kubectl apply -f ./fluentd-ds.yaml
```

```shell
kubectl get pods -n logging
```

### 创建日志测试 Pod

* v0

* **注意：只有具有 logging: "true" 标签才会被接入日志**

```yaml
cat > test-log-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-log
  labels:
    logging: "true"  # Trun log on.
spec:
  containers:
  - name: test-log
    image: busybox
    args:
    - "/bin/sh"
    - "-c"
    - "while true; do echo $(date); sleep 1; done"
EOF
```

```shell
kubectl apply -f ./test-log-pod.yaml
```

```shell
kubectl logs test-log -f
```

* 在 Kibana 中创建 Index Pattern `k8s-*`

### 清理

* v0

```shell
kubectl delete -f ./test-log-pod.yaml
```
