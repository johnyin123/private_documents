protocol="http"
data_dir="data.etcd"
cluster_token="cluster-1"
nodes=(node1 node2 node3)

initial_cluster="--initial-cluster="
for n in ${nodes[@]}; do
    initial_cluster+="${n}=${protocol}://${n}:2380,"
done
initial_cluster="${initial_cluster%?}"

for n in ${nodes[@]}; do
    cat <<EOF
etcd \\
    --name=${n} \\
    --data-dir=${data_dir} \\
    --advertise-client-urls=${protocol}://${n}:2379 \\
    --listen-client-urls=${protocol}://0.0.0.0:2379 \\
    --initial-advertise-peer-urls=${protocol}://${n}:2380 \\
    --listen-peer-urls=${protocol}://0.0.0.0:2380 \\
    --initial-cluster-state=new \\
    --initial-cluster-token=${cluster_token} \\
    ${initial_cluster}
EOF
done
