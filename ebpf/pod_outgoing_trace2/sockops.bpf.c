#include "vmlinux.h"
#include <bpf/bpf_core_read.h>

#define bpf_debug(fmt, ...) bpf_printk("DEBUG: " fmt, ##__VA_ARGS__)

#ifndef UNUSED
#define UNUSED(x)           ((void)(x))
#endif
#ifndef ARRAY_LEN
#define ARRAY_LEN(a)        (sizeof(a)/sizeof((a)[0]))
#endif

#ifndef AF_INET
#define AF_INET      2   /* Internet IP Protocol */
#endif

#include <bpf/bpf_tracing.h>
SEC("tp_btf/inet_sock_set_state") int BPF_PROG(sock_set_state, struct sock *sk, int oldstate, int newstate) {
    /* socket cookie，全生命周期稳定，可作全局唯一 socket ID */
    __u64 cookie = bpf_get_socket_cookie(sk);
    __u32 err = BPF_CORE_READ(sk, sk_err);
    if (oldstate == BPF_TCP_SYN_SENT && newstate == BPF_TCP_CLOSE) {
        bpf_debug("err=%d cookie=%llu %d -> %d", err, cookie, oldstate, newstate);
        /* err: 111=ECONNREFUSED, 110=ETIMEDOUT... */
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
