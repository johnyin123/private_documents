#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_endian.h>
#include <bpf/bpf_tracing.h>
#include "pod_trace.h"
char LICENSE[] SEC("license") = "GPL";

struct {
    __uint(type, BPF_MAP_TYPE_RINGBUF);
    __uint(max_entries, 1 << 16);
    __uint(pinning, LIBBPF_PIN_BY_NAME);
} rb SEC(".maps");

/* Temporary storage map to hold the socket pointer until the function finishes */
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 4096);
    __type(key, u64);
    __type(value, struct sock *);
} sock_store SEC(".maps");

// 1. Hook the entry point to catch and stash the socket reference
SEC("kprobe/tcp_v4_connect") int BPF_KPROBE(tcp_v4_connect, struct sock *sk) {
    u64 pid_tgid = bpf_get_current_pid_tgid();
    /* Store the socket pointer temporarily using thread ID as key */
    bpf_map_update_elem(&sock_store, &pid_tgid, &sk, BPF_ANY);
    return 0;
}
// 2. Hook the exit point where skc_daddr is guaranteed to be populated
SEC("kretprobe/tcp_v4_connect") int BPF_KRETPROBE(tcp_v4_connect_exit, int ret) {
    u64 pid_tgid = bpf_get_current_pid_tgid();
    /* Only proceed if the connection initialization returned success (0) */
    if (ret != 0) { bpf_map_delete_elem(&sock_store, &pid_tgid); return 0; }
    struct sock **skpp = bpf_map_lookup_elem(&sock_store, &pid_tgid);
    if (!skpp) { return 0; }
    struct sock *sk = *skpp;
    bpf_map_delete_elem(&sock_store, &pid_tgid);
    struct event *el = bpf_ringbuf_reserve(&rb, sizeof(*el), 0);
    if (!el) { return 0; }
    el->cgroup_id = bpf_get_current_cgroup_id();
    el->pid = bpf_get_current_pid_tgid() >> 32;
    bpf_get_current_comm(&el->comm, sizeof(el->comm));
    // Read socket endpoints using BPF CO-RE (Compile Once - Run Everywhere)
    el->daddr = BPF_CORE_READ(sk, __sk_common.skc_daddr);
    el->dport = BPF_CORE_READ(sk, __sk_common.skc_dport);
    bpf_ringbuf_submit(el, 0);
    return 0;
}
