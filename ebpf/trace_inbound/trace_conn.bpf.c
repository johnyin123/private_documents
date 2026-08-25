#include "trace_conn.h"
#include "xdp_parse.h"
char LICENSE[] SEC("license") = "GPL";
/*
握手失败率 (SLI)
(总SYN_SENT次数 - 总ESTABLISHED次数) / 总SYN_SENT次数
如果这个指标突增，代表网络层或对端应用层存在不可达。
*/
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __type(key, __u32);
    __type(value, struct data_stats);
    __uint(max_entries, 1);
} traffic_map SEC(".maps");
// Internal Map: Tracks ongoing handshake steps
struct {
    __uint(type, BPF_MAP_TYPE_LRU_PERCPU_HASH); /*BPF_MAP_TYPE_HASH*/
    __uint(max_entries, 10240);
    __type(key, struct connection_key);
    __type(value, __u8); 
} pending_incoming_map SEC(".maps");
// Telemetry Export Map: Sends finalized connections to user space
struct {
    __uint(type, BPF_MAP_TYPE_RINGBUF);
    __uint(max_entries, 256 * 1024); // 256 KB ring buffer size
} events_ringbuf SEC(".maps");
SEC("xdp") int xdp_prog(struct xdp_md *ctx) {
    void *data = (void *)(long)ctx->data;
    void *data_end = (void *)(long)ctx->data_end;
    struct hdr_cursor nh = { .pos = data };
    struct ethhdr *eth;
    struct iphdr *iphdr;
    struct tcphdr *tcphdr;
    if (parse_ethhdr(&nh, data_end, &eth) != bpf_htons(ETH_P_IP)) { return XDP_PASS; }
    if (parse_iphdr(&nh, data_end, &iphdr) != IPPROTO_TCP) { return XDP_PASS; }
    if (parse_tcphdr(&nh, data_end, &tcphdr) < 0) { return XDP_PASS; }

    struct connection_key key = { .saddr = iphdr->saddr, .daddr = iphdr->daddr, .sport = tcphdr->source, .dport = tcphdr->dest };
    // CASE 1: Inbound SYN
    if (tcphdr->syn && !tcphdr->ack) {
        //__u64 time_ns = bpf_ktime_get_ns();
        bpf_printk("SYN: %pI4:%d -> %pI4:%d\n", &key.saddr, bpf_ntohs(key.sport), &key.daddr, bpf_ntohs(key.dport));
        __u8 tracking = 1;
        bpf_map_update_elem(&pending_incoming_map, &key, &tracking, BPF_ANY);
        return XDP_PASS;
    }
    // CASE 2: Inbound ACK completing the handshake
    if (tcphdr->ack && !tcphdr->syn && !tcphdr->fin && !tcphdr->rst) {
        __u8 *is_pending = bpf_map_lookup_elem(&pending_incoming_map, &key);
        if (is_pending) {
            bpf_printk("ACK: %pI4:%d -> %pI4:%d\n", &key.saddr, bpf_ntohs(key.sport), &key.daddr, bpf_ntohs(key.dport));
            struct connection_key *e = bpf_ringbuf_reserve(&events_ringbuf, sizeof(struct connection_key), 0);
            if (e) {
                *e = key;
                bpf_ringbuf_submit(e, 0);
            }
            __u32 array_idx = 0;
            struct data_stats *stats = bpf_map_lookup_elem(&traffic_map, &array_idx);
            if(stats) {
                __sync_fetch_and_add(&stats->in_cnt, 1);
            }
            bpf_map_delete_elem(&pending_incoming_map, &key);
        }
    }
    return XDP_PASS;
}
