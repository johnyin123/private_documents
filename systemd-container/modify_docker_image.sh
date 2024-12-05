#!/usr/bin/env bash

ARCH=(amd64 arm64)
image=registry.local/kubesphere/ks-installer:v3.3.2
LOCAL_FILE=ks-devops-0.1.19.tgz
IMG_FILE=/kubesphere/installer/roles/ks-devops/files/ks-devops/charts/ks-devops-0.1.19.tgz
for arch in ${ARCH[@]}; do
    docker pull ${image} --platform ${arch}
    # # with entrypoint and parm, new image docker inspect entrypoint changed to busybox, after commit.
    # docker run --rm --name badboy-${arch} --entrypoint="busybox" ${image} sleep infinity
    docker run --name badboy-${arch} ${image} >/dev/null 2>&1 &
    # docker cp badboy-${arch}:${IMG_FILE} backupfile
    for cnt in $(seq 1 5); do
        docker cp badboy-${arch}:${IMG_FILE} - > $(date +'%Y%m%d%H%M%S').bak 2>/dev/null || { echo "wait $cnt"; sleep 2; continue; }
        break
    done
    docker cp ${LOCAL_FILE} badboy-${arch}:${IMG_FILE} && echo "COPY OK" || { echo "ERROR"; exit 1; }
    docker commit badboy-${arch} ${image}-${arch}
    # # maybe container is down now
    docker kill badboy-${arch} || true
    docker rm badboy-${arch}
    docker push ${image}-${arch}
done
./make_docker_image.sh -c combine --tag ${image}
