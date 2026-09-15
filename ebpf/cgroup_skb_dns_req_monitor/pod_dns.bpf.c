#include "pod_dns.h"
#include "xdp_parse.h"
char LICENSE[] SEC("license") = "GPL";
struct {
    __uint(type, BPF_MAP_TYPE_RINGBUF);
    __uint(max_entries, 1 << 16);
} dns_events SEC(".maps");

const volatile __be16 udp_port = 0x3500; /*network order, 53*/
SEC("cgroup_skb/egress") int trace_dns(struct __sk_buff *skb) {
    /*kernel verifier allows Direct Packet Access, when cgroup_skb.
     and disallow when SEC("socket") socketfilter*/
    void *data = (void *)(long)skb->data;
    void *data_end = (void *)(long)skb->data_end;
    struct hdr_cursor nh = { .pos = data };
    if (skb->protocol != __bpf_constant_htons(ETH_P_IP)) { return 1; }
    struct iphdr *iphdr = NULL;
    struct udphdr *udp = NULL;
    if (parse_iphdr(&nh, data_end, &iphdr) < 0) { return 1; }
    if (iphdr->protocol != IPPROTO_UDP) { return 1; }
    if (parse_udphdr(&nh, data_end, &udp) < 0) { return 1; }
    if (udp->dest != udp_port) { return 1; }

    struct dns_raw_event *e = bpf_ringbuf_reserve(&dns_events, sizeof(*e), 0);
    if (!e) { return 0; }
    e->saddr = iphdr->saddr;

    // 1. Calculate raw DNS payload length (UDP length minus 8 bytes header)
    __u32 dns_len = bpf_ntohs(udp->len) - sizeof(struct udphdr);
    __u32 len = min(dns_len, MAX_PAYLOAD_LEN);
    // 2. Clear zero-size and upper bound constraints sequentially for the verifier
    if (len == 0) {
        bpf_ringbuf_discard(e, 0);
        return 1;
    }
    if (len > MAX_PAYLOAD_LEN) {
        bpf_ringbuf_discard(e, 0);
        return 1;
    }
    // 3. Pin down the payload address (the position immediately following the UDP header)
    void *dns_payload = nh.pos;
    // 4. Final safety guard check against packet structural bounds before copying
    if (dns_payload + len > data_end) {
        bpf_ringbuf_discard(e, 0);
        return 1;
    }
    // 5. Populate your event's metadata blocks
    e->cgroup_id = bpf_get_current_cgroup_id(); // Fully working in cgroup_skb!
    e->payload_len = len;
    // 6. Safe kernel-space buffer copy into the ringbuf event
    bpf_probe_read_kernel(e->payload, len, dns_payload);

    bpf_ringbuf_submit(e, 0);
    return 1; // Return 1 to ensure the kernel forwards the packet to the wire
}
