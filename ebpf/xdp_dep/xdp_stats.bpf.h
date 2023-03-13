#ifndef __XDP_STATS_MAP_H_164452_1199259872__INC__
#define __XDP_STATS_MAP_H_164452_1199259872__INC__
#include "xdp_stats_def.h"

/* Keeps stats per (enum) xdp_action */
struct {
    __uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
    __uint(max_entries, XDP_ACTION_MAX);
    __uint(key_size, sizeof(__u32));
    __uint(value_size, sizeof(struct datarec));
} xdp_stats_map SEC(".maps");

static __always_inline enum xdp_action xdp_stats_record_action(struct xdp_md *ctx, enum xdp_action action)
{
    /* Lookup in kernel BPF-side return pointer to actual data record */
    struct datarec *rec = bpf_map_lookup_elem(&xdp_stats_map, &action);
    if (!rec)
        return XDP_ABORTED;
    /* BPF_MAP_TYPE_PERCPU_ARRAY returns a data record specific to current
     * CPU and XDP hooks runs under Softirq, which makes it safe to update
     * without atomic operations.
     */
    rec->rx_packets++;
    rec->rx_bytes += (ctx->data_end - ctx->data);
    return action;
}
#endif
