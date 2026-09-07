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

#ifdef DEBUG
/* cat /sys/kernel/debug/tracing/trace_pipe */
#define bpf_debug bpf_printk
#else
#define bpf_debug(fmt, ...){;}
#endif

#define likely(x) __builtin_expect(!!(x), 1)
#define unlikely(x) __builtin_expect(!!(x), 0)

struct hdr_cursor {
    void *pos;
};
struct vlan_hdr {
    __be16    h_vlan_TCI;
    __be16    h_vlan_encapsulated_proto;
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
/* parse_udphdr: parse the udp header and return the length of the udp payload */
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
/* parse_tcphdr: parse and return the length of the tcp header */
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
static __always_inline __u16 csum_fold_helper(__u32 csum) {
    csum = (csum & 0xffff) + (csum >> 16);
    return ~((csum & 0xffff) + (csum >> 16));
}
static __always_inline void ipv4_csum(void *data_start, int data_size, __u32 *csum) {
    *csum = bpf_csum_diff(0, 0, data_start, data_size, *csum);
    *csum = csum_fold_helper(*csum);
}
static __always_inline void fast_udp_checksum_bypass(struct udphdr *udph) {
    if (udph) { udph->check = 0; }
}
/*
static __always_inline __u32 csum_add(__u32 csum, __u32 addend) {
    __u32 res = csum + addend;
    return res + (res < addend);
}
static __always_inline __u16 csum_replace4(__u32 csum, __u32 from, __u32 to) {
    __u32 tmp = csum_add(~csum, ~from);
    return csum_fold_helper(csum_add(tmp, to));
}
static __always_inline __u16 csum_replace16(__u32 csum, __u32 *from, __u32 *to) {
    __u32 diff[] = { ~from[0], ~from[1], ~from[2], ~from[3], to[0], to[1], to[2], to[3], };
    csum = bpf_csum_diff(0, 0, diff, sizeof(diff), ~csum);
    return csum_fold_helper(csum);
}

__be32 addr = iph->saddr;
iph->saddr = nat_addr;
iph->check = csum_replace4((__u32)iph->check, addr, nat_addr);

struct in6_addr *addr, struct in6_addr *nat_addr
tcph->check = csum_replace16((__u32)tcph->check, addr->in6_u.u6_addr32, nat_addr->in6_u.u6_addr32);
udph->check = csum_replace16((__u32)udph->check, addr->in6_u.u6_addr32, nat_addr->in6_u.u6_addr32);

tcph->check = csum_replace4((__u32)tcph->check, addr, nat_addr);
udph->check = csum_replace4((__u32)udph->check, addr, nat_addr);
*/

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
    struct iphdr *iphdr = NULL;
    struct ipv6hdr *ipv6hdr = NULL;
    struct udphdr *udphdr = NULL;
    struct tcphdr *tcphdr = NULL;
    int ip_type = -1;
    // Ethernet
    int eth_type = parse_ethhdr(&nh, data_end, &eth);
    switch (bpf_ntohs(eth_type)) {
        case ETH_P_IP:
            ip_type = parse_iphdr(&nh, data_end, &iphdr);
            break;
        case ETH_P_IPV6:
            ip_type = parse_ip6hdr(&nh, data_end, &ipv6hdr);
            break;
        case ETH_P_ARP:
        case ETH_P_8021Q:
        default:
            return XDP_PASS;
    }
    switch (ip_type) {
        case IPPROTO_TCP:
            if (parse_tcphdr(&nh, data_end, &tcphdr) < 0) { return XDP_PASS; }
            if (iphdr) { bpf_debug("TCP: %pI4:%u -> %pI4:%u", &iphdr->saddr, bpf_ntohs(tcphdr->source), &iphdr->daddr, bpf_ntohs(tcphdr->dest)); }
            if (ipv6hdr) { bpf_debug("TCP: %pI6:%u -> %pI6:%u", &ipv6hdr->saddr, bpf_ntohs(tcphdr->source), &ipv6hdr->daddr, bpf_ntohs(tcphdr->dest)); }
            break;
        case IPPROTO_UDP:
            if (parse_udphdr(&nh, data_end, &udphdr) < 0) { return XDP_PASS; }
            break;
        case IPPROTO_ICMP:
        case IPPROTO_IGMP:
        default:
            return XDP_PASS;
    }
    // __u16 src_port = (tcphdr) ? tcphdr->source : (udphdr) ? udphdr->source : 0;
    // __u16 dst_port = (tcphdr) ? tcphdr->dest : (udphdr) ? udphdr->dest : 0;
#if defined(DPORT_TEST)
    if (tcphdr && (iphdr || ipv6hdr)) {
        __u32 csum_diff = ~tcphdr->dest + bpf_htons(80);
        tcphdr->dest = bpf_htons(80);
        __u32 new_tcp_csum = bpf_ntohs(tcphdr->check) + csum_diff;
        new_tcp_csum = (new_tcp_csum & 0xFFFF) + (new_tcp_csum >> 16);
        tcphdr->check = bpf_htons(new_tcp_csum);
        if (iphdr) {
            iphdr->check = 0;
            __u32 csum = 0; ipv4_csum(iphdr, iphdr->ihl * 4, &csum); iphdr->check = csum;
        }
    }
    if (udphdr && (iphdr || ipv6hdr)) {
        udphdr->dest = bpf_htons(81);
        // UDP, setting the checksum to 0 forces the receiving OS skip validation entirely.
        fast_udp_checksum_bypass(udphdr);
    }
#endif
#if defined(DADDR_TEST)
    if (iphdr) {
        iphdr->daddr = bpf_htonl(0xC0A80164);
        iphdr->check = 0;
        __u32 csum = 0; ipv4_csum(iphdr, sizeof(struct iphdr), &csum); iphdr->check = csum;
    }
    if (ipv6hdr) {
        struct in6_addr old_daddr = ipv6hdr->daddr;
        ipv6hdr->daddr.s6_addr32[0] = bpf_htonl(0x20010db8);
        ipv6hdr->daddr.s6_addr32[1] = 0;
        ipv6hdr->daddr.s6_addr32[2] = 0;
        ipv6hdr->daddr.s6_addr32[3] = bpf_htonl(0x00000001);
        // IPv6 has NO header checksum field to update here!
        if (tcphdr) {
            __u32 csum_diff = bpf_csum_diff((__be32 *)&old_daddr, 16, (__be32 *)&ipv6hdr->daddr, 16, 0);
            __u32 new_tcp_csum = (__u32)(~bpf_ntohs(tcphdr->check) & 0xFFFF) + csum_diff;
            tcphdr->check = bpf_htons(csum_fold_helper(new_tcp_csum));
        }
        fast_udp_checksum_bypass(udphdr);
    }
#endif
    //IPv6 has NO header checksum
    return XDP_PASS;
}
*/
