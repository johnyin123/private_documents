echo "test app pod" && cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo-app
  labels:
    app: echo-app
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
          resources:
            requests:
              cpu: "20m"
              memory: "50Mi"
            limits:
              cpu: "100m"
              memory: 1Gi
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
curl <pod ip>:8080
curl <node ip>:32000
curl <external ip>:80
EOF
