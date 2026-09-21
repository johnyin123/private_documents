#include "vmlinux.h"
#include <bpf/bpf_core_read.h>

#ifdef DEBUG
#define bpf_debug(fmt, ...) bpf_printk("DEBUG: " fmt, ##__VA_ARGS__)
#else
#define bpf_debug(fmt, ...) do { } while (0)
#endif

#ifndef UNUSED
#define UNUSED(x)           ((void)(x))
#endif
#ifndef ARRAY_LEN
#define ARRAY_LEN(a)        (sizeof(a)/sizeof((a)[0]))
#endif

#ifndef AF_INET
#define AF_INET      2   /* Internet IP Protocol */
#endif

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
            // 1. Get the bpf_sock pointer from the context
            struct bpf_sock *sk = skops->sk;
            if (!sk) return 1;
            // 2. Cast it to the true internal kernel 'struct sock' via CO-RE
            struct sock *kernel_sk = (struct sock *)sk;
            // 3. Read the internal error code (sk_err)
            int error_code = 0;
            bpf_core_read(&error_code, sizeof(error_code), &kernel_sk->sk_err);
            if (error_code > 0) {
                // error_code matches Linux errnos:
                // 111 -> ECONNREFUSED (Connection refused)
                // 110 -> ETIMEDOUT (Connection timed out)
                bpf_debug("Connection failed. Internal sk_err: %d\n", error_code);
            }
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
