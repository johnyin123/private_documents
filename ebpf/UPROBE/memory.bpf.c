#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

char LICENSE[] SEC("license") = "GPL";

unsigned long long func_entry_time = 0;
unsigned long long func_exit_time = 0;
/*int foo(int a, int b)*/
SEC("uprobe/foo")
int BPF_KPROBE(uprobe_foo, int a, int b)
{
    func_entry_time = bpf_ktime_get_ns();
    bpf_printk("function execute time:%lu, %d, %d\n", func_exit_time - func_entry_time, a, b);
    return 0;
}
SEC("uretprobe/foo")
int BPF_KRETPROBE(uretprobe_foo, int ret)
{
    func_exit_time = bpf_ktime_get_ns();
    bpf_printk("function execute time:%lu\n", func_exit_time - func_entry_time);
    return 0;
}
