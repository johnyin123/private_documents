#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
set -o errtrace
set -o nounset
set -o errexit
VERSION+=("211fc9e[2023-08-07T13:46:17+08:00]:gen_k8s_pkg.sh")
################################################################################
PKG_DIR=${1?"${SCRIPTNAME} <src_dir> <amd64/arm64> <k8sver examp: v1.27.3>"}
ARCH=${2?"${SCRIPTNAME} <src_dir> <amd64/arm64> <k8sver examp: v1.27.3>"}
VER=${3?"${SCRIPTNAME} <src_dir> <amd64/arm64> <k8sver examp: v1.27.3>"}
# # requires start
TGZ_CRICTL=crictl-v1.27.1-linux-${ARCH}.tar.gz 
TGZ_CONTAINERD=containerd-static-1.7.2-linux-${ARCH}.tar.gz 
TGZ_CNI_PLUGINS=cni-plugins-linux-${ARCH}-v1.3.0.tgz 
BIN_KUBEADM=kubeadm.${VER}.${ARCH}
BIN_KUBECTL=kubectl.${VER}.${ARCH}
BIN_KUBELET=kubelet.${VER}.${ARCH}
BIN_RUNC=runc.${ARCH}
BIN_CALICOCTL=calicoctl-linux-${ARCH}
BIN_HELM=helm.v3.6.3.${ARCH}
# # requires end
[ -e "${TGZ_CRICTL}" ] && \
[ -e "${TGZ_CONTAINERD}" ] && \
[ -e "${TGZ_CNI_PLUGINS}" ] && \
[ -e "${BIN_KUBEADM}" ] && \
[ -e "${BIN_KUBECTL}" ] && \
[ -e "${BIN_KUBELET}" ] && \
[ -e "${BIN_RUNC}" ] && \
[ -e "${BIN_CALICOCTL}" ] &&
[ -e "${BIN_HELM}" ] || {
    cat<<EOF
Require:
    ${TGZ_CRICTL}
    ${TGZ_CONTAINERD}
    ${TGZ_CNI_PLUGINS}
    ${BIN_KUBEADM}
    ${BIN_KUBECTL}
    ${BIN_KUBELET}
    ${BIN_RUNC}
    ${BIN_CALICOCTL}
    ${BIN_HELM}
https://github.com/containerd/containerd/releases/download/v1.7.2/containerd-static-1.7.2-linux-${ARCH}.tar.gz
https://github.com/opencontainers/runc/releases/download/v1.1.7/runc.${ARCH}
https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-${ARCH}-v1.3.0.tgz
https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.27.1/crictl-v1.27.1-linux-${ARCH}.tar.gz
https://dl.k8s.io/release/${VER}/bin/linux/${ARCH}/kubelet
https://dl.k8s.io/release/${VER}/bin/linux/${ARCH}/kubeadm
https://dl.k8s.io/release/${VER}/bin/linux/${ARCH}/kubectl
EOF
    exit 1
}

for d in /opt/cni /usr/bin/ /etc/systemd/system/kubelet.service.d /lib/systemd/system /etc/kubernetes/manifests; do
    mkdir -pv ${PKG_DIR}/${d}
done
cat <<'EOF' > ${PKG_DIR}/etc/systemd/system/kubelet.service.d/10-kubeadm.conf
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
# This is a file that "kubeadm init" and "kubeadm join" generates at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
# This is a file that the user can use for overrides of the kubelet args as a last resort. Preferably, the user should use
# the .NodeRegistration.KubeletExtraArgs object in the configuration files instead. KUBELET_EXTRA_ARGS should be sourced from this file.
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
EOF
chmod -v 644 ${PKG_DIR}/etc/systemd/system/kubelet.service.d/10-kubeadm.conf
cat <<EOF > ${PKG_DIR}/lib/systemd/system/kubelet.service
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=https://kubernetes.io/docs/home/
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/bin/kubelet
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
chmod -v 644 ${PKG_DIR}/lib/systemd/system/kubelet.service
cat <<EOF > ${PKG_DIR}/lib/systemd/system/containerd.service
# Copyright The containerd Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
#uncomment to enable the experimental sbservice (sandboxed) version of containerd/cri integration
#Environment="ENABLE_CRI_SANDBOXES=sandboxed"
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/bin/containerd

Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
# Comment TasksMax if your systemd version does not supports it.
# Only systemd 226 and above support this version.
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF
chmod -v 644 ${PKG_DIR}/lib/systemd/system/containerd.service

install -v --mode=0755 ${BIN_KUBEADM} ${PKG_DIR}/usr/bin/kubeadm
install -v --mode=0755 ${BIN_KUBECTL} ${PKG_DIR}/usr/bin/kubectl
install -v --mode=0755 ${BIN_KUBELET} ${PKG_DIR}/usr/bin/kubelet
install -v --mode=0755 ${BIN_RUNC} ${PKG_DIR}/usr/bin/runc
install -v --mode=0755 ${BIN_CALICOCTL} ${PKG_DIR}/usr/bin/calicoctl
install -v --mode=0755 ${BIN_HELM} ${PKG_DIR}/usr/bin/helm
tar -C ${PKG_DIR}/usr/bin  -xvf ${TGZ_CRICTL}
tar -C ${PKG_DIR}/usr/     -xvf ${TGZ_CONTAINERD}
tar -C ${PKG_DIR}/opt/cni/ -xvf ${TGZ_CNI_PLUGINS}


depends="--depends ebtables --depends ethtool --depends iptables --depends conntrack --depends socat --depends ipvsadm"
fpm --package . -s dir -t rpm --architecture ${ARCH} -C ${PKG_DIR}/ --name tsd_cnap_${VER} --conflicts containerd --conflicts kubelet --conflicts kubeadm --conflicts kubectl ${depends} --version 0.9 --description "tsd cnap ${ARCH} env ${VER} $(echo "${VERSION[@]}" | cut -d'[' -f 1)"
fpm --package . -s dir -t deb --architecture ${ARCH} -C ${PKG_DIR}/ --name tsd_cnap_${VER} --conflicts containerd --conflicts kubelet --conflicts kubeadm --conflicts kubectl ${depends} --version 0.9 --description "tsd cnap ${ARCH} env ${VER} $(echo "${VERSION[@]}" | cut -d'[' -f 1)"
cat <<'EOF'
yum -y --disablerepo=* --enablerepo=myrepo --enablerepo=cnap install tsd_cnap_v1.21.7
cat <<EOFREP > cnap.repo
[cnap]
name=cnap
baseurl=http://10.170.6.105/cnap
enabled=1
gpgcheck=0

[myrepo]
name=myrepo
baseurl=http://10.170.6.105/openEuler-22.03-LTS-SP1/everything/\$basearch/
enabled=1
gpgcheck=0
EOFREP
createrepo_c .
EOF
