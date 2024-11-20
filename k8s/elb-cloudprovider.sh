#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
################################################################################
export IMAGE=python:bookworm  # BASE IMAGE
# export REGISTRY=registry.local
# export NAMESPACE=
ARCH=(amd64 arm64)
APP_NAME=elbprovider
APP_VER=0.1
for APP_ARCH in ${ARCH[@]}; do
    IMG_DIR=${APP_NAME}-${APP_ARCH}
    TAG_PREFIX=${REGISTRY:-registry.local}/${NAMESPACE:+${NAMESPACE}/}${APP_NAME}
    ./make_docker_image.sh -c ${APP_NAME} --arch ${APP_ARCH} -D ${IMG_DIR}
    ################################################
    mkdir -p ${IMG_DIR}/docker/home/johnyin/
    cp elb-cloudprovider.py ${IMG_DIR}/docker/home/johnyin/elb_provider.py
    cat <<EOF > ${IMG_DIR}/docker/run_command
CMD=/usr/sbin/runuser
ARGS="-u johnyin -- python3 /home/johnyin/elb_provider.py"
EOF
    cat <<EOF > ${IMG_DIR}/docker/build.run
apt update && apt -y install python3-kubernetes
chown johnyin:johnyin /home/johnyin/* -R
/usr/sbin/runuser -u johnyin -- /bin/bash -s << EOSHELL
    # python3 -m venv /home/johnyin/myvenv
    # source /home/johnyin/myvenv/bin/activate
    # which python
    python3 --version
    python3 -c "import kubernetes" && echo "kubernetes package OK" || echo "kubernetes package ERROR"
EOSHELL
EOF
    (cd ${IMG_DIR} && docker build --no-cache --force-rm --network=br-ext -t ${TAG_PREFIX}:${APP_VER}-${APP_ARCH} .)
    docker push  ${TAG_PREFIX}:${APP_VER}-${APP_ARCH}
done
echo "combine ${TAG_PREFIX}:${APP_VER}"
./make_docker_image.sh -c combine --tag ${TAG_PREFIX}:${APP_VER}

NAMESPACE=testns
cat <<EOF
kubectl create namespace ${NAMESPACE}
kubectl create deployment elbprovider-deployment --image=${TAG_PREFIX}:${APP_VER} --replicas=1 -n ${NAMESPACE}
# Requests.exceptions.HTTPError                                        :
#  403 Client Error: Forbidden for url... so need add rbac to namespace
EOF
cat <<EOF
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

echo  "use configmap as ns_ip.json"
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
         "testns": "1.2.3.4"
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
          image: ${TAG_PREFIX}:${APP_VER}
          volumeMounts:
            - name: ns-ip-json
              mountPath: /home/johnyin/ns_ip.json
              subPath: ns_ip.json
          env:
            - name: KEY
              value: value
      volumes:
        - name: ns-ip-json
          configMap:
            name: elb-nsip-mapping
EOF
