#include "xdp_masq.h"
#include "xdp_parse.h"
char LICENSE[] SEC("license") = "GPL";

#define S_PROTO(h) (h->protocol==IPPROTO_UDP ?  "U" : "T")
struct nat_key {
    __be32 saddr;
    __be32 daddr;
    __be16 sport;
    __be16 dport;
    __u8 protocol;
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
/*
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
*/
static __always_inline int rewrite_ipv4_saddr_udp(struct iphdr *iph, struct udphdr *udp, __be32 new_addr) {
    __be32 old_addr = iph->saddr;
    if (old_addr == new_addr) { return 0; }
    iph->check = csum_replace32(iph->check, old_addr, new_addr);
    /* IPv4 UDP checksum == 0 means checksum disabled. */
    if (udp->check != 0) { udp->check = csum_replace32(udp->check, old_addr, new_addr); }
    iph->saddr = new_addr;
    return 0;
}
static __always_inline int rewrite_ipv4_daddr_udp(struct iphdr *iph, struct udphdr *udp, __be32 new_addr) {
    __be32 old_addr = iph->daddr;
    if (old_addr == new_addr) { return 0; }
    iph->check = csum_replace32(iph->check, old_addr, new_addr);
    if (udp->check != 0) { udp->check = csum_replace32(udp->check, old_addr, new_addr); }
    iph->daddr = new_addr;
    return 0;
}
static __always_inline int rewrite_ipv4_saddr_tcp(struct iphdr *iph, struct tcphdr *tcp, __be32 new_addr) {
    __be32 old_addr = iph->saddr;
    if (old_addr == new_addr) { return 0; }
    iph->check = csum_replace32(iph->check, old_addr, new_addr);
    /* TCP pseudo-header contains source IPv4 address */
    tcp->check = csum_replace32(tcp->check, old_addr, new_addr);
    iph->saddr = new_addr;
    return 0;
}
static __always_inline int rewrite_ipv4_daddr_tcp(struct iphdr *iph, struct tcphdr *tcp, __be32 new_addr) {
    __be32 old_addr = iph->daddr;
    if (old_addr == new_addr) { return 0; }
    iph->check = csum_replace32(iph->check, old_addr, new_addr);
    tcp->check = csum_replace32(tcp->check, old_addr, new_addr);
    iph->daddr = new_addr;
    return 0;
}
SEC("xdp") int xdp_nat_engine(struct xdp_md *ctx) {
    void *data = (void *)(long)ctx->data;
    void *data_end = (void *)(long)ctx->data_end;
    struct hdr_cursor nh = { .pos = data };
    struct ethhdr *eth;
    struct iphdr *iphdr = NULL;
    struct udphdr *udphdr = NULL;
    struct tcphdr *tcphdr = NULL;
    int eth_type = parse_ethhdr(&nh, data_end, &eth);
    switch (bpf_ntohs(eth_type)) {
        case ETH_P_IP:
            if (parse_iphdr(&nh, data_end, &iphdr)  < 0) { return XDP_PASS; }
            break;
        case ETH_P_IPV6:
        case ETH_P_ARP:
        case ETH_P_8021Q:
        default:
            return XDP_PASS;
    }
    switch (iphdr->protocol) {
        case IPPROTO_TCP:
            if (parse_tcphdr(&nh, data_end, &tcphdr) < 0) { return XDP_PASS; }
            break;
        case IPPROTO_UDP:
            // if (parse_udphdr(&nh, data_end, &udphdr) < 0) { return XDP_PASS; }
            // break;
        case IPPROTO_ICMP:
        case IPPROTO_IGMP:
        default:
            return XDP_PASS;
    }
    __be16 sport = (iphdr->protocol == IPPROTO_TCP) ? tcphdr->source : (iphdr->protocol == IPPROTO_UDP) ? udphdr->source : 0;
    __be16 dport = (iphdr->protocol == IPPROTO_TCP) ? tcphdr->dest   : (iphdr->protocol == IPPROTO_UDP) ? udphdr->dest   : 0;
    if (iphdr->daddr == public_ip) {
        struct nat_key key = { .saddr = iphdr->saddr, .daddr = iphdr->daddr, .sport = sport, .dport = dport, .protocol = iphdr->protocol, };
        struct nat_val *orig_cli = bpf_map_lookup_elem(&nat_map, &key);
        if (!orig_cli) { return XDP_PASS; }
        bpf_debug("DNAT (%s) %pI4:%d => %pI4:%d -> %pI4:%u", S_PROTO(iphdr), &iphdr->saddr, bpf_ntohs(sport), &iphdr->daddr, bpf_ntohs(dport), &orig_cli->masq_ip, bpf_ntohs(orig_cli->masq_port));
        if (tcphdr) {
            rewrite_ipv4_daddr_tcp(iphdr, tcphdr, orig_cli->masq_ip);
            //rewrite_dport_tcp(tcphdr, orig_cli->masq_port);
        }
        if (udphdr) {
            rewrite_ipv4_daddr_udp(iphdr, udphdr, orig_cli->masq_ip);
            //rewrite_dport_udp(udphdr, orig_cli->masq_port);
        }
    } else {
        //__be16 masq_port = get_masq_port();
        bpf_debug("SNAT (%s) %pI4:%u -> %pI4:%u => %pI4:%u", S_PROTO(iphdr), &iphdr->saddr, bpf_ntohs(sport), &public_ip, bpf_ntohs(sport), &iphdr->daddr, bpf_ntohs(dport));
        struct nat_key key = { .saddr = iphdr->daddr, .daddr = public_ip, .sport = dport, .dport = sport, .protocol = iphdr->protocol, };
        struct nat_val *orig_cli = bpf_map_lookup_elem(&nat_map, &key);
        if (!orig_cli) {
            struct nat_val val = { .masq_ip = iphdr->saddr, .masq_port = sport, };
            bpf_map_update_elem(&nat_map, &key, &val, BPF_ANY);
        }
        if (tcphdr) {
            rewrite_ipv4_saddr_tcp(iphdr, tcphdr, public_ip);
            //rewrite_sport_tcp(tcphdr, masq_port);
        }
        if (udphdr) {
            rewrite_ipv4_saddr_udp(iphdr, udphdr, public_ip);
            //rewrite_sport_udp(udphdr, masq_port);
        }
    }
    return fib_redirect_v4(ctx, eth, iphdr);
}
