#include <linux/bpf.h>
#include <linux/in.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <bpf/bpf_helpers.h>
/*
ip link set dev lo xdp obj test.bpf.o sec drop_icmp
ip link show dev lo
ping 127.0.0.1
ip link set dev lo xdp off
ip link show dev lo
*/
SEC("drop_icmp")
int drop_icmp_func(struct xdp_md *ctx) {
  int ipsize = 0;
  void *data = (void *)(long)ctx->data;
  void *data_end = (void *)(long)ctx->data_end;

  struct ethhdr *eth = data;

  ipsize = sizeof(*eth);

  struct iphdr *ip = data + ipsize;
  ipsize += sizeof(struct iphdr);
  if (data + ipsize > data_end) {
    // not an ip packet, too short. Pass it on
    return XDP_PASS;
  }

  // technically, we should also check if it is an IP packet by
  // checking the ethernet header proto field ...
  if (ip->protocol == IPPROTO_ICMP) {
    return XDP_DROP;
  }

  return XDP_PASS;
}
char LICENSE[] SEC("license") = "Dual BSD/GPL";
