#include "udp_dump.h"
#include "xdp_parse.h"
#include <linux/pkt_cls.h>
char LICENSE[] SEC("license") = "GPL";
struct {
    __uint(type, BPF_MAP_TYPE_PERF_EVENT_ARRAY);
    __uint(key_size, sizeof(__u32));
    __uint(value_size, sizeof(__u32));
} events SEC(".maps");

const volatile __be16 udp_port = 0x3500; /*network order, 53*/
SEC("tc") int trace_dns(struct __sk_buff *skb) {
    void *data = (void *)(long)skb->data;
    void *data_end = (void *)(long)skb->data_end;
    struct hdr_cursor nh = { .pos = data };
    struct ethhdr *eth = NULL;
    struct iphdr *iphdr = NULL;
    struct udphdr *udphdr = NULL;
    if (parse_ethhdr(&nh, data_end, &eth) != __bpf_constant_htons(ETH_P_IP)) { return TC_ACT_OK; }
    if (parse_iphdr(&nh, data_end, &iphdr) < 0) { return TC_ACT_OK; }
    /* Ignore non-first IPv4 fragments. The first fragment can contain the UDP header. */
    if (bpf_ntohs(iphdr->frag_off) & 0x1fff) { return TC_ACT_OK; }
    if (iphdr->protocol != IPPROTO_UDP) { return TC_ACT_OK; }
    if (parse_udphdr(&nh, data_end, &udphdr) < 0) { return TC_ACT_OK; }
    if (udphdr->dest != udp_port) { return TC_ACT_OK; }
    __u32 udp_len = bpf_ntohs(udphdr->len);
    if (udp_len < sizeof(*udphdr)) { return TC_ACT_OK; }
    bpf_debug("DNS_REQ (U) %pI4:%d -> %pI4:%d", &iphdr->saddr, bpf_ntohs(udphdr->source), &iphdr->daddr, bpf_ntohs(udphdr->dest));
    /////////////////////////////////
    // 1. Calculate raw DNS payload length (UDP length minus 8 bytes header)
    __u32 dns_len = bpf_ntohs(udphdr->len) - sizeof(struct udphdr);
    __u32 len = min(dns_len, MAX_PAYLOAD_LEN);
    // 2. Clear zero-size and upper bound constraints sequentially for the verifier
    if (len == 0) { return TC_ACT_OK; }
    if (len > MAX_PAYLOAD_LEN) { return TC_ACT_OK; }
    // 3. Pin down the payload address (the position immediately following the UDP header)
    void *dns_payload = nh.pos;
    // 4. Final safety guard check against packet structural bounds before copying
    if (dns_payload + len > data_end) { return TC_ACT_OK; }
    // 5. Populate your event's metadata blocks
    struct dns_raw_event event = {
        //.cgroup_id = bpf_get_current_cgroup_id(),
        .ifindex = skb->ifindex,
        .saddr = iphdr->saddr,
        .daddr = iphdr->daddr,
        .sport = bpf_ntohs(udphdr->source),
        .dport = bpf_ntohs(udphdr->dest),
        .payload_len = len,
    };
    // 6. Safe kernel-space buffer copy into the ringbuf event
    bpf_probe_read_kernel(event.payload, len, dns_payload);
    /////////////////////////////////
    bpf_perf_event_output(skb, &events, BPF_F_CURRENT_CPU, &event, sizeof(event));
    return TC_ACT_OK;
}
