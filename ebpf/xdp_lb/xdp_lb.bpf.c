#include "xdp_parse.h"
#include "xdp_lb.h"
char _license[] SEC("license") = "GPL";

struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, MAX_CONF_ENTRIES);
    __type(key, struct key);
    __type(value, struct backend_config);
} config_map SEC(".maps");
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
    struct tcphdr *tcphdr;
    if (parse_ethhdr(&nh, data_end, &eth) != bpf_htons(ETH_P_IP)) { return XDP_PASS; }
    if (parse_iphdr(&nh, data_end, &iphdr) != IPPROTO_TCP) { return XDP_PASS; }
    if (parse_tcphdr(&nh, data_end, &tcphdr) < 0) { return XDP_PASS; }
    // Retrieve system configuration parameters from user-space map
    struct key key = { .ip_addr = iphdr->daddr, .port = tcphdr->dest };
    struct backend_config *lb_cfg = bpf_map_lookup_elem(&config_map, &key);
    if (!lb_cfg) return XDP_PASS;
    __u16 num_backends = lb_cfg->num;
    if (num_backends == 0 || num_backends > MAX_PEERS) { return XDP_PASS; }
    /*TODO: source hash persistent*/
    __u32 hash = iphdr->daddr ^ tcphdr->dest;
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
