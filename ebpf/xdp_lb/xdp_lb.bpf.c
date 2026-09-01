#include "xdp_parse.h"
#include "xdp_lb.h"
char _license[] SEC("license") = "GPL";

struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, MAX_CONF_ENTRIES);
    __uint(pinning, LIBBPF_PIN_BY_NAME);
    __type(key, struct key);
    __type(value, struct backend_config);
} config_map SEC(".maps");
struct {
    __uint(type, BPF_MAP_TYPE_LRU_HASH);
    __uint(max_entries, 100000);
    __type(key, struct flow_5tuple);
    __type(value, __u32); /* Stores the chosen backend index */
} session_cache SEC(".maps");
static __always_inline void set_backend_mac(struct ethhdr *eth, const struct backend_config *cfg, __u32 idx) {
    switch (idx) {
    case 0:
        __builtin_memcpy(eth->h_dest, cfg->backends[0].mac_addr, ETH_ALEN);
        break;
    case 1:
        __builtin_memcpy(eth->h_dest, cfg->backends[1].mac_addr, ETH_ALEN);
        break;
    case 2:
        __builtin_memcpy(eth->h_dest, cfg->backends[2].mac_addr, ETH_ALEN);
        break;
    case 3:
        __builtin_memcpy(eth->h_dest, cfg->backends[3].mac_addr, ETH_ALEN);
        break;
    }
}
SEC("xdp") int xdp_load_balancer(struct xdp_md *ctx) {
    void *data = (void *)(long)ctx->data;
    void *data_end = (void *)(long)ctx->data_end;
    struct hdr_cursor nh = { .pos = data };
    struct ethhdr *eth;
    struct iphdr *iphdr;
    struct udphdr *udphdr;
    struct tcphdr *tcphdr;
    int eth_type, ip_type;
    __be16 src_port = 0, dst_port = 0;
    eth_type = parse_ethhdr(&nh, data_end, &eth);
    if (eth_type < 0) { return XDP_PASS; }
    if (eth_type == bpf_htons(ETH_P_IP)) {
        ip_type = parse_iphdr(&nh, data_end, &iphdr);
    } else { return XDP_PASS; }
    if (ip_type == IPPROTO_UDP) {
        if (parse_udphdr(&nh, data_end, &udphdr) < 0) { return XDP_PASS; }
        src_port = udphdr->source;
        dst_port = udphdr->dest;
    } else if (ip_type == IPPROTO_TCP) {
        if (parse_tcphdr(&nh, data_end, &tcphdr) < 0) { return XDP_PASS; }
        src_port = tcphdr->source;
        dst_port = tcphdr->dest;
    } else { return XDP_PASS; }
    // Retrieve system configuration parameters from user-space map
    struct key key = { .ip_addr = iphdr->daddr, .port = dst_port };
    struct backend_config *lb_cfg = bpf_map_lookup_elem(&config_map, &key);
    if (!lb_cfg) return XDP_PASS;
    __u16 num_backends = lb_cfg->num;
    if (num_backends == 0 || num_backends > MAX_PEERS) { return XDP_PASS; }
    /*TODO: source hash persistent*/
    __u32 hash = iphdr->saddr ^ iphdr->daddr ^ ((__u32)src_port << 16) ^ dst_port ^ iphdr->protocol;
#if 1
    __u32 idx = hash % num_backends;
    set_backend_mac(eth, lb_cfg, idx);
#else
    __u64 idx = hash % num_backends;
    // 1. Calculate dynamic index & Clear out any signed/unsigned tracking errors using a 64-bit mask
    //__u64 idx = (__u64)(hash % num_backends)&(MAX_PEERS - 1);
    // 2. THE COMPILER FENCE: Lock down 'idx' before computing byte space sizes
    asm volatile("" : "+r"(idx));
    if (idx >= MAX_PEERS || idx >= num_backends) { return XDP_PASS; }
    __builtin_memcpy(eth->h_dest, lb_cfg->backends[idx].mac_addr, ETH_ALEN);
#endif
    /*No IP or TCP checksum recalculation needed!*/
    bpf_printk("LB-DR: VIP %pI4:%d Peer Index %d/%d\n", &key.ip_addr, bpf_ntohs(key.port), idx, num_backends);
    return XDP_TX;
}
/*
    struct flow_5tuple flow_key = { .saddr = iphdr->saddr, .daddr = iphdr->daddr, .sport = tcphdr->source, .dport = tcphdr->dest, .protocol = IPPROTO_TCP };
    __u32 *assigned_idx = bpf_map_lookup_elem(&session_cache, &flow_key);
    __u32 idx;
    if (assigned_idx) {
        idx = *assigned_idx;
    } else {
        __u32 hash = iphdr->saddr ^ tcphdr->source; // Source hash affinity seed
        //__u32 hash = iphdr->saddr ^ iphdr->daddr ^ ((__u32)src_port << 16) ^ dst_port ^ iphdr->protocol;
        idx = hash % num_backends;
        bpf_map_update_elem(&session_cache, &flow_key, &idx, BPF_ANY);
    }
    if (idx >= MAX_PEERS || idx >= num_backends) { return XDP_PASS; }
    set_backend_mac(eth, lb_cfg, idx);
*/
