#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

SEC("xdp")
int xdp_prog(struct xdp_md *ctx) {
    (void)ctx;
    return XDP_DROP;
}
char LICENSE[] SEC("license") = "GPL";
