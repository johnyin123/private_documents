#ifndef __XDP_PARSER_H_144909_4019462985__INC__
#define __XDP_PARSER_H_144909_4019462985__INC__
#ifdef __cplusplus
extern "C" {
#endif

#include <linux/if_packet.h>
#include <linux/if_ether.h>
#include <linux/in.h>
#include <linux/ip.h>
#include <linux/ipv6.h>
#include <linux/icmp.h>
#include <linux/icmpv6.h>
#include <linux/udp.h>
#include <linux/tcp.h>
#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

struct hdr_cursor {
    void *pos;
};
struct vlan_hdr {
    __be16    h_vlan_TCI;
    __be16    h_vlan_encapsulated_proto;
};
struct icmphdr_common {
    __u8        type;
    __u8        code;
    __sum16    cksum;
};

#ifndef VLAN_MAX_DEPTH
#define VLAN_MAX_DEPTH 2
#endif

#define VLAN_VID_MASK        0x0fff /* VLAN Identifier */
struct collect_vlans {
    __u16 id[VLAN_MAX_DEPTH];
};
static __always_inline int proto_is_vlan(__u16 h_proto) {
    return !!(h_proto == bpf_htons(ETH_P_8021Q) || h_proto == bpf_htons(ETH_P_8021AD));
}
/* Notice, parse_ethhdr() will skip VLAN tags, by advancing nh->pos and returns
 * next header EtherType, BUT the ethhdr pointer supplied still points to the
 * Ethernet header. Thus, caller can look at eth->h_proto to see if this was a
 * VLAN tagged packet.
 */
static __always_inline int parse_ethhdr_vlan(struct hdr_cursor *nh, void *data_end, struct ethhdr **ethhdr, struct collect_vlans *vlans) {
    struct ethhdr *eth = nh->pos;
    int hdrsize = sizeof(*eth);
    struct vlan_hdr *vlh;
    __u16 h_proto;
    int i;
    if (nh->pos + hdrsize > data_end) return -1;
    nh->pos += hdrsize;
    *ethhdr = eth;
    vlh = nh->pos;
    h_proto = eth->h_proto;
#if defined(__clang__)
    #pragma unroll
#elif defined(__GNUC__)
    #pragma GCC unroll 2
#endif
    for (i = 0; i < VLAN_MAX_DEPTH; i++) {
        if (!proto_is_vlan(h_proto))
            break;
        if (vlh + 1 > (struct vlan_hdr *)data_end)
            break;
        h_proto = vlh->h_vlan_encapsulated_proto;
        if (vlans) /* collect VLAN ids */
            vlans->id[i] = (bpf_ntohs(vlh->h_vlan_TCI) & VLAN_VID_MASK);
        vlh++;
    }
    nh->pos = vlh;
    return h_proto; /* network-byte-order */
}
static __always_inline int parse_ethhdr(struct hdr_cursor *nh, void *data_end, struct ethhdr **ethhdr) {
    /* Expect compiler removes the code that collects VLAN ids */
    return parse_ethhdr_vlan(nh, data_end, ethhdr, NULL);
}
static __always_inline int parse_ip6hdr(struct hdr_cursor *nh, void *data_end, struct ipv6hdr **ip6hdr) {
    struct ipv6hdr *ip6h = nh->pos;
    if (ip6h + 1 > (struct ipv6hdr *)data_end) return -1;
    nh->pos = ip6h + 1;
    *ip6hdr = ip6h;
    return ip6h->nexthdr;
}
static __always_inline int parse_iphdr(struct hdr_cursor *nh, void *data_end, struct iphdr **iphdr) {
    struct iphdr *iph = nh->pos;
    int hdrsize;
    if (iph + 1 > (struct iphdr *)data_end) return -1;
    hdrsize = iph->ihl * 4;
    if(hdrsize < sizeof(*iph)) return -1;
    if (nh->pos + hdrsize > data_end) return -1;
    nh->pos += hdrsize;
    *iphdr = iph;
    return iph->protocol;
}
static __always_inline int parse_icmp6hdr(struct hdr_cursor *nh, void *data_end, struct icmp6hdr **icmp6hdr) {
    struct icmp6hdr *icmp6h = nh->pos;
    if (icmp6h + 1 > (struct icmp6hdr *)data_end) return -1;
    nh->pos   = icmp6h + 1;
    *icmp6hdr = icmp6h;
    return icmp6h->icmp6_type;
}
static __always_inline int parse_icmphdr(struct hdr_cursor *nh, void *data_end, struct icmphdr **icmphdr) {
    struct icmphdr *icmph = nh->pos;
    if (icmph + 1 > (struct icmphdr *)data_end) return -1;
    nh->pos  = icmph + 1;
    *icmphdr = icmph;
    return icmph->type;
}
static __always_inline int parse_icmphdr_common(struct hdr_cursor *nh, void *data_end, struct icmphdr_common **icmphdr) {
    struct icmphdr_common *h = nh->pos;
    if (h + 1 > (struct icmphdr_common *)data_end) return -1;
    nh->pos  = h + 1;
    *icmphdr = h;
    return h->type;
}
/*
 * parse_udphdr: parse the udp header and return the length of the udp payload
 */
static __always_inline int parse_udphdr(struct hdr_cursor *nh, void *data_end, struct udphdr **udphdr) {
    int len;
    struct udphdr *h = nh->pos;
    if (h + 1 > (struct udphdr *)data_end) return -1;
    nh->pos  = h + 1;
    *udphdr = h;
    len = bpf_ntohs(h->len) - sizeof(struct udphdr);
    if (len < 0) return -1;
    return len;
}
/*
 * parse_tcphdr: parse and return the length of the tcp header
 */
static __always_inline int parse_tcphdr(struct hdr_cursor *nh, void *data_end, struct tcphdr **tcphdr) {
    int len;
    struct tcphdr *h = nh->pos;
    if (h + 1 > (struct tcphdr *)data_end) return -1;
    len = h->doff * 4;
    /* Sanity check packet field is valid */
    if(len < sizeof(*h)) return -1;
    /* Variable-length TCP header, need to use byte-based arithmetic */
    if (nh->pos + len > data_end) return -1;
    nh->pos += len;
    *tcphdr = h;
    return len;
}

static __always_inline __u16 csum_fold_helper(__u64 csum) {
    int i;
#if defined(__clang__)
    #pragma unroll
#elif defined(__GNUC__)
    #pragma GCC unroll 2
#endif
    for (i = 0; i < 4; i++) {
        if(csum >> 16) csum = (csum & 0xffff) + (csum >> 16);
    }
    return ~csum;
}
static __always_inline __u16 iph_csum(struct iphdr *iph) {
    iph->check = 0;
    unsigned long long csum = bpf_csum_diff(0, 0, (unsigned int *)iph, sizeof(struct iphdr), 0);
    return csum_fold_helper(csum);
}
#ifdef __cplusplus
}
#endif
#endif
/*
SEC("xdp") int xdp_prog(struct xdp_md *ctx) {
    void *data = (void *)(long)ctx->data;
    void *data_end = (void *)(long)ctx->data_end;
    struct hdr_cursor nh = { .pos = data };
    struct ethhdr *eth;
    struct iphdr *iphdr;
    struct ipv6hdr *ipv6hdr;
    struct udphdr *udphdr;
    struct tcphdr *tcphdr;
    int eth_type, ip_type;
    eth_type = parse_ethhdr(&nh, data_end, &eth);
    if (eth_type < 0) { return XDP_PASS; }
    if (eth_type == bpf_htons(ETH_P_IP)) {
        ip_type = parse_iphdr(&nh, data_end, &iphdr);
    } else if (eth_type == bpf_htons(ETH_P_IPV6)) {
        ip_type = parse_ip6hdr(&nh, data_end, &ipv6hdr);
    } else { return XDP_PASS; }
    if (ip_type == IPPROTO_UDP) {
        if (parse_udphdr(&nh, data_end, &udphdr) < 0) { return XDP_PASS; }
        //udphdr->dest = bpf_htons(bpf_ntohs(udphdr->dest) - 1);
    } else if (ip_type == IPPROTO_TCP) {
        if (parse_tcphdr(&nh, data_end, &tcphdr) < 0) { return XDP_PASS; }
        //tcphdr->dest = bpf_htons(bpf_ntohs(tcphdr->dest) - 1);
    }
    ...
}
*/
