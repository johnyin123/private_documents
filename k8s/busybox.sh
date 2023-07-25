#!/usr/bin/env bash
echo "gunzip -c ~/busybox\:1.31.1.tar.gz | ctr --namespace k8s.io image import -"
echo "ctr -n k8s.io image tag library/busybox:1.31.1 docker.io/library/busybox:1.31.1"
kubectl run myapp2 --image=library/busybox:1.31.1 --restart=Never -- sleep 1d
kubectl get pods -A -o wide | grep busybox
echo "kubectl delete pod busybox --force"
echo "nsenter -n -t <pid>"
