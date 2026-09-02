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
#define PIN_PATH      "/sys/fs/bpf/xdp_lb_link"

struct env {
    char ifname[IF_NAMESIZE];
    struct backend_config lb_cfg;
    int persist;
    int verbose;
    volatile bool exiting;
} env = {
    .ifname = { 0 },
    .lb_cfg = { .vip = { 0 }, .num = 0, },
    .persist = 0,
    .verbose = 3,
    .exiting = false,
};
enum { LOG_EMERG=0, LOG_ALERT=1, LOG_CRIT=2, LOG_ERR=3, LOG_WARNING=4, LOG_NOTICE=5, LOG_INFO=6, LOG_DEBUG=7 };
#define log_debug(fmt,args...)  { if(env.verbose>=LOG_DEBUG) fprintf(stderr, "DEBUG %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
#define log_info(fmt,args...)   { if(env.verbose>=LOG_INFO)  fprintf(stderr, "INFO  %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
#define log_error(fmt,args...)  { if(env.verbose>=LOG_ERR)   fprintf(stderr, "ERROR %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
const char *opt_short="hVi:Pv:p:R:";
struct option opt_long[] = {
    { "persist", no_argument, NULL, 'P' },
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
        "    -P|--persist      persistent ebpf when exit\n"
        "    -h|--help help\n"
        "    -V|--verbose\n"
        "Example:\n"
        "  %s -i eth0\n"
        , prog, prog);
    exit(0);
}
const char *ip_str(in_addr_t addr) {
    static __thread char buf[INET_ADDRSTRLEN];
    struct in_addr ip = { .s_addr = addr };
    if (inet_ntop(AF_INET, &ip, buf, sizeof(buf)) == NULL)
        return "<invalid>";
    return buf;
}
void dump_config_map(struct bpf_map *map) {
    struct key lookup_key, next_key;
    struct backend_config value;
    int err;
    fprintf(stderr, "--- Dumping Standard Map Entries ---\n");
    /* Pass NULL to fetch the first key from the kernel. */
    err = bpf_map__get_next_key(map, NULL, &next_key, sizeof(next_key));
    while (err == 0) {
        lookup_key = next_key;
        err = bpf_map__lookup_elem(map, &lookup_key, sizeof(lookup_key), &value, sizeof(value), 0);
        if (err == 0) {
            const unsigned char *mac_addr = value.vip.mac_addr;
            fprintf(stderr, "VIP %s:%d[%02X:%02X:%02X:%02X:%02X:%02X] ->\n", ip_str(value.vip.ip_addr), ntohs(value.vip.port), mac_addr[0], mac_addr[1], mac_addr[2], mac_addr[3], mac_addr[4], mac_addr[5]);
            for (int i=0;i<value.num;i++) {
                mac_addr = value.backends[i].mac_addr;
                fprintf(stderr, "    %s:[%02X:%02X:%02X:%02X:%02X:%02X]\n", ip_str(value.backends[i].ip_addr), mac_addr[0], mac_addr[1], mac_addr[2], mac_addr[3], mac_addr[4], mac_addr[5]);
            }
        } else {
            log_error("Failed lookup for key %d, %d: %s", lookup_key.ip_addr, ntohs(lookup_key.port), strerror(-err));
        }
        err = bpf_map__get_next_key(map, &lookup_key, &next_key, sizeof(next_key));
    }
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
#include <sys/ioctl.h>
#include <ifaddrs.h>
int get_local_mac_by_ip(__be32 target_ip, unsigned char *mac_out) {
    struct ifaddrs *ifaddr;
    int ret = -1;
    // Get all network interfaces
    if (getifaddrs(&ifaddr) == -1) { return -1; }
    for (struct ifaddrs *ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
        if (ifa->ifa_addr == NULL) continue;
        if (ifa->ifa_addr->sa_family != AF_INET) continue;
        struct sockaddr_in *current_addr = (struct sockaddr_in *)ifa->ifa_addr;
        // Check only IPv4 interfaces (AF_INET)
        if (current_addr->sin_addr.s_addr != target_ip) continue;
        struct ifreq request = {0};
        snprintf(request.ifr_name, ARRAY_LEN(request.ifr_name), "%s", ifa->ifa_name);
        log_info("VIP interface: %s", ifa->ifa_name);
        int sock = socket(AF_INET, SOCK_DGRAM, 0);
        if (sock < 0) { ret = -3; break; }
        if (ioctl(sock, SIOCGIFHWADDR, &request) >= 0) { ret = 0; }
        close(sock);
        memcpy(mac_out, request.ifr_hwaddr.sa_data, ETH_ALEN);
    }
    freeifaddrs(ifaddr);
    return ret;
}
static int parse_command_line(int argc, char **argv) {
    int opt, option_index;
    unsigned char *mac_addr;
    while ((opt = getopt_long(argc, argv, opt_short, opt_long, &option_index)) != -1) {
        switch (opt) {
            case 'i':
                snprintf(env.ifname, ARRAY_LEN(env.ifname), "%s", optarg);
                break;
            case 'v':
                env.lb_cfg.vip.ip_addr = inet_addr(optarg);
                mac_addr = env.lb_cfg.vip.mac_addr;
                if (get_local_mac_by_ip(env.lb_cfg.vip.ip_addr, mac_addr) != 0) {
                    log_error("VIP %s can not get MAC address", optarg);
                    exit(0);
                }
                break;
            case 'p':
                env.lb_cfg.vip.port = htons(strtol(optarg, NULL, 10));
                break;
            case 'R':
                if(env.lb_cfg.num >= ARRAY_LEN(env.lb_cfg.backends)) {  usage(argv[0]); }
                in_addr_t addr = inet_addr(optarg);
                mac_addr = env.lb_cfg.backends[env.lb_cfg.num].mac_addr;
                env.lb_cfg.backends[env.lb_cfg.num++].ip_addr = addr;
                if (get_mac_from_arp_cache(addr, mac_addr) != 0) {
                    log_error("Node %u is unreachable retry.", addr);
                    force_kernel_arp_resolution(addr);
                    if (get_mac_from_arp_cache(addr, mac_addr) != 0) {
                        log_error("Node %s [%u] is unreachable.", optarg, addr);
                        exit(0);
                    }
                }
                break;
            case 'P':
                env.persist = 1;
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
        log_error("Failed to load BPF skeleton: %d, %s", err, strerror(errno));
        goto cleanup;
    }
    /* 3. 附加到网卡（libbpf 自动尝试驱动模式，失败则回退到 skb 通用模式） */
    struct bpf_link *link = bpf_link__open(PIN_PATH);
    if (link) {
        log_info("Found an existing pinned XDP link. Reusing it.");
        skel->links.xdp_load_balancer = link;
    } else {
        skel->links.xdp_load_balancer = bpf_program__attach_xdp(skel->progs.xdp_load_balancer, ifindex);
        if (!skel->links.xdp_load_balancer) {
            err = -errno;
            log_error("Failed to attach XDP to %s: %d", env.ifname, err);
            goto cleanup;
        }
        if (env.persist) {
            log_info("Pin the link to the BPF filesystem");
            err = bpf_link__pin(skel->links.xdp_load_balancer, PIN_PATH);
            if (err) {
                log_error("Failed to pin link to %s: %d", PIN_PATH, err);
                goto cleanup;
            }
        }
        // // Standard POSIX unlink removes the pin file from bpffs
        // if (unlink(PIN_PATH) != 0) { log_error("Failed unlink %s", PIN_PATH); }
    }
    log_info("XDP loaded on %s (ifindex=%d)", env.ifname, ifindex);
    /* 4. set  config_map */
    struct key key = { .ip_addr = env.lb_cfg.vip.ip_addr, .port= env.lb_cfg.vip.port };
    err = bpf_map__update_elem(skel->maps.config_map, &key, sizeof(key), &env.lb_cfg, sizeof(env.lb_cfg), BPF_ANY);
    if (err) {
        log_error("set lb config error");
    }
    dump_config_map(skel->maps.config_map);
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
# 抑制 ARP，防止 RS 宣告 VIP
sysctl -w net.ipv4.conf.all.arp_ignore=1
sysctl -w net.ipv4.conf.all.arp_announce=2
sysctl -w net.ipv4.conf.eth0.arp_ignore=1
sysctl -w net.ipv4.conf.eth0.arp_announce=2
# 关闭反向路径过滤，允许 eth0 接收目的IP属于lo的包
sysctl -w net.ipv4.conf.all.rp_filter=0
sysctl -w net.ipv4.conf.eth0.rp_filter=0

# # lb srv
VIP=172.16.16.100/32
ip link add name dummy0 type dummy
ip a a ${VIP} dev dummy0
ip link set dummy0 up
sysctl -w net.ipv4.conf.eth0.proxy_arp=1
sysctl -w net.ipv4.conf.all.proxy_arp=1
# ./loader -i eth0 -v 172.16.16.100 -p 8888 -R 192.168.169.102
*/
