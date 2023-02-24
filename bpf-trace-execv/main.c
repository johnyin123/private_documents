#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <bpf/libbpf.h>
#include <time.h>
#include "mybpf.h"
#include "mybpf_skel.h"

static int bpfverbose = 0;
int libbpf_print_fn(enum libbpf_print_level level, const char *format, va_list args)
{
    if (level == LIBBPF_DEBUG && !bpfverbose)
        return 0;
    return vfprintf(stderr, format, args);
}

int bump_memlock_rlimit()
{
    struct rlimit rlim_new = {
        .rlim_cur = RLIM_INFINITY,
        .rlim_max = RLIM_INFINITY,
    };
    return setrlimit(RLIMIT_MEMLOCK, &rlim_new);
}

/*丢失事件的处理程序*/
static void handle_lost_events(void *ctx, int cpu, __u64 lost_cnt)
{
       fprintf(stderr, "Lost %llu events on CPU #%d!\n", lost_cnt, cpu);
}

/*打印参数,替换'\0'为空格*/
static void print_args(const struct event *e)
{
       int args_counter = 0;
       for (int i = 0; i < e->args_size && args_counter < e->args_count; i++) {
               char c = e->args[i];
               if (c == '\0') {
                       args_counter++;
                       putchar(' ');
               } else {
                       putchar(c);
               }
       }
       if (e->args_count > TOTAL_MAX_ARGS) {
               fputs(" ...", stdout);
       }
}

/*性能事件回调函数(向终端中打印进程名、PID、返回值以及参数)*/
void handle_event(void *ctx, int cpu, void *data, __u32 data_sz)
{
       const struct event *e = data;
       printf("%-16s %-6d %3d ", e->comm, e->pid, e->retval);
       print_args(e);
       putchar('\n');
}

int main(int argc, char **argv)
{
    struct mybpf_skel *skel;
    struct perf_buffer *pb = NULL;
    int err;

    libbpf_set_print(libbpf_print_fn);
    if ((err = bump_memlock_rlimit())) {
        fprintf(stderr, "Failed to increase rlimit: %d", err);
        return 1;
    }
    if (!(skel = mybpf_skel__open())) {
        fprintf(stderr, "Failed to open BPF skeleton\n");
        return 2;
    }
    if ((err = mybpf_skel__load(skel))) {
        fprintf(stderr, "Failed to load and verify BPF skeleton\n");
        return 3;
    }
    if ((err = mybpf_skel__attach(skel))) {
        fprintf(stderr, "Failed to attach BPF skeleton\n");
        return 4;
    }
    pb = perf_buffer__new(bpf_map__fd(skel->maps.events), 64, handle_event, handle_lost_events, NULL, NULL);
    if ((err = libbpf_get_error(pb))) {
        pb = NULL;
        fprintf(stderr, "failed to open perf buffer: %d\n", err);
        goto cleanup;
    }
    printf("%-16s %-6s %3s %s\n", "COMM", "PID", "RET", "ARGS");
    /*从缓冲区中循环读取数据*/
    while ((err = perf_buffer__poll(pb, 100)) >= 0) ;
    printf("Error polling perf buffer: %d\n", err);

 cleanup:
    perf_buffer__free(pb);
    mybpf_skel__destroy(skel);
    return err != 0;
}
