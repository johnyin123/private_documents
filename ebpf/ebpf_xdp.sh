# /linux-kernel/samples/bpf
cat <<EOF
/usr/include/linux/bpf.h
unsigned long long load_byte(void *skb, unsigned long long off) asm("llvm.bpf.load.byte");
unsigned long long load_half(void *skb, unsigned long long off) asm("llvm.bpf.load.half");
unsigned long long load_word(void *skb, unsigned long long off) asm("llvm.bpf.load.word");
enum bpf_prog_type {
	BPF_PROG_TYPE_UNSPEC,
	BPF_PROG_TYPE_SOCKET_FILTER,
	BPF_PROG_TYPE_KPROBE,
	BPF_PROG_TYPE_SCHED_CLS,
	BPF_PROG_TYPE_SCHED_ACT,
	BPF_PROG_TYPE_TRACEPOINT,
	BPF_PROG_TYPE_XDP,
	BPF_PROG_TYPE_PERF_EVENT,
	BPF_PROG_TYPE_CGROUP_SKB,
	BPF_PROG_TYPE_CGROUP_SOCK,
	BPF_PROG_TYPE_LWT_IN,
	BPF_PROG_TYPE_LWT_OUT,
	BPF_PROG_TYPE_LWT_XMIT,
	BPF_PROG_TYPE_SOCK_OPS,
	BPF_PROG_TYPE_SK_SKB,
	BPF_PROG_TYPE_CGROUP_DEVICE,
	BPF_PROG_TYPE_SK_MSG,
	BPF_PROG_TYPE_RAW_TRACEPOINT,
	BPF_PROG_TYPE_CGROUP_SOCK_ADDR,
	BPF_PROG_TYPE_LWT_SEG6LOCAL,
	BPF_PROG_TYPE_LIRC_MODE2,
	BPF_PROG_TYPE_SK_REUSEPORT,
	BPF_PROG_TYPE_FLOW_DISSECTOR,
	BPF_PROG_TYPE_CGROUP_SYSCTL,
	BPF_PROG_TYPE_RAW_TRACEPOINT_WRITABLE,
	BPF_PROG_TYPE_CGROUP_SOCKOPT,
	BPF_PROG_TYPE_TRACING,
	BPF_PROG_TYPE_STRUCT_OPS,
	BPF_PROG_TYPE_EXT,
	BPF_PROG_TYPE_LSM,
	BPF_PROG_TYPE_SK_LOOKUP,
	BPF_PROG_TYPE_SYSCALL, /* a program that can execute syscalls */
};


EOF
cat <<EOF
libbpf develop:
    apt install libbpf-dev libxdp-dev bpftool bpftrace
    bpftool btf dump file /sys/kernel/btf/vmlinux format c > vmlinux.h

# Files opened by process
bpftrace -e 'tracepoint:syscalls:sys_enter_open {printf("%s %s\n", comm, str(args->filename)); }'

# Syscall count by program
bpftrace -e 'tracepoint:raw_syscalls:sys_enter {@[comm] = count(); }'

# Read bytes by process:
bpftrace -e 'tracepoint:syscalls:sys_exit_read /args->ret/ {@[comm] = sum(args->ret); }'

# Read size distribution by process:
bpftrace -e 'tracepoint:syscalls:sys_exit_read {@[comm] = hist(args->ret); }'

# Show per-second syscall rates:
bpftrace -e 'tracepoint:raw_syscalls:sys_enter {@ = count(); } interval:s:1 { print(@); clear(@); }'

# Trace disk size by process
bpftrace -e 'tracepoint:block:block_rq_issue {printf("%d %s %d\n", pid, comm, args->bytes); }'

# Count page faults by process
bpftrace -e 'software:faults:1 {@[comm] = count(); }'
EOF
cat<<EOF
XDP程序是通过bpf()系统调用控制的，bpf()系统调用使用程序类型BPF_PROG_TYPE_XDP进行加载。

