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
spec:
  replicas: ${replica}
  selector:
    matchLabels:
      app: iperf3
  template:
    metadata:
      labels:
        app: iperf3${spec}
EOF
}
main() {
    iperf3 2 server | kubectl apply -f -
    iperf3 2 client | kubectl apply -f -
    echo "gunzip -c iperf3\:latest.tar.gz | ctr --namespace k8s.io image import -"
    echo "kubectl exec -it iperf3-client-5665bdcbbd-szvhg -- /bin/sh"
    echi "benchmark manually: kubectl exec iperf3-clients-xxx -- /bin/sh -c 'iperf3 -c iperf3-server'"
    echo "kubectl exec -it <pod-name> -- iperf3 -s -p 12345"
    echo "kubectl exec -it <pod-name> -- iperf3 -c <server pod IP address> -p 12345"
    return 0
}
main "$@"
