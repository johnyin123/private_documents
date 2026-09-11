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
    __be32 pub_ip;
    __be16 pub_port;
};

struct {
    __uint(type, BPF_MAP_TYPE_LRU_HASH);
    __uint(max_entries, 65536);
    __type(key, struct nat_key);
    __type(value, struct nat_val);
} nat_map SEC(".maps");

volatile __be32 public_ip = 0;
const volatile __be32 network = 0;
const volatile __u32 mask = 0;
static __always_inline bool is_pub_ip(__be32 ip) {
    return ip == public_ip; //__u8 *v = bpf_map_lookup_elem(&public_ip_map, &ip);
}
static __always_inline __be32 get_pub_ip(__be32 sip, __be32 dip, __be16 sport, __be16 dport, __u8 protocol) {
    UNUSED(sip);UNUSED(dip);UNUSED(sport);UNUSED(dport);UNUSED(protocol);
    //__u32 hash = (__u32)sip ^ (__u32)dip ^ (__u32)sport ^ (__u32)dport ^ (__u32)iphdr->protocol;
    //return public_ip[hash % public_ip_count];
    return public_ip;
}
static __always_inline bool ipv4_acl(__be32 ipaddr) {
    return ((bpf_ntohl(ipaddr) & mask) == network);
}
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
    if (is_pub_ip(iphdr->daddr)) {
        struct nat_key key = { .saddr = iphdr->saddr, .sport = sport, .daddr = iphdr->daddr, .dport = dport, .protocol = iphdr->protocol, };
        struct nat_val *orig_cli = bpf_map_lookup_elem(&nat_map, &key);
        if (!orig_cli) { return XDP_PASS; }
        bpf_debug("DNAT (%s) %pI4:%d => %pI4:%d -> %pI4:%u", S_PROTO(iphdr), &iphdr->saddr, bpf_ntohs(sport), &iphdr->daddr, bpf_ntohs(dport), &orig_cli->masq_ip, bpf_ntohs(orig_cli->masq_port));
        if (tcphdr) {
            rewrite_ipv4_daddr_tcp(iphdr, tcphdr, orig_cli->masq_ip);
            rewrite_dport_tcp(tcphdr, orig_cli->masq_port);
        }
        if (udphdr) {
            rewrite_ipv4_daddr_udp(iphdr, udphdr, orig_cli->masq_ip);
            rewrite_dport_udp(udphdr, orig_cli->masq_port);
        }
    } else {
        if (!ipv4_acl(iphdr->saddr)) { return XDP_DROP; }
        __be32 pub_ip = get_pub_ip(iphdr->saddr, iphdr->daddr, sport, dport, iphdr->protocol);
        __be16 pub_port = sport; /*sport not modify*/
        struct nat_key key = { .saddr = iphdr->daddr, .sport = dport, .daddr = pub_ip, .dport = sport, .protocol = iphdr->protocol, };
        struct nat_val *orig_cli = bpf_map_lookup_elem(&nat_map, &key);
        if (!orig_cli) {
            struct nat_val val = { .masq_ip = iphdr->saddr, .masq_port = sport, .pub_ip = key.daddr, .pub_port = pub_port, };
            bpf_map_update_elem(&nat_map, &key, &val, BPF_ANY);
            bpf_debug("SNAT (%s) %pI4:%u -> %pI4:%u => %pI4:%u", S_PROTO(iphdr), &iphdr->saddr, bpf_ntohs(sport), &val.pub_ip, bpf_ntohs(val.pub_port), &iphdr->daddr, bpf_ntohs(dport));
        }
        if (tcphdr) {
            rewrite_ipv4_saddr_tcp(iphdr, tcphdr, key.daddr);
            rewrite_sport_tcp(tcphdr, pub_port);
        }
        if (udphdr) {
            rewrite_ipv4_saddr_udp(iphdr, udphdr, key.daddr);
            rewrite_sport_udp(udphdr, pub_port);
        }
    }
    return fib_redirect_v4(ctx, eth, iphdr);
}
