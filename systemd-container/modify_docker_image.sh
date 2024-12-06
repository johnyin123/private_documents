#!/usr/bin/env bash

ARCH=(amd64 arm64)
image=registry.local/kubesphere/ks-installer:v3.3.2
# # local file / directory
echo "chown 1002:1002 kubesphere -R"
LOCAL_FILE=kubesphere
# # docker image position
IMG_FILE=/
for arch in ${ARCH[@]}; do
    docker pull ${image} --platform ${arch}
    # # with entrypoint and parm, new image docker inspect entrypoint changed to busybox, after commit.
    # docker run --rm --name badboy-${arch} --entrypoint="busybox" ${image} sleep infinity
    docker run --name badboy-${arch} ${image} >/dev/null 2>&1 &
    # docker cp badboy-${arch}:${IMG_FILE} backupfile
    for cnt in $(seq 1 5); do
        docker cp --archive badboy-${arch}:${IMG_FILE} - > $(date +'%Y%m%d%H%M%S').bak 2>/dev/null || { echo "wait $cnt"; sleep 2; continue; }
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
