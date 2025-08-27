#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
# nodes=(node1 node2 node3)
nodes=("${@:?$(echo "<CMD=1> CA=<ca> KEY=<key> CERT=<cert> $0 node1 ..."; exit 1;)}")
cert_ca="${CA:-}"
cert_key="${KEY:-}"
cert_cert="${CERT:-}"
data_dir="data.etcd"
cluster_token="cluster-1"
protocol="http"
[ -z "${cert_key}" ] || protocol="https"

log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }

initial_cluster="--initial-cluster="
for n in ${nodes[@]}; do
    initial_cluster+="${n}=${protocol}://${n}:2380,"
done
initial_cluster="${initial_cluster%?}"

[ -z "${CMD:-}" ] && {
    exec > >(${CMD:-sed -e 's/[a-z\-]*=/\U&/' -e 's/\s*--/ETCD_/' -e 's/-/_/' -e 's/\\//'})
}
for n in ${nodes[@]}; do
   log "# ==[${n}]==================================="
   [ -z "${CMD:-}" ] || echo 'etcd \'
   cat <<EOF
    --name=${n} \\
    --data-dir=${data_dir} \\
    --advertise-client-urls=${protocol}://${n}:2379 \\
    --listen-client-urls=${protocol}://0.0.0.0:2379 \\
    --initial-advertise-peer-urls=${protocol}://${n}:2380 \\
    --listen-peer-urls=${protocol}://0.0.0.0:2380 \\
    --initial-cluster-state=new \\
    --initial-cluster-token=${cluster_token} \\
EOF
    # # Security
    [ -z "${cert_key}" ] || cat <<EOF
    --cert-file=${cert_cert} \\
    --peer-cert-file=${cert_cert} \\
    --key-file=${cert_key} \\
    --peer-key-file=${cert_key} \\
    --trusted-ca-file=${cert_ca} \\
    --peer-trusted-ca-file=${cert_ca} \\
    --peer-client-cert-auth=true \\
EOF
    cat <<EOF
    ${initial_cluster}
EOF
done
