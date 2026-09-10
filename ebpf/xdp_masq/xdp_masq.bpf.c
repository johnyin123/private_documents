#include "xdp_masq.h"
#include "xdp_parse.h"
char LICENSE[] SEC("license") = "GPL";

#define S_PROTO(h) ((h)->protocol==IPPROTO_UDP ?  "U" : "T")
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
SEC("xdp") int xdp_nat_engine(struct xdp_md *ctx) {
    void *data = (void *)(long)ctx->data;
    void *data_end = (void *)(long)ctx->data_end;
    struct hdr_cursor nh = { .pos = data };
    struct ethhdr *eth;
    struct iphdr *iphdr = NULL;
    struct udphdr *udphdr = NULL;
    struct tcphdr *tcphdr = NULL;
    if (parse_ethhdr(&nh, data_end, &eth) != __bpf_constant_htons(ETH_P_IP)) { return XDP_PASS; }
    if (parse_iphdr(&nh, data_end, &iphdr) < 0) { return XDP_PASS; }
    if ((iphdr->protocol != IPPROTO_TCP) && (iphdr->protocol != IPPROTO_UDP) && (iphdr->protocol != IPPROTO_ICMP)) { return XDP_PASS; }
    __be16 sport = 0, dport = 0;
    switch (iphdr->protocol) {
        case IPPROTO_TCP:
            if (parse_tcphdr(&nh, data_end, &tcphdr) < 0) { return XDP_PASS; }
            sport = tcphdr->source; dport = tcphdr->dest;
            if (ipv4_pkg4local_tcp(ctx, iphdr->saddr, iphdr->daddr, sport, dport)) { return XDP_PASS; }
            break;
        case IPPROTO_UDP:
            if (parse_udphdr(&nh, data_end, &udphdr) < 0) { return XDP_PASS; }
            sport = udphdr->source; dport = udphdr->dest;
            if (ipv4_pkg4local_udp(ctx, iphdr->saddr, iphdr->daddr, sport, dport)) { return XDP_PASS; }
            break;
        case IPPROTO_ICMP:
            return XDP_PASS;
    }
    if (iphdr->daddr == public_ip) {
        struct nat_key key = { .saddr = iphdr->saddr, .sport = sport, .daddr = iphdr->daddr, .dport = dport, .protocol = iphdr->protocol, };
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
        struct nat_key key = { .saddr = iphdr->daddr, .sport = dport, .daddr = public_ip, .dport = sport, .protocol = iphdr->protocol, };
        struct nat_val *orig_cli = bpf_map_lookup_elem(&nat_map, &key);
        if (!orig_cli) {
            struct nat_val val = { .masq_ip = iphdr->saddr, .masq_port = sport, };
            bpf_map_update_elem(&nat_map, &key, &val, BPF_ANY);
            bpf_debug("SNAT (%s) %pI4:%u -> %pI4:%u => %pI4:%u", S_PROTO(iphdr), &iphdr->saddr, bpf_ntohs(sport), &public_ip, bpf_ntohs(sport), &iphdr->daddr, bpf_ntohs(dport));
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
/*
__u32 ip = 0xC0A80102; // 192.168.1.2
__u32 prefix = 24;
__u32 mask = (0xFFFFFFFF << (32 - prefix));
__u32 network_address = ip & mask; // Result: 0xC0A80100 (192.168.1.0)
if ((src_ip & mask) == network_address) {
    return XDP_DROP; // Drop traffic coming from 192.168.1.0/24
}
*/
