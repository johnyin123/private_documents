#ifndef __LOADER_H_073338_2774427544__INC__
#define __LOADER_H_073338_2774427544__INC__
#ifdef __cplusplus
extern "C" {
#endif
#include <bpf/libbpf.h>
#include <sys/resource.h>
#include <net/if.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif

#ifndef UNUSED
#define UNUSED(x)           ((void)(x))
#endif
#ifndef ARRAY_LEN
#define ARRAY_LEN(a)         (sizeof(a)/sizeof((a)[0]))
#endif

extern const int *log_level;
enum { LOG_EMERG=0, LOG_ALERT=1, LOG_CRIT=2, LOG_ERR=3, LOG_WARNING=4, LOG_NOTICE=5, LOG_INFO=6, LOG_DEBUG=7 };
#define log_debug(fmt,args...)  { if(log_level && *log_level>=LOG_DEBUG) fprintf(stderr, "DEBUG %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
#define log_info(fmt,args...)   { if(log_level && *log_level>=LOG_INFO)  fprintf(stderr, "INFO  %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }
#define log_error(fmt,args...)  { if(log_level && *log_level>=LOG_ERR)   fprintf(stderr, "ERROR %s:%d " fmt "\n", __FILE__, __LINE__, ##args); }

static inline void print_libbpf_ver() {
    log_debug("libbpf: %d.%d", libbpf_major_version(), libbpf_minor_version());
}
static inline int bump_memlock_rlimit() {
    struct rlimit rlim_new = { .rlim_cur = RLIM_INFINITY, .rlim_max = RLIM_INFINITY, };
    return setrlimit(RLIMIT_MEMLOCK, &rlim_new);
}
static inline int libbpf_print_fn(enum libbpf_print_level level, const char *format, va_list args) {
    if (level == LIBBPF_DEBUG && log_level && *log_level<LOG_DEBUG)
        return 0;
    return vfprintf(stderr, format, args);
}
static inline bool add_interface(const char *ifname, unsigned int ifindex[], unsigned int arr_len) {
    for (unsigned int i=0; i<arr_len; i++) {
        if (ifindex[i] != 0) { continue; }
        if ((ifindex[i] = if_nametoindex(ifname)) == 0) {
            /*char ifname[IFNAMSIZ]; if_indextoname(ifindex, ifname)*/
            log_error("invalid interface %s: %s", ifname, strerror(errno));
            return false;
        }
        log_info("add interface %s[%d]", ifname, ifindex[i]);
        return true;
    }
    log_error("Max interface [%u] exceed", arr_len);
    return false;
}
#include <sys/stat.h>
#include <fcntl.h>
static inline struct bpf_link *attach_cgroup(const struct bpf_program *prog, const char *cgroup_dir) {
    int cgroup_fd = open(cgroup_dir, O_RDONLY | O_DIRECTORY);
    if (cgroup_fd >= 0) {
        struct bpf_link *cg_link = bpf_program__attach_cgroup(prog, cgroup_fd);
        close(cgroup_fd);
        if (!cg_link) {
            log_error("bpf_program__attach_cgroup(%s) failed: %s", cgroup_dir, strerror(errno));
        }
        return cg_link;
    }
    log_error("Failed to open and attach cgroup(%s), %s", cgroup_dir, strerror(errno));
    return NULL;
}
static inline struct bpf_link *attach_tc(const struct bpf_program *prog, int ifindex) {
    struct bpf_link *tc_link = bpf_program__attach_tcx(prog, ifindex, NULL);
    if (!tc_link) {
        log_error("bpf_program__attach_tcx(%d) failed: %s", ifindex, strerror(errno));
    }
    return tc_link;
}
#include <arpa/inet.h>
static inline void ip_str_r(in_addr_t addr, char *buf, size_t size) {
    struct in_addr ip = { .s_addr = addr };
    if (inet_ntop(AF_INET, &ip, buf, size) == NULL) {
        snprintf(buf, size, "<invalid>");
    }
}
#ifdef __cplusplus
}
#endif
#endif
