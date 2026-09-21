#include "vmlinux.h"
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_tracing.h>
#include "share_info.h"

#ifndef AF_INET
#define AF_INET      2   /* Internet IP Protocol */
#endif

extern struct ssmap cookie_info_map;
//SEC("fentry/inet_sock_set_state") int BPF_PROG(inet_sock_set_state, struct sock *sk, int oldstate, int newstate) {
SEC("tp_btf/inet_sock_set_state") int BPF_PROG(sock_set_state, struct sock *sk, int oldstate, int newstate) {
    UNUSED(ctx);
    __u16 family = BPF_CORE_READ(sk, __sk_common.skc_family);
    if (family != AF_INET) { return 0; }
    __u8 protocol = BPF_CORE_READ(sk, sk_protocol);
    if (protocol != IPPROTO_TCP) { return 0; }
    __u64 cookie = bpf_get_socket_cookie(sk);
    if (!cookie) { return 0; }
    struct info *info_ptr = bpf_map_lookup_elem(&cookie_info_map, &cookie);
    if (!info_ptr) { return 0; }
    if ((oldstate == BPF_TCP_SYN_SENT && newstate == BPF_TCP_CLOSE) || (newstate == BPF_TCP_ESTABLISHED)) {
        if (newstate == BPF_TCP_CLOSE) {
            info_ptr->err = BPF_CORE_READ(sk, sk_err);
            bpf_map_update_elem(&cookie_info_map, &cookie, info_ptr, BPF_ANY);
            bpf_debug("cookie = %llu, %s err = %d", cookie, info_ptr->err, info_ptr->comm);
            /* err: 111=ECONNREFUSED, 110=ETIMEDOUT... */
        } /* info_ptr->err default is 0, no need update */
        else {
            bpf_debug("cookie = %llu, %s err = %d", cookie, info_ptr->err, info_ptr->comm);
        }

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
