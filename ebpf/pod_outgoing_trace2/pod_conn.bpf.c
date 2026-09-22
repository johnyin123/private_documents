#include "xdp_parse.h"
#include "type_def.bpf.h"
char LICENSE[] SEC("license") = "GPL";

struct event_ring event_rb SEC(".maps");
struct ssmap cookie_dump SEC(".maps");
struct ssmap cookie_tcp SEC(".maps");

SEC("cgroup/connect4") int track_connect4(struct bpf_sock_addr *ctx) {
    if (ctx->family != AF_INET) { return 1; }
    if ((ctx->protocol != IPPROTO_UDP) && (ctx->protocol != IPPROTO_TCP)) { return 1; }
    __u64 cookie = bpf_get_socket_cookie(ctx);
    if(cookie) {
        struct info e = { .netns_cookie = bpf_get_netns_cookie(ctx), .err = 0, .dualtime_ns = bpf_ktime_get_ns(), };
        if (0 == bpf_get_current_comm(&e.comm, sizeof(e.comm))) {
            bpf_map_update_elem(&cookie_dump, &cookie, &e, BPF_ANY);
        }
    }
    return 1;
}
static __always_inline bool tcp_established(struct __sk_buff *skb) {
    struct bpf_sock *sk = skb->sk;
    if (!sk) { return false; }
    // Optional: Obtain full socket context (helps verify it isn't a request/timewait sock)
    sk = bpf_sk_fullsock(sk);
    if (!sk) { return false; }
    return sk->protocol == IPPROTO_TCP && sk->state == BPF_TCP_ESTABLISHED;
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

    int payload_len = 0;
    __be16 sport = 0, dport = 0;
    __u32 absolute_payload_offset = 0;
    __u32 ip_hlen = iphdr->ihl * 4;
    __u32 ip_total_len = bpf_ntohs(iphdr->tot_len);
    switch (iphdr->protocol) {
        case IPPROTO_UDP:
            if (parse_udphdr(&nh, data_end, &udp) < 0) { return 1; }
            __u32 udp_hlen = sizeof(struct udphdr); /*always 8*/
            absolute_payload_offset = ip_hlen + udp_hlen;
            if (ip_total_len > absolute_payload_offset) {
                payload_len = ip_total_len - absolute_payload_offset;
            } else { payload_len = 0; }
            // payload_len = (void *)data_end - nh.pos;
            // absolute_payload_offset = (void *)data_end - nh.pos;
            sport = udp->source; dport = udp->dest;
            break;
        case IPPROTO_TCP:
            int tcp_hlen = parse_tcphdr(&nh, data_end, &tcp);
            if (tcp_hlen < 0) { return 1; }
            if (!tcp_established(skb)) { return 1; }
            // --- THE FIX: Derive payload length from the IP layer header ---
            if (ip_total_len > (ip_hlen + tcp_hlen)) {
                payload_len = ip_total_len - (ip_hlen + tcp_hlen);
            } else { payload_len = 0; } //Pure ACK

            // Calculate absolute byte offset where payload starts relative to skb base
            absolute_payload_offset = ip_hlen + tcp_hlen;
            sport = tcp->source; dport = tcp->dest;
            break;
    }
    __u64 cookie = bpf_get_socket_cookie(skb);
    /* packet is a kernel-generated synthetic flow with no real owner socket */
    if (!cookie) { return 1; }
    struct info *info_ptr = bpf_map_lookup_elem(&cookie_dump, &cookie);
    if (!info_ptr) { return 1; } /*only dump already get Comm*/

    // 1. Calculate raw payload length
    __u32 len = (__u32)payload_len;
    // 2. Clear zero-size and upper bound constraints sequentially for the verifier
    if (len == 0) { return 1; }
    if (len > MAX_PAYLOAD_LEN) { len = MAX_PAYLOAD_LEN; }

    struct raw_event *e = bpf_ringbuf_reserve(&event_rb, sizeof(*e), 0);
    if (!e) { return 1; }
    //*e = *info_ptr;
    __builtin_memcpy(e->comm, info_ptr->comm, sizeof(e->comm));
    e->netns_cookie = info_ptr->netns_cookie;
    e->err = info_ptr->err;
    bpf_map_delete_elem(&cookie_dump, &cookie);
    // 4. Populate your event's metadata blocks
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
    // 5. Safe kernel-space buffer copy into the ringbuf event
    // if (bpf_probe_read_kernel(e->payload, len, payload)<0) { bpf_ringbuf_discard(e, 0); return 1; }
    // --- THE FIX: Use load bytes helper with the absolute calculated offset ---
    // This helper automatically parses fragments even if data_end says 0 bytes exist
    if (bpf_skb_load_bytes(skb, absolute_payload_offset, e->payload, len) < 0) { bpf_ringbuf_discard(e, 0); return 1; }
    bpf_ringbuf_submit(e, 0);
    return 1; // Return 1 to ensure the kernel forwards the packet to the wire
}