XDP操作模式
XDP支持3种工作模式，默认使用native模式：
1.Native XDP：在native模式下，XDP BPF程序运行在网络驱动的早期接收路径上（RX队列），因此，使用该模式时需要网卡驱动程序支持。
2.Offloaded XDP：在Offloaded模式下，XDP BFP程序直接在NIC（Network Interface Controller）中处理数据包，而不使用主机CPU，相比native模式，性能更高
3.Generic XDP：Generic模式主要提供给开发人员测试使用，对于网卡或驱动无法支持native或offloaded模式的情况，内核提供了通用的generic模式，运行在协议栈中，不需要对驱动做任何修改。生产环境中建议使用native或offloaded模式
XDP操作结果码
XDP_DROP：丢弃数据包，发生在驱动程序的最早RX阶段
XDP_PASS：将数据包传递到协议栈处理，操作可能为以下两种形式：
1、正常接收数据包，分配愿数据sk_buff结构并且将接收数据包入栈，然后将数据包引导到另一个CPU进行处理。他允许原始接口到用户空间进行处理。 这可能发生在数据包修改前或修改后。
2、通过GRO（Generic receive offload）方式接收大的数据包，并且合并相同连接的数据包。经过处理后，GRO最终将数据包传入“正常接收”流
XDP_TX：转发数据包，将接收到的数据包发送回数据包到达的同一网卡。这可能在数据包修改前或修改后发生
XDP_REDIRECT：数据包重定向，XDP_TX，XDP_REDIRECT是将数据包送到另一块网卡或传入到BPF的cpumap中
XDP_ABORTED：表示eBPF程序发生错误，并导致数据包被丢弃。自己开发的程序不应该使用该返回码
EOF
cat > netstat.py <<'EOF'
#!/usr/bin/python3
# apt -y install python3-bpfcc
from bcc import BPF
from time import sleep
#eBPF prog
bpf_text = """
BPF_HASH(stats, u32);
int count(struct pt_regs *ctx) {
    u32 key = 0;
    u64 *val, zero=0;
    val = stats.lookup_or_init(&key, &zero);
    (*val)++;
    return 0;
}
"""
#compile eBPF
b = BPF(text=bpf_text, cflags=["-Wno-macro-redefined"])
#load
b.attach_kprobe(event="tcp_sendmsg", fn_name="count")
name = {
    0: "tcp_sendmsg"
}
# output stats
while True:
    try:
        for k, v in b["stats"].items():
            print("{}: {}".format(name[k.value], v.value))
            sleep(1)
    except KeyboardInterrupt:
        exit()
EOF
cat > xdp_filter.c <<EOF
/*
丢弃所有TCP连接包,UDP正常
clang -O2 -target bpf -c xdp_filter.c -o xdp_filter.o
ip link set dev ens33 xdp obj xdp_filter.o sec mysection
 # ip doesn't support the BPF Type Format (BTF) type map, xdp-loader support it.
 or: xdp-loader load -m skb -s mysection veth1 xdp_filter.o
     xdp-loader status / xdp-loader unload -a veth1
ip a show ens33

卸载XDP程序: ip link set dev ens33 xdp off
*/
#include <linux/bpf.h>
#include <linux/if_ether.h>
#include <linux/in.h>
#include <linux/ip.h>
#include <linux/tcp.h>

#define SEC(NAME) __attribute__((section(NAME), used))

SEC("mysection")
int filter(struct xdp_md *ctx) {
    int ipsize = 0;
    void *data = (void *)(long)ctx->data;
    void *data_end = (void *)(long)ctx->data_end;
    struct ethhdr *eth = data;
    struct iphdr *ip;

    ipsize = sizeof(*eth);
    ip = data + ipsize;

    ipsize += sizeof(struct iphdr);
    if (data + ipsize > data_end) {
        return XDP_DROP;
    }

    if (ip->protocol == IPPROTO_TCP) {
        return XDP_DROP;
    }

    return XDP_PASS;
}
EOF

cat > xdp_bcc.c <<EOF
/*
xdp_bcc.c，当TCP连接目的端口为9999时DROP
can use iproute2 tools load bcc like xdp, or use python load it

from bcc import BPF
import time
device = "ens33"
b = BPF(src_file="xdp_bcc.c")
fn = b.load_func("filter", BPF.XDP)
b.attach_xdp(device, fn, 0)
try:
  b.trace_print()
except KeyboardInterrupt:
  pass
b.remove_xdp(device, 0)
*/
#define KBUILD_MODNAME "program"
#include <linux/bpf.h>
#include <linux/in.h>
#include <linux/ip.h>
#include <linux/tcp.h>

int filter(struct xdp_md *ctx) {
    int ipsize = 0;
    void *data = (void *)(long)ctx->data;
    void *data_end = (void *)(long)ctx->data_end;
    struct ethhdr *eth = data;
    struct iphdr *ip;

    ipsize = sizeof(*eth);
    ip = data + ipsize;

    ipsize += sizeof(struct iphdr);
    if (data + ipsize > data_end) {
        return XDP_DROP;
    }

    if (ip->protocol == IPPROTO_TCP) {
        struct tcphdr *tcp = (void *)ip + sizeof(*ip);
        ipsize += sizeof(struct tcphdr);
        if (data + ipsize > data_end) {
            return XDP_DROP;
        }

        if (tcp->dest == ntohs(9999)) {
            bpf_trace_printk("drop tcp dest port 9999\n");
            return XDP_DROP;
        }
    }

    return XDP_PASS;
}
EOF
