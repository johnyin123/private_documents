#include <stdio.h>
#include <getopt.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/resource.h>

#include <net/if.h>
#include <arpa/inet.h>
#include <linux/if_link.h>

#include <bpf/libbpf.h>
#include "xdp_lb_skel.h"
#include "xdp_lb.h"

#define UNUSED(x)     ((void)(x))
#define ARRAY_LEN(a)  (sizeof(a)/sizeof((a)[0]))

struct env {
    char ifname[IF_NAMESIZE];
    struct backend_config lb_cfg;
    int verbose;
    volatile bool exiting;
} env = {
    .ifname = { 0 },
    .lb_cfg = { .vip = { 0 }, .num = 0, },
    .verbose = 3,
    .exiting = false,
};
enum { LOG_EMERG=0, LOG_ALERT=1, LOG_CRIT=2, LOG_ERR=3, LOG_WARNING=4, LOG_NOTICE=5, LOG_INFO=6, LOG_DEBUG=7 };
#define log_debug(fmt,args...)  { if(env.verbose>=LOG_DEBUG) fprintf(stderr, "DEBUG %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
#define log_info(fmt,args...)   { if(env.verbose>=LOG_INFO)  fprintf(stderr, "INFO  %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
#define log_error(fmt,args...)  { if(env.verbose>=LOG_ERR)   fprintf(stderr, "ERROR %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
const char *opt_short="hVi:v:p:R:";
struct option opt_long[] = {
    { "help",    no_argument, NULL, 'h' },
    { "verbose", no_argument, NULL, 'V' },
    { 0, 0, 0, 0 }
};
static void usage(const char *prog) {
    fprintf(stderr,
        "Usage: %s\n"
        "    -i  * <ifname>    attach network device name\n"
        "    -v  * <ip>        virtual ipaddr\n"
        "    -p  * <port>      virtual port\n"
        "    -R  * <ip>        real srv ipaddr\n"
        "    -h|--help help\n"
        "    -V|--verbose\n"
        "Example:\n"
        "  %s -i eth0\n"
        , prog, prog);
    exit(0);
}
static int get_mac_from_arp_cache(__be32 target_ip, unsigned char *mac_out) {
    FILE *fp = fopen("/proc/net/arp", "r");
    if (!fp) {
        log_error("Error: Cannot open /proc/net/arp");
        return -1;
    }
    char line[256], ip_str[64], hw_type[16], flags[16], mac_str[32], mask[16], device[16];
    struct in_addr addr = { .s_addr = target_ip };
    char *target_ip_str = inet_ntoa(addr);
    if (fgets(line, sizeof(line), fp) == NULL) { goto cleanup; }
    while (fgets(line, sizeof(line), fp)) {
        if (sscanf(line, "%63s %15s %15s %31s %15s %15s", ip_str, hw_type, flags, mac_str, mask, device) == 6) {
            if (strcmp(ip_str, target_ip_str) == 0) {
                if (strcmp(flags, "0x0") == 0) {
                    log_error("Warning: ARP entry for %s exists but is incomplete (0x0).", ip_str);
                    break;
                }
                int m[6];
                if (sscanf(mac_str, "%x:%x:%x:%x:%x:%x", &m[0], &m[1], &m[2], &m[3], &m[4], &m[5]) == 6) {
                    for (int i = 0; i < ETH_ALEN; i++) { mac_out[i] = (unsigned char)m[i]; }
                    fclose(fp);
                    return 0;
                }
            }
        }
    }
cleanup:
    fclose(fp);
    return -1;
}
static void force_kernel_arp_resolution(__be32 target_ip) {
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) return;
    struct sockaddr_in target = { .sin_family = AF_INET, .sin_port = htons(1), .sin_addr.s_addr = target_ip };
    char dummy = 0;
    sendto(sock, &dummy, 1, 0, (struct sockaddr *)&target, sizeof(target));
    close(sock);
    usleep(5000);
}
static int parse_command_line(int argc, char **argv) {
    int opt, option_index;
    while ((opt = getopt_long(argc, argv, opt_short, opt_long, &option_index)) != -1) {
        switch (opt) {
            case 'i':
                snprintf(env.ifname, ARRAY_LEN(env.ifname), "%s", optarg);
                break;
            case 'v':
                env.lb_cfg.vip.ip_addr = inet_addr(optarg);
                break;
            case 'p':
                env.lb_cfg.vip.port = htons(strtol(optarg, NULL, 10));
                break;
            case 'R':
                if(env.lb_cfg.num >= ARRAY_LEN(env.lb_cfg.backends)) {  usage(argv[0]); }
                in_addr_t addr = inet_addr(optarg);
                unsigned char *mac_addr = env.lb_cfg.backends[env.lb_cfg.num].mac_addr;
                env.lb_cfg.backends[env.lb_cfg.num++].ip_addr = addr;
                if (get_mac_from_arp_cache(addr, mac_addr) == 0) {
                    log_debug("MAC %u: %02X:%02X:%02X:%02X:%02X:%02X", addr, mac_addr[0], mac_addr[1], mac_addr[2], mac_addr[3], mac_addr[4], mac_addr[5]);
                } else {
                    log_error("Node %u is unreachable retry.", addr);
                    force_kernel_arp_resolution(addr);
                    if (get_mac_from_arp_cache(addr, mac_addr) == 0) {
                        log_debug("MAC %u: %02X:%02X:%02X:%02X:%02X:%02X", addr, mac_addr[0], mac_addr[1], mac_addr[2], mac_addr[3], mac_addr[4], mac_addr[5]);
                    } else {
                        struct in_addr ip_struct = { .s_addr = addr };
                        log_error("Node %s [%u] is unreachable.", inet_ntoa(ip_struct), addr);
                        exit(0);
                    }
                }
                break;
            case 'h':
                usage(argv[0]);
                break;
            case 'V':
                env.verbose++;
                break;
            default:
                usage(argv[0]);
        }
    }
    return 0;
}
static void sig_int(int signo) {
    UNUSED(signo);
    env.exiting = true;
}
static void print_libbpf_ver() { 
    log_debug("libbpf: %d.%d", libbpf_major_version(), libbpf_minor_version()); 
}
static int bump_memlock_rlimit() {
    struct rlimit rlim_new = { .rlim_cur = RLIM_INFINITY, .rlim_max = RLIM_INFINITY, };
    return setrlimit(RLIMIT_MEMLOCK, &rlim_new);
}
static int libbpf_print_fn(enum libbpf_print_level level, const char *format, va_list args) {
    if (level == LIBBPF_DEBUG && env.verbose<LOG_DEBUG)
        return 0;
    return vfprintf(stderr, format, args);
}
int main(int argc, char *argv[]) {
    parse_command_line(argc, argv);
    if ((strlen(env.ifname) == 0) || (env.lb_cfg.vip.ip_addr == 0) || (env.lb_cfg.backends[0].ip_addr == 0) || (!env.lb_cfg.vip.port)) {
        log_error("required args");
        usage(argv[0]);
    }
    signal(SIGINT, sig_int);
    signal(SIGTERM, sig_int);
    print_libbpf_ver();
    /* Set up libbpf errors and debug info callback */
    if (env.verbose>=LOG_DEBUG) { libbpf_set_print(libbpf_print_fn); }
    else { libbpf_set_print(NULL); }
    bump_memlock_rlimit();
    int ifindex = if_nametoindex(env.ifname);
    if (ifindex == 0) {
        log_error("invalid interface %s: %s", env.ifname, strerror(errno));
        return 1;
    }
    /* 1. 打开 skeleton */
    struct xdp_lb *skel = xdp_lb__open();
    if (!skel) {
        log_error("Failed to open BPF skeleton");
        return 1;
    }
    /* 2. 加载到内核 */
    int err = xdp_lb__load(skel);
    if (err) {
        log_error("Failed to load BPF skeleton: %d", err);
        goto cleanup;
    }
    /* 3. 附加到网卡（libbpf 自动尝试驱动模式，失败则回退到 skb 通用模式） */
    skel->links.xdp_load_balancer = bpf_program__attach_xdp(skel->progs.xdp_load_balancer, ifindex);
    if (!skel->links.xdp_load_balancer) {
        err = -errno;
        log_error("Failed to attach XDP to %s: %d", env.ifname, err);
        goto cleanup;
    }
    log_info("XDP loaded on %s (ifindex=%d)", env.ifname, ifindex);
    /* 4. set  config_map */
    struct key key = { .ip_addr = env.lb_cfg.vip.ip_addr, .port= env.lb_cfg.vip.port };
    err = bpf_map__update_elem(skel->maps.config_map, &key, sizeof(key), &env.lb_cfg, sizeof(env.lb_cfg), BPF_ANY);
    if (err) {
        log_error("set lb config error");
    }
    fprintf(stderr, "%d,%d\n", key.ip_addr, key.port);
    /* 5. 保持运行，信号触发退出 */
    fprintf(stderr, "Press Ctrl+C to stop and detach...\n");
    while (!env.exiting) {
        sleep(1);
    }
    log_info("Detaching XDP program...");
cleanup:
    xdp_lb__destroy(skel);
    return err < 0 ? 1 : 0;
}
/*
# real srv
VIP=172.16.16.100/32
ip link add name dummy0 type dummy
ip a a ${VIP} dev dummy0
ip link set dummy0 up
sysctl -w net.ipv4.conf.all.arp_ignore=1
sysctl -w net.ipv4.conf.eth0.arp_ignore=1
sysctl -w net.ipv4.conf.all.arp_announce=2
sysctl -w net.ipv4.conf.eth0.arp_announce=2

# # lb srv
VIP=172.16.16.100/32
ip link add name dummy0 type dummy
ip a a ${VIP} dev dummy0
ip link set dummy0 up
sysctl -w net.ipv4.conf.eth0.proxy_arp=1
sysctl -w net.ipv4.conf.all.proxy_arp=1
# ./loader -i eth0 -v 172.16.16.100 -p 8888 -R 192.168.169.102
*/
