#include "vmlinux.h"
#include <bpf/bpf_endian.h>
#include <bpf/bpf_helpers.h>
#include "bpf_sockops.h"

static inline void sk_extractv4_key(struct bpf_sock_ops *ops, struct sock_key *key)
{
	// keep ip and port in network byte order
	key->dip4 = ops->remote_ip4;
	key->sip4 = ops->local_ip4;
	key->family = 1;
	// local_port is in host byte order, and 
	// remote_port is in network byte order
	key->sport = (bpf_htonl(ops->local_port) >> 16);
	key->dport = FORCE_READ(ops->remote_port) >> 16;
}

static inline void bpf_sock_ops_ipv4(struct bpf_sock_ops *skops)
{
	struct sock_key key = {};
	sk_extractv4_key(skops, &key);
    //if (key.dport == 4135 || key.sport == 4135) {
	/*insert the source socket in the sock_ops_map*/
	long ret = bpf_sock_hash_update(skops, &sock_ops_map, &key, BPF_NOEXIST);
	bpf_printk("<<< ipv4 op = %d, port %d --> %d\n", skops->op, skops->local_port, bpf_ntohl(skops->remote_port));
	if (ret != 0) {
		bpf_printk("FAILED: sock_hash_update ret: %d\n", ret);
	}
    //}
}

/* sock_ops BPF程序依赖cgroupv2*/
SEC("sockops")
int bpf_sockops(struct bpf_sock_ops *skops)
{
    /*不是ipv4的则忽略*/
    if (skops->family != 2) { //AF_INET
        return BPF_OK;
    }
	switch (skops->op) {
        case BPF_SOCK_OPS_PASSIVE_ESTABLISHED_CB:
        case BPF_SOCK_OPS_ACTIVE_ESTABLISHED_CB:
            /* 新创建的主动连接或被动连接 */
            bpf_sock_ops_ipv4(skops);
            break;
        default:
            break;
        }
    return BPF_OK;
}
char LICENSE[] SEC("license") = "GPL";
