#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
file_exists() { [ -e "$1" ]; }
ARCH=(amd64 arm64)

type=etcd
ver=trixie
nsname=simplekvm

for fn in make_docker_image.sh tpl_overlay.sh; do
    file_exists "${fn}" || { log "${fn} no found"; exit 1; }
done

export BUILD_NET=${BUILD_NET:-host}
export REGISTRY=registry.local
export IMAGE=debian:trixie       # # BASE IMAGE
export NAMESPACE=

for arch in ${ARCH[@]}; do
    ./make_docker_image.sh -c ${type} -D ${type}-${arch} --arch ${arch}
    cat <<EODOC > ${type}-${arch}/docker/build.run
set -o nounset -o pipefail -o errexit
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive
APT="apt -y ${PROXY:+--option Acquire::http::Proxy=\"${PROXY}\" }--no-install-recommends"
\${APT} update
\${APT} install etcd-server
find /usr/share/locale -maxdepth 1 -mindepth 1 -type d ! -iname 'zh_CN*' ! -iname 'en*' | xargs -I@ rm -rf @ || true
rm -rf /var/lib/apt/* /var/cache/* /root/.cache /root/.bash_history /usr/share/man/* /usr/share/doc/*
EODOC
    mkdir -p ${type}-${arch}/docker/ && cat <<'EODOC' >${type}-${arch}/docker/entrypoint.sh
#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
env || true
exec "$@"
EODOC
    chmod 755 ${type}-${arch}/docker/entrypoint.sh
    cat <<EODOC >> ${type}-${arch}/Dockerfile
EXPOSE 2379 2380
ENTRYPOINT ["/entrypoint.sh"]
CMD ["etcd"]
EODOC
    ################################################
    docker pull --quiet "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" --platform ${arch}
    docker run --name ${type}-${arch}.baseimg --entrypoint="uname" "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" -m || true
    rm -f ${type}-${arch}.baseimg.tpl || true
    docker export ${type}-${arch}.baseimg | mksquashfs - ${type}-${arch}.baseimg.tpl -tar # -quiet
    docker rm -v ${type}-${arch}.baseimg
    log "Pre chroot, copy files in ${type}-${arch}/docker/"
    #####
    log "Pre chroot exit"
    ./tpl_overlay.sh -t ${type}-${arch}.baseimg.tpl -r ${type}-${arch}.rootfs --upper ${type}-${arch}/docker
    log "chroot ${type}-${arch}.rootfs,(copy app) exit continue build"
    chroot ${type}-${arch}.rootfs /usr/bin/env -i SHELL=/bin/bash PS1="\u@DOCKER-${arch}:\w$" TERM=${TERM:-} COLORTERM=${COLORTERM:-} /bin/bash --noprofile --norc -o vi || true
    log "exit ${type}-${arch}.rootfs"
    ./tpl_overlay.sh -r ${type}-${arch}.rootfs -u
    log "Post chroot, delete nouse file in ${type}-${arch}/docker/"
    for fn in tmp root build.run nginx-johnyin_${arch}.deb; do
        rm -fr ${type}-${arch}/docker/${fn}
    done
    rm -vfr ${type}-${arch}.baseimg.tpl ${type}-${arch}.rootfs
done
log '=================================================='
for arch in ${ARCH[@]}; do
    log docker pull --quiet "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" --platform ${arch}
    log ./make_docker_image.sh -c build -D ${type}-${arch} --tag ${REGISTRY}/${nsname}/${type}:${ver}-${arch}
    log docker push ${REGISTRY}/${nsname}/${type}:${ver}-${arch}
done
log ./make_docker_image.sh -c combine --tag ${REGISTRY}/${nsname}/${type}:${ver}

trap "exit -1" SIGINT SIGTERM
read -n 1 -t 10 -p "Continue build(Y/n)? 10s timeout, default n" value || true
if [ "${value}" = "y" ]; then
    for arch in ${ARCH[@]}; do
        docker pull --quiet "${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}" --platform ${arch}
        ./make_docker_image.sh -c build -D ${type}-${arch} --tag ${REGISTRY}/${nsname}/${type}:${ver}-${arch}
        docker push ${REGISTRY}/${nsname}/${type}:${ver}-${arch}
    done
    ./make_docker_image.sh -c combine --tag ${REGISTRY}/${nsname}/${type}:${ver}
fi
