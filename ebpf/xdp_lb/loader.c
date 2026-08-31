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
    char vip[46];
    __u16 vport; 
    char rip[46];
    int verbose;
    volatile bool exiting;
} env = {
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
static int parse_command_line(int argc, char **argv) {
    int opt, option_index;
    while ((opt = getopt_long(argc, argv, opt_short, opt_long, &option_index)) != -1) {
        switch (opt) {
            case 'i':
                snprintf(env.ifname, ARRAY_LEN(env.ifname), "%s", optarg);
                break;
            case 'v':
                snprintf(env.vip, ARRAY_LEN(env.vip), "%s", optarg);
                break;
            case 'p':
                env.vport = strtol(optarg, NULL, 10);
                break;
            case 'R':
                snprintf(env.rip, ARRAY_LEN(env.rip), "%s", optarg);
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
void force_kernel_arp_resolution(__be32 target_ip) {
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) return;
    struct sockaddr_in target = { .sin_family = AF_INET, .sin_port = htons(1), .sin_addr.s_addr = target_ip };
    char dummy = 0;
    sendto(sock, &dummy, 1, 0, (struct sockaddr *)&target, sizeof(target));
    close(sock);
    usleep(5000); 
}
int get_mac_from_arp_cache(__be32 target_ip, unsigned char *mac_out) {
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
#include <sys/ioctl.h>
#include <ifaddrs.h>
int get_local_mac_by_ip(const char *ipaddr, unsigned char *mac_out, char *if_name_out) {
    struct ifaddrs *ifaddr, *ifa;
    int found = 0;
    // 1. Get all network interfaces
    if (getifaddrs(&ifaddr) == -1) { return -1; }
    // 2. Walk through the linked list to find the matching IP
    for (ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
        if (ifa->ifa_addr == NULL) continue;
        // Check only IPv4 interfaces (AF_INET)
        if (ifa->ifa_addr->sa_family == AF_INET) {
            struct sockaddr_in *current_addr = (struct sockaddr_in *)ifa->ifa_addr;
            char *current_ip = inet_ntoa(current_addr->sin_addr);
            // Check if this interface matches our targeted local IP
            if (strcmp(current_ip, ipaddr) == 0) {
                snprintf(if_name_out, IFNAMSIZ, "%s", ifa->ifa_name);
                found = 1;
                break;
            }
        }
    }
    freeifaddrs(ifaddr);
    if (!found) { return -2; }
    // 3. Open a dummy socket to query the MAC address via ioctl
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) { return -3; }
    struct ifreq request = {0};
    snprintf(request.ifr_name, sizeof(request.ifr_name), "%s", if_name_out);
    // Fetch the hardware (MAC) address
    if (ioctl(sock, SIOCGIFHWADDR, &request) < 0) {
        close(sock);
        return -4;
    }
    close(sock);
    // 4. Copy the 6-byte MAC address into our buffer
    memcpy(mac_out, request.ifr_hwaddr.sa_data, 6);
    return 0;
}

int main(int argc, char *argv[]) {
    struct bpf_link *link = NULL;
    parse_command_line(argc, argv);
    if ((strlen(env.ifname) == 0) || (strlen(env.vip) == 0) || (strlen(env.rip) == 0) || (!env.vport)) {
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
    link = bpf_program__attach_xdp(skel->progs.xdp_load_balancer, ifindex);
    if (!link) {
        err = -errno;
        log_error("Failed to attach XDP to %s: %d", env.ifname, err);
        goto cleanup;
    }
    log_info("XDP loaded on %s (ifindex=%d)", env.ifname, ifindex);
    /* 4. set  config_map */
    struct backend_config lb_cfg = {
        .vip = { .ip_addr = inet_addr(env.vip), .port = htons(env.vport), .mac_addr = {0} },
        .num = 1,
        .backends = {
            { .ip_addr = inet_addr(env.rip), },
        }
    };
    for (int i=0;i<lb_cfg.num;i++) {
        if (get_mac_from_arp_cache(lb_cfg.backends[i].ip_addr, lb_cfg.backends[i].mac_addr) == 0) {
            log_info("MAC %u: %02X:%02X:%02X:%02X:%02X:%02X", lb_cfg.backends[i].ip_addr, lb_cfg.backends[i].mac_addr[0], lb_cfg.backends[i].mac_addr[1], lb_cfg.backends[i].mac_addr[2], lb_cfg.backends[i].mac_addr[3], lb_cfg.backends[i].mac_addr[4], lb_cfg.backends[i].mac_addr[5]);
        } else {
            log_error("Node %u is unreachable retry.", lb_cfg.backends[i].ip_addr);
            force_kernel_arp_resolution(lb_cfg.backends[i].ip_addr);
            if (get_mac_from_arp_cache(lb_cfg.backends[i].ip_addr, lb_cfg.backends[i].mac_addr) == 0) {
                log_info("MAC %u: %02X:%02X:%02X:%02X:%02X:%02X", lb_cfg.backends[i].ip_addr, lb_cfg.backends[i].mac_addr[0], lb_cfg.backends[i].mac_addr[1], lb_cfg.backends[i].mac_addr[2], lb_cfg.backends[i].mac_addr[3], lb_cfg.backends[i].mac_addr[4], lb_cfg.backends[i].mac_addr[5]);
            }
        }
    }
    struct key key = { .ip_addr = lb_cfg.vip.ip_addr, .port= lb_cfg.vip.port };
    err = bpf_map__update_elem(skel->maps.config_map, &key, sizeof(key), &lb_cfg, sizeof(lb_cfg), BPF_ANY);
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
    if (link)
        bpf_link__destroy(link);   /* detach XDP */
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
