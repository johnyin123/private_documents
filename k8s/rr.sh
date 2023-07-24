kubectl get nodes -o wide
# choose some nodes as reflector nodes
command -v calicoctl &> /dev/null || { exit 1; }
calicoctl node status || true
# # Configure BGP Peering
RR_LABEL=route-reflector
# # # Add peering between the RouteReflectors themselves.
cat <<EOF | calicoctl apply -f -
kind: BGPPeer
apiVersion: projectcalico.org/v3
metadata:
  name: rr-to-rr
spec:
  nodeSelector: has(${RR_LABEL})
  peerSelector: has(${RR_LABEL})
EOF

cat <<EOF | calicoctl apply -f -
kind: BGPPeer
apiVersion: projectcalico.org/v3
metadata:
  name: peer-to-rr
spec:
  nodeSelector: !has(${RR_LABEL})
  peerSelector: has(${RR_LABEL})
EOF
nodes=(srv150 srv151)
for node in  ${nodes[@]}; do
calicoctl patch node ${node} -p '{"spec": {"bgp": {"routeReflectorClusterID": "224.0.0.1"}}}'
kubectl label node ${node} ${RR_LABEL}=true
done

# # Disable node-to-node Mesh
ASNUMBER=63401
calicoctl get bgpconfig default || true
cat <<EOF | calicoctl create -f -
apiVersion: projectcalico.org/v3
kind: BGPConfiguration
metadata:
  name: default
spec:
  logSeverityScreen: Info
  nodeToNodeMeshEnabled: false
  asNumber: ${ASNUMBER}
EOF
calicoctl patch bgpconfiguration default -p '{"spec": {"nodeToNodeMeshEnabled": false}}'
# # modify asnumber
# calicoctl patch bgpconfiguration default -p '{"spec": {"asNumber": "64513"}}'
# # on non reflector node run:
calicoctl node status || true
# for ip in $(ip r | grep bird | awk '{ print $1 }' | grep -v blackhole ); do ping -W1 -c1 ${ip%/*} &>/dev/null && echo "${ip} OK" || echo "${ip} ERR"; done
