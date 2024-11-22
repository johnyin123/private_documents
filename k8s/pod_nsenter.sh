cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: util-linux
spec:
  hostPID: true
  containers:
  - name: nginx
    image: registry.local/debian:bookworm
    securityContext:
      privileged: true
    command:
    - /usr/bin/busybox
    - sleep
    - infinity
EOF
echo "kubectl exec util-linux -- nsenter --mount=/proc/1/ns/mnt -- bash -c 'ip a'"
