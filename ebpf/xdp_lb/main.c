#include <stdio.h>
#include <getopt.h>
#include <string.h>
#include <stdlib.h>
#include "xdplb_skel.h"

struct env {
    int exiting;
    int verbose;
    unsigned int ifindex;
} env = {
    .exiting = 0,
    .verbose = 0,
    .ifindex = 0,
};

const char *opt_short="i:hV";
struct option opt_long[] = {
    { "iface",   required_argument, NULL, 'i' }, 
    { "help",    no_argument,       NULL, 'h' },
    { "verbose", no_argument,       NULL, 'V' },
    { 0, 0, 0, 0 }
};
/*
 * { "demo",    required_argument, NULL, 'd' }, 
 * strncpy(env.demo, optarg, 10);
 * env.demo = strtol(optarg, NULL, 10);
*/

static void usage(char *prog)
{
    printf("Usage: %s\n", prog);
    printf("    -i|--iface <str> network interface\n");
    printf("    -h|--help help\n");
    printf("    -V|--verbose\n");
    printf("       ip addr add ${vip}/32 dev lo\n");
    printf("       sysctl net.ipv4.conf.all.arp_ignore=1\n");
    printf("       sysctl net.ipv4.conf.eth0.arp_ignore=1\n");
    printf("       sysctl net.ipv4.conf.all.arp_announce=2\n");
    printf("       sysctl net.ipv4.conf.eth0.arp_announce=2\n");
    exit(0);
}

#include <net/if.h>
static int parse_command_line(int argc, char **argv)
{
    int opt, option_index;
    while ((opt = getopt_long(argc, argv, opt_short, opt_long, &option_index)) != -1) {
        switch (opt) {
            case 'i':
                env.ifindex = if_nametoindex(optarg);
                break;
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

#include "xdp_stats.h"
static void stats_print(struct stats_record *stats_rec, struct stats_record *stats_prev)
{
	struct record *rec, *prev;
	__u64 packets, bytes;
	double period;
	double pps; /* packets per sec */
	double bps; /* bits per sec */
	int i;
	/* Print for each XDP actions stats */
	for (i = 0; i < XDP_ACTION_MAX; i++)
	{
		char *fmt = "%-12s %'11lld pkts (%'10.0f pps)" " %'11lld Kbytes (%'6.0f Mbits/s)" " period:%f\n";
		rec  = &stats_rec->stats[i];
		prev = &stats_prev->stats[i];
		period = calc_period(rec, prev);
		if (period == 0) return;
		packets = rec->total.rx_packets - prev->total.rx_packets;
		pps     = packets / period;
		bytes   = rec->total.rx_bytes   - prev->total.rx_bytes;
		bps     = (bytes * 8)/ period / 1000000;
		printf(fmt, action2str(i), rec->total.rx_packets, pps, rec->total.rx_bytes / 1000 , bps, period);
	}
	printf("\n");
}
#include <locale.h>
#include <unistd.h>
static void stats_poll(int map_fd, __u32 map_type, int interval)
{
    struct stats_record prev, record = { 0 };
    /* Trick to pretty printf with thousands separators use %' */
    setlocale(LC_NUMERIC, "en_US");
    /* Get initial reading quickly */
    stats_collect(map_fd, map_type, &record);
    usleep(1000000/4);
    while (!env.exiting) {
        prev = record; /* struct copy */
        stats_collect(map_fd, map_type, &record);
        stats_print(&record, &prev);
        sleep(interval);
    }
}

#include <signal.h>
static void int_exit(int sig)
{
    fprintf(stderr, "EXIT!!\n");
    env.exiting = 1;
}

static int libbpf_print_fn(enum libbpf_print_level level, const char *format, va_list args)
{
    if (level == LIBBPF_DEBUG && !env.verbose)
        return 0;
    return vfprintf(stderr, format, args);
}
/* XDP_FLAGS_SKB_MODE */
#include <linux/if_link.h>
#include "real_def.h"
#include <arpa/inet.h>
#include <bpf/bpf.h>
int main(int argc, char *argv[])
{
    int err, xdp_flags = XDP_FLAGS_UPDATE_IF_NOEXIST | XDP_FLAGS_SKB_MODE;
    struct xdplb_skel *skel;
    //xdp_flags |= XDP_FLAGS_DRV_MODE;
    parse_command_line(argc, argv);
    if (!env.ifindex) {
        fprintf(stderr, "failed to resolve iface\n");
        //perror("failed to resolve iface to ifindex");
        return 1;
    }
    struct reals real;
    struct in_addr in;
    const char *dip = "11.22.33.44";
    if(!inet_pton(AF_INET, dip, &in)) {
        fprintf(stderr, "inet_pton error");
        exit(EXIT_FAILURE);
    }
    unsigned char mac[BUCKET_SIZE][ETH_MAC_LEN] = {
        {0x52,0x54,0xa3,0x5c,0x2d,0x49},
    };


    print_libbpf_ver();
    libbpf_set_print(libbpf_print_fn);
    if ((err = bump_memlock_rlimit())) {
        fprintf(stderr, "set rlimit failed\n");
        return 1;
    }
    if ((skel = xdplb_skel__open_and_load()) == NULL) {
        fprintf(stderr, "Failed to open and load BPF skeleton\n");
        return 1;
    }
    /*load reals config*/
    real.addr = in.s_addr;
    memcpy(real.mac, &mac[0][0], ETH_MAC_LEN);
    int i=0;
    if (bpf_map_update_elem(bpf_map__fd(skel->maps.reals), &i, &real, BPF_ANY) < 0) {
        fprintf(stderr, "Error updating bpf %d map", i);
        goto cleanup;
    }
    /* Attach BPF to network interface */
    //if ((err = bpf_set_link_xdp_fd(env.ifindex, bpf_program__fd(skel->progs.xdp_prog), xdp_flags))) {
    if ((err = bpf_xdp_attach(env.ifindex, bpf_program__fd(skel->progs.xdp_redirect_map_func), xdp_flags, NULL))) {
        fprintf(stderr, "failed to attach BPF iface (%d): %d\n", env.ifindex, err);
        goto cleanup;
    }
    fprintf(stderr, "Hit enter stop prog!\n");
    signal(SIGINT, int_exit);
    signal(SIGHUP, int_exit);
    signal(SIGTERM, int_exit);
    stats_poll(bpf_map__fd(skel->maps.xdp_stats_map), BPF_MAP_TYPE_PERCPU_ARRAY, 1);
    /* Remove BPF from network interface */
    // if ((err = bpf_set_link_xdp_fd(env.ifindex, -1, xdp_flags))) {
    if ((err = bpf_xdp_detach(env.ifindex, xdp_flags, NULL))) {
        fprintf(stderr, "failed to detach BPF iface (%d): %d\n", env.ifindex, err);
        goto cleanup;
    }
cleanup:
    xdplb_skel__destroy(skel);
    return -err;
}
