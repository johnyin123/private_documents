#!/usr/bin/env bash
VERSION+=("31fbfd8[2023-12-21T09:57:44+08:00]:multiarch_docker_img.sh")
set -o errexit
set -o pipefail
set -o nounset
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
################################################################################
init_docker() {
    local insec_registry=${1:-}
    local cfg_file=/etc/docker/daemon.json
    mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
{
  "registry-mirrors": [ "https://docker.mirrors.ustc.edu.cn", "http://hub-mirror.c.163.com" ],
  "insecure-registries": [ "quay.io"${insec_registry:+, \"${insec_registry}\"} ],
  "exec-opts": ["native.cgroupdriver=systemd", "native.umask=normal" ],
  "storage-driver": "overlay2",
  "data-root": "/var/lib/docker",
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
    debian_minimum_init
EOSHELL
echo "SUCCESS build docker rootfs"
exit 0
EOF
    chmod 755 ${DIRNAME}/create_base_img.sh
    INST_ARCH=amd64 ${DIRNAME}/create_base_img.sh
    INST_ARCH=arm64 ${DIRNAME}/create_base_img.sh
    rm -f ${DIRNAME}/create_base_img.sh
}
gen_dockerfile() {
    local img_tag=${1}
    local target_dir=${2}
    cfg_file=${target_dir}/Dockerfile
mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
ARG ARCH=
FROM ${img_tag}-\${ARCH}
LABEL maintainer="johnyin" name="${img_tag}" build-date="$(date '+%Y%m%d%H%M%S')"
ENV PS1="\$(tput bold)(DOCKER)\$(tput sgr0)[\$(id -un)@\$(hostname -s) \$(pwd)]$ "
COPY starter.sh /usr/local/bin/startup
COPY service /run_command
RUN mkdir -p /run/sshd && touch /usr/local/bin/startup && chmod 755 /usr/local/bin/startup
ENTRYPOINT ["dumb-init", "--single-child", "--", "/usr/local/bin/startup"]
EOF
cat <<EOF
RUN { \
    touch /usr/local/bin/startup && chmod 755 /usr/local/bin/startup; \
    echo "deb [trusted=yes] http://192.168.168.1/debian bookworm main" > /etc/apt/sources.list; \
    apt update; \
    apt -y install iproute2; \
    apt clean all; \
    uname -m; \
    }
EOF
    cfg_file=${target_dir}/starter.sh
    mkdir -p $(dirname "${cfg_file}") && cat <<'EOF' > "${cfg_file}"
#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset
set -o xtrace
CMD=$(cat /run_command)
ARGS=""
echo "Running command: '${CMD}${ARGS:+ $ARGS}'"
exec ${CMD} ${ARGS}
EOF
    # echo "sleep infinity" > ${target_dir}/service
    cfg_file=${target_dir}/service
    mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
/usr/sbin/sshd -D
EOF
}
build_multiarch_docker_img() {
    local base_img_tag="${1}"
    local img_tag="${2}"
    local dockerfile_dir="${3}"
    local registry="${4}"
    local arch=""
    for arch in amd64 arm64; do
        local sha256=$(cd ${DIRNAME}/buildroot-${arch} && tar cv . | docker import -)
        docker tag ${sha256} ${base_img_tag}-${arch}
        (cd ${dockerfile_dir} && docker build -t ${registry}/${img_tag}-${arch} --build-arg ARCH=${arch} --network=host .)
        docker inspect ${registry}/${img_tag}-${arch}
        docker push ${registry}/${img_tag}-${arch}
    done
    echo "#### GEN MULTI ARCH IMAGE ####"
    # # registry must has ssl
    docker manifest rm ${registry}/${img_tag} 2>/dev/null || true
    docker manifest create --insecure ${registry}/${img_tag} \
        --amend ${registry}/${img_tag}-amd64 \
        --amend ${registry}/${img_tag}-arm64
    for arch in amd64 arm64; do
        docker manifest annotate --arch ${arch} ${registry}/${img_tag} ${registry}/${img_tag}-${arch}
    done
    docker manifest inspect ${registry}/${img_tag}
    docker manifest push --insecure ${registry}/${img_tag}
    for arch in amd64 arm64; do
        echo "++++++++++++++++++check ${arch} start++++++++++++++++++"
        docker pull ${registry}/${img_tag} --platform ${arch}
        docker run --entrypoint="uname" ${registry}/${img_tag} -m
        echo "++++++++++++++++++check ${arch} end  ++++++++++++++++++"
    done
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

init_docker "registry.local"
create_docker_bridge "br-ext"
create_base_img
gen_dockerfile "debian:bookworm" "${DIRNAME}/myimg"
build_multiarch_docker_img "debian:bookworm" "ssh:v1" "${DIRNAME}/myimg" "registry.local"

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
