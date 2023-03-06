#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>
#include "tcpdump.h"
struct {
    __uint(type, BPF_MAP_TYPE_PERF_EVENT_ARRAY);
    __uint(key_size, sizeof(int));
    __uint(value_size, sizeof(__u32));
    __uint(max_entries, MAX_CPUS);
} my_map SEC(".maps");

SEC("xdp")
int xdp_prog(struct xdp_md *ctx)
{
    void *data_end = (void *)(long)ctx->data_end;
    void *data = (void *)(long)ctx->data;

    if (data < data_end) {
        /* The XDP perf_event_output handler will use the upper 32 bits
         * of the flags argument as a number of bytes to include of the
         * packet payload in the event data. If the size is too big, the
         * call to bpf_perf_event_output will fail and return -EFAULT.
         *
         * See bpf_xdp_event_output in net/core/filter.c.
         *
         * The BPF_F_CURRENT_CPU flag means that the event output fd
         * will be indexed by the CPU number in the event map.
         */
        __u64 flags = BPF_F_CURRENT_CPU;
        __u16 sample_size;
        int ret;
        struct data_t metadata;

        metadata.cookie = 0xdead;
        metadata.pkt_len = (__u16)(data_end - data);
        sample_size = min(metadata.pkt_len, SAMPLE_SIZE);

        flags |= (__u64)sample_size << 32;

        ret = bpf_perf_event_output(ctx, &my_map, flags, &metadata, sizeof(metadata));
        if (ret)
            bpf_printk("perf_event_output failed: %d\n", ret);
    }

    return XDP_PASS;
}
char LICENSE[] SEC("license") = "GPL";
