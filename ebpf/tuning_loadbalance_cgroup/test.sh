bpftool prog load sockops.bpf.o /sys/fs/bpf/sockops type sockops pinmaps /sys/fs/bpf
bpftool cgroup attach /sys/fs/cgroup/ sock_ops pinned /sys/fs/bpf/sockops

bpftool prog load sockredir.bpf.o /sys/fs/bpf/sockredir type sk_msg map name sock_ops_map pinned /sys/fs/bpf/sock_ops_map
bpftool prog attach pinned /sys/fs/bpf/sockredir msg_verdict pinned /sys/fs/bpf/sock_ops_map

# Detach and unload the sockredir.bpf program
bpftool prog detach pinned /sys/fs/bpf/sockredir msg_verdict pinned /sys/fs/bpf/sock_ops_map
rm -f /sys/fs/bpf/sockredir
# Detach and unload the sockops.bpf program
bpftool cgroup detach /sys/fs/cgroup sock_ops pinned /sys/fs/bpf/sockops
rm -f /sys/fs/bpf/sockops
# Delete the map
rm -f /sys/fs/bpf/sock_ops_map

nginx in cgroup will more performance
