cat <<EOF
sysctl -w net.ipv4.conf.eth1.arp_ignore = 1
sysctl -w net.ipv4.conf.eth1.arp_announce = 2
# # worker节点可以不设置VIP，VIP并不需要由用户态程序来接收流量，直接由iptables来进行数据包转换,
# # 如果需要直接从worker节点上通过VIP访问该服务时就需要在worker节点上配置VIP
sysctl -w net.ipv4.conf.eth1.rp_filter=1
sysctl -w net.ipv4.conf.eth1.accept_local=1
EOF
echo "test app pod" && cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo-deployment
  # namespace: web
spec:
  selector:
    matchLabels:
      app: echo-app
  replicas: 1
  template:
    metadata:
      labels:
        app: echo-app
    spec:
      containers:
        - name: echo-app
          image: registry.local/hashicorp/http-echo
          args:
            - "-text=my echo app"
            - "-listen=:8080"
          env:
            - name: KEY
              value: value
          imagePullPolicy: IfNotPresent
EOF

create_svc() {
    local svc_type=${1}
    local port=${2}
    local external_ip=${3:-}
    case "${svc_type}" in
        ########################################
        NodePort|ClusterIP|LoadBalancer)
            echo "Service expose mode ${svc_type}"
            ;;
        *)  echo "Unexpected option: ${svc_type}"; exit 1;;
    esac
    cat <<EOF | kubectl apply -f -
kind: Service
apiVersion: v1
metadata:
  name: test-${svc_type}-service
spec:
  type: ${svc_type}
  selector:
    app: echo-app
  ports:
    - name: http
      protocol: TCP
      targetPort: 8080
      port: ${port}
$([ "${svc_type}" == "NodePort" ] && cat << EO_NODEPORT
      nodePort: ${port}
EO_NODEPORT
[ -z "${external_ip}" ] || cat <<EO_IP
  externalIPs:
    - ${external_ip}
EO_IP
)
EOF
}

create_svc NodePort 32000
create_svc LoadBalancer 80 172.16.0.155
create_svc ClusterIP 80 172.16.0.156

cat <<EOF
# kubectl expose deployment example --port=8765 --target-port=9376 --name=example-service --type=LoadBalancer
# # LoadBalancer not set externalips, should have a cloud-provider, like elb-cloudprovider.py
curl <pod ip>:8080
curl <node ip>:32000
curl <external ip>:80
kubectl patch svc <svc-name> -n <namespace> -p '{"spec": {"type": "LoadBalancer", "externalIPs":["<you ip>"]}}'
EOF
