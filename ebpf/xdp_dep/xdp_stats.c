#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <bpf/bpf.h>
#include <bpf/libbpf.h>
#include "xdp_stats.h"

#define NANOSEC_PER_SEC 1000000000 /* 10^9 */
double calc_period(struct record *r, struct record *p)
{
	double period_ = 0;
	__u64 period = 0;
	period = r->timestamp - p->timestamp;
	if (period > 0)
		period_ = ((double) period / NANOSEC_PER_SEC);
	return period_;
}

static __u64 gettime(void)
{
    struct timespec t;
    int res;
    res = clock_gettime(CLOCK_MONOTONIC, &t);
    if (res < 0) {
        fprintf(stderr, "Error with gettimeofday! (%i)\n", res);
        exit(EXIT_FAILURE);
    }
    return (__u64) t.tv_sec * NANOSEC_PER_SEC + t.tv_nsec;
}

/* BPF_MAP_TYPE_ARRAY */ 
static void map_get_value_array(int fd, __u32 key, struct datarec *value) 
{ 
    if ((bpf_map_lookup_elem(fd, &key, value)) != 0) { 
        fprintf(stderr, "ERR: bpf_map_lookup_elem failed key:0x%X\n", key); 
    } 
} 

/* BPF_MAP_TYPE_PERCPU_ARRAY */
static void map_get_value_percpu_array(int fd, __u32 key, struct datarec *value)
{
    /* For percpu maps, userspace gets a value per possible CPU */
    unsigned int nr_cpus = libbpf_num_possible_cpus();
    struct datarec values[nr_cpus];
    __u64 sum_bytes = 0;
    __u64 sum_pkts = 0;
    int i;
    if ((bpf_map_lookup_elem(fd, &key, values)) != 0) {
        fprintf(stderr, "ERR: bpf_map_lookup_elem failed key:0x%X\n", key);
        return;
    }   
    /* Sum values from each CPU */
    for (i = 0; i < nr_cpus; i++) {
        sum_pkts  += values[i].rx_packets;
        sum_bytes += values[i].rx_bytes;
    }   
    value->rx_packets = sum_pkts;
    value->rx_bytes   = sum_bytes;
}   

static bool map_collect(int fd, __u32 map_type, __u32 key, struct record *rec)
{
    struct datarec value;
    /* Get time as close as possible to reading map contents */
    rec->timestamp = gettime();
    switch (map_type) {
    case BPF_MAP_TYPE_ARRAY:
        map_get_value_array(fd, key, &value);
        break;
    case BPF_MAP_TYPE_PERCPU_ARRAY:
        map_get_value_percpu_array(fd, key, &value);
        break;
    default:
        fprintf(stderr, "ERR: Unknown map_type(%u) cannot handle\n",
            map_type);
        return false;
        break;
    }
    rec->total.rx_packets = value.rx_packets;
    rec->total.rx_bytes   = value.rx_bytes;
    return true;
}

void stats_collect(int map_fd, __u32 map_type, struct stats_record *stats_rec)
{
    /* Collect all XDP actions stats  */
    __u32 key;
    for (key = 0; key < XDP_ACTION_MAX; key++) {
        map_collect(map_fd, map_type, key, &stats_rec->stats[key]);
    }
}

/*
kernel:
    #include "xdp_stats.bpf.h"
    xdp_main:
        return xdp_stats_record_action(ctx, action);
user:
    #include "xdp_stats.h"
static void stats_print(struct stats_record *stats_rec, struct stats_record *stats_prev)
{
	struct record *rec, *prev;
	__u64 packets, bytes;
	double period;
	double pps; // packets per sec
	double bps; // bits per sec
	int i;
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
    // Trick to pretty printf with thousands separators use %'
    setlocale(LC_NUMERIC, "en_US");
    // Get initial reading quickly
    stats_collect(map_fd, map_type, &record);
    usleep(1000000/4);
    while (!env.exiting) {
        prev = record;
        stats_collect(map_fd, map_type, &record);
        stats_print(&record, &prev);
        sleep(interval);
    }
}
    stats_poll(bpf_map__fd(skel->maps.xdp_stats_map), BPF_MAP_TYPE_PERCPU_ARRAY, 1);
*/
