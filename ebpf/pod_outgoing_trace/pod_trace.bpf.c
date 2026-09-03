#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_endian.h>
#include <bpf/bpf_tracing.h>
#include "pod_trace.h"
char LICENSE[] SEC("license") = "GPL";

struct {
    __uint(type, BPF_MAP_TYPE_RINGBUF);
    __uint(max_entries, 256 * 1024);
    /*__uint(pinning, LIBBPF_PIN_BY_NAME);*/
} rb SEC(".maps");

/* Temporary storage map to hold the socket pointer until the function finishes */
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 10240);
    __type(key, __u64);
    __type(value, struct event);
} sock_store SEC(".maps");

#ifndef AF_INET
#define AF_INET      2   /* Internet IP Protocol */
#endif
#if 1
SEC("kprobe/tcp_v4_connect") int BPF_KPROBE(tcp_v4_connect, struct sock *sk) {
#else
SEC("kprobe/tcp_v4_connect") int tcp_v4_connect(struct pt_regs *ctx) {
    struct sock *sk = (struct sock *) PT_REGS_PARM1(ctx);
#endif
    if (!sk) { return 0; }
    __u64 sk_key = (__u64)sk; // Cast socket address to u64 map key
    struct event el = {};
    el.time_consuming = bpf_ktime_get_ns();
    el.cgroup_id = bpf_get_current_cgroup_id();
    el.pid = bpf_get_current_pid_tgid() >> 32;
    bpf_get_current_comm(&el.comm, sizeof(el.comm));
    el.final_errno = 0; // Default placeholder, updated later on tracepoint exit
    bpf_map_update_elem(&sock_store, &sk_key, &el, BPF_ANY);
    return 0;
}
SEC("tracepoint/sock/inet_sock_set_state") int sock_set_state(struct trace_event_raw_inet_sock_set_state *ctx) {
    // Filter down evaluation strictly to standard IPv4 TCP transport structures
    if (ctx->protocol != IPPROTO_TCP || ctx->family != AF_INET) { return 0; }
    __u64 sk_key = (__u64)ctx->skaddr;
    struct event *el = bpf_map_lookup_elem(&sock_store, &sk_key);
    if (!el) { return 0; }
    if ((ctx->oldstate == TCP_SYN_SENT && ctx->newstate == TCP_CLOSE) || (ctx->newstate == BPF_TCP_ESTABLISHED)) {
        el->protocol = ctx->protocol;
        __builtin_memcpy(&el->saddr, ctx->saddr, sizeof(el->saddr));
        el->sport = ctx->sport;
        __builtin_memcpy(&el->daddr, ctx->daddr, sizeof(el->daddr));
        el->dport = ctx->dport;
        el->time_consuming = bpf_ktime_get_ns() - el->time_consuming;
        if (ctx->newstate == TCP_CLOSE) {
            struct sock *sk = (struct sock *)ctx->skaddr;
            int err = 0;
            bpf_probe_read_kernel(&err, sizeof(err), &sk->sk_err);
            el->final_errno = err;
        } else {
            el->final_errno = 0; // Handshake completed without issue
        }
        struct event *to_send = bpf_ringbuf_reserve(&rb, sizeof(struct event), 0);
        if (to_send) {
            *to_send = *el;
            bpf_ringbuf_submit(to_send, 0);
        }
        bpf_map_delete_elem(&sock_store, &sk_key);
    }
    return 0;
}
