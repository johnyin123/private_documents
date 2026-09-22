#include "vmlinux.h"
#include "type_def.bpf.h"
char LICENSE[] SEC("license") = "GPL";

#ifndef AF_INET
#define AF_INET      2   /* Internet IP Protocol */
#endif

extern struct event_ring event_rb;
extern struct ssmap cookie_dump;
extern struct ssmap cookie_tcp;
//SEC("fentry/inet_sock_set_state") int BPF_PROG(inet_sock_set_state, struct sock *sk, int oldstate, int newstate) {
SEC("tp_btf/inet_sock_set_state") int BPF_PROG(sock_set_state, struct sock *sk, int oldstate, int newstate) {
    UNUSED(ctx);
    __u16 family = BPF_CORE_READ(sk, __sk_common.skc_family);
    if (family != AF_INET) { return 0; }
    __u8 protocol = BPF_CORE_READ(sk, sk_protocol);
    if (protocol != IPPROTO_TCP) { return 0; }
    __u64 cookie = bpf_get_socket_cookie(sk);
    if (!cookie) { return 0; }
    struct info *info_ptr = bpf_map_lookup_elem(&cookie_tcp, &cookie);
    if (!info_ptr) { return 0; }
    if (oldstate == BPF_TCP_SYN_SENT && newstate == BPF_TCP_CLOSE) {
        struct raw_event *e = bpf_ringbuf_reserve(&event_rb, sizeof(*e), 0);
        if (!e) { return 1; }
        e->err = BPF_CORE_READ(sk, sk_err); /* err: 111=ECONNREFUSED .. */
        __builtin_memcpy(e->comm, info_ptr->comm, sizeof(e->comm));
        e->netns_cookie = info_ptr->netns_cookie;
        e->cgroup_id = info_ptr->cgroup_id;
        e->pid = info_ptr->pid;
        bpf_debug("cookie = %llu, %s err = %d", cookie, e->comm, e->err);

        bpf_map_delete_elem(&cookie_dump, &cookie);
        bpf_map_delete_elem(&cookie_tcp, &cookie);
        e->protocol = IPPROTO_TCP;

        e->saddr = sk->__sk_common.skc_rcv_saddr;
        e->daddr = sk->__sk_common.skc_daddr;
        e->sport = sk->__sk_common.skc_num;
        e->dport = bpf_ntohs(sk->__sk_common.skc_dport); 

        e->payload_len = 0;
        bpf_ringbuf_submit(e, 0);
    }
    return 0;
}
SEC("sockops") int trace_sockops(struct bpf_sock_ops *skops) {
    if (skops->family != AF_INET) { return 1; }
    // Force the TCP state callbacks to execute
    if (skops->op == BPF_SOCK_OPS_TIMEOUT_INIT) {
        bpf_sock_ops_cb_flags_set(skops, BPF_SOCK_OPS_STATE_CB_FLAG);
        return 1;
    }
    if (skops->op == BPF_SOCK_OPS_STATE_CB) {
        __u32 old_state = skops->args[0];
        __u32 new_state = skops->args[1];
        //__u64 cookie = bpf_get_socket_cookie(skops);
        if (old_state == BPF_TCP_SYN_SENT && new_state == BPF_TCP_CLOSE) {
        }
        else if (old_state == BPF_TCP_SYN_RECV && new_state == BPF_TCP_CLOSE) {
            /* passive connect failed */
        }
        else if (old_state == BPF_TCP_SYN_RECV && new_state == BPF_TCP_LAST_ACK) {
            // Inbound Connection Failure - Phase 2 (Server Mode)
            // The handshake completed on the network, but the connection was reset/closed
            // before your application could call accept().
        }
    }
    return 1;
}
