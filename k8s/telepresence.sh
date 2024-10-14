#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("2275dae[2024-10-14T15:10:59+08:00]:telepresence.sh")
################################################################################
REGISTRY=${REGISTRY:-}
TYPE=${TYPE:-ServiceAccount} #ServiceAccount/User
USER=${1:?usage, TYPE=[User|ServiceAccount] REGISTRY=registry.local $0 <user> [userns]}
USER_NS=${2:-${USER}-namespace}
cat<<EOF
UserAccount是给k8s外部用户使用，如运维或者集群管理人员，使用kubectl命令时用的就是UserAccount账户；UserAccount是全局性。在集群所有namespaces中，名称具有唯一性；
ServiceAccount是给运行在Pod的程序使用的身份认证，ServiceAccount仅局限它所在的namespace
EOF
log() { GREEN='\033[32m'; NC='\033[0m'; printf "[${GREEN}$(date +'%Y-%m-%dT%H:%M:%S.%2N%z')${NC}]%b\n" "---- $@"; }
log "Confirm env(5 seconds): USER=${USER}, NAMESPACE=${USER_NS}, TYPE=${TYPE}${REGISTRY:+, REGISTRY=${REGISTRY}}" && sleep 5
log "Install ${USER_NS}/telepresence"
telepresence helm install --namespace ${USER_NS} ${REGISTRY:+--set image.registry=${REGISTRY}/datawire --set image.name=tel2} --set 'managerRbac.namespaced=true' --set "managerRbac.namespaces={${USER_NS}}"

gen_client_config() {
    local user=${1}
# USER=user1
# USER_NS=test
# K8S_CA_CRT=ca.crt
# kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}'| base64 -d > ${K8S_CA_CRT}
# CLUSTER=$(kubectl config view -o jsonpath='{.clusters[0].name}')
# CLUSTER_URL=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}')
# kubectl config set-cluster ${CLUSTER} --certificate-authority=${K8S_CA_CRT} --embed-certs=true --server=${CLUSTER_URL} --kubeconfig=${USER}.kubeconfig
# kubectl config set-credentials ${USER} --client-certificate=${USER}.crt --client-key=${USER}.key --embed-certs=true --kubeconfig=${USER}.kubeconfig
# kubectl config set-context ${USER}-context --namespace=${USER_NS} --cluster=${CLUSTER} --user=${USER} --kubeconfig=${USER}.kubeconfig
# kubectl config use-context ${USER}-context --kubeconfig=${USER}.kubeconfig
    cat <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
  certificate-authority-data: $(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
  server: $(kubectl config view -o jsonpath='{.clusters[0].cluster.server}')
  name: kubernetes
contexts:
- name: ${user}-context
  context:
    cluster: kubernetes
    user: ${user}
users:
- name: ${user}
  user:
EOF
}

create_user() {
    local user=${1}
    local user_ns=${2}
    local K8SCA=/etc/kubernetes/pki/ca.crt
    local K8SKEY=/etc/kubernetes/pki/ca.key
    log "Create User ${user} if not exist"
    kubectl config get-users | grep -q "${user}" || {
        openssl genrsa -out ${user}.key 2048
        openssl req -new -key ${user}.key -subj "/CN=${user}/O=tsd.org" -out ${user}.csr
        openssl x509 -req -in ${user}.csr -CA ${K8SCA} -CAkey ${K8SKEY} -CAcreateserial -out ${user}.crt -days 365
        # 生成账号
        kubectl config set-credentials ${user} --client-certificate=${user}.crt --client-key=${user}.key --embed-certs=true
        log "Gen User config for client, ${user}@${user_ns}.config.yaml"
        gen_client_config ${user} > ${user}@${user_ns}.config.yaml
        cat <<EOF >> ${user}@${user_ns}.config.yaml
    client-certificate-data: $(cat ${user}.crt | base64 -w0)
    client-key-data: $(cat ${user}.key | base64 -w0)
# kubectl config set-context ${user}-context --namespace=${user_ns}
# kubectl config use-context ${user}-context
EOF
    }
}
create_serviceaccount() {
    local user=${1}
    local user_ns=${2}
    log "Crate ServiceAccount ${user}" 
    # kubectl get secret -n ${user_ns} | grep ${user} && return
    # kubectl create serviceaccount
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${user}
  namespace: ${user_ns}
EOF
    log "Gen ServiceAccount config for client, ${user}@${user_ns}.config.yaml"
    gen_client_config ${user} > ${user}@${user_ns}.config.yaml
    # sync && sleep 1
    cat <<EOF >> ${user}@${user_ns}.config.yaml
    token: $(kubectl get secret -n ${user_ns} $(kubectl get secret -n ${user_ns} | awk "/${user}/{print \$1}") -o jsonpath='{.data.token}' | base64 -d)
# kubectl config set-context ${user}-context --namespace=${user_ns}
# kubectl config use-context ${user}-context
EOF
}

############################################################
log "Create namespace ${USER_NS} if not exist"
kubectl create namespace ${USER_NS} &>/dev/null || true
log "Telepresence Using RBAC Authorization"
case "${TYPE}" in
    ########################################
    User)            create_user "${USER}" "${USER_NS}";;
    ServiceAccount)  create_serviceaccount "${USER}" "${USER_NS}";;
    *)               log "Unexpected TYPE: ${TYPE}"; exit 9;;
