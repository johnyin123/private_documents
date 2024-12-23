#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
################################################################################
export BUILD_NET=br-ext
export IMAGE=python:bookworm  # # BASE IMAGE
# export REGISTRY=registry.local
# export NAMESPACE=
ARCH=(arm64 amd64)
type=elbprovider
ver=1.0
for arch in ${ARCH[@]}; do
    IMG_DIR=${type}-${arch}
    TAG_PREFIX=${REGISTRY:-registry.local}/${NAMESPACE:+${NAMESPACE}/}${type}
    ./make_docker_image.sh -c ${type} --arch ${arch} -D ${IMG_DIR}
    ################################################
    mkdir -p ${IMG_DIR}/docker/home/johnyin/
    cp elb-cloudprovider.py ${IMG_DIR}/docker/home/johnyin/elb_provider.py
    chown 1000:1000 ${IMG_DIR}/docker/home/johnyin -R
    cat <<EOF >> ${IMG_DIR}/Dockerfile
USER johnyin
WORKDIR /home/johnyin
ENTRYPOINT ["python3", "/home/johnyin/elb_provider.py" ]
EOF
    cat <<EOF > ${IMG_DIR}/docker/build.run
apt update && apt -y install python3-kubernetes
getent passwd johnyin >/dev/null || useradd -m -u 10001 johnyin --home-dir /home/johnyin/ --shell /bin/bash
chown johnyin:johnyin /home/johnyin/* -R
/usr/sbin/runuser -u johnyin -- /bin/bash -s << EOSHELL
    # python3 -m venv /home/johnyin/myvenv
    # source /home/johnyin/myvenv/bin/activate
    # which python
    python3 --version
    python3 -c "import kubernetes" && echo "kubernetes package OK" || echo "kubernetes package ERROR"
EOSHELL
EOF
    # confirm base-image is right arch
    docker pull --quiet ${REGISTRY:-registry.local}/${NAMESPACE:+${NAMESPACE}/}${IMAGE} --platform ${arch}
    docker run --rm --entrypoint="uname" ${REGISTRY:-registry.local}/${NAMESPACE:+${NAMESPACE}/}${IMAGE} -m
    ./make_docker_image.sh -c build -D ${IMG_DIR} --tag ${TAG_PREFIX}:${ver}-${arch}
    docker push ${TAG_PREFIX}:${ver}-${arch}
done
echo "combine ${TAG_PREFIX}:${ver}"
./make_docker_image.sh -c combine --tag ${TAG_PREFIX}:${ver}

NAMESPACE=tsdelb
cat <<EOF
kubectl create namespace ${NAMESPACE}
kubectl create deployment elbprovider-deployment --image=${TAG_PREFIX}:${ver} --replicas=1 -n ${NAMESPACE}
# Requests.exceptions.HTTPError:
#  403 Client Error: Forbidden for url... so need add rbac to namespace
EOF
cat <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: elboper
rules:
  - apiGroups: [""]
    resources: ["services", "services/status", "nodes"]
    verbs: ["get", "patch", "list", "watch"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: elboper
subjects:
  - kind: ServiceAccount
    name: default
    namespace: ${NAMESPACE}
roleRef:
  kind: ClusterRole
  name: elboper
  apiGroup: rbac.authorization.k8s.io
EOF

cat<<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: elb-nsip-mapping
  namespace: ${NAMESPACE}
data:
  ns_ip.json: |
    {
      "default":"172.16.17.155",
      "kubesphere-controls-system": "172.16.17.100"
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: elbprovider
  namespace: ${NAMESPACE}
  labels:
    app: elbprovider
spec:
  selector:
    matchLabels:
      app: elbprovider
  replicas: 1
  template:
    metadata:
      labels:
        app: elbprovider
    spec:
      containers:
        - name: elbprovider
          image: ${REGISTRY:-registry.local}/${type}:${ver}
          # imagePullPolicy: IfNotPresent|Always|Never
          volumeMounts:
            - name: ns-ip-json
              mountPath: /home/johnyin/ns_ip.json
              subPath: ns_ip.json
          env:
            - name: LOG
              value: DEBUG
      volumes:
        - name: ns-ip-json
          configMap:
            name: elb-nsip-mapping
EOF
