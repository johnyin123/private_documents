#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("initver[2026-10-08T08:19:32+08:00]:gen_bpf.sh")
################################################################################
FILTER_CMD="cat"
LOGFILE=
################################################################################
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
gen_loader() {
    local cg_bpf_func=${1}
    local bpf2_func=${2}
    local ringbuf_name=${3}
    log "loader.c ..........."
    cat <<EOF
#include <getopt.h>
#include <stdlib.h>
#include <signal.h>
#include "bpf_skel.h"
#include "type_def.h"
#include "loader.h"

struct env {
    int verbose;
    volatile bool exiting;
} env = {
    .verbose = LOG_ERR,
    .exiting = false,
};
const int *log_level = &env.verbose;
const char *opt_short="hV";
struct option opt_long[] = {
    { "help",    no_argument, NULL, 'h' },
    { "verbose", no_argument, NULL, 'V' },
    { 0, 0, 0, 0 }
};
static void usage(const char *prog) {
    fprintf(stderr,
        "Usage: %s\n"
        "    -h|--help help\n"
        "    -V|--verbose\n"
        , prog);
    exit(0);
}
static int parse_command_line(int argc, char **argv) {
    int opt, option_index;
    while ((opt = getopt_long(argc, argv, opt_short, opt_long, &option_index)) != -1) {
        switch (opt) {
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
static int handle_ringbuf_ev(void *ctx, void *data, size_t data_sz) {
    UNUSED(ctx);
    if (data_sz < sizeof(struct raw_event)) { return 0; }
    struct raw_event *e = data;
    hexdump(stderr, e, sizeof(*e));
    return 0;
}
int main(int argc, char *argv[]) {
    parse_command_line(argc, argv);
    signal(SIGINT, sig_int);
    signal(SIGTERM, sig_int);
    /* Set up libbpf errors and debug info callback */
    if (env.verbose>=LOG_DEBUG) { print_libbpf_ver(); libbpf_set_print(libbpf_print_fn); }
    else { libbpf_set_print(NULL); }
    if (bump_memlock_rlimit()) { log_error("Failed setrlimit: %d, %s", errno, strerror(errno)); return 1; }
    /* 1. 打开 skeleton */
    struct ring_buffer *rb = NULL;
    struct bpf_skel *skel = bpf_skel__open();
    if (!skel) {
        log_error("Failed to open BPF skeleton");
        return 1;
    }
    /* 2. 加载到内核 */
    int err = bpf_skel__load(skel);
    if (err) {
        log_error("Failed to load BPF skeleton: %d, %s", err, strerror(errno));
        goto cleanup;
    }
    /* 3. Attach */
    skel->links.${bpf2_func} = bpf_program__attach(skel->progs.${bpf2_func});
    if (!skel->links.${bpf2_func}) {
        log_error("Failed to attach bpf: %s", strerror(errno));
        goto cleanup;
    }
    if (!(skel->links.${cg_bpf_func} = attach_cgroup(skel->progs.${cg_bpf_func}, "/sys/fs/cgroup"))) { goto cleanup; }
    /* 4. ringbuffer*/
    if (!(rb = ring_buffer__new(bpf_map__fd(skel->maps.${ringbuf_name}), handle_ringbuf_ev, NULL, NULL))) {
        log_error("Failed to create ring buffer");
        goto cleanup;
    }
    /* 5. 保持运行，信号触发退出 */
    fprintf(stderr, "Press Ctrl+C to stop and detach...\n");
    while (!env.exiting) {
        err = ring_buffer__poll(rb, 100 /* timeout ms */);
        if (err < 0 && err != -EINTR) {
            log_error("Error polling ring buffer: %d", err);
            break;
        }
    }
    log_info("Detaching bpf program...");
cleanup:
    if (rb) { ring_buffer__free(rb); }
    bpf_skel__destroy(skel);
    return err < 0 ? 1 : 0;
}
EOF
}
gen_inc() {
    local uuid=$(cat /proc/sys/kernel/random/uuid | tr '-' '_')
    log "type_def.h ..........."
    cat <<EOF
#ifndef __TYPE_DEF_H_${uuid}_INC__
#define __TYPE_DEF_H_${uuid}_INC__
#ifdef __cplusplus
extern "C" {
#endif

#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif

struct raw_event {
    __u32 id;
};

#ifdef __cplusplus
}
#endif
#endif
EOF
}
gen_bpf_inc() {
    local uuid=$(cat /proc/sys/kernel/random/uuid | tr '-' '_')
    log "type_def.bpf.h ..........."
    cat <<EOF
#ifndef __TYPE_DEF_BPF_H_${uuid}_INC__
#define __TYPE_DEF_BPF_H_${uuid}_INC__
#ifdef __cplusplus
extern "C" {
#endif

#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif

#ifdef DEBUG
#define bpf_debug(fmt, ...) bpf_printk("DEBUG: " fmt, ##__VA_ARGS__)
#else
#define bpf_debug(fmt, ...) do { } while (0)
#endif

#ifndef UNUSED
#define UNUSED(x)           ((void)(x))
#endif
#ifndef ARRAY_LEN
#define ARRAY_LEN(a)        (sizeof(a)/sizeof((a)[0]))
#endif
#include "type_def.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_tracing.h>
#include <bpf/bpf_endian.h>

struct info {
    int id;
};
struct ssmap {
    __uint(type, BPF_MAP_TYPE_LRU_HASH);
    __uint(max_entries, 65536);
    __type(key, __u64);
    __type(value, struct info);
};
struct event_ring {
    __uint(type, BPF_MAP_TYPE_RINGBUF);
    __uint(max_entries, 1 << 16);
};

#ifdef __cplusplus
}
#endif
#endif
EOF
}
gen_bpf2() {
    local func_name=${1}
    local ringbuf_name=${2}
    log "demo_trace.bpf.c ..........."
    cat <<EOF
#include "vmlinux.h"
#include "type_def.bpf.h"
char LICENSE[] SEC("license") = "GPL";

#ifndef AF_INET
#define AF_INET      2   /* Internet IP Protocol */
#endif

extern struct event_ring ${ringbuf_name};
extern struct ssmap cookie_dump;
SEC("tp_btf/inet_sock_set_state") int BPF_PROG(${func_name}, struct sock *sk, int oldstate, int newstate) {
    UNUSED(ctx);UNUSED(oldstate);UNUSED(newstate);
    __u16 family = BPF_CORE_READ(sk, __sk_common.skc_family);
    if (family != AF_INET) { return 0; }
    __u8 protocol = BPF_CORE_READ(sk, sk_protocol);
    if (protocol != IPPROTO_TCP) { return 0; }
    __u64 cookie = bpf_get_socket_cookie(sk);
    if (!cookie) { return 0; }
    struct info *pinfo = bpf_map_lookup_elem(&cookie_dump, &cookie);
    if (!pinfo) { return 0; }
    bpf_debug("cookie = %llu, infoid = %d", cookie, pinfo->id);
    bpf_map_delete_elem(&cookie_dump, &cookie);
    return 0;
}
EOF
}
gen_bpf1() {
    local func_name=${1}
    local ringbuf_name=${2}
    log "demo_xdp.bpf.c ..........."
    cat <<EOF
#include "xdp_parse.h"
#include "type_def.bpf.h"
char LICENSE[] SEC("license") = "GPL";

struct event_ring ${ringbuf_name} SEC(".maps");
struct ssmap cookie_dump SEC(".maps");

SEC("cgroup_skb/egress") int ${func_name}(struct __sk_buff *skb) {
    void *data = (void *)(long)skb->data;
    void *data_end = (void *)(long)skb->data_end;
    struct hdr_cursor nh = { .pos = data };
    if (skb->protocol != __bpf_constant_htons(ETH_P_IP)) { return 1; }
    struct iphdr *iphdr = NULL;
    if (parse_iphdr(&nh, data_end, &iphdr) < 0) { return 1; }
    if ((iphdr->protocol != IPPROTO_UDP) && (iphdr->protocol != IPPROTO_TCP)) { return 1; }

    struct raw_event *e = bpf_ringbuf_reserve(&${ringbuf_name}, sizeof(*e), 0);
    if (!e) { return 1; }
    e->id = 1;
    __u64 cookie = bpf_get_socket_cookie(skb);
    if (!cookie) { bpf_ringbuf_discard(e, 0); return 1; }
    struct info info = { .id=1, };
    bpf_map_update_elem(&cookie_dump, &cookie, &info, BPF_ANY);
    bpf_ringbuf_submit(e, 0);
    return 1;
}
EOF
}
main() {
    local opt_short=""
    local opt_long=""
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            ########################################
            -q | --quiet)   shift; FILTER_CMD=;;
            -l | --log)     shift; LOGFILE=${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    exec > >(${FILTER_CMD:-sed '/^\s*#/d'} | tee ${LOGFILE:+-i ${LOGFILE}})
    local out_ringbuf="myrb"
    local func1="mybpf_cg1"
    local func2="mybpf_tpbtf"
    gen_loader "${func1}" "${func2}" "${out_ringbuf}"
    gen_bpf1 "${func1}" "${out_ringbuf}"
    gen_bpf2 "${func2}" "${out_ringbuf}"
    gen_inc
    gen_bpf_inc
    return 0
}
main "$@"
