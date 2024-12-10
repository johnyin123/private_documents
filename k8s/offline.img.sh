#!/usr/bin/env bash
# # in internet env(maybe netns/vm)
# # PROXY=https://registry.k8s.io PORT=:5001 ./registry.sh
# # docker pull <ip:5001>/<img> --platform <arch> / k8s.io image pull <ip:5001>/<img> --all-platforms
from_registry=registry.aliyuncs.com/google_containers
to_registry=192.168.168.250
for img in $(kubeadm config images list --kubernetes-version=v1.21.7 --image-repository=${from_registry})
do
    ctr -n k8s.io image pull ${img} --all-platforms
    ctr -n k8s.io image tag ${img} ${target_img}
    target_img=${to_registry}/google_containers/${img##*/}
    ctr -n k8s.io image push ${target_img} --platform amd64 --platform arm64 --plain-http
done
# # only pull/push arm64/amd64
cat <<EOF
from_registry=127.0.0.1:5000
to_registry=127.0.0.1:5001
# # image.list
library/busybox:latest
EOF
ARCH=(amd64 arm64)
for img in $(cat lst); do
    for arch in ${ARCH[@]}; do
        docker pull --quiet ${from_registry}/${img} --platform ${arch}
        docker tag ${from_registry}/${img} ${to_registry}/${img}-${arch}
        echo "rm ${from_registry}/${img}"
        docker image rm ${from_registry}/${img} >/dev/null 2>/dev/null
        docker push --quiet ${to_registry}/${img}-${arch}
        docker inspect --type=image --format='{{json .Config.Env}}' ${to_registry}/${img}-${arch}
        docker inspect --type=image --format='{{json .Config.Entrypoint}}' ${to_registry}/${img}-${arch}
        docker inspect --type=image --format='{{json .Config.Cmd}}' ${to_registry}/${img}-${arch}
    done
    ./make_docker_image.sh -c combine --tag ${to_registry}/${img}
    for arch in ${ARCH[@]}; do
        echo "rm ${to_registry}/${img}-${arch}"
        docker image rm ${to_registry}/${img}-${arch} >/dev/null 2>/dev/null
    done
    echo "rm ${to_registry}/${img}"
    docker image rm ${to_registry}/${img} >/dev/null 2>/dev/null
done
