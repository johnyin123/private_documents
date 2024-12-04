#!/usr/bin/env bash

ARCH=(amd64 arm64)
image=registry.local/kubesphere/ks-installer:v3.3.2
LOCAL_FILE=values.yaml
IMG_FILE=/kubesphere/installer/roles/ks-core/ks-core/files/ks-core/values.yaml
LOCAL_FILE1=main.yml
IMG_FILE1=/kubesphere/installer/roles/download/defaults/main.yml
for arch in ${ARCH[@]}; do
    docker pull ${image} --platform ${arch}
    # # with entrypoint and parm, new image docker inspect entrypoint changed to busybox, after commit.
    # docker run --rm --name badboy-image --entrypoint="busybox" ${image} sleep infinity
    docker run --name badboy-image ${image} >/dev/null 2>&1 &
    # docker cp badboy-image:${IMG_FILE} backupfile
    docker cp ${LOCAL_FILE} badboy-image:${IMG_FILE}
    docker cp ${LOCAL_FILE1} badboy-image:${IMG_FILE1}
    docker commit badboy-image ${image}-${arch}
    # # maybe container is down now
    docker kill badboy-image || true
    docker rm badboy-image
    docker push ${image}-${arch}
done
./make_docker_image.sh -c combine --tag ${image}
