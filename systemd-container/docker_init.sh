#!/usr/bin/env bash
VERSION+=("initver[2023-12-26T14:47:21+08:00]:docker_init.sh")
set -o errexit
set -o pipefail
set -o nounset
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
################################################################################
init_docker() {
    local insec_registry=${1:-}
    local dns=${2:-}
    local cfg_file=/etc/docker/daemon.json
    mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
{
  "registry-mirrors": [ "https://docker.mirrors.ustc.edu.cn", "http://hub-mirror.c.163.com" ],
  "insecure-registries": [ "quay.io"${insec_registry:+, \"${insec_registry}\"} ],
  "exec-opts": ["native.cgroupdriver=systemd", "native.umask=normal" ],
  "storage-driver": "overlay2",
  "data-root": "/var/lib/docker",
  ${dns:+  "dns": ["${dns}"],}
  "bridge": "none",
  "ip-forward": false,
  "iptables": false
}
EOF
    cfg_file=/etc/systemd/system/docker.service.d/opt.conf
    mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
[Service]
MountFlags=shared
EOF
    systemctl daemon-reload || true
    systemctl restart docker || true
    systemctl enable docker || true
}
create_base_img() {
    # # base image, install dumb-init
    local cfg_file=${DIRNAME}/create_base_img.sh
    mkdir -p $(dirname "${cfg_file}") && cat <<'EOF' > "${cfg_file}"
#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
################################################################################
[ -e ${DIRNAME}/os_debian_init.sh ] && . ${DIRNAME}/os_debian_init.sh || { echo '**ERROR: os_debian_init.sh nofound!'; exit 1; }

INST_ARCH=${INST_ARCH:-amd64}
DEBIAN_VERSION=${DEBIAN_VERSION:-bookworm}
HOSTNAME="docker"
REPO=http://mirrors.aliyun.com/debian
NAME_SERVER=114.114.114.114

PKG="openssh-server,dumb-init"

mkdir -p ${DIRNAME}/buildroot-${INST_ARCH}
mkdir -p ${DIRNAME}/cache

debian_build "${DIRNAME}/buildroot"-${INST_ARCH} "${DIRNAME}/cache" "${PKG}"

LC_ALL=C LANGUAGE=C LANG=C chroot "${DIRNAME}/buildroot-${INST_ARCH}/" /bin/bash <<EOSHELL
    debian_sshd_init || true
    debian_bash_init root true
    debian_minimum_init
EOSHELL
echo "SUCCESS build docker rootfs"
exit 0
EOF
    chmod 755 ${DIRNAME}/create_base_img.sh
    echo "INST_ARCH=amd64 ./create_base_img.sh"
    echo "INST_ARCH=arm64 ./create_base_img.sh"
    echo "rm -f create_base_img.sh"
}
create_docker_bridge() {
    local br_name=${1}
    # # use EXISTS BRIDGE as docker bridge network
    docker network prune -f
    docker network ls
    docker network create --attachable --driver bridge \
        --gateway 192.168.168.1 --subnet 192.168.168.0/24 \
        --ip-range 192.168.168.192/26 \
        --opt "com.docker.network.bridge.name=${br_name}" ${br_name}
    docker network ls
}

init_docker "registry.local" "114.114.114.114"
create_docker_bridge "br-ext"
create_base_img

cat <<'EOF'
# make user can run docker command
usermod -aG docker johnyin
docker create -e KEY1=1 -e KEY2=2 --hostname testrv --name myname --network br-ext myimg 
# --dns 8.8.8.8
# --ip 192.168.168.2
# --volume /host/disk/:/docker/mnt     # bind mount
# --mount       Attach a filesystem mount to the container
docker ps -a --no-trunc
docker images | awk '{print $3}' | xargs -I@ docker image rm @ -f
docker ps -a | awk '{print $1}' | xargs -I@ docker rm @
# # override ENTRYPOINT
docker run --entrypoint="/bin/ls" mybase:v1 /bin/
EOF
