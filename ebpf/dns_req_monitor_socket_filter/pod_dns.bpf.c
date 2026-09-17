#include "pod_dns.h"
#include "xdp_parse.h"
char LICENSE[] SEC("license") = "GPL";
struct {
    __uint(type, BPF_MAP_TYPE_RINGBUF);
    __uint(max_entries, 1 << 16);
} dns_events SEC(".maps");

const volatile __be16 udp_port = 0x3500; /*network order, 53*/

SEC("cgroup/sock") int bpf_track_socket_creation(struct bpf_sock *sk) {
    __u64 pid_tgid = bpf_get_current_pid_tgid();
    __u32 pid = pid_tgid >> 32;
    __u64 cookie = bpf_get_socket_cookie(sk);
    bpf_map_update_elem(&cookie_pid_map, &cookie, &pid, BPF_ANY);
    return 1;
}
SEC("socket") int trace_dns(struct __sk_buff *skb) {
    struct iphdr ip;
    struct udphdr udp;
    if (skb->protocol != __bpf_constant_htons(ETH_P_IP)) { return 0; }
    __u32 ip_off = sizeof(struct ethhdr);
    if (bpf_skb_load_bytes(skb, ip_off, &ip, sizeof(ip)) < 0) { return 0; }
    if (ip.protocol != IPPROTO_UDP) { return 0; }
    __u32 udp_off = ip_off + (ip.ihl * 4);
    if (bpf_skb_load_bytes(skb, udp_off, &udp, sizeof(udp)) < 0) { return 0; }
    // Filter strictly for DNS (Port 53)
    if (udp.dest != udp_port) { return 0; }

    struct dns_raw_event *e = bpf_ringbuf_reserve(&dns_events, sizeof(*e), 0);
    if (!e) { return 0; }
    e->saddr = ip.saddr;
    // 1. Calculate and cap the payload length into a LOCAL STACK variable
    __u32 dns_len = bpf_ntohs(udp.len) - sizeof(struct udphdr);
    __u32 len = min(dns_len, MAX_PAYLOAD_LEN);
    // 2. FORCE THE VERIFIER TO NARROW THE BOUNDS
    if (len == 0) {
        bpf_ringbuf_discard(e, 0);
        return 0;
    }
    if (len > MAX_PAYLOAD_LEN) {
        bpf_ringbuf_discard(e, 0);
        return 0;
    }
    // 3. Perform the load using the trusted local stack variable
    __u32 dns_off = udp_off + sizeof(struct udphdr);
    if (bpf_skb_load_bytes(skb, dns_off, e->payload, len) < 0) {
        bpf_ringbuf_discard(e, 0);
        return 0;
    }
    // 4. Safely save the tracked length to the struct *after* the read succeeds
    e->payload_len = len;

    bpf_ringbuf_submit(e, 0); // Don't forget to submit the event!
    return 0;
}

