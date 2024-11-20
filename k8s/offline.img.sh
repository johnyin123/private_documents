#!/usr/bin/env bash
mirror=registry.aliyuncs.com/google_containers
local_registry=192.168.168.250
for img in $(kubeadm config images list --kubernetes-version=v1.21.7 --image-repository=${mirror})
do
    ctr -n k8s.io image pull ${img} --all-platforms
    ctr -n k8s.io image tag ${img} ${target_img}
    target_img=${local_registry}/google_containers/${img##*/}
    ctr -n k8s.io image push ${target_img} --platform amd64 --platform arm64 --plain-http
done
