#!/usr/bin/env bash
# # in internet env(maybe netns/vm)
# # PROXY=https://registry.k8s.io PORT=:5001 ./registry.sh
# # docker pull <ip:5001>/<img> --platform <arch> / k8s.io image pull <ip:5001>/<img> --all-platforms
mirror=registry.aliyuncs.com/google_containers
local_registry=192.168.168.250
for img in $(kubeadm config images list --kubernetes-version=v1.21.7 --image-repository=${mirror})
do
    ctr -n k8s.io image pull ${img} --all-platforms
    ctr -n k8s.io image tag ${img} ${target_img}
    target_img=${local_registry}/google_containers/${img##*/}
    ctr -n k8s.io image push ${target_img} --platform amd64 --platform arm64 --plain-http
done
# # only pull/push arm64/amd64
cat <<EOF
mirror=127.0.0.1:5000
local_registry=127.0.0.1:5001
# # image.list
library/busybox:latest
EOF
ARCH=(amd64 arm64)
for img in $(cat lst); do
    for arch in ${ARCH[@]}; do
        docker pull --quiet ${mirror}/${img} --platform ${arch}
        docker tag ${mirror}/${img} ${local_registry}/${img}-${arch}
        echo "rm ${mirror}/${img}"
        docker image rm ${mirror}/${img} >/dev/null 2>/dev/null
        docker push --quiet ${local_registry}/${img}-${arch}
    done
    ./make_docker_image.sh -c combine --tag ${local_registry}/${img}
    for arch in ${ARCH[@]}; do
        echo "rm ${local_registry}/${img}-${arch}"
        docker image rm ${local_registry}/${img}-${arch} >/dev/null 2>/dev/null
    done
    echo "rm ${local_registry}/${img}"
    docker image rm ${local_registry}/${img} >/dev/null 2>/dev/null
done
