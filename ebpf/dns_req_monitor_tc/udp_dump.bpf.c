#include "udp_dump.h"
#include "xdp_parse.h"
#include <linux/pkt_cls.h>
char LICENSE[] SEC("license") = "GPL";
struct {
    __uint(type, BPF_MAP_TYPE_PERF_EVENT_ARRAY);
    __uint(key_size, sizeof(__u32));
    __uint(value_size, sizeof(__u32));
} events SEC(".maps");

const volatile __be16 udp_port = 0x3500; /*network order, 53*/
struct info {
    __u64 cgroup_id;
    __u32 pid;
};
struct {
    __uint(type, BPF_MAP_TYPE_LRU_HASH);
    __uint(max_entries, 65536);
    __type(key, __u64);   // Socket Cookie
    __type(value, struct info);
} cookie_pid_map SEC(".maps");
static __always_inline void save_socket_pid(void *ctx) {
    __u64 pid_tgid = bpf_get_current_pid_tgid();
    struct info info = {
        .pid = pid_tgid >> 32,
        .cgroup_id = bpf_get_current_cgroup_id(),
    };
    __u64 cookie = bpf_get_socket_cookie(ctx);
    bpf_map_update_elem(&cookie_pid_map, &cookie, &info, BPF_ANY);
}
//SEC("cgroup/sock_create") int track_sock_create(struct bpf_sock *ctx) {
SEC("cgroup/connect4") int track_connect4(struct bpf_sock_addr *ctx) {
    save_socket_pid(ctx);
    return 1;
}
// SEC("cgroup/connect6") int track_connect6(struct bpf_sock_addr *ctx) {
//     save_socket_pid(ctx);
//     return 1;
// }
// SEC("cgroup/sendmsg4") int track_sendmsg4(struct bpf_sock_addr *ctx) {
//     save_socket_pid(ctx);
//     return 1;
// }
// SEC("cgroup/sendmsg6") int track_sendmsg6(struct bpf_sock_addr *ctx) {
//     save_socket_pid(ctx);
//     return 1;
// }
static __always_inline int trace_dns(struct __sk_buff *skb, __u8 direction) {
    UNUSED(direction);
    void *data = (void *)(long)skb->data;
    void *data_end = (void *)(long)skb->data_end;
    struct hdr_cursor nh = { .pos = data };
    struct ethhdr *eth = NULL;
    struct iphdr *iphdr = NULL;
    struct udphdr *udphdr = NULL;
    if (parse_ethhdr(&nh, data_end, &eth) != __bpf_constant_htons(ETH_P_IP)) { return TC_ACT_OK; }
    if (parse_iphdr(&nh, data_end, &iphdr) < 0) { return TC_ACT_OK; }
    /* Ignore non-first IPv4 fragments. The first fragment can contain the UDP header. */
    //if (bpf_ntohs(iphdr->frag_off) & 0x1fff) { return TC_ACT_OK; }
    if (is_fragmented(iphdr)) { return TC_ACT_OK; }
    if (iphdr->protocol != IPPROTO_UDP) { return TC_ACT_OK; }
    if (parse_udphdr(&nh, data_end, &udphdr) < 0) { return TC_ACT_OK; }
    if (udphdr->dest != udp_port) { return TC_ACT_OK; }
    __u32 udp_len = bpf_ntohs(udphdr->len);
    if (udp_len < sizeof(*udphdr)) { return TC_ACT_OK; }
    bpf_debug("DNS_REQ (U) %pI4:%d -> %pI4:%d", &iphdr->saddr, bpf_ntohs(udphdr->source), &iphdr->daddr, bpf_ntohs(udphdr->dest));
    __u64 cookie = bpf_get_socket_cookie(skb);
    // 3. Look up the matching PID from our tracked map
    __u32 pid = 0;
    __u64 cgroup_id = 0;
    struct info *info_ptr = bpf_map_lookup_elem(&cookie_pid_map, &cookie);
    if (info_ptr) { pid = info_ptr->pid; cgroup_id = info_ptr->cgroup_id; }
    /////////////////////////////////
    // 1. Calculate raw DNS payload length (UDP length minus 8 bytes header)
    __u32 dns_len = bpf_ntohs(udphdr->len) - sizeof(struct udphdr);
    __u32 len = min(dns_len, MAX_PAYLOAD_LEN);
    // 2. Clear zero-size and upper bound constraints sequentially for the verifier
    if (len == 0) { return TC_ACT_OK; }
    if (len > MAX_PAYLOAD_LEN) { return TC_ACT_OK; }
    // 3. Pin down the payload address (the position immediately following the UDP header)
    void *dns_payload = nh.pos;
    // 4. Final safety guard check against packet structural bounds before copying
    if (dns_payload + len > data_end) { return TC_ACT_OK; }
    // 5. Populate your event's metadata blocks
    struct dns_raw_event event = {
        .cgroup_id = cgroup_id,
        .pid = pid,
        .ifindex = skb->ifindex,
        .saddr = iphdr->saddr,
        .daddr = iphdr->daddr,
        .sport = bpf_ntohs(udphdr->source),
        .dport = bpf_ntohs(udphdr->dest),
        .payload_len = len,
    };
    // 6. Safe kernel-space buffer copy into the ringbuf event
    bpf_probe_read_kernel(event.payload, len, dns_payload);
    /////////////////////////////////
    bpf_perf_event_output(skb, &events, BPF_F_CURRENT_CPU, &event, sizeof(event));
    return TC_ACT_OK;
}
SEC("tc/ingress") int handle_ingress(struct __sk_buff *skb) {
    return trace_dns(skb, 0);
}
SEC("tc/egress") int handle_egress(struct __sk_buff *skb) {
    return trace_dns(skb, 1);
}
