#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>
#include "xdp.bpf.h"
#include "xdp_stats.bpf.h"
#include "murmur_hash.h"
#include "real_def.h"

char LICENSE[] SEC("license") = "GPL";

struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(key_size, sizeof(__u32));
    __uint(value_size, sizeof(struct reals));
    __uint(max_entries, BUCKET_SIZE);
} reals SEC(".maps");

////////////////////////////////////////////////////////////////////////////////////////////////////
struct keys {
    __be32 src;
    __be32 dst;
    __be16 sport;
    __be16 dport;
};

struct pkt_desc {
    struct keys keys;
    __u32 daddr;
    __u16 size;
    __u8 proto;
};

static __always_inline struct reals *dst_lookup(struct pkt_desc *pkt_meta)
{
    #define HASH_SEED 0xcafebabe
    __u32 digest = murmurhash((const char *)&pkt_meta->keys, HASH_SEED) % BUCKET_SIZE;
    /* TODO: LRU lookup can perform here */
    return bpf_map_lookup_elem(&reals, &digest);
}

/* FB's impl of ipv4 checksum calculation,
 * somehow the following is not working, 
 * the verifier says that I have <<= pointer
 * arithmetic, maybe it's caused by -O2
 * compiler flag.
 * 
 * 	iph_csum =  (__u16 *) &iph;
 *	#pragma clang loop unroll(full)
 *	for (int i = 0; i < (int)sizeof(*iph) >> 1; i++)
 *		csum += *iph_csum++;
 *	iph->check = ~((csum & 0xffff) + (csum >> 16));
 * 
 * where csum is of type __u32
 * */
static __always_inline __u16 csum_fold_helper(__u64 csum)
{
	int i;
#pragma unroll
	for (i = 0; i < 4; i ++) {
		if (csum >> 16)
		csum = (csum & 0xffff) + (csum >> 16);
	}
	return ~csum;
}

static __always_inline void ipv4_csum_inline(void *iph, __u64 *csum)
{
	__u16 *next_iph_u16 = (__u16 *)iph;
#pragma clang loop unroll(full)
	for (int i = 0; i < sizeof(struct iphdr) >> 1; i++) {
		*csum += *next_iph_u16++;
	}
	*csum = csum_fold_helper(*csum);
}
static __always_inline bool encap_iph(struct reals *real, struct pkt_desc *pkt_meta, void *data, void *data_end)
{
	struct ethhdr *new_eth, *old_eth;
	struct iphdr *iph;
	__u64 csum = 0;
	/* update eth header first, since we are going to overwrite */
	new_eth = data;
	old_eth = data + sizeof(struct iphdr);
	iph = data + sizeof(struct ethhdr);
	if ((void *)(new_eth + 1) > data_end || (void *)(old_eth + 1) > data_end || (void *)(iph + 1) > data_end)
		return false;
	memcpy(new_eth->h_source, old_eth->h_dest, ETH_MAC_LEN);
	memcpy(new_eth->h_dest, real->mac, ETH_MAC_LEN);
	new_eth->h_proto = ETH_P_IP;
	iph->version = 4; /* ipv4 */
	iph->ihl = 5; /* no options set */
	iph->frag_off = 0;
	iph->protocol = IPPROTO_IPIP; /* outter-most iphdr */
	iph->check = 0;
	iph->tos = 0;
	iph->tot_len = bpf_htons(pkt_meta->size + sizeof(struct iphdr));
	iph->daddr = real->addr;
	iph->saddr = pkt_meta->daddr;
	iph->ttl = 64;
	/* chksum calc */
	ipv4_csum_inline(iph, &csum);
	iph->check = csum;
	return true;
}


SEC("xdp")
int xdp_redirect_map_func(struct xdp_md *ctx)
{
    void *data_end = (void *)(long)ctx->data_end;
    void *data = (void *)(long)ctx->data;
    struct hdr_cursor nh;
    struct ethhdr *ethhdr;
    struct iphdr *iphdr;
    struct tcphdr *tcphdr;
    int nh_type;
    int action = XDP_PASS;
    /* These keep track of the next header type and iterator pointer */
    nh.pos = data;
    /* Parse Ethernet and IP/IPv6 headers */
    nh_type = parse_ethhdr(&nh, data_end, &ethhdr);
    if (nh_type == -1)
        goto out;
    // bpf_htons(ETH_P_IPV6)
    if (nh_type != bpf_htons(ETH_P_IP)) 
        goto out;
    nh_type = parse_iphdr(&nh, data_end, &iphdr);
    if (nh_type != IPPROTO_TCP)
        goto out;
    if (iphdr->ihl != 5)
        goto out; /* packet has ip options inside, which we dont support */
    if (parse_tcphdr(&nh, data_end, &tcphdr) < 0)
        goto out;
    ////////////////////////////////
    struct pkt_desc pkt_meta;
    pkt_meta.keys.src = iphdr->saddr;
    pkt_meta.keys.dst = iphdr->daddr;
	pkt_meta.keys.sport = tcphdr->source;
	pkt_meta.keys.dport = tcphdr->dest;
    pkt_meta.size = bpf_ntohs(iphdr->tot_len);
    pkt_meta.proto = iphdr->protocol;
    pkt_meta.daddr = iphdr->daddr;
    struct reals *real = dst_lookup(&pkt_meta);
    if (!real) {
        action = XDP_DROP;
        goto out;
    }
    if (real->addr == iphdr->daddr) {
        action = XDP_PASS;
        goto out;
    }
    /* expend the packet for ipip header */
    if (bpf_xdp_adjust_head(ctx, 0 - (int)sizeof(struct iphdr))) {
        action = XDP_DROP;
        goto out;
    }
    data = (void *)(long) ctx->data;
    data_end = (void *)(long) ctx->data_end;
    if (!encap_iph(real, &pkt_meta, data, data_end)) {
        action = XDP_DROP;
        goto out;
    }
    bpf_printk("found %x, %x, %x ,%x", pkt_meta.keys.src, pkt_meta.keys.dst, pkt_meta.keys.sport, pkt_meta.keys.dport);
    action = XDP_TX;
out:
    return xdp_stats_record_action(ctx, action);
}
