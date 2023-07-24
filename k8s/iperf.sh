#!/usr/bin/env bash
iperf3() {
    local replica=${1}
    local mode=${2}
    local spec=""
    case "${mode}" in
        client) spec="
    spec:
      containers:
      - name: iperf3-client
        image: docker.io/networkstatic/iperf3:latest
        imagePullPolicy: IfNotPresent
        command: ['/bin/sh', '-c', 'sleep infinity']
        # To benchmark manually: kubectl exec iperf3-clients-jlfxq -- /bin/sh -c 'iperf3 -c iperf3-server'
      terminationGracePeriodSeconds: 0
"
                ;;
        server) spec="
    spec:
      containers:
      - name: iperf3-server
        image: docker.io/networkstatic/iperf3:latest
        imagePullPolicy: IfNotPresent
        args: ['-s']
        ports:
        - containerPort: 5201
          name: server
      terminationGracePeriodSeconds: 0
"
                ;;
        *)      echo "mode server/client" >&2; return 1;;
    esac
       cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: iperf3-${mode}
  namespace: iperf3-${mode}
  labels:
    app: iperf3-${mode}
spec:
  replicas: ${replica}
  selector:
    matchLabels:
      app: iperf3${mode}
  template:
    metadata:
      labels:
        app: iperf3${mode}${spec}
EOF
}
cat <<EOF
kind: Service
apiVersion: v1
metadata:
  name: iperf3-server
  namespace: iperf3-server
  labels:
    app: iperf3-server
  annotations:
    kubesphere.io/serviceType: statelessservice
spec:
  ports:
    - name: tcp-5201
      protocol: TCP
      port: 5201
      targetPort: 5201
      nodePort: 31119
  selector:
    app: iperf3-server
    app.kubernetes.io/name: iperf3
    app.kubernetes.io/version: v1
  clusterIP: 172.16.200.119
  clusterIPs:
    - 172.16.200.119
  type: NodePort
  sessionAffinity: None
  externalTrafficPolicy: Cluster
  ipFamilies:
    - IPv4
  ipFamilyPolicy: SingleStack
EOF
main() {
    kubectl create namespace iperf3-server
    iperf3 2 server | kubectl apply -f -
    kubectl create namespace iperf3-client
    iperf3 2 client | kubectl apply -f -
    echo "gunzip -c iperf3\:latest.tar.gz | ctr --namespace k8s.io image import -"
    echo "kubectl exec -it iperf3-client-5665bdcbbd-szvhg -- /bin/sh"
    echo "benchmark manually: kubectl exec iperf3-clients-xxx -- /bin/sh -c 'iperf3 -c iperf3-server'"
    echo "kubectl exec -it <pod-name> -- iperf3 -s -p 12345"
    echo "kubectl exec -it <pod-name> -- iperf3 -c <server pod IP address> -p 12345"
    return 0
}
main "$@"
