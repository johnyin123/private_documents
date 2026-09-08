#include "xdp_masq.h"
#include "xdp_parse.h"
char LICENSE[] SEC("license") = "GPL";

struct nat_key {
    __be32 saddr;
    __be32 daddr;
    __be16 sport;
    __be16 dport;
};

struct nat_val {
    __be32 masq_ip;
    __be16 masq_port;
};

struct {
    __uint(type, BPF_MAP_TYPE_LRU_HASH);
    __uint(max_entries, 65536);
    __type(key, struct nat_key);
    __type(value, struct nat_val);
} nat_map SEC(".maps");

volatile __be32 public_ip = 0;
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(max_entries, 1);
    __type(key, __u32);
    __type(value, __u16);
} port_allocator SEC(".maps");

static __always_inline __be16 get_masq_port() {
    __u32 index = 0;
    __u16 *last_port = bpf_map_lookup_elem(&port_allocator, &index);
    if (!last_port) { return bpf_htons(50001); }
    __u16 next_port = *last_port + 1;
    if (next_port < 40000) { next_port = 40000; }
    bpf_map_update_elem(&port_allocator, &index, &next_port, BPF_ANY);
    return bpf_htons(next_port);
}
static __always_inline int rewrite_ipv4_saddr(struct iphdr *iph, struct tcphdr *tcp, __be32 new_addr) {
    __be32 old_addr = iph->saddr;
    if (old_addr == new_addr)
        return 0;
    iph->check = csum_replace32(iph->check, old_addr, new_addr);
    /* TCP pseudo-header contains source IPv4 address */
    tcp->check = csum_replace32(tcp->check, old_addr, new_addr);
    iph->saddr = new_addr;
    return 0;
}
static __always_inline int rewrite_ipv4_daddr(struct iphdr *iph, struct tcphdr *tcp, __be32 new_addr) {
    __be32 old_addr = iph->daddr;
    if (old_addr == new_addr)
        return 0;
    /* IPv4 header checksum. */
    iph->check = csum_replace32(iph->check, old_addr, new_addr);
    /* TCP pseudo-header. */
    tcp->check = csum_replace32(tcp->check, old_addr, new_addr);
    iph->daddr = new_addr;
    return 0;
}
static __always_inline int rewrite_tcp_sport(struct tcphdr *tcp, __be16 new_port) {
    __be16 old_port = tcp->source;
    if (old_port == new_port)
        return 0;
    tcp->check = csum_replace16(tcp->check, old_port, new_port);
    tcp->source = new_port;
    return 0;
}
static __always_inline int rewrite_tcp_dport(struct tcphdr *tcp, __be16 new_port) {
    __be16 old_port = tcp->dest;
    if (old_port == new_port)
        return 0;
    tcp->check = csum_replace16(tcp->check, old_port, new_port);
    tcp->dest = new_port;
    return 0;
}
static __always_inline int fib_redirect(struct xdp_md *ctx, struct ethhdr *eth, struct iphdr *iphdr) {
    struct bpf_fib_lookup fib = { .family = AF_INET, .ipv4_src = iphdr->saddr, .ipv4_dst = iphdr->daddr, .ifindex = ctx->ingress_ifindex, };
    int rc = bpf_fib_lookup(ctx, &fib, sizeof(fib), 0);
    bpf_debug("AFTER  %pI4 -> %pI4, bpf_fib_lookup = %d", &iphdr->saddr, &iphdr->daddr, rc);
    if (rc != BPF_FIB_LKUP_RET_SUCCESS) { return XDP_PASS; }
    __builtin_memcpy(eth->h_source, fib.smac, ETH_ALEN);
    __builtin_memcpy(eth->h_dest, fib.dmac, ETH_ALEN);
    return bpf_redirect(fib.ifindex, 0);
}
SEC("xdp") int xdp_nat_engine(struct xdp_md *ctx) {
    void *data = (void *)(long)ctx->data;
    void *data_end = (void *)(long)ctx->data_end;
    struct hdr_cursor nh = { .pos = data };
    struct ethhdr *eth;
    struct iphdr *iphdr = NULL;
    struct tcphdr *tcphdr = NULL;
    int ip_type = -1;
    // Ethernet
    int eth_type = parse_ethhdr(&nh, data_end, &eth);
    switch (bpf_ntohs(eth_type)) {
        case ETH_P_IP:
            ip_type = parse_iphdr(&nh, data_end, &iphdr);
            break;
        case ETH_P_IPV6:
        case ETH_P_ARP:
        case ETH_P_8021Q:
        default:
            return XDP_PASS;
    }
    switch (ip_type) {
        case IPPROTO_TCP:
            if (parse_tcphdr(&nh, data_end, &tcphdr) < 0) { return XDP_PASS; }
            break;
        case IPPROTO_UDP:
        case IPPROTO_ICMP:
        case IPPROTO_IGMP:
        default:
            return XDP_PASS;
    }
    /* DNAT */
    if (iphdr->daddr == public_ip) {
        struct nat_key key = { .saddr = iphdr->saddr, .daddr = iphdr->daddr, .sport = tcphdr->source, .dport = tcphdr->dest, };
        struct nat_val *orig_cli = bpf_map_lookup_elem(&nat_map, &key);
        if (!orig_cli) { return XDP_PASS; }
        bpf_debug("IN 0 %pI4:%d -> %pI4:%d", &iphdr->saddr, bpf_ntohs(tcphdr->source), &iphdr->daddr, bpf_ntohs(tcphdr->dest));
        rewrite_ipv4_daddr(iphdr, tcphdr, orig_cli->masq_ip);
        rewrite_tcp_dport(tcphdr, orig_cli->masq_port);
        return fib_redirect(ctx, eth, iphdr);
    }
    /* SNAT */
    bpf_debug("BEFORE %pI4:%u -> %pI4:%u", &iphdr->saddr, bpf_ntohs(tcphdr->source), &iphdr->daddr, bpf_ntohs(tcphdr->dest));
    __be16 masq_port = get_masq_port();
    struct nat_key reverse_key = { .saddr = iphdr->daddr, .daddr = public_ip, .sport = tcphdr->dest, .dport = masq_port, };
    struct nat_val reverse_val = { .masq_ip = iphdr->saddr, .masq_port = tcphdr->source, };
    bpf_map_update_elem(&nat_map, &reverse_key, &reverse_val, BPF_ANY);
    rewrite_ipv4_saddr(iphdr, tcphdr, public_ip);
    rewrite_tcp_sport(tcphdr, masq_port);
    return fib_redirect(ctx, eth, iphdr);
}