esac

log "Create ${TYPE} Role/RoleBinding"
cat <<EOF | kubectl apply -f -
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name:  telepresence-role
  namespace: ${USER_NS}
rules:
- apiGroups: ['']
  resources: ['services']
  verbs: ['get', 'list', 'watch']
- apiGroups: ['apps']
  resources: ['deployments', 'replicasets', 'statefulsets']
  verbs: ['get', 'list', 'watch']
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: telepresence-role-binding
  namespace: ${USER_NS}
subjects:
- kind: ${TYPE}
  name: ${USER}
roleRef:
  kind: Role
  name: telepresence-role
  apiGroup: rbac.authorization.k8s.io
EOF
log "Create telepresence connect for ${TYPE} ${USER}, namespace: ${USER_NS}"
cat << EOYML | kubectl apply -f -
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name:  traffic-manager-connect
  namespace: ${USER_NS}
rules:
  - apiGroups: ['']
    resources: ['pods']
    verbs: ['get', 'list', 'watch']
  - apiGroups: ['']
    resources: ['pods/portforward']
    verbs: ['create']
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: traffic-manager-connect
  namespace: ${USER_NS}
subjects:
  - kind: ${TYPE}
    name: ${USER}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  name: traffic-manager-connect
  kind: Role
EOYML
log "ALL OVER ==========================================================="
cat <<EOF
# # 不希望Traffic Manager在整个kubernetes集群中拥有权限或希望在集群中安装多个流量管理器
# # 流量管理器支持使用命名空间作用域进行安装，从而允许集群管理员限制流量管理器权限的范围。
telepresence helm install --namespace ${USER_NS} --set image.registry=registry.local/datawire --set image.name=tel2 --set 'managerRbac.namespaced=true' --set 'managerRbac.namespaces={${USER_NS}}'
# kubectl delete namespace ${USER_NS}
# telepresence helm uninstall --namespace ${USER_NS}
# # client need install systemd-resolved, apt -y install systemd-resolved
telepresence connect # --namespace ${USER_NS}
telepresence status
telepresence quit -s
EOF

: <<'EOF'
kubectl get clusterrole
kubectl describe clusterrole view
kubectl api-resources
kubectl explain <xxx>
# # 只能访问某个namespace 的普通用户
export USER=dev2@tsd.org
export USER_NS=test
export K8SCA=/etc/kubernetes/pki/ca.crt
export K8SKEY=/etc/kubernetes/pki/ca.key
# # 只能访问某个namespace 的普通用户
openssl genrsa -out ${USER}.key 2048
openssl req -new -key ${USER}.key -subj "/CN=${USER}/O=tsd.org" -out ${USER}.csr
openssl x509 -req -in ${USER}.csr -CA ${K8SCA} -CAkey ${K8SKEY} -CAcreateserial -out ${USER}.crt -days 365
# 生成账号
kubectl config set-credentials ${USER} --client-certificate=${USER}.crt --client-key=${USER}.key --embed-certs=true
# 设置上下文. 默认会保存在~/.kube/config
kubectl config set-context ${USER}-context --cluster=kubernetes --user=${USER} --namespace=${USER_NS}
kubectl config get-contexts ${USER}-context
# check error Forbidden, 授权后正常
kubectl get pods --context=${USER}-context
# kubectl config use-context ${USER}-context
# 对用户授权 can run multi times!!
cat << EOYML | tee | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role                      # 角色
metadata:
  name: tsd-role
  namespace: ${USER_NS}
rules:
  - apiGroups: ['', 'apps']     # ''代表核心api组
    resources: ['deployments', 'replicasets', 'pods']  # 用户可以操作Deployment、Pod、ReplicaSets的角色
    verbs: ['*'] # ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete']
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding               # 角色绑定
metadata:
  name: tsd-rolebinding
  namespace: ${USER_NS}
subjects:
  - kind: User
    name: ${USER}               # 目标用户
    apiGroup: ''
roleRef:
  kind: Role
  name: tsd-role                # 角色信息
  apiGroup: rbac.authorization.k8s.io # 留空字符串也可以，则使用当前的apiGroup
EOYML
EOF
