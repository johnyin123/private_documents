#!/usr/bin/env bash
VERSION+=("e8bcecb[2024-01-03T09:29:49+08:00]:docker_init.sh")
set -o errexit
set -o pipefail
set -o nounset
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
################################################################################
init_docker() {
    local insec_registry=${1:-}
    local dns=${2:-}
    local cfg_file=/etc/docker/daemon.json
    # If self-signed certificate or an internal Certificate Authority
    # /etc/docker/certs.d/<docker registry>/ca.crt
    [ -z "${insec_registry}" ] || mkdir -p /etc/docker/certs.d/${insec_registry}/
    # openssl s_client -showcerts -connect ${insec_registry}:443 < /dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > /etc/docker/certs.d/${insec_registry}/ca.crt
    echo "https://get.docker.io/builds/Linux/x86_64/docker-latest.tgz"
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
	# debian requires setting unprivileged_userns_clone
	if [ -f /proc/sys/kernel/unprivileged_userns_clone ]; then
		if [ "1" != "$(cat /proc/sys/kernel/unprivileged_userns_clone)" ]; then
cat <<EOT > /etc/sysctl.d/50-rootless.conf
kernel.unprivileged_userns_clone = 1
EOT
		fi
	fi
	# centos requires setting max_user_namespaces
	if [ -f /proc/sys/user/max_user_namespaces ]; then
		if [ "0" = "$(cat /proc/sys/user/max_user_namespaces)" ]; then
cat <<EOT > /etc/sysctl.d/51-rootless.conf
user.max_user_namespaces = 62669
EOT
		fi
	fi
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
    rm -fr /usr/share/doc/* /usr/share/man/*
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
        --gateway 192.168.169.1 --subnet 192.168.169.0/24 \
        --ip-range 192.168.169.192/26 \
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
# By default docker runs the container as root user unless specified otherwise.
# In order to force docker to run the container as the same user as the docker daemon add --user flag as show below to docker run command.
# --user "$(id -u):$(id -g)"
# --dns 8.8.8.8
# --ip 192.168.168.2
# --volume /host/disk/:/docker/mnt     # bind mount
# --mount       Attach a filesystem mount to the container
docker ps -a --no-trunc
docker images | awk '{print $3}' | xargs -I@ docker image rm @ -f
docker ps -a | awk '{print $1}' | xargs -I@ docker rm @
# # override ENTRYPOINT
docker run --rm --entrypoint="/bin/ls" mybase:v1 /bin/
for image in $(docker images --format "{{.Repository}}:{{.Tag}}") ;do echo $image;done
EOF
