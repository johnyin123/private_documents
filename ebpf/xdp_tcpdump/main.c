#include <stdio.h>
#include <getopt.h>
#include <string.h>
#include <stdlib.h>
#include <net/if.h>
#include <sys/resource.h>
#include <sys/time.h>
#include <unistd.h>
#include <bpf/bpf.h>
/* XDP_FLAGS_SKB_MODE */
#include <linux/if_link.h>
#include "tcpdump_skel.h"
#include "tcpdump.h"
static volatile bool exiting;
struct env {
    char iface[128];
    int verbose;
} env = {
    .iface = { 0, },
    .verbose = 0,
};
static int libbpf_print_fn(enum libbpf_print_level level, const char *format, va_list args)
{
    if (level == LIBBPF_DEBUG && !env.verbose)
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
const char *opt_short="i:hV";
struct option opt_long[] = {
    { "iface",   required_argument, NULL, 'i' },
    { "help",    no_argument, NULL, 'h' },
    { "verbose", no_argument, NULL, 'V' },
    { 0, 0, 0, 0 }
};

static void usage(char *prog)
{
    printf("Usage: %s\n", prog);
    printf("    -i|--ether <iface> network interface attach\n");
    printf("    -h|--help help\n");
    printf("    -V|--verbose\n");
    exit(0);
}

static int parse_command_line(int argc, char **argv)
{
    int opt, option_index;
    while ((opt = getopt_long(argc, argv, opt_short, opt_long, &option_index)) != -1) {
        switch (opt) {
            case 'i':
                strncpy(env.iface, optarg, 127);
                return 0;
            case 'h':
                usage(argv[0]);
                return 0;
            case 'V':
                env.verbose = 1;
                break;
            default:
                usage(argv[0]);
                return 1;
        }
    }
    return 0;
}
#include <signal.h>
static void int_exit(int sig)
{
    fprintf(stderr, "EXIT!!\n");
    exiting = 1;
}
void handle_event(void *ctx, int cpu, void *data, __u32 data_sz)
{
    int i;
    struct data_t *e = data;
    const __u8 *payload = data;
    payload += sizeof(struct data_t);
    if (e->cookie != 0xdead) {
        fprintf(stderr, "BUG cookie %x sized %d\n", e->cookie, data_sz);
        return;
    }
    fprintf(stdout, "pkg size %-5d, hdr: ", e->pkt_len);
    for (i = 0; i < e->pkt_len; i++) {
        fprintf(stdout, "%02x ", payload[i]);
    }
	fprintf(stdout, "\n");

}
void handle_lost_events(void *ctx, int cpu, __u64 lost_cnt)
{
    fprintf(stderr, "lost %llu events on CPU #%d\n", lost_cnt, cpu);
}
int main(int argc, char **argv)
{
    struct tcpdump_skel *skel;
    struct perf_buffer *pb = NULL;
    int err;
    parse_command_line(argc, argv);
    if (strlen(env.iface)<=0)
        usage(argv[0]);
    unsigned int ifindex = if_nametoindex(env.iface);
    if (!ifindex) {
        perror("failed to resolve iface to ifindex");
        return EXIT_FAILURE;
    }

    libbpf_set_print(libbpf_print_fn);
    if ((err = bump_memlock_rlimit())) {
        fprintf(stderr, "Failed to increase rlimit: %d", err);
        return 1;
    }
    if (!(skel = tcpdump_skel__open_and_load())) {
        fprintf(stderr, "Failed to open and load BPF skeleton\n");
        return 2;
    }
    /*Use "xdpgeneric" mode; less performance but supported by all drivers*/
    int flags = XDP_FLAGS_SKB_MODE | XDP_FLAGS_UPDATE_IF_NOEXIST;
    //int flags = XDP_FLAGS_UPDATE_IF_NOEXIST | XDP_FLAGS_DRV_MODE;
    int fd = bpf_program__fd(skel->progs.xdp_prog);
    /* TODO: replace with actual code, e.g. loop to get data from BPF*/
    signal(SIGINT, int_exit);
    signal(SIGHUP, int_exit);
    signal(SIGTERM, int_exit);
    /* Attach BPF to network interface */
    err = bpf_set_link_xdp_fd(ifindex, fd, flags);
    if (err) {
        fprintf(stderr, "failed to attach BPF to iface %s (%d): %d\n", env.iface, ifindex, err);
        goto cleanup;
    }
    pb = perf_buffer__new(bpf_map__fd(skel->maps.my_map), 64, handle_event, handle_lost_events, NULL, NULL);
    if ((err = libbpf_get_error(pb))) {
        pb = NULL;
        fprintf(stderr, "failed to open perf buffer: %d\n", err);
        goto cleanup;
    }
    while ((err = perf_buffer__poll(pb, 100)) >= 0) {
        if (exiting) {
            err = 0;
            goto cleanup;
        }
    }
 cleanup:
    /* Remove BPF from network interface */
    fd = -1;
    err = bpf_set_link_xdp_fd(ifindex, fd, flags);
    if (err) {
        fprintf(stderr, "failed to detach BPF from iface %s (%d): %d\n", env.iface, ifindex, err);
        goto cleanup;
    }
    perf_buffer__free(pb);
    tcpdump_skel__destroy(skel);
    return err != 0;
}
