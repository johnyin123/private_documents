#ifndef __XDPLB_BPF_H_164556_2726077384__INC__
#define __XDPLB_BPF_H_164556_2726077384__INC__

/* Header cursor to keep track of current parsing position */
struct hdr_cursor {
    void *pos;
};

/*
 * Struct icmphdr_common represents the common part of the icmphdr and icmp6hdr
 * structures.
 */
struct icmphdr_common {
    __u8    type;
    __u8    code;
    __sum16 cksum;
};

#ifndef memcpy
#define memcpy(dest, src, n) __builtin_memcpy((dest), (src), (n))
#endif

#ifndef VLAN_MAX_DEPTH
#define VLAN_MAX_DEPTH 2
#endif

#ifndef ETH_P_8021Q
#define ETH_P_8021Q    0x8100          /* 802.1Q VLAN Extended Header  */
#endif

#ifndef ETH_P_8021AD
#define ETH_P_8021AD    0x88A8          /* 802.1ad Service VLAN        */
#endif

#ifndef ETH_ALEN
#define ETH_ALEN    6        /* Octets in one ethernet addr     */
#endif

#ifndef ETH_P_IP
#define ETH_P_IP    0x0800        /* Internet Protocol packet    */
#endif

#ifndef ETH_P_IPV6
#define ETH_P_IPV6    0x86DD        /* IPv6 over bluebook        */
#endif

#ifndef IPPROTO_ICMPV6
#define IPPROTO_ICMPV6        58    /* ICMPv6            */
#endif

#ifndef ICMP_ECHO
#define ICMP_ECHO        8    /* Echo Request            */
#endif

#ifndef ICMP_ECHOREPLY
#define ICMP_ECHOREPLY        0    /* Echo Reply            */
#endif

#ifndef ICMPV6_ECHO_REQUEST
#define ICMPV6_ECHO_REQUEST        128
#endif

#ifndef ICMPV6_ECHO_REPLY
#define ICMPV6_ECHO_REPLY        129
#endif

#define VLAN_VID_MASK        0x0fff /* VLAN Identifier */
/* Struct for collecting VLANs after parsing via parse_ethhdr_vlan */
struct collect_vlans {
    __u16 id[VLAN_MAX_DEPTH];
};

static __always_inline int proto_is_vlan(__u16 h_proto)
{
    return !!(h_proto == bpf_htons(ETH_P_8021Q) || h_proto == bpf_htons(ETH_P_8021AD));
}

/* Notice, parse_ethhdr() will skip VLAN tags, by advancing nh->pos and returns
 * next header EtherType, BUT the ethhdr pointer supplied still points to the
 * Ethernet header. Thus, caller can look at eth->h_proto to see if this was a
 * VLAN tagged packet.
 */
static __always_inline int parse_ethhdr_vlan(struct hdr_cursor *nh, void *data_end, struct ethhdr **ethhdr, struct collect_vlans *vlans)
{
    struct ethhdr *eth = nh->pos;
    int hdrsize = sizeof(*eth);
    struct vlan_hdr *vlh;
    __u16 h_proto;
    int i;
    /* Byte-count bounds check; check if current pointer + size of header is after data_end. */
    if (nh->pos + hdrsize > data_end)
        return -1;
    nh->pos += hdrsize;
    *ethhdr = eth;
    vlh = nh->pos;
    h_proto = eth->h_proto;

    /* Use loop unrolling to avoid the verifier restriction on loops;
     * support up to VLAN_MAX_DEPTH layers of VLAN encapsulation.
     */
    #pragma unroll
    for (i = 0; i < VLAN_MAX_DEPTH; i++) {
        if (!proto_is_vlan(h_proto))
            break;

        if ((void *)(vlh + 1) > data_end)
            break;

        h_proto = vlh->h_vlan_encapsulated_proto;
        if (vlans) /* collect VLAN ids */
            vlans->id[i] = (bpf_ntohs(vlh->h_vlan_TCI) & VLAN_VID_MASK);
        vlh++;
    }

    nh->pos = vlh;
    return h_proto; /* network-byte-order */
}

static __always_inline int parse_icmphdr_common(struct hdr_cursor *nh, void *data_end, struct icmphdr_common **icmphdr)
{
    struct icmphdr_common *h = nh->pos;
    if ((void *)(h + 1) > data_end)
        return -1;
    nh->pos  = h + 1;
    *icmphdr = h;
    return h->type;
}

static __always_inline int parse_ip6hdr(struct hdr_cursor *nh, void *data_end, struct ipv6hdr **ip6hdr)
{
    struct ipv6hdr *ip6h = nh->pos;

    /* Pointer-arithmetic bounds check; pointer +1 points to after end of
     * thing being pointed to. We will be using this style in the remainder
     * of the tutorial.
     */
    if ((void *)(ip6h + 1) > data_end)
        return -1;

    nh->pos = ip6h + 1;
    *ip6hdr = ip6h;

    return ip6h->nexthdr;
}

static __always_inline int parse_iphdr(struct hdr_cursor *nh, void *data_end, struct iphdr **iphdr)
{
    struct iphdr *iph = nh->pos;
    int hdrsize;

    if ((void *)(iph + 1) > data_end)
        return -1;

    hdrsize = iph->ihl * 4;
    /* Sanity check packet field is valid */
    if(hdrsize < sizeof(*iph))
        return -1;

    /* Variable-length IPv4 header, need to use byte-based arithmetic */
    if (nh->pos + hdrsize > data_end)
        return -1;

    nh->pos += hdrsize;
    *iphdr = iph;

    return iph->protocol;
}

/*parse_tcphdr: parse and return the length of the tcp header */
static __always_inline int parse_tcphdr(struct hdr_cursor *nh, void *data_end, struct tcphdr **tcphdr)
{
    int len;
    struct tcphdr *h = nh->pos;
    if ((void *)(h + 1) > data_end)
        return -1;
    len = h->doff * 4;
    /* Sanity check packet field is valid */
    if(len < sizeof(*h))
        return -1;
    /* Variable-length TCP header, need to use byte-based arithmetic */
    if (nh->pos + len > data_end)
        return -1;
    nh->pos += len;
    *tcphdr = h;
    return len;
}

static __always_inline int parse_ethhdr(struct hdr_cursor *nh, void *data_end, struct ethhdr **ethhdr) 
{ 
    /* Expect compiler removes the code that collects VLAN ids */ 
    return parse_ethhdr_vlan(nh, data_end, ethhdr, NULL); 
}

/* Swaps destination and source MAC addresses inside an Ethernet header */
static __always_inline void swap_src_dst_mac(struct ethhdr *eth)
{
    __u8 h_tmp[ETH_ALEN];

    __builtin_memcpy(h_tmp, eth->h_source, ETH_ALEN);
    __builtin_memcpy(eth->h_source, eth->h_dest, ETH_ALEN);
    __builtin_memcpy(eth->h_dest, h_tmp, ETH_ALEN);
}

/*Swaps destination and source IPv6 addresses inside an IPv6 header */
static __always_inline void swap_src_dst_ipv6(struct ipv6hdr *ipv6)
{
    struct in6_addr tmp = ipv6->saddr;
    ipv6->saddr = ipv6->daddr;
    ipv6->daddr = tmp;
}

/* Swaps destination and source IPv4 addresses inside an IPv4 header */
static __always_inline void swap_src_dst_ipv4(struct iphdr *iphdr)
{
    __be32 tmp = iphdr->saddr;
    iphdr->saddr = iphdr->daddr;
    iphdr->daddr = tmp;
}
#endif

