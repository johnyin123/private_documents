#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
SEC("xdp")
int xdp_prog(struct xdp_md *ctx) {
    (void)ctx;
    return XDP_PASS;
}
char LICENSE[] SEC("license") = "GPL";
