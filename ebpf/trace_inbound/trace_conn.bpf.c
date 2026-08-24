#include <linux/bpf.h>
#include <linux/if_ether.h>
#include <linux/in.h>
#include <linux/ip.h>
#include <linux/tcp.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>
#include "trace_conn.h"
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

SEC("xdp")
int xdp_prog(struct xdp_md *ctx)
{
    void *data = (void *)(long)ctx->data;
    void *data_end = (void *)(long)ctx->data_end;
    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > data_end) return XDP_PASS;
    if (eth->h_proto != bpf_htons(ETH_P_IP)) return XDP_PASS;
    struct iphdr *ip = (struct iphdr *)(eth + 1);
    if ((void *)(ip + 1) > data_end) return XDP_PASS;
    if (ip->protocol != IPPROTO_TCP) return XDP_PASS;
    int ip_hdr_len = ip->ihl * 4;
    if ((void *)ip + ip_hdr_len > data_end) return XDP_PASS;
    struct tcphdr *tcp = (struct tcphdr *)((void *)ip + ip_hdr_len);
    if ((void *)(tcp + 1) > data_end) return XDP_PASS;
    struct connection_key key = { .saddr = ip->saddr, .daddr = ip->daddr, .sport = tcp->source, .dport = tcp->dest };
    // CASE 1: Inbound SYN
    if (tcp->syn && !tcp->ack) {
        //__u64 time_ns = bpf_ktime_get_ns();
        bpf_printk("SYN: %pI4:%d -> %pI4:%d\n", &key.saddr, bpf_ntohs(key.sport), &key.daddr, bpf_ntohs(key.dport));
        __u8 tracking = 1;
        bpf_map_update_elem(&pending_incoming_map, &key, &tracking, BPF_ANY);
        return XDP_PASS;
    }
    // CASE 2: Inbound ACK completing the handshake
    if (tcp->ack && !tcp->syn && !tcp->fin && !tcp->rst) {
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
