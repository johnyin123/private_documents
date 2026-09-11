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
#include <stdbool.h>

#ifdef DEBUG
#define bpf_debug           bpf_printk
#else
#define bpf_debug(fmt, ...) {;}
#endif

#ifndef UNUSED
#define UNUSED(x)           ((void)(x))
#endif
#ifndef ARRAY_LEN
#define ARRAY_LEN(a)  (sizeof(a)/sizeof((a)[0]))
#endif

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
    unsigned int hdrsize;
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
    struct udphdr *h = nh->pos;
    if ((void *)(h + 1) > data_end) return -1;
    nh->pos  = h + 1;
    *udphdr = h;
    unsigned int udp_len = bpf_ntohs(h->len);
    if (udp_len < sizeof(*h)) return -1;
    return udp_len - sizeof(*h);
}
/* parse_tcphdr: parse and return the length of the tcp header */
static __always_inline int parse_tcphdr(struct hdr_cursor *nh, void *data_end, struct tcphdr **tcphdr) {
    unsigned int len;
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
static __always_inline __u64 getmac(__u8 *eth_mac) {
    __u64 mac = 0;
    __builtin_memcpy(&mac, eth_mac, ETH_ALEN);
    return __builtin_bswap64(mac) >> 16;
}
static __always_inline void fast_udp_checksum_bypass(struct udphdr *udph) {
    if (udph) { udph->check = 0; }
}
static __always_inline __u16 csum_fold_helper(__u32 csum) {
    csum = (csum & 0xffff) + (csum >> 16);
    csum = (csum & 0xffff) + (csum >> 16);
    return ~csum;
}
static __always_inline __u16 csum_replace16(__u16 check, __be16 from, __be16 to) {
    __u32 csum = (~check & 0xffff);
    csum += (~from & 0xffff);
    csum += to;
    csum = (csum & 0xffff) + (csum >> 16);
    csum = (csum & 0xffff) + (csum >> 16);
    return ~csum;
}
static __always_inline __u16 csum_replace32(__u16 check, __be32 from, __be32 to) {
    __u32 csum = (~check & 0xffff);
    csum += (~((__u16)(from >> 16)) & 0xffff);
    csum += ((__u16)(to >> 16) & 0xffff);
    csum += (~((__u16)(from & 0xffff)) & 0xffff);
    csum += ((__u16)(to & 0xffff) & 0xffff);
    csum = (csum & 0xffff) + (csum >> 16);
    csum = (csum & 0xffff) + (csum >> 16);
    return ~csum;
}
static __always_inline int fib_redirect_v4(struct xdp_md *ctx, struct ethhdr *eth, struct iphdr *iphdr) {
    struct bpf_fib_lookup fib = { .family = AF_INET, .ipv4_src = iphdr->saddr, .ipv4_dst = iphdr->daddr, .ifindex = ctx->ingress_ifindex, };
    int rc = bpf_fib_lookup(ctx, &fib, sizeof(fib), BPF_FIB_LOOKUP_DIRECT);
    bpf_debug("FIB %pI4[%012llx->%012llx] -> %pI4[%012llx->%012llx], bpf_fib_lookup = %d", &iphdr->saddr, getmac(eth->h_source), getmac(fib.smac), &iphdr->daddr, getmac(eth->h_dest), getmac(fib.dmac), rc);
    if (rc != BPF_FIB_LKUP_RET_SUCCESS) { return XDP_PASS; }
    __builtin_memcpy(eth->h_source, fib.smac, ETH_ALEN);
    __builtin_memcpy(eth->h_dest, fib.dmac, ETH_ALEN);
    return bpf_redirect(fib.ifindex, 0);
}
static __always_inline int fib_redirect_v6(struct xdp_md *ctx, struct ethhdr *eth, struct ipv6hdr *ip6h) {
    struct bpf_fib_lookup fib = { .family = AF_INET6, .ifindex = ctx->ingress_ifindex, };
    __builtin_memcpy(fib.ipv6_src, &ip6h->saddr, sizeof(fib.ipv6_src));
    __builtin_memcpy(fib.ipv6_dst, &ip6h->daddr, sizeof(fib.ipv6_dst));
    int rc = bpf_fib_lookup(ctx, &fib, sizeof(fib), BPF_FIB_LOOKUP_DIRECT);
    bpf_debug("FIB %pI6c[%012llx->%012llx] -> %pI6c[%012llx->%012llx], bpf_fib_lookup = %d", &ip6h->saddr, getmac(eth->h_source), getmac(fib.smac), &ip6h->daddr, getmac(eth->h_dest), getmac(fib.dmac), rc);
    if (rc != BPF_FIB_LKUP_RET_SUCCESS) { return XDP_PASS; }
    __builtin_memcpy(eth->h_source, fib.smac, ETH_ALEN);
    __builtin_memcpy(eth->h_dest, fib.dmac, ETH_ALEN);
    return bpf_redirect(fib.ifindex, 0);
}
static __always_inline int rewrite_sport_udp(struct udphdr *udp, __be16 new_port) {
    __be16 old_port = udp->source;
    if (old_port == new_port) { return 0; }
    bpf_debug("REWRITE SPORT (U) %d -> %d", bpf_ntohs(udp->source), bpf_ntohs(new_port));
    if (udp->check != 0) { udp->check = csum_replace16(udp->check, old_port, new_port); }
    udp->source = new_port;
    return 0;
}
static __always_inline int rewrite_dport_udp(struct udphdr *udp, __be16 new_port) {
    __be16 old_port = udp->dest;
    if (old_port == new_port) { return 0; }
    bpf_debug("REWRITE DPORT (U) %d -> %d", bpf_ntohs(udp->dest), bpf_ntohs(new_port));
    if (udp->check != 0) { udp->check = csum_replace16(udp->check, old_port, new_port); }
    udp->dest = new_port;
    return 0;
}
static __always_inline int rewrite_sport_tcp(struct tcphdr *tcp, __be16 new_port) {
    __be16 old_port = tcp->source;
    if (old_port == new_port) { return 0; }
    bpf_debug("REWRITE SPORT (T) %d -> %d", bpf_ntohs(tcp->source), bpf_ntohs(new_port));
    tcp->check = csum_replace16(tcp->check, old_port, new_port);
    tcp->source = new_port;
    return 0;
}
static __always_inline int rewrite_dport_tcp(struct tcphdr *tcp, __be16 new_port) {
    __be16 old_port = tcp->dest;
    if (old_port == new_port) { return 0; }
    bpf_debug("REWRITE DPORT (T) %d -> %d", bpf_ntohs(tcp->dest), bpf_ntohs(new_port));
    tcp->check = csum_replace16(tcp->check, old_port, new_port);
    tcp->dest = new_port;
    return 0;
}
static __always_inline int rewrite_ipv4_saddr_udp(struct iphdr *iph, struct udphdr *udp, __be32 new_addr) {
    __be32 old_addr = iph->saddr;
    if (old_addr == new_addr) { return 0; }
    bpf_debug("REWRITE IPV4 SADDR (U) %pI4 -> %pI4", &iph->saddr, &new_addr);
    /* IPv4 UDP checksum == 0 means checksum disabled. */
    if (udp->check != 0) { udp->check = csum_replace32(udp->check, old_addr, new_addr); }
    iph->check = csum_replace32(iph->check, old_addr, new_addr);
    iph->saddr = new_addr;
    return 0;
}
static __always_inline int rewrite_ipv4_daddr_udp(struct iphdr *iph, struct udphdr *udp, __be32 new_addr) {
    __be32 old_addr = iph->daddr;
    if (old_addr == new_addr) { return 0; }
    bpf_debug("REWRITE IPV4 DADDR (U) %pI4 -> %pI4", &iph->daddr, &new_addr);
    if (udp->check != 0) { udp->check = csum_replace32(udp->check, old_addr, new_addr); }
    iph->check = csum_replace32(iph->check, old_addr, new_addr);
    iph->daddr = new_addr;
    return 0;
}
static __always_inline int rewrite_ipv4_saddr_tcp(struct iphdr *iph, struct tcphdr *tcp, __be32 new_addr) {
    __be32 old_addr = iph->saddr;
    if (old_addr == new_addr) { return 0; }
    bpf_debug("REWRITE IPV4 SADDR (T) %pI4 -> %pI4", &iph->saddr, &new_addr);
    /* TCP pseudo-header contains source IPv4 address */
    tcp->check = csum_replace32(tcp->check, old_addr, new_addr);
    iph->check = csum_replace32(iph->check, old_addr, new_addr);
    iph->saddr = new_addr;
    return 0;
}
static __always_inline int rewrite_ipv4_daddr_tcp(struct iphdr *iph, struct tcphdr *tcp, __be32 new_addr) {
    __be32 old_addr = iph->daddr;
    if (old_addr == new_addr) { return 0; }
    bpf_debug("REWRITE IPV4 DADDR (T) %pI4 -> %pI4", &iph->daddr, &new_addr);
    tcp->check = csum_replace32(tcp->check, old_addr, new_addr);
    iph->check = csum_replace32(iph->check, old_addr, new_addr);
    iph->daddr = new_addr;
    return 0;
}
/* from calico */
static __always_inline void ip_dec_ttl(struct iphdr *ip) {
    ip->ttl--;
    __u32 sum = ip->check;
    sum += bpf_htons(0x0100);
    ip->check = (__be16) (sum + (sum >> 16));
}
static __always_inline bool ipv4_pkg4local_tcp(void *ctx, __be32 saddr, __be32 daddr, __be16 sport, __be16 dport) {
    struct bpf_sock_tuple tuple = { .ipv4 = { .saddr = saddr, .daddr = daddr, .sport = sport, .dport = dport } };
    /* Look up if an active/listening socket exists */
    struct bpf_sock *sk = bpf_sk_lookup_tcp(ctx, &tuple, sizeof(tuple.ipv4), BPF_F_CURRENT_NETNS, 0);
    if (!sk) { return false; }
    bpf_sk_release(sk);
    return true;
}
static __always_inline bool ipv4_pkg4local_udp(void *ctx, __be32 saddr, __be32 daddr, __be16 sport, __be16 dport) {
    struct bpf_sock_tuple tuple = { .ipv4 = { .saddr = saddr, .daddr = daddr, .sport = sport, .dport = dport } };
    /* Look up if an active/bound UDP socket exists */
    struct bpf_sock *sk = bpf_sk_lookup_udp(ctx, &tuple, sizeof(tuple.ipv4), BPF_F_CURRENT_NETNS, 0);
    if (!sk) { return false; }
    bpf_sk_release(sk);
    return true;
}
static __always_inline bool ipv4_in_subnet(__be32 src_ip, __be32 network, __u32 prefix) {
    if (prefix == 0) { return true; }
    if (prefix > 32) { return false; }
    __u32 mask = prefix == 32 ? 0xFFFFFFFFU : 0xFFFFFFFFU << (32 - prefix);
    return (bpf_ntohl(src_ip) & mask) == (bpf_ntohl(network) & mask);
}
//__u32 src = bpf_ntohl(iphdr->saddr);
//if ((src & 0xFFFFFF00U) == 0xC0A80100U) { 192.168.1.0/24
//}
#ifdef __cplusplus
}
#endif
#endif
