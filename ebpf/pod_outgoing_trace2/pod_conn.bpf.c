#include "pod_conn.h"
#include "xdp_parse.h"
char LICENSE[] SEC("license") = "GPL";
struct {
    __uint(type, BPF_MAP_TYPE_RINGBUF);
    __uint(max_entries, 1 << 16);
} event_rb SEC(".maps");

struct info {
    __u64 netns_cookie;
    char comm[COMM_SIZE];
};
struct {
    __uint(type, BPF_MAP_TYPE_LRU_HASH);
    __uint(max_entries, 65536);
    __type(key, __u64);   // Socket Cookie
    __type(value, struct info);
} cookie_info_map SEC(".maps");
SEC("cgroup/connect4") int track_connect4(struct bpf_sock_addr *ctx) {
    if (ctx->family != AF_INET) { return 1; }
    if ((ctx->protocol != IPPROTO_UDP) && (ctx->protocol != IPPROTO_TCP)) { return 1; }
    __u64 cookie = bpf_get_socket_cookie(ctx);
    if(cookie) {
        struct info e = { .netns_cookie = bpf_get_netns_cookie(ctx), };
        if (0 == bpf_get_current_comm(&e.comm, sizeof(e.comm))) {
            bpf_map_update_elem(&cookie_info_map, &cookie, &e, BPF_ANY);
        }
    }
    return 1;
}
SEC("cgroup_skb/egress") int trace_conn(struct __sk_buff *skb) {
    /*kernel verifier allows Direct Packet Access, when cgroup_skb.disallow in SEC("socket") socketfilter*/
    void *data = (void *)(long)skb->data;
    void *data_end = (void *)(long)skb->data_end;
    struct hdr_cursor nh = { .pos = data };
    if (skb->protocol != __bpf_constant_htons(ETH_P_IP)) { return 1; }
    struct iphdr *iphdr = NULL;
    struct udphdr *udp = NULL;
    struct tcphdr *tcp = NULL;
    if (parse_iphdr(&nh, data_end, &iphdr) < 0) { return 1; }
    if ((iphdr->protocol != IPPROTO_UDP) && (iphdr->protocol != IPPROTO_TCP)) { return 1; }
    if (is_fragmented(iphdr)) { return 1; }
    void *payload = NULL;
    int payload_len = 0;
    __be16 sport = 0, dport = 0;
    switch (iphdr->protocol) {
        case IPPROTO_UDP:
            if ((payload_len = parse_udphdr(&nh, data_end, &udp)) < 0) { return 1; }
            payload = nh.pos;
            sport = udp->source; dport = udp->dest;
            break;
        case IPPROTO_TCP:
            if ((payload_len = parse_tcphdr(&nh, data_end, &tcp) < 0)) { return 1; }
            payload = (void *)(long)tcp + payload_len;
            payload_len = data_end - payload;
            sport = tcp->source; dport = tcp->dest;
            break;
    }
    __u64 cookie = bpf_get_socket_cookie(skb);
    /* packet is a kernel-generated synthetic flow with no real owner socket */
    if (!cookie) { return 1; }
    struct info *info_ptr = bpf_map_lookup_elem(&cookie_info_map, &cookie);
    if (!info_ptr) { return 1; } /*only dump already get Comm*/
    // 1. Calculate raw payload length
    __u32 len = min((__u32)payload_len, MAX_PAYLOAD_LEN);
    // 2. Clear zero-size and upper bound constraints sequentially for the verifier
    if (len == 0) { return 1; }
    if (len > MAX_PAYLOAD_LEN) { return 1; }

    struct raw_event *e = bpf_ringbuf_reserve(&event_rb, sizeof(*e), 0);
    if (!e) { return 1; }
    //*e = *info_ptr;
    if (info_ptr) {
        __builtin_memcpy(e->comm, info_ptr->comm, sizeof(e->comm)); 
        e->netns_cookie = info_ptr->netns_cookie;
    }
    else { __builtin_memset(e->comm, 0, sizeof(e->comm)); e->netns_cookie = 0; }
    // 4. Final safety guard check against packet structural bounds before copying
    if (payload + len > data_end) { bpf_ringbuf_discard(e, 0); return 1; }
    // 5. Populate your event's metadata blocks
    //e->cgroup_id = bpf_get_current_cgroup_id(); // Fully working in cgroup_skb!
    e->cgroup_id = bpf_skb_cgroup_id(skb);
    __u64 pid_tgid = bpf_get_current_pid_tgid();
    e->pid = pid_tgid >> 32;
    e->protocol = iphdr->protocol;
    e->saddr = iphdr->saddr;
    e->daddr = iphdr->daddr;
    e->sport = bpf_ntohs(sport);
    e->dport = bpf_ntohs(dport);
    e->payload_len = len;
    // 6. Safe kernel-space buffer copy into the ringbuf event
    bpf_probe_read_kernel(e->payload, len, payload);
    bpf_ringbuf_submit(e, 0);
    return 1; // Return 1 to ensure the kernel forwards the packet to the wire
}
SEC("sockops") int trace_sockops(struct bpf_sock_ops *skops) {
    if (skops->family != AF_INET) { return 1; }
    // Force the TCP state callbacks to execute
    if (skops->op == BPF_SOCK_OPS_TIMEOUT_INIT) {
        bpf_sock_ops_cb_flags_set(skops, BPF_SOCK_OPS_STATE_CB_FLAG);
        return 1;
    }
    if (skops->op == BPF_SOCK_OPS_STATE_CB) {
        //__u32 old_state = skops->args[0];
        __u32 new_state = skops->args[1];
        if (new_state == BPF_TCP_ESTABLISHED) {
            //__u64 cookie = bpf_get_socket_cookie(skops);
            //bpf_debug("sockops FIRST OUTGOING cookie=%llu, op=%d", cookie, skops->op);
        }
    }
    return 1;
} 
